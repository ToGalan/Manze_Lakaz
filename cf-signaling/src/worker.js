// Cloudflare Worker + Durable Object signaling server for Tube (WebRTC
// session bootstrap over a WebTorrent-tracker-shaped protocol). Speaks only
// the subset of that protocol addons/tube/tube_tracker.gd actually sends
// and expects -- not the full BitTorrent tracker spec. See ../README.md
// for the message shapes and the architecture note explaining why every
// connection lands on a single Durable Object instance instead of one per
// info_hash.

const ANNOUNCE_INTERVAL_SECONDS = 90; // comfortably under tube_tracker.gd's own 120s MAX_INTERVAL clamp
const STALE_MS = 5 * 60 * 1000; // ~3 missed re-announces at the interval above
const SWEEP_INTERVAL_MS = 2 * 60 * 1000;
const ROSTER_PREFIX = "peer:";

export class SignalingHub {
	constructor(ctx, env) {
		this.ctx = ctx;
		this.env = env;
	}

	async fetch(request) {
		if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
			return new Response("expected websocket upgrade", { status: 426 });
		}

		const pair = new WebSocketPair();
		const [client, server] = Object.values(pair);
		// ctx.acceptWebSocket (Hibernation API), not server.accept() -- lets
		// this connection sit open at zero cost while idle, and survive the
		// Durable Object itself being evicted/reloaded between messages. No
		// tags: peer_id isn't known until the first message arrives (Tube
		// connects to a fixed, session-agnostic URL -- see the README), so
		// there's nothing to tag with yet at accept time.
		this.ctx.acceptWebSocket(server);

		return new Response(null, { status: 101, webSocket: client });
	}

	// --- Hibernatable WebSocket event handlers ---------------------------
	// Nothing here may depend on any plain instance field (e.g. `this.peers`)
	// set by a previous message: hibernation can evict this object's JS
	// state between any two events on the same socket. Routing state always
	// comes fresh from ctx.getWebSockets()/ws.deserializeAttachment()
	// (survives hibernation by design); durable facts (peer roster,
	// last-seen times) always come from ctx.storage.

	async webSocketMessage(ws, message) {
		const data = parseMessage(message);
		if (!data || data.action !== "announce") return;
		if (typeof data.info_hash !== "string" || typeof data.peer_id !== "string") return;

		if (data.answer && typeof data.to_peer_id === "string") {
			this._relayAnswer(data);
			return;
		}

		if (data.event === "stopped") {
			await this._deregister(data.info_hash, data.peer_id);
			// Also clear the attachment on the reporting socket itself, not
			// just the storage entry: _findSocket() (what relay delivery
			// actually uses to pick a target) reads live attachments, not
			// storage -- Tube always closes the socket right after sending
			// "stopped" so this rarely matters in practice, but without it a
			// still-open-a-moment-longer socket would keep looking like a
			// valid relay target even though it just announced it's leaving.
			ws.serializeAttachment(null);
			return;
		}

		await this._register(ws, data.info_hash, data.peer_id);
		ws.send(JSON.stringify({
			action: "announce",
			info_hash: data.info_hash,
			interval: ANNOUNCE_INTERVAL_SECONDS,
		}));
	}

	async webSocketClose(ws) {
		await this._forgetSocket(ws);
	}

	async webSocketError(ws) {
		await this._forgetSocket(ws);
	}

	// Storage-backed expiry sweep: catches peers whose socket died without a
	// clean close/stop (crash, network drop) so their roster entry doesn't
	// linger forever. Self-cancelling -- only reschedules itself while at
	// least one peer is still on the roster, so a fully abandoned Worker
	// (no sessions at all) goes back to costing nothing rather than waking
	// up forever.
	async alarm() {
		const all = await this.ctx.storage.list({ prefix: ROSTER_PREFIX });
		const now = Date.now();
		let remaining = 0;

		for (const [key, entry] of all) {
			if (now - entry.lastSeen > STALE_MS) {
				await this.ctx.storage.delete(key);
				const staleSocket = this._findSocket(entry.infoHash, entry.peerId);
				if (staleSocket) {
					try {
						staleSocket.close(4000, "stale");
					} catch {
						// already closing/closed -- fine, nothing to clean up
					}
				}
			} else {
				remaining++;
			}
		}

		if (remaining > 0) {
			await this.ctx.storage.setAlarm(Date.now() + SWEEP_INTERVAL_MS);
		}
	}

	// --- internals ---------------------------------------------------------

	async _register(ws, infoHash, peerId) {
		// A stale/duplicate socket from a previous connection attempt for the
		// same (infoHash, peerId) shouldn't linger and race the new one for
		// relay delivery -- close it if one's still around.
		const existing = this._findSocket(infoHash, peerId);
		if (existing && existing !== ws) {
			try {
				existing.close(4000, "superseded");
			} catch {
				// ignore
			}
		}

		ws.serializeAttachment({ infoHash, peerId });
		await this.ctx.storage.put(rosterKey(infoHash, peerId), {
			infoHash,
			peerId,
			lastSeen: Date.now(),
		});

		if ((await this.ctx.storage.getAlarm()) === null) {
			await this.ctx.storage.setAlarm(Date.now() + SWEEP_INTERVAL_MS);
		}
	}

	async _deregister(infoHash, peerId) {
		await this.ctx.storage.delete(rosterKey(infoHash, peerId));
	}

	async _forgetSocket(ws) {
		const attachment = safeAttachment(ws);
		if (attachment) {
			await this._deregister(attachment.infoHash, attachment.peerId);
		}
	}

	// Relays an offer or answer (indistinguishable at this layer -- both are
	// carried the same way, with the embedded SDP's own "type" field saying
	// which) to whichever currently-connected socket is registered as
	// to_peer_id within the SAME info_hash. Scoping every lookup by
	// (infoHash, peerId) together, never peerId alone, is what makes a
	// cross-session collision structurally impossible even though every
	// session's sockets are held by this one Durable Object instance -- see
	// the README's architecture note for why that's necessary here.
	_relayAnswer(data) {
		const target = this._findSocket(data.info_hash, data.to_peer_id);
		if (!target) return; // not connected (yet, or gone) -- drop; the sender's own peer-connection retry/timeout handles this

		target.send(JSON.stringify({
			action: "announce",
			info_hash: data.info_hash,
			peer_id: data.peer_id,
			answer: data.answer,
			offer_id: data.offer_id ?? "0",
		}));
	}

	_findSocket(infoHash, peerId) {
		// A plain scan, not a Map kept on `this`: in-memory fields don't
		// survive hibernation, and ctx.getWebSockets() is the one source of
		// live sockets that's guaranteed current regardless of whether this
		// object was just woken up. Fine at this project's traffic (a
		// handful of concurrent card-game sessions, not a public tracker).
		for (const ws of this.ctx.getWebSockets()) {
			const attachment = safeAttachment(ws);
			if (attachment && attachment.infoHash === infoHash && attachment.peerId === peerId) {
				return ws;
			}
		}
		return null;
	}
}

// Space-separated, not ":" -- app_id's own character set (see
// tube_context.gd's _APP_ID_CHARACTER_SET) includes ":", so info_hash
// (app_id + session_id) can legitimately contain one. Neither app_id's nor
// session_id's character set includes a space, and peer_id is always
// digits only, so a space is actually a safe delimiter here -- though it
// never needs parsing back apart anyway, since infoHash/peerId are stored
// again in the value itself; the key only has to be unique per pair.
function rosterKey(infoHash, peerId) {
	return `${ROSTER_PREFIX}${infoHash} ${peerId}`;
}

function safeAttachment(ws) {
	try {
		return ws.deserializeAttachment();
	} catch {
		return null;
	}
}

function parseMessage(message) {
	try {
		const text = typeof message === "string" ? message : new TextDecoder().decode(message);
		const data = JSON.parse(text);
		return typeof data === "object" && data !== null ? data : null;
	} catch {
		return null;
	}
}

export default {
	async fetch(request, env) {
		if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
			return new Response("manze lakaz signaling: ok\n", { status: 200 });
		}

		// Every connection, regardless of which game session it's for, lands
		// on this one fixed Durable Object instance -- see the README's
		// architecture note for why info_hash (which is what would normally
		// pick the DO via idFromName) isn't available yet at this point, and
		// why that's still safe.
		const id = env.HUB.idFromName("hub");
		const stub = env.HUB.get(id);
		return stub.fetch(request);
	},
};

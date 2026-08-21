// Drives the protocol described in ../README.md against a running
// `npm run dev` instance. Not self-starting -- run `npm run dev` in one
// terminal first, then `npm test` in another.

import WebSocket from "ws";

const URL = "ws://127.0.0.1:8787/";

function connect(label) {
	return new Promise((resolve, reject) => {
		const ws = new WebSocket(URL);
		ws.on("open", () => resolve(ws));
		ws.on("error", reject);
		ws.on("message", (data) => {
			console.log(`[${label}] recv:`, data.toString());
		});
	});
}

function send(ws, label, obj) {
	console.log(`[${label}] send:`, JSON.stringify(obj));
	ws.send(JSON.stringify(obj));
}

function waitForMessage(ws, predicate, timeoutMs = 3000) {
	return new Promise((resolve, reject) => {
		const timer = setTimeout(() => reject(new Error("timeout waiting for message")), timeoutMs);
		ws.on("message", function handler(data) {
			const parsed = JSON.parse(data.toString());
			if (predicate(parsed)) {
				clearTimeout(timer);
				ws.removeListener("message", handler);
				resolve(parsed);
			}
		});
	});
}

const INFO_HASH_A = "AAAAAAAAAAAAAAAAAAA1"; // 20 chars, session A
const INFO_HASH_B = "BBBBBBBBBBBBBBBBBBB1"; // 20 chars, session B (different session, same peer_id numbers, to prove no cross-session collision)
const HOST_PEER = "00000000000000000001";
const JOIN_PEER = "00000000000000000002";

async function main() {
	// --- Test 1: basic announce gets an interval back -----------------------
	const host = await connect("hostA");
	const announceReply = waitForMessage(host, (m) => typeof m.interval === "number");
	send(host, "hostA", { action: "announce", info_hash: INFO_HASH_A, peer_id: HOST_PEER, uploaded: 0, downloaded: 0 });
	const reply = await announceReply;
	console.assert(reply.info_hash === INFO_HASH_A, "announce reply should echo info_hash");
	console.log("PASS: announce reply has interval:", reply.interval);

	// --- Test 2: offer/answer relay works between two peers in session A ----
	const joinA = await connect("joinA");
	send(joinA, "joinA", { action: "announce", info_hash: INFO_HASH_A, peer_id: JOIN_PEER, uploaded: 0, downloaded: 0 });
	await waitForMessage(joinA, (m) => typeof m.interval === "number");

	const offerReceived = waitForMessage(host, (m) => m.answer && m.answer.type === "offer");
	send(joinA, "joinA", {
		action: "announce",
		info_hash: INFO_HASH_A,
		peer_id: JOIN_PEER,
		to_peer_id: HOST_PEER,
		answer: { type: "offer", sdp: "fake-offer-sdp-A", ice_candidates: [] },
		offer_id: "0",
	});
	const relayedOffer = await offerReceived;
	console.assert(relayedOffer.peer_id === JOIN_PEER, "relayed offer should carry sender's peer_id");
	console.log("PASS: offer relayed host<-join with correct sender peer_id");

	const answerReceived = waitForMessage(joinA, (m) => m.answer && m.answer.type === "answer");
	send(host, "hostA", {
		action: "announce",
		info_hash: INFO_HASH_A,
		peer_id: HOST_PEER,
		to_peer_id: JOIN_PEER,
		answer: { type: "answer", sdp: "fake-answer-sdp-A", ice_candidates: [] },
		offer_id: "0",
	});
	const relayedAnswer = await answerReceived;
	console.assert(relayedAnswer.peer_id === HOST_PEER, "relayed answer should carry sender's peer_id");
	console.log("PASS: answer relayed join<-host with correct sender peer_id");

	// --- Test 3: cross-session collision -- session B's peer 1/2 must NOT --
	// -- receive anything meant for session A's peer 1/2, even though the ---
	// -- peer_id numbers are identical. -------------------------------------
	const hostB = await connect("hostB");
	send(hostB, "hostB", { action: "announce", info_hash: INFO_HASH_B, peer_id: HOST_PEER, uploaded: 0, downloaded: 0 });
	await waitForMessage(hostB, (m) => typeof m.interval === "number");

	let hostBGotLeak = false;
	hostB.on("message", (data) => {
		const parsed = JSON.parse(data.toString());
		if (parsed.answer) hostBGotLeak = true;
	});

	// Session A's joiner sends another offer; hostB (same peer_id=1, DIFFERENT
	// info_hash) must not see it.
	send(joinA, "joinA", {
		action: "announce",
		info_hash: INFO_HASH_A,
		peer_id: JOIN_PEER,
		to_peer_id: HOST_PEER,
		answer: { type: "offer", sdp: "fake-offer-sdp-A-2", ice_candidates: [] },
		offer_id: "0",
	});
	await new Promise((r) => setTimeout(r, 500));
	console.assert(!hostBGotLeak, "session B must not receive session A's relayed offer");
	console.log(hostBGotLeak ? "FAIL: cross-session leak detected!" : "PASS: no cross-session leak");

	// --- Test 4: stop is silent (no reply) ----------------------------------
	let joinAGotReplyToStop = false;
	joinA.on("message", () => { joinAGotReplyToStop = true; });
	send(joinA, "joinA", { action: "announce", info_hash: INFO_HASH_A, peer_id: JOIN_PEER, event: "stopped" });
	await new Promise((r) => setTimeout(r, 500));
	console.log(joinAGotReplyToStop ? "FAIL: got a reply to stop" : "PASS: no reply to stop, as expected");

	// --- Test 5: relaying to a peer that stopped/never existed is a silent -
	// -- no-op: dropped, not delivered, not an error -------------------------
	let joinAGotPostStopMessage = false;
	joinA.on("message", () => { joinAGotPostStopMessage = true; });
	send(host, "hostA", {
		action: "announce",
		info_hash: INFO_HASH_A,
		peer_id: HOST_PEER,
		to_peer_id: JOIN_PEER, // just stopped in test 4
		answer: { type: "answer", sdp: "should-be-dropped", ice_candidates: [] },
		offer_id: "0",
	});
	await new Promise((r) => setTimeout(r, 500));
	console.log(joinAGotPostStopMessage ? "FAIL: relay delivered to a stopped peer" : "PASS: relay to a stopped peer was dropped");

	console.log("ALL_TESTS_DONE");
	host.close();
	joinA.close();
	hostB.close();
	process.exit(0);
}

main().catch((err) => {
	console.error("TEST SCRIPT ERROR:", err);
	process.exit(1);
});

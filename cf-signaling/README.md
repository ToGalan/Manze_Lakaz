# Manze Lakaz signaling (Cloudflare Worker + Durable Object)

A second, always-on signaling backend for Tube (WebRTC session bootstrap),
alongside `tracker-server/` rather than replacing it -- see the Rollout
note below. Existing for one reason: `tracker-server/` on Render's free
tier sleeps after inactivity and can take tens of seconds to wake back up,
and Tube's `create_session()` hard-fails if no tracker is reachable at
that exact instant. Durable Objects never cold-start that way, and their
WebSocket Hibernation API keeps a connection open at zero cost while
idle -- no sleep, nothing to wake up.

This is **not** a Godot resource -- it's a separate Cloudflare project you
deploy on its own, then add its `wss://` URL to
`net/manze_lakaz_tube_context.tres`'s `trackers_urls`.

## Protocol

Not the full BitTorrent tracker spec -- only the exact subset
`addons/tube/tube_tracker.gd` sends and expects. Every message is JSON
over one WebSocket. `info_hash` and `peer_id` are both always exactly
20-character ASCII strings (`app_id + session_id` and a 20-digit
peer-id-hash respectively -- see `tube_context.gd`), never binary and
never hex-encoded, so unlike a real BitTorrent tracker this server does no
hex/binary conversion anywhere; every id is passed through as a plain
string.

**Client -> server**, all three shaped as `{"action": "announce", ...}`:

- Join or periodic keepalive: `{info_hash, peer_id, uploaded, downloaded}`
- Offer or answer (indistinguishable at this layer -- the embedded SDP's
  own `type` field says which): `{info_hash, peer_id, to_peer_id, answer:
  {type, sdp, ice_candidates}, offer_id}`
- Leave: `{info_hash, peer_id, event: "stopped"}`

**Server -> client:**

- Reply to a join/keepalive, to the same sender only:
  `{action: "announce", info_hash, interval}`
- Relay of an offer/answer, to whichever peer is currently registered as
  `to_peer_id` within the same `info_hash`: `{action: "announce",
  info_hash, peer_id: <sender>, answer, offer_id}`
- Nothing is sent back for "stopped" -- matches the reference tracker
  (`bittorrent-tracker`'s own server skips a response for both cases).

No `offers`/`numwant` array support, no scrape endpoint -- Tube's client
never sends either.

## Architecture note: one Durable Object, not one per session

The design this was originally specified against was "the Worker routes
each connection to a Durable Object keyed by `idFromName(info_hash)`, one
object per game session." That's not actually possible here, and it's
worth recording why so nobody re-attempts it and burns time rediscovering
this: a Cloudflare Worker has to pick which Durable Object handles a
WebSocket **at the HTTP Upgrade request**, before any WebSocket message
has been exchanged -- but `info_hash` only ever arrives *in-band*, in the
first `announce` message, same as it does for a real BitTorrent tracker
(one connection there can even announce for several different
`info_hash`es over its lifetime). Tube itself connects to a single fixed
URL from `trackers_urls` with no per-session path or query string, so
there is nothing in the Upgrade request itself to route on.

So every connection, for every session, lands on one fixed Durable Object
instance (`env.HUB.idFromName("hub")`). Session isolation is preserved
anyway, just at a different layer: every roster entry and every relay
lookup is scoped by the pair `(info_hash, peer_id)` together, never
`peer_id` alone, so two different sessions' peers can never be confused
even though their sockets are held by the same object instance. At this
project's scale (a handful of concurrent card-game sessions among
friends, not a public tracker) one object comfortably holds every open
connection with room to spare before anything in the Workers Free plan's
limits (100,000 requests/day, 13,000 GB-s/day) becomes a concern.

If this ever needs genuine per-session isolation at the Durable Object
level (e.g. hitting real scale), the fix is a two-tier design: this same
object keeps holding the actual client-facing sockets, but forwards each
parsed message to a second `idFromName(info_hash)`-keyed Durable Object
(via a plain internal `fetch()`/RPC call, not a second WebSocket) that
owns the roster and decides what to relay. Not built here since nothing
about the current scale calls for that complexity.

## Local dev

```
npm install
npm run dev
```

Wrangler prints a `http://localhost:8787` URL. A plain `GET` there
returns `manze lakaz signaling: ok` -- confirms the Worker is up, same
role as `tracker-server`'s `/stats` page. The actual signaling endpoint
is `ws://localhost:8787/`.

With `npm run dev` left running in one terminal, `npm test` (in another)
drives two simulated peers through a join, an offer/answer exchange, a
second session proving no cross-session leak, and a stop -- exactly the
message shapes in the Protocol section above.

Requires Node 20+ (wrangler is pinned to the 3.x line here specifically
because 4.x requires Node 22, which wasn't available when this was set
up -- bump the pin once that's no longer true).

## Deploying

```
npx wrangler login    # opens a browser; one-time per machine
npm run deploy
```

Wrangler prints the deployed URL, e.g.
`https://manze-lakaz-signal.<your-subdomain>.workers.dev`. Swap `https://`
for `wss://` and add it as the tracker URL -- see Rollout below for where.

**Naming constraint, inherited from `tracker-server/README.md` --
preserve it:** never rename the Worker (`name` in `wrangler.toml`) or add
a custom domain containing "tracker" or "announce". Ad-blockers and strict
tracking-protection features pattern-match on exactly those words in a
hostname, which is what drove this project to self-host signaling in the
first place (see `tracker-server/README.md`). `manze-lakaz-signal` is
deliberately clean of both.

## Rollout

Added as the **first** entry in `trackers_urls` in
`net/manze_lakaz_tube_context.tres`, with the existing Render tracker kept
as a second entry, not replaced -- Tube already connects to every tracker
in the list, so this gets redundancy for free while the Cloudflare path
is still being validated in the wild. Do not delete `tracker-server/`.

## `npm audit` note

`npm install` flags vulnerabilities in `esbuild`/`miniflare`/`undici`/`ws`
-- all of them wrangler's own **local dev tooling** (the dev server,
local simulator, local dev networking), never part of what `wrangler
deploy` actually uploads to Cloudflare. They don't affect the deployed
Worker. The suggested fix (`npm audit fix --force`) pulls in wrangler 4.x,
which requires Node 22 (see Local dev above) -- not applied here for that
reason, not because the advisories were dismissed. Same shape of tradeoff
as `tracker-server/README.md`'s own audit note; re-check once this
project's Node version moves to 22+.

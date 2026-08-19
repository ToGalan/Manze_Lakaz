# Manze Lakaz tracker server

A self-hosted WebTorrent tracker, deployed under a plain domain (no
"tracker"/"announce" in the visible hostname) so browser ad-blockers and
strict tracking-protection features don't block it the way they block
`tracker.openwebtorrent.com` and similar public trackers -- that's the
whole reason this exists. See the project's own notes on that diagnosis
before changing anything here.

This is **not** a Godot resource -- it's a separate Node.js process you
deploy on its own, then point `net/manze_lakaz_tube_context.tres`'s
`trackers_urls` at its `wss://` URL.

## Local test

```
npm install
npm start
```

Then open `http://localhost:8080/stats` in a browser -- `bittorrent-
tracker`'s built-in stats page should load, confirming the server is up.
The actual signaling endpoint the game connects to is
`ws://localhost:8080/` (`wss://` once deployed behind HTTPS).

## Deploying

Any host that can run a persistent Node.js process and forward WebSocket
connections works. Two starting points:

- **Render.com** (Web Service, free tier): no payment method required to
  sign up, but free-tier services sleep after ~15 minutes of inactivity
  and take tens of seconds to wake back up on the next connection -- the
  very first join attempt after a quiet period may time out and need a
  retry.
- **Fly.io** (free allowance): stays awake continuously, no cold-start
  delay, but requires a payment method on file to create an account even
  though usage within the free allowance isn't charged.

Either way, the deploy steps are the same shape:
1. Push this `tracker-server/` folder (as its own repo, or a subdirectory
   deploy) to the host.
2. Point it at `npm start` (or `node server.js`) as the start command.
3. Make sure the platform's assigned port reaches the app via the `PORT`
   environment variable (both Render and Fly do this automatically).
4. Once deployed, take the `https://` URL the host gives you and swap the
   scheme for `wss://` -- that's the tracker URL to add to
   `trackers_urls` in `net/manze_lakaz_tube_context.tres`.

## `npm audit` note

`npm install` flags a high-severity SSRF advisory in `ip` (a dependency
of `bittorrent-tracker`). Checked: `ip` is declared in
`bittorrent-tracker`'s own `package.json` but never actually
`require`/`import`-ed anywhere in its source, so the vulnerable code path
is unreachable regardless of config here. Not fixed via `npm audit fix
--force`, since that downgrades to a years-old pre-1.0 `bittorrent-
tracker` release as its only available remediation, which is a worse
tradeoff than an unreachable advisory in an unused transitive dependency.
Worth re-checking if `bittorrent-tracker` ever starts actually using `ip`
in a future release.

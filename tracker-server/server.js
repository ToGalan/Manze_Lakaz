// Self-hosted WebTorrent tracker for Manze Lakaz's Tube-based WebRTC
// signaling (see net/manze_lakaz_tube_context.tres' trackers_urls and
// addons/tube/README.md). Deployed under a plain domain with no
// "tracker"/"announce" in the visible hostname, specifically so browser
// ad-blockers and strict tracking-protection features (which match on
// exactly those patterns) don't block the signaling handshake the way
// they block the public trackers -- see the project's own diagnosis of
// that issue before reworking this.
//
// WebSocket-only: browsers can't do the tracker protocol's UDP or plain
// HTTP transports, and this game never needs them either (both peers are
// always browsers or native WebRTC clients, never a torrent client).
import Server from 'bittorrent-tracker/server'

const port = process.env.PORT || 8080

const server = new Server({
  udp: false,
  http: false,
  ws: true,
  stats: true, // serves a plain status page at "/" -- doubles as a health check for the host platform
})

server.on('error', (err) => {
  console.error('tracker server error:', err.message)
})

server.on('warning', (err) => {
  console.warn('tracker server warning:', err.message)
})

server.on('listening', () => {
  console.log(`tracker listening on port ${port} (ws only)`)
})

server.listen(port, '0.0.0.0')

extends Node
## Autoload singleton "NetworkPeer". MUST be registered as an autoload
## under this exact name so its node path (/root/NetworkPeer) matches on
## every connected process -- Godot's high-level multiplayer API routes
## RPCs by node path, so server and client need the same node there.
##
## This node is a thin RPC boundary only: every method here either
## forwards straight into ServerAuthority (when hosting) or emits a
## signal for NetworkSession to pick up (when receiving as a client). All
## real logic -- validation, filtering, reconnection, the turn timer --
## lives in ServerAuthority / NetworkStateFilter, not here.
##
## Transport is Tube (WebRTC + WebTorrent-tracker signalling), not ENet:
## the game ships as an HTML5 build, and browsers cannot host an ENet or
## WebSocket server, but a WebRTC peer needs no listening port, so a
## browser tab can be the session host. TubeClient installs its own
## MultiplayerAPI at the SceneTree root (see _ready()), so every existing
## rpc_id()/@rpc call below keeps routing exactly as it did over ENet --
## the session creator is always peer id 1, matching every rpc_id(1, ...)
## call already in this file.

signal lobby_changed(lobby: Dictionary)
signal seat_assigned(seat: int, token: String)
signal join_rejected(reason: String)
signal snapshot_received(snapshot: Dictionary)
signal log_line_received(text: String)

## Tube session lifecycle, re-emitted as NetworkPeer's own signals so
## GameScreen only ever talks to NetworkPeer, never to TubeClient directly.
signal session_ready(session_id: String)   # this peer is now hosting; share session_id
signal session_joined                      # this peer successfully joined as a client
signal session_ended                       # the session was left or closed
signal connection_error(message: String)   # create/join failed, or signaling broke

const TUBE_CONTEXT := preload("res://net/manze_lakaz_tube_context.tres")

## TURN username/credential are secrets and are deliberately NOT stored in
## TUBE_CONTEXT's .tres (a previous version had them committed in plaintext
## in this public repo, letting anyone drain the free relay quota -- do not
## reintroduce that). _apply_turn_credentials() injects them into
## TUBE_CONTEXT.turn_servers at runtime instead; see that function for
## where they're actually read from.
##
## Local, gitignored file where a credential pair can be dropped for a
## desktop/editor run or to be bundled into a web export (browsers have no
## environment variables at runtime, so the env-var path alone can't cover
## that target). Two lines: username, then credential. See
## net/turn_credentials.example.txt for the expected shape.
const _TURN_CREDENTIALS_LOCAL_FILE := "res://net/turn_credentials.local.txt"

var authority: ServerAuthority = null # non-null only on the hosting process
var db: CardDatabase
var my_token: String = ""
var my_seat: int = -1
var session_id: String = ""

var tube_client: TubeClient

# ===========================================================================
# Connection setup
# ===========================================================================

func _ready() -> void:
	_apply_turn_credentials()

	# TubeClient must be in the tree to function and must not be removed
	# while a session is open; NetworkPeer is an autoload that outlives
	# every scene, so it's the natural permanent home for it.
	tube_client = TubeClient.new()
	tube_client.name = "TubeClient"
	tube_client.context = TUBE_CONTEXT
	tube_client.peer_signaling_timeout = TUBE_CONTEXT.peer_signaling_timeout
	tube_client.peer_signaling_max_attempts = TUBE_CONTEXT.peer_signaling_max_attempts
	# Explicit instead of leaving this null: TubeClient._ready() already
	# guards a null multiplayer_root_node and falls back to the same
	# NodePath() (tree root) this resolves to, so this is a no-op for
	# routing -- but the inspector's client_control.gd reads
	# multiplayer_root_node.get_path() unguarded, which would otherwise
	# hard-error the moment TubeInspector.client is assigned (see
	# ui/GameScreen.gd's _wire_tube_inspector()).
	tube_client.multiplayer_root_node = get_tree().root
	tube_client.session_created.connect(_on_session_created)
	tube_client.session_joined.connect(_on_session_joined)
	tube_client.session_left.connect(_on_session_left)
	tube_client.error_raised.connect(_on_error_raised)
	tube_client.peer_refused.connect(_on_peer_refused)
	tube_client.peer_disconnected.connect(_on_peer_disconnected)
	add_child(tube_client)

## Fills in TUBE_CONTEXT.turn_servers' username/credential at runtime,
## checked in this order: TURN_USERNAME/TURN_CREDENTIAL environment
## variables first (set by a desktop shell or a CI/build pipeline), then
## _TURN_CREDENTIALS_LOCAL_FILE (needed for a web export -- OS.get_environment()
## is always empty in an exported HTML5 build, since browsers have no
## environment variables to read). If neither source has both values, every
## entry in turn_servers is dropped entirely rather than left with empty
## credentials -- an unauthenticated TURN entry can't possibly connect
## anyway, and shipping one silently would be indistinguishable from a real
## connectivity bug, whereas dropping it visibly degrades to STUN-only
## (works for most players; just not the ones on UDP-blocking/symmetric-NAT
## networks that specifically need a relay) with a clear log line saying why.
func _apply_turn_credentials() -> void:
	var username := OS.get_environment("TURN_USERNAME")
	var credential := OS.get_environment("TURN_CREDENTIAL")

	if username.is_empty() or credential.is_empty():
		var from_file := _read_turn_credentials_file()
		username = from_file[0]
		credential = from_file[1]

	if username.is_empty() or credential.is_empty():
		push_warning("NetworkPeer: no TURN credentials found (set TURN_USERNAME/TURN_CREDENTIAL env vars, or drop them in %s) -- falling back to STUN-only. Players on networks that block plain UDP (corporate wifi, some mobile carriers/routers) will likely be unable to connect." % _TURN_CREDENTIALS_LOCAL_FILE)
		# .clear(), not "= []" -- TUBE_CONTEXT is a const, and GDScript
		# rejects an assignment through a const's property path even though
		# the property itself (turn_servers, on the Resource TUBE_CONTEXT
		# refers to) is perfectly mutable. Mutating the existing Array
		# in place sidesteps that; the const only ever pins the TUBE_CONTEXT
		# reference itself, never the object's own contents.
		TUBE_CONTEXT.turn_servers.clear()
		return

	for turn_server in TUBE_CONTEXT.turn_servers:
		turn_server["username"] = username
		turn_server["credential"] = credential

## Reads a two-line "username\ncredential" pair from
## _TURN_CREDENTIALS_LOCAL_FILE. Returns ["", ""] if the file is missing,
## unreadable, or short a line -- callers treat that the same as "not
## configured", not as an error, since running without the local file
## (relying on the env vars instead, or on neither) is a normal setup.
func _read_turn_credentials_file() -> Array:
	if not FileAccess.file_exists(_TURN_CREDENTIALS_LOCAL_FILE):
		return ["", ""]

	var f := FileAccess.open(_TURN_CREDENTIALS_LOCAL_FILE, FileAccess.READ)
	if f == null:
		return ["", ""]

	var lines := f.get_as_text().split("\n")
	if lines.size() < 2:
		return ["", ""]

	return [lines[0].strip_edges(), lines[1].strip_edges()]

## Starts hosting: constructs ServerAuthority synchronously (it doesn't
## need a live connection yet, only the peer_node reference), same as the
## old ENet create_server() path did. Unlike ENet, Tube's session id
## isn't known synchronously -- it's only assigned once signaling starts
## -- so this is signal-driven: listen for session_ready(session_id) to
## get the id to share, or connection_error(message) if it fails.
func create_session(p_db: CardDatabase, config: GameConfig, turn_timer_seconds: float, auto_play_difficulty: int, ai_think_time_seconds: float, fill_empty_seats_with_ai: bool, ai_fill_difficulty: int) -> void:
	db = p_db
	authority = ServerAuthority.new(db, config, self, turn_timer_seconds, auto_play_difficulty, ai_think_time_seconds, fill_empty_seats_with_ai, ai_fill_difficulty)
	tube_client.create_session()

## Joins an existing session by its short shareable id (in place of an
## address:port pair -- WebRTC peers aren't reached that way). Signal-
## driven like create_session(): listen for session_joined or
## connection_error(message).
func join_session(p_session_id: String, p_db: CardDatabase) -> void:
	db = p_db
	authority = null
	tube_client.join_session(p_session_id)

func shutdown() -> void:
	tube_client.leave_session()
	authority = null
	my_token = ""
	my_seat = -1
	session_id = ""

func _on_session_created() -> void:
	session_id = tube_client.session_id
	session_ready.emit(session_id)

func _on_session_joined() -> void:
	# Mirrors _on_session_created()'s assignment: tube_client.session_id is
	# populated on the joining side too (see TubeClient.join_session()),
	# and GameScreen's reconnect loop needs this device's OWN record of
	# which session it's in regardless of whether it's the host or a
	# client -- session_id isn't just "the code the host shares".
	session_id = tube_client.session_id
	session_joined.emit()

func _on_session_left() -> void:
	authority = null
	session_id = ""
	session_ended.emit()

## Tube's own error codes are too coarse to tell these situations apart
## (JOIN_SESSION_FAILED covers all of them), so the actual signal is
## in the message text Tube's peer/tracker layer sets -- see
## _humanize_tube_error() for exactly which substrings map to which
## situation and why.
func _on_error_raised(_code: int, message: String) -> void:
	connection_error.emit(_humanize_tube_error(message))

func _on_peer_refused(_peer_id: int) -> void:
	connection_error.emit("This session isn't accepting new players right now.")

## WebRTC failure modes a player cannot fix by retrying the same way
## twice, so the message has to actually say what's going on and what
## (if anything) is worth trying next -- see tube_peer.gd/tube_client.gd
## for where each of these exact substrings gets set:
##   - "session id invalid": is_session_id_valid() rejected the format
##     locally (wrong length), never even attempted a connection.
##   - "max connection attempts reached": TubePeer exhausted its retries
##     exchanging signaling data (offer/answer) with the target peer and
##     never got a response -- indistinguishable, from here, from "no one
##     is hosting a session with that id" (expired, mistyped, or the host
##     already left).
##   - "cannot connect to any tracker" / "lost all trackers connections":
##     failure to reach the WebTorrent tracker relays themselves. In
##     practice this is very often local TLS interception, not a dead
##     tracker or a bad internet connection: many antivirus suites (AVG,
##     Avast, Kaspersky, etc.) and some corporate/school networks scan
##     HTTPS by re-signing every connection with their own locally-
##     generated root certificate. Browsers and curl trust that
##     certificate because it gets installed into the OS's certificate
##     store; Godot's networking layer ships its own fixed certificate
##     list and never reads the OS store, so it rejects it -- every wss://
##     connection the game makes fails identically, which is exactly the
##     "works in the browser, fails in the game" pattern this produces.
##     Confirmed by reproducing this exact failure against multiple
##     unrelated hosts (including plain https://www.google.com) with an
##     AVG "Web/Mail Shield" root certificate present in the local
##     machine's trust store.
##   - "connection failed": signaling DID succeed (offer/answer/ICE were
##     exchanged) but WebRTCPeerConnection still ended in STATE_FAILED --
##     the two peers talked but couldn't open a direct link. This is the
##     NAT/firewall case; checked last since the other messages above are
##     more specific substrings of situations that also happen to satisfy
##     this check.
func _humanize_tube_error(message: String) -> String:
	if message.findn("session id invalid") != -1:
		return "That session ID doesn't look right. Double-check it with whoever shared it and try again."
	if message.findn("max connection attempts reached") != -1:
		return "Couldn't find that session. It may not exist, may have expired, or the host may have already left."
	if message.findn("cannot connect to any tracker") != -1 or message.findn("lost all trackers connections") != -1:
		return "Couldn't reach the connection service. If your internet is otherwise working (e.g. you can browse normally), this is usually antivirus or firewall software scanning HTTPS traffic (AVG, Avast, Kaspersky, and similar 'web shield' features are common causes) -- try adding an exception for this game or briefly disabling that feature to confirm, then try again. Otherwise, check your internet connection."
	if message.findn("connection failed") != -1:
		return "A direct connection to the other player couldn't be established. This is usually a router or network restriction (NAT/firewall), not something wrong with the game. Try a different network if you can -- otherwise, hot-seat mode on this device still works. Retrying on the same network probably won't help."
	return message

func _on_peer_disconnected(peer_id: int) -> void:
	if authority != null:
		authority.handle_peer_disconnected(peer_id)

# ===========================================================================
# Client -> server (RPCs the server exposes; also called directly for the
# host's own local seat, which needs no network round-trip)
# ===========================================================================

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_join(display_name: String) -> void:
	if authority != null:
		authority.handle_join_request(multiplayer.get_remote_sender_id(), display_name)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_rejoin(token: String) -> void:
	if authority != null:
		authority.handle_rejoin_request(multiplayer.get_remote_sender_id(), token)

@rpc("any_peer", "call_remote", "reliable")
func rpc_submit_action(action_dict: Dictionary) -> void:
	if authority != null:
		authority.handle_action_intent(multiplayer.get_remote_sender_id(), action_dict)

@rpc("any_peer", "call_remote", "reliable")
func rpc_start_game() -> void:
	if authority != null:
		authority.handle_start_game_request(multiplayer.get_remote_sender_id())

func request_join(display_name: String) -> void:
	if authority != null:
		authority.handle_join_request(1, display_name)
	else:
		rpc_id(1, "rpc_request_join", display_name)

func request_rejoin(token: String) -> void:
	if authority != null:
		authority.handle_rejoin_request(1, token)
	else:
		rpc_id(1, "rpc_request_rejoin", token)

func request_start_game() -> void:
	if authority != null:
		authority.handle_start_game_request(1)
	else:
		rpc_id(1, "rpc_start_game")

func submit_action(action: Action) -> void:
	var d := ActionSerializer.serialize(action)
	if authority != null:
		authority.handle_action_intent(1, d)
	else:
		rpc_id(1, "rpc_submit_action", d)

# ===========================================================================
# Server -> client (unicast; each peer only ever receives its OWN filtered
# payload, never a broadcast of everyone's). ServerAuthority calls the
# deliver_* wrappers below rather than rpc_id() directly: for a real
# remote peer that's a normal RPC, but when the target IS the host's own
# seat, calling rpc_id(self, ...) would execute synchronously (Godot's
# "call yourself" RPC semantics), and since a snapshot arriving typically
# causes the receiver to immediately act and produce ANOTHER snapshot,
# that recurses -- a host could end up playing its entire game inside one
# unbounded, nested call stack. Routing self-delivery through
# call_deferred breaks that recursion by pushing the local delivery to
# the next idle frame, exactly like a real network hop would. This still
# applies unchanged under WebRTC: the recursion risk is in our own
# call-yourself pattern, not in the transport underneath it.
# ===========================================================================

func deliver_seat_assigned(peer_id: int, seat: int, token: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		call_deferred("rpc_seat_assigned", seat, token)
	else:
		rpc_id(peer_id, "rpc_seat_assigned", seat, token)

func deliver_join_rejected(peer_id: int, reason: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		call_deferred("rpc_join_rejected", reason)
	else:
		rpc_id(peer_id, "rpc_join_rejected", reason)

func deliver_lobby_state(peer_id: int, lobby: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		call_deferred("rpc_lobby_state", lobby)
	else:
		rpc_id(peer_id, "rpc_lobby_state", lobby)

func deliver_state_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		call_deferred("rpc_state_snapshot", snapshot)
	else:
		rpc_id(peer_id, "rpc_state_snapshot", snapshot)

func deliver_log_line(peer_id: int, text: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		call_deferred("rpc_log_line", text)
	else:
		rpc_id(peer_id, "rpc_log_line", text)

@rpc("authority", "call_remote", "reliable")
func rpc_log_line(text: String) -> void:
	log_line_received.emit(text)

@rpc("authority", "call_remote", "reliable")
func rpc_seat_assigned(seat: int, token: String) -> void:
	my_seat = seat
	my_token = token
	seat_assigned.emit(seat, token)

@rpc("authority", "call_remote", "reliable")
func rpc_join_rejected(reason: String) -> void:
	join_rejected.emit(reason)

@rpc("authority", "call_remote", "reliable")
func rpc_lobby_state(lobby: Dictionary) -> void:
	lobby_changed.emit(lobby)

@rpc("authority", "call_remote", "reliable")
func rpc_state_snapshot(snapshot: Dictionary) -> void:
	snapshot_received.emit(snapshot)

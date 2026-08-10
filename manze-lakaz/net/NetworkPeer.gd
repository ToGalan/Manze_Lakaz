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

signal lobby_changed(lobby: Dictionary)
signal seat_assigned(seat: int, token: String)
signal join_rejected(reason: String)
signal snapshot_received(snapshot: Dictionary)

var authority: ServerAuthority = null # non-null only on the hosting process
var db: CardDatabase
var my_token: String = ""
var my_seat: int = -1

# ===========================================================================
# Connection setup
# ===========================================================================

func start_hosting(p_db: CardDatabase, config: GameConfig, port: int, turn_timer_seconds: float, auto_play_difficulty: int, ai_think_time_seconds: float, fill_empty_seats_with_ai: bool, ai_fill_difficulty: int) -> int:
	db = p_db
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max(config.num_players, 1))
	if err != OK:
		return err
	multiplayer.multiplayer_peer = enet
	authority = ServerAuthority.new(db, config, self, turn_timer_seconds, auto_play_difficulty, ai_think_time_seconds, fill_empty_seats_with_ai, ai_fill_difficulty)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func join_as_client(address: String, port: int, p_db: CardDatabase) -> int:
	db = p_db
	authority = null
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = enet
	return OK

func shutdown() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	authority = null
	my_token = ""
	my_seat = -1

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
# the next idle frame, exactly like a real network hop would.
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

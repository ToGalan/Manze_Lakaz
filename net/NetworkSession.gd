class_name NetworkSession
extends GameSession
## Drives a game through NetworkPeer: submit_action() sends an intent to
## the server and waits, get_state() returns a shadow GameState rebuilt
## from the server's latest filtered snapshot, and get_legal_actions()
## returns exactly what the server computed and sent -- this session
## never calls RulesEngine.get_legal_actions() itself, since a shadow
## state never has enough data to compute anyone else's options (see
## ShadowStateBuilder), and the server has already told us our own.

var peer: Node # the NetworkPeer autoload
var my_seat: int = -1
var latest_snapshot: Dictionary = {}
var shadow_state: GameState = null

func _init(p_db: CardDatabase, p_peer: Node) -> void:
	db = p_db
	peer = p_peer
	peer.snapshot_received.connect(_on_snapshot_received)
	peer.log_line_received.connect(log_line_received.emit)
	my_seat = peer.my_seat

func _on_snapshot_received(snapshot: Dictionary) -> void:
	latest_snapshot = snapshot
	my_seat = snapshot.get("viewer_index", my_seat)
	shadow_state = ShadowStateBuilder.build(snapshot, db)
	state_changed.emit()

func get_state() -> GameState:
	return shadow_state

func get_legal_actions() -> Array[Action]:
	return ActionSerializer.deserialize_list(latest_snapshot.get("legal_actions", []))

func submit_action(action: Action) -> void:
	peer.submit_action(action)

func viewer_index() -> int:
	return my_seat

func is_seat_ai(_player_index: int) -> bool:
	# From a client's perspective every other seat just looks like "not
	# me, and not currently my problem" -- the server is the only place
	# that knows or needs to know which seats are AI-filled.
	return false

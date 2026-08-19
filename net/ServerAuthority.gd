class_name ServerAuthority
extends RefCounted
## The server-side authority. Owns the one real GameState. Every incoming
## action is (1) checked against the sending peer's actual seat -- a
## client's claimed player_index is never trusted on its own -- and then
## (2) re-validated against RulesEngine.get_legal_actions() before
## RulesEngine.apply_action() is allowed to touch state. Anything that
## fails either check is dropped with a warning, never applied.
##
## peer_node is the Node RPCs are sent through (see NetworkPeer.gd). It is
## optional: passing null (as unit tests do) exercises the pure validation
## logic without requiring a live SceneTree/multiplayer peer, since
## broadcasting and the turn timer are the only things that need a real
## tree and both no-op safely when peer_node is null.

var db: CardDatabase
var config: GameConfig
var peer_node: Node

var turn_timer_seconds: float
var auto_play_difficulty: int
var ai_think_time_seconds: float
var fill_empty_seats_with_ai: bool
var ai_fill_difficulty: int

var state: GameState = null
var game_started: bool = false

var peer_to_seat: Dictionary = {}   # peer_id -> seat
var seat_to_peer: Dictionary = {}   # seat -> peer_id (-1 if disconnected)
var seat_tokens: Dictionary = {}    # seat -> reconnection token
var token_to_seat: Dictionary = {}  # token -> seat
var seat_names: Dictionary = {}     # seat -> display name
var seat_is_ai: Dictionary = {}     # seat -> bool

var _fallback_bots: Dictionary = {} # seat -> AiBot
var _turn_timer_token: int = 0      # invalidates stale timer callbacks after a real action lands

func _init(
	p_db: CardDatabase,
	p_config: GameConfig,
	p_peer_node: Node = null,
	p_turn_timer_seconds: float = 30.0,
	p_auto_play_difficulty: int = AiBot.Difficulty.EASY,
	p_ai_think_time_seconds: float = 1.0,
	p_fill_empty_seats_with_ai: bool = false,
	p_ai_fill_difficulty: int = AiBot.Difficulty.MEDIUM
) -> void:
	db = p_db
	config = p_config
	peer_node = p_peer_node
	turn_timer_seconds = p_turn_timer_seconds
	auto_play_difficulty = p_auto_play_difficulty
	ai_think_time_seconds = p_ai_think_time_seconds
	fill_empty_seats_with_ai = p_fill_empty_seats_with_ai
	ai_fill_difficulty = p_ai_fill_difficulty

# ===========================================================================
# Lobby: join / rejoin / start
# ===========================================================================

func handle_join_request(peer_id: int, display_name: String) -> void:
	if game_started:
		_send_rejected(peer_id, "Game already started.")
		return
	if peer_to_seat.has(peer_id):
		return # already joined, ignore duplicate request

	var seat := _first_open_human_seat()
	if seat == -1:
		_send_rejected(peer_id, "Game is full.")
		return

	var token := _generate_token()
	peer_to_seat[peer_id] = seat
	seat_to_peer[seat] = peer_id
	seat_tokens[seat] = token
	token_to_seat[token] = seat
	seat_names[seat] = display_name if display_name != "" else "Player %d" % (seat + 1)
	seat_is_ai[seat] = false

	_send_seat_assigned(peer_id, seat, token)
	_broadcast_lobby()

func handle_rejoin_request(peer_id: int, token: String) -> void:
	if not token_to_seat.has(token):
		_send_rejected(peer_id, "Unknown or expired reconnection token.")
		return

	var seat: int = token_to_seat[token]
	var old_peer: int = seat_to_peer.get(seat, -1)
	if old_peer != -1 and old_peer != peer_id and peer_to_seat.get(old_peer, -1) == seat:
		peer_to_seat.erase(old_peer)

	peer_to_seat[peer_id] = seat
	seat_to_peer[seat] = peer_id

	_send_seat_assigned(peer_id, seat, token)
	_broadcast_lobby()
	if game_started:
		_send_snapshot_to_seat(seat) # "restores a player's filtered view"

func handle_peer_disconnected(peer_id: int) -> void:
	if not peer_to_seat.has(peer_id):
		return
	var seat: int = peer_to_seat[peer_id]
	peer_to_seat.erase(peer_id)
	seat_to_peer[seat] = -1
	_broadcast_lobby()
	# No pause and no seat teardown: the token stays valid, so the seat can
	# be reclaimed by handle_rejoin_request() at any time. Until then, the
	# turn timer's auto-play fallback keeps their turns from blocking the
	# rest of the table.

func handle_start_game_request(_peer_id: int) -> void:
	if game_started:
		return
	_fill_remaining_seats_with_ai()
	state = RulesEngine.new_game(config, db)
	if state == null:
		return
	game_started = true
	_broadcast_snapshots()
	_arm_turn_timer()

func _fill_remaining_seats_with_ai() -> void:
	if not fill_empty_seats_with_ai:
		return
	for i in config.num_players:
		if not seat_to_peer.has(i):
			seat_is_ai[i] = true
			seat_names[i] = "AI (%s)" % AiBot.DIFFICULTY_NAMES[ai_fill_difficulty]

func _first_open_human_seat() -> int:
	for i in config.num_players:
		if seat_is_ai.get(i, false):
			continue
		if not seat_to_peer.has(i) or seat_to_peer[i] == -1:
			return i
	return -1

# ===========================================================================
# Action intents
# ===========================================================================

func handle_action_intent(peer_id: int, action_dict: Dictionary) -> void:
	if state == null or state.game_over:
		return

	var claimed_seat: int = peer_to_seat.get(peer_id, -1)
	if claimed_seat == -1:
		push_warning("ServerAuthority: rejected action from an unrecognized peer (%d)" % peer_id)
		return

	var action := ActionSerializer.deserialize(action_dict)
	if action.player_index != claimed_seat:
		# A client declared a different player_index than the seat it is
		# actually authenticated as. Never trust the client's own claim.
		push_warning("ServerAuthority: rejected action -- peer %d is seated at %d but claimed to act as %d" % [peer_id, claimed_seat, action.player_index])
		return

	_apply_validated_action(action)

func _apply_validated_action(action: Action) -> bool:
	var legal := RulesEngine.get_legal_actions(state)
	var is_legal := false
	for a in legal:
		if a.equals(action):
			is_legal = true
			break
	if not is_legal:
		push_warning("ServerAuthority: rejected illegal action: %s" % action.describe())
		return false

	# Resolved against state BEFORE apply_action() mutates it -- see
	# GameViewModel.describe_action_for_log()'s own contract (hand/board
	# lookups by instance id need the card to still be there). GameViewModel
	# lives under ui/ but is a pure state+action -> String formatter with no
	# Node/SceneTree dependency, and this is the one place that already
	# holds the full, unfiltered state -- reusing it here avoids
	# reimplementing the same per-action-type description text a second
	# time just to keep a directory boundary.
	var log_line := GameViewModel.describe_action_for_log(state, action)

	RulesEngine.apply_action(state, action)
	_broadcast_snapshots()
	_broadcast_log_line(log_line)
	if state.game_over:
		_turn_timer_token += 1 # cancel any pending timer
	else:
		_arm_turn_timer()
	return true

# ===========================================================================
# Turn timer / auto-play fallback
# ===========================================================================

func _arm_turn_timer() -> void:
	if peer_node == null or not peer_node.is_inside_tree():
		return
	_turn_timer_token += 1
	var armed_token := _turn_timer_token
	var seat := state.current_player_index
	var delay := ai_think_time_seconds if seat_is_ai.get(seat, false) else turn_timer_seconds
	peer_node.get_tree().create_timer(delay).timeout.connect(_on_turn_timer_expired.bind(armed_token))

func _on_turn_timer_expired(fired_token: int) -> void:
	if fired_token != _turn_timer_token:
		return # a real action already landed and re-armed the timer; this callback is stale
	if state == null or state.game_over:
		return

	var seat := state.current_player_index
	var legal := RulesEngine.get_legal_actions(state)
	if legal.is_empty():
		_arm_turn_timer()
		return

	var bot: AiBot = _fallback_bots.get(seat)
	if bot == null:
		var difficulty: int = ai_fill_difficulty if seat_is_ai.get(seat, false) else auto_play_difficulty
		bot = AiBot.create(difficulty, seat)
		_fallback_bots[seat] = bot

	var action := bot.choose_action(state, legal)
	if action != null:
		_apply_validated_action(action) # re-arms the timer on success
	else:
		_arm_turn_timer()

# ===========================================================================
# Broadcasting (unicast per peer -- every seat gets its OWN filtered view)
# ===========================================================================

func _broadcast_lobby() -> void:
	if peer_node == null:
		return
	var seats := []
	for i in config.num_players:
		seats.append({
			"seat": i,
			"name": seat_names.get(i, ""),
			"connected": seat_to_peer.get(i, -1) != -1,
			"is_ai": seat_is_ai.get(i, false),
		})
	var payload := {"seats": seats, "started": game_started}
	for peer_id in peer_to_seat.keys():
		peer_node.deliver_lobby_state(peer_id, payload)

func _broadcast_snapshots() -> void:
	for seat in range(config.num_players):
		_send_snapshot_to_seat(seat)

## Every connected human seat gets the exact same text -- unlike a
## snapshot, a log line never contains hidden information (see
## _apply_validated_action()'s comment), so there's no per-seat filtering
## to do here.
func _broadcast_log_line(text: String) -> void:
	if peer_node == null:
		return
	for seat in range(config.num_players):
		if seat_is_ai.get(seat, false):
			continue
		var peer_id: int = seat_to_peer.get(seat, -1)
		if peer_id == -1:
			continue
		peer_node.deliver_log_line(peer_id, text)

func _send_snapshot_to_seat(seat: int) -> void:
	if peer_node == null or seat_is_ai.get(seat, false):
		return
	var peer_id: int = seat_to_peer.get(seat, -1)
	if peer_id == -1:
		return # disconnected; they'll get a fresh snapshot on rejoin
	var snapshot := NetworkStateFilter.build_snapshot(state, seat, turn_timer_seconds)
	peer_node.deliver_state_snapshot(peer_id, snapshot)

func _send_seat_assigned(peer_id: int, seat: int, token: String) -> void:
	if peer_node == null:
		return
	peer_node.deliver_seat_assigned(peer_id, seat, token)

func _send_rejected(peer_id: int, reason: String) -> void:
	if peer_node == null:
		return
	peer_node.deliver_join_rejected(peer_id, reason)

func _generate_token() -> String:
	return "%d-%d-%d" % [Time.get_ticks_usec(), randi(), randi()]

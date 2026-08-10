class_name LocalHotSeatSession
extends GameSession
## Drives a game directly against a real, fully-authoritative local
## GameState -- the hot-seat mode from earlier phases, now behind the
## GameSession interface so GameScreen can't tell it apart from an
## online game except by asking is_seat_ai()/viewer_index().

var state: GameState
var seat_bots: Dictionary = {}       # player_index -> AiBot, local hot-seat AI opponents
var seat_difficulty: Dictionary = {} # player_index -> AiBot.Difficulty, for display purposes
var _viewer_index: int = -1

func _init(p_db: CardDatabase) -> void:
	db = p_db

func start_game(config: GameConfig) -> bool:
	state = RulesEngine.new_game(config, db)
	return state != null

func get_state() -> GameState:
	return state

func get_legal_actions() -> Array[Action]:
	if state == null:
		return []
	return RulesEngine.get_legal_actions(state)

func submit_action(action: Action) -> void:
	RulesEngine.apply_action(state, action)
	state_changed.emit()

func viewer_index() -> int:
	return _viewer_index

func set_viewer_index(i: int) -> void:
	_viewer_index = i

func is_seat_ai(player_index: int) -> bool:
	return seat_bots.has(player_index)

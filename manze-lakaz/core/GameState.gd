class_name GameState
extends RefCounted
## The complete state of one game in progress. Pure data plus a deterministic
## RNG stream; all mutation happens through RulesEngine.apply_action().

enum Phase { DRAFT, TAKE, PLAY, HAND_LIMIT, GAME_OVER }

var config: GameConfig
var database: CardDatabase
var rng: RandomNumberGenerator

var deck: Array[Card] = []
var discard_pile: Array[Card] = []
var players: Array[Player] = []

## DRAFT phase only: draft_offers[i] is the list of recipe_ids still offered
## to player i and not yet kept. Shrinks as that player keeps recipes.
var draft_offers: Array = [] # Array[Array[String]]

var current_player_index: int = 0
var phase: int = Phase.DRAFT
var turn_number: int = 1 # 1-indexed; the turn currently in progress (or last one played)

var game_over: bool = false
var winner_player_index: int = -1
var winner_team_id: int = -1

# Stats accumulated as the game is played, for the simulator to read at the end.
var steal_count: int = 0
var reshuffle_count: int = 0
var starvation_events: int = 0
var starvation_by_def: Dictionary = {} # def_id -> count

func _init(p_config: GameConfig = null, p_database: CardDatabase = null) -> void:
	config = p_config
	database = p_database
	rng = RandomNumberGenerator.new()
	if config != null:
		rng.seed = config.seed

func current_player() -> Player:
	return players[current_player_index]

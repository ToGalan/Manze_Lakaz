class_name GameResult
extends RefCounted
## The recorded outcome of one simulated game, ready for aggregation.

var num_players: int = 0
var seed: int = 0

var capped: bool = false # true if the game hit max_turns without a winner

var winner_player_index: int = -1
var winner_seat: int = -1
var winner_team_id: int = -1
var winning_recipe_id: String = ""
var winning_recipe_slot: int = -1 # 0 or 1: which of the winner's drafted recipes was completed

var total_turns: int = 0
var steal_count: int = 0
var reshuffle_count: int = 0
var starvation_events: int = 0
var starvation_by_def: Dictionary = {} # def_id -> count

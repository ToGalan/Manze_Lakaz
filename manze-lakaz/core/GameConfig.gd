class_name GameConfig
extends Resource
## Runtime-tunable rules. Every one of these is meant to be changed between
## simulation runs without touching code -- that's the whole point of
## exposing them here instead of as constants in RulesEngine.

## When true, a player may attach ANY ingredient to a recipe, including ones
## the recipe does not require. Off-recipe attachments are decoys: stealable,
## and they never count toward completion.
@export var decoys_enabled: bool = false

## Hand size a player must discard down to in the Step 3 hand-limit check.
@export var hand_limit: int = 7

## How many recipes each player keeps after the draft (kept, not offered).
@export var recipes_per_player: int = 2

## Free-for-all (false): first player to complete either recipe wins instantly.
## Team mode (true): a 4-player game splits into two 2-player teams (seats
## 0&2 vs 1&3); the team wins once BOTH partners have completed one recipe.
@export var win_on_both_recipes: bool = false

## How many recipe cards are offered to each player during the draft, of
## which they keep recipes_per_player and return the rest to the box.
@export var draft_pool_size: int = 3

## How many times a single player may perform the STEAL action over the
## whole game. Once a player reaches this many steals, STEAL simply stops
## being offered to them for the rest of the game; DRAW/TAKE_DISCARD remain
## available.
@export var max_steals_per_player: int = 4

## Player count for this game instance.
@export var num_players: int = 4

## Deterministic RNG seed. Same seed + same config + same data = same game.
@export var seed: int = 0

## Used only for converting turn counts into estimated wall-clock minutes
## in simulation reports; has no effect on rules.
@export var seconds_per_turn: float = 12.0

func duplicate_config() -> GameConfig:
	var c := GameConfig.new()
	c.decoys_enabled = decoys_enabled
	c.hand_limit = hand_limit
	c.recipes_per_player = recipes_per_player
	c.win_on_both_recipes = win_on_both_recipes
	c.draft_pool_size = draft_pool_size
	c.max_steals_per_player = max_steals_per_player
	c.num_players = num_players
	c.seed = seed
	c.seconds_per_turn = seconds_per_turn
	return c

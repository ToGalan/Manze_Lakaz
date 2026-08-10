class_name PublicGameView
extends RefCounted
## The information boundary AI opponents are restricted to. Built fresh
## from the real GameState for one specific seat, it exposes exactly what
## a human sitting in that seat could legitimately know:
##   - that seat's own hand and recipes, in full
##   - every other player's hand COUNT (never contents), team, and recipes
##     -- recipe dish name/tier/full requirement list is public per the
##     rules ("sit face up in front of them"), so def is included in full;
##     only which specific cards are currently attached is otherwise
##     observable, exactly as the table would show it
##   - the shared deck size and the discard pile (a real pile is visible)
##   - phase/turn/config, which are just rules parameters, not secrets
##
## AiBot._decide() receives ONLY a PublicGameView, never the raw GameState,
## so a bot has no way to reach into another seat's hand even by accident.

class RecipeView:
	var def: RecipeDef
	var recipe_index: int
	var attached_ingredients: Array = []   # Array[Card], the actual visible cards
	var attached_preparations: Array = []  # Array[Card]
	var decoy_cards: Array = []            # Array[Card]
	var completed: bool = false

	func filled_slot_count() -> int:
		return attached_ingredients.size() + attached_preparations.size()

	func total_slot_count() -> int:
		return def.total_required_slots()

	func progress_fraction() -> float:
		var total := total_slot_count()
		if total <= 0:
			return 0.0
		return float(filled_slot_count()) / float(total)

	func find_card(card_instance_id: int) -> Card:
		for c in attached_ingredients:
			if c.instance_id == card_instance_id:
				return c
		for c in attached_preparations:
			if c.instance_id == card_instance_id:
				return c
		for c in decoy_cards:
			if c.instance_id == card_instance_id:
				return c
		return null

class OpponentView:
	var player_index: int
	var team_id: int
	var hand_count: int
	var steals_used: int
	var recipes: Array = []  # Array[RecipeView]

var viewer_index: int
var config: GameConfig
var database: CardDatabase
var phase: int
var turn_number: int
var current_player_index: int
var deck_size: int
var discard_pile: Array = []  # Array[Card] -- a real discard pile is visible to everyone

var own_hand: Array = []      # Array[Card]
var own_recipes: Array = []   # Array[Recipe] -- the viewer's own, full detail
var own_steals_used: int = 0
var opponents: Array = []     # Array[OpponentView]

static func from_state(state: GameState, viewer_index: int) -> PublicGameView:
	var v := PublicGameView.new()
	v.viewer_index = viewer_index
	v.config = state.config
	v.database = state.database
	v.phase = state.phase
	v.turn_number = state.turn_number
	v.current_player_index = state.current_player_index
	v.deck_size = state.deck.size()
	v.discard_pile = state.discard_pile.duplicate()

	var me: Player = state.players[viewer_index]
	v.own_hand = me.hand.duplicate()
	v.own_recipes = me.recipes
	v.own_steals_used = me.steals_used

	for p in state.players:
		if p.index == viewer_index:
			continue
		var ov := OpponentView.new()
		ov.player_index = p.index
		ov.team_id = p.team_id
		ov.hand_count = p.hand.size()
		ov.steals_used = p.steals_used
		for ri in p.recipes.size():
			var recipe: Recipe = p.recipes[ri]
			var rv := RecipeView.new()
			rv.def = recipe.def
			rv.recipe_index = ri
			rv.attached_ingredients = recipe.filled_ingredients.values()
			rv.attached_preparations = recipe.filled_preparations.values()
			rv.decoy_cards = recipe.decoys.duplicate()
			rv.completed = recipe.completed
			ov.recipes.append(rv)
		v.opponents.append(ov)

	return v

func find_opponent(player_index: int) -> OpponentView:
	for ov in opponents:
		if ov.player_index == player_index:
			return ov
	return null

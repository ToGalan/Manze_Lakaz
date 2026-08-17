class_name AiBot
extends RefCounted
## Base interface for a gameplay AI opponent. The no-cheat guarantee is
## structural, not just a convention: choose_action() is the only entry
## point and it immediately narrows the real GameState down to a
## PublicGameView before handing off to _decide(), which is the only place
## difficulty-specific strategy lives. _decide() never receives GameState,
## so it has no way to read another seat's hand even by mistake.

enum Difficulty { EASY, MEDIUM, HARD }

const DIFFICULTY_NAMES := {
	Difficulty.EASY: "Easy",
	Difficulty.MEDIUM: "Medium",
	Difficulty.HARD: "Hard",
}

var player_index: int
var rng: RandomNumberGenerator

func _init(p_player_index: int) -> void:
	player_index = p_player_index
	rng = RandomNumberGenerator.new()
	rng.randomize()

func choose_action(state: GameState, legal_actions: Array[Action]) -> Action:
	if legal_actions.is_empty():
		return null
	var view := PublicGameView.from_state(state, player_index)
	return _decide(view, legal_actions)

## Override in subclasses. Must use only what `view` exposes.
func _decide(view: PublicGameView, legal_actions: Array[Action]) -> Action:
	push_error("AiBot._decide is abstract; use EasyBot, MediumBot, or HardBot")
	return null

static func create(difficulty: int, player_index: int) -> AiBot:
	match difficulty:
		Difficulty.EASY:
			return EasyBot.new(player_index)
		Difficulty.MEDIUM:
			return MediumBot.new(player_index)
		Difficulty.HARD:
			return HardBot.new(player_index)
	push_error("AiBot.create: unknown difficulty %s" % str(difficulty))
	return null

## Shared by Medium/Hard: at draft time there is no board state yet to
## reason about, so both fall back to preferring whichever offered recipe
## has the fewest total required components (faster to realistically finish).
func _choose_fewest_slots_draft(view: PublicGameView, legal_actions: Array[Action]) -> Action:
	var best: Action = null
	var best_slots := 999999
	for a in legal_actions:
		var def: RecipeDef = view.database.recipe_defs[a.recipe_id]
		var slots := def.total_required_slots()
		if slots < best_slots:
			best = a
			best_slots = slots
	return best

## Shared by Medium/Hard for the PLAY phase: always attach if any attach is
## legal (preferring a real fill over a decoy), otherwise discard whichever
## legal card is least useful to the bot's own recipes. Hard's opponent
## modelling only changes STEAL target selection in the TAKE phase, not this.
func _choose_greedy_attach_or_discard(view: PublicGameView, legal_actions: Array[Action]) -> Action:
	var attach_actions: Array[Action] = []
	var discard_actions: Array[Action] = []
	for a in legal_actions:
		if a.type == Action.Type.ATTACH:
			attach_actions.append(a)
		elif a.type == Action.Type.DISCARD:
			discard_actions.append(a)

	if not attach_actions.is_empty():
		for a in attach_actions:
			if not a.as_decoy:
				return a
		return attach_actions[0]

	return _choose_least_useful_discard(view, discard_actions)

func _choose_least_useful_discard(view: PublicGameView, discard_actions: Array[Action]) -> Action:
	var best: Action = null
	var best_score := 999999
	for a in discard_actions:
		var card := _find_in_hand(view, a.card_instance_id)
		var score := _usefulness_score(view, card)
		if best == null or score < best_score:
			best = a
			best_score = score
	return best

func _usefulness_score(view: PublicGameView, card: Card) -> int:
	var joker_type := _joker_ingredient_type(view, card)
	var score := 0
	for recipe in view.own_recipes:
		if recipe.completed:
			continue
		if joker_type != "":
			if _recipe_has_open_slot_of_type(view, recipe, joker_type):
				score += 1
		elif card.is_ingredient() and recipe.is_ingredient_slot_open(card.def_id):
			score += 1
		elif card.is_preparation() and recipe.is_preparation_slot_open(card.def_id):
			score += 1
	return score

## Non-empty only for a joker ingredient card -- its ingredient_type, the
## category of open slot it can fill in place of one specific ingredient.
func _joker_ingredient_type(view: PublicGameView, card: Card) -> String:
	if not card.is_ingredient():
		return ""
	var def := view.database.get_ingredient_def(card.def_id)
	return def.ingredient_type if def != null and def.is_joker else ""

func _recipe_has_open_slot_of_type(view: PublicGameView, recipe: Recipe, ingredient_type: String) -> bool:
	for req_id in recipe.def.ingredient_ids:
		if not recipe.is_ingredient_slot_open(req_id):
			continue
		var req_def := view.database.get_ingredient_def(req_id)
		if req_def != null and req_def.ingredient_type == ingredient_type:
			return true
	return false

func _find_in_hand(view: PublicGameView, card_instance_id: int) -> Card:
	for c in view.own_hand:
		if c.instance_id == card_instance_id:
			return c
	return null

func _own_open_ingredient_slot(view: PublicGameView, def_id: String) -> bool:
	var def := view.database.get_ingredient_def(def_id)
	if def != null and def.is_joker:
		for recipe in view.own_recipes:
			if not recipe.completed and _recipe_has_open_slot_of_type(view, recipe, def.ingredient_type):
				return true
		return false
	for recipe in view.own_recipes:
		if recipe.completed:
			continue
		if recipe.is_ingredient_slot_open(def_id):
			return true
	return false

func _steal_target_card(view: PublicGameView, action: Action) -> Card:
	var ov := view.find_opponent(action.target_player_index)
	if ov == null:
		return null
	for rv in ov.recipes:
		if rv.recipe_index == action.target_recipe_index:
			return rv.find_card(action.card_instance_id)
	return null

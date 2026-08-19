class_name GameViewModel
extends RefCounted
## Pure display formatting for GameScreen.gd. Everything here reads
## GameState/CardDatabase/Action and produces strings or plain data for
## rendering. Nothing here decides what is legal -- that is always
## get_legal_actions()'s job. If a function here ever needs to answer "is
## this allowed", that's a sign it belongs in core/, not here.

## "Player 2 must Draw or Steal" -- built purely from which Action.Type
## values are present in the current legal action list, so it can never
## drift out of sync with what the engine will actually accept.
static func status_text(state: GameState, legal_actions: Array[Action]) -> String:
	if state.game_over:
		return _winner_headline(state)

	var player_num := state.current_player_index + 1

	if state.phase == GameState.Phase.DRAFT:
		var player: Player = state.players[state.current_player_index]
		return "Player %d must choose a recipe to keep (%d/%d kept)" % [player_num, player.recipes.size(), state.config.recipes_per_player]

	var types_present: Dictionary = {}
	for a in legal_actions:
		types_present[a.type] = true

	var verbs: Array[String] = []
	if types_present.has(Action.Type.DRAW):
		verbs.append("Draw")
	if types_present.has(Action.Type.STEAL):
		verbs.append("Steal")
	if types_present.has(Action.Type.TAKE_DISCARD):
		verbs.append("Take Discard")
	if types_present.has(Action.Type.ATTACH):
		verbs.append("Attach")
	if types_present.has(Action.Type.DISCARD):
		verbs.append("Discard")
	if types_present.has(Action.Type.MOVE_PREPARATION):
		verbs.append("Move Preparation")

	if verbs.is_empty():
		return "Player %d has no legal actions" % player_num
	return "Player %d must %s" % [player_num, " or ".join(verbs)]

static func _winner_headline(state: GameState) -> String:
	if state.winner_player_index >= 0:
		var wp: Player = state.players[state.winner_player_index]
		var rec := wp.completed_recipe()
		var recipe_name := rec.def.display_name if rec != null else "a recipe"
		return "Player %d wins with %s!" % [state.winner_player_index + 1, recipe_name]
	if state.winner_team_id >= 0:
		return "Team %d wins!" % (state.winner_team_id + 1)
	return "Game over."

static func steals_remaining(state: GameState, player: Player) -> int:
	return max(0, state.config.max_steals_per_player - player.steals_used)

static func card_label(def_id: String, category: int, db: CardDatabase) -> String:
	var def := db.get_card_def(def_id, category)
	return def.display_name if def != null else def_id

static func recipe_title(def: RecipeDef) -> String:
	return "%s (%s)" % [def.display_name, def.tier_name().capitalize()]

## The real-world recipe reveal shown when a dish is completed in-game:
## every real ingredient with its quantity, plus prep/cook/total time as
## "Xh Ym" (or "Ym" under an hour). Always looked up from the CardDatabase
## rather than a specific Recipe instance's own .def, since this is static
## flavor data that's identical for every copy of a dish -- including
## reconstructed opponent recipes online, whose .def is otherwise stripped
## down to only what's actually visible on the table.
static func real_recipe_view(recipe_id: String, db: CardDatabase) -> Dictionary:
	var def: RecipeDef = db.recipe_defs[recipe_id]
	return {
		"recipe_id": recipe_id,
		"display_name": def.display_name,
		"tier_name": def.tier_name(),
		"title": recipe_title(def),
		"country": def.country,
		"ingredients": def.real_ingredients.duplicate(true),
		"steps": def.prep_steps.duplicate(),
		"prep_time": _format_minutes(def.prep_time_minutes),
		"cook_time": _format_minutes(def.cook_time_minutes),
		"total_time": _format_minutes(def.total_time_minutes()),
	}

static func _format_minutes(minutes: int) -> String:
	if minutes <= 0:
		return "--"
	if minutes < 60:
		return "%dm" % minutes
	var h := minutes / 60
	var m := minutes % 60
	return ("%dh %dm" % [h, m]) if m > 0 else "%dh" % h

## Own-recipe view: every required slot, filled or not. Used only for the
## acting player's own recipes.
## Returns Array[{label: String, filled: bool, is_ingredient: bool}]
static func own_recipe_slots(recipe: Recipe, db: CardDatabase) -> Array:
	var slots: Array = []
	for iid in recipe.def.ingredient_ids:
		var filled_card: Card = recipe.filled_ingredients.get(iid)
		slots.append({
			"label": card_label(iid, CardDef.Category.INGREDIENT, db),
			"filled": filled_card != null,
			"is_ingredient": true,
			"card_instance_id": filled_card.instance_id if filled_card != null else -1,
		})
	for pid in recipe.def.preparation_ids:
		var filled_card: Card = recipe.filled_preparations.get(pid)
		slots.append({
			"label": card_label(pid, CardDef.Category.PREPARATION, db),
			"filled": filled_card != null,
			"is_ingredient": false,
			"card_instance_id": filled_card.instance_id if filled_card != null else -1,
		})
	if recipe.def.uses_grill:
		slots.append({"label": "Grill (free)", "filled": true, "is_ingredient": false, "card_instance_id": -1})
	return slots

## Other-player-recipe view: only cards actually attached, nothing about
## what's still required. Includes decoys with no distinction from
## required fills, since which slots exist at all is itself hidden info.
## Returns Array[{label: String, card_instance_id: int, def_id: String, category: int}]
static func other_recipe_attachments(recipe: Recipe, db: CardDatabase) -> Array:
	var out: Array = []
	for c in recipe.all_attached_ingredient_cards():
		out.append({"label": card_label(c.def_id, c.category, db), "card_instance_id": c.instance_id, "def_id": c.def_id, "category": c.category})
	for c in recipe.filled_preparations.values():
		out.append({"label": card_label(c.def_id, c.category, db), "card_instance_id": c.instance_id, "def_id": c.def_id, "category": c.category})
	return out

## Full detail of one player's own draft offer -- fully visible to them,
## it's their own pending decision. Returns Array[{recipe_id, title, ingredients: Array[String], preparations: Array[String]}]
static func draft_offer_view(state: GameState, player_index: int) -> Array:
	var db := state.database
	var out: Array = []
	for rid in state.draft_offers[player_index]:
		var def: RecipeDef = db.recipe_defs[rid]
		var ingredient_names: Array[String] = []
		for iid in def.ingredient_ids:
			ingredient_names.append(card_label(iid, CardDef.Category.INGREDIENT, db))
		var prep_names: Array[String] = []
		for pid in def.preparation_ids:
			prep_names.append(card_label(pid, CardDef.Category.PREPARATION, db))
		out.append({
			"recipe_id": rid,
			"title": recipe_title(def),
			"display_name": def.display_name,
			"country": def.country,
			"tier_name": def.tier_name(),
			"ingredients": ingredient_names,
			"preparations": prep_names,
			"uses_grill": def.uses_grill,
		})
	return out

## Human-readable log line for an action, resolved from state BEFORE the
## action is applied (so hand/board lookups still find the card).
static func describe_action_for_log(state: GameState, action: Action) -> String:
	var db := state.database
	var actor := "Player %d" % (action.player_index + 1)
	match action.type:
		Action.Type.DRAFT_KEEP:
			var def: RecipeDef = db.recipe_defs[action.recipe_id]
			return "%s kept recipe %s" % [actor, recipe_title(def)]
		Action.Type.DRAW:
			return "%s drew a card" % actor
		Action.Type.TAKE_DISCARD:
			var card := state.discard_pile[state.discard_pile.size() - 1] if not state.discard_pile.is_empty() else null
			var card_name := card_label(card.def_id, card.category, db) if card != null else "a card"
			return "%s took %s from the discard pile" % [actor, card_name]
		Action.Type.STEAL:
			var target: Player = state.players[action.target_player_index]
			var recipe: Recipe = target.recipes[action.target_recipe_index]
			var card := recipe.find_attached_card(action.card_instance_id)
			var card_name := card_label(card.def_id, card.category, db) if card != null else "a card"
			return "%s stole %s from Player %d's %s" % [actor, card_name, action.target_player_index + 1, recipe.def.display_name]
		Action.Type.ATTACH:
			var player: Player = state.players[action.player_index]
			var card := player.find_in_hand(action.card_instance_id)
			var card_name := card_label(card.def_id, card.category, db) if card != null else "a card"
			var recipe: Recipe = player.recipes[action.recipe_index]
			var decoy_note := " as a decoy" if action.as_decoy else ""
			return "%s attached %s to %s%s" % [actor, card_name, recipe.def.display_name, decoy_note]
		Action.Type.DISCARD:
			var player: Player = state.players[action.player_index]
			var card := player.find_in_hand(action.card_instance_id)
			var card_name := card_label(card.def_id, card.category, db) if card != null else "a card"
			return "%s discarded %s" % [actor, card_name]
		Action.Type.MOVE_PREPARATION:
			var player: Player = state.players[action.player_index]
			var from_recipe: Recipe = player.recipes[action.recipe_index]
			var card := from_recipe.find_attached_card(action.card_instance_id)
			var card_name := card_label(card.def_id, card.category, db) if card != null else "a preparation"
			var to_recipe: Recipe = player.recipes[action.move_to_recipe_index]
			return "%s moved %s to %s" % [actor, card_name, to_recipe.def.display_name]
	return "%s took an action" % actor

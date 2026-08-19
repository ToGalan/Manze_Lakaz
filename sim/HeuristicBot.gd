class_name HeuristicBot
extends Bot
## Simple heuristic: attach if legal, else steal a card you need, else draw,
## else discard your least useful card.

func choose_action(state: GameState, legal_actions: Array[Action]) -> Action:
	if legal_actions.is_empty():
		return null
	var player: Player = state.players[state.current_player_index]
	if state.phase == GameState.Phase.DRAFT:
		return _choose_draft(state, legal_actions)
	if state.phase == GameState.Phase.TAKE:
		return _choose_take(state, player, legal_actions)
	return _choose_play_or_discard(state, player, legal_actions)

## Keeps whichever offered recipe has the fewest total required
## ingredients+preparations -- a simple bias toward faster-to-complete
## recipes, since the draft happens before any hand is dealt.
func _choose_draft(state: GameState, legal_actions: Array[Action]) -> Action:
	var best: Action = null
	var best_slots := -1
	for a in legal_actions:
		var def: RecipeDef = state.database.recipe_defs[a.recipe_id]
		var slots := def.total_required_slots()
		if best == null or slots < best_slots:
			best = a
			best_slots = slots
	return best

func _choose_take(state: GameState, player: Player, legal_actions: Array[Action]) -> Action:
	var needed_steal: Action = null
	var any_steal: Action = null
	var draw_action: Action = null

	for a in legal_actions:
		if a.type == Action.Type.STEAL:
			if any_steal == null:
				any_steal = a
			if needed_steal == null:
				var target: Player = state.players[a.target_player_index]
				var recipe: Recipe = target.recipes[a.target_recipe_index]
				var card := recipe.find_attached_card(a.card_instance_id)
				if card != null and _player_needs_ingredient(player, card.def_id):
					needed_steal = a
		elif a.type == Action.Type.DRAW:
			draw_action = a

	if needed_steal != null:
		return needed_steal
	if draw_action != null:
		return draw_action
	if any_steal != null:
		return any_steal
	return legal_actions[0]

func _player_needs_ingredient(player: Player, def_id: String) -> bool:
	for recipe in player.recipes:
		if recipe.completed:
			continue
		if recipe.is_ingredient_slot_open(def_id):
			return true
	return false

func _choose_play_or_discard(state: GameState, player: Player, legal_actions: Array[Action]) -> Action:
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

	return _choose_least_useful_discard(player, discard_actions)

func _choose_least_useful_discard(player: Player, discard_actions: Array[Action]) -> Action:
	var best: Action = null
	var best_score := -1
	for a in discard_actions:
		var card := player.find_in_hand(a.card_instance_id)
		var score := _usefulness_score(player, card)
		if best == null or score < best_score:
			best = a
			best_score = score
	return best

func _usefulness_score(player: Player, card: Card) -> int:
	var score := 0
	for recipe in player.recipes:
		if recipe.completed:
			continue
		if card.is_ingredient() and recipe.is_ingredient_slot_open(card.def_id):
			score += 1
		elif card.is_preparation() and recipe.is_preparation_slot_open(card.def_id):
			score += 1
	return score

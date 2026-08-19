class_name MediumBot
extends AiBot
## Greedy: always attach if possible. Steal a card it needs if one is
## visible. Otherwise draw. Discard the card least useful to either of its
## recipes.

func _decide(view: PublicGameView, legal_actions: Array[Action]) -> Action:
	match view.phase:
		GameState.Phase.DRAFT:
			return _choose_fewest_slots_draft(view, legal_actions)
		GameState.Phase.TAKE:
			return _choose_take(view, legal_actions)
		_:
			return _choose_greedy_attach_or_discard(view, legal_actions)

func _choose_take(view: PublicGameView, legal_actions: Array[Action]) -> Action:
	var needed_steal: Action = null
	var any_steal: Action = null
	var draw_action: Action = null

	for a in legal_actions:
		if a.type == Action.Type.STEAL:
			if any_steal == null:
				any_steal = a
			if needed_steal == null:
				var card := _steal_target_card(view, a)
				if card != null and _own_open_ingredient_slot(view, card.def_id):
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

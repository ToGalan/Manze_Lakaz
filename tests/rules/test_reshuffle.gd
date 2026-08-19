extends RefCounted
## Rule: if the deck empties, shuffle the discard pile to form a new deck.

func test_draw_with_empty_deck_reshuffles_discard_pile() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	state.deck = []
	state.discard_pile = [
		alloc.call("salt", CardDef.Category.INGREDIENT),
		alloc.call("oil", CardDef.Category.INGREDIENT),
		alloc.call("fish", CardDef.Category.INGREDIENT),
	]
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	var has_draw := false
	for a in legal:
		if a.type == Action.Type.DRAW:
			has_draw = true
	TestUtil.assert_true(has_draw, "DRAW should still be legal when the deck is empty but the discard pile is not")

	var hand_before: int = state.players[0].hand.size()
	RulesEngine.apply_action(state, Action.make_draw(0))

	TestUtil.assert_eq(state.reshuffle_count, 1, "drawing with an empty deck should trigger exactly one reshuffle")
	TestUtil.assert_eq(state.discard_pile.size(), 0, "the discard pile should be emptied into the deck on reshuffle")
	TestUtil.assert_eq(state.deck.size(), 2, "3 reshuffled cards minus the 1 drawn should leave 2 in the deck")
	TestUtil.assert_eq(state.players[0].hand.size(), hand_before + 1, "the draw itself should still succeed after reshuffling")

func test_draw_unavailable_with_empty_deck_and_empty_discard() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])

	state.deck = []
	state.discard_pile = []
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	for a in legal:
		TestUtil.assert_ne(a.type, Action.Type.DRAW, "DRAW must not be offered when both the deck and discard pile are empty")

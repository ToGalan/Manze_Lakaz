extends RefCounted
## Rule: after Step 2 (and after every subsequent forced discard), a player
## must discard down to config.hand_limit before their turn ends.

func test_over_limit_hand_forces_repeated_discards_then_ends_turn() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	config.hand_limit = 3
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	# "salt" is not required by dish_a, so every card here is discard-only:
	# no ATTACH action can ever be legal for it, keeping this test focused
	# purely on hand-limit enforcement.
	var cards: Array[Card] = []
	for i in 5:
		cards.append(alloc.call("salt", CardDef.Category.INGREDIENT))
	p0.hand = cards.duplicate()

	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	# Step 2: discard one card. 5 -> 4, still over the limit of 3.
	var legal := RulesEngine.get_legal_actions(state)
	TestUtil.assert_true(legal.size() == 5, "with nothing attachable, every hand card should offer exactly a DISCARD action")
	RulesEngine.apply_action(state, Action.make_discard(0, p0.hand[0].instance_id))

	TestUtil.assert_eq(p0.hand.size(), 4, "hand should shrink by one after the Step 2 discard")
	TestUtil.assert_eq(state.phase, GameState.Phase.HAND_LIMIT, "hand of 4 over a limit of 3 must trigger the hand-limit phase")
	TestUtil.assert_eq(state.current_player_index, 0, "hand-limit discards belong to the same player's turn")

	# Forced hand-limit discard: 4 -> 3, now at the limit.
	RulesEngine.apply_action(state, Action.make_discard(0, p0.hand[0].instance_id))

	TestUtil.assert_eq(p0.hand.size(), 3, "hand should be exactly at the limit")
	TestUtil.assert_eq(state.phase, GameState.Phase.TAKE, "reaching the limit should end the turn and return to TAKE")
	TestUtil.assert_eq(state.current_player_index, 1, "turn should pass to the next player")

func test_hand_at_or_under_limit_does_not_trigger_hand_limit_phase() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	config.hand_limit = 7
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	p0.hand = [alloc.call("salt", CardDef.Category.INGREDIENT)]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	RulesEngine.apply_action(state, Action.make_discard(0, p0.hand[0].instance_id))

	TestUtil.assert_eq(state.phase, GameState.Phase.TAKE, "a hand already under the limit should skip straight to the next player's TAKE phase")
	TestUtil.assert_eq(state.current_player_index, 1, "turn should pass to the next player")

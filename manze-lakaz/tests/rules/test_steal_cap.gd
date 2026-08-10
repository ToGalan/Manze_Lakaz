extends RefCounted
## Rule: a player may perform the STEAL action at most
## config.max_steals_per_player times over the whole game. Once reached,
## STEAL simply stops being offered to that player; DRAW/TAKE_DISCARD are
## unaffected, and other players' steal budgets are untouched.

func test_steal_offered_until_cap_then_withheld() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	config.max_steals_per_player = 2
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0] # dish_b: salt + oil, prep chopping

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	# Steal #1: still under the cap of 2.
	recipe1.attach_ingredient_to_slot(alloc.call("salt", CardDef.Category.INGREDIENT))
	var legal := RulesEngine.get_legal_actions(state)
	var has_steal := false
	for a in legal:
		if a.type == Action.Type.STEAL:
			has_steal = true
	TestUtil.assert_true(has_steal, "STEAL should be offered before the cap is reached")

	var steal1: Action = null
	for a in legal:
		if a.type == Action.Type.STEAL:
			steal1 = a
	RulesEngine.apply_action(state, steal1)
	TestUtil.assert_eq(p0.steals_used, 1, "steals_used should increment after a successful steal")

	# Back to player 0's TAKE phase for a controlled second steal.
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE
	recipe1.attach_ingredient_to_slot(alloc.call("oil", CardDef.Category.INGREDIENT))

	legal = RulesEngine.get_legal_actions(state)
	var steal2: Action = null
	for a in legal:
		if a.type == Action.Type.STEAL:
			steal2 = a
	TestUtil.assert_true(steal2 != null, "STEAL should still be offered on the 2nd steal (== cap)")
	RulesEngine.apply_action(state, steal2)
	TestUtil.assert_eq(p0.steals_used, 2, "steals_used should be 2 after the 2nd steal")

	# Player 0 has now used both of their 2 allowed steals; even with a
	# stealable card sitting right there, STEAL must not be offered again.
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE
	recipe1.attach_ingredient_to_slot(alloc.call("salt", CardDef.Category.INGREDIENT))

	legal = RulesEngine.get_legal_actions(state)
	for a in legal:
		TestUtil.assert_ne(a.type, Action.Type.STEAL, "STEAL must not be offered once a player has reached their steal cap")

func test_steal_cap_is_tracked_per_player_not_globally() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	config.max_steals_per_player = 1
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])

	var p0: Player = state.players[0]
	var p1: Player = state.players[1]
	p0.steals_used = 1 # player 0 already exhausted their budget

	var recipe0: Recipe = p0.recipes[0] # dish_a: oil + fish, prep grinding
	recipe0.attach_ingredient_to_slot(Card.new(500, "oil", CardDef.Category.INGREDIENT))

	state.current_player_index = 1
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	var has_steal := false
	for a in legal:
		if a.type == Action.Type.STEAL:
			has_steal = true
	TestUtil.assert_true(has_steal, "player 1's own steal budget should be untouched by player 0 exhausting theirs")
	TestUtil.assert_eq(p1.steals_used, 0, "player 1 should have no steals recorded yet")

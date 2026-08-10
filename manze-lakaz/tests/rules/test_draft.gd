extends RefCounted
## Rule: recipe draft. Each player is offered draft_pool_size recipes and
## keeps recipes_per_player of them one at a time; whichever offered
## recipes they don't keep are simply left behind. Only once every player
## has finished drafting do hands get dealt and turn 1 begin.

func test_draft_offers_and_sequential_keeps() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var state := RulesEngine.new_game(config, db)

	TestUtil.assert_eq(state.phase, GameState.Phase.DRAFT, "a new game should start in the DRAFT phase")
	TestUtil.assert_eq(state.current_player_index, 0, "player 0 should draft first")
	TestUtil.assert_eq(state.draft_offers[0].size(), 3, "player 0 should be offered draft_pool_size recipes")
	TestUtil.assert_eq(state.draft_offers[1].size(), 3, "player 1 should be offered draft_pool_size recipes")
	TestUtil.assert_eq(state.players[0].hand.size(), 0, "hands must not be dealt until the draft is finished")

	var legal := RulesEngine.get_legal_actions(state)
	TestUtil.assert_eq(legal.size(), 3, "player 0 should have exactly 3 legal DRAFT_KEEP choices")
	for a in legal:
		TestUtil.assert_eq(a.type, Action.Type.DRAFT_KEEP, "every legal draft action should be a DRAFT_KEEP")
		TestUtil.assert_eq(a.player_index, 0, "player 0's draft actions must belong to player 0")

	# Player 0 keeps their first pick.
	var first_pick: String = state.draft_offers[0][0]
	RulesEngine.apply_action(state, Action.make_draft_keep(0, first_pick))

	TestUtil.assert_eq(state.players[0].recipes.size(), 1, "player 0 should have kept one recipe")
	TestUtil.assert_eq(state.phase, GameState.Phase.DRAFT, "still drafting after only one of two keeps")
	TestUtil.assert_eq(state.current_player_index, 0, "player 0 still needs a second pick before the turn passes")
	TestUtil.assert_eq(state.draft_offers[0].size(), 2, "the kept recipe should be removed from the remaining offer")

	# Player 0 keeps their second pick; recipes_per_player (2) is now met,
	# so drafting should move on to player 1.
	var second_pick: String = state.draft_offers[0][0]
	RulesEngine.apply_action(state, Action.make_draft_keep(0, second_pick))

	TestUtil.assert_eq(state.players[0].recipes.size(), 2, "player 0 should have kept exactly recipes_per_player recipes")
	TestUtil.assert_eq(state.current_player_index, 1, "drafting should now move to player 1")
	TestUtil.assert_eq(state.phase, GameState.Phase.DRAFT, "still drafting: player 1 hasn't picked yet")

func test_draft_finishes_and_deals_hands_after_last_player() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var state := RulesEngine.new_game(config, db)

	for p in 2:
		for i in config.recipes_per_player:
			var pick: String = state.draft_offers[p][0]
			RulesEngine.apply_action(state, Action.make_draft_keep(p, pick))

	TestUtil.assert_eq(state.phase, GameState.Phase.TAKE, "once the last player finishes drafting, the game should move to TAKE")
	TestUtil.assert_eq(state.current_player_index, 0, "turn 1 should belong to player 0")
	TestUtil.assert_eq(state.turn_number, 1, "turn counter should start fresh at 1")
	for p in state.players:
		TestUtil.assert_eq(p.hand.size(), 7, "every player's hand should be dealt to 7 once drafting finishes")
		TestUtil.assert_eq(p.recipes.size(), config.recipes_per_player, "every player should have kept recipes_per_player recipes")

func test_cannot_keep_a_recipe_not_in_own_offer() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var state := RulesEngine.new_game(config, db)

	var legal := RulesEngine.get_legal_actions(state)
	var offered_ids: Array = state.draft_offers[0]
	for a in legal:
		TestUtil.assert_true(offered_ids.has(a.recipe_id), "a legal DRAFT_KEEP must only ever name a recipe actually offered to that player")

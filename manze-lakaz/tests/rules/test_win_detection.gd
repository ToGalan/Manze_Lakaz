extends RefCounted
## Rule: FFA - first player to complete either of their two recipes wins
## immediately. Team mode - the team wins only once both partners have each
## completed a recipe.

func test_ffa_win_on_first_completed_recipe() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	config.win_on_both_recipes = false
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var recipe0: Recipe = p0.recipes[0] # dish_a: oil + fish, prep grinding
	var oil_card: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	var fish_card: Card = alloc.call("fish", CardDef.Category.INGREDIENT)
	var grinding_card: Card = alloc.call("grinding", CardDef.Category.PREPARATION)
	recipe0.attach_ingredient_to_slot(oil_card)
	recipe0.attach_ingredient_to_slot(fish_card)

	p0.hand = [grinding_card]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	TestUtil.assert_false(state.game_over, "game should not be over before the last required card is attached")

	RulesEngine.apply_action(state, Action.make_attach(0, grinding_card.instance_id, 0, false))

	TestUtil.assert_true(state.game_over, "completing a recipe in FFA mode should end the game immediately")
	TestUtil.assert_eq(state.winner_player_index, 0, "the player who completed the recipe should be recorded as the winner")
	TestUtil.assert_true(recipe0.completed, "the recipe itself should be marked completed")

func test_team_mode_requires_both_partners_to_complete() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	config.num_players = 4
	config.win_on_both_recipes = true
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b", "dish_a", "dish_b"])
	RulesEngine._assign_teams(state) # seats 0&2 vs 1&3
	var alloc := TestFixtures.make_card_allocator()

	# Player 0 (team 0) completes their recipe first.
	var p0: Player = state.players[0]
	var recipe0: Recipe = p0.recipes[0] # dish_a: oil + fish, prep grinding
	recipe0.attach_ingredient_to_slot(alloc.call("oil", CardDef.Category.INGREDIENT))
	recipe0.attach_ingredient_to_slot(alloc.call("fish", CardDef.Category.INGREDIENT))
	var grinding_card: Card = alloc.call("grinding", CardDef.Category.PREPARATION)
	p0.hand = [grinding_card]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY
	RulesEngine.apply_action(state, Action.make_attach(0, grinding_card.instance_id, 0, false))

	TestUtil.assert_true(recipe0.completed, "player 0's recipe should be complete")
	TestUtil.assert_false(state.game_over, "team should not win until BOTH partners have completed a recipe")

	# Player 2 (team 0, player 0's partner) now completes their recipe too.
	var p2: Player = state.players[2]
	var recipe2: Recipe = p2.recipes[0] # dish_a: oil + fish, prep grinding
	recipe2.attach_ingredient_to_slot(alloc.call("oil", CardDef.Category.INGREDIENT))
	recipe2.attach_ingredient_to_slot(alloc.call("fish", CardDef.Category.INGREDIENT))
	var grinding_card2: Card = alloc.call("grinding", CardDef.Category.PREPARATION)
	p2.hand = [grinding_card2]
	state.current_player_index = 2
	state.phase = GameState.Phase.PLAY
	RulesEngine.apply_action(state, Action.make_attach(2, grinding_card2.instance_id, 0, false))

	TestUtil.assert_true(state.game_over, "the team should win once both partners have completed a recipe")
	TestUtil.assert_eq(state.winner_team_id, 0, "team 0 (seats 0 and 2) should be recorded as the winner")

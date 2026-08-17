extends RefCounted
## Rule: a preparation card already attached to one of a player's own
## recipes can be relocated to another of their own recipes (MOVE_PREPARATION),
## as a PLAY-phase alternative to ATTACH/DISCARD. It can never be moved off a
## completed recipe (frozen, same as STEAL already treats a completed
## recipe), and it can only land on another of the player's own recipes that
## has an open slot for that exact preparation def_id. It is never offered
## to move preparations belonging to another player.

func test_move_preparation_between_own_recipes_relocates_card() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"]) # dish_a: oil+fish/grinding
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var recipe0: Recipe = player.recipes[0] # dish_a
	player.recipes.append(Recipe.new(db.recipe_defs["dish_c"])) # oil+salt/grinding
	var recipe1: Recipe = player.recipes[1]

	var grinding_card: Card = alloc.call("grinding", CardDef.Category.PREPARATION)
	recipe0.attach_preparation_to_slot(grinding_card)

	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	var move_action: Action = null
	for a in legal:
		if a.type == Action.Type.MOVE_PREPARATION and a.card_instance_id == grinding_card.instance_id and a.move_to_recipe_index == 1:
			move_action = a
			break

	TestUtil.assert_true(move_action != null, "moving an attached preparation to another of the player's own recipes that needs it should be legal")
	TestUtil.assert_eq(move_action.recipe_index, 0, "the move action should record which recipe the card is currently on")

	RulesEngine.apply_action(state, move_action)

	TestUtil.assert_false(recipe0.filled_preparations.has("grinding"), "the source recipe should no longer have the preparation attached")
	TestUtil.assert_true(recipe1.filled_preparations.has("grinding"), "the destination recipe should now have the preparation attached")
	TestUtil.assert_eq(recipe1.filled_preparations["grinding"].instance_id, grinding_card.instance_id, "the exact same card instance should have moved, not a new one")

func test_cannot_move_preparation_off_a_completed_recipe() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var recipe0: Recipe = player.recipes[0] # dish_a: oil+fish/grinding
	recipe0.attach_ingredient_to_slot(alloc.call("oil", CardDef.Category.INGREDIENT))
	recipe0.attach_ingredient_to_slot(alloc.call("fish", CardDef.Category.INGREDIENT))
	recipe0.attach_preparation_to_slot(alloc.call("grinding", CardDef.Category.PREPARATION))
	TestUtil.assert_true(recipe0.completed, "recipe should be complete once every required slot is filled")

	player.recipes.append(Recipe.new(db.recipe_defs["dish_c"])) # also needs grinding

	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	for a in legal:
		if a.type == Action.Type.MOVE_PREPARATION:
			TestUtil.assert_ne(a.recipe_index, 0, "a preparation on a completed recipe must never be offered for MOVE_PREPARATION")

func test_cannot_move_preparation_to_a_recipe_that_does_not_need_it() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var recipe0: Recipe = player.recipes[0] # dish_a: needs grinding
	player.recipes.append(Recipe.new(db.recipe_defs["dish_b"])) # needs chopping, not grinding
	var grinding_card: Card = alloc.call("grinding", CardDef.Category.PREPARATION)
	recipe0.attach_preparation_to_slot(grinding_card)

	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	for a in legal:
		if a.type == Action.Type.MOVE_PREPARATION and a.card_instance_id == grinding_card.instance_id:
			TestUtil.assert_ne(a.move_to_recipe_index, 1, "grinding should never be offered as movable onto a recipe that requires chopping instead")

func test_move_preparation_not_offered_with_only_one_recipe() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var recipe0: Recipe = player.recipes[0]
	recipe0.attach_preparation_to_slot(alloc.call("grinding", CardDef.Category.PREPARATION))

	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	for a in legal:
		TestUtil.assert_ne(a.type, Action.Type.MOVE_PREPARATION, "a player with only one recipe has nowhere to move a preparation to")

func test_move_preparation_can_complete_the_destination_recipe() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	config.win_on_both_recipes = false
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var recipe0: Recipe = player.recipes[0] # dish_a: oil+fish/grinding -- left incomplete
	var grinding_card: Card = alloc.call("grinding", CardDef.Category.PREPARATION)
	recipe0.attach_preparation_to_slot(grinding_card)

	player.recipes.append(Recipe.new(db.recipe_defs["dish_c"])) # oil+salt/grinding
	var recipe1: Recipe = player.recipes[1]
	recipe1.attach_ingredient_to_slot(alloc.call("oil", CardDef.Category.INGREDIENT))
	recipe1.attach_ingredient_to_slot(alloc.call("salt", CardDef.Category.INGREDIENT))
	TestUtil.assert_false(recipe1.completed, "destination recipe should still be missing its preparation before the move")

	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	var move_action: Action = null
	for a in legal:
		if a.type == Action.Type.MOVE_PREPARATION and a.card_instance_id == grinding_card.instance_id and a.move_to_recipe_index == 1:
			move_action = a
			break
	TestUtil.assert_true(move_action != null, "the move completing the destination recipe should still be legal")

	RulesEngine.apply_action(state, move_action)

	TestUtil.assert_true(recipe1.completed, "the destination recipe should be complete once the moved preparation fills its last slot")
	TestUtil.assert_true(state.game_over, "completing a recipe via MOVE_PREPARATION should end the game in FFA mode exactly like ATTACH would")
	TestUtil.assert_eq(state.winner_player_index, 0, "the player who completed the recipe should be recorded as the winner")

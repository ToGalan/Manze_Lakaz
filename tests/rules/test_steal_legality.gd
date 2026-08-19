extends RefCounted
## Rule: only Ingredient cards attached to another player's recipe can be
## stolen. Preparation cards can never be stolen. Cards attached to a
## completed recipe can never be stolen. A player cannot steal from
## themselves.

func test_only_stealable_ingredients_are_offered() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0] # dish_b: salt + oil, prep chopping

	var salt_card: Card = alloc.call("salt", CardDef.Category.INGREDIENT)
	var chopping_card: Card = alloc.call("chopping", CardDef.Category.PREPARATION)
	recipe1.attach_ingredient_to_slot(salt_card)
	recipe1.attach_preparation_to_slot(chopping_card)

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	var steal_targets := []
	for a in legal:
		if a.type == Action.Type.STEAL:
			steal_targets.append(a.card_instance_id)

	TestUtil.assert_true(steal_targets.has(salt_card.instance_id), "an attached ingredient on an incomplete recipe should be stealable")
	TestUtil.assert_false(steal_targets.has(chopping_card.instance_id), "an attached preparation should never be stealable")

func test_completed_recipe_cards_are_not_stealable() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0] # dish_b: salt + oil, prep chopping
	var salt_card: Card = alloc.call("salt", CardDef.Category.INGREDIENT)
	var oil_card: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	var chopping_card: Card = alloc.call("chopping", CardDef.Category.PREPARATION)
	recipe1.attach_ingredient_to_slot(salt_card)
	recipe1.attach_ingredient_to_slot(oil_card)
	recipe1.attach_preparation_to_slot(chopping_card)
	TestUtil.assert_true(recipe1.completed, "recipe should be complete once every required slot is filled")

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	for a in legal:
		if a.type == Action.Type.STEAL:
			TestUtil.assert_ne(a.card_instance_id, salt_card.instance_id, "cards on a completed recipe must never be stealable")
			TestUtil.assert_ne(a.card_instance_id, oil_card.instance_id, "cards on a completed recipe must never be stealable")

func test_cannot_steal_from_self() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var recipe0: Recipe = p0.recipes[0]
	var oil_card: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	recipe0.attach_ingredient_to_slot(oil_card)

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	for a in legal:
		if a.type == Action.Type.STEAL:
			TestUtil.assert_ne(a.target_player_index, 0, "a player should never be offered a steal targeting their own recipe")

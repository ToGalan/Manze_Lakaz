extends RefCounted
## Rule: a joker ingredient card (CardDef.is_joker) can fill any open
## ingredient slot whose own def shares the joker's ingredient_type, instead
## of only the one exact def_id a normal card matches. If more than one open
## slot on the same recipe matches, each is offered as a separate legal
## ATTACH action (naming the slot via Action.target_def_id) rather than the
## engine guessing one. Once attached, a joker behaves exactly like any other
## filled ingredient card for stealing and completion purposes.

func test_joker_can_fill_matching_open_slot() -> void:
	var db := TestFixtures.joker_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_protein"])
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var joker_card: Card = alloc.call("joker_protein", CardDef.Category.INGREDIENT)
	player.hand = [joker_card]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	var matches: Array[Action] = []
	for a in legal:
		if a.type == Action.Type.ATTACH and a.card_instance_id == joker_card.instance_id:
			matches.append(a)

	TestUtil.assert_eq(matches.size(), 1, "a protein joker should offer exactly one attach action against a recipe with one open protein slot")
	TestUtil.assert_eq(matches[0].target_def_id, "fish", "the joker's attach action should name the open protein slot it would fill")
	TestUtil.assert_false(matches[0].as_decoy, "a joker filling a real open slot is not a decoy attachment")

	RulesEngine.apply_action(state, matches[0])

	var recipe: Recipe = player.recipes[0]
	TestUtil.assert_false(recipe.is_ingredient_slot_open("fish"), "the fish slot should now be filled")
	TestUtil.assert_eq(recipe.filled_ingredients["fish"].instance_id, joker_card.instance_id, "the fish slot should hold the joker card itself, not a real fish")

func test_joker_does_not_offer_non_matching_category_slots() -> void:
	var db := TestFixtures.joker_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_protein"])
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var joker_card: Card = alloc.call("joker_protein", CardDef.Category.INGREDIENT)
	player.hand = [joker_card]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	for a in legal:
		if a.type == Action.Type.ATTACH and a.card_instance_id == joker_card.instance_id:
			TestUtil.assert_ne(a.target_def_id, "oil", "a protein joker must never be offered to fill oil's pantry slot")

func test_joker_offers_one_action_per_matching_open_slot_when_ambiguous() -> void:
	var db := TestFixtures.joker_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_veg2"]) # onion + tomato, both vegetable
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var joker_card: Card = alloc.call("joker_vegetable", CardDef.Category.INGREDIENT)
	player.hand = [joker_card]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	var target_ids: Array[String] = []
	for a in legal:
		if a.type == Action.Type.ATTACH and a.card_instance_id == joker_card.instance_id:
			target_ids.append(a.target_def_id)

	TestUtil.assert_eq(target_ids.size(), 2, "a vegetable joker facing two open vegetable slots on the same recipe should offer both as separate actions")
	TestUtil.assert_true(target_ids.has("onion"), "onion should be one of the offered slots")
	TestUtil.assert_true(target_ids.has("tomato"), "tomato should be the other offered slot")

func test_joker_attached_ingredient_is_stealable_like_any_other() -> void:
	var db := TestFixtures.joker_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_protein", "dish_protein"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0]
	var joker_card: Card = alloc.call("joker_protein", CardDef.Category.INGREDIENT)
	recipe1.attach_ingredient_to_slot(joker_card, "fish")

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	var steal_targets := []
	for a in legal:
		if a.type == Action.Type.STEAL:
			steal_targets.append(a.card_instance_id)

	TestUtil.assert_true(steal_targets.has(joker_card.instance_id), "a joker filling a slot should be stealable exactly like a normal attached ingredient")

func test_joker_completes_recipe_when_it_fills_last_open_slot() -> void:
	var db := TestFixtures.joker_database()
	var config := TestFixtures.default_config()
	config.win_on_both_recipes = false
	var state := TestFixtures.bare_state(config, db, ["dish_protein"])
	var alloc := TestFixtures.make_card_allocator()

	var player: Player = state.players[0]
	var recipe: Recipe = player.recipes[0] # dish_protein: fish + oil, prep grinding
	recipe.attach_ingredient_to_slot(alloc.call("oil", CardDef.Category.INGREDIENT))
	recipe.attach_preparation_to_slot(alloc.call("grinding", CardDef.Category.PREPARATION))

	var joker_card: Card = alloc.call("joker_protein", CardDef.Category.INGREDIENT)
	player.hand = [joker_card]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	var attach_action: Action = null
	for a in legal:
		if a.type == Action.Type.ATTACH and a.card_instance_id == joker_card.instance_id:
			attach_action = a
			break
	TestUtil.assert_true(attach_action != null, "the joker should have a legal attach action filling the last open slot")

	RulesEngine.apply_action(state, attach_action)

	TestUtil.assert_true(recipe.completed, "the recipe should be complete once the joker fills its last open slot")
	TestUtil.assert_true(state.game_over, "completing a recipe via a joker should end the game in FFA mode exactly like a normal card would")

extends RefCounted
## Hard: same greedy attach/discard as Medium, but picks steal targets by
## opponent modelling instead of "first needed card found". These tests
## specifically construct a scenario where the naive first-match choice
## (what Medium picks) and the better strategic choice (what Hard should
## pick) are different cards, to prove Hard is actually scoring options
## rather than just reusing Medium's loop order.

func test_hard_prefers_stealing_from_the_more_progressed_opponent() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	# p0 (the bot) needs oil for dish_a. Both p1 and p2 have a stealable
	# oil attached, so both steals would help p0 equally -- but p2's
	# recipe is much closer to completion, so a smart bot should steal
	# from p2 to deny the win, not just grab whichever it sees first.
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b", "dish_c"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0] # dish_b: salt + oil, prep chopping
	var oil1: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	recipe1.attach_ingredient_to_slot(oil1) # 1 of 3 slots filled -- barely started

	var p2: Player = state.players[2]
	var recipe2: Recipe = p2.recipes[0] # dish_c: oil + salt, prep grinding
	var oil2: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	recipe2.attach_ingredient_to_slot(oil2)
	recipe2.attach_ingredient_to_slot(alloc.call("salt", CardDef.Category.INGREDIENT)) # 2 of 3 slots filled -- close to done

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE
	state.deck = [alloc.call("fish", CardDef.Category.INGREDIENT)]

	var legal := RulesEngine.get_legal_actions(state)

	# Sanity check the scenario: Medium's simpler "first needed card found"
	# loop should land on p1's oil, since p1 is iterated before p2.
	var medium_action := MediumBot.new(0).choose_action(state, legal)
	TestUtil.assert_eq(medium_action.type, Action.Type.STEAL, "medium should still prefer stealing a needed card over drawing")
	TestUtil.assert_eq(medium_action.target_player_index, 1, "medium's naive first-match should land on p1, since p1 is checked first")

	var hard_action := HardBot.new(0).choose_action(state, legal)
	TestUtil.assert_eq(hard_action.type, Action.Type.STEAL, "hard should also prefer a strong steal over drawing")
	TestUtil.assert_eq(hard_action.target_player_index, 2, "hard should steal from p2 instead: same self-benefit, but p2 is much closer to winning")
	TestUtil.assert_eq(hard_action.card_instance_id, oil2.instance_id, "hard should take the specific card denying p2's near-complete recipe")

func test_hard_draws_when_no_steal_is_worthwhile() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0] # dish_b: salt + oil, prep chopping
	recipe1.attach_ingredient_to_slot(alloc.call("salt", CardDef.Category.INGREDIENT)) # not needed by p0, barely progressed

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE
	state.deck = [alloc.call("fish", CardDef.Category.INGREDIENT)]

	var legal := RulesEngine.get_legal_actions(state)
	var action := HardBot.new(0).choose_action(state, legal)

	TestUtil.assert_eq(action.type, Action.Type.DRAW, "hard should draw rather than take a low-value, unhelpful steal")

func test_hard_attaches_when_possible_just_like_medium() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	p0.hand = [oil]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	var action := HardBot.new(0).choose_action(state, legal)

	TestUtil.assert_eq(action.type, Action.Type.ATTACH, "hard should still always attach when legal, same as medium")
	TestUtil.assert_eq(action.card_instance_id, oil.instance_id, "it should attach the card that fits")

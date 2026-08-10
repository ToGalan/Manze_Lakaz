extends RefCounted
## Medium: always attach if possible; steal a needed card if visible;
## otherwise draw; discard the card least useful to its recipes.

func test_attaches_when_possible() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var salt: Card = alloc.call("salt", CardDef.Category.INGREDIENT) # not needed by dish_a
	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)   # dish_a needs oil
	p0.hand = [salt, oil]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	var action := MediumBot.new(0).choose_action(state, legal)

	TestUtil.assert_eq(action.type, Action.Type.ATTACH, "medium should attach when any attach is legal")
	TestUtil.assert_eq(action.card_instance_id, oil.instance_id, "it should attach the card that actually fits")

func test_steals_a_needed_card_over_drawing() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0] # dish_b: salt + oil, prep chopping
	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT) # also needed by p0's dish_a
	recipe1.attach_ingredient_to_slot(oil)

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE
	state.deck = [alloc.call("fish", CardDef.Category.INGREDIENT)]

	var legal := RulesEngine.get_legal_actions(state)
	var action := MediumBot.new(0).choose_action(state, legal)

	TestUtil.assert_eq(action.type, Action.Type.STEAL, "medium should steal a card it needs over drawing")
	TestUtil.assert_eq(action.card_instance_id, oil.instance_id, "it should steal the specific needed card")

func test_draws_when_no_needed_steal_is_available() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0] # dish_b: salt + oil, prep chopping
	recipe1.attach_ingredient_to_slot(alloc.call("salt", CardDef.Category.INGREDIENT)) # not needed by dish_a

	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE
	state.deck = [alloc.call("fish", CardDef.Category.INGREDIENT)]

	var legal := RulesEngine.get_legal_actions(state)
	var action := MediumBot.new(0).choose_action(state, legal)

	TestUtil.assert_eq(action.type, Action.Type.DRAW, "medium should draw when no visible steal helps it")

func test_discards_least_useful_card_at_hand_limit() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)   # dish_a needs this -- useful
	var salt: Card = alloc.call("salt", CardDef.Category.INGREDIENT) # dish_a doesn't need this -- useless
	p0.hand = [oil, salt]

	state.current_player_index = 0
	state.phase = GameState.Phase.HAND_LIMIT # only DISCARD is ever legal here, regardless of hand contents

	var legal := RulesEngine.get_legal_actions(state)
	var action := MediumBot.new(0).choose_action(state, legal)

	TestUtil.assert_eq(action.type, Action.Type.DISCARD, "only discard is legal in the hand-limit phase")
	TestUtil.assert_eq(action.card_instance_id, salt.instance_id, "medium should discard the useless card, keeping the one it still needs")

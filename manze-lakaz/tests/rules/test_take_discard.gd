extends RefCounted
## Rule: during Step 1, a player may take the top card of the discard pile
## instead of drawing blind. This is a plain alternative to DRAW, not a
## replacement for it -- both remain legal side by side whenever the
## discard pile is non-empty.
##
## Also covers the related rule change: a duplicate Preparation card in
## hand no longer restricts PLAY-phase choices to resolving it. Any hand
## card is always a legal discard target.

func test_take_discard_offered_and_moves_top_card_into_hand() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var salt: Card = alloc.call("salt", CardDef.Category.INGREDIENT)
	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	state.discard_pile = [salt, oil] # oil is on top
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	var has_take_discard := false
	for a in legal:
		if a.type == Action.Type.TAKE_DISCARD:
			has_take_discard = true
	TestUtil.assert_true(has_take_discard, "TAKE_DISCARD should be offered when the discard pile is non-empty")

	var p0: Player = state.players[0]
	var hand_before: int = p0.hand.size()
	RulesEngine.apply_action(state, Action.make_take_discard(0))

	TestUtil.assert_eq(p0.hand.size(), hand_before + 1, "taking the discard should add exactly one card to hand")
	TestUtil.assert_true(p0.find_in_hand(oil.instance_id) != null, "the specific top card (oil, not salt) should be the one taken")
	TestUtil.assert_eq(state.discard_pile.size(), 1, "the discard pile should shrink by one")
	TestUtil.assert_eq(state.discard_pile[0].instance_id, salt.instance_id, "the remaining discard card should be the one that was underneath")

func test_take_discard_not_offered_when_discard_pile_empty() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])

	state.deck = [] # irrelevant to this rule, but keeps DRAW's own legality out of the picture
	state.discard_pile = []
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	for a in legal:
		TestUtil.assert_ne(a.type, Action.Type.TAKE_DISCARD, "TAKE_DISCARD must not be offered when the discard pile is empty")

func test_draw_and_take_discard_both_legal_side_by_side() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	state.deck = [alloc.call("fish", CardDef.Category.INGREDIENT)]
	state.discard_pile = [alloc.call("salt", CardDef.Category.INGREDIENT)]
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE

	var legal := RulesEngine.get_legal_actions(state)
	var has_draw := false
	var has_take_discard := false
	for a in legal:
		if a.type == Action.Type.DRAW:
			has_draw = true
		if a.type == Action.Type.TAKE_DISCARD:
			has_take_discard = true
	TestUtil.assert_true(has_draw, "DRAW should remain legal alongside TAKE_DISCARD")
	TestUtil.assert_true(has_take_discard, "TAKE_DISCARD should be legal alongside DRAW")

func test_duplicate_preparation_in_hand_no_longer_restricts_play_actions() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var grinding1: Card = alloc.call("grinding", CardDef.Category.PREPARATION)
	var grinding2: Card = alloc.call("grinding", CardDef.Category.PREPARATION)
	var oil1: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	p0.hand = [grinding1, grinding2, oil1]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)

	var has_oil_discard := false
	for a in legal:
		if a.type == Action.Type.DISCARD and a.card_instance_id == oil1.instance_id:
			has_oil_discard = true
	TestUtil.assert_true(has_oil_discard, "a non-duplicate hand card should always be a legal discard target, even with a duplicate prep still in hand")

	# Discarding the non-duplicate card should be allowed to actually apply,
	# leaving the duplicate sitting in hand unresolved.
	RulesEngine.apply_action(state, Action.make_discard(0, oil1.instance_id))
	TestUtil.assert_true(p0.find_in_hand(grinding1.instance_id) != null, "the duplicate prep should still be sitting in hand, unresolved")
	TestUtil.assert_true(p0.find_in_hand(grinding2.instance_id) != null, "the duplicate prep should still be sitting in hand, unresolved")

extends RefCounted
## Rule: skip_turn() is the timeout-fallback path (ServerAuthority /
## GameScreen's hot-seat equivalent) that ends a stalled player's turn
## with zero board-state change -- no bot plays for them, so nothing they
## didn't actually choose (a steal, an attach) can happen while they're
## away. Never reachable through get_legal_actions()/apply_action(); only
## ever called directly by the timeout handlers.

func test_skip_during_take_ends_the_turn_immediately() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()
	state.players[0].hand = [alloc.call("oil", CardDef.Category.INGREDIENT)]
	state.phase = GameState.Phase.TAKE
	state.current_player_index = 0
	state.turn_number = 1

	RulesEngine.skip_turn(state)

	TestUtil.assert_eq(state.current_player_index, 1, "skipping during TAKE should move directly to the next player")
	TestUtil.assert_eq(state.phase, GameState.Phase.TAKE, "the next player should start in TAKE, same as any normal turn")
	TestUtil.assert_eq(state.turn_number, 2, "the turn counter should still advance")
	TestUtil.assert_eq(state.players[0].hand.size(), 1, "the skipped player's hand must be completely untouched")

func test_skip_during_play_with_hand_within_limit_ends_the_turn() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()
	state.players[0].hand = [alloc.call("oil", CardDef.Category.INGREDIENT)]
	state.phase = GameState.Phase.PLAY
	state.current_player_index = 0

	RulesEngine.skip_turn(state)

	TestUtil.assert_eq(state.current_player_index, 1, "skipping during PLAY with a legal hand should still end the turn")
	TestUtil.assert_eq(state.phase, GameState.Phase.TAKE, "the next player should start fresh in TAKE")
	TestUtil.assert_eq(state.players[0].hand.size(), 1, "no card should have been attached or discarded")

func test_skip_during_play_over_hand_limit_falls_into_hand_limit_phase() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	config.hand_limit = 2
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()
	state.players[0].hand = [
		alloc.call("oil", CardDef.Category.INGREDIENT),
		alloc.call("fish", CardDef.Category.INGREDIENT),
		alloc.call("salt", CardDef.Category.INGREDIENT),
	]
	state.phase = GameState.Phase.PLAY
	state.current_player_index = 0

	RulesEngine.skip_turn(state)

	TestUtil.assert_eq(state.current_player_index, 0, "a hand over the limit still has to be resolved -- the turn must not silently end")
	TestUtil.assert_eq(state.phase, GameState.Phase.HAND_LIMIT, "should fall into the same hand-limit phase a real PLAY action would have")
	TestUtil.assert_eq(state.players[0].hand.size(), 3, "skip_turn() itself must not discard anything -- that's still the existing hand-limit fallback's job")

func test_skip_is_a_no_op_during_draft() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var state := RulesEngine.new_game(config, db)
	TestUtil.assert_eq(state.phase, GameState.Phase.DRAFT, "sanity check: a new game starts in DRAFT")

	RulesEngine.skip_turn(state)

	TestUtil.assert_eq(state.phase, GameState.Phase.DRAFT, "skip_turn() must never be applied during DRAFT -- every player has to actually pick recipes")
	TestUtil.assert_eq(state.current_player_index, 0, "current player must be unchanged")

func test_skip_is_a_no_op_when_game_is_over() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	state.phase = GameState.Phase.TAKE
	state.game_over = true
	state.current_player_index = 0

	RulesEngine.skip_turn(state)

	TestUtil.assert_eq(state.current_player_index, 0, "a finished game must not have its turn advanced")

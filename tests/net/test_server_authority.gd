extends RefCounted
## ServerAuthority is where "never trust the client" is actually enforced.
## peer_node=null lets these run without a live SceneTree/multiplayer peer
## -- exactly the isolation this class was designed to support so its
## validation logic can be tested directly.

func _make_authority_with_started_game() -> ServerAuthority:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var authority := ServerAuthority.new(db, config)
	authority.state = TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	authority.game_started = true
	authority.peer_to_seat = {101: 0, 102: 1}
	authority.seat_to_peer = {0: 101, 1: 102}
	return authority

func test_rejects_action_claiming_a_seat_the_peer_does_not_own() -> void:
	var authority := _make_authority_with_started_game()
	var alloc := TestFixtures.make_card_allocator()
	authority.state.current_player_index = 0
	authority.state.phase = GameState.Phase.TAKE
	authority.state.deck = [alloc.call("oil", CardDef.Category.INGREDIENT)]

	# peer 102 is genuinely seated at 1, but submits an action claiming to be player 0.
	authority.handle_action_intent(102, ActionSerializer.serialize(Action.make_draw(0)))

	TestUtil.assert_eq(authority.state.players[0].hand.size(), 0, "an impersonation attempt must not mutate the impersonated seat")

func test_rejects_action_from_completely_unrecognized_peer() -> void:
	var authority := _make_authority_with_started_game()
	var alloc := TestFixtures.make_card_allocator()
	authority.state.current_player_index = 0
	authority.state.phase = GameState.Phase.TAKE
	authority.state.deck = [alloc.call("oil", CardDef.Category.INGREDIENT)]

	authority.handle_action_intent(999, ActionSerializer.serialize(Action.make_draw(0)))

	TestUtil.assert_eq(authority.state.players[0].hand.size(), 0, "an action from a peer that never joined must be dropped")

func test_rejects_action_not_actually_in_get_legal_actions() -> void:
	var authority := _make_authority_with_started_game()
	authority.state.current_player_index = 0
	authority.state.phase = GameState.Phase.PLAY
	authority.state.players[0].hand = [] # nothing legal to attach or discard

	var fake_discard := Action.make_discard(0, 12345) # instance id that doesn't exist anywhere
	authority.handle_action_intent(101, ActionSerializer.serialize(fake_discard))

	TestUtil.assert_eq(authority.state.discard_pile.size(), 0, "an action absent from get_legal_actions() must be rejected even from the correctly-authenticated seat")

func test_accepts_a_genuinely_legal_action_from_the_correct_seat() -> void:
	var authority := _make_authority_with_started_game()
	var alloc := TestFixtures.make_card_allocator()
	authority.state.current_player_index = 0
	authority.state.phase = GameState.Phase.TAKE
	authority.state.deck = [alloc.call("oil", CardDef.Category.INGREDIENT)]

	authority.handle_action_intent(101, ActionSerializer.serialize(Action.make_draw(0)))

	TestUtil.assert_eq(authority.state.players[0].hand.size(), 1, "a legal action from the correctly-authenticated seat should be applied")

func test_join_assigns_first_open_seat_and_a_reconnection_token() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var authority := ServerAuthority.new(db, config)

	authority.handle_join_request(201, "Alice")
	TestUtil.assert_eq(authority.peer_to_seat[201], 0, "the first joining peer should take seat 0")
	TestUtil.assert_true(authority.seat_tokens.has(0), "a reconnection token should be issued for the seat")

	authority.handle_join_request(202, "Bob")
	TestUtil.assert_eq(authority.peer_to_seat[202], 1, "the second joining peer should take the next open seat")

func test_join_rejected_when_no_seats_remain() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var authority := ServerAuthority.new(db, config)
	authority.handle_join_request(201, "Alice")
	authority.handle_join_request(202, "Bob")

	authority.handle_join_request(203, "Carol")
	TestUtil.assert_false(authority.peer_to_seat.has(203), "a peer must not be seated once the game is full")

func test_rejoin_restores_the_same_seat_under_a_new_peer_id() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var authority := ServerAuthority.new(db, config)
	authority.handle_join_request(201, "Alice")
	var token: String = authority.seat_tokens[0]

	authority.handle_peer_disconnected(201)
	TestUtil.assert_eq(authority.seat_to_peer[0], -1, "the seat should be marked disconnected, not vacated")

	authority.handle_rejoin_request(555, token) # a brand new peer id, as a real reconnect would have
	TestUtil.assert_eq(authority.seat_to_peer[0], 555, "rejoining with the correct token should restore seat 0 under the new peer id")
	TestUtil.assert_eq(authority.peer_to_seat[555], 0, "the new peer id should now map back to seat 0")
	TestUtil.assert_false(authority.peer_to_seat.has(201), "the stale old peer id should no longer be mapped to any seat")

func test_rejoin_with_unknown_token_is_rejected() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var authority := ServerAuthority.new(db, config)
	authority.handle_join_request(201, "Alice")

	authority.handle_rejoin_request(777, "not-a-real-token")
	TestUtil.assert_false(authority.peer_to_seat.has(777), "an unrecognized token must not grant a seat")

func test_turn_timer_fallback_auto_plays_when_invoked() -> void:
	var authority := _make_authority_with_started_game()
	var alloc := TestFixtures.make_card_allocator()
	authority.state.current_player_index = 0
	authority.state.phase = GameState.Phase.TAKE
	authority.state.deck = [alloc.call("oil", CardDef.Category.INGREDIENT)]
	authority.auto_play_difficulty = AiBot.Difficulty.EASY

	authority._on_turn_timer_expired(authority._turn_timer_token) # simulate the configured timer firing

	TestUtil.assert_eq(authority.state.players[0].hand.size(), 1, "when no client acts in time, the fallback bot should take one action for the current player")

func test_stale_turn_timer_callback_is_ignored() -> void:
	var authority := _make_authority_with_started_game()
	var alloc := TestFixtures.make_card_allocator()
	authority.state.current_player_index = 0
	authority.state.phase = GameState.Phase.TAKE
	authority.state.deck = [alloc.call("oil", CardDef.Category.INGREDIENT)]

	var stale_token := authority._turn_timer_token
	authority._turn_timer_token += 1 # simulate a real action having already re-armed the timer

	authority._on_turn_timer_expired(stale_token)

	TestUtil.assert_eq(authority.state.players[0].hand.size(), 0, "a stale timer callback superseded by a real action must not double-act")

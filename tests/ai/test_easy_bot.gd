extends RefCounted
## Easy: random legal action, weighted slightly toward attaching.

func test_only_ever_returns_a_legal_action() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	p0.hand = [alloc.call("oil", CardDef.Category.INGREDIENT), alloc.call("salt", CardDef.Category.INGREDIENT)]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var legal := RulesEngine.get_legal_actions(state)
	var bot := EasyBot.new(0)
	for i in 50:
		var action := bot.choose_action(state, legal)
		var found := false
		for a in legal:
			if a.equals(action):
				found = true
				break
		TestUtil.assert_true(found, "easy bot must only ever return an action that was actually offered as legal")

func test_weighted_toward_attaching() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)   # yields exactly one ATTACH option
	var salt: Card = alloc.call("salt", CardDef.Category.INGREDIENT) # discard-only
	p0.hand = [oil, salt]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	# legal here is: ATTACH(oil), DISCARD(oil), DISCARD(salt) -- 1 attach vs 2 discards
	var legal := RulesEngine.get_legal_actions(state)
	var bot := EasyBot.new(0)
	var attach_count := 0
	var trials := 4000
	for i in trials:
		if bot.choose_action(state, legal).type == Action.Type.ATTACH:
			attach_count += 1

	var rate := float(attach_count) / float(trials)
	# Uniform random over 3 options would give ~33%; the attach weight
	# should push this well above that without ever being deterministic.
	TestUtil.assert_true(rate > 0.45, "attach should be picked noticeably more than its 1-in-3 uniform share (got %.2f)" % rate)
	TestUtil.assert_true(rate < 0.95, "easy bot must still sometimes pick something other than attach (got %.2f)" % rate)

extends RefCounted
## The state filter is THE security boundary for online play. These tests
## don't just check "the UI doesn't show X" -- they check the literal
## serialized payload never contains X anywhere, including under an
## unused/ignored key, since anything present in the Dictionary sent to a
## client can be read by that client regardless of what the field is
## named or whether the UI happens to render it.

func test_snapshot_never_contains_opponent_hand_card_identity() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	# A rare, unique def_id planted ONLY in the opponent's hidden hand.
	var secret_card: Card = alloc.call("chopping", CardDef.Category.PREPARATION)
	state.players[1].hand = [secret_card]

	var snapshot := NetworkStateFilter.build_snapshot(state, 0)
	var serialized := JSON.stringify(snapshot)

	TestUtil.assert_true(serialized.find("chopping") == -1, "an opponent's hidden hand card must not appear anywhere in the serialized payload")

func test_snapshot_exposes_viewers_own_hand_in_full() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	state.players[0].hand = [oil]

	var snapshot := NetworkStateFilter.build_snapshot(state, 0)
	var own_hand: Array = snapshot["own_hand"]
	TestUtil.assert_eq(own_hand.size(), 1, "the viewer's own hand should be sent in full")
	TestUtil.assert_eq(own_hand[0]["def_id"], "oil", "own hand card identity should be included")
	TestUtil.assert_eq(own_hand[0]["instance_id"], oil.instance_id, "own hand card instance id should be included")

func test_snapshot_never_includes_opponent_recipe_requirement_list() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])

	var snapshot := NetworkStateFilter.build_snapshot(state, 0)
	var opponents: Array = snapshot["opponents"]
	TestUtil.assert_eq(opponents.size(), 1, "should have one opponent entry")
	var opp_recipes: Array = opponents[0]["recipes"]
	TestUtil.assert_eq(opp_recipes.size(), 1, "opponent should have one recipe entry")

	var recipe_dict: Dictionary = opp_recipes[0]
	TestUtil.assert_eq(recipe_dict["recipe_id"], "dish_b", "the dish name is public and should be included")
	TestUtil.assert_false(recipe_dict.has("ingredient_ids"), "an opponent recipe's ingredient requirement list must never be serialized")
	TestUtil.assert_false(recipe_dict.has("preparation_ids"), "an opponent recipe's preparation requirement list must never be serialized")

func test_snapshot_exposes_viewers_own_recipe_requirements_in_full() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])

	var snapshot := NetworkStateFilter.build_snapshot(state, 0)
	var own_recipes: Array = snapshot["own_recipes"]
	TestUtil.assert_eq(own_recipes[0]["ingredient_ids"], ["oil", "fish"], "the viewer's own recipe requirements should be sent in full")

func test_snapshot_never_includes_deck_contents_only_count() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	# "chopping" belongs only to dish_b (the opponent's recipe, whose
	# requirement list is excluded) -- not to dish_a (the viewer's own
	# recipe, whose requirement list is legitimately included) -- so it's
	# a clean marker with no legitimate way to appear in this viewer's payload.
	state.deck = [alloc.call("chopping", CardDef.Category.PREPARATION)]

	var snapshot := NetworkStateFilter.build_snapshot(state, 0)
	TestUtil.assert_eq(snapshot["deck_size"], 1, "deck size should be public")
	TestUtil.assert_false(snapshot.has("deck"), "raw deck contents must never be serialized")
	var serialized := JSON.stringify(snapshot)
	TestUtil.assert_true(serialized.find("chopping") == -1, "the specific deck card must not leak into the payload even indirectly")

func test_snapshot_exposes_steals_used_for_self_and_opponents() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	state.players[0].steals_used = 1
	state.players[1].steals_used = 4

	var snapshot := NetworkStateFilter.build_snapshot(state, 0)
	TestUtil.assert_eq(snapshot["own_steals_used"], 1, "the viewer's own steals_used is a public stat and should be sent")
	var opponents: Array = snapshot["opponents"]
	TestUtil.assert_eq(opponents[0]["steals_used"], 4, "an opponent's steals_used is a public stat and should be sent")
	TestUtil.assert_eq(snapshot["config"]["max_steals_per_player"], config.max_steals_per_player, "the configured steal cap should be sent as part of config")

func test_legal_actions_only_sent_to_the_current_player() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	state.players[0].hand = [alloc.call("oil", CardDef.Category.INGREDIENT)]
	state.current_player_index = 0
	state.phase = GameState.Phase.PLAY

	var current_player_snapshot := NetworkStateFilter.build_snapshot(state, 0)
	TestUtil.assert_false((current_player_snapshot["legal_actions"] as Array).is_empty(), "the current player's own legal actions should be included")

	var other_player_snapshot := NetworkStateFilter.build_snapshot(state, 1)
	TestUtil.assert_true((other_player_snapshot["legal_actions"] as Array).is_empty(), "a player should never receive another player's legal-action list")

func test_draft_offer_only_includes_the_viewers_own_offer() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.draft_config(2)
	var state := RulesEngine.new_game(config, db)

	var snapshot := NetworkStateFilter.build_snapshot(state, 0)
	TestUtil.assert_eq((snapshot["draft_offer"] as Array).size(), 3, "the viewer's own draft offer should be visible")

	var serialized := JSON.stringify(snapshot)
	for rid in state.draft_offers[1]:
		if not state.draft_offers[0].has(rid):
			TestUtil.assert_true(serialized.find(rid) == -1, "another player's draft offer must not leak into the payload (recipe '%s')" % rid)

extends RefCounted
## Proves the client-side reconstruction round-trips correctly and that
## the existing GameViewModel rendering functions work unchanged against
## a shadow state built purely from a filtered snapshot.

func test_round_trip_preserves_own_hand_and_recipe_progress() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var real_state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	real_state.players[0].hand = [oil]
	real_state.players[0].recipes[0].attach_ingredient_to_slot(alloc.call("fish", CardDef.Category.INGREDIENT))

	var snapshot := NetworkStateFilter.build_snapshot(real_state, 0)
	var shadow := ShadowStateBuilder.build(snapshot, db)

	TestUtil.assert_eq(shadow.players[0].hand.size(), 1, "own hand should round-trip")
	TestUtil.assert_eq(shadow.players[0].hand[0].def_id, "oil", "own hand card identity should round-trip")
	TestUtil.assert_true(shadow.players[0].recipes[0].filled_ingredients.has("fish"), "own recipe progress should round-trip")

func test_round_trip_hides_opponent_hand_but_preserves_count() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var real_state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()
	real_state.players[1].hand = [alloc.call("salt", CardDef.Category.INGREDIENT), alloc.call("oil", CardDef.Category.INGREDIENT)]

	var snapshot := NetworkStateFilter.build_snapshot(real_state, 0)
	var shadow := ShadowStateBuilder.build(snapshot, db)

	TestUtil.assert_eq(shadow.players[1].hand.size(), 0, "the shadow state must never carry opponent hand contents")
	TestUtil.assert_eq(ShadowStateBuilder.hand_count_of(shadow.players[1]), 2, "the true hand count should still be readable via metadata")

func test_round_trip_preserves_steals_used_for_self_and_opponents() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var real_state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])

	real_state.players[0].steals_used = 2
	real_state.players[1].steals_used = 3

	var snapshot := NetworkStateFilter.build_snapshot(real_state, 0)
	var shadow := ShadowStateBuilder.build(snapshot, db)

	TestUtil.assert_eq(shadow.players[0].steals_used, 2, "the viewer's own steals_used should round-trip")
	TestUtil.assert_eq(shadow.players[1].steals_used, 3, "an opponent's steals_used should round-trip -- it's a public stat, same as hand_count")

func test_gameviewmodel_renders_correctly_from_a_shadow_state() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var real_state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()
	real_state.players[1].recipes[0].attach_ingredient_to_slot(alloc.call("salt", CardDef.Category.INGREDIENT))
	real_state.current_player_index = 0
	real_state.phase = GameState.Phase.TAKE
	real_state.deck = [alloc.call("oil", CardDef.Category.INGREDIENT)]

	var snapshot := NetworkStateFilter.build_snapshot(real_state, 0)
	var shadow := ShadowStateBuilder.build(snapshot, db)
	var legal := ActionSerializer.deserialize_list(snapshot["legal_actions"])

	TestUtil.assert_eq(GameViewModel.recipe_title(shadow.players[0].recipes[0].def).find("Test Dish A"), 0, "own recipe title should render from the shadow state")
	var attachments := GameViewModel.other_recipe_attachments(shadow.players[1].recipes[0], db)
	TestUtil.assert_eq(attachments.size(), 1, "opponent attachments should render from the shadow state")
	TestUtil.assert_eq(attachments[0]["label"], "Salt", "the specific attached card should render correctly")

	var status := GameViewModel.status_text(shadow, legal)
	TestUtil.assert_true(status.find("Player 1") == 0, "status text should still correctly name the current player")

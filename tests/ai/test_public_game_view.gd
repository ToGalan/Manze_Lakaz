extends RefCounted
## PublicGameView is the no-cheat boundary every AI bot is restricted to.
## These tests pin down exactly what it does and does not expose.

func test_view_hides_opponent_hand_contents_but_shows_count() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	p1.hand = [alloc.call("oil", CardDef.Category.INGREDIENT), alloc.call("fish", CardDef.Category.INGREDIENT)]

	var view := PublicGameView.from_state(state, 0)

	TestUtil.assert_eq(view.opponents.size(), 1, "a 2-player game should have exactly one opponent view")
	var ov: PublicGameView.OpponentView = view.opponents[0]
	TestUtil.assert_eq(ov.hand_count, 2, "opponent hand COUNT must be visible (it's public in every card game)")
	# OpponentView has no hand field at all -- there is no accessor that
	# could leak card contents, by construction (see PublicGameView.gd).

func test_view_exposes_own_hand_in_full() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p0: Player = state.players[0]
	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	p0.hand = [oil]

	var view := PublicGameView.from_state(state, 0)
	TestUtil.assert_eq(view.own_hand.size(), 1, "the viewer's own hand should be fully visible to itself")
	TestUtil.assert_eq(view.own_hand[0].instance_id, oil.instance_id, "own hand contents should match exactly")

func test_view_exposes_public_recipe_defs_and_visible_attachments() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	var p1: Player = state.players[1]
	var recipe1: Recipe = p1.recipes[0]
	var oil: Card = alloc.call("oil", CardDef.Category.INGREDIENT)
	recipe1.attach_ingredient_to_slot(oil)

	var view := PublicGameView.from_state(state, 0)
	var ov: PublicGameView.OpponentView = view.opponents[0]
	var rv: PublicGameView.RecipeView = ov.recipes[0]

	TestUtil.assert_eq(rv.def.id, "dish_b", "recipe dish name/def is public (dealt face up)")
	TestUtil.assert_eq(rv.attached_ingredients.size(), 1, "attached cards should be visible")
	TestUtil.assert_eq(rv.attached_ingredients[0].instance_id, oil.instance_id, "the exact attached card instance should be visible")

func test_view_discard_pile_is_visible() -> void:
	var db := TestFixtures.tiny_database()
	var config := TestFixtures.default_config()
	var state := TestFixtures.bare_state(config, db, ["dish_a", "dish_b"])
	var alloc := TestFixtures.make_card_allocator()

	state.discard_pile = [alloc.call("salt", CardDef.Category.INGREDIENT)]
	var view := PublicGameView.from_state(state, 0)
	TestUtil.assert_eq(view.discard_pile.size(), 1, "the discard pile is a real, visible pile")

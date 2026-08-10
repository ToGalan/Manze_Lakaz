extends RefCounted
## Regression check on the actual shipped balance data in res://data. This
## is the test that catches typos and copy-count mistakes made while
## rebalancing -- it should fail loudly the moment the JSON drifts from its
## own declared invariants.

func test_shipped_data_passes_validation() -> void:
	var result := DataLoader.load_database(
		"res://data/ingredients.json",
		"res://data/preparations.json",
		"res://data/recipes.json"
	)
	if not result.ok:
		for e in result.errors:
			TestUtil.assert_true(false, "data validation error: " + e)
	TestUtil.assert_true(result.ok, "res://data/*.json should pass DataLoader validation with zero errors")

func test_deck_totals_match_spec() -> void:
	var result := DataLoader.load_database(
		"res://data/ingredients.json",
		"res://data/preparations.json",
		"res://data/recipes.json"
	)
	TestUtil.assert_true(result.ok, "data must load before checking deck totals")
	if not result.ok:
		return
	var db := result.database
	var deck := db.build_deck()
	TestUtil.assert_eq(deck.size(), 92, "the full deck should contain exactly 92 cards")
	TestUtil.assert_eq(db.recipe_order.size(), 12, "there should be exactly 12 recipe cards")

	var ingredient_count := 0
	var preparation_count := 0
	for c in deck:
		if c.is_ingredient():
			ingredient_count += 1
		else:
			preparation_count += 1
	TestUtil.assert_eq(ingredient_count, 68, "68 ingredient cards expected in the deck")
	TestUtil.assert_eq(preparation_count, 24, "24 preparation cards expected in the deck")

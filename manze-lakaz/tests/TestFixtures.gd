class_name TestFixtures
extends RefCounted
## A small synthetic CardDatabase for rule tests. Deliberately independent
## of res://data/*.json: balance numbers change constantly, and rule tests
## must not break every time someone retunes a copy count.

## oil x4, fish x3, salt x3 ingredients; grinding x3, chopping x2 preparations.
## dish_a needs oil+fish+grinding. dish_b needs salt+oil+chopping.
## dish_c..dish_f are trivial extra recipes (reusing the same defs) that only
## exist so draft tests have a big enough pool to offer 3-at-a-time.
static func tiny_database() -> CardDatabase:
	var db := CardDatabase.new()
	_add_ingredient(db, "oil", "Oil", 4)
	_add_ingredient(db, "fish", "Fish", 3)
	_add_ingredient(db, "salt", "Salt", 3)
	_add_preparation(db, "grinding", "Grinding", 3)
	_add_preparation(db, "chopping", "Chopping", 2)
	_add_recipe(db, "dish_a", "Test Dish A", "quick", ["oil", "fish"], ["grinding"])
	_add_recipe(db, "dish_b", "Test Dish B", "quick", ["salt", "oil"], ["chopping"])
	_add_recipe(db, "dish_c", "Test Dish C", "quick", ["oil", "salt"], ["grinding"])
	_add_recipe(db, "dish_d", "Test Dish D", "quick", ["fish", "salt"], ["chopping"])
	_add_recipe(db, "dish_e", "Test Dish E", "feast", ["oil", "fish", "salt"], ["grinding", "chopping"])
	_add_recipe(db, "dish_f", "Test Dish F", "feast", ["fish", "oil", "salt"], ["chopping", "grinding"])
	return db

static func default_config() -> GameConfig:
	var c := GameConfig.new()
	c.num_players = 2
	c.recipes_per_player = 1
	c.draft_pool_size = 2
	c.hand_limit = 7
	c.seed = 42
	return c

## Matches the real default rules (draft_pool_size 3, recipes_per_player 2);
## needs tiny_database()'s full 6 recipes to have enough pool for 2 players.
static func draft_config(num_players: int = 2, seed: int = 7) -> GameConfig:
	var c := GameConfig.new()
	c.num_players = num_players
	c.recipes_per_player = 2
	c.draft_pool_size = 3
	c.hand_limit = 7
	c.seed = seed
	return c

## Bare GameState with N players/recipes but no cards dealt anywhere; tests
## populate hands/deck/discard/attachments by hand for precise control.
static func bare_state(config: GameConfig, db: CardDatabase, recipe_id_per_player: Array[String]) -> GameState:
	var state := GameState.new(config, db)
	for i in recipe_id_per_player.size():
		var p := Player.new(i)
		p.recipes.append(Recipe.new(db.recipe_defs[recipe_id_per_player[i]]))
		state.players.append(p)
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE
	return state

## Deterministic instance-id allocator for hand-built test cards, so tests
## never accidentally collide instance ids within one state.
static func make_card_allocator() -> Callable:
	var next_id := {"v": 0}
	return func(def_id: String, category: int) -> Card:
		var id: int = next_id["v"]
		next_id["v"] = id + 1
		return Card.new(id, def_id, category)

static func _add_ingredient(db: CardDatabase, id: String, name: String, copies: int) -> void:
	db.ingredient_defs[id] = CardDef.new(id, name, CardDef.Category.INGREDIENT, copies)
	db.ingredient_order.append(id)

static func _add_preparation(db: CardDatabase, id: String, name: String, copies: int) -> void:
	db.preparation_defs[id] = CardDef.new(id, name, CardDef.Category.PREPARATION, copies)
	db.preparation_order.append(id)

static func _add_recipe(db: CardDatabase, id: String, name: String, tier: String, ingredients: Array, preparations: Array) -> void:
	var rd := RecipeDef.new()
	rd.id = id
	rd.display_name = name
	rd.country = "Testland"
	rd.tier = RecipeDef.Tier.QUICK if tier == "quick" else RecipeDef.Tier.FEAST
	for iid in ingredients:
		rd.ingredient_ids.append(String(iid))
	for pid in preparations:
		rd.preparation_ids.append(String(pid))
	db.recipe_defs[id] = rd
	db.recipe_order.append(id)

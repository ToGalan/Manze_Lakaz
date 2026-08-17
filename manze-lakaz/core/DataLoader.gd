class_name DataLoader
extends RefCounted
## Loads res://data/*.json into a CardDatabase and validates it. Validation
## failures are collected (not thrown) so callers can decide how loudly to
## fail; load_database_or_fail() is the convenience path that prints every
## error and returns null.

class LoadResult:
	var ok: bool = false
	var database: CardDatabase = null
	var errors: Array[String] = []

static func load_database(ingredients_path: String, preparations_path: String, recipes_path: String) -> LoadResult:
	var result := LoadResult.new()
	var db := CardDatabase.new()

	var ing_json := _read_json(ingredients_path, result.errors)
	var prep_json := _read_json(preparations_path, result.errors)
	var rec_json := _read_json(recipes_path, result.errors)

	if not result.errors.is_empty():
		return result

	var ing_sum := _load_card_defs(ing_json, ingredients_path, CardDef.Category.INGREDIENT, db.ingredient_defs, db.ingredient_order, result.errors)
	var prep_sum := _load_card_defs(prep_json, preparations_path, CardDef.Category.PREPARATION, db.preparation_defs, db.preparation_order, result.errors)

	_check_declared_total(ing_json, ing_sum, ingredients_path, result.errors)
	_check_declared_total(prep_json, prep_sum, preparations_path, result.errors)

	_load_recipe_defs(rec_json, recipes_path, db, result.errors)

	if not result.errors.is_empty():
		result.database = db
		result.ok = false
		return result

	_validate_recipe_references(db, result.errors)
	_validate_every_type_used(db, result.errors)

	result.database = db
	result.ok = result.errors.is_empty()
	return result

static func load_database_or_fail(ingredients_path: String, preparations_path: String, recipes_path: String) -> CardDatabase:
	var result := load_database(ingredients_path, preparations_path, recipes_path)
	if not result.ok:
		printerr("=== Manze Lakaz data validation FAILED ===")
		for e in result.errors:
			printerr(" - " + e)
		printerr("===========================================")
		return null
	return result.database

# ---------------------------------------------------------------------------

static func _load_card_defs(json: Dictionary, path: String, category: int, defs_out: Dictionary, order_out: Array[String], errors: Array[String]) -> int:
	var sum := 0
	var cards = json.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		errors.append("Expected 'cards' array in %s" % path)
		return sum
	for entry in cards:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("id") or not entry.has("name") or not entry.has("copies"):
			errors.append("Malformed card entry in %s: %s" % [path, str(entry)])
			continue
		var id: String = entry["id"]
		var copies: int = int(entry["copies"])
		if defs_out.has(id):
			errors.append("Duplicate card id '%s' in %s" % [id, path])
			continue
		if copies <= 0:
			errors.append("Card '%s' in %s has non-positive copy count %d" % [id, path, copies])
			continue
		var ingredient_type := String(entry.get("type", ""))
		if category == CardDef.Category.INGREDIENT and not CardDef.ALL_INGREDIENT_TYPES.has(ingredient_type):
			errors.append("Ingredient '%s' in %s has missing/unknown 'type' '%s' (expected one of %s)" % [id, path, ingredient_type, CardDef.ALL_INGREDIENT_TYPES])
			continue
		var is_joker := bool(entry.get("joker", false))
		var def := CardDef.new(id, entry["name"], category, copies, ingredient_type, is_joker)
		defs_out[id] = def
		order_out.append(id)
		sum += copies
	return sum

static func _check_declared_total(json: Dictionary, actual_sum: int, path: String, errors: Array[String]) -> void:
	if not json.has("total"):
		return
	var declared := int(json["total"])
	if actual_sum != declared:
		errors.append("%s: copy counts sum to %d but declared total is %d" % [path, actual_sum, declared])

static func _load_recipe_defs(json: Dictionary, path: String, db: CardDatabase, errors: Array[String]) -> void:
	var cards = json.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		errors.append("Expected 'cards' array in %s" % path)
		return
	for entry in cards:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("id") or not entry.has("name") or not entry.has("tier"):
			errors.append("Malformed recipe entry in %s: %s" % [path, str(entry)])
			continue
		var rd := RecipeDef.new()
		rd.id = entry["id"]
		rd.display_name = entry["name"]
		rd.country = entry.get("country", "")
		var tier_str: String = String(entry["tier"]).to_lower()
		if tier_str == "quick":
			rd.tier = RecipeDef.Tier.QUICK
		elif tier_str == "feast":
			rd.tier = RecipeDef.Tier.FEAST
		else:
			errors.append("Recipe '%s' in %s has unknown tier '%s' (expected 'quick' or 'feast')" % [rd.id, path, tier_str])
			continue
		var ingredients = entry.get("ingredients", [])
		for iid in ingredients:
			rd.ingredient_ids.append(String(iid))
		var preparations = entry.get("preparations", [])
		for pid in preparations:
			rd.preparation_ids.append(String(pid))
		rd.uses_grill = entry.get("uses_grill", false)
		_load_real_recipe(rd, entry.get("real_recipe", {}), path, errors)
		if rd.ingredient_ids.is_empty() and rd.preparation_ids.is_empty():
			errors.append("Recipe '%s' in %s has no ingredients or preparations" % [rd.id, path])
			continue
		if db.recipe_defs.has(rd.id):
			errors.append("Duplicate recipe id '%s' in %s" % [rd.id, path])
			continue
		db.recipe_defs[rd.id] = rd
		db.recipe_order.append(rd.id)

## real_recipe is purely flavor text (shown on completion), never read by
## RulesEngine -- so a missing/empty block is fine, but a malformed one
## (wrong shape) still fails validation, same as any other data error.
static func _load_real_recipe(rd: RecipeDef, entry: Dictionary, path: String, errors: Array[String]) -> void:
	if entry.is_empty():
		return
	var ingredients = entry.get("ingredients", [])
	if typeof(ingredients) != TYPE_ARRAY:
		errors.append("Recipe '%s' in %s has a malformed real_recipe.ingredients (expected an array)" % [rd.id, path])
	else:
		for ing in ingredients:
			if typeof(ing) != TYPE_DICTIONARY or not ing.has("name") or not ing.has("quantity"):
				errors.append("Recipe '%s' in %s has a malformed real_recipe ingredient entry: %s" % [rd.id, path, str(ing)])
				continue
			rd.real_ingredients.append({"name": String(ing["name"]), "quantity": String(ing["quantity"])})
	rd.prep_time_minutes = int(entry.get("prep_time_minutes", 0))
	rd.cook_time_minutes = int(entry.get("cook_time_minutes", 0))
	var steps = entry.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		errors.append("Recipe '%s' in %s has a malformed real_recipe.steps (expected an array)" % [rd.id, path])
	else:
		for step in steps:
			rd.prep_steps.append(String(step))

static func _validate_recipe_references(db: CardDatabase, errors: Array[String]) -> void:
	for rid in db.recipe_order:
		var rd: RecipeDef = db.recipe_defs[rid]
		for iid in rd.ingredient_ids:
			if not db.ingredient_defs.has(iid):
				errors.append("Recipe '%s' references unknown ingredient '%s' (not in the deck)" % [rid, iid])
		for pid in rd.preparation_ids:
			if not db.preparation_defs.has(pid):
				errors.append("Recipe '%s' references unknown preparation '%s' (not in the deck)" % [rid, pid])

static func _validate_every_type_used(db: CardDatabase, errors: Array[String]) -> void:
	var used_ingredients: Dictionary = {}
	var used_preps: Dictionary = {}
	for rid in db.recipe_order:
		var rd: RecipeDef = db.recipe_defs[rid]
		for iid in rd.ingredient_ids:
			used_ingredients[iid] = true
		for pid in rd.preparation_ids:
			used_preps[pid] = true
	for iid in db.ingredient_order:
		# Joker ingredients deliberately never appear in a recipe's literal
		# ingredient_ids -- they stand in for a whole category (see
		# CardDef.is_joker), so "unused" is expected and correct for them.
		if not db.ingredient_defs[iid].is_joker and not used_ingredients.has(iid):
			errors.append("Ingredient '%s' does not appear in any recipe" % iid)
	for pid in db.preparation_order:
		if not used_preps.has(pid):
			errors.append("Preparation '%s' does not appear in any recipe" % pid)

static func _read_json(path: String, errors: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("Data file not found: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("Could not open data file: %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		errors.append("JSON parse error in %s at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("Expected a top-level JSON object in %s" % path)
		return {}
	return data

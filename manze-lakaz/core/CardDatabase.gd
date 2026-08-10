class_name CardDatabase
extends RefCounted
## In-memory index of every card/recipe definition, built by DataLoader from
## res://data. This is the single source of truth the rules engine reads
## from; nothing in core/ hardcodes card names or counts.

var ingredient_defs: Dictionary = {}  # def_id -> CardDef
var preparation_defs: Dictionary = {} # def_id -> CardDef
var recipe_defs: Dictionary = {}      # recipe_id -> RecipeDef

var ingredient_order: Array[String] = []
var preparation_order: Array[String] = []
var recipe_order: Array[String] = []

func get_ingredient_def(def_id: String) -> CardDef:
	return ingredient_defs.get(def_id)

func get_preparation_def(def_id: String) -> CardDef:
	return preparation_defs.get(def_id)

func get_card_def(def_id: String, category: int) -> CardDef:
	if category == CardDef.Category.INGREDIENT:
		return ingredient_defs.get(def_id)
	return preparation_defs.get(def_id)

## Builds one fresh, unshuffled 92-card deck of distinct Card instances.
func build_deck() -> Array[Card]:
	var deck: Array[Card] = []
	var next_id := 0
	for id in ingredient_order:
		var def: CardDef = ingredient_defs[id]
		for i in def.copies:
			deck.append(Card.new(next_id, id, CardDef.Category.INGREDIENT))
			next_id += 1
	for id in preparation_order:
		var def: CardDef = preparation_defs[id]
		for i in def.copies:
			deck.append(Card.new(next_id, id, CardDef.Category.PREPARATION))
			next_id += 1
	return deck

func quick_recipe_ids() -> Array[String]:
	var out: Array[String] = []
	for id in recipe_order:
		if recipe_defs[id].tier == RecipeDef.Tier.QUICK:
			out.append(id)
	return out

func feast_recipe_ids() -> Array[String]:
	var out: Array[String] = []
	for id in recipe_order:
		if recipe_defs[id].tier == RecipeDef.Tier.FEAST:
			out.append(id)
	return out

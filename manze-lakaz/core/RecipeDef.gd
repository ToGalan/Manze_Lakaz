class_name RecipeDef
extends RefCounted
## Static definition of a recipe card, loaded from res://data/recipes.json.
## Recipes are not part of the 92-card deck.

enum Tier { QUICK, FEAST }

var id: String
var display_name: String
var country: String
var tier: int
var ingredient_ids: Array[String] = []
var preparation_ids: Array[String] = []
var uses_grill: bool = false

func total_required_slots() -> int:
	return ingredient_ids.size() + preparation_ids.size()

func requires_ingredient(def_id: String) -> bool:
	return ingredient_ids.has(def_id)

func requires_preparation(def_id: String) -> bool:
	return preparation_ids.has(def_id)

func tier_name() -> String:
	return "quick" if tier == Tier.QUICK else "feast"

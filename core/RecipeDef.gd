class_name RecipeDef
extends RefCounted
## Static definition of a recipe card, loaded from res://data/recipes.json.
## Recipes are not part of the 92-card deck.

enum Tier { EASY, MEDIUM, HARD }

var id: String
var display_name: String
var country: String
var tier: int
var ingredient_ids: Array[String] = []
var preparation_ids: Array[String] = []
var uses_grill: bool = false

## Real-world recipe info, shown as a reveal once the dish is completed
## in-game. Purely flavor -- never read by RulesEngine. Array[{name:
## String, quantity: String}]; a recipe with none of this data set just
## renders an empty ingredients list and 0 for both times.
var real_ingredients: Array = []
var prep_time_minutes: int = 0
var cook_time_minutes: int = 0
var prep_steps: Array[String] = []

func total_required_slots() -> int:
	return ingredient_ids.size() + preparation_ids.size()

func total_time_minutes() -> int:
	return prep_time_minutes + cook_time_minutes

func requires_ingredient(def_id: String) -> bool:
	return ingredient_ids.has(def_id)

func requires_preparation(def_id: String) -> bool:
	return preparation_ids.has(def_id)

func tier_name() -> String:
	match tier:
		Tier.EASY:
			return "easy"
		Tier.MEDIUM:
			return "medium"
		_:
			return "hard"

class_name CardCategoryMap
extends RefCounted
## Presentational-only categorization for color-coding card faces (Protein /
## Vegetable / Pantry / Preparation). This has zero effect on rules -- it
## exists purely so cards read at a glance. Deliberately NOT part of
## res://data or res://core: the engine has no concept of these categories.

const PROTEIN := "protein"
const VEGETABLE := "vegetable"
const PANTRY := "pantry"
const PREPARATION := "preparation"

const _INGREDIENT_CATEGORY := {
	"oil": PANTRY,
	"island_spice_blend": PANTRY,
	"garlic": VEGETABLE,
	"chicken": PROTEIN,
	"salt_pepper": PANTRY,
	"onion": VEGETABLE,
	"chili": VEGETABLE,
	"coconut_milk": PANTRY,
	"fish": PROTEIN,
	"fresh_herbs": VEGETABLE,
	"tomato": VEGETABLE,
	"beef": PROTEIN,
	"goat": PROTEIN,
	"lime": VEGETABLE,
	"pork": PROTEIN,
	"lamb": PROTEIN,
	"joker_protein": PROTEIN,
	"joker_vegetable": VEGETABLE,
	"joker_pantry": PANTRY,
}

## Unknown ingredient ids (e.g. after a balance-data edit adds a new one)
## fall back to Pantry rather than erroring -- this is decorative only.
static func category_for(def_id: String, category: int) -> String:
	if category == CardDef.Category.PREPARATION:
		return PREPARATION
	return _INGREDIENT_CATEGORY.get(def_id, PANTRY)

static func theme_variation_for(category_key: String) -> String:
	match category_key:
		PROTEIN:
			return "CardFaceProtein"
		VEGETABLE:
			return "CardFaceVegetable"
		PANTRY:
			return "CardFacePantry"
		PREPARATION:
			return "CardFacePreparation"
	return "CardFaceBack"

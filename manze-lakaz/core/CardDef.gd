class_name CardDef
extends RefCounted
## Static definition of a card type (e.g. "Oil" or "Chopping"), loaded from res://data.
## Not an in-play card instance -- see Card.gd for that.

enum Category { INGREDIENT, PREPARATION }

## Ingredient sub-category, required for every INGREDIENT card def (empty for
## PREPARATION defs). This is the rules-relevant grouping a joker card
## matches against -- not to be confused with ui/CardCategoryMap.gd, which
## is a separate, presentation-only color-coding lookup.
const TYPE_PROTEIN := "protein"
const TYPE_VEGETABLE := "vegetable"
const TYPE_PANTRY := "pantry"
const ALL_INGREDIENT_TYPES := [TYPE_PROTEIN, TYPE_VEGETABLE, TYPE_PANTRY]

var id: String
var display_name: String
var category: int
var copies: int
var ingredient_type: String
var is_joker: bool

func _init(p_id: String = "", p_name: String = "", p_category: int = Category.INGREDIENT, p_copies: int = 0, p_ingredient_type: String = "", p_is_joker: bool = false) -> void:
	id = p_id
	display_name = p_name
	category = p_category
	copies = p_copies
	ingredient_type = p_ingredient_type
	is_joker = p_is_joker

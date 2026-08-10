class_name CardDef
extends RefCounted
## Static definition of a card type (e.g. "Oil" or "Chopping"), loaded from res://data.
## Not an in-play card instance -- see Card.gd for that.

enum Category { INGREDIENT, PREPARATION }

var id: String
var display_name: String
var category: int
var copies: int

func _init(p_id: String = "", p_name: String = "", p_category: int = Category.INGREDIENT, p_copies: int = 0) -> void:
	id = p_id
	display_name = p_name
	category = p_category
	copies = p_copies

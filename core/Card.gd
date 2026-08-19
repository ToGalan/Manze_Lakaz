class_name Card
extends RefCounted
## A single physical card instance in play. instance_id is unique per copy
## across the whole deck, so a steal/attach/discard can always name one
## exact card even when several copies of the same def_id exist.

var instance_id: int
var def_id: String
var category: int # CardDef.Category

func _init(p_instance_id: int = -1, p_def_id: String = "", p_category: int = CardDef.Category.INGREDIENT) -> void:
	instance_id = p_instance_id
	def_id = p_def_id
	category = p_category

func is_ingredient() -> bool:
	return category == CardDef.Category.INGREDIENT

func is_preparation() -> bool:
	return category == CardDef.Category.PREPARATION

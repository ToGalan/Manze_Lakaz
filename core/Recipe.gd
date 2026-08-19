class_name Recipe
extends RefCounted
## A recipe card in play in front of a player: its static def plus whatever
## has been attached to it so far.

var def: RecipeDef
var filled_ingredients: Dictionary = {}  # def_id (String) -> Card
var filled_preparations: Dictionary = {} # def_id (String) -> Card
var decoys: Array[Card] = []             # DECOYS_ENABLED off-recipe ingredient attachments
var completed: bool = false

func _init(p_def: RecipeDef = null) -> void:
	def = p_def

func is_ingredient_slot_open(def_id: String) -> bool:
	return def.requires_ingredient(def_id) and not filled_ingredients.has(def_id)

func is_preparation_slot_open(def_id: String) -> bool:
	return def.requires_preparation(def_id) and not filled_preparations.has(def_id)

## slot_def_id: which required slot this card fills. Defaults to the card's
## own def_id (true for every normal card); a joker card names a different,
## specific def_id here since its own def_id is never itself a required slot.
func attach_ingredient_to_slot(card: Card, slot_def_id: String = "") -> void:
	filled_ingredients[slot_def_id if slot_def_id != "" else card.def_id] = card
	_check_completion()

func attach_preparation_to_slot(card: Card, slot_def_id: String = "") -> void:
	filled_preparations[slot_def_id if slot_def_id != "" else card.def_id] = card
	_check_completion()

func attach_decoy(card: Card) -> void:
	decoys.append(card)

func _check_completion() -> void:
	completed = filled_ingredients.size() == def.ingredient_ids.size() \
		and filled_preparations.size() == def.preparation_ids.size()

## All attached ingredient cards (required-slot fills and decoys), the set
## that is potentially stealable while this recipe is incomplete.
func all_attached_ingredient_cards() -> Array[Card]:
	var out: Array[Card] = []
	for c in filled_ingredients.values():
		out.append(c)
	for c in decoys:
		out.append(c)
	return out

## Cards on this recipe eligible to be stolen right now.
func stealable_ingredient_cards() -> Array[Card]:
	if completed:
		return []
	return all_attached_ingredient_cards()

func find_attached_card(instance_id: int) -> Card:
	for c in filled_ingredients.values():
		if c.instance_id == instance_id:
			return c
	for c in filled_preparations.values():
		if c.instance_id == instance_id:
			return c
	for c in decoys:
		if c.instance_id == instance_id:
			return c
	return null

## Remove and return a stealable card by instance id, or null if not found/eligible.
func remove_stealable_card(instance_id: int) -> Card:
	if completed:
		return null
	for def_id in filled_ingredients.keys():
		var c: Card = filled_ingredients[def_id]
		if c.instance_id == instance_id:
			filled_ingredients.erase(def_id)
			return c
	for i in decoys.size():
		if decoys[i].instance_id == instance_id:
			return decoys.pop_at(i)
	return null

## Remove and return an attached preparation card by instance id, or null if
## not found. Unlike remove_stealable_card, this has no completed-recipe
## guard of its own -- callers (RulesEngine) are responsible for only ever
## moving a preparation off a recipe that isn't completed, exactly as they
## already restrict which recipes are stealable-from.
func remove_preparation(instance_id: int) -> Card:
	for def_id in filled_preparations.keys():
		var c: Card = filled_preparations[def_id]
		if c.instance_id == instance_id:
			filled_preparations.erase(def_id)
			return c
	return null

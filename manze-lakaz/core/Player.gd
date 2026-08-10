class_name Player
extends RefCounted

var index: int
var team_id: int = 0
var hand: Array[Card] = []
var recipes: Array[Recipe] = []
var steals_used: int = 0

func _init(p_index: int = -1) -> void:
	index = p_index

func has_completed_recipe() -> bool:
	for r in recipes:
		if r.completed:
			return true
	return false

func completed_recipe() -> Recipe:
	for r in recipes:
		if r.completed:
			return r
	return null

func find_in_hand(instance_id: int) -> Card:
	for c in hand:
		if c.instance_id == instance_id:
			return c
	return null

func remove_from_hand(instance_id: int) -> Card:
	for i in hand.size():
		if hand[i].instance_id == instance_id:
			return hand.pop_at(i)
	return null

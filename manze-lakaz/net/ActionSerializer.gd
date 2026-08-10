class_name ActionSerializer
extends RefCounted
## Converts Action (a RefCounted core/ class) to and from plain
## Dictionaries, since RPC payloads should be primitive Variant data, not
## live engine objects. Every field round-trips exactly.

static func serialize(a: Action) -> Dictionary:
	return {
		"type": a.type,
		"player_index": a.player_index,
		"recipe_id": a.recipe_id,
		"target_player_index": a.target_player_index,
		"target_recipe_index": a.target_recipe_index,
		"card_instance_id": a.card_instance_id,
		"recipe_index": a.recipe_index,
		"as_decoy": a.as_decoy,
	}

static func deserialize(d: Dictionary) -> Action:
	var a := Action.new()
	a.type = d.get("type", -1)
	a.player_index = d.get("player_index", -1)
	a.recipe_id = d.get("recipe_id", "")
	a.target_player_index = d.get("target_player_index", -1)
	a.target_recipe_index = d.get("target_recipe_index", -1)
	a.card_instance_id = d.get("card_instance_id", -1)
	a.recipe_index = d.get("recipe_index", -1)
	a.as_decoy = d.get("as_decoy", false)
	return a

static func serialize_list(actions: Array) -> Array:
	var out := []
	for a in actions:
		out.append(serialize(a))
	return out

static func deserialize_list(dicts: Array) -> Array[Action]:
	var out: Array[Action] = []
	for d in dicts:
		out.append(deserialize(d))
	return out

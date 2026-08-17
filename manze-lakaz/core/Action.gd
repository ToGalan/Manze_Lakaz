class_name Action
extends RefCounted
## One legal move. Every state transition in RulesEngine goes through an
## Action produced by get_legal_actions() and consumed by apply_action().

enum Type { DRAFT_KEEP, DRAW, STEAL, ATTACH, DISCARD, TAKE_DISCARD, MOVE_PREPARATION }

var type: int
var player_index: int = -1

## DRAFT_KEEP only: which offered recipe id the player is keeping.
var recipe_id: String = ""

## STEAL only: whose recipe the card is being taken from and which recipe slot.
var target_player_index: int = -1
var target_recipe_index: int = -1

## ATTACH/DISCARD/STEAL: the exact card instance this action operates on.
## For ATTACH this is a card in the acting player's hand; for STEAL it is a
## card currently attached to target_player's target_recipe.
var card_instance_id: int = -1

## ATTACH: which of the acting player's own recipes to attach to.
## MOVE_PREPARATION: the recipe the preparation card is currently on (the
## "from" side of the move -- see move_to_recipe_index for the "to" side).
var recipe_index: int = -1

## ATTACH only: true if this attaches an ingredient that does not fill an
## open required slot (only possible when DECOYS_ENABLED is on).
var as_decoy: bool = false

## ATTACH only (non-decoy): the specific required slot def_id this card is
## filling. Equal to the card's own def_id for a normal card, but may name a
## different def_id when the card is a joker (CardDef.is_joker) standing in
## for one specific open slot of its own ingredient_type.
var target_def_id: String = ""

## MOVE_PREPARATION only: which of the acting player's own recipes the
## preparation card is being moved to.
var move_to_recipe_index: int = -1

static func make_draft_keep(player_index: int, recipe_id: String) -> Action:
	var a := Action.new()
	a.type = Type.DRAFT_KEEP
	a.player_index = player_index
	a.recipe_id = recipe_id
	return a

static func make_draw(player_index: int) -> Action:
	var a := Action.new()
	a.type = Type.DRAW
	a.player_index = player_index
	return a

static func make_take_discard(player_index: int) -> Action:
	var a := Action.new()
	a.type = Type.TAKE_DISCARD
	a.player_index = player_index
	return a

static func make_steal(player_index: int, target_player_index: int, target_recipe_index: int, card_instance_id: int) -> Action:
	var a := Action.new()
	a.type = Type.STEAL
	a.player_index = player_index
	a.target_player_index = target_player_index
	a.target_recipe_index = target_recipe_index
	a.card_instance_id = card_instance_id
	return a

static func make_attach(player_index: int, card_instance_id: int, recipe_index: int, as_decoy: bool, target_def_id: String = "") -> Action:
	var a := Action.new()
	a.type = Type.ATTACH
	a.player_index = player_index
	a.card_instance_id = card_instance_id
	a.recipe_index = recipe_index
	a.as_decoy = as_decoy
	a.target_def_id = target_def_id
	return a

static func make_discard(player_index: int, card_instance_id: int) -> Action:
	var a := Action.new()
	a.type = Type.DISCARD
	a.player_index = player_index
	a.card_instance_id = card_instance_id
	return a

static func make_move_preparation(player_index: int, card_instance_id: int, from_recipe_index: int, to_recipe_index: int) -> Action:
	var a := Action.new()
	a.type = Type.MOVE_PREPARATION
	a.player_index = player_index
	a.card_instance_id = card_instance_id
	a.recipe_index = from_recipe_index
	a.move_to_recipe_index = to_recipe_index
	return a

func equals(other: Action) -> bool:
	if other == null or other.type != type or other.player_index != player_index:
		return false
	match type:
		Type.DRAFT_KEEP:
			return other.recipe_id == recipe_id
		Type.DRAW:
			return true
		Type.STEAL:
			return other.target_player_index == target_player_index \
				and other.target_recipe_index == target_recipe_index \
				and other.card_instance_id == card_instance_id
		Type.ATTACH:
			return other.card_instance_id == card_instance_id \
				and other.recipe_index == recipe_index \
				and other.as_decoy == as_decoy \
				and other.target_def_id == target_def_id
		Type.DISCARD:
			return other.card_instance_id == card_instance_id
		Type.TAKE_DISCARD:
			return true
		Type.MOVE_PREPARATION:
			return other.card_instance_id == card_instance_id \
				and other.recipe_index == recipe_index \
				and other.move_to_recipe_index == move_to_recipe_index
	return false

func describe() -> String:
	match type:
		Type.DRAFT_KEEP:
			return "P%d: KEEP recipe '%s'" % [player_index, recipe_id]
		Type.DRAW:
			return "P%d: DRAW" % player_index
		Type.STEAL:
			return "P%d: STEAL card#%d from P%d recipe#%d" % [player_index, card_instance_id, target_player_index, target_recipe_index]
		Type.ATTACH:
			var slot_note := "" if as_decoy else " as %s" % target_def_id
			return "P%d: ATTACH card#%d to recipe#%d%s%s" % [player_index, card_instance_id, recipe_index, slot_note, (" (decoy)" if as_decoy else "")]
		Type.DISCARD:
			return "P%d: DISCARD card#%d" % [player_index, card_instance_id]
		Type.MOVE_PREPARATION:
			return "P%d: MOVE prep card#%d from recipe#%d to recipe#%d" % [player_index, card_instance_id, recipe_index, move_to_recipe_index]
	return "P%d: <unknown action>" % player_index

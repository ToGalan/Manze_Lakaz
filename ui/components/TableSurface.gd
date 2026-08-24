extends Control
class_name TableSurface
## The shared table: a custom-drawn felt trapezoid (a cheap, layout-safe way
## to suggest a low-angle perspective view without fighting Control's
## anchor-based layout system with real skew transforms), holding the
## shared deck/discard piles and the active player's own recipe tableau.

## The discard pile's own card face was clicked while taking it was legal.
signal take_discard_requested

const CARD_SCENE := preload("res://ui/components/CardFace.tscn")
const TABLECLOTH_TEXTURE := preload("res://ui/art/MLtexture_tablePlaid.png")
const PILE_CARD_SIZE := Vector2(96, 130)

var own_recipes_box: HBoxContainer
var deck_pile: PanelContainer
var discard_pile: PanelContainer

var _deck_count_label: Label
var _discard_count_label: Label
var _discard_card: CardFace

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED # lets the tablecloth texture tile across the trapezoid instead of stretching to fit it
	resized.connect(queue_redraw)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	# No ScrollContainer: the table never scrolls, so its own available
	# height has to genuinely fit the tallest recipe panel (see
	# GameScreen._on_screen_resized(), which sizes hand_fan/prompt_panel to
	# leave the table enough room, and _build_own_recipe_panel(), which
	# keeps each recipe panel's own rows compact). A plain CenterContainer
	# centers `row` within whatever this margin gives it with no extra sync
	# needed (unlike ScrollContainer, it hands a smaller child the rest of
	# its available space itself).
	var center := CenterContainer.new()
	margin.add_child(center)

	var row := HBoxContainer.new()
	# TableGroupHBox (56px), not WideHBox (18px) -- own_recipes_box and
	# piles_row each read as their own group, and need more separation
	# from each other than either needs internally (recipe-to-recipe,
	# deck-to-discard). See GameTheme._setup_containers().
	row.theme_type_variation = "TableGroupHBox"
	center.add_child(row)

	own_recipes_box = HBoxContainer.new()
	own_recipes_box.theme_type_variation = "WideHBox"
	row.add_child(own_recipes_box)

	var piles_row := HBoxContainer.new()
	piles_row.theme_type_variation = "WideHBox"
	# Without this, HBoxContainer's default vertical FILL stretches piles_row
	# to match `row`'s full cross-axis height -- which is set by the tallest
	# sibling, own_recipes_box (a multi-line recipe panel can run much taller
	# than a card). That stretch then cascades into deck_pile/discard_pile
	# (also default FILL) growing to fill it, ballooning each PilePanel's
	# background far past its fixed-size CardFace and making the two piles
	# read as oversized/disproportionate next to their own card art. Shrink-
	# centering here keeps both piles at their natural content height,
	# vertically centered alongside whatever height the recipe column ends
	# up needing.
	piles_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(piles_row)

	deck_pile = _build_pile("Deck")
	piles_row.add_child(deck_pile)
	_deck_count_label = deck_pile.get_meta("count_label")
	var deck_card: CardFace = deck_pile.get_meta("card_face")
	# set_face_down() touches @onready fields that only resolve once this
	# node is actually inside the SceneTree -- still not true here, since
	# _init() runs while the whole TableSurface subtree is being built
	# detached, before GameScreen parents it in. Deferring lets it run once
	# this frame's tree insertion has actually happened.
	deck_card.set_face_down.call_deferred()
	deck_card.disabled = true

	discard_pile = _build_pile("Discard")
	piles_row.add_child(discard_pile)
	_discard_count_label = discard_pile.get_meta("count_label")
	_discard_card = discard_pile.get_meta("card_face")
	_discard_card.set_face_down.call_deferred()
	_discard_card.disabled = true
	_discard_card.pressed.connect(func(): take_discard_requested.emit())

func _build_pile(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "PilePanel"

	var box := VBoxContainer.new()
	box.theme_type_variation = "TightVBox"
	panel.add_child(box)

	var title_label := Label.new()
	title_label.theme_type_variation = "PileSectionLabel"
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)

	var card_face: CardFace = CARD_SCENE.instantiate()
	box.add_child(card_face)
	card_face.custom_minimum_size = PILE_CARD_SIZE
	card_face.size = PILE_CARD_SIZE
	panel.set_meta("card_face", card_face)

	var count_label := Label.new()
	count_label.theme_type_variation = "PileBadgeLabel"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(count_label)
	panel.set_meta("count_label", count_label)

	return panel

## discard_top: {label, category_key, def_id} describing the discard pile's
## top card, or an empty Dictionary if the pile is empty. discard_takeable:
## whether TAKE_DISCARD is currently a legal action for the acting player.
func update_piles(deck_count: int, discard_count: int, discard_top: Dictionary, discard_takeable: bool) -> void:
	_deck_count_label.text = "%d cards" % deck_count
	_discard_count_label.text = "%d cards" % discard_count
	if discard_top.is_empty():
		_discard_card.set_face_down()
		_discard_card.disabled = true
	else:
		_discard_card.setup(discard_top["label"], discard_top["category_key"], -1, discard_top["def_id"])
		_discard_card.disabled = not discard_takeable

func get_deck_marker_global_position() -> Vector2:
	return deck_pile.global_position + deck_pile.size * 0.5

func get_discard_marker_global_position() -> Vector2:
	return discard_pile.global_position + discard_pile.size * 0.5

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var top_inset := size.x * 0.07
	var points := PackedVector2Array([
		Vector2(top_inset, 0),
		Vector2(size.x - top_inset, 0),
		Vector2(size.x, size.y),
		Vector2(0, size.y),
	])
	var colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var tex_size := TABLECLOTH_TEXTURE.get_size()
	var uvs := PackedVector2Array()
	for p in points:
		uvs.append(p / tex_size)
	draw_polygon(points, colors, uvs, TABLECLOTH_TEXTURE)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), GameTheme.COLOR_FELT_EDGE, 3.0, true)

extends Control
class_name TableSurface
## The shared table: a custom-drawn felt trapezoid (a cheap, layout-safe way
## to suggest a low-angle perspective view without fighting Control's
## anchor-based layout system with real skew transforms), holding the
## shared deck/discard piles and the active player's own recipe tableau.

## The discard pile's own card face was clicked while taking it was legal.
signal take_discard_requested

const CARD_SCENE := preload("res://ui/components/CardFace.tscn")
const PILE_CARD_SIZE := Vector2(96, 130)

var own_recipes_box: HBoxContainer
var deck_pile: PanelContainer
var discard_pile: PanelContainer

var _deck_count_label: Label
var _discard_count_label: Label
var _discard_card: CardFace

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	# A ScrollContainer (not a bare CenterContainer) so a recipe with many
	# required slots -- a Feast dish can be 6 ingredients + 2 preparations
	# + grill, 9+ rows in one panel -- scrolls and clips to the table's own
	# bounds instead of overflowing past it into whatever control sits
	# below (the prompt bar), which is what "overlaps and blocks the list"
	# actually was: not a z-order bug, a missing-clip bug.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margin.add_child(scroll)

	# ScrollContainer never hands its child more than the child's own
	# minimum size -- it does NOT honor size_flags like SHRINK_CENTER and
	# does NOT give a smaller child the rest of its available space, so the
	# row would otherwise sit pinned at the top-left with dead space to the
	# right/bottom instead of actually being centered. A CenterContainer
	# whose minimum size is forced to match the scroll view (kept in sync
	# on resize) is what makes it genuinely center -- and once the row's
	# real content outgrows that floor, its minimum grows past it and
	# scrolling takes over exactly as before.
	var center := CenterContainer.new()
	scroll.add_child(center)

	var row := HBoxContainer.new()
	row.theme_type_variation = "WideHBox"
	center.add_child(row)

	# Deferred for the same reason as the CardFace setup below: _init() runs
	# while this whole subtree is still detached (TableSurface itself isn't
	# parented into GameScreen's live tree yet), so scroll.size would read
	# (0, 0) if read synchronously here.
	_sync_center_to_scroll.call_deferred(scroll, center)
	scroll.resized.connect(_sync_center_to_scroll.bind(scroll, center))

	own_recipes_box = HBoxContainer.new()
	own_recipes_box.theme_type_variation = "WideHBox"
	row.add_child(own_recipes_box)

	var piles_col := VBoxContainer.new()
	piles_col.theme_type_variation = "WideVBox"
	row.add_child(piles_col)

	deck_pile = _build_pile("Deck")
	piles_col.add_child(deck_pile)
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
	piles_col.add_child(discard_pile)
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
	title_label.theme_type_variation = "SectionLabel"
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)

	var card_face: CardFace = CARD_SCENE.instantiate()
	box.add_child(card_face)
	card_face.custom_minimum_size = PILE_CARD_SIZE
	card_face.size = PILE_CARD_SIZE
	panel.set_meta("card_face", card_face)

	var count_label := Label.new()
	count_label.theme_type_variation = "BadgeLabel"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(count_label)
	panel.set_meta("count_label", count_label)

	return panel

func _sync_center_to_scroll(scroll: ScrollContainer, center: CenterContainer) -> void:
	center.custom_minimum_size = scroll.size

## discard_top: {label, category_key} describing the discard pile's top
## card, or an empty Dictionary if the pile is empty. discard_takeable:
## whether TAKE_DISCARD is currently a legal action for the acting player.
func update_piles(deck_count: int, discard_count: int, discard_top: Dictionary, discard_takeable: bool) -> void:
	_deck_count_label.text = "%d cards" % deck_count
	_discard_count_label.text = "%d cards" % discard_count
	if discard_top.is_empty():
		_discard_card.set_face_down()
		_discard_card.disabled = true
	else:
		_discard_card.setup(discard_top["label"], discard_top["category_key"])
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
	var colors := PackedColorArray([
		GameTheme.COLOR_FELT_DARK, GameTheme.COLOR_FELT_DARK,
		GameTheme.COLOR_FELT, GameTheme.COLOR_FELT,
	])
	draw_polygon(points, colors)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), GameTheme.COLOR_FELT_EDGE, 3.0, true)

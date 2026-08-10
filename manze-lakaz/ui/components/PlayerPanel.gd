extends PanelContainer
class_name PlayerPanel
## Top-bar identity card for one player: avatar, name, hand-count and
## recipes-completed badges, active-turn highlight, and (for opponents) a
## row of small clickable card faces for whatever they've attached --
## these ARE the steal targets, glowing when stealable. Purely a renderer:
## it is handed already-computed display data and only ever reports which
## card the user clicked; it never decides what's legal.

signal steal_requested(target_player_index: int, target_recipe_index: int, card_instance_id: int)

const CARD_SCENE := preload("res://ui/components/CardFace.tscn")
const MINI_CARD_SIZE := Vector2(56, 76)
const STEAL_ICON_RADIUS := 5.0
const STEAL_ICON_SPACING := 14.0

const AVATAR_COLORS := [
	Color8(224, 122, 95), Color8(129, 178, 154), Color8(230, 183, 88), Color8(129, 161, 193),
]

var _seat_index: int = -1
var _avatar: Control
var _name_label: Label
var _hand_label: Label
var _recipes_label: Label
var _steals_icons: Control
var _steals_label: Label
var _steals_remaining: int = 0
var _steals_total: int = 0
var _chips_col: VBoxContainer

func _init() -> void:
	# Small enough that top_bar's HFlowContainer can still fit 2+ per row
	# on a narrow/mobile viewport instead of stacking every seat into its
	# own full-width row; SIZE_EXPAND_FILL still lets it grow to fill
	# whatever room a wider window actually has.
	custom_minimum_size = Vector2(150, 0)
	size_flags_horizontal = SIZE_EXPAND_FILL

	var content := VBoxContainer.new()
	add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)

	_avatar = Control.new()
	_avatar.custom_minimum_size = Vector2(36, 36)
	_avatar.draw.connect(_draw_avatar)
	header.add_child(_avatar)

	var text_col := VBoxContainer.new()
	text_col.theme_type_variation = "TightVBox"
	text_col.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(text_col)

	_name_label = Label.new()
	_name_label.theme_type_variation = "PlayerNameLabel"
	text_col.add_child(_name_label)

	# Plain HBoxContainer, not "TightHBox" (0 separation): these are
	# adjacent text labels, not bordered card chips, so 0 separation made
	# them visually run together with no gap at all ("Hand: 3Recipes:
	# 1/2"). The base HBoxContainer's normal 8px separation is what chip
	# rows further down deliberately opt out of via TightHBox -- text
	# badges need the opposite.
	var badges := HBoxContainer.new()
	text_col.add_child(badges)

	_hand_label = Label.new()
	_hand_label.theme_type_variation = "BadgeLabel"
	badges.add_child(_hand_label)

	_recipes_label = Label.new()
	_recipes_label.theme_type_variation = "BadgeLabel"
	badges.add_child(_recipes_label)

	# Its own row, not crammed into `badges`: a row of pip icons (one per
	# allowed steal, filled while available, hollowed out once spent) plus
	# a "X/Y left" message -- both the icon count and the message
	# communicate the same cap, since a bare number is easy to miss but a
	# visibly-shrinking row of dots reads as "running out" at a glance.
	var steals_row := HBoxContainer.new()
	text_col.add_child(steals_row)

	_steals_icons = Control.new()
	_steals_icons.draw.connect(_draw_steal_icons)
	steals_row.add_child(_steals_icons)

	_steals_label = Label.new()
	_steals_label.theme_type_variation = "BadgeLabel"
	steals_row.add_child(_steals_label)

	_chips_col = VBoxContainer.new()
	_chips_col.theme_type_variation = "TightVBox"
	content.add_child(_chips_col)

func _draw_avatar() -> void:
	var color: Color = AVATAR_COLORS[_avatar.get_meta("seat", 0) % AVATAR_COLORS.size()]
	var r := _avatar.size.x * 0.5
	_avatar.draw_circle(Vector2(r, r), r, color)
	var initial: String = _avatar.get_meta("initial", "?")
	var font := ThemeDB.fallback_font
	var font_size := 18
	var text_size := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	_avatar.draw_string(font, Vector2(r - text_size.x * 0.5, r + text_size.y * 0.35), initial, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

## One pip per allowed steal: filled (COLOR_STEAL) while still available,
## a dim hollow ring once spent -- so the count visibly shrinks as the
## player steals, instead of only being conveyed by a number.
func _draw_steal_icons() -> void:
	var r := STEAL_ICON_RADIUS
	var cy := r + 2.0
	for i in _steals_total:
		var cx := r + i * STEAL_ICON_SPACING
		if i < _steals_remaining:
			_steals_icons.draw_circle(Vector2(cx, cy), r, GameTheme.COLOR_STEAL)
		else:
			_steals_icons.draw_arc(Vector2(cx, cy), r, 0.0, TAU, 16, GameTheme.COLOR_TEXT_DISABLED, 1.5, true)

## recipe_rows: Array[{recipe_index:int, cards:Array[{label,category_key,card_instance_id,stealable}]}]
## Pass an empty array for the active player's own panel (their board is
## shown in full on the table instead).
func update(seat_index: int, hand_count: int, recipes_completed: int, recipes_total: int, steals_remaining: int, steals_total: int, is_active: bool, recipe_rows: Array) -> void:
	_seat_index = seat_index
	theme_type_variation = "PlayerPanelActive" if is_active else "PlayerPanel"
	_avatar.set_meta("seat", seat_index)
	_avatar.set_meta("initial", str(seat_index + 1))
	_avatar.queue_redraw()

	_name_label.text = "Player %d" % (seat_index + 1)
	_hand_label.text = "Hand: %d" % hand_count
	_recipes_label.text = "Recipes: %d/%d" % [recipes_completed, recipes_total]

	_steals_remaining = steals_remaining
	_steals_total = steals_total
	var icons_width: float = max(steals_total, 1) * STEAL_ICON_SPACING
	_steals_icons.custom_minimum_size = Vector2(icons_width, STEAL_ICON_RADIUS * 2.0 + 4.0)
	_steals_icons.queue_redraw()
	_steals_label.text = " %d/%d steals left" % [steals_remaining, steals_total]

	# queue_free(), not free(): a stealable chip's own "pressed" click can
	# trigger the re-render that calls update() again, and free()-ing a
	# node still processing its own signal raises "Attempted to free a
	# locked object".
	for c in _chips_col.get_children():
		_chips_col.remove_child(c)
		c.queue_free()

	for row in recipe_rows:
		var row_box := HBoxContainer.new()
		row_box.theme_type_variation = "TightHBox"
		_chips_col.add_child(row_box)
		var cards: Array = row["cards"]
		if cards.is_empty():
			var none_label := Label.new()
			none_label.theme_type_variation = "MiniChipLabel"
			none_label.text = "(no cards attached)"
			row_box.add_child(none_label)
			continue
		for card_data in cards:
			_build_mini_card(row_box, row["recipe_index"], card_data)

## CardFace's @onready fields only resolve once it's actually in the tree,
## so it must be add_child()-ed before setup() is called -- build directly
## into the destination parent rather than returning a detached node.
func _build_mini_card(parent: Node, recipe_index: int, card_data: Dictionary) -> void:
	var face: CardFace = CARD_SCENE.instantiate()
	var stealable: bool = card_data["stealable"]

	if stealable:
		var frame := PanelContainer.new()
		frame.theme_type_variation = "StealTargetHighlight"
		parent.add_child(frame)
		frame.add_child(face)
	else:
		parent.add_child(face)

	face.custom_minimum_size = MINI_CARD_SIZE
	face.size = MINI_CARD_SIZE
	face.setup(card_data["label"], card_data["category_key"], card_data["card_instance_id"])
	face.disabled = not stealable
	if stealable:
		face.pressed.connect(_on_mini_card_pressed.bind(recipe_index, card_data["card_instance_id"]))

func _on_mini_card_pressed(recipe_index: int, card_instance_id: int) -> void:
	steal_requested.emit(_seat_index, recipe_index, card_instance_id)

extends Control
class_name HandFan
## The active player's hand: cards arranged in an arc, overlap and spread
## computed from the control's own (anchored) size so it stays readable at
## any aspect ratio and any hand size. Hover raises a card; click selects
## it. Selection state and which cards are currently actionable are both
## supplied by the caller -- this node has no idea what a legal action is.

signal card_clicked(instance_id: int)

const CARD_SCENE := preload("res://ui/components/CardFace.tscn")

var _cards_data: Array = []
var _db: CardDatabase
var _selectable_ids: Dictionary = {}
var _selected_id: int = -1
var _card_nodes: Dictionary = {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_layout)

func set_cards(cards: Array, db: CardDatabase, selectable_ids: Dictionary, selected_id: int) -> void:
	_cards_data = cards
	_db = db
	_selectable_ids = selectable_ids
	_selected_id = selected_id

	# queue_free(), not free(): set_cards() runs during a re-render that a
	# card's own "pressed" click can trigger, and free()-ing a node still
	# processing its own signal raises "Attempted to free a locked object".
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_card_nodes.clear()

	for card in cards:
		var face: CardFace = CARD_SCENE.instantiate()
		add_child(face)
		var label := GameViewModel.card_label(card.def_id, card.category, db)
		var cat := CardCategoryMap.category_for(card.def_id, card.category)
		face.setup(label, cat, card.instance_id, card.def_id)
		face.disabled = not selectable_ids.has(card.instance_id)
		face.mouse_entered.connect(_on_card_hover.bind(card.instance_id, true))
		face.mouse_exited.connect(_on_card_hover.bind(card.instance_id, false))
		face.pressed.connect(_on_card_pressed.bind(card.instance_id))
		_card_nodes[card.instance_id] = face

	_layout()

func _layout() -> void:
	var n := _cards_data.size()
	if n == 0 or size.x <= 0.0 or size.y <= 0.0:
		return

	var card_h: float = clamp(size.y * 0.82, 90.0, 190.0)
	var card_w := card_h * 0.68
	var max_spread_deg: float = clamp(4.0 * n, 8.0, 28.0)

	var overlap_step: float
	if n > 1:
		overlap_step = min(card_w * 0.85, (size.x - card_w) / float(n - 1))
		overlap_step = max(overlap_step, card_w * 0.26)
	else:
		overlap_step = 0.0

	var total_width: float = card_w + overlap_step * float(max(n - 1, 0))
	var start_x: float = (size.x - total_width) * 0.5

	for i in n:
		var card = _cards_data[i]
		var face: CardFace = _card_nodes[card.instance_id]
		face.size = Vector2(card_w, card_h)
		face.pivot_offset = Vector2(card_w * 0.5, card_h)

		var t := 0.0 if n == 1 else (float(i) / float(n - 1)) * 2.0 - 1.0
		var angle_deg := t * (max_spread_deg * 0.5)
		var arc_lift := (1.0 - t * t) * size.y * 0.09
		var base_y := size.y - card_h - 4.0 - arc_lift
		var base_x := start_x + i * overlap_step

		face.position = Vector2(base_x, base_y)
		face.rotation_degrees = angle_deg
		face.z_index = i
		face.set_meta("base_position", face.position)

		if card.instance_id == _selected_id:
			face.position.y = base_y - 30.0
			face.z_index = 100

func _on_card_hover(instance_id: int, entered: bool) -> void:
	if instance_id == _selected_id:
		return
	var face: CardFace = _card_nodes.get(instance_id)
	if face == null:
		return
	var base_pos: Vector2 = face.get_meta("base_position", face.position)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if entered:
		face.move_to_front()
		tween.tween_property(face, "position:y", base_pos.y - 20.0, 0.12)
	else:
		tween.tween_property(face, "position:y", base_pos.y, 0.12)

func _on_card_pressed(instance_id: int) -> void:
	card_clicked.emit(instance_id)

func get_card_global_position(instance_id: int) -> Vector2:
	var face: CardFace = _card_nodes.get(instance_id)
	if face == null:
		return global_position + size * 0.5
	return face.global_position + face.size * 0.5

func get_fan_center_global_position() -> Vector2:
	return global_position + Vector2(size.x * 0.5, size.y * 0.25)

class_name CardAnimator
extends RefCounted
## Spawns a short-lived "ghost" CardFace that flies between two screen
## points and frees itself. Purely decorative: it never blocks input or
## gates state changes, so correctness never depends on an animation
## finishing. Each action style has a deliberately distinct motion so the
## five action types read as physically different gestures.

const CARD_SCENE := preload("res://ui/components/CardFace.tscn")
const GHOST_SIZE := Vector2(92, 124)

## style: "deal", "draw", "attach", "discard", or "steal".
static func fly(layer: Control, from_global: Vector2, to_global: Vector2, display_name: String, category_key: String, style: String) -> void:
	var ghost: CardFace = CARD_SCENE.instantiate()
	layer.add_child(ghost)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.disabled = true
	ghost.size = GHOST_SIZE
	ghost.pivot_offset = GHOST_SIZE * 0.5

	if category_key == "back":
		ghost.set_face_down()
	else:
		ghost.setup(display_name, category_key)

	ghost.global_position = from_global - GHOST_SIZE * 0.5

	var tween := layer.create_tween()
	match style:
		"steal":
			_animate_steal(tween, ghost, to_global)
		"discard":
			_animate_discard(tween, ghost, to_global)
		"attach":
			_animate_attach(tween, ghost, to_global)
		_:
			_animate_draw(tween, ghost, to_global)

	tween.finished.connect(ghost.queue_free)

static func _target_top_left(to_global: Vector2) -> Vector2:
	return to_global - GHOST_SIZE * 0.5

## Deal / draw: a calm, slightly floaty arrival -- the default, unremarkable motion.
static func _animate_draw(tween: Tween, ghost: Control, to_global: Vector2) -> void:
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "global_position", _target_top_left(to_global), 0.35)
	tween.parallel().tween_property(ghost, "scale", Vector2(1.05, 1.05), 0.35)
	tween.tween_property(ghost, "scale", Vector2(1.0, 1.0), 0.08)

## Attach: a deliberate placement that "settles" into the slot with a small
## confirming pulse, unlike the passive draw.
static func _animate_attach(tween: Tween, ghost: Control, to_global: Vector2) -> void:
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "global_position", _target_top_left(to_global), 0.3)
	tween.tween_property(ghost, "scale", Vector2(1.2, 1.2), 0.08)
	tween.tween_property(ghost, "scale", Vector2(1.0, 1.0), 0.12)

## Discard: a dismissive toss -- rotates away and fades as it lands, unlike
## every other motion which arrives fully opaque.
static func _animate_discard(tween: Tween, ghost: Control, to_global: Vector2) -> void:
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(ghost, "global_position", _target_top_left(to_global), 0.3)
	tween.parallel().tween_property(ghost, "rotation_degrees", 26.0, 0.3)
	tween.parallel().tween_property(ghost, "modulate:a", 0.0, 0.22).set_delay(0.1)

## Steal: unmistakably the most aggressive motion -- a red anticipation
## flash, then a fast overshooting snatch across the table with a tilt,
## unlike the slower/calmer motions used everywhere else.
static func _animate_steal(tween: Tween, ghost: Control, to_global: Vector2) -> void:
	ghost.modulate = GameTheme.COLOR_STEAL
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "scale", Vector2(1.3, 1.3), 0.06)
	tween.tween_property(ghost, "global_position", _target_top_left(to_global), 0.24)
	tween.parallel().tween_property(ghost, "modulate", Color(1, 1, 1, 1), 0.24)
	tween.parallel().tween_property(ghost, "scale", Vector2(1.0, 1.0), 0.24)
	tween.parallel().tween_property(ghost, "rotation_degrees", -14.0, 0.1)
	tween.tween_property(ghost, "rotation_degrees", 0.0, 0.1)

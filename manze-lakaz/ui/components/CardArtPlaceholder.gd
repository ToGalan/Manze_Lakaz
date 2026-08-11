extends Control
class_name CardArtPlaceholder
## This project has no real card art yet, so every card's art slot draws
## a simple placeholder instead of sitting blank: a generic "photo" glyph
## (frame + sun + mountains -- the universal missing-image icon) tinted
## by category for a card front, or a repeating diamond lattice for a
## card back, matching how a real deck has one shared back design.
## Callers set category_key/is_back and this draws itself; swapping in
## real textures later only means changing this one file.

var category_key: String = ""
var is_back: bool = false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if is_back:
		_draw_back_pattern()
	else:
		_draw_photo_icon(tint_for_category(category_key))

static func tint_for_category(key: String) -> Color:
	match key:
		CardCategoryMap.PROTEIN:
			return GameTheme.COLOR_PROTEIN
		CardCategoryMap.VEGETABLE:
			return GameTheme.COLOR_VEGETABLE
		CardCategoryMap.PANTRY:
			return GameTheme.COLOR_PANTRY
		CardCategoryMap.PREPARATION:
			return GameTheme.COLOR_PREPARATION
	return GameTheme.COLOR_ACCENT

func _draw_photo_icon(tint: Color) -> void:
	var w := size.x
	var h := size.y
	var line_c := Color(tint, 0.55)
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color(tint, 0.10), true)
	draw_rect(Rect2(1, 1, w - 2, h - 2), line_c, false, 2.0)
	draw_circle(Vector2(w * 0.28, h * 0.32), min(w, h) * 0.09, line_c)
	var back_ridge := PackedVector2Array([
		Vector2(w * 0.10, h * 0.80), Vector2(w * 0.40, h * 0.42), Vector2(w * 0.68, h * 0.80),
	])
	draw_colored_polygon(back_ridge, Color(tint, 0.28))
	var front_ridge := PackedVector2Array([
		Vector2(w * 0.38, h * 0.80), Vector2(w * 0.66, h * 0.50), Vector2(w * 0.94, h * 0.80),
	])
	draw_colored_polygon(front_ridge, line_c)

func _draw_back_pattern() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), GameTheme.COLOR_CARD_BACK, true)
	var stripe_c := Color(GameTheme.COLOR_ACCENT_DIM, 0.35)
	var step: float = max(w, h) * 0.16
	var x := -h
	while x < w:
		draw_line(Vector2(x, h), Vector2(x + h, 0), stripe_c, 2.0)
		x += step
	var cx := w * 0.5
	var cy := h * 0.5
	var r: float = min(w, h) * 0.14
	var diamond := PackedVector2Array([
		Vector2(cx, cy - r), Vector2(cx + r, cy), Vector2(cx, cy + r), Vector2(cx - r, cy),
	])
	draw_colored_polygon(diamond, Color(GameTheme.COLOR_ACCENT, 0.55))

extends Control
class_name MenuBackground
## Full-screen backdrop for menu-style screens (main menu, story, setup),
## each with its own art. No real background art exists yet for any of
## them -- once it does, pass its res:// path to the constructor (same
## res:// pattern as CardArtMap); everything below the "if _texture" check
## in _draw() stops running automatically and this becomes a plain
## full-bleed image. Until then, a themed gradient plus a small corner
## label make it obvious this is a placeholder, not a rendering bug.

var _texture: Texture2D

func _init(image_path: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if image_path != "":
		_texture = load(image_path)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
		return

	var top := GameTheme.COLOR_FELT_EDGE.darkened(0.5)
	var bottom := GameTheme.COLOR_ACCENT_DIM.darkened(0.55)
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y),
	])
	var colors := PackedColorArray([top, top, bottom, bottom])
	draw_polygon(points, colors)

	var label_text := "Background art placeholder, final art coming later"
	var font := ThemeDB.fallback_font
	var font_size := 13
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var margin := 14.0
	draw_string(font, Vector2(size.x - text_size.x - margin, size.y - margin), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.25))

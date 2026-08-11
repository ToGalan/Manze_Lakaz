extends Button
class_name RecipeCardFace
## A recipe card's visual: a placeholder art slot (see CardArtPlaceholder)
## plus dish name and country/tier, with a proper face-down back like
## every ingredient/preparation card -- the whole deck shares one back
## design. The card itself is the button (same pattern as every other
## clickable card in this game); disable it wherever it's display-only
## (the recipe reveal, the game-over screen).

const ART_HEIGHT := 90.0

var art: CardArtPlaceholder
var title_label: Label
var subtitle_label: Label
var recipe_id: String = ""

func _init() -> void:
	custom_minimum_size = Vector2(170, 220)
	focus_mode = Control.FOCUS_NONE
	text = ""
	theme_type_variation = "RecipeCardFront"

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	add_child(margin)

	var content := VBoxContainer.new()
	content.theme_type_variation = "TightVBox"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)

	art = CardArtPlaceholder.new()
	art.custom_minimum_size = Vector2(0, ART_HEIGHT)
	content.add_child(art)

	title_label = Label.new()
	title_label.theme_type_variation = "RecipeTitleLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.theme_type_variation = "HintLabel"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle_label)

func setup(display_name: String, country: String, tier_name: String, p_recipe_id: String = "") -> void:
	recipe_id = p_recipe_id
	theme_type_variation = "RecipeCardFront"
	art.category_key = "recipe"
	art.is_back = false
	art.queue_redraw()
	title_label.text = display_name
	title_label.visible = true
	subtitle_label.text = "%s -- %s" % [country, tier_name.capitalize()] if country != "" else tier_name.capitalize()
	subtitle_label.visible = true

func set_face_down() -> void:
	recipe_id = ""
	theme_type_variation = "CardFaceBack"
	art.is_back = true
	art.queue_redraw()
	title_label.visible = false
	subtitle_label.visible = false

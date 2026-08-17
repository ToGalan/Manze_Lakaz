extends Button
class_name CardFace
## A single card's visual: a themed Button (so hover/press/disabled all come
## free from the central Theme) showing either a shipped card image
## (CardArtMap -- art and name baked in by the artist) or, for the handful
## of def_ids with no shipped art yet, a procedural placeholder art slot
## (CardArtPlaceholder) plus a name label. Purely presentational -- callers
## decide what card this represents and whether it's currently clickable;
## CardFace never touches GameState or Action.

@onready var art_slot: CardArtPlaceholder = %ArtSlot
@onready var name_label: Label = %NameLabel
@onready var margin: MarginContainer = $Margin
@onready var art_image: TextureRect = %ArtImage

var card_instance_id: int = -1
var def_id: String = ""
var category_key: String = ""

func setup(display_name: String, p_category_key: String, p_card_instance_id: int = -1, p_def_id: String = "") -> void:
	category_key = p_category_key
	card_instance_id = p_card_instance_id
	def_id = p_def_id

	var art_path := CardArtMap.path_for(p_def_id)
	if art_path != "":
		_show_shipped_art(art_path)
	else:
		name_label.text = display_name
		name_label.visible = true
		art_slot.category_key = p_category_key
		art_slot.is_back = false
		art_slot.queue_redraw()
		_show_placeholder()
		theme_type_variation = CardCategoryMap.theme_variation_for(p_category_key)

func set_face_down() -> void:
	category_key = "back"
	card_instance_id = -1
	def_id = ""

	if CardArtMap.BACK_PATH != "":
		_show_shipped_art(CardArtMap.BACK_PATH)
	else:
		name_label.visible = false
		art_slot.is_back = true
		art_slot.queue_redraw()
		_show_placeholder()
		theme_type_variation = "CardFaceBack"

func _show_shipped_art(path: String) -> void:
	art_image.texture = load(path)
	art_image.visible = true
	margin.visible = false
	theme_type_variation = "CardFaceArt"

func _show_placeholder() -> void:
	art_image.visible = false
	margin.visible = true

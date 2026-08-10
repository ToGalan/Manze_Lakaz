extends Button
class_name CardFace
## A single card's visual: a themed Button (so hover/press/disabled all come
## free from the central Theme) with an art slot for future real card art
## and a name label. Purely presentational -- callers decide what card this
## represents and whether it's currently clickable; CardFace never touches
## GameState or Action.

@onready var art_slot: TextureRect = %ArtSlot
@onready var name_label: Label = %NameLabel

var card_instance_id: int = -1
var def_id: String = ""
var category_key: String = ""

func setup(display_name: String, p_category_key: String, p_card_instance_id: int = -1, p_def_id: String = "", art: Texture2D = null) -> void:
	name_label.text = display_name
	name_label.visible = true
	category_key = p_category_key
	card_instance_id = p_card_instance_id
	def_id = p_def_id
	art_slot.texture = art
	theme_type_variation = CardCategoryMap.theme_variation_for(p_category_key)

func set_face_down() -> void:
	name_label.visible = false
	art_slot.texture = null
	category_key = "back"
	card_instance_id = -1
	def_id = ""
	theme_type_variation = "CardFaceBack"

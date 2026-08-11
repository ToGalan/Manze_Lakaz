extends Button
class_name CardFace
## A single card's visual: a themed Button (so hover/press/disabled all come
## free from the central Theme) with a placeholder art slot (see
## CardArtPlaceholder -- no real card art exists yet) and a name label.
## Purely presentational -- callers decide what card this represents and
## whether it's currently clickable; CardFace never touches GameState or
## Action.

@onready var art_slot: CardArtPlaceholder = %ArtSlot
@onready var name_label: Label = %NameLabel

var card_instance_id: int = -1
var def_id: String = ""
var category_key: String = ""

func setup(display_name: String, p_category_key: String, p_card_instance_id: int = -1, p_def_id: String = "") -> void:
	name_label.text = display_name
	name_label.visible = true
	category_key = p_category_key
	card_instance_id = p_card_instance_id
	def_id = p_def_id
	art_slot.category_key = p_category_key
	art_slot.is_back = false
	art_slot.queue_redraw()
	theme_type_variation = CardCategoryMap.theme_variation_for(p_category_key)

func set_face_down() -> void:
	name_label.visible = false
	category_key = "back"
	card_instance_id = -1
	def_id = ""
	art_slot.is_back = true
	art_slot.queue_redraw()
	theme_type_variation = "CardFaceBack"

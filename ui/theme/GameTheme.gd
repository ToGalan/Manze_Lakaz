class_name GameTheme
extends RefCounted
## The one central Theme resource for the whole UI. Every visual style in
## the app is a named theme_type_variation defined here; nothing outside
## this file should call add_theme_*_override(). To restyle the app,
## change colors/values here -- nothing else needs to touch styling.

# --- Palette ---------------------------------------------------------------

const COLOR_APP_BG := Color8(17, 22, 28)
const COLOR_FELT := Color8(244, 244, 240)
const COLOR_FELT_DARK := Color8(222, 222, 217)
const COLOR_FELT_EDGE := Color8(188, 188, 182)

const COLOR_PANEL := Color8(31, 39, 50)
const COLOR_PANEL_LIGHT := Color8(42, 52, 65)
const COLOR_PANEL_BORDER := Color8(55, 67, 82)

const COLOR_ACCENT := Color8(240, 187, 66)
const COLOR_ACCENT_DIM := Color8(163, 128, 51)

const COLOR_TEXT := Color8(235, 238, 240)
const COLOR_TEXT_MUTED := Color8(148, 160, 173)
const COLOR_TEXT_DISABLED := Color8(95, 104, 115)
## COLOR_TEXT_MUTED is tuned for dark panels; the deck/discard pile labels
## sit directly on the light board background (COLOR_FELT) and need a dark
## muted tone instead -- see "PileSectionLabel"/"PileBadgeLabel".
const COLOR_TEXT_MUTED_ON_LIGHT := Color8(96, 100, 104)

const COLOR_PROTEIN := Color8(196, 87, 74)
const COLOR_VEGETABLE := Color8(96, 158, 100)
const COLOR_PANTRY := Color8(199, 162, 74)
const COLOR_PREPARATION := Color8(110, 124, 206)
const COLOR_CARD_BACK := Color8(52, 61, 75)

const COLOR_STEAL := Color8(214, 69, 55)
const COLOR_STEAL_DIM := Color8(140, 46, 38)
const COLOR_ATTACH_HIGHLIGHT := Color8(102, 204, 148)
const COLOR_DECOY_HIGHLIGHT := Color8(204, 168, 84)

static var _cached: Theme = null

static func get_theme() -> Theme:
	if _cached == null:
		_cached = _build()
	return _cached

# ===========================================================================

static func _build() -> Theme:
	var t := Theme.new()

	t.default_font_size = 16
	t.set_color("font_color", "Label", COLOR_TEXT)

	_setup_labels(t)
	_setup_buttons(t)
	_setup_panels(t)
	_setup_containers(t)
	return t

static func _setup_containers(t: Theme) -> void:
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 8)

	t.set_type_variation("TightHBox", "HBoxContainer")
	t.set_constant("separation", "TightHBox", 0)

	t.set_type_variation("TightVBox", "VBoxContainer")
	t.set_constant("separation", "TightVBox", 2)

	t.set_type_variation("WideHBox", "HBoxContainer")
	t.set_constant("separation", "WideHBox", 18)

	t.set_type_variation("WideVBox", "VBoxContainer")
	t.set_constant("separation", "WideVBox", 16)

	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		t.set_constant(side, "MarginContainer", 12)

	t.set_type_variation("WideMargin", "MarginContainer")
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		t.set_constant(side, "WideMargin", 28)

static func _box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 10, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb

## Like _box(), but with a separate top/bottom margin -- used to shrink a
## button's height without narrowing its horizontal padding.
static func _box_v(bg: Color, border: Color, border_w: int, radius: int, horizontal_margin: int, vertical_margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.set_content_margin(SIDE_LEFT, horizontal_margin)
	sb.set_content_margin(SIDE_RIGHT, horizontal_margin)
	sb.set_content_margin(SIDE_TOP, vertical_margin)
	sb.set_content_margin(SIDE_BOTTOM, vertical_margin)
	return sb

static func _empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

# --- Labels ------------------------------------------------------------

static func _setup_labels(t: Theme) -> void:
	_label_variation(t, "TitleLabel", 30, COLOR_TEXT)
	_label_variation(t, "PromptLabel", 18, COLOR_TEXT)
	_label_variation(t, "HintLabel", 14, COLOR_TEXT_MUTED)
	_label_variation(t, "SectionLabel", 13, COLOR_TEXT_MUTED)
	_label_variation(t, "PlayerNameLabel", 16, COLOR_TEXT)
	_label_variation(t, "BadgeLabel", 13, COLOR_TEXT_MUTED)
	_label_variation(t, "PileSectionLabel", 13, COLOR_TEXT_MUTED_ON_LIGHT)
	_label_variation(t, "PileBadgeLabel", 13, COLOR_TEXT_MUTED_ON_LIGHT)
	_label_variation(t, "LogEntryLabel", 13, COLOR_TEXT_MUTED)
	_label_variation(t, "RecipeTitleLabel", 15, COLOR_TEXT)
	_label_variation(t, "RecipeSlotFilledLabel", 14, COLOR_ATTACH_HIGHLIGHT)
	_label_variation(t, "RecipeSlotEmptyLabel", 14, COLOR_TEXT_MUTED)
	_label_variation(t, "MiniChipLabel", 11, COLOR_TEXT)

static func _label_variation(t: Theme, name: String, size: int, color: Color) -> void:
	t.set_type_variation(name, "Label")
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)

# --- Buttons -------------------------------------------------------------

static func _setup_buttons(t: Theme) -> void:
	_button_variation(t, "PrimaryButton", COLOR_ACCENT, Color8(30, 24, 10), COLOR_ACCENT_DIM, 18)
	_button_variation(t, "SecondaryButton", COLOR_PANEL_LIGHT, COLOR_TEXT, COLOR_PANEL_BORDER, 15)
	_button_variation(t, "PrimaryButtonCompact", COLOR_ACCENT, Color8(30, 24, 10), COLOR_ACCENT_DIM, 18, 4)
	## The opponent-recipe-row Prev/Next pagination controls (PlayerPanel) --
	## small enough not to compete with the mini card row they sit under.
	_button_variation(t, "PageNavButton", COLOR_PANEL_LIGHT, COLOR_TEXT, COLOR_PANEL_BORDER, 11, 2)

	_card_face_variation(t, "CardFaceProtein", COLOR_PROTEIN)
	_card_face_variation(t, "CardFaceVegetable", COLOR_VEGETABLE)
	_card_face_variation(t, "CardFacePantry", COLOR_PANTRY)
	_card_face_variation(t, "CardFacePreparation", COLOR_PREPARATION)
	_card_face_variation(t, "CardFaceBack", COLOR_CARD_BACK)

	_button_variation(t, "RecipeCardFront", COLOR_PANEL.lightened(0.03), COLOR_TEXT, COLOR_ACCENT_DIM, 15)

	_slot_button_variation(t, "RecipeSlotFilledButton", COLOR_ATTACH_HIGHLIGHT, false)
	_slot_button_variation(t, "RecipeSlotFilledButtonSelected", COLOR_ATTACH_HIGHLIGHT, true)

	# A shipped card-art image (CardArtMap) already bakes in its own rounded
	# card shape with alpha-transparent corners and its own background
	# color, painted by the artist -- a themed category-color stylebox
	# behind it would just bleed through those corners as a mismatched
	# colored ring. Fully transparent so the artwork reads as the whole card
	# with nothing showing behind it.
	var transparent := StyleBoxEmpty.new()
	t.set_type_variation("CardFaceArt", "Button")
	t.set_stylebox("normal", "CardFaceArt", transparent)
	t.set_stylebox("hover", "CardFaceArt", transparent)
	t.set_stylebox("pressed", "CardFaceArt", transparent)
	t.set_stylebox("disabled", "CardFaceArt", transparent)
	t.set_stylebox("focus", "CardFaceArt", transparent)

static func _button_variation(t: Theme, name: String, bg: Color, fg: Color, border: Color, font_size: int, vertical_margin: int = 12) -> void:
	t.set_type_variation(name, "Button")
	t.set_stylebox("normal", name, _box_v(bg, border, 2, 10, 12, vertical_margin))
	t.set_stylebox("hover", name, _box_v(bg.lightened(0.12), border, 2, 10, 12, vertical_margin))
	t.set_stylebox("pressed", name, _box_v(bg.darkened(0.15), border, 2, 10, 12, vertical_margin))
	t.set_stylebox("disabled", name, _box_v(COLOR_PANEL, COLOR_PANEL_BORDER, 1, 10, 12, vertical_margin))
	t.set_stylebox("focus", name, _box_v(bg, Color.WHITE, 2, 10, 12, vertical_margin))
	t.set_color("font_color", name, fg)
	t.set_color("font_hover_color", name, fg)
	t.set_color("font_pressed_color", name, fg)
	t.set_color("font_disabled_color", name, COLOR_TEXT_DISABLED)
	t.set_font_size("font_size", name, font_size)

## An attached, filled preparation slot row rendered as a Button instead of a
## Label so it can be clicked to pick it up for MOVE_PREPARATION -- same
## RecipeSlotFilledLabel color at rest, with a tinted fill + border once
## picked up so the player can see which one they've selected.
static func _slot_button_variation(t: Theme, name: String, color: Color, selected: bool) -> void:
	t.set_type_variation(name, "Button")
	var rest_bg := Color(color, 0.16) if selected else Color(0, 0, 0, 0)
	var rest_border := color if selected else Color(0, 0, 0, 0)
	var rest_border_w := 2 if selected else 0
	t.set_stylebox("normal", name, _box_v(rest_bg, rest_border, rest_border_w, 6, 4, 2))
	t.set_stylebox("hover", name, _box_v(Color(color, 0.22), color, 2, 6, 4, 2))
	t.set_stylebox("pressed", name, _box_v(Color(color, 0.30), color, 2, 6, 4, 2))
	t.set_stylebox("disabled", name, _box_v(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 4, 2))
	t.set_stylebox("focus", name, _box_v(rest_bg, color, 2, 6, 4, 2))
	t.set_color("font_color", name, color)
	t.set_color("font_hover_color", name, color)
	t.set_color("font_pressed_color", name, color)
	t.set_color("font_disabled_color", name, COLOR_TEXT_DISABLED)
	t.set_font_size("font_size", name, 14)

static func _card_face_variation(t: Theme, name: String, category_color: Color) -> void:
	t.set_type_variation(name, "Button")
	t.set_stylebox("normal", name, _box(category_color.darkened(0.15), category_color.darkened(0.4), 2, 12, 8))
	t.set_stylebox("hover", name, _box(category_color, Color.WHITE, 2, 12, 8))
	t.set_stylebox("pressed", name, _box(category_color.darkened(0.25), Color.WHITE, 3, 12, 8))
	t.set_stylebox("disabled", name, _box(category_color.darkened(0.4), category_color.darkened(0.55), 1, 12, 8))
	t.set_stylebox("focus", name, _box(category_color, Color.WHITE, 2, 12, 8))
	t.set_color("font_color", name, COLOR_TEXT)
	t.set_color("font_hover_color", name, COLOR_TEXT)
	t.set_color("font_pressed_color", name, COLOR_TEXT)
	t.set_color("font_disabled_color", name, Color(1, 1, 1, 0.55))
	t.set_font_size("font_size", name, 14)

# --- Panels ----------------------------------------------------------------

static func _setup_panels(t: Theme) -> void:
	t.set_type_variation("PlayerPanel", "PanelContainer")
	t.set_stylebox("panel", "PlayerPanel", _box(COLOR_PANEL, COLOR_PANEL_BORDER, 2, 12, 10))

	t.set_type_variation("PlayerPanelActive", "PanelContainer")
	t.set_stylebox("panel", "PlayerPanelActive", _box(COLOR_PANEL_LIGHT, COLOR_ACCENT, 3, 12, 10))

	t.set_type_variation("RecipePanel", "PanelContainer")
	t.set_stylebox("panel", "RecipePanel", _box(COLOR_PANEL.lightened(0.03), COLOR_PANEL_BORDER, 2, 10, 10))

	t.set_type_variation("RecipePanelComplete", "PanelContainer")
	t.set_stylebox("panel", "RecipePanelComplete", _box(COLOR_PANEL.lightened(0.03), COLOR_ATTACH_HIGHLIGHT, 3, 10, 10))

	t.set_type_variation("LogPanel", "PanelContainer")
	t.set_stylebox("panel", "LogPanel", _box(COLOR_PANEL, COLOR_PANEL_BORDER, 2, 10, 10))

	t.set_type_variation("PromptBarPanel", "PanelContainer")
	t.set_stylebox("panel", "PromptBarPanel", _box(COLOR_PANEL_LIGHT, COLOR_ACCENT_DIM, 2, 14, 10))

	t.set_type_variation("OverlayBackdrop", "PanelContainer")
	t.set_stylebox("panel", "OverlayBackdrop", _box(Color(0.04, 0.05, 0.07, 0.88), Color(0, 0, 0, 0), 0, 0, 0))

	# Same overlay slot, but fully transparent -- for the main menu, whose
	# own MenuBackground (a full-rect sibling drawn first) needs to actually
	# show through instead of being nearly hidden under OverlayBackdrop's
	# 88%-opaque fill.
	t.set_type_variation("ClearOverlay", "PanelContainer")
	t.set_stylebox("panel", "ClearOverlay", StyleBoxEmpty.new())

	t.set_type_variation("OverlayCard", "PanelContainer")
	t.set_stylebox("panel", "OverlayCard", _box(COLOR_PANEL, COLOR_PANEL_BORDER, 2, 16, 24))

	# Recipe panels sit directly on the light board (COLOR_FELT), unlike
	# StealTargetHighlight below (always inside an opponent's still-dark
	# PlayerPanel) -- a translucent wash here would blend toward the light
	# board instead of staying legible under RecipeTitleLabel/
	# RecipeSlotFilledLabel's light text, so this blends the highlight tint
	# into the normal dark recipe-panel color instead of relying on
	# whatever's behind it.
	t.set_type_variation("LegalTargetHighlight", "PanelContainer")
	t.set_stylebox("panel", "LegalTargetHighlight", _box(COLOR_PANEL.lightened(0.03).blend(Color(COLOR_ATTACH_HIGHLIGHT, 0.35)), COLOR_ATTACH_HIGHLIGHT, 3, 14, 4))

	t.set_type_variation("DecoyTargetHighlight", "PanelContainer")
	t.set_stylebox("panel", "DecoyTargetHighlight", _box(COLOR_PANEL.lightened(0.03).blend(Color(COLOR_DECOY_HIGHLIGHT, 0.35)), COLOR_DECOY_HIGHLIGHT, 3, 14, 4))

	t.set_type_variation("StealTargetHighlight", "PanelContainer")
	t.set_stylebox("panel", "StealTargetHighlight", _box(Color(COLOR_STEAL, 0.22), COLOR_STEAL, 3, 12, 4))

	t.set_type_variation("PilePanel", "PanelContainer")
	t.set_stylebox("panel", "PilePanel", _box(COLOR_FELT_DARK, COLOR_PANEL_BORDER, 2, 8, 8))

	t.set_type_variation("ChipPanel", "PanelContainer")
	t.set_stylebox("panel", "ChipPanel", _box(COLOR_PANEL_LIGHT, Color(0, 0, 0, 0), 0, 6, 4))

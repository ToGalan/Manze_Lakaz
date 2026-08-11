class_name GameTheme
extends RefCounted
## The one central Theme resource for the whole UI. Every visual style in
## the app is a named theme_type_variation defined here; nothing outside
## this file should call add_theme_*_override(). To restyle the app,
## change colors/values here -- nothing else needs to touch styling.

# --- Palette ---------------------------------------------------------------

const COLOR_APP_BG := Color8(17, 22, 28)
const COLOR_FELT := Color8(23, 87, 61)
const COLOR_FELT_DARK := Color8(14, 58, 40)
const COLOR_FELT_EDGE := Color8(10, 41, 29)

const COLOR_PANEL := Color8(31, 39, 50)
const COLOR_PANEL_LIGHT := Color8(42, 52, 65)
const COLOR_PANEL_BORDER := Color8(55, 67, 82)

const COLOR_ACCENT := Color8(240, 187, 66)
const COLOR_ACCENT_DIM := Color8(163, 128, 51)

const COLOR_TEXT := Color8(235, 238, 240)
const COLOR_TEXT_MUTED := Color8(148, 160, 173)
const COLOR_TEXT_DISABLED := Color8(95, 104, 115)

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

static func _empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

# --- Labels ------------------------------------------------------------

static func _setup_labels(t: Theme) -> void:
	_label_variation(t, "TitleLabel", 30, COLOR_TEXT)
	_label_variation(t, "PromptLabel", 22, COLOR_TEXT)
	_label_variation(t, "HintLabel", 14, COLOR_TEXT_MUTED)
	_label_variation(t, "SectionLabel", 13, COLOR_TEXT_MUTED)
	_label_variation(t, "PlayerNameLabel", 16, COLOR_TEXT)
	_label_variation(t, "BadgeLabel", 13, COLOR_TEXT_MUTED)
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

	_card_face_variation(t, "CardFaceProtein", COLOR_PROTEIN)
	_card_face_variation(t, "CardFaceVegetable", COLOR_VEGETABLE)
	_card_face_variation(t, "CardFacePantry", COLOR_PANTRY)
	_card_face_variation(t, "CardFacePreparation", COLOR_PREPARATION)
	_card_face_variation(t, "CardFaceBack", COLOR_CARD_BACK)

	_button_variation(t, "RecipeCardFront", COLOR_PANEL.lightened(0.03), COLOR_TEXT, COLOR_ACCENT_DIM, 15)

	t.set_type_variation("InvisibleFillButton", "Button")
	var transparent := StyleBoxEmpty.new()
	t.set_stylebox("normal", "InvisibleFillButton", transparent)
	t.set_stylebox("hover", "InvisibleFillButton", transparent)
	t.set_stylebox("pressed", "InvisibleFillButton", transparent)
	t.set_stylebox("disabled", "InvisibleFillButton", transparent)
	t.set_stylebox("focus", "InvisibleFillButton", transparent)
	t.set_color("font_color", "InvisibleFillButton", COLOR_TEXT)
	t.set_font_size("font_size", "InvisibleFillButton", 15)

static func _button_variation(t: Theme, name: String, bg: Color, fg: Color, border: Color, font_size: int) -> void:
	t.set_type_variation(name, "Button")
	t.set_stylebox("normal", name, _box(bg, border, 2, 10, 12))
	t.set_stylebox("hover", name, _box(bg.lightened(0.12), border, 2, 10, 12))
	t.set_stylebox("pressed", name, _box(bg.darkened(0.15), border, 2, 10, 12))
	t.set_stylebox("disabled", name, _box(COLOR_PANEL, COLOR_PANEL_BORDER, 1, 10, 12))
	t.set_stylebox("focus", name, _box(bg, Color.WHITE, 2, 10, 12))
	t.set_color("font_color", name, fg)
	t.set_color("font_hover_color", name, fg)
	t.set_color("font_pressed_color", name, fg)
	t.set_color("font_disabled_color", name, COLOR_TEXT_DISABLED)
	t.set_font_size("font_size", name, font_size)

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
	t.set_stylebox("panel", "PromptBarPanel", _box(COLOR_PANEL_LIGHT, COLOR_ACCENT_DIM, 2, 14, 14))

	t.set_type_variation("OverlayBackdrop", "PanelContainer")
	t.set_stylebox("panel", "OverlayBackdrop", _box(Color(0.04, 0.05, 0.07, 0.88), Color(0, 0, 0, 0), 0, 0, 0))

	t.set_type_variation("OverlayCard", "PanelContainer")
	t.set_stylebox("panel", "OverlayCard", _box(COLOR_PANEL, COLOR_PANEL_BORDER, 2, 16, 24))

	t.set_type_variation("LegalTargetHighlight", "PanelContainer")
	t.set_stylebox("panel", "LegalTargetHighlight", _box(Color(COLOR_ATTACH_HIGHLIGHT, 0.18), COLOR_ATTACH_HIGHLIGHT, 3, 14, 4))

	t.set_type_variation("DecoyTargetHighlight", "PanelContainer")
	t.set_stylebox("panel", "DecoyTargetHighlight", _box(Color(COLOR_DECOY_HIGHLIGHT, 0.18), COLOR_DECOY_HIGHLIGHT, 3, 14, 4))

	t.set_type_variation("StealTargetHighlight", "PanelContainer")
	t.set_stylebox("panel", "StealTargetHighlight", _box(Color(COLOR_STEAL, 0.22), COLOR_STEAL, 3, 12, 4))

	t.set_type_variation("PilePanel", "PanelContainer")
	t.set_stylebox("panel", "PilePanel", _box(COLOR_FELT_DARK, Color8(230, 230, 230), 2, 8, 8))

	t.set_type_variation("ChipPanel", "PanelContainer")
	t.set_stylebox("panel", "ChipPanel", _box(COLOR_PANEL_LIGHT, Color(0, 0, 0, 0), 0, 6, 4))

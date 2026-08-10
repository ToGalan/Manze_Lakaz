extends Control
## Board-Game-Arena-style table, playable either hot-seat (local,
## multiple people sharing this device) or online (each player on their
## own device, server-authoritative). GameScreen never touches rules or
## network internals directly -- it only ever talks to a GameSession
## (LocalHotSeatSession or NetworkSession). Every action button is
## enabled/disabled strictly by whether a matching Action is present in
## session.get_legal_actions(), and every mutation goes through
## session.submit_action(). Animations are purely decorative flourishes
## layered on top of already-correct state -- nothing here ever waits on
## a Tween to decide what happens next.

const DATA_DIR := "res://data"

enum UiMode { SETUP, NETWORK_SETUP, LOBBY, PASS_DEVICE, DRAFT, PLAY, AI_THINKING, GAME_OVER }

var db: CardDatabase
var session: GameSession
var state: GameState # a cached read of session.get_state(), refreshed every _advance_ui_after_state_change()
var is_network_mode: bool = false
var ui_mode: int = UiMode.SETUP
var selected_card_id: int = -1
var debug_visible: bool = false
var log_collapsed: bool = true
var _dealt_seen: Dictionary = {} # player_index -> true, once their first hand reveal has played
var _player_panel_nodes: Dictionary = {} # player_index -> PlayerPanel, for the current render

# Hot-seat setup (player count + per-seat Human/AI + AI think time).
var think_time_seconds: float = 1.0
var _pending_num_players: int = 4
var _pending_seat_mode: Dictionary = {} # player_index -> -1 (Human) or AiBot.Difficulty

# Online setup + lobby.
var _pending_is_host: bool = true
var _pending_display_name: String = "Player"
var _pending_host_port: int = 8910
var _pending_join_address: String = "127.0.0.1"
var _pending_join_port: int = 8910
var _pending_turn_timer_seconds: float = 30.0
var _pending_auto_play_difficulty: int = AiBot.Difficulty.EASY
var _pending_fill_ai: bool = true
var _pending_ai_fill_difficulty: int = AiBot.Difficulty.MEDIUM
var lobby_seats: Array = []

# Static structure, built once in _ready().
var main_layout: VBoxContainer
var top_bar: HFlowContainer
var table_surface: TableSurface
var log_toggle_button: Button
var log_panel: PanelContainer
var log_box: VBoxContainer
var log_scroll: ScrollContainer
var prompt_panel: PanelContainer
var prompt_label: Label
var prompt_buttons_box: HBoxContainer
var hand_fan: HandFan
var animation_layer: Control

var overlay_layer: Control
var setup_overlay: PanelContainer
var network_setup_overlay: PanelContainer
var lobby_overlay: PanelContainer
var pass_overlay: PanelContainer
var draft_overlay: PanelContainer
var ai_thinking_overlay: PanelContainer
var gameover_overlay: PanelContainer

var debug_toggle_button: Button
var debug_panel: PanelContainer
var debug_label: Label

func _ready() -> void:
	theme = GameTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	db = DataLoader.load_database_or_fail(
		DATA_DIR + "/ingredients.json",
		DATA_DIR + "/preparations.json",
		DATA_DIR + "/recipes.json"
	)

	_build_static_ui()

	if db == null:
		prompt_label.text = "Data failed to validate -- see console output."
		return

	_show_setup()

# ===========================================================================
# Static UI construction (built once)
# ===========================================================================

func _build_static_ui() -> void:
	var bg := ColorRect.new()
	bg.color = GameTheme.COLOR_APP_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer_margin)

	main_layout = VBoxContainer.new()
	outer_margin.add_child(main_layout)

	top_bar = HFlowContainer.new()
	main_layout.add_child(top_bar)

	var middle := HBoxContainer.new()
	middle.theme_type_variation = "WideHBox"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_layout.add_child(middle)

	table_surface = TableSurface.new()
	table_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_surface.take_discard_requested.connect(_on_take_discard_pressed)
	middle.add_child(table_surface)

	var log_side := VBoxContainer.new()
	log_side.theme_type_variation = "TightVBox"
	middle.add_child(log_side)

	log_toggle_button = Button.new()
	log_toggle_button.theme_type_variation = "SecondaryButton"
	log_toggle_button.pressed.connect(_on_log_toggle_pressed)
	log_side.add_child(log_toggle_button)

	log_panel = PanelContainer.new()
	log_panel.theme_type_variation = "LogPanel"
	log_panel.custom_minimum_size = Vector2(260, 0)
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_side.add_child(log_panel)

	log_scroll = ScrollContainer.new()
	log_panel.add_child(log_scroll)

	log_box = VBoxContainer.new()
	log_box.theme_type_variation = "TightVBox"
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_box)

	log_panel.visible = not log_collapsed
	log_toggle_button.text = "Log <" if not log_collapsed else "Log >"

	prompt_panel = PanelContainer.new()
	prompt_panel.theme_type_variation = "PromptBarPanel"
	# A Label with autowrap under-reports its own minimum height to
	# whatever container is sizing it (it only accounts for one line), so
	# without a floor here the VBoxContainer can allocate less room than a
	# two-line prompt actually needs and the text overflows into whatever
	# sits above it. Tall enough for a two-line PromptLabel + the button row.
	prompt_panel.custom_minimum_size = Vector2(0, 76)
	main_layout.add_child(prompt_panel)

	var prompt_row := HBoxContainer.new()
	prompt_row.theme_type_variation = "WideHBox"
	prompt_panel.add_child(prompt_row)

	prompt_label = Label.new()
	prompt_label.theme_type_variation = "PromptLabel"
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_row.add_child(prompt_label)

	prompt_buttons_box = HBoxContainer.new()
	prompt_row.add_child(prompt_buttons_box)

	hand_fan = HandFan.new()
	hand_fan.card_clicked.connect(_on_hand_card_clicked)
	main_layout.add_child(hand_fan)

	_build_overlays()

	animation_layer = Control.new()
	animation_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	animation_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(animation_layer)

	_build_debug_panel()

	resized.connect(_on_screen_resized)
	_on_screen_resized()

## hand_fan/prompt_panel/log_panel each impose a minimum size on
## main_layout's single VBoxContainer, which never scrolls -- on a short or
## narrow viewport (a resized window, a phone in portrait), fixed pixel
## floors here are exactly what would force the table to be starved of
## space or push content past the bottom of the screen. Scaling these
## floors off the actual viewport size (with the same clamp-based approach
## HandFan already uses internally for its own card sizing) keeps every
## section visible and usable at any window size instead of just the one
## this was designed at.
func _on_screen_resized() -> void:
	if size.y <= 0.0 or size.x <= 0.0:
		return
	hand_fan.custom_minimum_size.y = clampf(size.y * 0.24, 110.0, 190.0)
	prompt_panel.custom_minimum_size.y = clampf(size.y * 0.11, 56.0, 76.0)
	log_panel.custom_minimum_size.x = clampf(size.x * 0.22, 160.0, 320.0)

func _build_overlays() -> void:
	overlay_layer = Control.new()
	overlay_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_layer)

	setup_overlay = _make_overlay_panel()
	network_setup_overlay = _make_overlay_panel()
	lobby_overlay = _make_overlay_panel()
	pass_overlay = _make_overlay_panel()
	draft_overlay = _make_overlay_panel()
	ai_thinking_overlay = _make_overlay_panel()
	gameover_overlay = _make_overlay_panel()

func _make_overlay_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "OverlayBackdrop"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	overlay_layer.add_child(panel)
	return panel

## ScrollContainer -> themed card panel -> VBox, ready for overlay content.
## A ScrollContainer, not a bare CenterContainer, for the same reason as
## TableSurface's recipe row: a setup screen with 4 per-seat difficulty
## pickers, a network host/join form, or a long draft offer list can end up
## taller (or wider) than a short/narrow viewport, and CenterContainer
## never clips or scrolls -- it silently overflows past the screen edge.
func _overlay_content_box(overlay: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margin.add_child(scroll)

	# ScrollContainer never hands its child more than the child's own
	# minimum size -- unlike every other Container, it does NOT give a
	# smaller child the rest of its available space, so neither
	# size_flags=SHRINK_CENTER nor a plain nested CenterContainer actually
	# centers anything here; the extra space is just left empty at the
	# bottom-right while content sits pinned at the top-left. The real fix:
	# force the CenterContainer's own minimum size to match the scroll
	# view, kept in sync across resizes, so it fills that view and
	# genuinely centers its child -- and once real content outgrows that
	# floor, the CenterContainer's minimum grows past it and scrolling
	# takes over exactly as before.
	var center := CenterContainer.new()
	scroll.add_child(center)

	var card := PanelContainer.new()
	card.theme_type_variation = "OverlayCard"
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.theme_type_variation = "WideVBox"
	card.add_child(vbox)

	_sync_overlay_center(scroll, center)
	scroll.resized.connect(_sync_overlay_center.bind(scroll, center))
	return vbox

func _sync_overlay_center(scroll: ScrollContainer, center: CenterContainer) -> void:
	center.custom_minimum_size = scroll.size

func _build_debug_panel() -> void:
	debug_toggle_button = Button.new()
	debug_toggle_button.theme_type_variation = "SecondaryButton"
	debug_toggle_button.text = "Debug"
	debug_toggle_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_toggle_button.position = Vector2(-90, 8)
	debug_toggle_button.size = Vector2(80, 0)
	debug_toggle_button.pressed.connect(_on_debug_toggle_pressed)
	add_child(debug_toggle_button)

	debug_panel = PanelContainer.new()
	debug_panel.theme_type_variation = "LogPanel"
	debug_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	debug_panel.anchor_left = 0.62
	debug_panel.visible = false
	add_child(debug_panel)

	var scroll := ScrollContainer.new()
	debug_panel.add_child(scroll)

	debug_label = Label.new()
	debug_label.theme_type_variation = "LogEntryLabel"
	debug_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	scroll.add_child(debug_label)

func _on_debug_toggle_pressed() -> void:
	debug_visible = not debug_visible
	debug_panel.visible = debug_visible
	_refresh_debug_panel()

func _refresh_debug_panel() -> void:
	if not debug_visible:
		return
	# Note: even in network mode this only ever reveals what THIS
	# session's shadow state actually contains -- opponents' hands are
	# empty there too, by construction (see ShadowStateBuilder).
	debug_label.text = GameViewModel.debug_dump(state) if state != null else "(no game in progress)"

func _on_log_toggle_pressed() -> void:
	log_collapsed = not log_collapsed
	log_panel.visible = not log_collapsed
	log_toggle_button.text = "Log <" if not log_collapsed else "Log >"

# ===========================================================================
# Session plumbing (shared by hot-seat and network)
# ===========================================================================

func _connect_session(new_session: GameSession) -> void:
	if session != null:
		if session.state_changed.is_connected(_on_session_state_changed):
			session.state_changed.disconnect(_on_session_state_changed)
	session = new_session
	session.state_changed.connect(_on_session_state_changed)

func _on_session_state_changed() -> void:
	_advance_ui_after_state_change()

func _submit_action(action: Action) -> void:
	session.submit_action(action)

func _viewer_index() -> int:
	return session.viewer_index()

# ===========================================================================
# Setup screen (hot-seat config + entry points to online play)
# ===========================================================================

func _show_setup() -> void:
	ui_mode = UiMode.SETUP
	_clear_children(setup_overlay)
	var box := _overlay_content_box(setup_overlay)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Manze Lakaz"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.theme_type_variation = "HintLabel"
	subtitle.text = "Choose player count, then set each seat to Human or an AI difficulty"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	var count_row := HBoxContainer.new()
	count_row.theme_type_variation = "WideHBox"
	box.add_child(count_row)
	for n in [2, 3, 4]:
		var b := Button.new()
		b.theme_type_variation = "PrimaryButton" if n == _pending_num_players else "SecondaryButton"
		b.text = "%d players" % n
		b.pressed.connect(_on_pending_player_count_pressed.bind(n))
		count_row.add_child(b)

	var seat_rows := VBoxContainer.new()
	box.add_child(seat_rows)
	for i in _pending_num_players:
		seat_rows.add_child(_build_seat_row(i))

	var think_row := HBoxContainer.new()
	box.add_child(think_row)
	var think_label := Label.new()
	think_label.theme_type_variation = "HintLabel"
	think_label.text = "AI think time: %.1fs" % think_time_seconds
	think_row.add_child(think_label)
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 2.5
	slider.step = 0.1
	slider.value = think_time_seconds
	slider.custom_minimum_size = Vector2(220, 0)
	slider.value_changed.connect(_on_think_time_changed.bind(think_label))
	think_row.add_child(slider)

	var start_button := Button.new()
	start_button.theme_type_variation = "PrimaryButton"
	start_button.text = "Start hot-seat game"
	start_button.custom_minimum_size = Vector2(260, 0)
	start_button.pressed.connect(_on_start_pressed)
	box.add_child(start_button)

	var online_label := Label.new()
	online_label.theme_type_variation = "SectionLabel"
	online_label.text = "OR PLAY ONLINE"
	online_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(online_label)

	var online_row := HBoxContainer.new()
	online_row.theme_type_variation = "WideHBox"
	box.add_child(online_row)
	var host_btn := Button.new()
	host_btn.theme_type_variation = "SecondaryButton"
	host_btn.text = "Host Online Game"
	host_btn.pressed.connect(_show_network_setup.bind(true))
	online_row.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.theme_type_variation = "SecondaryButton"
	join_btn.text = "Join Online Game"
	join_btn.pressed.connect(_show_network_setup.bind(false))
	online_row.add_child(join_btn)

	_apply_overlay_visibility()

func _build_seat_row(seat_index: int) -> HBoxContainer:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.theme_type_variation = "PlayerNameLabel"
	label.text = "Player %d:" % (seat_index + 1)
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)

	# Default: seat 0 is Human, every other seat defaults to a Medium AI.
	var current: int = _pending_seat_mode.get(seat_index, -1 if seat_index == 0 else AiBot.Difficulty.MEDIUM)
	_pending_seat_mode[seat_index] = current

	var mode_button := Button.new()
	mode_button.theme_type_variation = "SecondaryButton"
	mode_button.custom_minimum_size = Vector2(160, 0)
	mode_button.text = _seat_mode_label(current)
	mode_button.pressed.connect(_on_seat_mode_cycle_pressed.bind(seat_index, mode_button))
	row.add_child(mode_button)

	return row

func _seat_mode_label(mode: int) -> String:
	if mode == -1:
		return "Human"
	return "AI -- " + AiBot.DIFFICULTY_NAMES[mode]

func _on_seat_mode_cycle_pressed(seat_index: int, button: Button) -> void:
	var current: int = _pending_seat_mode.get(seat_index, -1)
	var next: int
	match current:
		-1:
			next = AiBot.Difficulty.EASY
		AiBot.Difficulty.EASY:
			next = AiBot.Difficulty.MEDIUM
		AiBot.Difficulty.MEDIUM:
			next = AiBot.Difficulty.HARD
		_:
			next = -1
	_pending_seat_mode[seat_index] = next
	button.text = _seat_mode_label(next)

func _on_pending_player_count_pressed(n: int) -> void:
	_pending_num_players = n
	if ui_mode == UiMode.NETWORK_SETUP:
		_show_network_setup(_pending_is_host)
	else:
		_show_setup()

func _on_think_time_changed(value: float, label: Label) -> void:
	think_time_seconds = value
	label.text = "AI think time: %.1fs" % value

func _on_start_pressed() -> void:
	var config := GameConfig.new()
	config.num_players = _pending_num_players
	config.seed = int(Time.get_unix_time_from_system() * 1000.0) % 1000000

	var hot_seat := LocalHotSeatSession.new(db)
	if not hot_seat.start_game(config):
		prompt_label.text = "Failed to start game -- see console output."
		return

	for i in _pending_num_players:
		var mode: int = _pending_seat_mode.get(i, -1)
		if mode != -1:
			hot_seat.seat_bots[i] = AiBot.create(mode, i)
			hot_seat.seat_difficulty[i] = mode

	is_network_mode = false
	_connect_session(hot_seat)

	_clear_children(log_box)
	selected_card_id = -1
	_dealt_seen.clear()
	_advance_ui_after_state_change()

# ===========================================================================
# Online setup + lobby
# ===========================================================================

func _network_peer() -> Node:
	return get_node("/root/NetworkPeer")

func _show_network_setup(is_host: bool) -> void:
	_pending_is_host = is_host
	ui_mode = UiMode.NETWORK_SETUP
	_clear_children(network_setup_overlay)
	var box := _overlay_content_box(network_setup_overlay)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Host Online Game" if is_host else "Join Online Game"
	box.add_child(title)

	_add_labeled_line_edit(box, "Your name:", _pending_display_name, func(t): _pending_display_name = t)

	if is_host:
		var count_row := HBoxContainer.new()
		count_row.theme_type_variation = "WideHBox"
		box.add_child(count_row)
		for n in [2, 3, 4]:
			var b := Button.new()
			b.theme_type_variation = "PrimaryButton" if n == _pending_num_players else "SecondaryButton"
			b.text = "%d players" % n
			b.pressed.connect(_on_pending_player_count_pressed.bind(n))
			count_row.add_child(b)

		_add_labeled_line_edit(box, "Port:", str(_pending_host_port), func(t): _pending_host_port = int(t) if t.is_valid_int() else _pending_host_port)

		var timer_row := HBoxContainer.new()
		box.add_child(timer_row)
		var timer_label := Label.new()
		timer_label.theme_type_variation = "HintLabel"
		timer_label.text = "Turn timer: %.0fs" % _pending_turn_timer_seconds
		timer_row.add_child(timer_label)
		var timer_slider := HSlider.new()
		timer_slider.min_value = 10
		timer_slider.max_value = 120
		timer_slider.step = 5
		timer_slider.value = _pending_turn_timer_seconds
		timer_slider.custom_minimum_size = Vector2(200, 0)
		timer_slider.value_changed.connect(func(v): _pending_turn_timer_seconds = v; timer_label.text = "Turn timer: %.0fs" % v)
		timer_row.add_child(timer_slider)

		var fallback_row := HBoxContainer.new()
		box.add_child(fallback_row)
		var fallback_label := Label.new()
		fallback_label.theme_type_variation = "HintLabel"
		fallback_label.text = "If a turn times out, auto-play as:"
		fallback_row.add_child(fallback_label)
		var fallback_button := Button.new()
		fallback_button.theme_type_variation = "SecondaryButton"
		fallback_button.text = AiBot.DIFFICULTY_NAMES[_pending_auto_play_difficulty]
		fallback_button.pressed.connect(func():
			_pending_auto_play_difficulty = (_pending_auto_play_difficulty + 1) % 3
			fallback_button.text = AiBot.DIFFICULTY_NAMES[_pending_auto_play_difficulty]
		)
		fallback_row.add_child(fallback_button)

		var fill_row := HBoxContainer.new()
		box.add_child(fill_row)
		var fill_check := CheckBox.new()
		fill_check.text = "Fill empty seats with AI"
		fill_check.button_pressed = _pending_fill_ai
		fill_check.toggled.connect(func(v): _pending_fill_ai = v)
		fill_row.add_child(fill_check)
		var fill_difficulty_button := Button.new()
		fill_difficulty_button.theme_type_variation = "SecondaryButton"
		fill_difficulty_button.text = AiBot.DIFFICULTY_NAMES[_pending_ai_fill_difficulty]
		fill_difficulty_button.pressed.connect(func():
			_pending_ai_fill_difficulty = (_pending_ai_fill_difficulty + 1) % 3
			fill_difficulty_button.text = AiBot.DIFFICULTY_NAMES[_pending_ai_fill_difficulty]
		)
		fill_row.add_child(fill_difficulty_button)

		var host_button := Button.new()
		host_button.theme_type_variation = "PrimaryButton"
		host_button.text = "Start hosting"
		host_button.custom_minimum_size = Vector2(260, 0)
		host_button.pressed.connect(_on_host_pressed)
		box.add_child(host_button)
	else:
		_add_labeled_line_edit(box, "Server address:", _pending_join_address, func(t): _pending_join_address = t)
		_add_labeled_line_edit(box, "Port:", str(_pending_join_port), func(t): _pending_join_port = int(t) if t.is_valid_int() else _pending_join_port)

		var join_button := Button.new()
		join_button.theme_type_variation = "PrimaryButton"
		join_button.text = "Connect"
		join_button.custom_minimum_size = Vector2(260, 0)
		join_button.pressed.connect(_on_join_pressed)
		box.add_child(join_button)

	var back_button := Button.new()
	back_button.theme_type_variation = "SecondaryButton"
	back_button.text = "Back"
	back_button.pressed.connect(_show_setup)
	box.add_child(back_button)

	_apply_overlay_visibility()

func _add_labeled_line_edit(box: VBoxContainer, label_text: String, initial_value: String, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.theme_type_variation = "HintLabel"
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = initial_value
	edit.custom_minimum_size = Vector2(180, 0)
	edit.text_changed.connect(on_changed)
	row.add_child(edit)

func _on_host_pressed() -> void:
	var config := GameConfig.new()
	config.num_players = _pending_num_players
	config.seed = int(Time.get_unix_time_from_system() * 1000.0) % 1000000

	var peer := _network_peer()
	var err: int = peer.start_hosting(db, config, _pending_host_port, _pending_turn_timer_seconds, _pending_auto_play_difficulty, think_time_seconds, _pending_fill_ai, _pending_ai_fill_difficulty)
	if err != OK:
		prompt_label.text = "Failed to host (error %d) -- is the port already in use?" % err
		return

	is_network_mode = true
	_connect_session(NetworkSession.new(db, peer))
	_wire_lobby_signals(peer)

	peer.request_join(_pending_display_name) # host's own seat: no network round-trip needed
	_show_lobby()

func _on_join_pressed() -> void:
	var peer := _network_peer()
	var err: int = peer.join_as_client(_pending_join_address, _pending_join_port, db)
	if err != OK:
		prompt_label.text = "Failed to connect (error %d)" % err
		return

	is_network_mode = true
	_connect_session(NetworkSession.new(db, peer))
	_wire_lobby_signals(peer)

	multiplayer.connected_to_server.connect(func(): peer.request_join(_pending_display_name), CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(func(): prompt_label.text = "Connection failed.", CONNECT_ONE_SHOT)

	_show_lobby()

func _wire_lobby_signals(peer: Node) -> void:
	if not peer.lobby_changed.is_connected(_on_lobby_changed):
		peer.lobby_changed.connect(_on_lobby_changed)
	if not peer.join_rejected.is_connected(_on_join_rejected):
		peer.join_rejected.connect(_on_join_rejected)

func _on_join_rejected(reason: String) -> void:
	prompt_label.text = "Join rejected: %s" % reason

func _on_lobby_changed(lobby: Dictionary) -> void:
	lobby_seats = lobby.get("seats", [])
	if ui_mode == UiMode.LOBBY:
		_show_lobby()

func _show_lobby() -> void:
	ui_mode = UiMode.LOBBY
	_clear_children(lobby_overlay)
	var box := _overlay_content_box(lobby_overlay)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Lobby"
	box.add_child(title)

	for seat_info in lobby_seats:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.theme_type_variation = "PlayerNameLabel"
		var status := "connected" if seat_info["connected"] else ("AI" if seat_info["is_ai"] else "empty")
		label.text = "Seat %d: %s (%s)" % [int(seat_info["seat"]) + 1, str(seat_info["name"]), status]
		row.add_child(label)

	var peer := _network_peer()
	if peer.authority != null:
		var start_button := Button.new()
		start_button.theme_type_variation = "PrimaryButton"
		start_button.text = "Start game"
		start_button.custom_minimum_size = Vector2(220, 0)
		start_button.pressed.connect(func(): peer.request_start_game())
		box.add_child(start_button)
	else:
		var waiting := Label.new()
		waiting.theme_type_variation = "HintLabel"
		waiting.text = "Waiting for the host to start the game..."
		box.add_child(waiting)

	var leave_button := Button.new()
	leave_button.theme_type_variation = "SecondaryButton"
	leave_button.text = "Leave"
	leave_button.pressed.connect(_on_leave_lobby_pressed)
	box.add_child(leave_button)

	_apply_overlay_visibility()

func _on_leave_lobby_pressed() -> void:
	_network_peer().shutdown()
	is_network_mode = false
	_show_setup()

# ===========================================================================
# Turn-owner change detection -> hot-seat privacy (network mode never gates)
# ===========================================================================

func _advance_ui_after_state_change() -> void:
	state = session.get_state()
	_refresh_debug_panel()
	if state == null:
		return

	if state.game_over:
		_show_game_over()
		return

	if is_network_mode:
		# No pass-device gate online: this device only ever shows its OWN
		# assigned seat's board (see ShadowStateBuilder/NetworkStateFilter),
		# so there is nothing to hide from "whoever's holding the device".
		if state.phase == GameState.Phase.DRAFT:
			_show_draft()
		else:
			_show_play()
		return

	var hot_seat := session as LocalHotSeatSession
	if hot_seat.is_seat_ai(state.current_player_index):
		_show_ai_thinking()
		return

	if state.current_player_index != hot_seat.viewer_index():
		selected_card_id = -1
		_show_pass_device()
		return

	if state.phase == GameState.Phase.DRAFT:
		_show_draft()
	else:
		_show_play()

## AI turns are resolved entirely behind this overlay: no board, no hand,
## nothing rendered that a human shouldn't see. Only the resulting log
## lines (draws, attaches, steals, discards -- all public consequences)
## become visible once control returns to a human. Hot-seat only: online
## AI seats are server-side (ServerAuthority), never driven from here.
func _show_ai_thinking() -> void:
	ui_mode = UiMode.AI_THINKING
	_clear_children(ai_thinking_overlay)
	var box := _overlay_content_box(ai_thinking_overlay)

	var hot_seat := session as LocalHotSeatSession
	var difficulty: int = hot_seat.seat_difficulty.get(state.current_player_index, AiBot.Difficulty.MEDIUM)
	var label := Label.new()
	label.theme_type_variation = "TitleLabel"
	label.text = "Player %d (%s AI) is thinking..." % [state.current_player_index + 1, AiBot.DIFFICULTY_NAMES[difficulty]]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	_apply_overlay_visibility()

	get_tree().create_timer(think_time_seconds).timeout.connect(_run_ai_step)

func _run_ai_step() -> void:
	var hot_seat := session as LocalHotSeatSession
	if state.game_over or not hot_seat.is_seat_ai(state.current_player_index):
		_advance_ui_after_state_change()
		return

	var bot: AiBot = hot_seat.seat_bots[state.current_player_index]
	var legal := session.get_legal_actions()
	if legal.is_empty():
		_advance_ui_after_state_change()
		return

	var action := bot.choose_action(state, legal)
	if action == null:
		_advance_ui_after_state_change()
		return

	var line := GameViewModel.describe_action_for_log(state, action)
	_submit_action(action)
	_append_log_line(line)

func _append_log_line(text: String) -> void:
	var l := Label.new()
	l.theme_type_variation = "LogEntryLabel"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_box.add_child(l)
	call_deferred("_scroll_log_to_bottom")

func _scroll_log_to_bottom() -> void:
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

# ===========================================================================
# Pass-the-device screen (hot-seat only)
# ===========================================================================

func _show_pass_device() -> void:
	ui_mode = UiMode.PASS_DEVICE
	_clear_children(pass_overlay)
	var box := _overlay_content_box(pass_overlay)

	var next_player_num := state.current_player_index + 1
	var headline := Label.new()
	headline.theme_type_variation = "TitleLabel"
	headline.text = "Pass the device to Player %d" % next_player_num
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(headline)

	var sub := Label.new()
	sub.theme_type_variation = "HintLabel"
	sub.text = "Everyone else look away."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var ready_button := Button.new()
	ready_button.theme_type_variation = "PrimaryButton"
	ready_button.text = "I'm Player %d -- show my turn" % next_player_num
	ready_button.custom_minimum_size = Vector2(300, 0)
	ready_button.pressed.connect(_on_pass_device_ready_pressed)
	box.add_child(ready_button)

	_apply_overlay_visibility()

func _on_pass_device_ready_pressed() -> void:
	(session as LocalHotSeatSession).set_viewer_index(state.current_player_index)
	if state.phase == GameState.Phase.DRAFT:
		_show_draft()
	else:
		_show_play()

# ===========================================================================
# Draft screen
# ===========================================================================

func _show_draft() -> void:
	ui_mode = UiMode.DRAFT
	_clear_children(draft_overlay)
	var box := _overlay_content_box(draft_overlay)

	var legal := session.get_legal_actions()
	var header := Label.new()
	header.theme_type_variation = "TitleLabel"
	header.text = GameViewModel.status_text(state, legal)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(header)

	var row := HBoxContainer.new()
	row.theme_type_variation = "WideHBox"
	box.add_child(row)

	for offer in GameViewModel.draft_offer_view(state, _viewer_index()):
		row.add_child(_build_draft_card(offer, legal))

	_apply_overlay_visibility()

func _build_draft_card(offer: Dictionary, legal: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "RecipePanel"
	panel.custom_minimum_size = Vector2(230, 0)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.theme_type_variation = "RecipeTitleLabel"
	title.text = offer["title"]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	if not offer["ingredients"].is_empty():
		var ing := Label.new()
		ing.theme_type_variation = "HintLabel"
		ing.text = "Ingredients: " + ", ".join(offer["ingredients"])
		ing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(ing)
	if not offer["preparations"].is_empty():
		var prep := Label.new()
		prep.theme_type_variation = "HintLabel"
		prep.text = "Preparations: " + ", ".join(offer["preparations"])
		prep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(prep)
	if offer["uses_grill"]:
		var grill := Label.new()
		grill.theme_type_variation = "HintLabel"
		grill.text = "+ Grill (free)"
		box.add_child(grill)

	var keep_action := _find_draft_keep_action(legal, offer["recipe_id"])
	var keep_button := Button.new()
	keep_button.theme_type_variation = "PrimaryButton"
	keep_button.text = "Keep this recipe"
	keep_button.disabled = keep_action == null
	if keep_action != null:
		keep_button.pressed.connect(_on_draft_keep_pressed.bind(offer["recipe_id"]))
	box.add_child(keep_button)

	return panel

func _on_draft_keep_pressed(recipe_id: String) -> void:
	var line := GameViewModel.describe_action_for_log(state, Action.make_draft_keep(_viewer_index(), recipe_id))
	_submit_action(Action.make_draft_keep(_viewer_index(), recipe_id))
	if not is_network_mode:
		_append_log_line(line)

# ===========================================================================
# Main play screen
# ===========================================================================

func _show_play() -> void:
	ui_mode = UiMode.PLAY
	_apply_overlay_visibility()

	var pidx := _viewer_index()
	if not _dealt_seen.has(pidx):
		_dealt_seen[pidx] = true
		_play_deal_animation(pidx)

	_refresh_play_view()

func _refresh_play_view() -> void:
	var legal := session.get_legal_actions()
	_render_top_bar(legal)
	_render_table(legal)
	_render_prompt_bar(legal)
	_render_hand(legal)

func _play_deal_animation(pidx: int) -> void:
	var player: Player = state.players[pidx]
	var deck_pos := table_surface.get_deck_marker_global_position()
	var hand_pos := hand_fan.get_fan_center_global_position()
	for i in player.hand.size():
		var delay := i * 0.06
		get_tree().create_timer(delay).timeout.connect(
			func(): CardAnimator.fly(animation_layer, deck_pos, hand_pos, "", "back", "deal")
		)

func _render_top_bar(legal: Array) -> void:
	_clear_children(top_bar)
	_player_panel_nodes.clear()

	var viewer := _viewer_index()
	for p in state.players:
		var panel := PlayerPanel.new()
		panel.steal_requested.connect(_on_steal_requested)
		top_bar.add_child(panel)
		_player_panel_nodes[p.index] = panel

		var is_viewer := p.index == viewer
		var is_active_turn := p.index == state.current_player_index
		var recipe_rows: Array = []
		if not is_viewer:
			for ri in p.recipes.size():
				var recipe: Recipe = p.recipes[ri]
				var cards: Array = []
				for att in GameViewModel.other_recipe_attachments(recipe, db):
					var steal_action := _find_steal_action(legal, p.index, ri, att["card_instance_id"])
					cards.append({
						"label": att["label"],
						"category_key": CardCategoryMap.category_for(att["def_id"], att["category"]),
						"card_instance_id": att["card_instance_id"],
						"stealable": steal_action != null,
					})
				recipe_rows.append({"recipe_index": ri, "cards": cards})

		var completed := 0
		for r in p.recipes:
			if r.completed:
				completed += 1
		var hand_count := ShadowStateBuilder.hand_count_of(p)
		var steals_remaining := GameViewModel.steals_remaining(state, p)
		panel.update(p.index, hand_count, completed, p.recipes.size(), steals_remaining, state.config.max_steals_per_player, is_active_turn, recipe_rows)

func _render_table(legal: Array) -> void:
	var top_discard := {}
	if not state.discard_pile.is_empty():
		var top: Card = state.discard_pile[state.discard_pile.size() - 1]
		top_discard = {
			"label": GameViewModel.card_label(top.def_id, top.category, db),
			"category_key": CardCategoryMap.category_for(top.def_id, top.category),
		}
	var discard_takeable := _has_action_type(legal, Action.Type.TAKE_DISCARD)
	table_surface.update_piles(state.deck.size(), state.discard_pile.size(), top_discard, discard_takeable)

	_clear_children(table_surface.own_recipes_box)
	var player := state.players[_viewer_index()]
	for ri in player.recipes.size():
		table_surface.own_recipes_box.add_child(_build_own_recipe_panel(player.recipes[ri], ri, legal))

func _build_own_recipe_panel(recipe: Recipe, ri: int, legal: Array) -> Control:
	var outer := PanelContainer.new()
	# Wide enough for the longest real recipe title + tier suffix ("Creole
	# Fish Curry (Feast)") and the longest ingredient/prep slot line ("[ ]
	# Island Spice Blend") without relying on the panel growing past this
	# floor to fit them -- when this panel is a legal attach target (see
	# below), its content is anchored inside a Button instead of flowing
	# normally, which means it does NOT grow past this floor even if its
	# text needs more room. Every label below carries its own autowrap so
	# text that still doesn't fit wraps to a second line instead of
	# clipping, regardless of which of the two layouts is in play.
	outer.custom_minimum_size = Vector2(260, 0)

	var attach_action: Action = null
	if selected_card_id != -1:
		attach_action = _find_attach_action(legal, selected_card_id, ri)

	var box := VBoxContainer.new()

	if attach_action != null:
		outer.theme_type_variation = "DecoyTargetHighlight" if attach_action.as_decoy else "LegalTargetHighlight"
		var btn := Button.new()
		btn.theme_type_variation = "InvisibleFillButton"
		btn.pressed.connect(_on_recipe_target_pressed.bind(ri, outer))
		outer.add_child(btn)
		btn.add_child(box)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
	else:
		outer.theme_type_variation = "RecipePanelComplete" if recipe.completed else "RecipePanel"
		outer.add_child(box)

	var title := Label.new()
	title.theme_type_variation = "RecipeTitleLabel"
	title.text = GameViewModel.recipe_title(recipe.def) + (" -- COMPLETE" if recipe.completed else "")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	for slot in GameViewModel.own_recipe_slots(recipe, db):
		var row := Label.new()
		row.theme_type_variation = "RecipeSlotFilledLabel" if slot["filled"] else "RecipeSlotEmptyLabel"
		row.text = ("[x] " if slot["filled"] else "[ ] ") + slot["label"]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(row)

	return outer

func _render_hand(legal: Array) -> void:
	var player := state.players[_viewer_index()]
	var selectable: Dictionary = {}
	for a in legal:
		if a.type == Action.Type.ATTACH or a.type == Action.Type.DISCARD:
			selectable[a.card_instance_id] = true
	if selected_card_id != -1 and not selectable.has(selected_card_id):
		selected_card_id = -1
	hand_fan.set_cards(player.hand, db, selectable, selected_card_id)

func _render_prompt_bar(legal: Array) -> void:
	_clear_children(prompt_buttons_box)

	if selected_card_id != -1:
		var card := state.players[_viewer_index()].find_in_hand(selected_card_id)
		var card_name := GameViewModel.card_label(card.def_id, card.category, db) if card != null else "that card"
		prompt_label.text = "Selected %s -- click a glowing recipe to attach it, or discard it" % card_name

		var discard_action := _find_discard_action(legal, selected_card_id)
		var discard_btn := Button.new()
		discard_btn.theme_type_variation = "PrimaryButton"
		discard_btn.text = "Discard"
		discard_btn.disabled = discard_action == null
		if discard_action != null:
			discard_btn.pressed.connect(_on_discard_pressed.bind(selected_card_id))
		prompt_buttons_box.add_child(discard_btn)

		var cancel_btn := Button.new()
		cancel_btn.theme_type_variation = "SecondaryButton"
		cancel_btn.text = "Cancel"
		cancel_btn.pressed.connect(_on_cancel_selection_pressed)
		prompt_buttons_box.add_child(cancel_btn)
		return

	prompt_label.text = GameViewModel.status_text(state, legal)

	if _has_action_type(legal, Action.Type.DRAW):
		var draw_btn := Button.new()
		draw_btn.theme_type_variation = "PrimaryButton"
		draw_btn.text = "Draw"
		draw_btn.pressed.connect(_on_draw_pressed)
		prompt_buttons_box.add_child(draw_btn)

	if _has_action_type(legal, Action.Type.STEAL):
		var hint := Label.new()
		hint.theme_type_variation = "HintLabel"
		hint.text = "or click a glowing card above to steal it"
		prompt_buttons_box.add_child(hint)

	if _has_action_type(legal, Action.Type.TAKE_DISCARD):
		var discard_hint := Label.new()
		discard_hint.theme_type_variation = "HintLabel"
		discard_hint.text = "or click the discard pile to take the top card"
		prompt_buttons_box.add_child(discard_hint)

	if legal.is_empty() and state.current_player_index != _viewer_index():
		var waiting_hint := Label.new()
		waiting_hint.theme_type_variation = "HintLabel"
		waiting_hint.text = "Waiting for Player %d..." % (state.current_player_index + 1)
		prompt_buttons_box.add_child(waiting_hint)
	elif state.phase == GameState.Phase.PLAY or state.phase == GameState.Phase.HAND_LIMIT:
		var hint2 := Label.new()
		hint2.theme_type_variation = "HintLabel"
		hint2.text = "Select a card from your hand below"
		prompt_buttons_box.add_child(hint2)

# --- action handlers -------------------------------------------------------

func _on_hand_card_clicked(instance_id: int) -> void:
	selected_card_id = -1 if selected_card_id == instance_id else instance_id
	_refresh_play_view()

func _on_cancel_selection_pressed() -> void:
	selected_card_id = -1
	_refresh_play_view()

func _on_draw_pressed() -> void:
	var from := table_surface.get_deck_marker_global_position()
	var to := hand_fan.get_fan_center_global_position()
	CardAnimator.fly(animation_layer, from, to, "", "back", "draw")

	selected_card_id = -1
	var action := Action.make_draw(_viewer_index())
	var line := GameViewModel.describe_action_for_log(state, action)
	_submit_action(action)
	if not is_network_mode:
		_append_log_line(line)

func _on_take_discard_pressed() -> void:
	var legal := session.get_legal_actions()
	if not _has_action_type(legal, Action.Type.TAKE_DISCARD):
		return

	var top: Card = state.discard_pile[state.discard_pile.size() - 1]
	var label := GameViewModel.card_label(top.def_id, top.category, db)
	var cat := CardCategoryMap.category_for(top.def_id, top.category)

	var from := table_surface.get_discard_marker_global_position()
	var to := hand_fan.get_fan_center_global_position()
	CardAnimator.fly(animation_layer, from, to, label, cat, "draw")

	var action := Action.make_take_discard(_viewer_index())
	var line := GameViewModel.describe_action_for_log(state, action)
	selected_card_id = -1
	_submit_action(action)
	if not is_network_mode:
		_append_log_line(line)

func _on_steal_requested(target_player_index: int, target_recipe_index: int, card_instance_id: int) -> void:
	var legal := session.get_legal_actions()
	var action := _find_steal_action(legal, target_player_index, target_recipe_index, card_instance_id)
	if action == null:
		return

	var target: Player = state.players[target_player_index]
	var recipe: Recipe = target.recipes[target_recipe_index]
	var card := recipe.find_attached_card(card_instance_id)
	var label := GameViewModel.card_label(card.def_id, card.category, db) if card != null else ""
	var cat := CardCategoryMap.category_for(card.def_id, card.category) if card != null else CardCategoryMap.PANTRY

	var panel: PlayerPanel = _player_panel_nodes.get(target_player_index)
	var from: Vector2 = (panel.global_position + panel.size * 0.5) if panel != null else get_global_rect().get_center()
	var to := hand_fan.get_fan_center_global_position()
	CardAnimator.fly(animation_layer, from, to, label, cat, "steal")

	var line := GameViewModel.describe_action_for_log(state, action)
	selected_card_id = -1
	_submit_action(action)
	if not is_network_mode:
		_append_log_line(line)

func _on_recipe_target_pressed(recipe_index: int, panel_node: Control) -> void:
	var legal := session.get_legal_actions()
	var action := _find_attach_action(legal, selected_card_id, recipe_index)
	if action == null:
		return

	var player := state.players[_viewer_index()]
	var card := player.find_in_hand(selected_card_id)
	var label := GameViewModel.card_label(card.def_id, card.category, db) if card != null else ""
	var cat := CardCategoryMap.category_for(card.def_id, card.category) if card != null else CardCategoryMap.PANTRY

	var from := hand_fan.get_card_global_position(selected_card_id)
	var to: Vector2 = panel_node.global_position + panel_node.size * 0.5
	CardAnimator.fly(animation_layer, from, to, label, cat, "attach")

	var line := GameViewModel.describe_action_for_log(state, action)
	selected_card_id = -1
	_submit_action(action)
	if not is_network_mode:
		_append_log_line(line)

func _on_discard_pressed(card_instance_id: int) -> void:
	var player := state.players[_viewer_index()]
	var card := player.find_in_hand(card_instance_id)
	var label := GameViewModel.card_label(card.def_id, card.category, db) if card != null else ""
	var cat := CardCategoryMap.category_for(card.def_id, card.category) if card != null else CardCategoryMap.PANTRY

	var from := hand_fan.get_card_global_position(card_instance_id)
	var to := table_surface.get_discard_marker_global_position()
	CardAnimator.fly(animation_layer, from, to, label, cat, "discard")

	var action := Action.make_discard(_viewer_index(), card_instance_id)
	var line := GameViewModel.describe_action_for_log(state, action)
	selected_card_id = -1
	_submit_action(action)
	if not is_network_mode:
		_append_log_line(line)

# ===========================================================================
# Game over screen
# ===========================================================================

func _show_game_over() -> void:
	ui_mode = UiMode.GAME_OVER
	_clear_children(gameover_overlay)
	var box := _overlay_content_box(gameover_overlay)

	var headline := Label.new()
	headline.theme_type_variation = "TitleLabel"
	headline.text = GameViewModel.status_text(state, [])
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(headline)

	var new_game_button := Button.new()
	new_game_button.theme_type_variation = "PrimaryButton"
	new_game_button.text = "New game"
	new_game_button.custom_minimum_size = Vector2(220, 0)
	new_game_button.pressed.connect(_on_new_game_pressed)
	box.add_child(new_game_button)

	_apply_overlay_visibility()

func _on_new_game_pressed() -> void:
	if is_network_mode:
		_network_peer().shutdown()
		is_network_mode = false
	_show_setup()

# ===========================================================================
# Legal-action lookups (pure search over get_legal_actions() output --
# not a rule decision, just finding which already-legal action matches a
# clicked element)
# ===========================================================================

func _has_action_type(legal: Array, type: int) -> bool:
	for a in legal:
		if a.type == type:
			return true
	return false

func _find_attach_action(legal: Array, card_instance_id: int, recipe_index: int) -> Action:
	for a in legal:
		if a.type == Action.Type.ATTACH and a.card_instance_id == card_instance_id and a.recipe_index == recipe_index:
			return a
	return null

func _find_discard_action(legal: Array, card_instance_id: int) -> Action:
	for a in legal:
		if a.type == Action.Type.DISCARD and a.card_instance_id == card_instance_id:
			return a
	return null

func _find_steal_action(legal: Array, target_player_index: int, target_recipe_index: int, card_instance_id: int) -> Action:
	for a in legal:
		if a.type == Action.Type.STEAL and a.target_player_index == target_player_index and a.target_recipe_index == target_recipe_index and a.card_instance_id == card_instance_id:
			return a
	return null

func _find_draft_keep_action(legal: Array, recipe_id: String) -> Action:
	for a in legal:
		if a.type == Action.Type.DRAFT_KEEP and a.recipe_id == recipe_id:
			return a
	return null

# ===========================================================================
# Overlay visibility
# ===========================================================================

func _apply_overlay_visibility() -> void:
	setup_overlay.visible = ui_mode == UiMode.SETUP
	network_setup_overlay.visible = ui_mode == UiMode.NETWORK_SETUP
	lobby_overlay.visible = ui_mode == UiMode.LOBBY
	pass_overlay.visible = ui_mode == UiMode.PASS_DEVICE
	draft_overlay.visible = ui_mode == UiMode.DRAFT
	ai_thinking_overlay.visible = ui_mode == UiMode.AI_THINKING
	gameover_overlay.visible = ui_mode == UiMode.GAME_OVER
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE if ui_mode == UiMode.PLAY else Control.MOUSE_FILTER_STOP
	main_layout.visible = ui_mode == UiMode.PLAY

func _clear_children(node: Node) -> void:
	# queue_free(), not free(): this is routinely called while rebuilding
	# the UI in response to a signal from one of these very children (e.g.
	# a button's own "pressed" handler triggering a re-render), and
	# free()-ing a node that's still "locked" processing its own signal
	# raises "Attempted to free a locked object". queue_free() defers
	# deletion to the end of the frame, after the current call stack (and
	# the signal it came from) has fully unwound.
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

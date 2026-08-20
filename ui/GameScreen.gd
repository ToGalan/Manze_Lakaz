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

enum UiMode { MAIN_MENU, HOW_TO_PLAY, SETTINGS, STORY, SETUP, NETWORK_SETUP, LOBBY, PASS_DEVICE, DRAFT, PLAY, AI_THINKING, RECIPE_REVEAL, GAME_OVER, RECONNECTING }

## Background art per menu-style screen (see MenuBackground) -- each blank
## for now, so every one of them renders the same placeholder gradient
## until real art lands and these get pointed at it.
const MAIN_MENU_BG_PATH := "" # e.g. "res://ui/art/menu/main_menu_bg.png"
const STORY_BG_PATH := "" # e.g. "res://ui/art/menu/story_bg.png"
const SETUP_BG_PATH := "" # e.g. "res://ui/art/menu/setup_bg.png"

# Reconnection budget: total time a disconnected client keeps retrying
# before giving up and returning to the menu, vs. how long a single
# join_session() + request_rejoin() attempt is allowed to hang before it's
# abandoned in favor of a fresh one. The per-attempt figure is set above
# the addon's own worst-case single-peer signaling budget (see
# manze_lakaz_tube_context.tres' peer_signaling_timeout *
# peer_signaling_max_attempts = 4.0 * 5 = 20s) so a legitimately slow-but-
# succeeding negotiation isn't cut off by our own retry logic before Tube
# itself would have given up.
const RECONNECT_TOTAL_TIMEOUT_SECONDS := 60.0
const RECONNECT_ATTEMPT_TIMEOUT_SECONDS := 25.0
const RECONNECT_BACKOFF_START_SECONDS := 1.0
const RECONNECT_BACKOFF_MAX_SECONDS := 8.0

## How long a first-time join waits for the host to actually confirm
## (seat_assigned) after request_join() before retrying/giving up -- see
## _confirm_initial_join(). Short relative to the reconnect budget above:
## this is the very first RPC on a brand new transport, not recovering a
## session that was already known-good a moment ago, so there's no reason
## to make a player who typed a bad/expired code sit and wait as long.
const JOIN_CONFIRM_TIMEOUT_SECONDS := 8.0
const JOIN_CONFIRM_ATTEMPTS := 2

## How to Play, paginated one topic per card -- see _show_how_to_play().
const HOW_TO_PLAY_PAGES := [
	{"heading": "The Goal", "body": "Be the first to complete a recipe: fill every ingredient and preparation slot it needs. A dish that uses a grill fills that slot for free once everything else is in place."},
	{"heading": "Drafting", "body": "At the start of the game you're offered a few recipes and keep some of them, these are the dishes you'll spend the game trying to complete."},
	{"heading": "Your Turn", "body": "Each turn has two steps. First, take a card: draw from the deck, take the top of the discard pile, or steal an ingredient card off an opponent's incomplete recipe (a limited number of times per game). Then, play a card: attach a card to one of your recipes, move a preparation between your own recipes, or discard."},
	{"heading": "Ingredients vs. Preparations", "body": "Ingredient cards attached to an incomplete recipe can be stolen by an opponent. Preparation cards, once attached, are safe, they can never be stolen."},
	{"heading": "Joker Cards", "body": "A Protein, Vegetable, or Pantry joker can fill any open ingredient slot of its matching category instead of one specific ingredient. Like preparations, a joker is safe from stealing once it's attached."},
	{"heading": "Winning", "body": "Complete a recipe first and you win, unless team mode is on, in which case your whole team needs to finish before anyone wins."},
]

## The backstory, shown once between the main menu's Play button and game
## setup -- paginated the same way as HOW_TO_PLAY_PAGES, see _show_story().
const STORY_PAGES := [
	{"heading": "Home for the Holidays", "body": "The whole family has piled into Grandma's old kitchen for the first reunion in years. Cousins you haven't seen since you were kids are swapping hugs, stories, and not-so-subtle jabs about who Grandma always liked best."},
	{"heading": "The Recipe Box", "body": "Tucked in a drawer, right where it's always been, is Grandma's battered recipe box, dishes she carried from every corner of the family's history, from island grills to slow-simmered stews. She never wrote down exactly how she made them. She just knew."},
	{"heading": "The Challenge", "body": "Someone (you'll never admit it was you) says it out loud: whoever gathers the right ingredients and recreates Grandma's dishes first proves, once and for all, who's really her favorite grandchild. The rest of the table lights up. This is happening."},
	{"heading": "Let's Cook", "body": "Ingredients are scattered across the table, everyone's reaching for the same spice jar at once, and there's no going easy on your cousins. Pick your recipes, grab what you need before someone else does, and cook like your reputation depends on it, because apparently, it does."},
]

var db: CardDatabase
var session: GameSession
var state: GameState # a cached read of session.get_state(), refreshed every _advance_ui_after_state_change()
var is_network_mode: bool = false
var is_network_host: bool = false # true only while THIS device is the one hosting the current session
var _reconnecting: bool = false # guards against re-entering the retry loop, and tells _on_join_rejected to defer to it
var ui_mode: int = UiMode.MAIN_MENU
var selected_card_id: int = -1
var selected_move_prep_id: int = -1 # instance id of an attached preparation card picked up for MOVE_PREPARATION; mutually exclusive with selected_card_id
var _pending_joker_choices: Array[Action] = [] # ambiguous ATTACH choices (a joker matching >1 open slot on the just-clicked recipe) awaiting the player's pick
var log_collapsed: bool = true
var _dealt_seen: Dictionary = {} # player_index -> true, once their first hand reveal has played
var _player_panel_nodes: Dictionary = {} # player_index -> PlayerPanel, for the current render
var _own_recipe_panel_nodes: Dictionary = {} # recipe_index -> Control, for the current render
var _shown_recipe_completions: Dictionary = {} # "player_index:recipe_index" -> true
var _pending_recipe_reveal: Dictionary = {} # {player_index, recipe_index}, while ui_mode == RECIPE_REVEAL
var _player_card_page: Dictionary = {} # "player_index:recipe_index" -> int, an opponent recipe row's current page once it needs pagination (see PlayerPanel.CARDS_PER_PAGE)

# Hot-seat setup (player count + per-seat Human/AI + turn timer).
## AI turns still pace themselves visibly rather than resolving instantly
## (see _run_ai_step()), but this is no longer a setup-screen option --
## just a fixed, reasonable default now that the option slot is Turn Timer.
const AI_THINK_TIME_SECONDS := 1.0
var _pending_num_players: int = 4
var _pending_seat_mode: Dictionary = {} # player_index -> -1 (Human) or AiBot.Difficulty
## How long a human player has to act in hot-seat before a fallback bot
## plays out the rest of their turn for them, same idea as online's per-seat
## turn timer (ServerAuthority) but purely local -- see
## _advance_ui_after_state_change()'s arming of _hotseat_turn_timer_token
## and _on_hotseat_turn_timer_expired().
var hotseat_turn_timer_enabled: bool = true
var hotseat_turn_timer_seconds: float = 60.0
var _hotseat_turn_timer_token: int = 0
## Wall-clock deadline (Time.get_ticks_msec()) for the countdown shown by
## turn_timer_badge, or -1 while no countdown is running. Shared between
## hot-seat and network mode -- hot-seat also schedules a real
## SceneTreeTimer alongside it to actually act on timeout (see
## _arm_hotseat_turn_timer()), but network mode only ever sets this for
## display: the server (ServerAuthority) already owns the real timer and
## its auto-play fallback there, so the client has nothing to schedule,
## just a number to show (see _arm_network_turn_timer_display()).
var _turn_timer_deadline_msec: int = -1

# Online setup + lobby.
var _pending_is_host: bool = true
var _pending_display_name: String = "Player"
var _pending_join_session_id: String = ""
var _pending_turn_timer_seconds: float = 30.0
var _pending_auto_play_difficulty: int = AiBot.Difficulty.EASY
var _pending_fill_ai: bool = true
var _pending_ai_fill_difficulty: int = AiBot.Difficulty.MEDIUM
var lobby_seats: Array = []
var my_session_id: String = "" # this device's current session id, host or client; only shown in the lobby (as a shareable code) when is_network_host -- see _show_lobby()
var network_status_label: Label # rebuilt each time _show_network_setup() runs; updated from async connection signals
var _setup_info_message: String = "" # one-shot banner shown on the next _show_setup(), e.g. "the host ended the session"
var _leaving_intentionally: bool = false # set right before OUR OWN shutdown() calls, so the global session_ended handler doesn't also treat it as "the host ended it out from under us"
var leave_game_button: Button # persistent, visible only mid-game in network mode; the only way to leave once play has started
var turn_timer_badge: PanelContainer # persistent, bottom-right; visible only while a hot-seat turn countdown is actually running
var turn_timer_label: Label

## One clip per Action.Type, played once from _submit_action() -- no
## randomized variety, just a single consistent cue per action so it stays
## recognizable. Only ever fires for THIS device's own locally-submitted
## actions (hot-seat covers both players since they share one device;
## online only plays for the acting client, not for opponents watching a
## snapshot arrive -- there's no typed "an action just happened" signal
## broadcast to observers to hook, only the log line's text). DRAFT_KEEP and
## DRAW are deliberately absent -- see DRAFT_KEEP_SFX/DRAW_SFX below, each
## capped to its own short max playback length.
const ACTION_SFX := {
	Action.Type.STEAL: preload("res://sfx/448995__qubodup__yoink-stealing-sound-effect.wav"), # Godot can't import the source .flac directly; converted to .wav once, see the file alongside it
	Action.Type.ATTACH: preload("res://sfx/740218__simeonradivoev__sci-fi-robotic-attachment.mp3"),
	Action.Type.DISCARD: preload("res://sfx/zapsplat_leisure_trading_or_playing_card_shuffle_002_77303.mp3"),
	Action.Type.TAKE_DISCARD: preload("res://sfx/zapsplat_leisure_trading_card_or_playing_card_shuffle_turn_over_single_001_68322.mp3"),
}

const DRAW_SFX := preload("res://sfx/423769__someonecool15__playing-cards-being-delt.mp3")
const DRAW_SFX_MAX_SECONDS := 2.0

## A single "shuffling the deck" cue for the whole draft, not one per pick
## (recipes_per_player picks, times every player) -- played on the first
## DRAFT_KEEP of a new game only.
const DRAFT_KEEP_SFX := preload("res://sfx/zapsplat_leisure_playing_cards_flick_through_shuffle_007_62510.mp3")
const DRAFT_KEEP_SFX_MAX_SECONDS := 4.0
var _draft_keep_sfx_played: bool = false

## "Dealing everyone their recipe offers" -- played once when the draft
## screen is first shown for a new game (see _show_draft()), not tied to
## MOVE_PREPARATION at all despite the clip's filename.
const DRAFT_BEGIN_SFX := preload("res://sfx/747805__hope_sounds_3__countingplayingcards.wav")
var _draft_begin_sfx_played: bool = false

## A small round-robin pool, not one shared player: one-shot sfx
## previously all funneled through a single AudioStreamPlayer, so any new
## sound truncated whatever was still playing -- most noticeably the steal
## "yoink" getting chopped mid-sample by the very next action's sound
## during a fast bot-driven turn. See _play_sfx() for the selection logic
## (prefer an idle player; only reuse a busy one, round-robin, once every
## member is occupied) and _sfx_pool_tokens (the per-player version of the
## old single _sfx_play_token guard).
const SFX_POOL_SIZE := 4
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_tokens: Array[int] = [] # per pool index -- invalidates a pending max-duration auto-stop once a *different* sound has since taken over that specific player (see _play_sfx())
var _sfx_pool_next_index: int = 0 # round-robin cursor, only advanced when every player is already busy and one has to be reused

## Only the last TURN_TIMER_WARNING_SECONDS of this clip are ever heard --
## see the countdown-crossing check in _process() -- so it plays as a
## single ticking/ringing alarm that builds tension right up to 0, once per
## turn (guarded by _timer_warning_played), instead of the whole ~87s file
## dumped out in full the moment a turn actually expires.
const TURN_TIMER_WARNING_SFX := preload("res://sfx/47838__delphidebrain__delphis-double-egg-timer.wav")
const TURN_TIMER_WARNING_SECONDS := 10.0
var _timer_warning_played: bool = false
var timer_warning_player: AudioStreamPlayer

## Played once from _on_start_pressed() (hot-seat) or the first snapshot a
## network client ever receives (see _advance_ui_after_state_change()) --
## "lighting the stove" to mark a brand new game actually starting, not
## just returning to a game already in progress (a reconnect never calls
## _connect_session() again, so _game_start_sfx_played stays true and this
## correctly never replays for one).
const GAME_START_SFX := preload("res://sfx/740091__fossarts__turning-on-gas-stove-1.wav")
var _game_start_sfx_played: bool = false

## Plays continuously from the first main-menu button press onward (see
## _unlock_audio()), through every screen after that -- there's only one
## track, so nothing has to pick when to start/stop/switch it. Never
## started from _ready()/_build_static_ui() directly: a browser's autoplay
## policy blocks the AudioContext until a real user gesture, and calling
## play() before one is issued is silently dropped rather than deferred,
## which is exactly the "no sound until the page is refreshed" bug this
## unlock step exists to avoid on the web export.
const MUSIC_STREAM: AudioStreamWAV = preload("res://sfx/595860__szegvari__africa-safari-love-world-ethnic-modern-soundtrack-music-drum-flute-piano-snare-contemporary-eq-mastered_BG.wav")
var music_player: AudioStreamPlayer

## Set once a real user gesture has resumed the browser's AudioContext (or
## immediately, on a native build where no such restriction exists) -- see
## _unlock_audio(). Every actual playback call in this file (music, sfx,
## the timer warning, the prep ambience) is gated behind this, since
## attempting to play into a still-suspended AudioContext is silently
## dropped, not queued. Never reset once true -- _connect_session() runs
## again for every new game/session, same as _game_start_sfx_played and
## friends, but audio being unlocked is a browser-tab-lifetime fact, not a
## per-game one.
var _audio_unlocked: bool = false
var _audio_unlock_in_progress: bool = false # re-entrancy guard while a web resume is still being polled

## Layered on top of the main track (which ducks by MUSIC_DUCK_VOLUME_DB)
## the first time ANY player's recipe has a preparation card attached --
## driven by game state (see _check_prep_ambience()), not by this device's
## own submitted actions, so it starts the same way for every player at the
## table regardless of who actually cooked first. Loops for the rest of
## the game; _connect_session() resets it for a new one.
const FRYING_AMBIENCE_SFX: AudioStreamWAV = preload("res://sfx/426870__katfolker__frying-food.wav")
const MUSIC_DUCK_VOLUME_DB := -10.0
var ambience_player: AudioStreamPlayer
var _prep_ambience_started: bool = false

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
var main_menu_overlay: PanelContainer
var how_to_play_overlay: PanelContainer
var _how_to_play_page: int = 0
var settings_overlay: PanelContainer
var story_overlay: PanelContainer
var _story_page: int = 0
var setup_overlay: PanelContainer
var network_setup_overlay: PanelContainer
var lobby_overlay: PanelContainer
var pass_overlay: PanelContainer
var draft_overlay: PanelContainer
var ai_thinking_overlay: PanelContainer
var recipe_reveal_overlay: PanelContainer
var gameover_overlay: PanelContainer
var reconnecting_overlay: PanelContainer
var reconnect_status_label: Label # rebuilt each time _show_reconnecting_overlay() runs; updated in place across retry attempts

func _ready() -> void:
	theme = GameTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	db = DataLoader.load_database_or_fail(
		DATA_DIR + "/ingredients.json",
		DATA_DIR + "/preparations.json",
		DATA_DIR + "/recipes.json"
	)

	_ensure_audio_buses() # must exist before _build_static_ui() creates AudioStreamPlayers routed to them
	_build_static_ui()
	_load_settings()

	# Connected once, persistently: NetworkPeer is an autoload that outlives
	# this scene entirely, so there's never a matching moment to
	# disconnect it, and it must catch session_ended no matter which
	# screen is showing when the host closes the session.
	_network_peer().session_ended.connect(_on_network_session_ended)

	if db == null:
		prompt_label.text = "Data failed to validate, see console output."
		return

	_show_main_menu()

## Ticks the bottom-right countdown badge. Purely display -- the actual
## timeout is still owned by the SceneTreeTimer set up in
## _arm_hotseat_turn_timer() (hot-seat) or ServerAuthority (network); this
## just reads the same deadline every frame so the number on screen stays
## honest without re-deriving anything about whose turn it is.
func _process(_delta: float) -> void:
	if _turn_timer_deadline_msec < 0:
		turn_timer_badge.visible = false
		return
	var remaining_ms: int = _turn_timer_deadline_msec - Time.get_ticks_msec()
	var remaining_seconds: int = maxi(0, ceili(remaining_ms / 1000.0))
	turn_timer_badge.visible = true
	turn_timer_label.text = "Turn ends in %d:%02d" % [remaining_seconds / 60, remaining_seconds % 60]

	if not _timer_warning_played and remaining_ms <= int(TURN_TIMER_WARNING_SECONDS * 1000.0):
		_timer_warning_played = true
		# Marked played either way -- by the time a turn timer can even be
		# running, audio has always already been unlocked via the
		# main-menu click that started the flow (the only real exception,
		# a reconnect that skips the menu entirely, has no later gesture
		# to unlock on anyway, so there's nothing to defer this to).
		if _audio_unlocked:
			timer_warning_player.stream = TURN_TIMER_WARNING_SFX
			timer_warning_player.play(maxf(0.0, TURN_TIMER_WARNING_SFX.get_length() - TURN_TIMER_WARNING_SECONDS))

## Connected to every main-menu button's pressed signal (see
## _show_main_menu()) -- the first one to actually fire is this browser
## tab's one real user gesture, which a web export needs before its
## AudioContext will produce sound at all. Idempotent: a later main-menu
## visit (leaving a game, network disconnect, ...) rebuilds those buttons
## and reconnects this same handler, but _audio_unlocked short-circuits it
## instantly once already true, so nothing about playback gets restarted
## or re-ducked.
func _unlock_audio() -> void:
	if _audio_unlocked or _audio_unlock_in_progress:
		return
	_audio_unlock_in_progress = true
	if OS.has_feature("web"):
		var resumed := await _resume_web_audio_context()
		if not resumed:
			# Stays locked -- the next main-menu button press (there's
			# always another one available; the player hasn't left the
			# menu yet) gets a fresh attempt instead of giving up for the
			# whole session.
			_audio_unlock_in_progress = false
			return
	_audio_unlocked = true
	_audio_unlock_in_progress = false
	music_player.play()
	if _prep_ambience_started:
		_apply_prep_ambience()

## Godot's own web audio driver already listens for a user gesture to
## resume its AudioContext, but that internal resume can race whatever
## play() call this same gesture triggers -- calling play() before the
## resume has actually landed gets silently dropped rather than deferred,
## which is precisely the "plays once, muted, never again until refresh"
## bug this whole unlock step exists to avoid. Explicitly requesting the
## resume and then polling until the context reports "running" (capped so
## a page that genuinely has no audio context, or whose internals changed
## in a future engine version, doesn't hang here forever) means play() is
## only ever called once sound can actually come out.
func _resume_web_audio_context() -> bool:
	var has_context: bool = JavaScriptBridge.eval(
		"typeof GodotAudio !== 'undefined' && !!GodotAudio.ctx", true
	)
	if not has_context:
		push_warning("GameScreen: no GodotAudio.ctx found to resume -- proceeding without an explicit unlock")
		return true

	JavaScriptBridge.eval("if (GodotAudio.ctx.state === 'suspended') { GodotAudio.ctx.resume(); }", true)
	for _attempt in 30:
		var ctx_state: String = JavaScriptBridge.eval("GodotAudio.ctx.state", true)
		if ctx_state == "running":
			return true
		await get_tree().process_frame
	push_warning("GameScreen: AudioContext did not report 'running' after resume -- will retry on the next menu interaction")
	return false

# ===========================================================================
# Static UI construction (built once)
# ===========================================================================

func _build_static_ui() -> void:
	var bg := TextureRect.new()
	bg.texture = preload("res://ui/art/MLtexture_tableWood_16-9.png")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED # a 16:9 source image, fills any window size without seams or distortion
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_pool.append(player)
		_sfx_pool_tokens.append(0)

	timer_warning_player = AudioStreamPlayer.new()
	timer_warning_player.bus = "SFX"
	add_child(timer_warning_player)

	# Setting loop_mode via the .import sidecar (edit/loop_mode) instead of
	# here was tried first, since preload() returns the one shared cached
	# resource instance and mutating it at runtime looks like configuring a
	# local copy while actually changing that instance for every future
	# preload() of it too. Confirmed empirically (a fresh reimport, then a
	# cache-bypassed ResourceLoader.load() of the .wav directly) that this
	# engine version's WAV importer does not actually propagate
	# edit/loop_mode into the imported resource -- it reads back
	# loop_mode=0 regardless of what the .import file says. .duplicate()
	# here gets the same practical safety (this player's own copy, not the
	# shared cache) without depending on that importer behavior.
	var music_stream: AudioStreamWAV = MUSIC_STREAM.duplicate()
	music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.stream = music_stream
	add_child(music_player)
	# Not started here -- see _unlock_audio().

	var ambience_stream: AudioStreamWAV = FRYING_AMBIENCE_SFX.duplicate()
	ambience_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ambience_player = AudioStreamPlayer.new()
	ambience_player.bus = "Music"
	ambience_player.stream = ambience_stream
	add_child(ambience_player)

	# A direct child of this Control, not of main_layout -- floats over
	# the bottom of the screen (the prompt bar included) instead of
	# taking its own reserved row in main_layout's vertical stack, which
	# hands that space back to the table/recipe area above. Added BEFORE
	# outer_margin so the prompt bar (built below, part of outer_margin's
	# content) draws -- and hit-tests -- on top of it wherever the two
	# overlap: the bar's own text and Draw/Discard/Cancel buttons must
	# stay legible and clickable regardless of what the fan is doing, so
	# a card tucks behind the bar there rather than the other way around.
	# mouse_filter = PASS (set in HandFan._init()) still matters for the
	# table/recipe area above, where nothing overlaps it at all -- a click
	# in the empty space around a card there falls through cleanly.
	hand_fan = HandFan.new()
	hand_fan.card_clicked.connect(_on_hand_card_clicked)
	hand_fan.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(hand_fan)

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
	# sits above it. Tall enough for a two-line PromptLabel (18px font) +
	# the button row.
	prompt_panel.custom_minimum_size = Vector2(0, 64)
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

	_build_overlays()

	animation_layer = Control.new()
	animation_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	animation_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(animation_layer)

	# Persistent, top-left; visibility is toggled per-frame in
	# _apply_overlay_visibility() since
	# that's the one choke point every _show_*() screen transition already
	# passes through. This is the ONLY way to leave a network game once
	# play has actually started -- the lobby's own Leave button only
	# exists pre-start.
	leave_game_button = Button.new()
	leave_game_button.theme_type_variation = "SecondaryButton"
	leave_game_button.text = "Leave Game"
	leave_game_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	leave_game_button.position = Vector2(8, 8)
	leave_game_button.size = Vector2(110, 0)
	leave_game_button.visible = false
	leave_game_button.pressed.connect(_on_leave_game_pressed)
	add_child(leave_game_button)

	# Persistent, bottom-right; visibility and text are driven every frame
	# in _process() from _turn_timer_deadline_msec rather than the
	# per-screen _show_*() choke point leave_game_button uses -- a
	# countdown needs to keep ticking every frame while its screen is up,
	# not just refresh once when that screen is entered.
	turn_timer_badge = PanelContainer.new()
	turn_timer_badge.theme_type_variation = "LogPanel"
	turn_timer_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	turn_timer_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	turn_timer_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	turn_timer_badge.offset_left = -108.0
	turn_timer_badge.offset_top = -40.0
	turn_timer_badge.offset_right = -12.0
	turn_timer_badge.offset_bottom = -12.0
	turn_timer_badge.visible = false
	add_child(turn_timer_badge)

	turn_timer_label = Label.new()
	turn_timer_label.theme_type_variation = "BadgeLabel"
	turn_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_timer_badge.add_child(turn_timer_label)

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
	# hand_fan floats over the bottom of the screen (see _build_static_ui())
	# rather than taking its own row in main_layout, so this is a plain
	# Control outside any Container -- custom_minimum_size means nothing to
	# it here, its actual rect comes from these offsets against its
	# PRESET_BOTTOM_WIDE anchors. 12px matches outer_margin's own margin
	# (see GameTheme's base MarginContainer variation) so the fan's card
	# row lines up with everything else's left/right/bottom edges instead
	# of running flush to the true screen edge. Full width, no reserved
	# gap for prompt_row's buttons -- unlike a card, the bar draws (and
	# hit-tests) on top of hand_fan wherever they overlap, see
	# _build_static_ui(), so there's nothing for a card to block there.
	# Cards ~1.5x bigger than the original 90-190 clamp in HandFan.gd:
	# floor, ceiling, and multiplier all scaled up (110-160 -> 165-240). A
	# first attempt only raised the ceiling, to avoid an oversized recipe
	# panel spilling past the table -- but that meant a 1280x720 window
	# (this project's own default size) landed exactly on the untouched
	# floor, with no visible growth at all. Safe to scale uniformly now
	# that the tallest recipe's slot grid scrolls instead of overflowing
	# once it doesn't fit (see the ScrollContainer in
	# _build_own_recipe_panel()) -- and safer still now that hand_fan no
	# longer competes with the table for main_layout's own height at all,
	# floating over the prompt bar instead.
	var hand_fan_height := clampf(size.y * 0.27, 165.0, 240.0)
	hand_fan.offset_left = 12.0
	hand_fan.offset_right = -12.0
	hand_fan.offset_top = -hand_fan_height
	hand_fan.offset_bottom = -12.0
	prompt_panel.custom_minimum_size.y = clampf(size.y * 0.09, 48.0, 64.0)
	log_panel.custom_minimum_size.x = clampf(size.x * 0.22, 160.0, 320.0)

func _build_overlays() -> void:
	overlay_layer = Control.new()
	overlay_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_layer)

	main_menu_overlay = _make_overlay_panel()
	main_menu_overlay.theme_type_variation = "ClearOverlay" # lets MenuBackground show through -- see _show_main_menu()
	how_to_play_overlay = _make_overlay_panel()
	settings_overlay = _make_overlay_panel()
	story_overlay = _make_overlay_panel()
	story_overlay.theme_type_variation = "ClearOverlay" # lets MenuBackground show through -- see _show_story()
	setup_overlay = _make_overlay_panel()
	setup_overlay.theme_type_variation = "ClearOverlay" # lets MenuBackground show through -- see _show_setup()
	network_setup_overlay = _make_overlay_panel()
	lobby_overlay = _make_overlay_panel()
	pass_overlay = _make_overlay_panel()
	draft_overlay = _make_overlay_panel()
	ai_thinking_overlay = _make_overlay_panel()
	recipe_reveal_overlay = _make_overlay_panel()
	gameover_overlay = _make_overlay_panel()
	reconnecting_overlay = _make_overlay_panel()

func _make_overlay_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "OverlayBackdrop"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	overlay_layer.add_child(panel)
	return panel

## ScrollContainer -> themed card panel -> VBox, ready for overlay content.
## A ScrollContainer, not a bare CenterContainer, for the same reason as
## TableSurface's recipe row USED to need one: a setup screen with 4
## per-seat difficulty pickers, a network host/join form, or a long draft
## offer list can end up taller (or wider) than a short/narrow viewport,
## and CenterContainer never clips or scrolls -- it silently overflows
## past the screen edge.
##
## scrollable = false opts out for a specific screen that would rather stay
## non-scrolling and just size the card to its real content (Settings,
## the recipe reveal) -- same tradeoff TableSurface already made for the
## board: it's on that screen to actually fit (e.g. widen its own content)
## instead of relying on scroll as a safety net.
func _overlay_content_box(overlay: PanelContainer, scrollable: bool = true) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(margin)

	var card_parent: Container = margin
	if scrollable:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		margin.add_child(scroll)

		# ScrollContainer never hands its child more than the child's own
		# minimum size -- unlike every other Container, it does NOT give a
		# smaller child the rest of its available space, so neither
		# size_flags=SHRINK_CENTER nor a plain nested CenterContainer
		# actually centers anything here; the extra space is just left
		# empty at the bottom-right while content sits pinned at the
		# top-left. The real fix: force the CenterContainer's own minimum
		# size to match the scroll view, kept in sync across resizes, so
		# it fills that view and genuinely centers its child -- and once
		# real content outgrows that floor, the CenterContainer's minimum
		# grows past it and scrolling takes over exactly as before.
		var scroll_center := CenterContainer.new()
		scroll.add_child(scroll_center)
		_sync_overlay_center(scroll, scroll_center)
		scroll.resized.connect(_sync_overlay_center.bind(scroll, scroll_center))
		card_parent = scroll_center
	else:
		# No ScrollContainer to fight with -- a plain CenterContainer
		# already centers a smaller child within whatever margin gives it,
		# same as TableSurface's board.
		var center := CenterContainer.new()
		margin.add_child(center)
		card_parent = center

	var card := PanelContainer.new()
	card.theme_type_variation = "OverlayCard"
	card_parent.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.theme_type_variation = "WideVBox"
	card.add_child(vbox)

	return vbox

func _sync_overlay_center(scroll: ScrollContainer, center: CenterContainer) -> void:
	center.custom_minimum_size = scroll.size

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
		if session.log_line_received.is_connected(_append_log_line):
			session.log_line_received.disconnect(_append_log_line)
	session = new_session
	session.state_changed.connect(_on_session_state_changed)
	session.log_line_received.connect(_append_log_line)
	_game_start_sfx_played = false
	_draft_keep_sfx_played = false
	_draft_begin_sfx_played = false
	_prep_ambience_started = false
	ambience_player.stop()
	music_player.volume_db = 0.0

func _on_session_state_changed() -> void:
	_advance_ui_after_state_change()

func _submit_action(action: Action) -> void:
	match action.type:
		Action.Type.DRAFT_KEEP:
			if not _draft_keep_sfx_played:
				_draft_keep_sfx_played = true
				_play_sfx(DRAFT_KEEP_SFX, DRAFT_KEEP_SFX_MAX_SECONDS)
		Action.Type.DRAW:
			_play_sfx(DRAW_SFX, DRAW_SFX_MAX_SECONDS)
		_:
			_play_sfx(ACTION_SFX.get(action.type))
	session.submit_action(action)

## Skips a retrigger while the exact same clip is already playing on any
## pool member, so a rapid repeat of the same cue (e.g. an online click
## landing again before the server's confirming snapshot disables the
## button) can't sound like it fired twice or stack into a phasing mess. A
## genuinely different cue always gets a player -- an idle one if any pool
## member has one free, otherwise the least-recently-reused busy one
## (round-robin), so it interrupts as narrowly as possible instead of
## always stealing the same slot. This is the actual fix for the steal
## "yoink" getting chopped mid-sample by the next action's sound during a
## fast bot-driven turn -- with SFX_POOL_SIZE >= 2 concurrent sounds, both
## get their own player and neither truncates the other.
##
## max_seconds, if given, cuts the clip short instead of letting it play to
## its natural end -- e.g. a shuffle/deal sound that's really just meant as
## a quick flourish, not the whole source file. Guarded by
## _sfx_pool_tokens[index], the per-player version of what used to be one
## shared _sfx_play_token: a cutoff timer is bound to the specific pool
## slot it was scheduled for, so it can only ever stop the playback it was
## created for, never a different sound that reused (or moved on from)
## that same slot in the meantime.
##
## Skipped outright (not queued for later) before _audio_unlocked -- see
## _unlock_audio() -- since play() into a still-suspended browser
## AudioContext is silently dropped anyway; a fired-but-lost cue would be
## indistinguishable from a real bug.
func _play_sfx(stream: AudioStream, max_seconds: float = 0.0) -> void:
	if stream == null or not _audio_unlocked:
		return
	for player in _sfx_pool:
		if player.playing and player.stream == stream:
			return

	var index := -1
	for i in _sfx_pool.size():
		if not _sfx_pool[i].playing:
			index = i
			break
	if index == -1:
		index = _sfx_pool_next_index
		_sfx_pool_next_index = (_sfx_pool_next_index + 1) % _sfx_pool.size()

	var player: AudioStreamPlayer = _sfx_pool[index]
	player.stream = stream
	player.play()
	_sfx_pool_tokens[index] += 1
	if max_seconds > 0.0:
		var token: int = _sfx_pool_tokens[index]
		get_tree().create_timer(max_seconds).timeout.connect(func():
			if _sfx_pool_tokens[index] == token:
				player.stop()
		)

## Attached cards (preparations included) are always public information --
## the whole steal mechanic depends on every player seeing what's attached
## to every recipe -- so this is safe to check directly off state.players
## even for a network client's own shadow state, not just the local hand.
##
## Recording the condition (_prep_ambience_started) and actually starting
## the audio for it (_apply_prep_ambience()) are deliberately separate:
## this can be reached before _audio_unlocked (a reconnect that lands
## straight into an already-cooking game, skipping the main menu's unlock
## click entirely) and the fact still needs recording even though nothing
## can play yet -- _unlock_audio() re-applies it once unlocked.
func _check_prep_ambience() -> void:
	if _prep_ambience_started:
		return
	for p in state.players:
		for recipe in p.recipes:
			if not recipe.filled_preparations.is_empty():
				_prep_ambience_started = true
				_apply_prep_ambience()
				return

func _apply_prep_ambience() -> void:
	if not _audio_unlocked:
		return
	music_player.volume_db = MUSIC_DUCK_VOLUME_DB
	ambience_player.play()

func _viewer_index() -> int:
	return session.viewer_index()

# ===========================================================================
# Main menu (the very first screen) and How to Play
# ===========================================================================

## Deliberately NOT built on _overlay_content_box()'s centered-card pattern:
## the title sits pinned to the top and the buttons to the left, so the
## middle of the screen stays clear for MenuBackground to actually show.
## main_menu_overlay is a plain Control (main_menu_overlay itself is
## "ClearOverlay", not "OverlayBackdrop" -- see _build_overlays()) with the
## background as one full-rect child and this content as a second,
## unconstrained full-rect child on top of it; a Control (unlike a
## Container) leaves its own children free to position themselves via
## their own anchors instead of forcing every child to the same rect.
func _show_main_menu() -> void:
	ui_mode = UiMode.MAIN_MENU
	_invalidate_hotseat_turn_timer() # in case we got here mid-turn (e.g. leaving a game), not through _advance_ui_after_state_change()
	_clear_children(main_menu_overlay)

	var bg := MenuBackground.new(MAIN_MENU_BG_PATH)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_menu_overlay.add_child(bg)

	var content_root := Control.new()
	content_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_menu_overlay.add_child(content_root)

	var top_band := VBoxContainer.new()
	top_band.theme_type_variation = "TightVBox"
	top_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_band.custom_minimum_size = Vector2(0, 120) # floor: real height even though a zero-height top anchor would otherwise collapse it
	top_band.position.y = 32
	content_root.add_child(top_band)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Manze Lakaz"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_band.add_child(title)

	var subtitle := Label.new()
	subtitle.theme_type_variation = "HintLabel"
	subtitle.text = "A home-cooking card game, draft a dish, gather what it needs, and finish it before anyone else."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_band.add_child(subtitle)

	var button_col := VBoxContainer.new()
	button_col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	# Control's own grow_horizontal default (GROW_DIRECTION_END) already
	# grows rightward/inward from a left-side anchor, which is what we want
	# here -- unlike the right-anchored version of this column, which
	# needed grow_horizontal overridden to BEGIN so it grew inward
	# (leftward) instead of further off the right edge of the screen.
	button_col.offset_left = 64.0
	button_col.mouse_filter = Control.MOUSE_FILTER_STOP
	content_root.add_child(button_col)

	var play_btn := Button.new()
	play_btn.theme_type_variation = "PrimaryButton"
	play_btn.text = "Play"
	play_btn.custom_minimum_size = Vector2(240, 0)
	play_btn.pressed.connect(_on_play_menu_pressed)
	play_btn.pressed.connect(_unlock_audio) # see _unlock_audio() -- every button here does this, Play is just the most common first click
	button_col.add_child(play_btn)

	var how_to_play_btn := Button.new()
	how_to_play_btn.theme_type_variation = "SecondaryButton"
	how_to_play_btn.text = "How to Play"
	how_to_play_btn.custom_minimum_size = Vector2(240, 0)
	how_to_play_btn.pressed.connect(_on_how_to_play_menu_pressed)
	how_to_play_btn.pressed.connect(_unlock_audio)
	button_col.add_child(how_to_play_btn)

	var settings_btn := Button.new()
	settings_btn.theme_type_variation = "SecondaryButton"
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(240, 0)
	settings_btn.pressed.connect(_show_settings)
	settings_btn.pressed.connect(_unlock_audio)
	button_col.add_child(settings_btn)

	# Quitting a browser tab from inside the page isn't a real/friendly
	# action (get_tree().quit() on web just no-ops or errors depending on
	# platform) -- the button only makes sense for a native build.
	if not OS.has_feature("web"):
		var quit_btn := Button.new()
		quit_btn.theme_type_variation = "SecondaryButton"
		quit_btn.text = "Quit"
		quit_btn.custom_minimum_size = Vector2(240, 0)
		quit_btn.pressed.connect(func(): get_tree().quit())
		button_col.add_child(quit_btn)

	_apply_overlay_visibility()

func _on_how_to_play_menu_pressed() -> void:
	_how_to_play_page = 0
	_show_how_to_play()

## One topic per screen, paged with Prev/Next -- no scroll. Rebuilding the
## whole overlay on every page turn (rather than swapping just the card's
## content) matches how every other screen here reacts to state changes,
## and it's cheap: this is a handful of Labels and Buttons, not a game board.
func _show_how_to_play() -> void:
	ui_mode = UiMode.HOW_TO_PLAY
	_clear_children(how_to_play_overlay)
	var box := _overlay_content_box(how_to_play_overlay, false)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "How to Play"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_how_to_play_page = clampi(_how_to_play_page, 0, HOW_TO_PLAY_PAGES.size() - 1)
	var page: Dictionary = HOW_TO_PLAY_PAGES[_how_to_play_page]

	var page_body := VBoxContainer.new()
	page_body.theme_type_variation = "WideVBox"
	page_body.custom_minimum_size = Vector2(560, 220)
	box.add_child(page_body)

	var heading_label := Label.new()
	heading_label.theme_type_variation = "SectionLabel"
	heading_label.text = page["heading"]
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_body.add_child(heading_label)

	var body_label := Label.new()
	body_label.theme_type_variation = "HintLabel"
	body_label.text = page["body"]
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.custom_minimum_size = Vector2(560, 0)
	page_body.add_child(body_label)

	var nav_row := HBoxContainer.new()
	nav_row.theme_type_variation = "WideHBox"
	nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(nav_row)

	var prev_btn := Button.new()
	prev_btn.theme_type_variation = "SecondaryButton"
	prev_btn.text = "< Prev"
	prev_btn.custom_minimum_size = Vector2(140, 0)
	prev_btn.disabled = _how_to_play_page == 0
	prev_btn.pressed.connect(_on_how_to_play_prev_pressed)
	nav_row.add_child(prev_btn)

	var page_label := Label.new()
	page_label.theme_type_variation = "HintLabel"
	page_label.text = "%d / %d" % [_how_to_play_page + 1, HOW_TO_PLAY_PAGES.size()]
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page_label.custom_minimum_size = Vector2(80, 0)
	nav_row.add_child(page_label)

	var next_btn := Button.new()
	next_btn.theme_type_variation = "SecondaryButton"
	next_btn.text = "Next >"
	next_btn.custom_minimum_size = Vector2(140, 0)
	next_btn.disabled = _how_to_play_page == HOW_TO_PLAY_PAGES.size() - 1
	next_btn.pressed.connect(_on_how_to_play_next_pressed)
	nav_row.add_child(next_btn)

	var back_btn := Button.new()
	back_btn.theme_type_variation = "SecondaryButton"
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(220, 0)
	back_btn.pressed.connect(_show_main_menu)
	box.add_child(back_btn)

	_apply_overlay_visibility()

func _on_how_to_play_prev_pressed() -> void:
	_how_to_play_page -= 1
	_show_how_to_play()

func _on_how_to_play_next_pressed() -> void:
	_how_to_play_page += 1
	_show_how_to_play()

func _on_play_menu_pressed() -> void:
	_story_page = 0
	_show_story()

## The backstory, shown once between the main menu and setup -- same
## paginated-card pattern as _show_how_to_play(), except Next on the final
## page reads "Let's Cook" and moves straight on to _show_setup() instead
## of disabling, and Skip lets an impatient player (or a replaying one)
## jump straight there from any page.
func _show_story() -> void:
	ui_mode = UiMode.STORY
	_clear_children(story_overlay)

	var bg := MenuBackground.new(STORY_BG_PATH)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	story_overlay.add_child(bg)

	var box := _overlay_content_box(story_overlay, false)

	_story_page = clampi(_story_page, 0, STORY_PAGES.size() - 1)
	var page: Dictionary = STORY_PAGES[_story_page]
	var is_last_page := _story_page == STORY_PAGES.size() - 1

	var page_body := VBoxContainer.new()
	page_body.theme_type_variation = "WideVBox"
	page_body.custom_minimum_size = Vector2(560, 220)
	box.add_child(page_body)

	var heading_label := Label.new()
	heading_label.theme_type_variation = "SectionLabel"
	heading_label.text = page["heading"]
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_body.add_child(heading_label)

	var body_label := Label.new()
	body_label.theme_type_variation = "HintLabel"
	body_label.text = page["body"]
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.custom_minimum_size = Vector2(560, 0)
	page_body.add_child(body_label)

	var nav_row := HBoxContainer.new()
	nav_row.theme_type_variation = "WideHBox"
	nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(nav_row)

	var prev_btn := Button.new()
	prev_btn.theme_type_variation = "SecondaryButton"
	prev_btn.text = "< Prev"
	prev_btn.custom_minimum_size = Vector2(140, 0)
	prev_btn.disabled = _story_page == 0
	prev_btn.pressed.connect(_on_story_prev_pressed)
	nav_row.add_child(prev_btn)

	var page_label := Label.new()
	page_label.theme_type_variation = "HintLabel"
	page_label.text = "%d / %d" % [_story_page + 1, STORY_PAGES.size()]
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page_label.custom_minimum_size = Vector2(80, 0)
	nav_row.add_child(page_label)

	var next_btn := Button.new()
	next_btn.theme_type_variation = "PrimaryButton" if is_last_page else "SecondaryButton"
	next_btn.text = "Let's Cook >" if is_last_page else "Next >"
	next_btn.custom_minimum_size = Vector2(140, 0)
	next_btn.pressed.connect(_on_story_next_pressed)
	nav_row.add_child(next_btn)

	var bottom_row := HBoxContainer.new()
	bottom_row.theme_type_variation = "WideHBox"
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bottom_row)

	var back_btn := Button.new()
	back_btn.theme_type_variation = "SecondaryButton"
	back_btn.text = "< Main Menu"
	back_btn.pressed.connect(_show_main_menu)
	bottom_row.add_child(back_btn)

	var skip_btn := Button.new()
	skip_btn.theme_type_variation = "SecondaryButton"
	skip_btn.text = "Skip Intro"
	skip_btn.pressed.connect(_show_setup)
	bottom_row.add_child(skip_btn)

	_apply_overlay_visibility()

func _on_story_prev_pressed() -> void:
	_story_page -= 1
	_show_story()

## On every page but the last, just advances the page; on the last page
## the button reads "Let's Cook" instead and this moves on to setup
## instead of incrementing past the end of STORY_PAGES.
func _on_story_next_pressed() -> void:
	if _story_page == STORY_PAGES.size() - 1:
		_show_setup()
		return
	_story_page += 1
	_show_story()

# ===========================================================================
# Settings (audio only, for now)
# ===========================================================================

func _show_settings() -> void:
	ui_mode = UiMode.SETTINGS
	_clear_children(settings_overlay)
	var box := _overlay_content_box(settings_overlay, false)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_build_volume_row("Master Volume", "Master"))
	box.add_child(_build_volume_row("Music Volume", "Music"))
	box.add_child(_build_volume_row("Sound Effects Volume", "SFX"))

	var back_btn := Button.new()
	back_btn.theme_type_variation = "SecondaryButton"
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(220, 0)
	back_btn.pressed.connect(_show_main_menu)
	box.add_child(back_btn)

	_apply_overlay_visibility()

func _build_volume_row(label_text: String, bus_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.theme_type_variation = "WideHBox"

	var label := Label.new()
	label.theme_type_variation = "HintLabel"
	label.text = label_text
	label.custom_minimum_size = Vector2(240, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = _bus_volume_pct(bus_name)
	slider.custom_minimum_size = Vector2(360, 0)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.theme_type_variation = "BadgeLabel"
	value_label.text = "%d%%" % int(slider.value)
	value_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		_set_bus_volume_pct(bus_name, v)
		value_label.text = "%d%%" % int(v)
		_save_settings()
	)

	return row

## Godot's default project has only the "Master" bus; Music/SFX are added
## at runtime (idempotently) rather than checked in as a saved bus layout
## resource, since there's no audio content yet to route through them --
## this just gets the routing ready for whenever some is added.
func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func _bus_volume_pct(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 100.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)) * 100.0, 0.0, 100.0)

func _set_bus_volume_pct(bus_name: String, pct: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped := clampf(pct, 0.0, 100.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamped / 100.0))

const _SETTINGS_PATH := "user://settings.cfg"

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(_SETTINGS_PATH) == OK
	for bus_name in ["Master", "Music", "SFX"]:
		var pct: float = cfg.get_value("audio", bus_name, 100.0) if loaded else 100.0
		_set_bus_volume_pct(bus_name, pct)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus_name in ["Master", "Music", "SFX"]:
		cfg.set_value("audio", bus_name, _bus_volume_pct(bus_name))
	cfg.save(_SETTINGS_PATH)

# ===========================================================================
# Setup screen (hot-seat config + entry points to online play)
# ===========================================================================

func _show_setup() -> void:
	ui_mode = UiMode.SETUP
	_clear_children(setup_overlay)

	var bg := MenuBackground.new(SETUP_BG_PATH)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	setup_overlay.add_child(bg)

	var box := _overlay_content_box(setup_overlay)

	var back_btn := Button.new()
	back_btn.theme_type_variation = "SecondaryButton"
	back_btn.text = "< Main Menu"
	back_btn.pressed.connect(_show_main_menu)
	box.add_child(back_btn)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Manze Lakaz"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	if _setup_info_message != "":
		var info_banner := Label.new()
		info_banner.theme_type_variation = "PromptLabel"
		info_banner.text = _setup_info_message
		info_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(info_banner)
		_setup_info_message = "" # one-shot: shown once, then cleared

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

	var timer_row := HBoxContainer.new()
	box.add_child(timer_row)
	var timer_toggle := CheckButton.new()
	timer_toggle.text = "Turn timer"
	timer_toggle.button_pressed = hotseat_turn_timer_enabled
	timer_row.add_child(timer_toggle)
	var timer_label := Label.new()
	timer_label.theme_type_variation = "HintLabel"
	timer_label.text = "%.0fs" % hotseat_turn_timer_seconds
	timer_label.modulate.a = 1.0 if hotseat_turn_timer_enabled else 0.5
	timer_row.add_child(timer_label)
	var timer_slider := HSlider.new()
	timer_slider.min_value = 10.0
	timer_slider.max_value = 300.0 # 5 minutes, the requested cap
	timer_slider.step = 10.0
	timer_slider.value = hotseat_turn_timer_seconds
	timer_slider.custom_minimum_size = Vector2(220, 0)
	timer_slider.editable = hotseat_turn_timer_enabled
	timer_slider.value_changed.connect(_on_hotseat_turn_timer_changed.bind(timer_label))
	timer_row.add_child(timer_slider)
	timer_toggle.toggled.connect(_on_hotseat_turn_timer_toggled.bind(timer_slider, timer_label))

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
	host_btn.text = "Create Session"
	host_btn.pressed.connect(_show_network_setup.bind(true))
	online_row.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.theme_type_variation = "SecondaryButton"
	join_btn.text = "Join Session"
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
	return "AI, " + AiBot.DIFFICULTY_NAMES[mode]

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

func _on_hotseat_turn_timer_changed(value: float, label: Label) -> void:
	hotseat_turn_timer_seconds = value
	label.text = "%.0fs" % value

func _on_hotseat_turn_timer_toggled(enabled: bool, slider: HSlider, label: Label) -> void:
	hotseat_turn_timer_enabled = enabled
	slider.editable = enabled
	label.modulate.a = 1.0 if enabled else 0.5

func _on_start_pressed() -> void:
	var config := GameConfig.new()
	config.num_players = _pending_num_players
	config.seed = int(Time.get_unix_time_from_system() * 1000.0) % 1000000

	var hot_seat := LocalHotSeatSession.new(db)
	if not hot_seat.start_game(config):
		prompt_label.text = "Failed to start game, see console output."
		return

	for i in _pending_num_players:
		var mode: int = _pending_seat_mode.get(i, -1)
		if mode != -1:
			hot_seat.seat_bots[i] = AiBot.create(mode, i)
			hot_seat.seat_difficulty[i] = mode

	is_network_mode = false
	_connect_session(hot_seat)
	_game_start_sfx_played = true
	_play_sfx(GAME_START_SFX)

	_clear_children(log_box)
	selected_card_id = -1
	selected_move_prep_id = -1
	_pending_joker_choices = []
	_dealt_seen.clear()
	_shown_recipe_completions.clear()
	_player_card_page.clear()
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
	title.text = "Create Session" if is_host else "Join Session"
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
		host_button.text = "Create Session"
		host_button.custom_minimum_size = Vector2(260, 0)
		host_button.pressed.connect(_on_host_pressed)
		box.add_child(host_button)
	else:
		# A session id (not an address:port) -- WebRTC peers don't listen
		# on a port, so there's nothing to dial directly. The host shares
		# this short code (from the lobby, once session_ready fires) out
		# of band, e.g. over chat.
		_add_labeled_line_edit(box, "Session ID:", _pending_join_session_id, func(t): _pending_join_session_id = t)

		var join_button := Button.new()
		join_button.theme_type_variation = "PrimaryButton"
		join_button.text = "Join"
		join_button.custom_minimum_size = Vector2(260, 0)
		join_button.pressed.connect(_on_join_pressed)
		box.add_child(join_button)

	network_status_label = Label.new()
	network_status_label.theme_type_variation = "HintLabel"
	network_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(network_status_label)

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

## Tube's create_session() is signal-driven, not synchronous (the session
## id doesn't exist until signaling actually starts), so this shows a
## waiting state immediately and _on_host_session_ready()/
## _on_network_connection_error() finish the attempt once Tube reports
## success or failure.
func _on_host_pressed() -> void:
	var config := GameConfig.new()
	config.num_players = _pending_num_players
	config.seed = int(Time.get_unix_time_from_system() * 1000.0) % 1000000

	var peer := _network_peer()
	peer.session_ready.connect(_on_host_session_ready, CONNECT_ONE_SHOT)
	peer.connection_error.connect(_on_network_connection_error, CONNECT_ONE_SHOT)
	peer.create_session(db, config, _pending_turn_timer_seconds, _pending_auto_play_difficulty, AI_THINK_TIME_SECONDS, _pending_fill_ai, _pending_ai_fill_difficulty)
	_show_connecting_state("Creating session...", true)

func _on_host_session_ready(session_id: String) -> void:
	var peer := _network_peer()
	if peer.connection_error.is_connected(_on_network_connection_error):
		peer.connection_error.disconnect(_on_network_connection_error)

	my_session_id = session_id
	is_network_mode = true
	is_network_host = true
	_connect_session(NetworkSession.new(db, peer))
	_wire_lobby_signals(peer)

	peer.request_join(_pending_display_name) # host's own seat: no network round-trip needed
	_show_lobby()

## join_session() is likewise signal-driven; _on_join_session_joined()/
## _on_network_connection_error() finish the attempt.
func _on_join_pressed() -> void:
	var peer := _network_peer()
	peer.session_joined.connect(_on_join_session_joined, CONNECT_ONE_SHOT)
	peer.connection_error.connect(_on_network_connection_error, CONNECT_ONE_SHOT)
	peer.join_session(_pending_join_session_id, db)
	_show_connecting_state("Joining session %s..." % _pending_join_session_id, true)

func _on_join_session_joined() -> void:
	var peer := _network_peer()
	if peer.connection_error.is_connected(_on_network_connection_error):
		peer.connection_error.disconnect(_on_network_connection_error)

	is_network_mode = true
	is_network_host = false
	# Not just for the host anymore -- see _run_reconnect_attempts(), which
	# needs a session id to rejoin regardless of which role disconnected.
	# The lobby's own "share this code" block stays host-only via the
	# explicit is_network_host check added there, so this doesn't change
	# what a joining client sees.
	my_session_id = peer.session_id
	_connect_session(NetworkSession.new(db, peer))
	_wire_lobby_signals(peer)

	_confirm_initial_join(peer)

## session_joined firing only proves the WebRTC transport connected -- it
## does NOT prove request_join()'s RPC actually reached the host and got a
## reply. A data channel can report "connected" a moment before it's truly
## ready to carry traffic, and a lost reliable RPC in that window has no
## automatic retry, so the old code (which just called request_join() once
## and immediately showed the lobby, trusting it would work out) is exactly
## the bug behind "client shows Waiting for host forever, but the host
## never sees them join": nothing was actually watching for the host's
## reply. This retries once, then gives up with a real, actionable error
## instead of hanging on the lobby screen with no feedback at all.
func _confirm_initial_join(peer: Node) -> void:
	_show_connecting_state("Confirming with the host...", false)
	for attempt in JOIN_CONFIRM_ATTEMPTS:
		peer.request_join(_pending_display_name)
		if await _await_seat_assigned(peer, JOIN_CONFIRM_TIMEOUT_SECONDS):
			_show_lobby()
			return
		if not is_network_mode:
			return # already handled elsewhere (e.g. _on_join_rejected already tore this down)

	_do_leave_network_game()
	_show_network_setup(_pending_is_host)
	network_status_label.text = "Connected, but the host never confirmed you joined. This usually means the connection looked successful at first but isn't actually working -- try again, and if it keeps happening, try a different network."

## True once seat_assigned fires, false on timeout. Bails out early (also
## false) if is_network_mode flips to false while waiting -- that means
## something else already tore the attempt down (e.g. an explicit
## join_rejected via _on_join_rejected()), so there's nothing left to wait
## for and no point sitting out the rest of the timeout.
func _await_seat_assigned(peer: Node, timeout_seconds: float) -> bool:
	var ctx := {"result": null}
	var on_seat_assigned := func(_seat: int, _token: String): ctx["result"] = true
	peer.seat_assigned.connect(on_seat_assigned, CONNECT_ONE_SHOT)

	var waited := 0.0
	while ctx["result"] == null and waited < timeout_seconds and is_network_mode:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25

	if peer.seat_assigned.is_connected(on_seat_assigned):
		peer.seat_assigned.disconnect(on_seat_assigned)

	return ctx["result"] == true

## A plain waiting/connecting screen (create and join both use it) --
## WebRTC signaling can take several seconds, and a player should never
## be staring at a form that no longer does anything with no way out, so
## this always offers a way back rather than only on the join side.
func _show_connecting_state(status_text: String, show_cancel: bool) -> void:
	ui_mode = UiMode.NETWORK_SETUP
	_clear_children(network_setup_overlay)
	var box := _overlay_content_box(network_setup_overlay)

	var label := Label.new()
	label.theme_type_variation = "TitleLabel"
	label.text = status_text
	# This label only ever holds a short one-line status ("Creating
	# session...", "Joining session %s...", "Confirming with the host...")
	# -- a real connection error goes to the separate network_status_label
	# on _show_network_setup() instead, which does wrap -- so there's no
	# long text here that would need wrapping; forcing one line reads
	# better than an unnecessary early break partway through a short phrase.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	if show_cancel:
		var cancel_btn := Button.new()
		cancel_btn.theme_type_variation = "SecondaryButton"
		cancel_btn.text = "Cancel"
		cancel_btn.pressed.connect(_on_connecting_cancel_pressed)
		box.add_child(cancel_btn)

	_apply_overlay_visibility()

## Aborts whichever attempt is in flight (create or join -- both route
## through the same waiting screen) and returns to that mode's config
## screen so the player can adjust and retry.
func _on_connecting_cancel_pressed() -> void:
	var peer := _network_peer()
	if peer.session_ready.is_connected(_on_host_session_ready):
		peer.session_ready.disconnect(_on_host_session_ready)
	if peer.session_joined.is_connected(_on_join_session_joined):
		peer.session_joined.disconnect(_on_join_session_joined)
	if peer.connection_error.is_connected(_on_network_connection_error):
		peer.connection_error.disconnect(_on_network_connection_error)
	peer.shutdown()
	_show_network_setup(_pending_is_host)

## Shared failure path for both create_session() and join_session().
## NetworkPeer has already translated whatever Tube/WebRTC reported into
## plain language (session not found, trackers unreachable, NAT/firewall
## failure, etc.) -- this only has to display it and give the player
## somewhere to go, never interpret the message itself.
func _on_network_connection_error(message: String) -> void:
	var peer := _network_peer()
	if peer.session_ready.is_connected(_on_host_session_ready):
		peer.session_ready.disconnect(_on_host_session_ready)
	if peer.session_joined.is_connected(_on_join_session_joined):
		peer.session_joined.disconnect(_on_join_session_joined)
	_show_network_setup(_pending_is_host)
	network_status_label.text = message

func _wire_lobby_signals(peer: Node) -> void:
	if not peer.lobby_changed.is_connected(_on_lobby_changed):
		peer.lobby_changed.connect(_on_lobby_changed)
	if not peer.join_rejected.is_connected(_on_join_rejected):
		peer.join_rejected.connect(_on_join_rejected)

## Only ever reaches a client (a host never rejects itself). By the time
## this arrives the WebRTC connection already succeeded, so there's a
## live session to tear back down before returning to the join screen.
func _on_join_rejected(reason: String) -> void:
	if _reconnecting:
		return # a rejected rejoin token is handled by the reconnect loop's own temporary listener, not this persistent one
	_do_leave_network_game()
	_show_network_setup(_pending_is_host)
	network_status_label.text = reason

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

	var peer := _network_peer()

	# The session id is the ONLY thing a player ever types or shares --
	# there's no address or port anymore -- so it has to be unmissable:
	# shown large, with a one-tap copy and a plain instruction. Host-only:
	# my_session_id is populated for clients too now (see
	# _on_join_session_joined()/_run_reconnect_attempts()), but a joining
	# client already knows the code -- they typed it in -- so repeating it
	# back with "send this to your friends" would only be confusing.
	if my_session_id != "" and is_network_host:
		var id_label := Label.new()
		id_label.theme_type_variation = "TitleLabel"
		id_label.text = my_session_id
		id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(id_label)

		var share_line := Label.new()
		share_line.theme_type_variation = "HintLabel"
		share_line.text = "Send this code to your friends so they can join."
		share_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(share_line)

		var copy_btn := Button.new()
		copy_btn.theme_type_variation = "SecondaryButton"
		copy_btn.text = "Copy"
		copy_btn.pressed.connect(func():
			DisplayServer.clipboard_set(my_session_id)
			copy_btn.text = "Copied!"
		)
		box.add_child(copy_btn)

	for seat_info in lobby_seats:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.theme_type_variation = "PlayerNameLabel"
		var status := "connected" if seat_info["connected"] else ("AI" if seat_info["is_ai"] else "empty")
		label.text = "Seat %d: %s (%s)" % [int(seat_info["seat"]) + 1, str(seat_info["name"]), status]
		row.add_child(label)

	if peer.authority != null:
		# Read-only: fill_empty_seats_with_ai/ai_fill_difficulty are baked
		# into ServerAuthority at creation time (see _on_host_pressed), so
		# there's nothing left to toggle here -- just confirm what was
		# already chosen before this seat count locked in.
		if _pending_fill_ai:
			var ai_fill_info := Label.new()
			ai_fill_info.theme_type_variation = "HintLabel"
			ai_fill_info.text = "Empty seats will be filled with %s AI when the game starts." % AiBot.DIFFICULTY_NAMES[_pending_ai_fill_difficulty]
			ai_fill_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(ai_fill_info)

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

	# No confirmation here: the game hasn't started yet, so leaving the
	# lobby doesn't cost anyone else anything. Once play begins,
	# leave_game_button (see _on_leave_game_pressed) takes over and does
	# warn, specifically because it's now destructive for everyone else.
	var leave_button := Button.new()
	leave_button.theme_type_variation = "SecondaryButton"
	leave_button.text = "Leave"
	leave_button.pressed.connect(_on_leave_lobby_pressed)
	box.add_child(leave_button)

	_apply_overlay_visibility()

func _on_leave_lobby_pressed() -> void:
	_do_leave_network_game()
	_show_setup()

## The one place that actually tears down a network session this device
## itself chose to leave -- every self-initiated exit (lobby Leave,
## mid-game Leave, New Game) routes through here so _leaving_intentionally
## is always set before shutdown() fires session_ended, which is what
## keeps _on_network_session_ended() from also treating our own
## deliberate exit as "the host ended it out from under us".
func _do_leave_network_game() -> void:
	_leaving_intentionally = true
	_reconnecting = false
	_network_peer().shutdown()
	is_network_mode = false
	is_network_host = false
	my_session_id = ""

## The only way to leave a network game once play has actually started
## (the lobby's own Leave button only exists pre-start). Hosting is
## destructive to everyone else -- leaving tears down the one real
## GameState -- so the host gets a confirmation; a client leaving only
## affects their own seat, so they don't.
func _on_leave_game_pressed() -> void:
	var peer := _network_peer()
	if peer.authority == null:
		_do_leave_network_game()
		_show_setup()
		return

	# queue_free() connected on every dismissal path (confirm, cancel, and
	# the window's own close button/Escape) -- AcceptDialog's default
	# behavior is to hide() itself, not free itself, so without this the
	# dialog would sit as a permanent invisible child of GameScreen after
	# every single dismissal, confirmed or not.
	var dialog := ConfirmationDialog.new()
	dialog.title = "Leave game?"
	dialog.dialog_text = "Leaving now will end the session for everyone else. Are you sure?"
	add_child(dialog)
	dialog.confirmed.connect(func():
		_do_leave_network_game()
		_show_setup()
	)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered()

## Fires whenever Tube tears the session down for any reason: our own
## Leave/New Game (see _do_leave_network_game -- guarded off below), the
## host closing the session, or this device's own connection dying
## post-join. Only the last two should ever reach here uninitiated by us.
##
## Tube's session_left/session_ended carries no reason -- there is no way
## to tell "the host ended it" apart from "my own connection just broke"
## at this level. For a client holding a still-valid rejoin token, the
## right move is the same either way: try to reconnect. If the host truly
## ended things, every rejoin attempt will keep coming back rejected (see
## ServerAuthority.handle_rejoin_request) and the retry loop below gives
## up on its own once the 60s budget runs out -- there's no separate "host
## ended it" fast path to write, because there's no signal to distinguish
## it by.
func _on_network_session_ended() -> void:
	if _leaving_intentionally:
		_leaving_intentionally = false
		return
	var peer := _network_peer()
	if is_network_mode and not is_network_host and peer.my_token != "":
		if not _reconnecting:
			_start_reconnect_loop()
		return
	is_network_mode = false
	is_network_host = false
	my_session_id = ""
	_setup_info_message = "The host ended the session."
	_show_setup()

# ===========================================================================
# Reconnection (client only -- see _on_network_session_ended)
# ===========================================================================

func _show_reconnecting_overlay(status_text: String) -> void:
	ui_mode = UiMode.RECONNECTING
	_clear_children(reconnecting_overlay)
	var box := _overlay_content_box(reconnecting_overlay)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "Reconnecting..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	reconnect_status_label = Label.new()
	reconnect_status_label.theme_type_variation = "HintLabel"
	reconnect_status_label.text = status_text
	reconnect_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reconnect_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(reconnect_status_label)

	_apply_overlay_visibility()

func _start_reconnect_loop() -> void:
	_reconnecting = true
	_show_reconnecting_overlay("Connection lost. Reconnecting...")
	_run_reconnect_attempts()

## Retries join_session() + request_rejoin(token) with backoff for up to
## RECONNECT_TOTAL_TIMEOUT_SECONDS. On success the existing NetworkSession
## pipeline takes it from here with no extra code: ServerAuthority's
## handle_rejoin_request() re-broadcasts the lobby and, if the game had
## already started, sends a fresh snapshot, which lands on
## snapshot_received -> state_changed -> _advance_ui_after_state_change(),
## swapping the reconnecting overlay for the right screen on its own. The
## one case that pipeline can't cover is a disconnect that happened before
## the game started (no snapshot is ever sent for a lobby-only rejoin), so
## that case is handled explicitly below instead.
func _run_reconnect_attempts() -> void:
	var peer := _network_peer()
	var session_id := my_session_id
	var token: String = peer.my_token
	var start_ticks := Time.get_ticks_msec()
	var backoff := RECONNECT_BACKOFF_START_SECONDS

	while true:
		# Tube emits session_left (which is what got us here) BEFORE it
		# resets its own client state back to IDLE -- calling
		# join_session() synchronously in the same frame that produced
		# this session_ended would still see a non-IDLE client and fail
		# outright. Deferring one frame gives that reset a chance to land.
		await get_tree().process_frame
		if not _reconnecting:
			return

		var elapsed_ms := Time.get_ticks_msec() - start_ticks
		if elapsed_ms >= int(RECONNECT_TOTAL_TIMEOUT_SECONDS * 1000.0):
			break

		if is_instance_valid(reconnect_status_label):
			reconnect_status_label.text = "Connection lost. Reconnecting..."

		var ok: bool = await _try_reconnect_once(session_id, token)
		if not _reconnecting:
			return
		if ok:
			_reconnecting = false
			# state (GameScreen's cached copy) can still be holding a
			# PREVIOUS game's snapshot from earlier this app session, so
			# it can't tell "this session's game hasn't started" apart
			# from "some past session's game had". session itself can:
			# _on_host_session_ready()/_on_join_session_joined() always
			# construct a brand new NetworkSession per session, so a
			# fresh one's own get_state() is null until ITS first
			# snapshot arrives.
			var net_session := session as NetworkSession
			if net_session == null or net_session.get_state() == null:
				# Disconnected before the game started: no snapshot is
				# coming, so nothing else will move the UI off this
				# overlay -- show the lobby ourselves.
				_show_lobby()
			return

		elapsed_ms = Time.get_ticks_msec() - start_ticks
		var remaining_seconds := RECONNECT_TOTAL_TIMEOUT_SECONDS - (elapsed_ms / 1000.0)
		if remaining_seconds <= 0.0:
			break

		if is_instance_valid(reconnect_status_label):
			reconnect_status_label.text = "Still trying to reconnect..."
		await get_tree().create_timer(minf(backoff, remaining_seconds)).timeout
		backoff = minf(backoff * 2.0, RECONNECT_BACKOFF_MAX_SECONDS)

	_reconnecting = false
	_do_leave_network_game()
	_setup_info_message = "Couldn't reconnect, the connection stayed down too long."
	_show_setup()

## One attempt: rejoin the WebRTC session, then redeem the rejoin token.
## Returns true only once seat_assigned confirms the token was accepted;
## any connection_error, join_rejected, or timeout returns false so the
## caller retries. Uses the same one-shot-listener pattern as
## _on_host_pressed/_on_join_pressed, just chained across two stages
## instead of one.
func _try_reconnect_once(session_id: String, token: String) -> bool:
	var peer := _network_peer()
	# Lambdas capture outer locals BY VALUE at the moment each lambda
	# literal is created -- on_session_joined needs to reach the (not yet
	# created) on_seat_assigned/on_join_rejected callables, and all four
	# need to reach the (also not yet fully populated) disconnect_all.
	# Boxing everything in one shared, mutable Dictionary sidesteps that:
	# every lookup below happens at CALL time, once the signal actually
	# fires, by which point ctx["callables"] has long since been filled in.
	var ctx := {"result": null, "callables": {}} # result: null = pending, true/false once settled

	var disconnect_all := func():
		var c: Dictionary = ctx["callables"]
		if peer.session_joined.is_connected(c["session_joined"]):
			peer.session_joined.disconnect(c["session_joined"])
		if peer.connection_error.is_connected(c["connection_error"]):
			peer.connection_error.disconnect(c["connection_error"])
		if peer.seat_assigned.is_connected(c["seat_assigned"]):
			peer.seat_assigned.disconnect(c["seat_assigned"])
		if peer.join_rejected.is_connected(c["join_rejected"]):
			peer.join_rejected.disconnect(c["join_rejected"])

	var on_seat_assigned := func(_seat: int, _token: String):
		disconnect_all.call()
		ctx["result"] = true
	var on_join_rejected := func(_reason: String):
		disconnect_all.call()
		ctx["result"] = false
	var on_session_joined := func():
		var c: Dictionary = ctx["callables"]
		peer.seat_assigned.connect(c["seat_assigned"], CONNECT_ONE_SHOT)
		peer.join_rejected.connect(c["join_rejected"], CONNECT_ONE_SHOT)
		peer.request_rejoin(token)
	var on_connection_error := func(_message: String):
		disconnect_all.call()
		ctx["result"] = false

	ctx["callables"] = {
		"session_joined": on_session_joined,
		"connection_error": on_connection_error,
		"seat_assigned": on_seat_assigned,
		"join_rejected": on_join_rejected,
	}

	peer.session_joined.connect(on_session_joined, CONNECT_ONE_SHOT)
	peer.connection_error.connect(on_connection_error, CONNECT_ONE_SHOT)
	peer.join_session(session_id, db)

	var waited := 0.0
	while ctx["result"] == null and waited < RECONNECT_ATTEMPT_TIMEOUT_SECONDS and _reconnecting:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25

	if ctx["result"] == null:
		disconnect_all.call()
		peer.shutdown() # force this attempt's half-open transport down before the next one starts
		return false

	return ctx["result"]

# ===========================================================================
# Turn-owner change detection -> hot-seat privacy (network mode never gates)
# ===========================================================================

func _advance_ui_after_state_change() -> void:
	state = session.get_state()
	# Invalidates any turn timer armed for a previous call to this function
	# (a stale one's captured token can no longer match) -- only the two
	# branches below that actually show the local human's own turn (one
	# hot-seat, one network) re-arm a fresh one, so every other outcome
	# (pass-device, AI turn, someone else's turn, game over, ...)
	# implicitly cancels it just by getting here.
	_invalidate_hotseat_turn_timer()
	if state == null:
		return

	if is_network_mode and not _game_start_sfx_played:
		_game_start_sfx_played = true
		_play_sfx(GAME_START_SFX)

	_check_prep_ambience()

	# Checked before game_over too: the winning attach IS a recipe
	# completion, and the reveal should show before the victory screen,
	# not instead of it -- "Continue" re-enters this function once the
	# completion is marked seen, and normal dispatch (including game_over)
	# proceeds from there.
	if _check_for_recipe_completions():
		return

	if state.game_over:
		_show_game_over()
		return

	if is_network_mode:
		# No pass-device gate online: this device only ever shows its OWN
		# assigned seat's board (see ShadowStateBuilder/NetworkStateFilter),
		# so there is nothing to hide from "whoever's holding the device".
		if state.current_player_index == _viewer_index():
			_arm_network_turn_timer_display()
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
		selected_move_prep_id = -1
		_pending_joker_choices = []
		_show_pass_device()
		return

	_arm_hotseat_turn_timer()

	if state.phase == GameState.Phase.DRAFT:
		_show_draft()
	else:
		_show_play()

## Also doubles as the reset point for network mode's display-only
## countdown (see _arm_network_turn_timer_display()) -- every caller here
## means "state just changed, whatever countdown was showing is stale",
## regardless of which mode set it.
func _invalidate_hotseat_turn_timer() -> void:
	_hotseat_turn_timer_token += 1
	_turn_timer_deadline_msec = -1
	_timer_warning_played = false
	timer_warning_player.stop()

## Starts (or restarts) the countdown for whoever can currently act. Called
## from two distinct places, both meaning "a human's turn just became
## actionable on this device": here, when the same player continues
## straight through without a pass-device interruption (e.g. a hand-limit
## forced discard), and from _on_pass_device_ready_pressed(), which shows
## _show_play()/_show_draft() directly and so never runs through this
## function at all. A no-op past invalidating the previous countdown
## (already done, correctly, by every caller) when the timer is turned off.
func _arm_hotseat_turn_timer() -> void:
	_invalidate_hotseat_turn_timer()
	if not hotseat_turn_timer_enabled:
		return
	var armed_token := _hotseat_turn_timer_token
	_turn_timer_deadline_msec = Time.get_ticks_msec() + int(hotseat_turn_timer_seconds * 1000.0)
	get_tree().create_timer(hotseat_turn_timer_seconds).timeout.connect(_on_hotseat_turn_timer_expired.bind(armed_token))

## Purely a visual countdown for online play -- the server (ServerAuthority)
## owns the real turn timer and its auto-play fallback there, so unlike
## _arm_hotseat_turn_timer() this schedules nothing: it only sets the same
## deadline turn_timer_badge already knows how to display. "Turn start" is
## approximated as "this snapshot just arrived", since the server doesn't
## broadcast an exact deadline, only the configured duration -- close
## enough for a non-authoritative aid, and the server's own timer is what
## actually decides when a turn times out regardless of what this shows.
func _arm_network_turn_timer_display() -> void:
	var seconds: float = (session as NetworkSession).latest_snapshot.get("turn_timer_seconds", 0.0)
	if seconds <= 0.0:
		return
	_turn_timer_deadline_msec = Time.get_ticks_msec() + int(seconds * 1000.0)

## If the local human at the controls doesn't act before hotseat_turn_timer_seconds
## elapses, a fallback bot plays out the REST of their turn -- not just one
## action -- so timing out actually skips play to the next player instead of
## nudging one step at a time and re-arming a fresh full-length wait for
## every remaining step of the same turn. Same idea as ServerAuthority's
## per-seat turn timer online, just driven locally since hot-seat has no
## server to own it. fired_token must still match _hotseat_turn_timer_token
## (see _advance_ui_after_state_change(), which bumps it on every call):
## otherwise this fire is stale, superseded by a real action or a
## phase/turn change that already happened.
func _on_hotseat_turn_timer_expired(fired_token: int) -> void:
	if fired_token != _hotseat_turn_timer_token:
		return
	if is_network_mode or state == null or state.game_over:
		return

	var stalled_player := state.current_player_index
	selected_card_id = -1
	selected_move_prep_id = -1
	_pending_joker_choices = []

	# TAKE/PLAY: skip the turn outright, no bot plays on the stalled
	# player's behalf -- see RulesEngine.skip_turn() for why (a fallback
	# bot choosing to steal or attach for a player who never actually
	# chose to was the exact bug this replaced, same as ServerAuthority's
	# equivalent online).
	if state.phase == GameState.Phase.TAKE or state.phase == GameState.Phase.PLAY:
		RulesEngine.skip_turn(state)
		_append_log_line("(Turn timer expired) Player %d's turn was skipped" % (stalled_player + 1))
		session.state_changed.emit()
		return

	# DRAFT/HAND_LIMIT can't be skipped -- every player must resolve these
	# regardless of presence, so fall back to auto-play exactly as before,
	# looping until this player's turn (potentially several picks/discards)
	# actually finishes. The draft is turn-based per player too, but
	# _advance_draft() can land the LAST drafter's index back on player 0
	# the moment the draft finishes -- if the stalled player happened to be
	# player 0, a bare current_player_index check would wrongly treat
	# their brand new TAKE turn as "still the same stalled draft turn" and
	# keep auto-playing past it. Stopping at the DRAFT->TAKE phase
	# boundary closes that gap.
	var stalled_in_draft := state.phase == GameState.Phase.DRAFT
	var steps := 0
	while steps < 20 and not state.game_over and state.current_player_index == stalled_player \
			and (not stalled_in_draft or state.phase == GameState.Phase.DRAFT):
		var legal := session.get_legal_actions()
		if legal.is_empty():
			break
		var bot := AiBot.create(AiBot.Difficulty.MEDIUM, state.current_player_index)
		var action := bot.choose_action(state, legal)
		if action == null:
			break
		var line := "(Turn timer expired) " + GameViewModel.describe_action_for_log(state, action)
		_submit_action(action)
		_append_log_line(line)
		steps += 1

## Scans for any completed recipe not yet revealed and, if found, shows it
## and returns true so the caller stops dispatching for this call --
## "Continue" re-enters _advance_ui_after_state_change() once it's marked
## seen. Completion is inherently public once it happens (a finished dish
## sits face-up on the table), so this runs the same way in hot-seat and
## online, and even for a bot's own turn -- there's no hidden information
## being exposed here, only which dish is done.
func _check_for_recipe_completions() -> bool:
	for p in state.players:
		for ri in p.recipes.size():
			var recipe: Recipe = p.recipes[ri]
			if not recipe.completed:
				continue
			var key := "%d:%d" % [p.index, ri]
			if _shown_recipe_completions.has(key):
				continue
			_shown_recipe_completions[key] = true
			_pending_recipe_reveal = {"player_index": p.index, "recipe_index": ri}
			_show_recipe_reveal()
			return true
	return false

## The real-world dish behind a just-completed recipe: full ingredient
## list with quantities, plus prep/cook/total time. Pure flavor -- shown
## once per completed recipe, then "Continue" resumes normal dispatch.
func _show_recipe_reveal() -> void:
	ui_mode = UiMode.RECIPE_REVEAL
	_clear_children(recipe_reveal_overlay)
	var box := _overlay_content_box(recipe_reveal_overlay, false)
	# Overrides _overlay_content_box()'s own "WideVBox" (16px gaps) -- with
	# scrolling gone (see that function's own comment), every px this
	# screen's own fixed header needs is a px a Feast dish's 9-step method
	# doesn't have, so the header is deliberately packed tighter.
	box.theme_type_variation = "TightVBox"

	var player_index: int = _pending_recipe_reveal["player_index"]
	var recipe_index: int = _pending_recipe_reveal["recipe_index"]
	var recipe: Recipe = state.players[player_index].recipes[recipe_index]
	var view := GameViewModel.real_recipe_view(recipe.def.id, db)

	var headline := Label.new()
	headline.theme_type_variation = "TitleLabel"
	headline.text = "Player %d completed a dish!" % (player_index + 1)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(headline)

	var card := RecipeCardFace.new()
	card.setup(view["display_name"], view["country"], view["tier_name"], view["recipe_id"])
	card.custom_minimum_size = Vector2(130, 150) # smaller than RecipeCardFace's own 170x220 default -- this reveal needs the vertical room more than the card needs its usual full size
	card.disabled = true
	box.add_child(card)

	var times := Label.new()
	times.theme_type_variation = "BadgeLabel"
	times.text = "Prep: %s    Cook: %s    Total: %s" % [view["prep_time"], view["cook_time"], view["total_time"]]
	times.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(times)

	var ingredients: Array = view["ingredients"]
	var steps: Array = view["steps"]

	if ingredients.is_empty() and steps.is_empty():
		var none_label := Label.new()
		none_label.theme_type_variation = "HintLabel"
		none_label.text = "(recipe details coming soon)"
		box.add_child(none_label)
	else:
		# Ingredients (left) and how-to-make-it steps (right) side by side,
		# not one long stacked list -- a Feast dish's full method can run to
		# 8-9 detailed steps, which read far more comfortably as a second
		# column than as a single narrow list stretching down the overlay.
		var columns := HBoxContainer.new()
		columns.theme_type_variation = "WideHBox"
		box.add_child(columns)

		var ingredients_col := VBoxContainer.new()
		ingredients_col.theme_type_variation = "TightVBox"
		ingredients_col.custom_minimum_size = Vector2(260, 0)
		columns.add_child(ingredients_col)

		var ingredients_title := Label.new()
		ingredients_title.theme_type_variation = "SectionLabel"
		ingredients_title.text = "Real ingredients"
		ingredients_col.add_child(ingredients_title)

		for ing in ingredients:
			var row := Label.new()
			row.theme_type_variation = "RecipeSlotFilledLabel"
			row.text = "%s, %s" % [ing["quantity"], ing["name"]]
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ingredients_col.add_child(row)

		var steps_col := VBoxContainer.new()
		steps_col.theme_type_variation = "TightVBox"
		steps_col.custom_minimum_size = Vector2(600, 0)
		columns.add_child(steps_col)

		var steps_title := Label.new()
		steps_title.theme_type_variation = "SectionLabel"
		steps_title.text = "How to make it"
		steps_col.add_child(steps_title)

		for i in steps.size():
			var step_row := Label.new()
			step_row.theme_type_variation = "RecipeSlotEmptyLabel"
			step_row.text = "%d. %s" % [i + 1, steps[i]]
			step_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			steps_col.add_child(step_row)

	var continue_btn := Button.new()
	continue_btn.theme_type_variation = "PrimaryButton"
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(220, 0)
	continue_btn.pressed.connect(_on_recipe_reveal_continue_pressed)
	box.add_child(continue_btn)

	_apply_overlay_visibility()

func _on_recipe_reveal_continue_pressed() -> void:
	_pending_recipe_reveal = {}
	_advance_ui_after_state_change()

## AI turns are resolved entirely behind this overlay: no board, no hand,
## nothing rendered that a human shouldn't see. Only the resulting log
## lines (draws, attaches, steals, discards -- all public consequences)
## become visible once control returns to a human. Hot-seat only: online
## AI seats are server-side (ServerAuthority), never driven from here.
func _show_ai_thinking() -> void:
	ui_mode = UiMode.AI_THINKING
	_clear_children(ai_thinking_overlay)
	var box := _overlay_content_box(ai_thinking_overlay)

	var label := Label.new()
	label.theme_type_variation = "TitleLabel"
	label.text = "Player %d is thinking..." % (state.current_player_index + 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	_apply_overlay_visibility()

	get_tree().create_timer(AI_THINK_TIME_SECONDS).timeout.connect(_run_ai_step)

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
	ready_button.text = "I'm Player %d, show my turn" % next_player_num
	ready_button.custom_minimum_size = Vector2(300, 0)
	ready_button.pressed.connect(_on_pass_device_ready_pressed)
	box.add_child(ready_button)

	_apply_overlay_visibility()

func _on_pass_device_ready_pressed() -> void:
	(session as LocalHotSeatSession).set_viewer_index(state.current_player_index)
	_arm_hotseat_turn_timer()
	if state.phase == GameState.Phase.DRAFT:
		_show_draft()
	else:
		_show_play()

# ===========================================================================
# Draft screen
# ===========================================================================

func _show_draft() -> void:
	ui_mode = UiMode.DRAFT
	if not _draft_begin_sfx_played:
		_draft_begin_sfx_played = true
		_play_sfx(DRAFT_BEGIN_SFX)
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

	# Display only: the "Keep this recipe" button below is the actual
	# action trigger, so drafting stays a single deliberate tap rather
	# than an easy-to-fumble tap on a small card image.
	var card := RecipeCardFace.new()
	card.setup(offer["display_name"], offer["country"], offer["tier_name"], offer["recipe_id"])
	card.disabled = true
	box.add_child(card)

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
		panel.page_changed.connect(_on_player_panel_page_changed)
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
						"def_id": att["def_id"],
						"stealable": steal_action != null,
					})
				var page: int = _player_card_page.get("%d:%d" % [p.index, ri], 0)
				recipe_rows.append({"recipe_index": ri, "cards": cards, "page": page})

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
			"def_id": top.def_id,
		}
	var discard_takeable := _has_action_type(legal, Action.Type.TAKE_DISCARD)
	table_surface.update_piles(state.deck.size(), state.discard_pile.size(), top_discard, discard_takeable)

	_clear_children(table_surface.own_recipes_box)
	_own_recipe_panel_nodes.clear()
	var player := state.players[_viewer_index()]
	for ri in player.recipes.size():
		var panel := _build_own_recipe_panel(player.recipes[ri], ri, legal)
		_own_recipe_panel_nodes[ri] = panel
		table_surface.own_recipes_box.add_child(panel)

const RECIPE_PANEL_WIDTH := 300.0
const RECIPE_PANEL_PADDING := 20.0 # PanelContainer content margin, both sides
const RECIPE_SLOT_COLUMNS := 2
const RECIPE_SLOT_H_SEPARATION := 8.0
## Each slot label/button is told this width up front (rather than letting
## the grid negotiate it) because a WORD_SMART-autowrap Label under-reports
## its own minimum height until it already knows how wide it'll be -- without
## this, a long name like "Island Spice Blend" wrapping to 2 lines wouldn't
## be accounted for until after layout, and the panel would report itself
## shorter than its actual rendered content, spilling text past its own
## drawn border.
const RECIPE_SLOT_COLUMN_WIDTH := (RECIPE_PANEL_WIDTH - RECIPE_PANEL_PADDING - RECIPE_SLOT_H_SEPARATION) / RECIPE_SLOT_COLUMNS
## A rough per-row budget (label height + v_separation), used only to decide
## whether a recipe's slot grid needs to scroll -- see the ScrollContainer
## in _build_own_recipe_panel(). Doesn't need to be exact: an ordinary
## recipe sits well under RECIPE_GRID_MAX_HEIGHT either way, and a slight
## overestimate on an edge case just means it scrolls a little sooner than
## strictly necessary, never later.
const RECIPE_SLOT_ROW_HEIGHT_ESTIMATE := 25.0
const RECIPE_GRID_MAX_HEIGHT := 170.0

func _build_own_recipe_panel(recipe: Recipe, ri: int, legal: Array) -> Control:
	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(RECIPE_PANEL_WIDTH, 0)
	outer.mouse_default_cursor_shape = Control.CURSOR_ARROW

	var attach_action: Action = null
	if selected_card_id != -1 and _pending_joker_choices.is_empty():
		attach_action = _find_attach_action(legal, selected_card_id, ri)

	var move_action: Action = null
	if selected_move_prep_id != -1:
		move_action = _find_move_preparation_action(legal, selected_move_prep_id, ri)

	# outer.gui_input (not a Button wrapping the content) so this panel's own
	# reported minimum size always comes from its real content (art + title +
	# slot grid) the normal PanelContainer way -- a Button doesn't propagate
	# an anchored child's natural size up to its own minimum size, which
	# previously meant a highlighted (legal-target) panel could report itself
	# far shorter than its actual content and spill past its own bottom edge.
	if attach_action != null:
		outer.theme_type_variation = "DecoyTargetHighlight" if attach_action.as_decoy else "LegalTargetHighlight"
		outer.mouse_filter = Control.MOUSE_FILTER_STOP
		outer.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		outer.gui_input.connect(_on_recipe_panel_gui_input.bind(ri, outer, false))
	elif move_action != null:
		outer.theme_type_variation = "LegalTargetHighlight"
		outer.mouse_filter = Control.MOUSE_FILTER_STOP
		outer.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		outer.gui_input.connect(_on_recipe_panel_gui_input.bind(ri, outer, true))
	else:
		outer.theme_type_variation = "RecipePanelComplete" if recipe.completed else "RecipePanel"

	# TightVBox (2px separation), not the 6px VBoxContainer default: with the
	# table no longer scrolling, every row this panel's own height needs
	# beyond what's actually available pushes it past the felt board's
	# bottom edge.
	var box := VBoxContainer.new()
	box.theme_type_variation = "TightVBox"
	outer.add_child(box)

	var art := CardArtPlaceholder.new()
	art.category_key = "recipe"
	art.custom_minimum_size = Vector2(0, 28)
	box.add_child(art)

	var title := Label.new()
	title.theme_type_variation = "RecipeTitleLabel"
	title.text = GameViewModel.recipe_title(recipe.def) + (", COMPLETE" if recipe.completed else "")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	# Two columns instead of one long stacked list: a Feast dish's 9 rows
	# (6 ingredients + 2 preparations + grill) in a single column ran the
	# panel's content taller than it reported itself, given the Label
	# under-reporting issue above -- splitting into a grid roughly halves
	# the row count.
	var grid := GridContainer.new()
	grid.columns = RECIPE_SLOT_COLUMNS
	grid.add_theme_constant_override("h_separation", int(RECIPE_SLOT_H_SEPARATION))
	grid.add_theme_constant_override("v_separation", 2)

	# A safety net, not the normal case: an ordinary recipe's grid sits well
	# under RECIPE_GRID_MAX_HEIGHT and this ScrollContainer just holds it at
	# its natural size, no visible scrollbar. Only a genuinely oversized
	# recipe (Awaze Tibs' 13 slots is the current worst case) hits the cap
	# and scrolls -- containment instead of the panel spilling past the
	# table's felt edge and overlapping the prompt bar below it, which is
	# what happened before this existed (see hand_fan's own 1.5x size
	# increase in _on_screen_resized() for why there's less slack than
	# there used to be).
	var grid_scroll := ScrollContainer.new()
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var slots := GameViewModel.own_recipe_slots(recipe, db)
	var estimated_rows := ceili(slots.size() / float(RECIPE_SLOT_COLUMNS))
	grid_scroll.custom_minimum_size.y = minf(estimated_rows * RECIPE_SLOT_ROW_HEIGHT_ESTIMATE, RECIPE_GRID_MAX_HEIGHT)
	box.add_child(grid_scroll)
	grid_scroll.add_child(grid)

	# A filled preparation slot is its own click target (to pick it up for
	# MOVE_PREPARATION) whenever this whole panel isn't already a click
	# target itself (see outer.gui_input above -- a nested click target
	# inside another would be ambiguous) and no hand card is currently
	# selected.
	var preps_selectable := attach_action == null and move_action == null and selected_card_id == -1 and not recipe.completed
	for slot in slots:
		if preps_selectable and not slot["is_ingredient"] and slot["filled"] and slot["card_instance_id"] != -1:
			var prep_card_id: int = slot["card_instance_id"]
			var row_btn := Button.new()
			row_btn.theme_type_variation = "RecipeSlotFilledButtonSelected" if prep_card_id == selected_move_prep_id else "RecipeSlotFilledButton"
			row_btn.text = "[x] " + slot["label"]
			row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row_btn.custom_minimum_size.x = RECIPE_SLOT_COLUMN_WIDTH
			row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_btn.pressed.connect(_on_prep_slot_clicked.bind(prep_card_id))
			grid.add_child(row_btn)
		else:
			var row := Label.new()
			row.theme_type_variation = "RecipeSlotFilledLabel" if slot["filled"] else "RecipeSlotEmptyLabel"
			row.text = ("[x] " if slot["filled"] else "[ ] ") + slot["label"]
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.custom_minimum_size.x = RECIPE_SLOT_COLUMN_WIDTH
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(row)

	return outer

func _on_recipe_panel_gui_input(event: InputEvent, recipe_index: int, panel_node: Control, is_move: bool) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if is_move:
			_on_move_target_pressed(recipe_index, panel_node)
		else:
			_on_recipe_target_pressed(recipe_index, panel_node)

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

	if not _pending_joker_choices.is_empty():
		var card := state.players[_viewer_index()].find_in_hand(selected_card_id)
		var card_name := GameViewModel.card_label(card.def_id, card.category, db) if card != null else "that card"
		prompt_label.text = "Selected %s, choose which ingredient it stands in for" % card_name

		for a in _pending_joker_choices:
			var choice_btn := Button.new()
			choice_btn.theme_type_variation = "PrimaryButtonCompact"
			choice_btn.text = GameViewModel.card_label(a.target_def_id, CardDef.Category.INGREDIENT, db)
			choice_btn.pressed.connect(_on_joker_slot_chosen.bind(a))
			prompt_buttons_box.add_child(choice_btn)

		var joker_cancel_btn := Button.new()
		joker_cancel_btn.theme_type_variation = "SecondaryButton"
		joker_cancel_btn.text = "Cancel"
		joker_cancel_btn.pressed.connect(_on_cancel_selection_pressed)
		prompt_buttons_box.add_child(joker_cancel_btn)
		return

	if selected_move_prep_id != -1:
		var player := state.players[_viewer_index()]
		var prep_card: Card = null
		for recipe in player.recipes:
			prep_card = recipe.find_attached_card(selected_move_prep_id)
			if prep_card != null:
				break
		var prep_name := GameViewModel.card_label(prep_card.def_id, prep_card.category, db) if prep_card != null else "that preparation"
		prompt_label.text = "Selected %s, click a glowing recipe to move it there" % prep_name

		var move_cancel_btn := Button.new()
		move_cancel_btn.theme_type_variation = "SecondaryButton"
		move_cancel_btn.text = "Cancel"
		move_cancel_btn.pressed.connect(_on_cancel_move_pressed)
		prompt_buttons_box.add_child(move_cancel_btn)
		return

	if selected_card_id != -1:
		var card := state.players[_viewer_index()].find_in_hand(selected_card_id)
		var card_name := GameViewModel.card_label(card.def_id, card.category, db) if card != null else "that card"
		prompt_label.text = "Selected %s, click a glowing recipe to attach it, or discard it" % card_name

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
		draw_btn.theme_type_variation = "PrimaryButtonCompact"
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

	if _has_action_type(legal, Action.Type.MOVE_PREPARATION):
		var move_hint := Label.new()
		move_hint.theme_type_variation = "HintLabel"
		move_hint.text = "or click a preparation on one of your recipes to move it to another"
		prompt_buttons_box.add_child(move_hint)

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
	selected_move_prep_id = -1
	_pending_joker_choices = []
	selected_card_id = -1 if selected_card_id == instance_id else instance_id
	_refresh_play_view()

func _on_cancel_selection_pressed() -> void:
	selected_card_id = -1
	_pending_joker_choices = []
	_refresh_play_view()

func _on_prep_slot_clicked(card_instance_id: int) -> void:
	selected_card_id = -1
	_pending_joker_choices = []
	selected_move_prep_id = -1 if selected_move_prep_id == card_instance_id else card_instance_id
	_refresh_play_view()

func _on_cancel_move_pressed() -> void:
	selected_move_prep_id = -1
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
	CardAnimator.fly(animation_layer, from, to, label, cat, "draw", top.def_id)

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
	CardAnimator.fly(animation_layer, from, to, label, cat, "steal", card.def_id if card != null else "")

	var line := GameViewModel.describe_action_for_log(state, action)
	selected_card_id = -1
	_submit_action(action)
	if not is_network_mode:
		_append_log_line(line)

## Purely a display preference (which page of an opponent's overflowing
## recipe row is showing), not game state -- no action to submit, just
## remember the page and rebuild the top bar with it applied.
func _on_player_panel_page_changed(target_player_index: int, recipe_index: int, new_page: int) -> void:
	_player_card_page["%d:%d" % [target_player_index, recipe_index]] = new_page
	_render_top_bar(session.get_legal_actions())

func _on_recipe_target_pressed(recipe_index: int, panel_node: Control) -> void:
	var legal := session.get_legal_actions()
	var matches := _find_attach_actions(legal, selected_card_id, recipe_index)
	if matches.is_empty():
		return

	# A joker matching more than one open slot on this recipe (e.g. a
	# Vegetable Joker against a recipe needing both tomato and onion) can't
	# be resolved to a single action yet -- ask which slot via the prompt
	# bar (see _render_prompt_bar's _pending_joker_choices branch) instead
	# of guessing.
	if matches.size() > 1:
		_pending_joker_choices = matches
		_refresh_play_view()
		return

	_apply_attach_action(matches[0], panel_node)

func _on_joker_slot_chosen(action: Action) -> void:
	var panel_node: Control = _own_recipe_panel_nodes.get(action.recipe_index)
	_pending_joker_choices = []
	_apply_attach_action(action, panel_node)

func _apply_attach_action(action: Action, panel_node: Control) -> void:
	var player := state.players[_viewer_index()]
	var card := player.find_in_hand(action.card_instance_id)
	var label := GameViewModel.card_label(card.def_id, card.category, db) if card != null else ""
	var cat := CardCategoryMap.category_for(card.def_id, card.category) if card != null else CardCategoryMap.PANTRY

	var from := hand_fan.get_card_global_position(action.card_instance_id)
	var to: Vector2 = (panel_node.global_position + panel_node.size * 0.5) if panel_node != null else from
	CardAnimator.fly(animation_layer, from, to, label, cat, "attach", card.def_id if card != null else "")

	var line := GameViewModel.describe_action_for_log(state, action)
	selected_card_id = -1
	_submit_action(action)
	if not is_network_mode:
		_append_log_line(line)

func _on_move_target_pressed(recipe_index: int, panel_node: Control) -> void:
	var legal := session.get_legal_actions()
	var action := _find_move_preparation_action(legal, selected_move_prep_id, recipe_index)
	if action == null:
		return

	var player := state.players[_viewer_index()]
	var from_panel: Control = _own_recipe_panel_nodes.get(action.recipe_index)
	var card := player.recipes[action.recipe_index].find_attached_card(selected_move_prep_id)
	var label := GameViewModel.card_label(card.def_id, card.category, db) if card != null else ""
	var cat := CardCategoryMap.category_for(card.def_id, card.category) if card != null else CardCategoryMap.PREPARATION

	var from: Vector2 = (from_panel.global_position + from_panel.size * 0.5) if from_panel != null else get_global_rect().get_center()
	var to: Vector2 = panel_node.global_position + panel_node.size * 0.5
	CardAnimator.fly(animation_layer, from, to, label, cat, "attach", card.def_id if card != null else "")

	var line := GameViewModel.describe_action_for_log(state, action)
	selected_move_prep_id = -1
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
	CardAnimator.fly(animation_layer, from, to, label, cat, "discard", card.def_id if card != null else "")

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

	# The winning dish(es), as a lasting trophy on this screen -- the
	# recipe-reveal overlay already showed this in full (ingredients,
	# steps) the moment it was completed, so this is a compact reminder,
	# not a repeat of that whole reveal.
	for recipe in _winning_recipes():
		var view := GameViewModel.real_recipe_view(recipe.def.id, db)
		var card := RecipeCardFace.new()
		card.setup(view["display_name"], view["country"], view["tier_name"], view["recipe_id"])
		card.disabled = true
		box.add_child(card)

	var new_game_button := Button.new()
	new_game_button.theme_type_variation = "PrimaryButton"
	new_game_button.text = "New game"
	new_game_button.custom_minimum_size = Vector2(220, 0)
	new_game_button.pressed.connect(_on_new_game_pressed)
	box.add_child(new_game_button)

	_apply_overlay_visibility()

## The recipe(s) that won the game: the winner's own completed recipe in
## free-for-all mode, or each teammate's completed recipe in team mode
## (win_on_both_recipes requires every partner to have finished one).
func _winning_recipes() -> Array[Recipe]:
	var out: Array[Recipe] = []
	if state.winner_player_index >= 0:
		var rec := state.players[state.winner_player_index].completed_recipe()
		if rec != null:
			out.append(rec)
	elif state.winner_team_id >= 0:
		for p in state.players:
			if p.team_id != state.winner_team_id:
				continue
			var rec := p.completed_recipe()
			if rec != null:
				out.append(rec)
	return out

func _on_new_game_pressed() -> void:
	if is_network_mode:
		_do_leave_network_game()
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

## Every legal ATTACH for this (card, recipe) pair -- ordinarily at most one,
## but a joker can match more than one open slot on the same recipe (see
## RulesEngine._add_joker_attach_actions), which is exactly the ambiguity
## _on_recipe_target_pressed needs to detect.
func _find_attach_actions(legal: Array, card_instance_id: int, recipe_index: int) -> Array[Action]:
	var out: Array[Action] = []
	for a in legal:
		if a.type == Action.Type.ATTACH and a.card_instance_id == card_instance_id and a.recipe_index == recipe_index:
			out.append(a)
	return out

func _find_move_preparation_action(legal: Array, card_instance_id: int, to_recipe_index: int) -> Action:
	for a in legal:
		if a.type == Action.Type.MOVE_PREPARATION and a.card_instance_id == card_instance_id and a.move_to_recipe_index == to_recipe_index:
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
	main_menu_overlay.visible = ui_mode == UiMode.MAIN_MENU
	how_to_play_overlay.visible = ui_mode == UiMode.HOW_TO_PLAY
	settings_overlay.visible = ui_mode == UiMode.SETTINGS
	story_overlay.visible = ui_mode == UiMode.STORY
	setup_overlay.visible = ui_mode == UiMode.SETUP
	network_setup_overlay.visible = ui_mode == UiMode.NETWORK_SETUP
	lobby_overlay.visible = ui_mode == UiMode.LOBBY
	pass_overlay.visible = ui_mode == UiMode.PASS_DEVICE
	draft_overlay.visible = ui_mode == UiMode.DRAFT
	ai_thinking_overlay.visible = ui_mode == UiMode.AI_THINKING
	recipe_reveal_overlay.visible = ui_mode == UiMode.RECIPE_REVEAL
	gameover_overlay.visible = ui_mode == UiMode.GAME_OVER
	reconnecting_overlay.visible = ui_mode == UiMode.RECONNECTING
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE if ui_mode == UiMode.PLAY else Control.MOUSE_FILTER_STOP
	main_layout.visible = ui_mode == UiMode.PLAY
	# hand_fan is a sibling of outer_margin now, not a child of main_layout
	# (see _build_static_ui()) -- the line above no longer covers it, so
	# it has to be hidden here explicitly on the same condition, or it
	# stays visible through every non-PLAY screen (AI thinking, draft,
	# menus, ...) instead of only showing during actual play.
	hand_fan.visible = ui_mode == UiMode.PLAY

	var game_in_progress := ui_mode in [UiMode.DRAFT, UiMode.PLAY, UiMode.AI_THINKING, UiMode.RECIPE_REVEAL]
	leave_game_button.visible = is_network_mode and game_in_progress

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

extends SceneTree
## Headless simulation harness entry point.
##
## Run with:
##   godot --headless --script res://sim/run_sim.gd -- --games=2000 --seed=1
##
## Everything after the lone "--" is a Manze Lakaz flag, not a Godot flag.
## Recognized flags (all optional):
##   --games=N              games per (player_count x bot_profile) segment [2000]
##   --players=2,3,4         comma list of player counts to simulate       [2,3,4]
##   --seed=N                base RNG seed; each game gets seed+i          [12345]
##   --seconds_per_turn=N    used only to convert turns -> minutes         [12]
##   --decoys=true|false     DECOYS_ENABLED                                [false]
##   --hand_limit=N          HAND_LIMIT                                    [7]
##   --win_on_both=true|false WIN_ON_BOTH_RECIPES (2v2 team mode)          [false]
##   --draft_pool_size=N     DRAFT_POOL_SIZE                               [3]
##   --recipes_per_player=N  RECIPES_PER_PLAYER                            [2]
##   --max_steals=N          MAX_STEALS_PER_PLAYER                         [4]
##   --out=res://path.csv    where to write the CSV report                 [res://sim/output/sim_report.csv]
## This script extends SceneTree only because Godot requires that to run a
## headless entry point; it contains no game logic, only orchestration.

const DATA_DIR := "res://data"
const DEFAULT_OUTPUT_CSV := "res://sim/output/sim_report.csv"
const BOT_PROFILES := ["random", "heuristic"]

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())

	var games_per_segment: int = int(args.get("games", "2000"))
	var base_seed: int = int(args.get("seed", "12345"))
	var seconds_per_turn: float = float(args.get("seconds_per_turn", "12"))
	var decoys_enabled: bool = args.get("decoys", "false") == "true"
	var hand_limit: int = int(args.get("hand_limit", "7"))
	var win_on_both: bool = args.get("win_on_both", "false") == "true"
	var draft_pool_size: int = int(args.get("draft_pool_size", "3"))
	var recipes_per_player: int = int(args.get("recipes_per_player", "2"))
	var max_steals_per_player: int = int(args.get("max_steals", "4"))
	var out_path: String = args.get("out", DEFAULT_OUTPUT_CSV)

	var player_counts: Array[int] = []
	for s in String(args.get("players", "2,3,4")).split(","):
		player_counts.append(int(s))

	var db := DataLoader.load_database_or_fail(
		DATA_DIR + "/ingredients.json",
		DATA_DIR + "/preparations.json",
		DATA_DIR + "/recipes.json"
	)
	if db == null:
		quit(1)
		return

	print("Manze Lakaz simulator: %d games/segment, seed base %d, %s decoys, hand_limit %d, win_on_both %s" % [
		games_per_segment, base_seed, ("with" if decoys_enabled else "without"), hand_limit, str(win_on_both)
	])

	var all_results: Dictionary = {} # "<num_players>_<profile>" -> Array[GameResult]
	var seed_counter := base_seed

	for num_players in player_counts:
		for profile in BOT_PROFILES:
			var results: Array[GameResult] = []
			for g in games_per_segment:
				var config := GameConfig.new()
				config.num_players = num_players
				config.decoys_enabled = decoys_enabled
				config.hand_limit = hand_limit
				config.win_on_both_recipes = win_on_both
				config.draft_pool_size = draft_pool_size
				config.recipes_per_player = recipes_per_player
				config.max_steals_per_player = max_steals_per_player
				config.seconds_per_turn = seconds_per_turn
				config.seed = seed_counter
				seed_counter += 1

				var bots: Array[Bot] = []
				for i in num_players:
					bots.append(RandomBot.new() if profile == "random" else HeuristicBot.new())

				results.append(GameRunner.play_game(config, db, bots))

			all_results["%d_%s" % [num_players, profile]] = results
			print(SimAggregator.format_segment_report(num_players, profile, results, seconds_per_turn, db))

	var out_dir := out_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	SimAggregator.write_csv(out_path, all_results, seconds_per_turn, db)
	print("\nCSV report written to: %s" % out_path)

	quit(0)

func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
			else:
				out[kv[0]] = "true"
	return out

class_name SimAggregator
extends RefCounted
## Turns a batch of GameResults into summary statistics, a human-readable
## report, and a tidy-format CSV suitable for charting.

static func compute_stats(results: Array[GameResult], db: CardDatabase) -> Dictionary:
	var turns: Array = []
	var seat_wins: Dictionary = {}
	var recipe_wins: Dictionary = {}
	var recipe_turns_sum: Dictionary = {}
	var tier_wins: Dictionary = {}
	var slot_wins: Dictionary = {}
	var steals: Array = []
	var reshuffles: Array = []
	var starvation: Array = []
	var starved_by_def: Dictionary = {}
	var capped_count := 0
	var decisive_count := 0

	for r in results:
		steals.append(r.steal_count)
		reshuffles.append(r.reshuffle_count)
		starvation.append(r.starvation_events)
		for def_id in r.starvation_by_def.keys():
			starved_by_def[def_id] = starved_by_def.get(def_id, 0) + r.starvation_by_def[def_id]

		if r.capped:
			capped_count += 1
			continue
		decisive_count += 1
		# Turn-length stats (mean/median/p10/p90) are computed over decisive
		# games only. Blending in turn-capped stalemates at their arbitrary
		# cap value would make "median turns" mostly reflect the cap, not
		# actual game pacing.
		turns.append(r.total_turns)

		if r.winner_seat >= 0:
			seat_wins[r.winner_seat] = seat_wins.get(r.winner_seat, 0) + 1

		if r.winning_recipe_id != "":
			recipe_wins[r.winning_recipe_id] = recipe_wins.get(r.winning_recipe_id, 0) + 1
			recipe_turns_sum[r.winning_recipe_id] = recipe_turns_sum.get(r.winning_recipe_id, 0) + r.total_turns
			slot_wins[r.winning_recipe_slot] = slot_wins.get(r.winning_recipe_slot, 0) + 1
			if db.recipe_defs.has(r.winning_recipe_id):
				var tier_name: String = db.recipe_defs[r.winning_recipe_id].tier_name()
				tier_wins[tier_name] = tier_wins.get(tier_name, 0) + 1

	turns.sort()

	return {
		"count": results.size(),
		"decisive_count": decisive_count,
		"capped_count": capped_count,
		"turns_mean": _mean(turns),
		"turns_median": _percentile(turns, 0.5),
		"turns_p10": _percentile(turns, 0.10),
		"turns_p90": _percentile(turns, 0.90),
		"seat_wins": seat_wins,
		"recipe_wins": recipe_wins,
		"recipe_turns_sum": recipe_turns_sum,
		"tier_wins": tier_wins,
		"slot_wins": slot_wins,
		"steals_mean": _mean(steals),
		"reshuffles_mean": _mean(reshuffles),
		"starvation_mean": _mean(starvation),
		"starved_by_def": starved_by_def,
	}

static func format_segment_report(num_players: int, profile: String, results: Array[GameResult], seconds_per_turn: float, db: CardDatabase) -> String:
	var stats := compute_stats(results, db)
	var decisive: int = stats["decisive_count"]
	var lines: Array[String] = []

	var capped_rate: float = 100.0 * stats["capped_count"] / float(max(1, stats["count"]))

	lines.append("")
	lines.append("==== %d players | %s bots | %d games (%d decisive, %d hit turn cap = %.1f%%) ====" % [num_players, profile, stats["count"], decisive, stats["capped_count"], capped_rate])
	if decisive == 0:
		lines.append("No games finished within the turn cap -- turn-length stats below are undefined (n=0 decisive games).")
	lines.append("Turns/game (decisive only) -> mean %.1f | median %.1f | p10 %.1f | p90 %.1f" % [stats["turns_mean"], stats["turns_median"], stats["turns_p10"], stats["turns_p90"]])
	lines.append("Est. minutes @%ds/turn -> mean %.1f | median %.1f | p10 %.1f | p90 %.1f" % [
		int(seconds_per_turn),
		stats["turns_mean"] * seconds_per_turn / 60.0,
		stats["turns_median"] * seconds_per_turn / 60.0,
		stats["turns_p10"] * seconds_per_turn / 60.0,
		stats["turns_p90"] * seconds_per_turn / 60.0,
	])
	lines.append("Steals/game mean %.2f | Reshuffles/game mean %.2f | Starvation events/game mean %.2f" % [stats["steals_mean"], stats["reshuffles_mean"], stats["starvation_mean"]])

	lines.append("Win rate by seat:")
	for seat in range(num_players):
		var w: int = stats["seat_wins"].get(seat, 0)
		var rate: float = 100.0 * w / float(max(1, decisive))
		lines.append("  seat %d: %5.1f%% (%d wins)" % [seat, rate, w])

	lines.append("Win rate by tier:")
	for tier in ["quick", "feast"]:
		var w: int = stats["tier_wins"].get(tier, 0)
		var rate: float = 100.0 * w / float(max(1, decisive))
		lines.append("  %s: %5.1f%% (%d wins)" % [tier, rate, w])

	lines.append("Which recipe slot won: slot0 %d | slot1 %d" % [stats["slot_wins"].get(0, 0), stats["slot_wins"].get(1, 0)])

	lines.append("Win rate by recipe:")
	var recipe_ids: Array = stats["recipe_wins"].keys()
	recipe_ids.sort()
	for rid in recipe_ids:
		var w: int = stats["recipe_wins"][rid]
		var rate: float = 100.0 * w / float(max(1, decisive))
		var avg_turns := float(stats["recipe_turns_sum"][rid]) / w
		lines.append("  %-20s %5.1f%% (%d wins, avg %.1f turns when won)" % [rid, rate, w, avg_turns])

	if not stats["starved_by_def"].is_empty():
		lines.append("Bottleneck check - starvation events by card type (most starved first):")
		var defs: Array = stats["starved_by_def"].keys()
		var starved_dict: Dictionary = stats["starved_by_def"]
		defs.sort_custom(func(a, b): return starved_dict[a] > starved_dict[b])
		for d in defs:
			lines.append("  %-20s %d events" % [d, starved_dict[d]])

	return "\n".join(lines)

static func write_csv(path: String, all_results: Dictionary, seconds_per_turn: float, db: CardDatabase) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("SimAggregator.write_csv: could not open %s for writing (error %d)" % [path, FileAccess.get_open_error()])
		return

	f.store_line("num_players,bot_profile,category,key,value")

	var seg_keys: Array = all_results.keys()
	seg_keys.sort()
	for seg_key in seg_keys:
		var parts: PackedStringArray = seg_key.split("_", true, 1)
		var num_players := int(parts[0])
		var profile := parts[1]
		var results: Array[GameResult] = all_results[seg_key]
		var stats := compute_stats(results, db)
		var decisive: int = stats["decisive_count"]

		_row(f, num_players, profile, "summary", "games", stats["count"])
		_row(f, num_players, profile, "summary", "capped_rate_pct", 100.0 * stats["capped_count"] / float(max(1, stats["count"])))
		_row(f, num_players, profile, "summary", "decisive_games", decisive)
		_row(f, num_players, profile, "summary", "capped_games", stats["capped_count"])
		_row(f, num_players, profile, "summary", "turns_mean", stats["turns_mean"])
		_row(f, num_players, profile, "summary", "turns_median", stats["turns_median"])
		_row(f, num_players, profile, "summary", "turns_p10", stats["turns_p10"])
		_row(f, num_players, profile, "summary", "turns_p90", stats["turns_p90"])
		_row(f, num_players, profile, "summary", "minutes_mean", stats["turns_mean"] * seconds_per_turn / 60.0)
		_row(f, num_players, profile, "summary", "minutes_median", stats["turns_median"] * seconds_per_turn / 60.0)
		_row(f, num_players, profile, "summary", "minutes_p10", stats["turns_p10"] * seconds_per_turn / 60.0)
		_row(f, num_players, profile, "summary", "minutes_p90", stats["turns_p90"] * seconds_per_turn / 60.0)
		_row(f, num_players, profile, "summary", "steals_mean", stats["steals_mean"])
		_row(f, num_players, profile, "summary", "reshuffles_mean", stats["reshuffles_mean"])
		_row(f, num_players, profile, "summary", "starvation_mean", stats["starvation_mean"])

		for seat in stats["seat_wins"].keys():
			var w: int = stats["seat_wins"][seat]
			_row(f, num_players, profile, "seat_win_rate", str(seat), 100.0 * w / max(1, decisive))

		for rid in stats["recipe_wins"].keys():
			var w: int = stats["recipe_wins"][rid]
			_row(f, num_players, profile, "recipe_win_rate", rid, 100.0 * w / max(1, decisive))
			_row(f, num_players, profile, "recipe_avg_turns", rid, float(stats["recipe_turns_sum"][rid]) / w)

		for tier in stats["tier_wins"].keys():
			var w: int = stats["tier_wins"][tier]
			_row(f, num_players, profile, "tier_win_rate", tier, 100.0 * w / max(1, decisive))

		for slot in stats["slot_wins"].keys():
			var w: int = stats["slot_wins"][slot]
			_row(f, num_players, profile, "slot_win_rate", "slot" + str(slot), 100.0 * w / max(1, decisive))

		for def_id in stats["starved_by_def"].keys():
			_row(f, num_players, profile, "starvation_by_card", def_id, stats["starved_by_def"][def_id])

	f.close()

static func _row(f: FileAccess, num_players: int, profile: String, category: String, key, value) -> void:
	f.store_line("%d,%s,%s,%s,%s" % [num_players, profile, category, str(key), str(value)])

static func _mean(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var s := 0.0
	for v in vals:
		s += v
	return s / vals.size()

static func _percentile(sorted_vals: Array, p: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx := p * (sorted_vals.size() - 1)
	var lo := int(floor(idx))
	var hi := int(ceil(idx))
	if lo == hi:
		return float(sorted_vals[lo])
	var frac := idx - lo
	return float(sorted_vals[lo]) * (1.0 - frac) + float(sorted_vals[hi]) * frac

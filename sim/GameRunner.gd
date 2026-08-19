class_name GameRunner
extends RefCounted
## Drives one game to completion (or to a turn cap, as a deadlock safety
## net) by repeatedly asking the current player's bot to pick from
## RulesEngine.get_legal_actions() and applying it.

static func play_game(config: GameConfig, database: CardDatabase, bots: Array[Bot], max_turns: int = 2000) -> GameResult:
	var state := RulesEngine.new_game(config, database)
	var result := GameResult.new()
	result.num_players = config.num_players
	result.seed = config.seed

	if state == null:
		result.capped = true
		return result

	while not state.game_over and state.turn_number <= max_turns:
		var player_idx := state.current_player_index

		if state.phase == GameState.Phase.TAKE:
			var player: Player = state.players[player_idx]
			var starved := RulesEngine.detect_starved_needs(state, player)
			if not starved.is_empty():
				state.starvation_events += starved.size()
				for def_id in starved:
					state.starvation_by_def[def_id] = state.starvation_by_def.get(def_id, 0) + 1

		var legal := RulesEngine.get_legal_actions(state)
		if legal.is_empty():
			break # deadlock safety net; should not happen under the rules as specified

		var bot: Bot = bots[player_idx]
		var action := bot.choose_action(state, legal)
		if action == null:
			break

		RulesEngine.apply_action(state, action)

	result.capped = not state.game_over
	result.total_turns = state.turn_number if state.game_over else max_turns
	result.steal_count = state.steal_count
	result.reshuffle_count = state.reshuffle_count
	result.starvation_events = state.starvation_events
	result.starvation_by_def = state.starvation_by_def

	if state.game_over:
		result.winner_team_id = state.winner_team_id
		result.winner_player_index = state.winner_player_index
		if state.winner_player_index >= 0:
			var wp: Player = state.players[state.winner_player_index]
			result.winner_seat = state.winner_player_index
			var rec := wp.completed_recipe()
			if rec != null:
				result.winning_recipe_id = rec.def.id
				result.winning_recipe_slot = wp.recipes.find(rec)

	return result

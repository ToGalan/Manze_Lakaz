class_name RandomBot
extends Bot
## Picks uniformly at random among all legal actions. Uses the game's own
## RNG stream so a whole game (rules + bot decisions) stays reproducible
## from a single seed.

func choose_action(state: GameState, legal_actions: Array[Action]) -> Action:
	if legal_actions.is_empty():
		return null
	var idx := state.rng.randi_range(0, legal_actions.size() - 1)
	return legal_actions[idx]

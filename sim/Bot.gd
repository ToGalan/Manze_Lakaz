class_name Bot
extends RefCounted
## Interface for a policy that plays one game. Bots live in sim/, not core/:
## they are simulation players, never part of the rules engine itself.

func choose_action(state: GameState, legal_actions: Array[Action]) -> Action:
	push_error("Bot.choose_action is abstract; use a subclass such as RandomBot or HeuristicBot")
	return null

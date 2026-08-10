class_name RulesEngine
extends RefCounted
## The whole rules engine. Stateless: every function takes the GameState it
## operates on explicitly. get_legal_actions() is the only source of truth
## for what a player may do; apply_action() is the only way state changes,
## and it re-validates against get_legal_actions() before doing anything.

# ===========================================================================
# Setup
# ===========================================================================

## Builds a game up through the point where the draft begins: teams are
## assigned, each player's draft_pool_size-card offer is shuffled out, and
## the deck is shuffled (but not yet dealt -- that happens once every player
## has finished drafting, in _finish_draft()). The draft itself is played
## out through ordinary get_legal_actions()/apply_action() calls, same as
## the rest of the game; the caller drives it, RulesEngine does not.
static func new_game(config: GameConfig, database: CardDatabase) -> GameState:
	var needed := config.num_players * config.draft_pool_size
	if needed > database.recipe_order.size():
		push_error("RulesEngine.new_game: %d players x draft_pool_size %d = %d, but only %d recipes exist" % [config.num_players, config.draft_pool_size, needed, database.recipe_order.size()])
		return null
	if config.recipes_per_player > config.draft_pool_size:
		push_error("RulesEngine.new_game: recipes_per_player (%d) cannot exceed draft_pool_size (%d)" % [config.recipes_per_player, config.draft_pool_size])
		return null

	var state := GameState.new(config, database)

	for i in config.num_players:
		state.players.append(Player.new(i))

	_assign_teams(state)
	_offer_draft(state)

	state.deck = database.build_deck()
	_shuffle(state, state.deck)

	state.current_player_index = 0
	state.phase = GameState.Phase.DRAFT
	state.turn_number = 1
	return state

static func _assign_teams(state: GameState) -> void:
	if state.config.win_on_both_recipes and state.players.size() == 4:
		state.players[0].team_id = 0
		state.players[2].team_id = 0
		state.players[1].team_id = 1
		state.players[3].team_id = 1
	else:
		for i in state.players.size():
			state.players[i].team_id = i

static func _offer_draft(state: GameState) -> void:
	var pool: Array[String] = state.database.recipe_order.duplicate()
	_shuffle(state, pool)
	var pool_size: int = state.config.draft_pool_size
	state.draft_offers = []
	for player in state.players:
		var offer: Array[String] = []
		for i in pool_size:
			offer.append(pool.pop_back())
		state.draft_offers.append(offer)

## Called once the last player has kept their final drafted recipe: deals
## hands and starts turn 1.
static func _finish_draft(state: GameState) -> void:
	_deal_hands(state)
	state.current_player_index = 0
	state.phase = GameState.Phase.TAKE
	state.turn_number = 1

static func _deal_hands(state: GameState) -> void:
	for player in state.players:
		for i in 7:
			player.hand.append(state.deck.pop_back())

static func _shuffle(state: GameState, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = state.rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ===========================================================================
# Legal actions
# ===========================================================================

static func get_legal_actions(state: GameState) -> Array[Action]:
	var actions: Array[Action] = []
	if state.game_over:
		return actions

	var pidx := state.current_player_index
	var player: Player = state.players[pidx]

	match state.phase:
		GameState.Phase.DRAFT:
			_add_draft_actions(state, player, actions)
		GameState.Phase.TAKE:
			_add_take_actions(state, player, actions)
		GameState.Phase.PLAY:
			_add_play_actions(state, player, actions)
		GameState.Phase.HAND_LIMIT:
			for c in player.hand:
				actions.append(Action.make_discard(pidx, c.instance_id))
	return actions

static func _add_draft_actions(state: GameState, player: Player, actions: Array[Action]) -> void:
	var offer: Array = state.draft_offers[player.index]
	for rid in offer:
		actions.append(Action.make_draft_keep(player.index, rid))

static func _add_take_actions(state: GameState, player: Player, actions: Array[Action]) -> void:
	if not state.deck.is_empty() or not state.discard_pile.is_empty():
		actions.append(Action.make_draw(player.index))
	if not state.discard_pile.is_empty():
		actions.append(Action.make_take_discard(player.index))

	if player.steals_used < state.config.max_steals_per_player:
		for other in state.players:
			if other.index == player.index:
				continue
			for ri in other.recipes.size():
				var recipe: Recipe = other.recipes[ri]
				for card in recipe.stealable_ingredient_cards():
					actions.append(Action.make_steal(player.index, other.index, ri, card.instance_id))

static func _add_play_actions(state: GameState, player: Player, actions: Array[Action]) -> void:
	for c in player.hand:
		_add_attach_actions_for_card(state, player, c, actions)
	for c in player.hand:
		actions.append(Action.make_discard(player.index, c.instance_id))

static func _add_attach_actions_for_card(state: GameState, player: Player, card: Card, actions: Array[Action]) -> void:
	for ri in player.recipes.size():
		var recipe: Recipe = player.recipes[ri]
		if recipe.completed:
			continue
		if card.is_ingredient():
			if recipe.is_ingredient_slot_open(card.def_id):
				actions.append(Action.make_attach(player.index, card.instance_id, ri, false))
			elif state.config.decoys_enabled:
				actions.append(Action.make_attach(player.index, card.instance_id, ri, true))
		elif card.is_preparation():
			if recipe.is_preparation_slot_open(card.def_id):
				actions.append(Action.make_attach(player.index, card.instance_id, ri, false))

# ===========================================================================
# Applying actions
# ===========================================================================

static func apply_action(state: GameState, action: Action) -> void:
	if state.game_over:
		push_error("RulesEngine.apply_action: game is already over")
		return
	if action.player_index != state.current_player_index:
		push_error("RulesEngine.apply_action: action is for player %d but it is player %d's turn" % [action.player_index, state.current_player_index])
		return

	var legal := get_legal_actions(state)
	if not _contains_equivalent(legal, action):
		push_error("RulesEngine.apply_action: illegal action attempted: %s" % action.describe())
		return

	match action.type:
		Action.Type.DRAFT_KEEP:
			_apply_draft_keep(state, action)
		Action.Type.DRAW:
			_apply_draw(state, action)
		Action.Type.STEAL:
			_apply_steal(state, action)
		Action.Type.ATTACH:
			_apply_attach(state, action)
		Action.Type.DISCARD:
			_apply_discard(state, action)
		Action.Type.TAKE_DISCARD:
			_apply_take_discard(state, action)

	_advance_phase_if_needed(state)

static func _contains_equivalent(actions: Array[Action], target: Action) -> bool:
	for a in actions:
		if a.equals(target):
			return true
	return false

static func _apply_draft_keep(state: GameState, action: Action) -> void:
	var player := state.players[action.player_index]
	var offer: Array = state.draft_offers[player.index]
	var idx := offer.find(action.recipe_id)
	if idx == -1:
		push_error("RulesEngine._apply_draft_keep: recipe '%s' not offered to P%d" % [action.recipe_id, player.index])
		return
	offer.remove_at(idx)
	player.recipes.append(Recipe.new(state.database.recipe_defs[action.recipe_id]))

static func _apply_draw(state: GameState, action: Action) -> void:
	var player := state.players[action.player_index]
	_ensure_deck_has_card(state)
	if state.deck.is_empty():
		return
	player.hand.append(state.deck.pop_back())

static func _apply_take_discard(state: GameState, action: Action) -> void:
	var player := state.players[action.player_index]
	if state.discard_pile.is_empty():
		push_error("RulesEngine._apply_take_discard: discard pile is empty")
		return
	player.hand.append(state.discard_pile.pop_back())

static func _ensure_deck_has_card(state: GameState) -> void:
	if state.deck.is_empty() and not state.discard_pile.is_empty():
		state.deck = state.discard_pile
		state.discard_pile = []
		_shuffle(state, state.deck)
		state.reshuffle_count += 1

static func _apply_steal(state: GameState, action: Action) -> void:
	var player := state.players[action.player_index]
	var target := state.players[action.target_player_index]
	var recipe: Recipe = target.recipes[action.target_recipe_index]
	var card := recipe.remove_stealable_card(action.card_instance_id)
	if card == null:
		push_error("RulesEngine._apply_steal: card #%d not stealable from P%d recipe#%d" % [action.card_instance_id, target.index, action.target_recipe_index])
		return
	player.hand.append(card)
	player.steals_used += 1
	state.steal_count += 1

static func _apply_attach(state: GameState, action: Action) -> void:
	var player := state.players[action.player_index]
	var recipe: Recipe = player.recipes[action.recipe_index]
	var card := player.remove_from_hand(action.card_instance_id)
	if card == null:
		push_error("RulesEngine._apply_attach: card #%d not in P%d's hand" % [action.card_instance_id, player.index])
		return

	if action.as_decoy:
		recipe.attach_decoy(card)
	elif card.is_ingredient():
		recipe.attach_ingredient_to_slot(card)
	else:
		recipe.attach_preparation_to_slot(card)

	if recipe.completed:
		_handle_recipe_completed(state, player, recipe)

static func _apply_discard(state: GameState, action: Action) -> void:
	var player := state.players[action.player_index]
	var card := player.remove_from_hand(action.card_instance_id)
	if card == null:
		push_error("RulesEngine._apply_discard: card #%d not in P%d's hand" % [action.card_instance_id, player.index])
		return
	state.discard_pile.append(card)

static func _handle_recipe_completed(state: GameState, player: Player, recipe: Recipe) -> void:
	if not state.config.win_on_both_recipes:
		state.winner_player_index = player.index
		state.winner_team_id = player.team_id
		state.game_over = true
		state.phase = GameState.Phase.GAME_OVER
		return

	var team_id := player.team_id
	for p in state.players:
		if p.team_id == team_id and not p.has_completed_recipe():
			return # teammate still short; team hasn't won yet

	state.winner_team_id = team_id
	state.game_over = true
	state.phase = GameState.Phase.GAME_OVER

# ===========================================================================
# Phase / turn advancement
# ===========================================================================

static func _advance_phase_if_needed(state: GameState) -> void:
	if state.game_over:
		return
	match state.phase:
		GameState.Phase.DRAFT:
			_advance_draft(state)
		GameState.Phase.TAKE:
			state.phase = GameState.Phase.PLAY
		GameState.Phase.PLAY, GameState.Phase.HAND_LIMIT:
			_enter_hand_limit_or_end_turn(state)

static func _advance_draft(state: GameState) -> void:
	var player := state.players[state.current_player_index]
	if player.recipes.size() < state.config.recipes_per_player:
		return # this player still has more recipes to keep
	if state.current_player_index == state.players.size() - 1:
		_finish_draft(state)
	else:
		state.current_player_index += 1

static func _enter_hand_limit_or_end_turn(state: GameState) -> void:
	var player := state.players[state.current_player_index]
	if player.hand.size() > state.config.hand_limit:
		state.phase = GameState.Phase.HAND_LIMIT
	else:
		_end_turn(state)

static func _end_turn(state: GameState) -> void:
	state.current_player_index = (state.current_player_index + 1) % state.players.size()
	state.phase = GameState.Phase.TAKE
	state.turn_number += 1

# ===========================================================================
# Read-only analysis (used by the simulator, not by turn resolution itself)
# ===========================================================================

## Returns the def_ids a player currently needs (open recipe slots, not
## already in hand) for which every remaining copy in the game is either in
## another player's hand or attached somewhere it can never be stolen from
## (a completed recipe, or attached as a preparation).
static func detect_starved_needs(state: GameState, player: Player) -> Array[String]:
	var starved: Array[String] = []
	var hand_ids: Dictionary = {}
	for c in player.hand:
		hand_ids[c.def_id] = true

	var needed_ids: Dictionary = {}
	for recipe in player.recipes:
		if recipe.completed:
			continue
		for iid in recipe.def.ingredient_ids:
			if not recipe.filled_ingredients.has(iid) and not hand_ids.has(iid):
				needed_ids[iid] = true
		for pid in recipe.def.preparation_ids:
			if not recipe.filled_preparations.has(pid) and not hand_ids.has(pid):
				needed_ids[pid] = true

	for def_id in needed_ids.keys():
		if _is_def_fully_unavailable(state, player, def_id):
			starved.append(def_id)
	return starved

static func _is_def_fully_unavailable(state: GameState, player: Player, def_id: String) -> bool:
	for c in state.deck:
		if c.def_id == def_id:
			return false
	for c in state.discard_pile:
		if c.def_id == def_id:
			return false
	for other in state.players:
		if other.index == player.index:
			continue
		for recipe in other.recipes:
			for c in recipe.stealable_ingredient_cards():
				if c.def_id == def_id:
					return false
	return true

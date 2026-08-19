class_name NetworkStateFilter
extends RefCounted
## THE security boundary for online play. Converts the authoritative,
## server-side GameState into a plain, RPC-safe Dictionary containing
## exactly what one specific seat is allowed to see -- nothing else is
## ever put into the payload, because "anything sent to a client can be
## read by that client": a field that merely isn't rendered by the UI is
## NOT a boundary. Only a field that was never serialized is.
##
## Built on PublicGameView so "what counts as hidden" has one definition
## shared with the local AI opponents, rather than a second boundary that
## could quietly drift out of sync with the first.
##
## What is deliberately EXCLUDED, and why:
##   - other players' hand contents: never present anywhere in this file.
##     Only hand_count (a public number in every card game) is sent.
##   - the deck's contents/order: only deck_size (a count) is sent.
##   - another player's recipe REQUIREMENT LIST (ingredient_ids /
##     preparation_ids): the dish name and tier are public per the rules
##     ("sit face up in front of them"), so those are sent -- but the full
##     list of what a recipe needs, and therefore what's still missing, is
##     not computed or sent for anyone else's recipe. Only the cards
##     actually visible/attached on their board are sent. A player who
##     recognizes the dish and remembers its recipe can reason about it
##     themselves, same as at a physical table -- but the server is never
##     the one handing over that computed answer.

const HIDDEN_RECIPE_TIER_KEYS := ["ingredient_ids", "preparation_ids"] # never present under "opponents"

## turn_timer_seconds is ServerAuthority's own config, not part of
## GameConfig (hot-seat has no equivalent -- it's an online-only knob), so
## it's threaded through as its own parameter rather than folded into
## _serialize_config(). Purely informational for the client: lets it show
## a countdown (see GameScreen._arm_network_turn_timer_display()), but the
## server is the only thing that actually enforces it.
static func build_snapshot(state: GameState, viewer_index: int, turn_timer_seconds: float = 0.0) -> Dictionary:
	var view := PublicGameView.from_state(state, viewer_index)

	var snapshot := {
		"viewer_index": viewer_index,
		"num_players": state.players.size(),
		"phase": state.phase,
		"turn_number": state.turn_number,
		"current_player_index": state.current_player_index,
		"deck_size": view.deck_size,
		"discard_pile": _serialize_cards(view.discard_pile),
		"steal_count": state.steal_count,
		"reshuffle_count": state.reshuffle_count,
		"game_over": state.game_over,
		"winner_player_index": state.winner_player_index,
		"winner_team_id": state.winner_team_id,
		"config": _serialize_config(state.config),
		"turn_timer_seconds": turn_timer_seconds,
		"own_hand": _serialize_cards(view.own_hand),
		"own_recipes": _serialize_own_recipes(view.own_recipes),
		"own_steals_used": view.own_steals_used,
		"opponents": _serialize_opponents(view.opponents),
		"draft_offer": [],
		"legal_actions": [],
	}

	if state.phase == GameState.Phase.DRAFT and viewer_index < state.draft_offers.size():
		snapshot["draft_offer"] = (state.draft_offers[viewer_index] as Array).duplicate()

	if not state.game_over and state.current_player_index == viewer_index:
		snapshot["legal_actions"] = ActionSerializer.serialize_list(RulesEngine.get_legal_actions(state))

	return snapshot

static func _serialize_card(c: Card) -> Dictionary:
	return {"instance_id": c.instance_id, "def_id": c.def_id, "category": c.category}

static func _serialize_cards(cards: Array) -> Array:
	var out := []
	for c in cards:
		out.append(_serialize_card(c))
	return out

static func _serialize_card_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for def_id in d.keys():
		out[def_id] = _serialize_card(d[def_id])
	return out

## Full detail: this is the viewer's OWN recipe, revealed to themselves.
static func _serialize_own_recipes(recipes: Array) -> Array:
	var out := []
	for recipe in recipes:
		out.append({
			"recipe_id": recipe.def.id,
			"display_name": recipe.def.display_name,
			"country": recipe.def.country,
			"tier": recipe.def.tier,
			"ingredient_ids": recipe.def.ingredient_ids.duplicate(),
			"preparation_ids": recipe.def.preparation_ids.duplicate(),
			"uses_grill": recipe.def.uses_grill,
			"filled_ingredients": _serialize_card_dict(recipe.filled_ingredients),
			"filled_preparations": _serialize_card_dict(recipe.filled_preparations),
			"decoys": _serialize_cards(recipe.decoys),
			"completed": recipe.completed,
		})
	return out

## Partial detail by design: dish name/tier (public) and whatever is
## actually attached (visible) -- never the requirement list. See the
## module doc comment above for why.
static func _serialize_opponents(opponents: Array) -> Array:
	var out := []
	for ov in opponents:
		var recipes := []
		for rv in ov.recipes:
			recipes.append({
				"recipe_id": rv.def.id,
				"display_name": rv.def.display_name,
				"country": rv.def.country,
				"tier": rv.def.tier,
				"uses_grill": rv.def.uses_grill,
				"recipe_index": rv.recipe_index,
				"attached_ingredients": _serialize_cards(rv.attached_ingredients),
				"attached_preparations": _serialize_cards(rv.attached_preparations),
				"decoys": _serialize_cards(rv.decoy_cards),
				"completed": rv.completed,
			})
		out.append({
			"player_index": ov.player_index,
			"team_id": ov.team_id,
			"hand_count": ov.hand_count,
			"steals_used": ov.steals_used,
			"recipes": recipes,
		})
	return out

static func _serialize_config(config: GameConfig) -> Dictionary:
	return {
		"decoys_enabled": config.decoys_enabled,
		"hand_limit": config.hand_limit,
		"recipes_per_player": config.recipes_per_player,
		"win_on_both_recipes": config.win_on_both_recipes,
		"draft_pool_size": config.draft_pool_size,
		"max_steals_per_player": config.max_steals_per_player,
		"num_players": config.num_players,
		"seconds_per_turn": config.seconds_per_turn,
	}

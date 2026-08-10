class_name ShadowStateBuilder
extends RefCounted
## Reconstructs a lightweight, CLIENT-SIDE GameState/Player/Recipe/Card
## object graph from a server-provided filtered snapshot Dictionary, so
## the exact same GameViewModel rendering code used by hot-seat play can
## render online play unchanged.
##
## This is safe specifically because the snapshot never contained hidden
## data in the first place (see NetworkStateFilter) -- reconstructing
## real objects from it cannot manufacture information that was never
## sent. Other players' hand arrays are simply left empty (their true
## hand_count is stashed in Player metadata instead, since Player.hand
## being empty would otherwise misreport a hand size of 0), and their
## RecipeDef carries no ingredient_ids/preparation_ids. Because of that,
## RulesEngine.get_legal_actions() must never be called on a shadow
## state -- there isn't enough data here to compute anyone's options
## correctly, nor should there be. The server already computed the
## viewer's own legal actions and included them in the snapshot
## (snapshot["legal_actions"]); the client only ever deserializes that
## list, never recomputes it.

const HAND_COUNT_META := "hand_count"

static func build(snapshot: Dictionary, db: CardDatabase) -> GameState:
	var config := _build_config(snapshot["config"])
	var state := GameState.new(config, db)
	state.phase = snapshot["phase"]
	state.turn_number = snapshot["turn_number"]
	state.current_player_index = snapshot["current_player_index"]
	state.game_over = snapshot["game_over"]
	state.winner_player_index = snapshot["winner_player_index"]
	state.winner_team_id = snapshot["winner_team_id"]
	state.steal_count = snapshot["steal_count"]
	state.reshuffle_count = snapshot["reshuffle_count"]

	state.deck = []
	for i in int(snapshot["deck_size"]):
		state.deck.append(Card.new(-1, "", CardDef.Category.INGREDIENT)) # opaque; only .size() is ever meaningful
	state.discard_pile = _build_cards(snapshot["discard_pile"])

	var viewer_index: int = snapshot["viewer_index"]
	var num_players: int = snapshot["num_players"]

	state.players = []
	for i in num_players:
		state.players.append(Player.new(i))

	var me: Player = state.players[viewer_index]
	me.hand = _build_cards(snapshot["own_hand"])
	me.recipes = _build_own_recipes(snapshot["own_recipes"])
	me.steals_used = snapshot["own_steals_used"]
	me.set_meta(HAND_COUNT_META, me.hand.size())

	for opp_dict in (snapshot["opponents"] as Array):
		var idx: int = opp_dict["player_index"]
		var p: Player = state.players[idx]
		p.team_id = opp_dict["team_id"]
		p.hand = [] # contents are never known; count is stashed in metadata
		p.recipes = _build_opponent_recipes(opp_dict["recipes"])
		p.steals_used = opp_dict["steals_used"]
		p.set_meta(HAND_COUNT_META, opp_dict["hand_count"])

	state.draft_offers = []
	for i in num_players:
		state.draft_offers.append((snapshot["draft_offer"] as Array).duplicate() if i == viewer_index else [])

	return state

## Every real Player.hand.size() call would read 0 for reconstructed
## opponents; use this instead anywhere a seat's hand size is displayed.
static func hand_count_of(player: Player) -> int:
	return player.get_meta(HAND_COUNT_META, player.hand.size())

static func _build_cards(dicts: Array) -> Array[Card]:
	var out: Array[Card] = []
	for d in dicts:
		out.append(_card_from_dict(d))
	return out

static func _card_from_dict(d: Dictionary) -> Card:
	return Card.new(d["instance_id"], d["def_id"], d["category"])

static func _build_config(d: Dictionary) -> GameConfig:
	var c := GameConfig.new()
	c.decoys_enabled = d["decoys_enabled"]
	c.hand_limit = d["hand_limit"]
	c.recipes_per_player = d["recipes_per_player"]
	c.win_on_both_recipes = d["win_on_both_recipes"]
	c.draft_pool_size = d["draft_pool_size"]
	c.max_steals_per_player = d["max_steals_per_player"]
	c.num_players = d["num_players"]
	c.seconds_per_turn = d["seconds_per_turn"]
	return c

static func _recipe_def_from_dict(d: Dictionary, include_requirements: bool) -> RecipeDef:
	var def := RecipeDef.new()
	def.id = d["recipe_id"]
	def.display_name = d["display_name"]
	def.country = d["country"]
	def.tier = d["tier"]
	def.uses_grill = d["uses_grill"]
	if include_requirements:
		for iid in (d["ingredient_ids"] as Array):
			def.ingredient_ids.append(iid)
		for pid in (d["preparation_ids"] as Array):
			def.preparation_ids.append(pid)
	return def

## Full detail: the viewer's own recipe, revealed to themselves.
static func _build_own_recipes(dicts: Array) -> Array[Recipe]:
	var out: Array[Recipe] = []
	for d in dicts:
		var recipe := Recipe.new(_recipe_def_from_dict(d, true))
		var filled_ing: Dictionary = d["filled_ingredients"]
		for def_id in filled_ing.keys():
			recipe.filled_ingredients[def_id] = _card_from_dict(filled_ing[def_id])
		var filled_prep: Dictionary = d["filled_preparations"]
		for def_id in filled_prep.keys():
			recipe.filled_preparations[def_id] = _card_from_dict(filled_prep[def_id])
		recipe.decoys = _build_cards(d["decoys"])
		recipe.completed = d["completed"]
		out.append(recipe)
	return out

## Partial detail: an opponent's recipe def carries no requirement list
## (see NetworkStateFilter); only what's actually attached is populated.
static func _build_opponent_recipes(dicts: Array) -> Array[Recipe]:
	var out: Array[Recipe] = []
	for d in dicts:
		var recipe := Recipe.new(_recipe_def_from_dict(d, false))
		for c in (d["attached_ingredients"] as Array):
			var card := _card_from_dict(c)
			recipe.filled_ingredients[card.def_id] = card
		for c in (d["attached_preparations"] as Array):
			var card := _card_from_dict(c)
			recipe.filled_preparations[card.def_id] = card
		recipe.decoys = _build_cards(d["decoys"])
		recipe.completed = d["completed"]
		out.append(recipe)
	return out

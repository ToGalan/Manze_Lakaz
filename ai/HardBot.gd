class_name HardBot
extends AiBot
## Adds opponent modelling on top of Medium's greedy play: it tracks which
## cards each opponent has attached over time (purely from public
## snapshots -- it never sees hand contents), infers which of an
## opponent's two recipes they're actually leaning on from the public dish
## names and visible attachment progress, and among all currently legal
## steals prefers whichever card both fills one of its own open slots and
## sets back whichever opponent is closest to completing a recipe.
##
## Attach/discard/draft behavior is identical to MediumBot -- the
## opponent modelling here only changes which STEAL target it picks.

const SELF_BENEFIT_BONUS := 3.0
const LEADING_RECIPE_BONUS := 0.2 # a tie-break nudge only -- must never by itself clear the worthwhile threshold
const DENIAL_WEIGHT := 4.0
const MIN_WORTHWHILE_STEAL_SCORE := 1.5 # a "needed" steal (self-benefit alone) always clears this; a pure denial steal needs the target recipe to be genuinely close to done (~60%+)

## "player_index:recipe_index" -> Dictionary[card_instance_id -> true],
## the attached-card set last observed for that recipe.
var _last_seen_attached: Dictionary = {}
## "player_index:recipe_index" -> turn_number a new attachment was last seen there.
var _last_attachment_turn: Dictionary = {}

func _decide(view: PublicGameView, legal_actions: Array[Action]) -> Action:
	_record_observations(view)
	match view.phase:
		GameState.Phase.DRAFT:
			return _choose_fewest_slots_draft(view, legal_actions)
		GameState.Phase.TAKE:
			return _choose_take(view, legal_actions)
		_:
			return _choose_greedy_attach_or_discard(view, legal_actions)

## Diffs this turn's public snapshot against the last one this bot saw, so
## it can tell which of an opponent's recipes has been getting recent
## attention even when two recipes are otherwise equally progressed.
func _record_observations(view: PublicGameView) -> void:
	for opp in view.opponents:
		for rv in opp.recipes:
			var key := "%d:%d" % [opp.player_index, rv.recipe_index]
			var current: Dictionary = {}
			for c in rv.attached_ingredients:
				current[c.instance_id] = true
			for c in rv.attached_preparations:
				current[c.instance_id] = true

			var previous: Dictionary = _last_seen_attached.get(key, {})
			for id in current.keys():
				if not previous.has(id):
					_last_attachment_turn[key] = view.turn_number
					break

			_last_seen_attached[key] = current

## Which of this opponent's (up to two) recipes they're most likely
## pursuing: the more-progressed one, tie-broken by whichever was attached
## to more recently.
func _leading_recipe(opp: PublicGameView.OpponentView) -> PublicGameView.RecipeView:
	var best: PublicGameView.RecipeView = null
	var best_progress := -1.0
	for rv in opp.recipes:
		if rv.completed:
			continue
		var progress: float = rv.progress_fraction()
		if progress > best_progress:
			best = rv
			best_progress = progress
		elif progress == best_progress and best != null:
			var key_candidate := "%d:%d" % [opp.player_index, rv.recipe_index]
			var key_best := "%d:%d" % [opp.player_index, best.recipe_index]
			if _last_attachment_turn.get(key_candidate, -1) > _last_attachment_turn.get(key_best, -1):
				best = rv
	return best

func _choose_take(view: PublicGameView, legal_actions: Array[Action]) -> Action:
	var draw_action: Action = null
	var best_steal: Action = null
	var best_score := -1.0

	for a in legal_actions:
		if a.type == Action.Type.DRAW:
			draw_action = a
		elif a.type == Action.Type.STEAL:
			var score := _score_steal(view, a)
			if best_steal == null or score > best_score:
				best_score = score
				best_steal = a

	if best_steal != null and best_score >= MIN_WORTHWHILE_STEAL_SCORE:
		return best_steal
	if draw_action != null:
		return draw_action
	if best_steal != null:
		return best_steal
	return legal_actions[0]

## Higher score = steal this one first. Rewards cards that fill the bot's
## own open slot, and separately rewards taking a card from a recipe that
## is heavily progressed (quadratic, so a near-complete recipe is worth
## far more to disrupt than a barely-started one) -- with an extra nudge
## if that recipe is specifically the opponent's inferred leading one.
func _score_steal(view: PublicGameView, action: Action) -> float:
	var card := _steal_target_card(view, action)
	if card == null:
		return 0.0

	var score := 0.0
	if _own_open_ingredient_slot(view, card.def_id):
		score += SELF_BENEFIT_BONUS

	var opp := view.find_opponent(action.target_player_index)
	if opp != null:
		var leading := _leading_recipe(opp)
		for rv in opp.recipes:
			if rv.recipe_index != action.target_recipe_index:
				continue
			score += DENIAL_WEIGHT * pow(rv.progress_fraction(), 2)
			if leading != null and leading.recipe_index == rv.recipe_index:
				score += LEADING_RECIPE_BONUS
			break

	return score

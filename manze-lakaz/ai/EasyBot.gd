class_name EasyBot
extends AiBot
## Random legal action, weighted slightly toward attaching.

const ATTACH_WEIGHT := 3.0
const DEFAULT_WEIGHT := 1.0

func _decide(view: PublicGameView, legal_actions: Array[Action]) -> Action:
	var weights: Array[float] = []
	var total := 0.0
	for a in legal_actions:
		var w := ATTACH_WEIGHT if a.type == Action.Type.ATTACH else DEFAULT_WEIGHT
		weights.append(w)
		total += w

	var roll := rng.randf() * total
	var acc := 0.0
	for i in legal_actions.size():
		acc += weights[i]
		if roll <= acc:
			return legal_actions[i]
	return legal_actions[legal_actions.size() - 1]

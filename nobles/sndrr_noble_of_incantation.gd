extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "sndrr_incantation",
		"name": "Sndrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, you may discard a card, then draw a card"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "seek", 1, {}, false)
	return {"ok": true, "log": "P%d activates Sndrr (Seek 1)." % owner}

extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "indrr_incantation",
		"name": "Indrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, look at the top card of a chosen deck; keep it on top or place it on the bottom"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "insight", 1, {}, false)
	return {"ok": true, "log": "P%d activates Indrr (Insight 1)." % owner}

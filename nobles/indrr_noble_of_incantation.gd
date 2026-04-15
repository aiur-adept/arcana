extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "indrr_incantation",
		"name": "Indrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, you may Insight 2"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "insight", 2)
	return {"ok": true, "log": "P%d activates Indrr (Insight 2)." % owner}

extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "rndrr_incantation",
		"name": "Rndrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, you may Revive 1"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "revive", 1)
	return {"ok": true, "log": "P%d activates Rndrr (Revive 1)." % owner}

extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "bndrr_incantation",
		"name": "Bndrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, you may Burn 1"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "burn", 1)
	return {"ok": true, "log": "P%d activates Bndrr (Burn 1)." % owner}

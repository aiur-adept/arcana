extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "rndrr_incantation",
		"name": "Rndrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, cast one incantation from your crypt; the cast card goes to the abyss"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "revive", 2, {}, false)
	return {"ok": true, "log": "P%d activates Rndrr (Revive 2)." % owner}

extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "bndrr_incantation",
		"name": "Bndrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, discard the top 4 cards of a chosen player's deck"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "burn", 2, {}, false)
	return {"ok": true, "log": "P%d activates Bndrr (Burn 2)." % owner}

extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "wndrr_incantation",
		"name": "Wndrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, you may discard a card to Woe 2"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "woe", 2)
	return {"ok": true, "log": "P%d activates Wndrr (Woe 2)." % owner}

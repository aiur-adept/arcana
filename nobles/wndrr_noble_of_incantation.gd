extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "wndrr_incantation",
		"name": "Wndrr, Noble of Incantation",
		"cost": 3,
		"active_text": "Once per turn, you may discard a card; then the opponent discards a chosen card from hand"
	}


func activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> Dictionary:
	state.resolve_spell_like_effect(owner, "woe", 3, {}, false)
	return {"ok": true, "log": "P%d activates Wndrr (Woe 3)." % owner}

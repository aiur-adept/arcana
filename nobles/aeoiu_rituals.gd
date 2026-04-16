extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "aeoiu_rituals",
		"name": "Aeoiu, Scion of Rituals",
		"cost": 4
	}


func can_activate(state: ArcanaMatchState, owner: int, _noble: Dictionary) -> bool:
	return state.can_play_aeoiu_ritual(owner)

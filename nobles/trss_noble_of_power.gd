extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "trss_power",
		"name": "Trss, Noble of Power",
		"cost": 2,
		"lane_grant": 2
	}


func grant_incantation_lanes(_match: ArcanaMatchState, _owner: int, _noble: Dictionary) -> Array:
	return [2]

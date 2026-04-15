extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "yrss_power",
		"name": "Yrss, Noble of Power",
		"cost": 4,
		"lane_grant": 3
	}


func grant_incantation_lanes(_match: ArcanaMatchState, _owner: int, _noble: Dictionary) -> Array:
	return [3]

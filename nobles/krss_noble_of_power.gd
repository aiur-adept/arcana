extends RefCounted

func build_definition() -> Dictionary:
	return {
		"id": "krss_power",
		"name": "Krss, Noble of Power",
		"cost": 2,
		"lane_grant": 1
	}


func grant_incantation_lanes(_match: ArcanaMatchState, _owner: int, _noble: Dictionary) -> Array:
	return [1]

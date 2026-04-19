extends RefCounted
class_name ArcanaCpuPilotRegistry

const _CpuBase = preload("res://cpu/cpu_base.gd")
const _Incantations = preload("res://cpu/pilots/incantations_pilot.gd")
const _NobleTest = preload("res://cpu/pilots/noble_test_pilot.gd")
const _WrathseekSac = preload("res://cpu/pilots/wrathseek_sac_pilot.gd")
const _RitualReanimator = preload("res://cpu/pilots/ritual_reanimator_pilot.gd")
const _Topheavy = preload("res://cpu/pilots/topheavy_annihilator_pilot.gd")
const _Occultation = preload("res://cpu/pilots/occultation_pilot.gd")
const _Annihilation = preload("res://cpu/pilots/annihilation_pilot.gd")
const _Emanation = preload("res://cpu/pilots/emanation_pilot.gd")
const _Scions = preload("res://cpu/pilots/scions_pilot.gd")
const _Temples = preload("res://cpu/pilots/temples_pilot.gd")
const _BirdTest = preload("res://cpu/pilots/bird_test_pilot.gd")
const _VoidTemples = preload("res://cpu/pilots/void_temples_pilot.gd")
const _Revive = preload("res://cpu/pilots/revive_pilot.gd")


static func create_for_slug(slug: String) -> ArcanaCpuBase:
	match slug:
		"incantations":
			return _Incantations.new()
		"noble_test":
			return _NobleTest.new()
		"wrathseek-sac":
			return _WrathseekSac.new()
		"ritual_reanimator":
			return _RitualReanimator.new()
		"topheavy_annihilator":
			return _Topheavy.new()
		"occultation":
			return _Occultation.new()
		"annihilation":
			return _Annihilation.new()
		"emanation":
			return _Emanation.new()
		"scions":
			return _Scions.new()
		"temples":
			return _Temples.new()
		"bird_test":
			return _BirdTest.new()
		"void_temples":
			return _VoidTemples.new()
		"revive":
			return _Revive.new()
		_:
			return _CpuBase.new()

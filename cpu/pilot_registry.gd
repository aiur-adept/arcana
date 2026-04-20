extends RefCounted
class_name ArcanaCpuPilotRegistry

const _CpuBase = preload("res://cpu/cpu_base.gd")
const _Incantations = preload("res://cpu/pilots/incantations_pilot.gd")
const _NobleTest = preload("res://cpu/pilots/noble_test_pilot.gd")
const _RitualReanimator = preload("res://cpu/pilots/ritual_reanimator_pilot.gd")
const _Topheavy = preload("res://cpu/pilots/topheavy_annihilator_pilot.gd")
const _Occultation = preload("res://cpu/pilots/occultation_pilot.gd")
const _Annihilation = preload("res://cpu/pilots/annihilation_pilot.gd")
const _Emanation = preload("res://cpu/pilots/emanation_pilot.gd")
const _Temples = preload("res://cpu/pilots/temples_pilot.gd")
const _BirdTest = preload("res://cpu/pilots/bird_test_pilot.gd")
const _VoidTemples = preload("res://cpu/pilots/void_temples_pilot.gd")
const _Revive = preload("res://cpu/pilots/revive_pilot.gd")
const _PilotWeights = preload("res://cpu/pilot_weights_loader.gd")


static func create_for_slug(slug: String) -> ArcanaCpuBase:
	var p: ArcanaCpuBase
	match slug:
		"incantations":
			p = _Incantations.new()
		"noble_test":
			p = _NobleTest.new()
		"ritual_reanimator":
			p = _RitualReanimator.new()
		"topheavy_annihilator":
			p = _Topheavy.new()
		"occultation":
			p = _Occultation.new()
		"annihilation":
			p = _Annihilation.new()
		"emanation":
			p = _Emanation.new()
		"temples":
			p = _Temples.new()
		"bird_test":
			p = _BirdTest.new()
		"void_temples":
			p = _VoidTemples.new()
		"revive":
			p = _Revive.new()
		_:
			p = _CpuBase.new()
	_PilotWeights.apply_saved_weights(p, slug)
	return p

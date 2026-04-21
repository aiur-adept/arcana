extends RefCounted
class_name ArcanaCpuPilotRegistry

const _CpuBase = preload("res://cpu/cpu_base.gd")
const _RitualReanimator = preload("res://cpu/pilots/ritual_reanimator_pilot.gd")
const _Occultation = preload("res://cpu/pilots/occultation_pilot.gd")
const _Annihilation = preload("res://cpu/pilots/annihilation_pilot.gd")
const _Emanation = preload("res://cpu/pilots/emanation_pilot.gd")
const _BirdTest = preload("res://cpu/pilots/bird_flock_pilot.gd")
const _VoidTemples = preload("res://cpu/pilots/void_temples_pilot.gd")
const _PilotWeights = preload("res://cpu/pilot_weights_loader.gd")


static func create_for_slug(slug: String) -> ArcanaCpuBase:
	var p: ArcanaCpuBase
	match slug:
		"ritual_reanimator":
			p = _RitualReanimator.new()
		"occultation":
			p = _Occultation.new()
		"annihilation":
			p = _Annihilation.new()
		"emanation":
			p = _Emanation.new()
		"bird_flock":
			p = _BirdTest.new()
		"void_temples":
			p = _VoidTemples.new()
		_:
			p = _CpuBase.new()
	_PilotWeights.apply_saved_weights(p, slug)
	return p

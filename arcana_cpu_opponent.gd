extends RefCounted
class_name ArcanaCpuOpponent

# Thin facade that delegates to a per-deck ArcanaCpuBase pilot. The
# concrete pilot is swapped via configure_for_opponent_slug() whenever
# a new match starts, keyed on the opponent's included-deck slug.

const CPU_ACTION_SEC := 1.618
const _CpuBaseScript := "res://cpu/cpu_base.gd"
const _PilotRegistryScript := "res://cpu/pilot_registry.gd"

var _pilot = load(_CpuBaseScript).new()


func configure_for_opponent_slug(slug: String) -> void:
	_pilot = load(_PilotRegistryScript).create_for_slug(slug)


func run_turn(host: Node) -> void:
	await _pilot.run_turn(host)


func run_mulligan_step(host: Node) -> void:
	await _pilot.run_mulligan_step(host)


func _cpu_decide_void_response(host: Node, snap: Dictionary, trigger_cpu_check: bool = true) -> void:
	_pilot._cpu_decide_void_response(host, snap, trigger_cpu_check)


# Back-compat helpers (kept as static so older call sites still link).

static func greedy_sacrifice_mids(snap: Dictionary, need: int) -> Array:
	var field: Array = snap.get("your_field", [])
	var items: Array = []
	for x in field:
		items.append({"mid": int(x.get("mid", 0)), "v": int(x.get("value", 0))})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["v"]) < int(b["v"])
	)
	var sum := 0
	var out: Array = []
	for it in items:
		out.append(int(it["mid"]))
		sum += int(it["v"])
		if sum >= need:
			return out
	return []


static func greedy_wrath_mids(opp_field: Array, need: int) -> Array:
	var items: Array = []
	for x in opp_field:
		items.append({"mid": int(x.get("mid", 0)), "v": int(x.get("value", 0))})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["v"]) < int(b["v"])
	)
	var out: Array = []
	for i in mini(need, items.size()):
		out.append(int(items[i]["mid"]))
	return out


static func ai_end_discards_from_snap(snap: Dictionary) -> Array:
	var hand: Array = snap.get("your_hand", [])
	var need := maxi(0, hand.size() - 7)
	if need == 0:
		return []
	var idxs: Array[int] = []
	for i in hand.size():
		idxs.append(i)
	idxs.shuffle()
	var chosen: Array = []
	for j in need:
		chosen.append(idxs[j])
	return chosen

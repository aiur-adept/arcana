class_name ArcanaMatchState
extends RefCounted

const MAX_HAND_END := 7
const START_HAND := 5
const WIN_POWER := 20
const NOBLES_DIR := "res://nobles"

enum Phase { MAIN, GAME_OVER }

var rng: RandomNumberGenerator
var phase: Phase = Phase.MAIN
var current: int
var ritual_played_this_turn: bool = false
var noble_played_this_turn: bool = false
var discard_draw_used: bool
var winner: int = -1
var empty_deck_end: bool = false
var log_lines: PackedStringArray
var turn_number: int = 0

var _players: Array[Dictionary]
var _noble_hooks: Dictionary = {}


func _card_kind(c: Variant) -> String:
	if c == null:
		return ""
	return str(c.get("type", "")).to_lower()


func _init(p0_deck: Array, p1_deck: Array, p0_first: bool, p_rng: RandomNumberGenerator) -> void:
	rng = p_rng
	_load_noble_hooks()
	_players = [
		_make_player(p0_deck),
		_make_player(p1_deck)
	]
	current = 0 if p0_first else 1
	discard_draw_used = false
	phase = Phase.MAIN
	_deal_start()
	_turn_start_draw()


func _make_player(deck_template: Array) -> Dictionary:
	var d: Array = deck_template.duplicate(true)
	_shuffle(d)
	return {
		"deck": d,
		"hand": [],
		"field": [],
		"noble_field": [],
		"ritual_grave": [],
		"noble_grave": [],
		"inc_discard": [],
		"deck_grave": []
	}


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _deal_start() -> void:
	for p in range(2):
		for _i in START_HAND:
			_draw_card_silent(p)


func _draw_card_silent(p: int) -> void:
	var pl: Dictionary = _players[p]
	var deck: Array = pl["deck"]
	if deck.is_empty():
		return
	var c: Variant = deck.pop_back()
	pl["hand"].append(c)


func _turn_start_draw() -> void:
	if phase == Phase.GAME_OVER:
		return
	ritual_played_this_turn = false
	noble_played_this_turn = false
	turn_number += 1
	if not _draw_one_attempt(current):
		return
	discard_draw_used = false
	_log("Turn P%d draw step." % current)


func _draw_one_attempt(p: int) -> bool:
	var pl: Dictionary = _players[p]
	var deck: Array = pl["deck"]
	if deck.is_empty():
		_resolve_empty_deck_loss(p)
		return false
	pl["hand"].append(deck.pop_back())
	_check_power_win(p)
	return phase != Phase.GAME_OVER


func _resolve_empty_deck_loss(trigger_player: int) -> void:
	empty_deck_end = true
	var p0_power := ritual_power(0)
	var p1_power := ritual_power(1)
	if p0_power > p1_power:
		winner = 0
	elif p1_power > p0_power:
		winner = 1
	else:
		winner = -1
	phase = Phase.GAME_OVER
	if winner >= 0:
		_log("P%d drew from an empty deck. P%d wins by higher active ritual power (%d vs %d)." % [trigger_player, winner, p0_power, p1_power])
	else:
		_log("P%d drew from an empty deck. Game is a draw on active ritual power (%d-%d)." % [trigger_player, p0_power, p1_power])


func _check_power_win(p: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	if ritual_power(p) >= WIN_POWER:
		winner = p
		phase = Phase.GAME_OVER
		_log("P%d reached %d ritual power." % [p, WIN_POWER])


func ritual_power(p: int) -> int:
	var field: Array = _players[p]["field"]
	var act: Array = _active_mask(field)
	var s := 0
	for i in field.size():
		if bool(act[i]):
			s += int(field[i]["value"])
	return s


static func active_mask_for_field(field: Array) -> Array:
	var n := field.size()
	var active: Array = []
	active.resize(n)
	var order: Array[int] = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return int(field[a]["value"]) < int(field[b]["value"])
	)
	for idx in order:
		var v: int = int(field[idx]["value"])
		if v == 1:
			active[idx] = true
		else:
			var ok := true
			for k in range(1, v):
				var found := false
				for j in n:
					if int(field[j]["value"]) == k and bool(active[j]):
						found = true
						break
				if not found:
					ok = false
					break
			active[idx] = ok
	return active


static func has_lane_for_field(field: Array, n: int) -> bool:
	var act: Array = active_mask_for_field(field)
	for i in field.size():
		if int(field[i]["value"]) == n and bool(act[i]):
			return true
	return false


func _active_mask(field: Array) -> Array:
	return active_mask_for_field(field)


func has_active_incantation_lane(p: int, n: int) -> bool:
	if has_lane_for_field(_players[p]["field"], n):
		return true
	var grants := _extra_incantation_lanes_from_nobles(p)
	return grants.has(n)


func _extra_incantation_lanes_from_nobles(p: int) -> Array:
	var lanes: Array = []
	var seen: Dictionary = {}
	var nobles: Array = _players[p]["noble_field"]
	for noble in nobles:
		var hook: Variant = _hook_for_noble(noble)
		if hook == null or not hook.has_method("grant_incantation_lanes"):
			continue
		var hook_lanes: Variant = hook.call("grant_incantation_lanes", self, p, noble)
		if typeof(hook_lanes) != TYPE_ARRAY:
			continue
		for lane in hook_lanes:
			var lv := int(lane)
			if lv > 0 and not seen.has(lv):
				seen[lv] = true
				lanes.append(lv)
	return lanes


func snapshot(for_player: int) -> Dictionary:
	var opp := 1 - for_player
	return {
		"phase": int(phase),
		"turn_number": turn_number,
		"current": current,
		"your_ritual_played": for_player == current and ritual_played_this_turn,
		"your_noble_played": for_player == current and noble_played_this_turn,
		"discard_draw_used": discard_draw_used,
		"winner": winner,
		"empty_deck_end": empty_deck_end,
		"you": for_player,
		"your_hand": _players[for_player]["hand"].duplicate(true),
		"your_deck": _players[for_player]["deck"].size(),
		"opp_hand": _players[opp]["hand"].size(),
		"opp_deck": _players[opp]["deck"].size(),
		"your_field": _players[for_player]["field"].duplicate(true),
		"opp_field": _players[opp]["field"].duplicate(true),
		"your_nobles": _players[for_player]["noble_field"].duplicate(true),
		"opp_nobles": _players[opp]["noble_field"].duplicate(true),
		"your_power": ritual_power(for_player),
		"opp_power": ritual_power(opp),
		"your_inc_disc": _players[for_player]["inc_discard"].size(),
		"opp_inc_disc": _players[opp]["inc_discard"].size(),
		"log": log_lines.duplicate()
	}


func can_play_ritual(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or p != current or ritual_played_this_turn:
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	return c != null and _card_kind(c) == "ritual"


func play_ritual(p: int, hand_idx: int) -> String:
	if not can_play_ritual(p, hand_idx):
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	var c: Dictionary = hand[hand_idx]
	hand.remove_at(hand_idx)
	var mid := _next_mid(pl)
	pl["field"].append({"mid": mid, "value": int(c["value"])})
	ritual_played_this_turn = true
	_log("P%d plays %d-Ritual." % [p, int(c["value"])])
	_check_power_win(p)
	return "ok"


func can_play_noble(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or p != current or noble_played_this_turn:
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "noble":
		return false
	var nid := str(c.get("noble_id", ""))
	if nid.is_empty() or not _noble_hooks.has(nid):
		return false
	var cost := _noble_play_cost(nid)
	if cost <= 0:
		return true
	var field: Array = _players[p]["field"]
	return has_lane_for_field(field, cost)


func play_noble(p: int, hand_idx: int) -> String:
	if not can_play_noble(p, hand_idx):
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	var c: Dictionary = hand[hand_idx]
	var nid := str(c.get("noble_id", ""))
	if nid.is_empty():
		return "illegal"
	if not _noble_hooks.has(nid):
		return "illegal_noble"
	hand.remove_at(hand_idx)
	var mid := _next_noble_mid(pl)
	var field_noble := {
		"mid": mid,
		"noble_id": nid,
		"name": str(c.get("name", nid)),
		"used_turn": -1
	}
	pl["noble_field"].append(field_noble)
	noble_played_this_turn = true
	_log("P%d summons %s." % [p, field_noble["name"]])
	return "ok"


func _next_mid(pl: Dictionary) -> int:
	var mx := 0
	for x in pl["field"]:
		mx = maxi(mx, int(x["mid"]))
	for x in pl["ritual_grave"]:
		mx = maxi(mx, int(x.get("mid", 0)))
	return mx + 1


func _next_noble_mid(pl: Dictionary) -> int:
	var mx := 0
	for x in pl["noble_field"]:
		mx = maxi(mx, int(x["mid"]))
	for x in pl["noble_grave"]:
		mx = maxi(mx, int(x.get("mid", 0)))
	return mx + 1


func _noble_play_cost(nid: String) -> int:
	if not _noble_hooks.has(nid):
		return 0
	var hook: Variant = _noble_hooks[nid]
	if hook == null or not hook.has_method("build_definition"):
		return 0
	var def: Variant = hook.call("build_definition")
	if typeof(def) != TYPE_DICTIONARY:
		return 0
	return int((def as Dictionary).get("cost", 0))


func can_play_incantation(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or p != current:
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "incantation":
		return false
	var n: int = int(c["value"])
	if n < 1:
		return false
	if has_active_incantation_lane(p, n):
		return true
	return _can_sacrifice(p, n)


func can_play_dethrone(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or p != current:
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "dethrone":
		return false
	var n := int(c.get("value", 4))
	if n != 4:
		return false
	if not has_lane_for_field(_players[p]["field"], n) and not _can_sacrifice(p, n):
		return false
	return not (_players[1 - p]["noble_field"] as Array).is_empty()


func _can_sacrifice(p: int, need: int) -> bool:
	var tot := 0
	for x in _players[p]["field"]:
		tot += int(x["value"])
	return tot >= need


func _greedy_sacrifice_mids_for_player(p: int, need: int) -> Array:
	var field: Array = _players[p]["field"]
	var items: Array = []
	for x in field:
		items.append({"mid": int(x["mid"]), "v": int(x["value"])})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["v"] < b["v"]
	)
	var sum := 0
	var out: Array = []
	for it in items:
		out.append(it["mid"])
		sum += int(it["v"])
		if sum >= need:
			return out
	return []


func play_incantation(p: int, hand_idx: int, sacrifice_mids: Array, wrath_mids: Array = [], insight_target: int = -1, insight_perm: Array = []) -> String:
	if not can_play_incantation(p, hand_idx):
		return "illegal"
	var c: Dictionary = _card_at_hand(p, hand_idx)
	var n: int = int(c["value"])
	if n < 1:
		return "illegal"
	var need_sac := not has_active_incantation_lane(p, n)
	var mids: Dictionary = {}
	if need_sac:
		for m in sacrifice_mids:
			mids[int(m)] = true
		if not _sacrifice_valid(p, n, mids):
			mids.clear()
			for mid in _greedy_sacrifice_mids_for_player(p, n):
				mids[int(mid)] = true
			if not _sacrifice_valid(p, n, mids):
				return "illegal_sacrifice"
	var payment_text := _incantation_payment_text(p, n, need_sac, mids)
	_apply_sacrifice(p, mids)
	var pl: Dictionary = _players[p]
	pl["hand"].remove_at(hand_idx)
	var verb_raw: String = str(c.get("verb", ""))
	var verb: String = verb_raw.to_lower()
	if verb == "wrath" and _wrath_destroy_count(n) == 0:
		return "illegal"
	var wrath_resolved: Array = []
	if verb == "wrath":
		wrath_resolved = _wrath_resolve_mids(1 - p, n, wrath_mids)
	_apply_incantation(p, verb, n, wrath_resolved, insight_target, insight_perm)
	pl["inc_discard"].append(c)
	_log("P%d plays %s %d (%s)." % [p, verb_raw, n, payment_text])
	_check_power_win(p)
	return "ok"


func play_dethrone(p: int, hand_idx: int, noble_mids: Array = [], sacrifice_mids: Array = []) -> String:
	if not can_play_dethrone(p, hand_idx):
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	var c: Dictionary = hand[hand_idx]
	var n := int(c.get("value", 4))
	var need_sac := not has_lane_for_field(_players[p]["field"], n)
	var destroyed := _dethrone_resolve_mids(1 - p, noble_mids)
	if destroyed.is_empty():
		return "illegal_target"
	var mids: Dictionary = {}
	if need_sac:
		for m in sacrifice_mids:
			mids[int(m)] = true
		if not _sacrifice_valid(p, n, mids):
			mids.clear()
			for mid in _greedy_sacrifice_mids_for_player(p, n):
				mids[int(mid)] = true
			if not _sacrifice_valid(p, n, mids):
				return "illegal_sacrifice"
	_apply_sacrifice(p, mids)
	hand.remove_at(hand_idx)
	_destroy_nobles_by_mids(1 - p, destroyed)
	pl["inc_discard"].append(c)
	_log("P%d plays Dethrone %d." % [p, n])
	return "ok"


func can_activate_noble(p: int, noble_mid: int) -> bool:
	if phase != Phase.MAIN or p != current:
		return false
	var noble := _find_noble_on_field(p, noble_mid)
	if noble.is_empty():
		return false
	if int(noble.get("used_turn", -1)) == turn_number:
		return false
	var hook: Variant = _hook_for_noble(noble)
	if hook == null:
		return false
	if hook.has_method("can_activate"):
		return bool(hook.call("can_activate", self, p, noble))
	return hook.has_method("activate")


func activate_noble(p: int, noble_mid: int) -> String:
	if not can_activate_noble(p, noble_mid):
		return "illegal"
	var noble := _find_noble_on_field(p, noble_mid)
	if str(noble.get("noble_id", "")) == "indrr_incantation":
		return activate_noble_with_insight(p, noble_mid, -1, [])
	var hook: Variant = _hook_for_noble(noble)
	var result: Variant = hook.call("activate", self, p, noble)
	if typeof(result) != TYPE_DICTIONARY:
		return "illegal"
	var rd := result as Dictionary
	if not bool(rd.get("ok", false)):
		return "illegal"
	_mark_noble_used_this_turn(p, noble_mid)
	var msg := str(rd.get("log", ""))
	if not msg.is_empty():
		_log(msg)
	return "ok"


func activate_noble_with_insight(p: int, noble_mid: int, insight_target: int, insight_perm: Array = []) -> String:
	if not can_activate_noble(p, noble_mid):
		return "illegal"
	var noble := _find_noble_on_field(p, noble_mid)
	if str(noble.get("noble_id", "")) == "indrr_incantation":
		_apply_incantation(p, "insight", 2, [], insight_target, insight_perm)
		_mark_noble_used_this_turn(p, noble_mid)
		_log("P%d activates Indrr (Insight 2)." % p)
		return "ok"
	var hook: Variant = _hook_for_noble(noble)
	var result: Variant = hook.call("activate", self, p, noble)
	if typeof(result) != TYPE_DICTIONARY:
		return "illegal"
	var rd := result as Dictionary
	if not bool(rd.get("ok", false)):
		return "illegal"
	_mark_noble_used_this_turn(p, noble_mid)
	var msg := str(rd.get("log", ""))
	if not msg.is_empty():
		_log(msg)
	return "ok"


func _sacrifice_valid(p: int, need: int, mids: Dictionary) -> bool:
	var sum := 0
	var pl: Dictionary = _players[p]
	var field: Array = pl["field"]
	var seen: Dictionary = {}
	for i in field.size():
		var mid: int = int(field[i]["mid"])
		if mids.has(mid):
			if seen.has(mid):
				return false
			seen[mid] = true
			sum += int(field[i]["value"])
	return sum >= need and seen.size() == mids.size()


func _apply_sacrifice(p: int, mids: Dictionary) -> void:
	if mids.is_empty():
		return
	var pl: Dictionary = _players[p]
	var field: Array = pl["field"]
	var keep: Array = []
	for x in field:
		if mids.has(int(x["mid"])):
			pl["ritual_grave"].append(x)
		else:
			keep.append(x)
	pl["field"] = keep


func _incantation_payment_text(p: int, cost: int, used_sacrifice: bool, mids: Dictionary) -> String:
	if not used_sacrifice:
		return "paid via active %d-lane" % cost
	var field: Array = _players[p]["field"]
	var values: Array = []
	var mid_list: Array = []
	var total := 0
	for x in field:
		var mid := int(x["mid"])
		if not mids.has(mid):
			continue
		var v := int(x["value"])
		total += v
		values.append(v)
		mid_list.append(mid)
	values.sort()
	mid_list.sort()
	return "paid by sacrificing mids %s (values %s, total %d for cost %d)" % [str(mid_list), str(values), total, cost]


func _apply_incantation(p: int, verb: String, value: int, wrath_mids: Array = [], insight_target: int = -1, insight_perm: Array = []) -> void:
	var opp := 1 - p
	match verb:
		"seek":
			_draw_n(p, value)
		"insight":
			var tgt := insight_target
			if tgt != p and tgt != opp:
				tgt = (1 - p) if rng.randf() < 0.5 else p
			_apply_insight_reorder(tgt, value, insight_perm)
		"burn":
			_mill(opp, value * 2)
		"woe":
			_random_discard_hand(opp, value)
		"revive":
			_revive_random(p, value)
		"wrath":
			_destroy_rituals_by_mids(opp, wrath_mids)
		_:
			pass


func resolve_spell_like_effect(p: int, verb: String, value: int) -> void:
	_apply_incantation(p, verb.to_lower(), value, [], -1, [])


func _draw_n(p: int, n: int) -> void:
	for _i in n:
		if phase == Phase.GAME_OVER:
			return
		if not _draw_one_attempt(p):
			return


func insight_peek_top_cards(target: int, x: int) -> Array:
	var deck: Array = _players[target]["deck"]
	var take := mini(x, deck.size())
	var out: Array = []
	for i in take:
		out.append(deck[deck.size() - 1 - i])
	return out


func _insight_perm_valid(take: int, perm: Array) -> bool:
	if perm.size() != take:
		return false
	var seen: Dictionary = {}
	for x in perm:
		var v := int(x)
		if v < 0 or v >= take or seen.has(v):
			return false
		seen[v] = true
	return seen.size() == take


func _shuffle_index_array(perm: Array) -> void:
	for i in range(perm.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = perm[i]
		perm[i] = perm[j]
		perm[j] = t


func _apply_insight_reorder(target: int, x: int, perm: Array) -> void:
	var pl: Dictionary = _players[target]
	var deck: Array = pl["deck"]
	var take := mini(x, deck.size())
	if take == 0:
		_log("Insight on P%d (empty deck)." % target)
		return
	if take == 1:
		_log("Insight 1 on P%d deck (single card)." % target)
		return
	var peek: Array = []
	peek.resize(take)
	for i in take:
		peek[i] = deck[deck.size() - 1 - i]
	for _i in take:
		deck.pop_back()
	var use_perm: Array = perm.duplicate()
	if not _insight_perm_valid(take, use_perm):
		use_perm.clear()
		for i in take:
			use_perm.append(i)
		_shuffle_index_array(use_perm)
	var new_seq: Array = []
	new_seq.resize(take)
	for i in take:
		new_seq[i] = peek[int(use_perm[i])]
	for k in range(take - 1, -1, -1):
		deck.append(new_seq[k])
	_log("Insight %d on P%d deck (reordered)." % [take, target])


func _mill(target: int, x: int) -> void:
	var pl: Dictionary = _players[target]
	var deck: Array = pl["deck"]
	var n := mini(x, deck.size())
	for _i in n:
		pl["deck_grave"].append(deck.pop_back())
	_log("Burn discards %d from P%d deck." % [n, target])


func _random_discard_hand(target: int, x: int) -> void:
	var pl: Dictionary = _players[target]
	var hand: Array = pl["hand"]
	for _i in mini(x, hand.size()):
		var idx := rng.randi_range(0, hand.size() - 1)
		_move_hand_card_to_discard(pl, hand, idx)
	_log("Woe discards P%d cards." % target)


func _revive_random(p: int, x: int) -> void:
	var pl: Dictionary = _players[p]
	var idisc: Array = pl["inc_discard"]
	for _k in range(int(x)):
		var opts: Array[int] = []
		for j in idisc.size():
			if _card_kind(idisc[j]) == "incantation":
				opts.append(j)
		if opts.is_empty():
			break
		var pick := opts[rng.randi_range(0, opts.size() - 1)]
		var c: Variant = idisc[pick]
		idisc.remove_at(pick)
		pl["hand"].append(c)
	_log("Revive returns incantations to P%d hand." % p)


func _wrath_destroy_count(value: int) -> int:
	if value == 4:
		return 2
	return 0


func _wrath_resolve_mids(opp: int, n: int, client_mids: Array) -> Array:
	var field: Array = _players[opp]["field"]
	var need := mini(_wrath_destroy_count(n), field.size())
	if need == 0:
		return []
	var dict: Dictionary = {}
	for m in client_mids:
		dict[int(m)] = true
	if _wrath_mids_valid(field, need, dict):
		var out: Array = []
		for k in dict.keys():
			out.append(k)
		return out
	return _greedy_destroy_mids(field, need)


func _wrath_mids_valid(field: Array, need: int, mids: Dictionary) -> bool:
	if mids.size() != need:
		return false
	var found: Dictionary = {}
	for x in field:
		var mid: int = int(x["mid"])
		if mids.has(mid):
			found[mid] = true
	return found.size() == mids.size()


func _greedy_destroy_mids(field: Array, need: int) -> Array:
	var items: Array = []
	for x in field:
		items.append({"mid": int(x["mid"]), "v": int(x["value"])})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["v"] < b["v"]
	)
	var out: Array = []
	for i in need:
		out.append(items[i]["mid"])
	return out


func _destroy_rituals_by_mids(target: int, mids: Array) -> void:
	if mids.is_empty():
		return
	var kill: Dictionary = {}
	for m in mids:
		kill[int(m)] = true
	var pl: Dictionary = _players[target]
	var field: Array = pl["field"]
	var keep: Array = []
	for x in field:
		if kill.has(int(x["mid"])):
			pl["ritual_grave"].append(x)
		else:
			keep.append(x)
	pl["field"] = keep
	_log("Wrath destroys %d ritual(s) on P%d." % [mids.size(), target])


func _destroy_nobles_by_mids(target: int, mids: Array) -> void:
	if mids.is_empty():
		return
	var kill: Dictionary = {}
	for m in mids:
		kill[int(m)] = true
	var pl: Dictionary = _players[target]
	var field_nobles: Array = pl["noble_field"]
	var keep: Array = []
	for x in field_nobles:
		if kill.has(int(x["mid"])):
			pl["noble_grave"].append(x)
		else:
			keep.append(x)
	pl["noble_field"] = keep
	_log("Dethrone destroys %d noble(s) on P%d." % [mids.size(), target])


func _dethrone_resolve_mids(target: int, client_mids: Array) -> Array:
	var field_nobles: Array = _players[target]["noble_field"]
	if field_nobles.is_empty():
		return []
	if field_nobles.size() == 1:
		return [int(field_nobles[0].get("mid", -1))]
	var mids: Dictionary = {}
	for m in client_mids:
		mids[int(m)] = true
	if mids.size() == 1:
		var only_mid := int(mids.keys()[0])
		for n in field_nobles:
			if int(n.get("mid", -1)) == only_mid:
				return [only_mid]
	return []


func can_discard_for_draw(p: int) -> bool:
	return phase == Phase.MAIN and p == current and not discard_draw_used and not _players[p]["hand"].is_empty()


func discard_for_draw(p: int, hand_idx: int) -> String:
	if not can_discard_for_draw(p):
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	if hand_idx < 0 or hand_idx >= hand.size():
		return "illegal"
	_move_hand_card_to_discard(pl, hand, hand_idx)
	discard_draw_used = true
	if not _draw_one_attempt(p):
		return "ok"
	_log("P%d discard-for-draw." % p)
	return "ok"


func _move_hand_card_to_discard(pl: Dictionary, hand: Array, idx: int) -> void:
	var c: Variant = hand[idx]
	hand.remove_at(idx)
	var kind := _card_kind(c)
	if kind == "ritual":
		pl["ritual_grave"].append(c)
	elif kind == "noble":
		pl["noble_grave"].append(c)
	else:
		pl["inc_discard"].append(c)


func end_turn(p: int, discard_indices: Array) -> String:
	if phase != Phase.MAIN or p != current:
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	var need := maxi(0, hand.size() - MAX_HAND_END)
	if discard_indices.size() != need:
		return "illegal_discard_count"
	var setx: Dictionary = {}
	for idx in discard_indices:
		var i := int(idx)
		if i < 0 or i >= hand.size() or setx.has(i):
			return "illegal_discard_idx"
		setx[i] = true
	var remove_desc: Array = discard_indices.duplicate()
	remove_desc.sort()
	remove_desc.reverse()
	for idx in remove_desc:
		var i2 := int(idx)
		_move_hand_card_to_discard(pl, hand, i2)
	current = 1 - p
	_log("P%d ends turn." % p)
	if phase != Phase.GAME_OVER:
		_turn_start_draw()
	return "ok"


func hand_size(p: int) -> int:
	return _players[p]["hand"].size()


func _card_at_hand(p: int, idx: int) -> Variant:
	var hand: Array = _players[p]["hand"]
	if idx < 0 or idx >= hand.size():
		return null
	return hand[idx]


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 40:
		log_lines.remove_at(0)


func _load_noble_hooks() -> void:
	_noble_hooks.clear()
	var dir := DirAccess.open(NOBLES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var fn := dir.get_next()
		if fn == "":
			break
		if dir.current_is_dir() or not fn.ends_with(".gd"):
			continue
		var script := load("%s/%s" % [NOBLES_DIR, fn])
		if script == null:
			continue
		var hook: Variant = script.new()
		if hook == null or not hook.has_method("build_definition"):
			continue
		var def: Variant = hook.call("build_definition")
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var nid := str((def as Dictionary).get("id", ""))
		if nid.is_empty():
			continue
		_noble_hooks[nid] = hook


func known_nobles() -> Array:
	var out: Array = []
	for nid in _noble_hooks.keys():
		var hook: Variant = _noble_hooks[nid]
		var def: Variant = hook.call("build_definition")
		if typeof(def) == TYPE_DICTIONARY:
			out.append(def)
	return out


func _hook_for_noble(noble: Dictionary) -> Variant:
	var nid := str(noble.get("noble_id", ""))
	if _noble_hooks.has(nid):
		return _noble_hooks[nid]
	return null


func _find_noble_on_field(p: int, noble_mid: int) -> Dictionary:
	for n in _players[p]["noble_field"]:
		if int(n.get("mid", -1)) == noble_mid:
			return n
	return {}


func _mark_noble_used_this_turn(p: int, noble_mid: int) -> void:
	var nobles: Array = _players[p]["noble_field"]
	for i in nobles.size():
		if int(nobles[i].get("mid", -1)) == noble_mid:
			var n: Dictionary = nobles[i]
			n["used_turn"] = turn_number
			nobles[i] = n
			break

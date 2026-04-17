class_name ArcanaMatchState
extends RefCounted

const CardTraits = preload("res://card_traits.gd")

const MAX_HAND_END := 7
const START_HAND := 5
const WIN_POWER := 20
const NOBLES_DIR := "res://nobles"

const TEMPLE_PLAY_COST := 7
const TEMPLE_PHAEDRA := "phaedra_illusion"
const TEMPLE_DELPHA := "delpha_oracles"
const TEMPLE_GOTHA := "gotha_illness"

enum Phase { MAIN, GAME_OVER }

var rng: RandomNumberGenerator
var phase: Phase = Phase.MAIN
var current: int
var ritual_played_this_turn: bool = false
var noble_played_this_turn: bool = false
var temple_played_this_turn: bool = false
var discard_draw_used: bool
var winner: int = -1
var empty_deck_end: bool = false
var log_lines: PackedStringArray
var turn_number: int = 0
var goldfish: bool = false
var _starting_player: int = 0
var _mulligan_decision_pending: Array[bool] = [true, true]
var _mulligan_used: Array[bool] = [false, false]
var _mulligan_bottom_needed: Array[int] = [0, 0]

var _players: Array[Dictionary]
var _noble_hooks: Dictionary = {}

var _woe_pending_instigator: int = -1
var _woe_pending_victim: int = -1
var _woe_pending_amount: int = 0
var _woe_pending_spell_card: Variant = null
var _woe_pending_spell_to_abyss: bool = false
var _woe_pending_revive_wrapper: Variant = null
var _woe_pending_noble_mid: int = -1
var _scion_pending: Dictionary = {}
var _scion_pending_next_id: int = 1


func _card_kind(c: Variant) -> String:
	if c == null or typeof(c) != TYPE_DICTIONARY:
		return ""
	return CardTraits.effective_kind(c as Dictionary)


func _noble_on_field(p: int, noble_id: String) -> bool:
	for x in _players[p]["noble_field"]:
		if str(x.get("noble_id", "")) == noble_id:
			return true
	return false


func insight_effective_n(p: int, base: int) -> int:
	return base + (1 if _noble_on_field(p, "xytzr_emanation") else 0)


func _woe_discard_need(instigator: int, value: int, victim: int) -> int:
	var hs: int = _players[victim]["hand"].size()
	var extra := 1 if _noble_on_field(instigator, "zytzr_annihilation") else 0
	return mini(value + extra, hs)


func effective_wrath_destroy_count(instigator: int, value: int) -> int:
	var base := _wrath_destroy_count(value)
	if base == 0:
		return 0
	if _noble_on_field(instigator, "zytzr_annihilation"):
		return base + 1
	return base


func can_play_aeoiu_ritual(p: int) -> bool:
	return not _ritual_crypt_cards(_players[p]).is_empty()


func _validate_yytzr_extra_sacrifice(p: int, primary_mids: Dictionary, extra: Array) -> bool:
	var esum := 0
	for m in extra:
		var mid := int(m)
		if primary_mids.has(mid):
			return false
		var found := false
		for x in _players[p]["field"]:
			if int(x["mid"]) == mid:
				esum += int(x["value"])
				found = true
				break
		if not found:
			return false
	return esum >= 2


func _init(p0_deck: Array, p1_deck: Array, p0_first: bool, p_rng: RandomNumberGenerator, p_goldfish: bool) -> void:
	rng = p_rng
	goldfish = p_goldfish
	_load_noble_hooks()
	_players = [
		_make_player(p0_deck),
		_make_player(p1_deck)
	]
	if goldfish:
		_starting_player = 0
	else:
		_starting_player = 0 if p0_first else 1
	current = _starting_player
	discard_draw_used = false
	phase = Phase.MAIN
	_deal_start()
	_start_mulligan()


func _make_player(deck_template: Array) -> Dictionary:
	var d: Array = deck_template.duplicate(true)
	_shuffle(d)
	return {
		"deck": d,
		"hand": [],
		"field": [],
		"noble_field": [],
		"temple_field": [],
		"crypt": [],
		"inc_abyss": [],
		"deck_crypt": []
	}


func _temple_field_safe(p: int) -> Array:
	var pl: Dictionary = _players[p]
	if not pl.has("temple_field"):
		pl["temple_field"] = []
	return pl["temple_field"] as Array


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _deal_start() -> void:
	if goldfish:
		for _i in START_HAND:
			_draw_card_silent(0)
		return
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
	if _is_mulligan_active():
		return
	ritual_played_this_turn = false
	noble_played_this_turn = false
	temple_played_this_turn = false
	turn_number += 1
	if _skip_draw_for_gotha(current):
		discard_draw_used = false
		_log("Turn P%d draw step skipped (Gotha)." % current)
		return
	if not _draw_one_attempt(current):
		return
	discard_draw_used = false
	_log("Turn P%d draw step." % current)


func _skip_draw_for_gotha(p: int) -> bool:
	for x in _temple_field_safe(p):
		if str(x.get("temple_id", "")) == TEMPLE_GOTHA:
			return true
	return false


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
	if goldfish and trigger_player == 0:
		winner = 1
		phase = Phase.GAME_OVER
		_log("Goldfish: could not draw from empty deck.")
		return
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
	if _is_mulligan_active():
		return
	if ritual_power(p) >= WIN_POWER:
		winner = p
		phase = Phase.GAME_OVER
		_log("P%d reached %d ritual power." % [p, WIN_POWER])


func concede(p: int) -> String:
	if p < 0 or p > 1:
		return "bad_player"
	if phase == Phase.GAME_OVER:
		return "game_over"
	winner = 1 - p
	phase = Phase.GAME_OVER
	_log("P%d conceded. P%d wins." % [p, winner])
	return "ok"


func _start_mulligan() -> void:
	_mulligan_decision_pending = [true, true]
	_mulligan_used = [false, false]
	_mulligan_bottom_needed = [0, 0]
	if goldfish:
		_mulligan_decision_pending[1] = false
	current = _starting_player
	if goldfish:
		_log("Starting hand dealt. You may take one London mulligan.")
	else:
		_log("Starting hands dealt. Each player may take one London mulligan.")


func _is_mulligan_active() -> bool:
	return _mulligan_decision_pending[0] or _mulligan_decision_pending[1] or _mulligan_bottom_needed[0] > 0 or _mulligan_bottom_needed[1] > 0


func _mulligan_player_needs_action(p: int) -> bool:
	return _mulligan_decision_pending[p] or _mulligan_bottom_needed[p] > 0


func _advance_mulligan_or_begin_game() -> void:
	if not _is_mulligan_active():
		current = _starting_player
		_turn_start_draw()
		return
	if _mulligan_player_needs_action(_starting_player):
		current = _starting_player
		return
	current = 1 - _starting_player


func choose_starting_hand(p: int, take_mulligan: bool) -> String:
	if phase != Phase.MAIN or not _is_mulligan_active() or p != current:
		return "illegal"
	if _mulligan_bottom_needed[p] > 0:
		return "need_bottom"
	if not _mulligan_decision_pending[p]:
		return "already_chosen"
	if take_mulligan:
		if _mulligan_used[p]:
			return "illegal"
		var pl: Dictionary = _players[p]
		var deck: Array = pl["deck"]
		var hand: Array = pl["hand"]
		for c in hand:
			deck.append(c)
		hand.clear()
		_shuffle(deck)
		for _i in START_HAND:
			_draw_card_silent(p)
		_mulligan_used[p] = true
		_mulligan_bottom_needed[p] = 1
		_log("P%d takes a London mulligan." % p)
	else:
		_log("P%d keeps opening hand." % p)
	_mulligan_decision_pending[p] = false
	_advance_mulligan_or_begin_game()
	return "ok"


func bottom_mulligan_card(p: int, hand_idx: int) -> String:
	if phase != Phase.MAIN or not _is_mulligan_active() or p != current:
		return "illegal"
	if _mulligan_bottom_needed[p] <= 0:
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	if hand_idx < 0 or hand_idx >= hand.size():
		return "illegal"
	var c: Variant = hand[hand_idx]
	hand.remove_at(hand_idx)
	var deck: Array = pl["deck"]
	deck.insert(0, c)
	_mulligan_bottom_needed[p] -= 1
	_log("P%d puts 1 card on bottom after mulligan." % p)
	_advance_mulligan_or_begin_game()
	return "ok"


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
	var scion_for_player := _scion_pending_player_view(for_player)
	return {
		"phase": int(phase),
		"turn_number": turn_number,
		"current": current,
		"mulligan_active": _is_mulligan_active(),
		"your_mulligan_decision_pending": _mulligan_decision_pending[for_player],
		"your_can_mulligan": _mulligan_decision_pending[for_player] and not _mulligan_used[for_player] and _mulligan_bottom_needed[for_player] == 0,
		"your_mulligan_bottom_needed": _mulligan_bottom_needed[for_player],
		"your_ritual_played": for_player == current and ritual_played_this_turn,
		"your_noble_played": for_player == current and noble_played_this_turn,
		"your_temple_played": for_player == current and temple_played_this_turn,
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
		"your_temples": _temple_field_safe(for_player).duplicate(true),
		"opp_temples": _temple_field_safe(opp).duplicate(true),
		"your_power": ritual_power(for_player),
		"opp_power": ritual_power(opp),
		"your_inc_disc": _inc_crypt_cards(_players[for_player]).size(),
		"opp_inc_disc": _inc_crypt_cards(_players[opp]).size(),
		"your_inc_discard_cards": _inc_crypt_cards(_players[for_player]).duplicate(true),
		"opp_inc_discard_cards": _inc_crypt_cards(_players[opp]).duplicate(true),
		"your_crypt_cards": (_players[for_player]["crypt"] as Array).duplicate(true),
		"opp_crypt_cards": (_players[opp]["crypt"] as Array).duplicate(true),
		"your_inc_abyss_cards": _players[for_player]["inc_abyss"].duplicate(true),
		"opp_inc_abyss_cards": _players[opp]["inc_abyss"].duplicate(true),
		"your_ritual_crypt_cards": _ritual_crypt_cards(_players[for_player]).duplicate(true),
		"opp_ritual_crypt_cards": _ritual_crypt_cards(_players[opp]).duplicate(true),
		"woe_pending_you_respond": _woe_pending_instigator >= 0 and for_player == _woe_pending_victim,
		"woe_pending_waiting": _woe_pending_instigator >= 0 and for_player == _woe_pending_instigator,
		"woe_pending_amount": _woe_pending_amount if _woe_pending_instigator >= 0 else 0,
		"scion_pending_you_respond": bool(scion_for_player.get("you_respond", false)),
		"scion_pending_waiting": bool(scion_for_player.get("waiting", false)),
		"scion_pending_type": str(scion_for_player.get("type", "")),
		"scion_pending_id": int(scion_for_player.get("id", -1)),
		"log": log_lines.duplicate(),
		"goldfish": goldfish
	}


func can_play_ritual(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current or ritual_played_this_turn:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
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
	if phase != Phase.MAIN or _is_mulligan_active() or p != current or noble_played_this_turn:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
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


func _valid_temple_id(tid: String) -> bool:
	return tid == TEMPLE_PHAEDRA or tid == TEMPLE_DELPHA or tid == TEMPLE_GOTHA


func can_play_temple(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current or temple_played_this_turn:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "temple":
		return false
	var tid := str((c as Dictionary).get("temple_id", ""))
	if not _valid_temple_id(tid):
		return false
	return _can_sacrifice(p, TEMPLE_PLAY_COST)


func play_temple(p: int, hand_idx: int, sacrifice_mids: Array) -> String:
	if not can_play_temple(p, hand_idx):
		return "illegal"
	var c: Variant = _card_at_hand(p, hand_idx)
	var tid := str((c as Dictionary).get("temple_id", ""))
	if not _valid_temple_id(tid):
		return "illegal"
	var mids: Dictionary = {}
	for m in sacrifice_mids:
		mids[int(m)] = true
	if not _sacrifice_valid(p, TEMPLE_PLAY_COST, mids):
		mids.clear()
		for mid in _greedy_sacrifice_mids_for_player(p, TEMPLE_PLAY_COST):
			mids[int(mid)] = true
		if not _sacrifice_valid(p, TEMPLE_PLAY_COST, mids):
			return "illegal_sacrifice"
	_apply_sacrifice(p, mids)
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	hand.remove_at(hand_idx)
	var tmid := _next_temple_mid(pl)
	var entry := {
		"mid": tmid,
		"temple_id": tid,
		"name": str((c as Dictionary).get("name", tid)),
		"used_turn": -1
	}
	_temple_field_safe(p).append(entry)
	temple_played_this_turn = true
	_log("P%d plays temple %s." % [p, entry["name"]])
	return "ok"


func _next_temple_mid(pl: Dictionary) -> int:
	var tf: Array = pl["temple_field"] if pl.has("temple_field") else []
	var mx := 0
	for x in tf:
		mx = maxi(mx, int(x.get("mid", 0)))
	return mx + 1


func _next_mid(pl: Dictionary) -> int:
	var mx := 0
	for x in pl["field"]:
		mx = maxi(mx, int(x["mid"]))
	for x in _ritual_crypt_cards(pl):
		mx = maxi(mx, int(x.get("mid", 0)))
	return mx + 1


func _next_noble_mid(pl: Dictionary) -> int:
	var mx := 0
	for x in pl["noble_field"]:
		mx = maxi(mx, int(x["mid"]))
	for x in _noble_crypt_cards(pl):
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


func _woe_waiting_on_response() -> bool:
	return _woe_pending_instigator >= 0


func _woe_clear_pending() -> void:
	_woe_pending_instigator = -1
	_woe_pending_victim = -1
	_woe_pending_amount = 0
	_woe_pending_spell_card = null
	_woe_pending_spell_to_abyss = false
	_woe_pending_revive_wrapper = null
	_woe_pending_noble_mid = -1


func _scion_waiting_on_response() -> bool:
	return not _scion_pending.is_empty()


func _scion_clear_pending() -> void:
	_scion_pending.clear()


func _scion_pending_player_view(for_player: int) -> Dictionary:
	if _scion_pending.is_empty():
		return {}
	var owner := int(_scion_pending.get("player", -1))
	if owner < 0:
		return {}
	return {
		"you_respond": owner == for_player,
		"waiting": owner != for_player,
		"type": str(_scion_pending.get("type", "")),
		"id": int(_scion_pending.get("id", -1))
	}


func _set_scion_pending(player: int, ptype: String) -> void:
	_scion_pending = {
		"id": _scion_pending_next_id,
		"player": player,
		"type": ptype
	}
	_scion_pending_next_id += 1


func _queue_post_effect_scion_trigger(p: int, verb: String) -> void:
	var v := verb.to_lower()
	if v == "insight":
		if _noble_on_field(p, "rmrsk_emanation"):
			_set_scion_pending(p, "rmrsk_draw")
		return
	if v == "burn" or v == "revive":
		if _noble_on_field(p, "smrsk_occultation"):
			_set_scion_pending(p, "smrsk_burn")
		return
	if v == "wrath":
		if _noble_on_field(p, "tmrsk_annihilation"):
			_set_scion_pending(p, "tmrsk_woe")
			_log("P%d: Tmrsk — choose Woe 1 (after Wrath)." % p)


func _ritual_value_for_mid(p: int, ritual_mid: int) -> int:
	for x in _players[p]["field"]:
		if int(x.get("mid", -1)) == ritual_mid:
			return int(x.get("value", 0))
	return -1


func submit_scion_trigger_response(p: int, action: String, ctx: Dictionary = {}) -> String:
	if not _scion_waiting_on_response():
		return "illegal"
	var expected_id := int(_scion_pending.get("id", -1))
	var provided_id := int(ctx.get("scion_id", -1))
	if expected_id < 0 or provided_id != expected_id:
		return "illegal"
	var owner := int(_scion_pending.get("player", -1))
	if p != owner:
		return "illegal"
	var ptype := str(_scion_pending.get("type", ""))
	var a := action.to_lower()
	if a != "accept" and a != "skip":
		return "illegal"
	if a == "skip":
		_scion_clear_pending()
		match ptype:
			"rmrsk_draw":
				_log("P%d skips Rmrsk trigger." % p)
			"smrsk_burn":
				_log("P%d skips Smrsk trigger." % p)
			"tmrsk_woe":
				_log("P%d skips Tmrsk trigger." % p)
		return "ok"
	match ptype:
		"rmrsk_draw":
			_scion_clear_pending()
			_draw_n(p, 1)
			_log("P%d resolves Rmrsk (draw 1)." % p)
			return "ok"
		"smrsk_burn":
			var ritual_mid := int(ctx.get("ritual_mid", -1))
			var power := _ritual_value_for_mid(p, ritual_mid)
			if power <= 0:
				return "illegal"
			_scion_clear_pending()
			_apply_sacrifice(p, {ritual_mid: true})
			var berr := execute_incantation_effect(p, "burn", power, [], {"mill_target": p})
			if berr != "ok":
				return berr
			_log("P%d resolves Smrsk (sacrifice %d-power ritual; Burn self %d)." % [p, power, power])
			return "ok"
		"tmrsk_woe":
			var wt := int(ctx.get("woe_target", -1))
			var opp := 1 - p
			if wt != p and wt != opp:
				return "illegal_target"
			var need := _woe_discard_need(p, 1, wt)
			if wt == opp and need > 0:
				_scion_clear_pending()
				_woe_pending_instigator = p
				_woe_pending_victim = wt
				_woe_pending_amount = need
				_woe_pending_spell_card = null
				_woe_pending_spell_to_abyss = false
				_woe_pending_revive_wrapper = null
				_woe_pending_noble_mid = -1
				_log("P%d resolves Tmrsk; Woe pending on P%d." % [p, wt])
				return "ok"
			_scion_clear_pending()
			var werr := execute_incantation_effect(p, "woe", 1, [], ctx)
			if werr != "ok":
				return werr
			_log("P%d resolves Tmrsk (Woe 1)." % p)
			return "ok"
		_:
			return "illegal"


func can_play_incantation(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
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
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
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


func _woe_indices_valid(hand_sz: int, need: int, indices: Array) -> bool:
	if need <= 0:
		return indices.is_empty()
	if indices.size() != need:
		return false
	var seen: Dictionary = {}
	for x in indices:
		var i := int(x)
		if i < 0 or i >= hand_sz or seen.has(i):
			return false
		seen[i] = true
	return seen.size() == need


func _discard_hand_chosen_indices(target: int, indices: Array) -> void:
	var pl: Dictionary = _players[target]
	var hand: Array = pl["hand"]
	var sorted: Array = indices.duplicate()
	sorted.sort()
	for k in range(sorted.size() - 1, -1, -1):
		var idx := int(sorted[k])
		_move_hand_card_to_discard(pl, hand, idx)
	_log("Woe: P%d discards %d chosen card(s)." % [target, indices.size()])


func execute_incantation_effect(p: int, verb: String, value: int, wrath_resolved: Array, ctx: Dictionary) -> String:
	var v := verb.to_lower()
	var opp := 1 - p
	match v:
		"seek":
			_draw_n(p, value)
			if _noble_on_field(p, "xytzr_emanation"):
				_draw_n(p, 1)
			return "ok"
		"insight":
			var tgt := int(ctx.get("insight_target", -1))
			if tgt != p and tgt != opp:
				return "illegal_target"
			var eff := insight_effective_n(p, value)
			var deck: Array = _players[tgt]["deck"]
			var take := mini(eff, deck.size())
			var parsed: Dictionary = _parse_insight_ctx(take, ctx)
			if not bool(parsed.get("ok", false)):
				return "illegal_insight_perm"
			var top_a: Array = parsed["top"] as Array
			var bot_a: Array = parsed["bottom"] as Array
			_apply_insight(tgt, eff, top_a, bot_a)
			return "ok"
		"burn":
			var mt := int(ctx.get("mill_target", -1))
			if mt != 0 and mt != 1:
				return "illegal_target"
			var mill_n := value * 2
			if _noble_on_field(p, "yytzr_occultation"):
				mill_n += 3
			_mill(mt, mill_n)
			return "ok"
		"woe":
			var wt := int(ctx.get("woe_target", -1))
			if wt != p and wt != opp:
				return "illegal_target"
			var hand_sz: int = _players[wt]["hand"].size()
			var need := _woe_discard_need(p, value, wt)
			var widx: Array = ctx.get("woe_indices", []) as Array
			if need > 0 and not _woe_indices_valid(hand_sz, need, widx):
				return "illegal_woe_indices"
			if need > 0:
				_discard_hand_chosen_indices(wt, widx)
			return "ok"
		"revive":
			return "illegal"
		"wrath":
			if effective_wrath_destroy_count(p, value) == 0:
				return "illegal"
			_destroy_rituals_by_mids(opp, wrath_resolved)
			return "ok"
		_:
			return "ok"


func _validate_play_ctx(p: int, verb: String, value: int, wrath_mids: Array, ctx: Dictionary) -> String:
	var v := verb.to_lower()
	var opp := 1 - p
	match v:
		"insight":
			var tgt := int(ctx.get("insight_target", -1))
			if tgt != p and tgt != opp:
				return "illegal_target"
			var eff := insight_effective_n(p, value)
			var take := mini(eff, _players[tgt]["deck"].size())
			var parsed: Dictionary = _parse_insight_ctx(take, ctx)
			if not bool(parsed.get("ok", false)):
				return "illegal_insight_perm"
			return "ok"
		"burn":
			var mt := int(ctx.get("mill_target", -1))
			if mt != 0 and mt != 1:
				return "illegal_target"
			return "ok"
		"woe":
			var wt := int(ctx.get("woe_target", -1))
			if wt != p and wt != opp:
				return "illegal_target"
			var hand_sz: int = _players[wt]["hand"].size()
			var need := _woe_discard_need(p, value, wt)
			if wt == p:
				var widx: Array = ctx.get("woe_indices", []) as Array
				if need > 0 and not _woe_indices_valid(hand_sz, need, widx):
					return "illegal_woe_indices"
			return "ok"
		"wrath":
			if effective_wrath_destroy_count(p, value) == 0:
				return "illegal"
			if (_players[opp]["field"] as Array).is_empty():
				return "ok"
			var wr := _wrath_resolve_mids(opp, value, wrath_mids, p)
			if wr.is_empty() and effective_wrath_destroy_count(p, value) > 0:
				return "illegal"
			return "ok"
		"seek":
			return "ok"
		"revive":
			return _validate_revive_chain(p, value, ctx)
		_:
			return "ok"


func _validate_revive_chain(p: int, value: int, ctx: Dictionary) -> String:
	var steps: Array = ctx.get("revive_steps", []) as Array
	if steps.is_empty() and value == 1:
		steps = [ctx]
	var yyt: Array = ctx.get("yytzr_extra_sac_mids", []) as Array
	var want_steps := value
	if not yyt.is_empty():
		if not _noble_on_field(p, "yytzr_occultation"):
			return "illegal"
		want_steps = value + 1
	if steps.size() != want_steps:
		return "illegal"
	var sim: Array = _inc_crypt_cards(_players[p]).duplicate()
	for step in steps:
		if typeof(step) != TYPE_DICTIONARY:
			return "illegal"
		var d: Dictionary = step
		if bool(d.get("revive_skip", false)):
			continue
		var cidx := int(d.get("revive_crypt_idx", -1))
		if cidx < 0 or cidx >= sim.size():
			return "illegal"
		var cc: Variant = sim[cidx]
		sim.remove_at(cidx)
		if _card_kind(cc) != "incantation":
			return "illegal"
		var cdict: Dictionary = cc
		var cv := str(cdict.get("verb", "")).to_lower()
		var cn := int(cdict.get("value", 0))
		if cv == "revive" or cv == "wrath":
			return "illegal"
		var nested: Dictionary = d.get("nested", {}) as Dictionary
		var wr_mids: Array = nested.get("wrath_mids", []) as Array
		if _validate_play_ctx(p, cv, cn, wr_mids, nested) != "ok":
			return "illegal"
	return "ok"


func _run_revive_steps_after_payment(p: int, value: int, ctx: Dictionary, payment_text: String, revive_wrapper: Dictionary) -> String:
	var steps: Array = ctx.get("revive_steps", []) as Array
	if steps.is_empty() and value == 1:
		steps = [ctx]
	var pl: Dictionary = _players[p]
	var any_cast := false
	for step in steps:
		if typeof(step) != TYPE_DICTIONARY:
			return "illegal"
		if not bool((step as Dictionary).get("revive_skip", false)):
			any_cast = true
			break
	if not any_cast:
		pl["crypt"].append(revive_wrapper)
		_log("P%d plays Revive %d (%s) — skipped." % [p, value, payment_text])
		_check_power_win(p)
		return "ok"
	for step in steps:
		if typeof(step) != TYPE_DICTIONARY:
			return "illegal"
		var d: Dictionary = step
		if bool(d.get("revive_skip", false)):
			continue
		var cidx := int(d.get("revive_crypt_idx", -1))
		var crypt_idx := _inc_crypt_index_to_crypt_index(pl, cidx)
		if crypt_idx < 0:
			return "illegal"
		var crypt: Array = pl["crypt"]
		var crypt_card: Dictionary = crypt[crypt_idx].duplicate(true)
		crypt.remove_at(crypt_idx)
		var nested: Dictionary = d.get("nested", {}) as Dictionary
		var cv := str(crypt_card.get("verb", "")).to_lower()
		var cn := int(crypt_card.get("value", 0))
		if cv == "wrath":
			crypt.insert(crypt_idx, crypt_card)
			return "illegal"
		var wr_mids: Array = nested.get("wrath_mids", []) as Array
		var wr_r := _wrath_resolve_mids(1 - p, cn, wr_mids, p)
		if cv == "woe":
			var wt := int(nested.get("woe_target", -1))
			var opp := 1 - p
			var need := _woe_discard_need(p, cn, wt)
			if wt == opp and need > 0:
				_woe_pending_instigator = p
				_woe_pending_victim = wt
				_woe_pending_amount = need
				_woe_pending_spell_card = crypt_card
				_woe_pending_spell_to_abyss = true
				_woe_pending_revive_wrapper = revive_wrapper
				_woe_pending_noble_mid = -1
				_log("P%d plays Revive %d (%s); Woe pending on P%d." % [p, value, payment_text, wt])
				return "ok"
		var err := execute_incantation_effect(p, cv, cn, wr_r, nested)
		if err != "ok":
			crypt.insert(crypt_idx, crypt_card)
			return err
		pl["inc_abyss"].append(crypt_card)
		_log("P%d Revive casts %s %d from crypt (%s)." % [p, cv, cn, payment_text])
	pl["crypt"].append(revive_wrapper)
	_log("P%d plays Revive %d (%s)." % [p, value, payment_text])
	_check_power_win(p)
	return "ok"


func submit_woe_discard(p: int, indices: Array) -> String:
	if not _woe_waiting_on_response():
		return "illegal"
	if p != _woe_pending_victim:
		return "illegal"
	var inst := _woe_pending_instigator
	var amt := _woe_pending_amount
	var hand_sz: int = _players[p]["hand"].size()
	var need := mini(amt, hand_sz)
	if need > 0 and not _woe_indices_valid(hand_sz, need, indices):
		return "illegal"
	if need > 0:
		_discard_hand_chosen_indices(p, indices)
	var spell: Variant = _woe_pending_spell_card
	var spell_to_abyss := _woe_pending_spell_to_abyss
	var wrap_card: Variant = _woe_pending_revive_wrapper
	var noble_mid := _woe_pending_noble_mid
	_woe_clear_pending()
	var pli: Dictionary = _players[inst]
	if spell != null:
		if spell_to_abyss:
			pli["inc_abyss"].append(spell)
		else:
			pli["crypt"].append(spell)
	if wrap_card != null:
		pli["crypt"].append(wrap_card)
	if noble_mid >= 0:
		_mark_noble_used_this_turn(inst, noble_mid)
	_log("Woe response complete (victim P%d)." % p)
	if not _scion_waiting_on_response():
		_queue_post_effect_scion_trigger(inst, "woe")
	_check_power_win(inst)
	return "ok"


func apply_noble_spell_like(p: int, noble_mid: int, verb: String, value: int, wrath_mids: Array, ctx: Dictionary) -> String:
	if not can_activate_noble(p, noble_mid):
		return "illegal"
	var noble := _find_noble_on_field(p, noble_mid)
	var nid := str(noble.get("noble_id", ""))
	var v := verb.to_lower()
	match nid:
		"bndrr_incantation":
			if v != "burn" or value != 1:
				return "illegal"
		"wndrr_incantation":
			if v != "woe" or value != 1:
				return "illegal"
		"sndrr_incantation":
			if v != "seek" or value != 1:
				return "illegal"
		_:
			return "illegal"
	if _validate_play_ctx(p, v, value, wrath_mids, ctx) != "ok":
		return "illegal"
	var wr_r: Array = []
	if v == "wrath":
		wr_r = _wrath_resolve_mids(1 - p, value, wrath_mids, p)
	if v == "woe":
		var wt := int(ctx.get("woe_target", -1))
		var opp := 1 - p
		var need := _woe_discard_need(p, value, wt)
		if wt == opp and need > 0:
			_woe_pending_instigator = p
			_woe_pending_victim = wt
			_woe_pending_amount = need
			_woe_pending_spell_card = null
			_woe_pending_spell_to_abyss = false
			_woe_pending_revive_wrapper = null
			_woe_pending_noble_mid = noble_mid
			_log("P%d activates Wndrr; Woe pending on P%d." % [p, wt])
			return "ok"
	var err := execute_incantation_effect(p, v, value, wr_r, ctx)
	if err != "ok":
		return err
	_queue_post_effect_scion_trigger(p, v)
	_mark_noble_used_this_turn(p, noble_mid)
	match nid:
		"bndrr_incantation":
			_log("P%d activates Bndrr (Burn 1)." % p)
		"wndrr_incantation":
			_log("P%d activates Wndrr (Woe 1)." % p)
		"sndrr_incantation":
			_log("P%d activates Sndrr (Seek 1)." % p)
		_:
			pass
	return "ok"


func apply_noble_revive_from_crypt(p: int, noble_mid: int, ctx: Dictionary) -> String:
	if not can_activate_noble(p, noble_mid):
		return "illegal"
	var noble := _find_noble_on_field(p, noble_mid)
	if str(noble.get("noble_id", "")) != "rndrr_incantation":
		return "illegal"
	if _validate_play_ctx(p, "revive", 1, [], ctx) != "ok":
		return "illegal"
	var steps: Array = ctx.get("revive_steps", []) as Array
	if steps.is_empty():
		steps = [ctx]
	var yyt: Array = ctx.get("yytzr_extra_sac_mids", []) as Array
	if steps.size() > 2:
		return "illegal"
	if steps.size() == 2:
		if not _validate_yytzr_extra_sacrifice(p, {}, yyt):
			return "illegal"
		var ed: Dictionary = {}
		for m in yyt:
			ed[int(m)] = true
		_apply_sacrifice(p, ed)
	var d0: Dictionary = steps[0]
	if bool(d0.get("revive_skip", false)):
		_mark_noble_used_this_turn(p, noble_mid)
		_log("P%d activates Rndrr (Revive 1 skipped)." % p)
		return "ok"
	var pl: Dictionary = _players[p]
	for si in steps.size():
		var d: Dictionary = steps[si]
		if bool(d.get("revive_skip", false)):
			continue
		var cidx := int(d.get("revive_crypt_idx", -1))
		var crypt_idx := _inc_crypt_index_to_crypt_index(pl, cidx)
		if crypt_idx < 0:
			return "illegal"
		var crypt: Array = pl["crypt"]
		var crypt_card: Dictionary = crypt[crypt_idx].duplicate(true)
		crypt.remove_at(crypt_idx)
		var nested: Dictionary = d.get("nested", {}) as Dictionary
		var cv := str(crypt_card.get("verb", "")).to_lower()
		var cn := int(crypt_card.get("value", 0))
		if cv == "wrath":
			crypt.insert(crypt_idx, crypt_card)
			return "illegal"
		var wr_mids: Array = nested.get("wrath_mids", []) as Array
		var wr_r := _wrath_resolve_mids(1 - p, cn, wr_mids, p)
		if cv == "woe":
			var wt := int(nested.get("woe_target", -1))
			var need := _woe_discard_need(p, cn, wt)
			if wt == 1 - p and need > 0:
				_woe_pending_instigator = p
				_woe_pending_victim = wt
				_woe_pending_amount = need
				_woe_pending_spell_card = crypt_card
				_woe_pending_spell_to_abyss = true
				_woe_pending_revive_wrapper = null
				_woe_pending_noble_mid = noble_mid
				return "ok"
		var err := execute_incantation_effect(p, cv, cn, wr_r, nested)
		if err != "ok":
			crypt.insert(crypt_idx, crypt_card)
			return err
		pl["inc_abyss"].append(crypt_card)
		_log("P%d Revive casts %s %d from crypt (Rndrr)." % [p, cv, cn])
		_queue_post_effect_scion_trigger(p, cv)
	_mark_noble_used_this_turn(p, noble_mid)
	_queue_post_effect_scion_trigger(p, "revive")
	_log("P%d activates Rndrr (Revive from crypt)." % p)
	return "ok"


func apply_aeoiu_ritual_from_crypt(p: int, noble_mid: int, crypt_idx: int) -> String:
	if not can_activate_noble(p, noble_mid):
		return "illegal"
	var noble := _find_noble_on_field(p, noble_mid)
	if str(noble.get("noble_id", "")) != "aeoiu_rituals":
		return "illegal"
	var pl: Dictionary = _players[p]
	var rg: Array = _ritual_crypt_cards(pl)
	if crypt_idx < 0 or crypt_idx >= rg.size():
		return "illegal"
	var global_crypt_idx := _ritual_crypt_index_to_crypt_index(pl, crypt_idx)
	if global_crypt_idx < 0:
		return "illegal"
	var c: Dictionary = ((pl["crypt"] as Array)[global_crypt_idx] as Dictionary).duplicate(true)
	(pl["crypt"] as Array).remove_at(global_crypt_idx)
	var mid := _next_mid(pl)
	pl["field"].append({"mid": mid, "value": int(c["value"])})
	_mark_noble_used_this_turn(p, noble_mid)
	_log("P%d plays %d-Ritual from crypt (Aeoiu)." % [p, int(c["value"])])
	_check_power_win(p)
	return "ok"


func _find_temple_on_field(p: int, temple_mid: int) -> Dictionary:
	for x in _temple_field_safe(p):
		if int(x.get("mid", -1)) == temple_mid:
			return x
	return {}


func _mark_temple_used_this_turn(p: int, temple_mid: int) -> void:
	var tf: Array = _temple_field_safe(p)
	for i in tf.size():
		if int(tf[i].get("mid", -1)) == temple_mid:
			var d: Dictionary = tf[i]
			d["used_turn"] = turn_number
			tf[i] = d
			break


func can_activate_temple(p: int, temple_mid: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	var t := _find_temple_on_field(p, temple_mid)
	if t.is_empty():
		return false
	if int(t.get("used_turn", -1)) == turn_number:
		return false
	var tid := str(t.get("temple_id", ""))
	if tid == TEMPLE_DELPHA:
		var pl: Dictionary = _players[p]
		if _ritual_crypt_cards(pl).is_empty():
			return false
		if (pl["deck"] as Array).size() < 2:
			return false
		if (pl["field"] as Array).is_empty():
			return false
	return true


func apply_temple_phaedra_insight(p: int, temple_mid: int, insight_target: int, insight_top: Array = [], insight_bottom: Array = []) -> String:
	if not can_activate_temple(p, temple_mid):
		return "illegal"
	var t := _find_temple_on_field(p, temple_mid)
	if str(t.get("temple_id", "")) != TEMPLE_PHAEDRA:
		return "illegal"
	var ctx := {"insight_target": insight_target, "insight_top": insight_top, "insight_bottom": insight_bottom}
	if _validate_play_ctx(p, "insight", 1, [], ctx) != "ok":
		return "illegal"
	var err := execute_incantation_effect(p, "insight", 1, [], ctx)
	if err != "ok":
		return err
	_queue_post_effect_scion_trigger(p, "insight")
	_draw_n(p, 1)
	_mark_temple_used_this_turn(p, temple_mid)
	_log("P%d activates Phaedra (Insight 1, draw 1)." % p)
	return "ok"


func apply_temple_delpha(p: int, temple_mid: int, ritual_mid: int, crypt_idx: int) -> String:
	if not can_activate_temple(p, temple_mid):
		return "illegal"
	var t := _find_temple_on_field(p, temple_mid)
	if str(t.get("temple_id", "")) != TEMPLE_DELPHA:
		return "illegal"
	var pl: Dictionary = _players[p]
	var field: Array = pl["field"]
	var x := 0
	var keep: Array = []
	var removed := false
	for r in field:
		var rm := int(r.get("mid", -1))
		if not removed and rm == ritual_mid:
			x = int(r.get("value", 0))
			removed = true
			continue
		keep.append(r)
	if not removed or x < 1:
		return "illegal"
	if (pl["deck"] as Array).size() < 2 * x:
		return "illegal"
	var abyss_ritual := {"mid": ritual_mid, "type": "ritual", "value": x}
	pl["field"] = keep
	pl["inc_abyss"].append(abyss_ritual)
	var berr := execute_incantation_effect(p, "burn", x, [], {"mill_target": p})
	if berr != "ok":
		pl["field"] = field
		(pl["inc_abyss"] as Array).remove_at((pl["inc_abyss"] as Array).size() - 1)
		return berr
	var rg: Array = _ritual_crypt_cards(pl)
	if crypt_idx < 0 or crypt_idx >= rg.size():
		pl["field"] = field
		(pl["inc_abyss"] as Array).remove_at((pl["inc_abyss"] as Array).size() - 1)
		return "illegal"
	var global_crypt_idx := _ritual_crypt_index_to_crypt_index(pl, crypt_idx)
	if global_crypt_idx < 0:
		pl["field"] = field
		(pl["inc_abyss"] as Array).remove_at((pl["inc_abyss"] as Array).size() - 1)
		return "illegal"
	var c: Dictionary = ((pl["crypt"] as Array)[global_crypt_idx] as Dictionary).duplicate(true)
	(pl["crypt"] as Array).remove_at(global_crypt_idx)
	var rmid := _next_mid(pl)
	pl["field"].append({"mid": rmid, "value": int(c["value"])})
	_mark_temple_used_this_turn(p, temple_mid)
	_log("P%d activates Delpha (send ritual %d to abyss, Burn %d, ritual from crypt)." % [p, ritual_mid, x])
	_check_power_win(p)
	return "ok"


func _gotha_draw_value_for_card(c: Dictionary) -> int:
	var k := _card_kind(c)
	if k == "ritual" or k == "incantation":
		return maxi(0, int(c.get("value", 0)))
	if k == "noble":
		return maxi(0, _noble_play_cost(str(c.get("noble_id", ""))))
	if k == "temple":
		return maxi(0, int(c.get("cost", TEMPLE_PLAY_COST)))
	if k == "dethrone":
		return 4
	return 0


func apply_temple_gotha(p: int, temple_mid: int, hand_idx: int) -> String:
	if not can_activate_temple(p, temple_mid):
		return "illegal"
	var t := _find_temple_on_field(p, temple_mid)
	if str(t.get("temple_id", "")) != TEMPLE_GOTHA:
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	if hand_idx < 0 or hand_idx >= hand.size():
		return "illegal"
	var c: Dictionary = (hand[hand_idx] as Dictionary).duplicate(true)
	var n := _gotha_draw_value_for_card(c)
	if n < 1:
		return "illegal"
	hand.remove_at(hand_idx)
	pl["crypt"].append(c)
	_draw_n(p, n)
	_mark_temple_used_this_turn(p, temple_mid)
	_log("P%d activates Gotha (discard for %d)." % [p, n])
	_check_power_win(p)
	return "ok"


func play_incantation(p: int, hand_idx: int, sacrifice_mids: Array, wrath_mids: Array = [], ctx: Dictionary = {}) -> String:
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
	var verb_raw: String = str(c.get("verb", ""))
	var verb: String = verb_raw.to_lower()
	var ctx_use: Dictionary = ctx.duplicate(true)
	if _validate_play_ctx(p, verb, n, wrath_mids, ctx_use) != "ok":
		return "illegal"
	var yyt_extra: Array = ctx_use.get("yytzr_extra_sac_mids", []) as Array
	if verb == "revive" and not yyt_extra.is_empty():
		if not _noble_on_field(p, "yytzr_occultation"):
			return "illegal"
		var pd_pri: Dictionary = {}
		if need_sac:
			for m in sacrifice_mids:
				pd_pri[int(m)] = true
		if not _validate_yytzr_extra_sacrifice(p, pd_pri, yyt_extra):
			return "illegal"
	var payment_text := _incantation_payment_text(p, n, need_sac, mids)
	_apply_sacrifice(p, mids)
	if verb == "revive" and not yyt_extra.is_empty():
		var ed: Dictionary = {}
		for m in yyt_extra:
			ed[int(m)] = true
		_apply_sacrifice(p, ed)
	var pl: Dictionary = _players[p]
	pl["hand"].remove_at(hand_idx)
	if verb == "revive":
		var rr := _run_revive_steps_after_payment(p, n, ctx_use, payment_text, c)
		if rr == "ok":
			_queue_post_effect_scion_trigger(p, "revive")
		return rr
	var wrath_resolved: Array = []
	if verb == "wrath":
		wrath_resolved = _wrath_resolve_mids(1 - p, n, wrath_mids, p)
	if verb == "woe":
		var wt := int(ctx_use.get("woe_target", -1))
		var opp := 1 - p
		var need := _woe_discard_need(p, n, wt)
		if wt == opp and need > 0:
			_woe_pending_instigator = p
			_woe_pending_victim = wt
			_woe_pending_amount = need
			_woe_pending_spell_card = c
			_woe_pending_spell_to_abyss = false
			_woe_pending_revive_wrapper = null
			_woe_pending_noble_mid = -1
			_log("P%d plays %s %d (%s); Woe pending on P%d." % [p, verb_raw, n, payment_text, wt])
			return "ok"
	execute_incantation_effect(p, verb, n, wrath_resolved, ctx_use)
	_queue_post_effect_scion_trigger(p, verb)
	pl["crypt"].append(c)
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
	pl["crypt"].append(c)
	_log("P%d plays Dethrone %d." % [p, n])
	return "ok"


func can_activate_noble(p: int, noble_mid: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
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
	var nid0 := str(noble.get("noble_id", ""))
	if nid0 == "indrr_incantation":
		return activate_noble_with_insight(p, noble_mid, -1, [])
	if nid0 in ["bndrr_incantation", "wndrr_incantation", "sndrr_incantation", "rndrr_incantation", "aeoiu_rituals"]:
		return "illegal"
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


func activate_noble_with_insight(p: int, noble_mid: int, insight_target: int, insight_top: Array = [], insight_bottom: Array = []) -> String:
	if not can_activate_noble(p, noble_mid):
		return "illegal"
	var noble := _find_noble_on_field(p, noble_mid)
	if str(noble.get("noble_id", "")) == "indrr_incantation":
		var ctx := {"insight_target": insight_target, "insight_top": insight_top, "insight_bottom": insight_bottom}
		if _validate_play_ctx(p, "insight", 2, [], ctx) != "ok":
			return "illegal"
		execute_incantation_effect(p, "insight", 2, [], ctx)
		_queue_post_effect_scion_trigger(p, "insight")
		_mark_noble_used_this_turn(p, noble_mid)
		_log("P%d activates Indrr (Insight %d)." % [p, insight_effective_n(p, 2)])
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
			pl["crypt"].append(x)
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


func resolve_spell_like_effect(p: int, verb: String, value: int, ctx: Dictionary = {}) -> void:
	var v := verb.to_lower()
	var wr: Array = []
	if v == "wrath":
		wr = _wrath_resolve_mids(1 - p, value, [], p)
	execute_incantation_effect(p, v, value, wr, ctx)
	_queue_post_effect_scion_trigger(p, v)


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


func _insight_perm_valid_legacy(take: int, perm: Array) -> bool:
	if perm.size() != take:
		return false
	var seen: Dictionary = {}
	for x in perm:
		var v := int(x)
		if v < 0 or v >= take or seen.has(v):
			return false
		seen[v] = true
	return seen.size() == take


func _insight_split_valid(take: int, top: Array, bottom: Array) -> bool:
	if top.size() + bottom.size() != take:
		return false
	var seen: Dictionary = {}
	for x in top:
		var v := int(x)
		if v < 0 or v >= take or seen.has(v):
			return false
		seen[v] = true
	for x in bottom:
		var v := int(x)
		if v < 0 or v >= take or seen.has(v):
			return false
		seen[v] = true
	return seen.size() == take


func _parse_insight_ctx(take: int, ctx: Dictionary) -> Dictionary:
	if take == 0:
		return {"ok": true, "top": [], "bottom": []}
	if ctx.has("insight_top") or ctx.has("insight_bottom"):
		var top: Array = ctx.get("insight_top", []) as Array
		var bot: Array = ctx.get("insight_bottom", []) as Array
		if not _insight_split_valid(take, top, bot):
			return {"ok": false}
		return {"ok": true, "top": top, "bottom": bot}
	var perm: Array = ctx.get("insight_perm", []) as Array
	if not _insight_perm_valid_legacy(take, perm):
		return {"ok": false}
	return {"ok": true, "top": perm, "bottom": []}


func _apply_insight(target: int, eff: int, top: Array, bottom: Array) -> void:
	var pl: Dictionary = _players[target]
	var deck: Array = pl["deck"]
	var take := mini(eff, deck.size())
	if take == 0:
		_log("Insight on P%d (empty deck)." % target)
		return
	var peek: Array = []
	peek.resize(take)
	for i in take:
		peek[i] = deck[deck.size() - 1 - i]
	for _i in take:
		deck.pop_back()
	var ks := top.size()
	var new_seq: Array = []
	new_seq.resize(ks)
	for i in ks:
		new_seq[i] = peek[int(top[i])]
	for k in range(ks - 1, -1, -1):
		deck.append(new_seq[k])
	for bi in bottom:
		deck.insert(0, peek[int(bi)])
	var nb := bottom.size()
	if nb == 0:
		if take == 1:
			_log("Insight 1 on P%d deck (single card)." % target)
		else:
			_log("Insight %d on P%d deck (reordered on top)." % [take, target])
	elif ks == 0:
		_log("Insight %d on P%d deck (%d to bottom)." % [take, target, nb])
	else:
		_log("Insight %d on P%d deck (%d on top, %d to bottom)." % [take, target, ks, nb])


func _mill(target: int, x: int) -> void:
	var pl: Dictionary = _players[target]
	var deck: Array = pl["deck"]
	var n := mini(x, deck.size())
	for _i in n:
		pl["crypt"].append(deck.pop_back())
	_log("Burn discards %d from P%d deck." % [n, target])


func _wrath_destroy_count(value: int) -> int:
	if value == 4:
		return 2
	return 0


func _wrath_resolve_mids(opp: int, n: int, client_mids: Array, instigator: int) -> Array:
	var field: Array = _players[opp]["field"]
	var need := mini(effective_wrath_destroy_count(instigator, n), field.size())
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
			pl["crypt"].append(x)
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
			pl["crypt"].append(x)
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
	if not (phase == Phase.MAIN and not _is_mulligan_active() and p == current and not discard_draw_used and not _players[p]["hand"].is_empty()):
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	return true


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
	if kind in ["ritual", "noble", "incantation", "dethrone"]:
		pl["crypt"].append(c)
	else:
		pl["crypt"].append(c)


func _inc_crypt_cards(pl: Dictionary) -> Array:
	var out: Array = []
	for c in (pl["crypt"] as Array):
		if _card_kind(c) == "incantation" or _card_kind(c) == "dethrone":
			out.append(c)
	return out


func _ritual_crypt_cards(pl: Dictionary) -> Array:
	var out: Array = []
	for c in (pl["crypt"] as Array):
		if _card_kind(c) == "ritual":
			out.append(c)
	return out


func _noble_crypt_cards(pl: Dictionary) -> Array:
	var out: Array = []
	for c in (pl["crypt"] as Array):
		if _card_kind(c) == "noble":
			out.append(c)
	return out


func _inc_crypt_index_to_crypt_index(pl: Dictionary, inc_idx: int) -> int:
	if inc_idx < 0:
		return -1
	var seen := 0
	var crypt: Array = pl["crypt"]
	for i in crypt.size():
		var k := _card_kind(crypt[i])
		if k == "incantation" or k == "dethrone":
			if seen == inc_idx:
				return i
			seen += 1
	return -1


func _ritual_crypt_index_to_crypt_index(pl: Dictionary, ritual_idx: int) -> int:
	if ritual_idx < 0:
		return -1
	var seen := 0
	var crypt: Array = pl["crypt"]
	for i in crypt.size():
		if _card_kind(crypt[i]) == "ritual":
			if seen == ritual_idx:
				return i
			seen += 1
	return -1


func end_turn(p: int, discard_indices: Array) -> String:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return "illegal"
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return "illegal"
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
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
	if goldfish:
		current = 0
	else:
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
	var fns: Array[String] = []
	if ResourceLoader.has_method(&"list_directory"):
		for fn in ResourceLoader.list_directory(NOBLES_DIR):
			if str(fn).ends_with("/"):
				continue
			if str(fn).ends_with(".gd"):
				fns.append(str(fn))
	if fns.is_empty():
		var dir := DirAccess.open(NOBLES_DIR)
		if dir == null:
			return
		dir.list_dir_begin()
		while true:
			var fn2 := dir.get_next()
			if fn2 == "":
				break
			if dir.current_is_dir() or not fn2.ends_with(".gd"):
				continue
			fns.append(fn2)
		dir.list_dir_end()
	var seen: Dictionary = {}
	for fn in fns:
		if seen.has(fn):
			continue
		seen[fn] = true
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

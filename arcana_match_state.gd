class_name ArcanaMatchState
extends RefCounted

const MAX_HAND_END := 7
const START_HAND := 5
const WIN_POWER := 20
const NOBLES_DIR := "res://nobles"

const TEMPLE_PLAY_COST := 7
const TEMPLE_EYRIE_COST := 6
const EYRIE_SEARCH_COUNT := 2
const TEMPLE_PHAEDRA := "phaedra_illusion"
const TEMPLE_DELPHA := "delpha_oracles"
const TEMPLE_GOTHA := "gotha_illness"
const TEMPLE_YTRIA := "ytria_cycles"
const TEMPLE_EYRIE := "eyrie_feathers"

const NOBLE_LANE_GRANTS := {
	"krss_power": 1,
	"trss_power": 2,
	"yrss_power": 3,
}

const RING_COST := 2
const RING_DEFS := {
	"sybiline_emanation":     {"name": "Sybiline, Ring of Emanation",     "reductions": {"seek": 1, "insight": 1}},
	"cymbil_occultation":     {"name": "Cymbil, Ring of Occultation",     "reductions": {"burn": 1, "revive": 1, "renew": 1}},
	"celadon_annihilation":   {"name": "Celadon, Ring of Annihilation",   "reductions": {"woe": 1}},
	"serraf_nobles":          {"name": "Serraf, Ring of Nobles",          "reductions": {"noble": 1}},
	"sinofia_feathers":       {"name": "Sinofia, Ring of Feathers",       "reductions": {"bird": 1, "tears": 1, "flight": 1}},
}

enum Phase { MAIN, GAME_OVER }

var rng: RandomNumberGenerator
var phase: Phase = Phase.MAIN
var current: int
var ritual_played_this_turn: bool = false
var noble_played_this_turn: bool = false
var temple_played_this_turn: bool = false
var bird_played_this_turn: bool = false
var bird_fight_used_this_turn: bool = false
var bird_nested_this_turn: bool = false
var discard_draw_used: bool
var winner: int = -1
var empty_deck_end: bool = false
var log_lines: Array = []
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

var _eyrie_pending_player: int = -1
var _eyrie_pending_remaining: int = 0

const VOID_RESPONSE_MS := 10000
var _pending_stack: Array = []
var _pending_next_id: int = 1
var _void_deadline_ms: int = 0


func _card_kind(c: Variant) -> String:
	if c == null or typeof(c) != TYPE_DICTIONARY:
		return ""
	return CardTraits.effective_kind(c as Dictionary)


func _noble_on_field(p: int, noble_id: String) -> bool:
	for x in _players[p]["noble_field"]:
		if str(x.get("noble_id", "")) == noble_id:
			return true
	return false


func _sum_ring_reduction(p: int, key: String) -> int:
	var total := 0
	var hosts: Array = []
	hosts.append_array(_players[p]["noble_field"] as Array)
	hosts.append_array(_players[p]["bird_field"] as Array)
	for h in hosts:
		var rings: Array = (h as Dictionary).get("rings", []) as Array
		for r in rings:
			var rid := str((r as Dictionary).get("ring_id", ""))
			if not RING_DEFS.has(rid):
				continue
			var def: Dictionary = RING_DEFS[rid] as Dictionary
			var reds: Dictionary = def.get("reductions", {}) as Dictionary
			total += int(reds.get(key, 0))
	return total


func effective_incantation_cost(p: int, verb: String, value: int) -> int:
	var v := verb.to_lower()
	if v == "void":
		return 0
	return maxi(0, value - _sum_ring_reduction(p, v))


func incantation_display_name(verb_lc: String, verb_raw: String, printed_value: int) -> String:
	if verb_lc == "void":
		return "Void"
	if verb_lc == "wrath":
		return "Wrath"
	return "%s %d" % [verb_raw, printed_value]


func _incantation_preview_card(verb_lc: String, value: int, verb_raw: String = "") -> Dictionary:
	var vr := verb_raw
	if vr.is_empty():
		vr = verb_lc.capitalize()
	return {
		"verb": vr,
		"value": value
	}


func _incantation_log_meta(verb_lc: String, value: int, verb_raw: String = "") -> Dictionary:
	var disp_raw := verb_raw if not verb_raw.is_empty() else verb_lc.capitalize()
	return {
		"incantation_link": {
			"text": incantation_display_name(verb_lc, disp_raw, value),
			"card": _incantation_preview_card(verb_lc, value, disp_raw)
		}
	}


func effective_noble_cost(p: int, base_cost: int) -> int:
	return maxi(0, base_cost - _sum_ring_reduction(p, "noble"))


func effective_bird_cost(p: int, base_cost: int) -> int:
	return maxi(0, base_cost - _sum_ring_reduction(p, "bird"))


func insight_effective_n(p: int, base: int) -> int:
	return base + (1 if _noble_on_field(p, "xytzr_emanation") else 0)


func _woe_discard_need(instigator: int, value: int, victim: int) -> int:
	var hs: int = _players[victim]["hand"].size()
	var base := maxi(value - 1, 0)
	var extra := 1 if _noble_on_field(instigator, "zytzr_annihilation") else 0
	return mini(base + extra, hs)


func effective_wrath_destroy_count(instigator: int, value: int) -> int:
	var base := _wrath_destroy_count(value)
	if base == 0:
		return 0
	if _noble_on_field(instigator, "zytzr_annihilation"):
		return base + 1
	return base


func can_play_aeoiu_ritual(p: int) -> bool:
	return not _ritual_crypt_cards(_players[p]).is_empty()


func match_power_loss_for_sacrificing_field_ritual(p: int, mid: int) -> int:
	if not _ritual_mid_on_player_field(p, mid):
		return 999999
	var before := match_power(p)
	var pl := _players[p]
	var trial: Array = []
	for x in pl["field"] as Array:
		if int(x.get("mid", -1)) == mid:
			continue
		trial.append(x)
	var act := active_mask_for_field(trial)
	var rp := 0
	for i in trial.size():
		if bool(act[i]):
			rp += int(trial[i].get("value", 0))
	var bird_power := (pl["bird_field"] as Array).size()
	var after := rp + bird_power
	return before - after


func _validate_renew_ctx(p: int, ctx: Dictionary) -> String:
	var ridx := int(ctx.get("renew_ritual_crypt_idx", -1))
	var rg: Array = _ritual_crypt_cards(_players[p])
	if ridx < 0 or ridx >= rg.size():
		return "illegal_target"
	if ctx.has("renew_second_ritual_crypt_idx") or ctx.has("yytzr_extra_discard_hand_idx"):
		return "illegal"
	return "ok"


func _ritual_crypt_count_after_payment_sacrifice(p: int, mids_main: Dictionary) -> int:
	var n: int = _ritual_crypt_cards(_players[p]).size()
	for x in _players[p]["field"]:
		if _card_kind(x) != "ritual":
			continue
		var mid := int(x["mid"])
		if mids_main.has(mid):
			n += 1
	return n


func _validate_renew_ctx_presacrifice(p: int, ctx: Dictionary, mids_main: Dictionary, _unused: Dictionary) -> String:
	var total: int = _ritual_crypt_count_after_payment_sacrifice(p, mids_main)
	var ridx := int(ctx.get("renew_ritual_crypt_idx", -1))
	if ridx < 0 or ridx >= total:
		return "illegal_target"
	if ctx.has("renew_second_ritual_crypt_idx") or ctx.has("yytzr_extra_discard_hand_idx"):
		return "illegal"
	return "ok"


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
		"bird_field": [],
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
	bird_played_this_turn = false
	bird_fight_used_this_turn = false
	bird_nested_this_turn = false
	turn_number += 1
	if turn_number == 1 and current == _starting_player:
		discard_draw_used = false
		_log("Draw step skipped (first turn).")
		return
	if _skip_draw_for_gotha(current):
		discard_draw_used = false
		_log("Draw step skipped (Gotha).")
		return
	if not _draw_one_attempt(current):
		return
	discard_draw_used = false
	_log("Draw step.")


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
	var p0_power := match_power(0)
	var p1_power := match_power(1)
	if p0_power > p1_power:
		winner = 0
	elif p1_power > p0_power:
		winner = 1
	else:
		winner = -1
	phase = Phase.GAME_OVER
	if winner >= 0:
		_log("P%d drew from an empty deck. P%d wins by higher match power (%d vs %d)." % [trigger_player, winner, p0_power, p1_power])
	else:
		_log("P%d drew from an empty deck. Game is a draw on match power (%d-%d)." % [trigger_player, p0_power, p1_power])


func _check_power_win(p: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	if _is_mulligan_active():
		return
	if match_power(p) >= WIN_POWER:
		winner = p
		phase = Phase.GAME_OVER
		_log("P%d reached %d match power." % [p, WIN_POWER])


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


func match_power(p: int) -> int:
	var bird_power := (_players[p]["bird_field"] as Array).size()
	return ritual_power(p) + bird_power


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


static func lane_grants_from_nobles(nobles: Array) -> Array:
	var lanes: Array = []
	var seen: Dictionary = {}
	for noble in nobles:
		var nid := str((noble as Dictionary).get("noble_id", ""))
		if not NOBLE_LANE_GRANTS.has(nid):
			continue
		var lv := int(NOBLE_LANE_GRANTS[nid])
		if lv > 0 and not seen.has(lv):
			seen[lv] = true
			lanes.append(lv)
	return lanes


static func has_lane_for_field_and_nobles(field: Array, nobles: Array, n: int) -> bool:
	if has_lane_for_field(field, n):
		return true
	return lane_grants_from_nobles(nobles).has(n)


func _active_mask(field: Array) -> Array:
	return active_mask_for_field(field)


func _bird_nest_temple_mid(b: Dictionary) -> int:
	return int(b.get("nest_temple_mid", -1))


func _temple_nest_capacity(t: Dictionary) -> int:
	var cap := int(t.get("cost", 0))
	if cap <= 0:
		cap = _temple_play_cost_for_id(str(t.get("temple_id", "")))
	return cap


func _remove_bird_from_temple_nest(p: int, temple_mid: int, bird_mid: int) -> void:
	var tf: Array = _temple_field_safe(p)
	for i in tf.size():
		var td: Dictionary = tf[i]
		if int(td.get("mid", -1)) != temple_mid:
			continue
		var nm: Array = (td.get("nested_bird_mids", []) as Array).duplicate()
		var nn: Array = []
		for m in nm:
			if int(m) != bird_mid:
				nn.append(m)
		td["nested_bird_mids"] = nn
		td["nested"] = not nn.is_empty()
		tf[i] = td
		break


func _bird_lane_value(p: int) -> int:
	var birds: Array = _players[p]["bird_field"]
	var s := 0
	for b in birds:
		var bd := b as Dictionary
		if _bird_nest_temple_mid(bd) >= 0:
			continue
		s += int(bd.get("power", 0))
	return s


func _has_bird_lane(p: int, n: int) -> bool:
	return n > 0 and _bird_lane_value(p) == n


func has_active_ritual_lane(p: int, n: int) -> bool:
	if has_lane_for_field(_players[p]["field"], n):
		return true
	if _has_bird_lane(p, n):
		return true
	return _extra_ritual_lanes_from_nobles(p).has(n)


func has_active_incantation_lane(p: int, n: int) -> bool:
	return has_active_ritual_lane(p, n)


func _extra_ritual_lanes_from_nobles(p: int) -> Array:
	var lanes: Array = []
	var seen: Dictionary = {}
	var nobles: Array = _players[p]["noble_field"]
	for noble in nobles:
		var hook: Variant = _hook_for_noble(noble)
		if hook == null or not hook.has_method("grant_ritual_lanes"):
			continue
		var hook_lanes: Variant = hook.call("grant_ritual_lanes", self, p, noble)
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
	var eyrie_you := _eyrie_waiting_on_response() and _eyrie_pending_player == for_player
	var eyrie_waiting_opp := _eyrie_waiting_on_response() and _eyrie_pending_player != for_player
	var eyrie_candidates: Array = []
	if eyrie_you:
		eyrie_candidates = _eyrie_snapshot_candidates(for_player)
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
		"your_bird_played": for_player == current and bird_played_this_turn,
		"your_bird_nested": for_player == current and bird_nested_this_turn,
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
		"your_birds": _players[for_player]["bird_field"].duplicate(true),
		"opp_birds": _players[opp]["bird_field"].duplicate(true),
		"your_nobles": _players[for_player]["noble_field"].duplicate(true),
		"opp_nobles": _players[opp]["noble_field"].duplicate(true),
		"your_temples": _temple_field_safe(for_player).duplicate(true),
		"opp_temples": _temple_field_safe(opp).duplicate(true),
		"your_power": match_power(for_player),
		"opp_power": match_power(opp),
		"your_match_power": match_power(for_player),
		"opp_match_power": match_power(opp),
		"your_bird_fight_used": for_player == current and bird_fight_used_this_turn,
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
		"eyrie_pending_you_respond": eyrie_you,
		"eyrie_pending_waiting": eyrie_waiting_opp,
		"eyrie_pending_remaining": _eyrie_pending_remaining if eyrie_you else 0,
		"eyrie_bird_candidates": eyrie_candidates,
		"void_pending_you_respond": _void_pending_you_respond_for(for_player),
		"void_pending_waiting": _void_pending_waiting_for(for_player),
		"void_pending_kind": _void_pending_kind_view(),
		"void_pending_card_label": _void_pending_label_view(),
		"void_pending_card": _void_pending_card_view(),
		"void_pending_cost": _void_pending_cost_view(),
		"void_pending_deadline_ms": _void_deadline_ms,
		"void_pending_id": _void_pending_id_view(),
		"log": log_lines.duplicate(true),
		"goldfish": goldfish
	}


func _void_pending_you_respond_for(for_player: int) -> bool:
	if _pending_stack.is_empty():
		return false
	var reactor := _pending_reactor()
	if reactor != for_player:
		return false
	return _responder_can_void(reactor)


func _void_pending_waiting_for(for_player: int) -> bool:
	if _pending_stack.is_empty():
		return false
	var reactor := _pending_reactor()
	if reactor < 0 or reactor == for_player:
		return false
	return _responder_can_void(reactor)


func _void_pending_kind_view() -> String:
	if _pending_stack.is_empty():
		return ""
	var top: Dictionary = _pending_stack_top()
	if bool(top.get("is_void", false)):
		return "void"
	return str(top.get("kind", ""))


func _void_pending_label_view() -> String:
	if _pending_stack.is_empty():
		return ""
	return str(_pending_stack_top().get("label", ""))


func _void_pending_card_view() -> Dictionary:
	if _pending_stack.is_empty():
		return {}
	var top: Dictionary = _pending_stack_top()
	var c: Variant = top.get("card", {})
	if typeof(c) != TYPE_DICTIONARY:
		return {}
	return (c as Dictionary).duplicate(true)


func _void_pending_cost_view() -> int:
	if _pending_stack.is_empty():
		return 0
	return int(_pending_stack_top().get("cost", 0))


func _void_pending_id_view() -> int:
	if _pending_stack.is_empty():
		return -1
	return int(_pending_stack_top().get("id", -1))


func can_play_ritual(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current or ritual_played_this_turn:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
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
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "noble":
		return false
	var nid := str(c.get("noble_id", ""))
	if nid.is_empty() or not _noble_hooks.has(nid):
		return false
	var cost := effective_noble_cost(p, _noble_play_cost(nid))
	if cost <= 0:
		return true
	if has_active_ritual_lane(p, cost):
		return true
	if cost < 6:
		return false
	return _can_sacrifice(p, cost)


func play_noble(p: int, hand_idx: int, sacrifice_mids: Array = []) -> String:
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
	var cost := effective_noble_cost(p, _noble_play_cost(nid))
	var need_sac := cost > 0 and not has_active_ritual_lane(p, cost) and cost >= 6
	var mids: Dictionary = {}
	if need_sac:
		for m in sacrifice_mids:
			mids[int(m)] = true
		if not _sacrifice_valid(p, cost, mids):
			mids.clear()
			for mid in _greedy_sacrifice_mids_for_player(p, cost):
				mids[int(mid)] = true
			if not _sacrifice_valid(p, cost, mids):
				return "illegal_sacrifice"
	_apply_sacrifice(p, mids)
	hand.remove_at(hand_idx)
	noble_played_this_turn = true
	var frame := {
		"kind": "noble",
		"card": c,
		"label": str(c.get("name", nid)),
		"cost": _noble_play_cost(nid),
		"payload": {"nid": nid, "name": str(c.get("name", nid))}
	}
	_open_void_window_or_resolve(p, frame)
	return "ok"


func _finalize_play_noble(p: int, card: Dictionary, payload: Dictionary) -> void:
	var pl: Dictionary = _players[p]
	var nid := str(payload.get("nid", card.get("noble_id", "")))
	var mid := _next_noble_mid(pl)
	var field_noble := {
		"mid": mid,
		"noble_id": nid,
		"name": str(payload.get("name", card.get("name", nid))),
		"used_turn": -1,
		"rings": []
	}
	pl["noble_field"].append(field_noble)
	_log("P%d summons %s." % [p, field_noble["name"]])


func can_play_bird(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current or bird_played_this_turn:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "bird":
		return false
	var raw_cost := int((c as Dictionary).get("cost", 0))
	if raw_cost <= 0:
		return false
	var cost := effective_bird_cost(p, raw_cost)
	if cost <= 0:
		return true
	return has_active_ritual_lane(p, cost)


func play_bird(p: int, hand_idx: int) -> String:
	if not can_play_bird(p, hand_idx):
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	var c: Dictionary = hand[hand_idx]
	hand.remove_at(hand_idx)
	bird_played_this_turn = true
	var frame := {
		"kind": "bird",
		"card": c,
		"label": str(c.get("name", "Bird")),
		"cost": int(c.get("cost", 0)),
		"payload": {}
	}
	_open_void_window_or_resolve(p, frame)
	return "ok"


func _finalize_play_bird(p: int, card: Dictionary, _payload: Dictionary) -> void:
	var pl: Dictionary = _players[p]
	var mid := _next_bird_mid(pl)
	var bird := {
		"mid": mid,
		"bird_id": str(card.get("bird_id", "")),
		"name": str(card.get("name", "Bird")),
		"cost": int(card.get("cost", 0)),
		"power": int(card.get("power", 0)),
		"damage": 0,
		"nest_temple_mid": -1,
		"rings": []
	}
	pl["bird_field"].append(bird)
	_log("P%d summons %s." % [p, bird["name"]])
	_check_power_win(p)


func _ring_legal_hosts(p: int) -> Dictionary:
	var out := {"noble_mids": [], "bird_mids": []}
	for n in _players[p]["noble_field"]:
		(out["noble_mids"] as Array).append(int((n as Dictionary).get("mid", -1)))
	for b in _players[p]["bird_field"]:
		var bd := b as Dictionary
		if int(bd.get("nest_temple_mid", -1)) >= 0:
			continue
		(out["bird_mids"] as Array).append(int(bd.get("mid", -1)))
	return out


func _find_noble_on_field_mid(p: int, mid: int) -> int:
	var arr: Array = _players[p]["noble_field"]
	for i in arr.size():
		if int((arr[i] as Dictionary).get("mid", -1)) == mid:
			return i
	return -1


func _find_bird_on_field_idx(p: int, mid: int) -> int:
	var arr: Array = _players[p]["bird_field"]
	for i in arr.size():
		if int((arr[i] as Dictionary).get("mid", -1)) == mid:
			return i
	return -1


func _next_ring_mid(pl: Dictionary) -> int:
	var mx := 0
	for n in pl["noble_field"]:
		for r in ((n as Dictionary).get("rings", []) as Array):
			mx = maxi(mx, int((r as Dictionary).get("mid", 0)))
	for b in pl["bird_field"]:
		for r in ((b as Dictionary).get("rings", []) as Array):
			mx = maxi(mx, int((r as Dictionary).get("mid", 0)))
	for c in (pl["crypt"] as Array):
		if str((c as Dictionary).get("type", "")).to_lower() == "ring":
			mx = maxi(mx, int((c as Dictionary).get("mid", 0)))
	return mx + 1


func can_play_ring(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "ring":
		return false
	var rid := str((c as Dictionary).get("ring_id", ""))
	if rid.is_empty() or not RING_DEFS.has(rid):
		return false
	if not has_active_ritual_lane(p, RING_COST):
		return false
	var hosts := _ring_legal_hosts(p)
	return not (hosts["noble_mids"] as Array).is_empty() or not (hosts["bird_mids"] as Array).is_empty()


func _ring_host_is_legal(p: int, host_kind: String, host_mid: int) -> bool:
	var hk := host_kind.to_lower()
	if hk == "noble":
		return _find_noble_on_field_mid(p, host_mid) >= 0
	if hk == "bird":
		var idx := _find_bird_on_field_idx(p, host_mid)
		if idx < 0:
			return false
		var bd: Dictionary = _players[p]["bird_field"][idx]
		return int(bd.get("nest_temple_mid", -1)) < 0
	return false


func play_ring(p: int, hand_idx: int, host_kind: String, host_mid: int) -> String:
	if not can_play_ring(p, hand_idx):
		return "illegal"
	if not _ring_host_is_legal(p, host_kind, host_mid):
		return "illegal_target"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	var c: Dictionary = hand[hand_idx]
	hand.remove_at(hand_idx)
	var frame := {
		"kind": "ring",
		"card": c,
		"label": str(c.get("name", "Ring")),
		"cost": RING_COST,
		"payload": {
			"ring_id": str(c.get("ring_id", "")),
			"name": str(c.get("name", "Ring")),
			"host_kind": host_kind.to_lower(),
			"host_mid": host_mid
		}
	}
	_open_void_window_or_resolve(p, frame)
	return "ok"


func _finalize_play_ring(p: int, card: Dictionary, payload: Dictionary) -> void:
	var pl: Dictionary = _players[p]
	var host_kind := str(payload.get("host_kind", "")).to_lower()
	var host_mid := int(payload.get("host_mid", -1))
	var rid := str(payload.get("ring_id", card.get("ring_id", "")))
	var rname := str(payload.get("name", card.get("name", rid)))
	if not _ring_host_is_legal(p, host_kind, host_mid):
		pl["crypt"].append(card)
		_log("P%d's %s has no legal host; sent to crypt." % [p, rname])
		return
	var ring_mid := _next_ring_mid(pl)
	var ring_entry := {"mid": ring_mid, "ring_id": rid, "name": rname}
	if host_kind == "noble":
		var ni := _find_noble_on_field_mid(p, host_mid)
		if ni < 0:
			pl["crypt"].append(card)
			return
		var noble: Dictionary = pl["noble_field"][ni]
		var arr: Array = (noble.get("rings", []) as Array).duplicate()
		arr.append(ring_entry)
		noble["rings"] = arr
		pl["noble_field"][ni] = noble
		_log("P%d attaches %s to %s." % [p, rname, str(noble.get("name", "Noble"))])
	elif host_kind == "bird":
		var bi := _find_bird_on_field_idx(p, host_mid)
		if bi < 0:
			pl["crypt"].append(card)
			return
		var bird: Dictionary = pl["bird_field"][bi]
		var barr: Array = (bird.get("rings", []) as Array).duplicate()
		barr.append(ring_entry)
		bird["rings"] = barr
		pl["bird_field"][bi] = bird
		_log("P%d attaches %s to %s." % [p, rname, str(bird.get("name", "Bird"))])
	else:
		pl["crypt"].append(card)
		return
	_check_power_win(p)


func _shed_rings_to_crypt(pl: Dictionary, host: Dictionary) -> void:
	var rings: Array = (host.get("rings", []) as Array)
	for r in rings:
		var rd := r as Dictionary
		var card := {
			"type": "Ring",
			"ring_id": str(rd.get("ring_id", "")),
			"name": str(rd.get("name", ""))
		}
		pl["crypt"].append(card)
	host["rings"] = []


func _valid_temple_id(tid: String) -> bool:
	return tid == TEMPLE_PHAEDRA or tid == TEMPLE_DELPHA or tid == TEMPLE_GOTHA or tid == TEMPLE_YTRIA or tid == TEMPLE_EYRIE


func _temple_play_cost_for_id(tid: String) -> int:
	if tid == TEMPLE_YTRIA:
		return 9
	if tid == TEMPLE_EYRIE:
		return TEMPLE_EYRIE_COST
	return TEMPLE_PLAY_COST


func can_play_temple(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current or temple_played_this_turn:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "temple":
		return false
	var tid := str((c as Dictionary).get("temple_id", ""))
	if not _valid_temple_id(tid):
		return false
	return _can_sacrifice(p, _temple_play_cost_for_id(tid))


func play_temple(p: int, hand_idx: int, sacrifice_mids: Array) -> String:
	if not can_play_temple(p, hand_idx):
		return "illegal"
	var c: Variant = _card_at_hand(p, hand_idx)
	var tid := str((c as Dictionary).get("temple_id", ""))
	if not _valid_temple_id(tid):
		return "illegal"
	var temple_cost := _temple_play_cost_for_id(tid)
	var mids: Dictionary = {}
	for m in sacrifice_mids:
		mids[int(m)] = true
	if not _sacrifice_valid(p, temple_cost, mids):
		mids.clear()
		for mid in _greedy_sacrifice_mids_for_player(p, temple_cost):
			mids[int(mid)] = true
		if not _sacrifice_valid(p, temple_cost, mids):
			return "illegal_sacrifice"
	_apply_sacrifice(p, mids)
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	hand.remove_at(hand_idx)
	temple_played_this_turn = true
	var card_d := c as Dictionary
	var frame := {
		"kind": "temple",
		"card": card_d,
		"label": str(card_d.get("name", tid)),
		"cost": temple_cost,
		"payload": {"tid": tid, "temple_cost": temple_cost, "name": str(card_d.get("name", tid))}
	}
	_open_void_window_or_resolve(p, frame)
	return "ok"


func _finalize_play_temple(p: int, _card: Dictionary, payload: Dictionary) -> void:
	var pl: Dictionary = _players[p]
	var tid := str(payload.get("tid", ""))
	var temple_cost := int(payload.get("temple_cost", TEMPLE_PLAY_COST))
	var tmid := _next_temple_mid(pl)
	var entry := {
		"mid": tmid,
		"temple_id": tid,
		"name": str(payload.get("name", tid)),
		"cost": temple_cost,
		"used_turn": -1,
		"nested": false,
		"nested_bird_mids": []
	}
	_temple_field_safe(p).append(entry)
	_log("P%d plays temple %s." % [p, entry["name"]])
	if tid == TEMPLE_EYRIE:
		_trigger_eyrie_enter(p)


func _trigger_eyrie_enter(p: int) -> void:
	var candidates := _eyrie_bird_candidate_indices(p)
	if candidates.is_empty():
		_log("P%d's Eyrie finds no birds; deck shuffled." % p)
		_shuffle(_players[p]["deck"])
		return
	_eyrie_pending_player = p
	_eyrie_pending_remaining = mini(EYRIE_SEARCH_COUNT, candidates.size())
	_log("P%d's Eyrie searches the deck for %d birds." % [p, _eyrie_pending_remaining])


func _eyrie_snapshot_candidates(p: int) -> Array:
	var deck: Array = _players[p]["deck"]
	var out: Array = []
	for i in deck.size():
		var c: Dictionary = deck[i] as Dictionary
		if _card_kind(c) != "bird":
			continue
		out.append({
			"deck_idx": i,
			"bird_id": str(c.get("bird_id", "")),
			"name": str(c.get("name", "Bird")),
			"cost": int(c.get("cost", 0)),
			"power": int(c.get("power", 0))
		})
	return out


func _eyrie_bird_candidate_indices(p: int) -> Array:
	var deck: Array = _players[p]["deck"]
	var out: Array = []
	for i in deck.size():
		if _card_kind(deck[i]) == "bird":
			out.append(i)
	return out


func _eyrie_waiting_on_response() -> bool:
	return _eyrie_pending_player >= 0


func _eyrie_clear_pending() -> void:
	_eyrie_pending_player = -1
	_eyrie_pending_remaining = 0


func can_submit_eyrie(p: int) -> bool:
	return _eyrie_waiting_on_response() and p == _eyrie_pending_player


func apply_eyrie_submit(p: int, deck_indices: Array) -> String:
	if not can_submit_eyrie(p):
		return "illegal"
	var pl: Dictionary = _players[p]
	var deck: Array = pl["deck"]
	var max_pick := _eyrie_pending_remaining
	var seen: Dictionary = {}
	var chosen: Array = []
	for it in deck_indices:
		var idx := int(it)
		if idx < 0 or idx >= deck.size() or seen.has(idx):
			return "illegal"
		if _card_kind(deck[idx]) != "bird":
			return "illegal"
		seen[idx] = true
		chosen.append(idx)
		if chosen.size() > max_pick:
			return "illegal"
	chosen.sort()
	var bird_cards: Array = []
	for i in range(chosen.size() - 1, -1, -1):
		var di: int = int(chosen[i])
		bird_cards.append(deck[di])
		deck.remove_at(di)
	bird_cards.reverse()
	for c in bird_cards:
		var mid := _next_bird_mid(pl)
		var bird := {
			"mid": mid,
			"bird_id": str((c as Dictionary).get("bird_id", "")),
			"name": str((c as Dictionary).get("name", "Bird")),
			"cost": int((c as Dictionary).get("cost", 0)),
			"power": int((c as Dictionary).get("power", 0)),
			"damage": 0,
			"nest_temple_mid": -1,
			"rings": []
		}
		pl["bird_field"].append(bird)
		_log("P%d's Eyrie summons %s from deck." % [p, bird["name"]])
	_shuffle(deck)
	_eyrie_clear_pending()
	_check_power_win(p)
	return "ok"


func can_nest_bird(p: int, bird_mid: int, temple_mid: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
		return false
	if bird_nested_this_turn:
		return false
	var b := _find_bird_on_field(p, bird_mid)
	if b.is_empty():
		return false
	if _bird_nest_temple_mid(b) >= 0:
		return false
	if not ((b.get("rings", []) as Array).is_empty()):
		return false
	var t := _find_temple_on_field(p, temple_mid)
	if t.is_empty():
		return false
	var cap := _temple_nest_capacity(t)
	var nest: Array = t.get("nested_bird_mids", []) as Array
	return nest.size() < cap


func nest_bird(p: int, bird_mid: int, temple_mid: int) -> String:
	if not can_nest_bird(p, bird_mid, temple_mid):
		return "illegal"
	var pl: Dictionary = _players[p]
	var birds: Array = pl["bird_field"]
	for i in birds.size():
		var bd: Dictionary = birds[i]
		if int(bd.get("mid", -1)) != bird_mid:
			continue
		bd["nest_temple_mid"] = temple_mid
		birds[i] = bd
		break
	var tf: Array = _temple_field_safe(p)
	for j in tf.size():
		var td: Dictionary = tf[j]
		if int(td.get("mid", -1)) != temple_mid:
			continue
		var nm: Array = (td.get("nested_bird_mids", []) as Array).duplicate()
		nm.append(bird_mid)
		td["nested_bird_mids"] = nm
		td["nested"] = true
		tf[j] = td
		break
	_log("P%d nests a bird (mid %d) in temple (mid %d)." % [p, bird_mid, temple_mid])
	bird_nested_this_turn = true
	_check_power_win(p)
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


func _next_bird_mid(pl: Dictionary) -> int:
	var mx := 0
	for x in pl["bird_field"]:
		mx = maxi(mx, int((x as Dictionary).get("mid", 0)))
	for x in (pl["crypt"] as Array):
		if _card_kind(x) == "bird":
			mx = maxi(mx, int((x as Dictionary).get("mid", 0)))
	return mx + 1


func _find_bird_on_field(p: int, bird_mid: int) -> Dictionary:
	for b in _players[p]["bird_field"]:
		if int((b as Dictionary).get("mid", -1)) == bird_mid:
			return b
	return {}


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


func _is_void_card(c: Variant) -> bool:
	if typeof(c) != TYPE_DICTIONARY:
		return false
	var cd := c as Dictionary
	if _card_kind(cd) != "incantation":
		return false
	return str(cd.get("verb", "")).to_lower() == "void"


func _player_has_void_in_hand(p: int) -> bool:
	for c in _players[p]["hand"]:
		if _is_void_card(c):
			return true
	return false


func _responder_can_void(p: int) -> bool:
	var hand: Array = _players[p]["hand"]
	if hand.size() < 2:
		return false
	return _player_has_void_in_hand(p)


func _pending_stack_blocks_action(_p: int) -> bool:
	return not _pending_stack.is_empty()


func _pending_stack_top() -> Dictionary:
	if _pending_stack.is_empty():
		return {}
	return _pending_stack[_pending_stack.size() - 1] as Dictionary


func _pending_reactor() -> int:
	if _pending_stack.is_empty():
		return -1
	var top: Dictionary = _pending_stack_top()
	return 1 - int(top.get("player", -1))


func _void_waiting_on_response() -> bool:
	if _pending_stack.is_empty():
		return false
	var reactor := _pending_reactor()
	if reactor < 0:
		return false
	return _responder_can_void(reactor)


func _open_void_window_or_resolve(instigator: int, frame: Dictionary) -> void:
	frame["id"] = _pending_next_id
	frame["player"] = instigator
	if not frame.has("is_void"):
		frame["is_void"] = false
	_pending_next_id += 1
	_pending_stack.append(frame)
	var reactor := 1 - instigator
	if _responder_can_void(reactor):
		_void_deadline_ms = Time.get_ticks_msec() + VOID_RESPONSE_MS
		_log("P%d plays %s (awaiting Void window)." % [instigator, str(frame.get("label", ""))])
		return
	_void_deadline_ms = 0
	_resolve_pending_stack_tail()


func _resolve_pending_stack_tail() -> void:
	while not _pending_stack.is_empty():
		var top: Dictionary = _pending_stack.pop_back() as Dictionary
		if bool(top.get("is_void", false)):
			if _pending_stack.is_empty():
				var owner_v := int(top.get("player", -1))
				if owner_v >= 0:
					_players[owner_v]["crypt"].append(top.get("card", {}))
				_log("P%d's Void resolves with no target." % owner_v)
				continue
			var target: Dictionary = _pending_stack.pop_back() as Dictionary
			var void_owner := int(top.get("player", -1))
			var tgt_owner := int(target.get("player", -1))
			if tgt_owner >= 0:
				_players[tgt_owner]["crypt"].append(target.get("card", {}))
			if void_owner >= 0:
				_players[void_owner]["crypt"].append(top.get("card", {}))
			_log("P%d's Void counters P%d's %s (moved to crypt, no effect)." % [void_owner, tgt_owner, str(target.get("label", ""))])
			continue
		_finalize_pending_play(top)
	_void_deadline_ms = 0


func _finalize_pending_play(frame: Dictionary) -> void:
	var p := int(frame.get("player", -1))
	if p < 0:
		return
	var card: Dictionary = frame.get("card", {}) as Dictionary
	var payload: Dictionary = frame.get("payload", {}) as Dictionary
	match str(frame.get("kind", "")):
		"noble":
			_finalize_play_noble(p, card, payload)
		"bird":
			_finalize_play_bird(p, card, payload)
		"temple":
			_finalize_play_temple(p, card, payload)
		"incantation":
			_finalize_play_incantation(p, card, payload)
		"dethrone":
			_finalize_play_dethrone(p, card, payload)
		"ring":
			_finalize_play_ring(p, card, payload)


func _queue_post_effect_scion_trigger(p: int, verb: String) -> void:
	var v := verb.to_lower()
	if v == "insight":
		if _noble_on_field(p, "rmrsk_emanation"):
			_set_scion_pending(p, "rmrsk_draw")
		return
	if v == "burn" or v == "revive" or v == "renew":
		if _noble_on_field(p, "smrsk_occultation"):
			_set_scion_pending(p, "smrsk_burn")
		return
	if v == "wrath":
		if _noble_on_field(p, "tmrsk_annihilation"):
			_set_scion_pending(p, "tmrsk_woe")
			_log("P%d: Tmrsk — choose Woe 3 (after Wrath)." % p)


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
		var def_phaedra := bool(_scion_pending.get("deferred_phaedra_temple_draw", false))
		_scion_clear_pending()
		match ptype:
			"rmrsk_draw":
				_log("P%d skips Rmrsk trigger." % p)
				if def_phaedra:
					_draw_n(p, 1)
			"smrsk_burn":
				_log("P%d skips Smrsk trigger." % p)
			"tmrsk_woe":
				_log("P%d skips Tmrsk trigger." % p)
		return "ok"
	match ptype:
		"rmrsk_draw":
			var def_phaedra2 := bool(_scion_pending.get("deferred_phaedra_temple_draw", false))
			_scion_clear_pending()
			_draw_n(p, 1)
			_log("P%d resolves Rmrsk (draw 1)." % p)
			if def_phaedra2:
				_draw_n(p, 1)
			return "ok"
		"smrsk_burn":
			var ritual_mid := int(ctx.get("ritual_mid", -1))
			var power := _ritual_value_for_mid(p, ritual_mid)
			if power <= 0:
				return "illegal"
			_scion_clear_pending()
			_apply_sacrifice(p, {ritual_mid: true})
			_log("P%d resolves Smrsk (sacrifice %d-power ritual; Burn self %d)." % [p, power, power])
			var berr := execute_incantation_effect(p, "burn", power, [], {"mill_target": p})
			if berr != "ok":
				return berr
			_check_power_win(p)
			return "ok"
		"tmrsk_woe":
			var wt := int(ctx.get("woe_target", -1))
			var opp := 1 - p
			if wt != p and wt != opp:
				return "illegal_target"
			var need := _woe_discard_need(p, 3, wt)
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
			_log("P%d resolves Tmrsk (Woe 3)." % p)
			var werr := execute_incantation_effect(p, "woe", 3, [], ctx)
			if werr != "ok":
				return werr
			_check_power_win(p)
			return "ok"
		_:
			return "illegal"


func can_submit_void(p: int) -> bool:
	if phase == Phase.GAME_OVER:
		return false
	if _pending_stack.is_empty():
		return false
	return p == _pending_reactor()


func submit_void_react(p: int, void_hand_idx: int, discard_hand_idx: int) -> String:
	if not can_submit_void(p):
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	if void_hand_idx < 0 or void_hand_idx >= hand.size():
		return "illegal"
	if discard_hand_idx < 0 or discard_hand_idx >= hand.size():
		return "illegal"
	if void_hand_idx == discard_hand_idx:
		return "illegal"
	if not _is_void_card(hand[void_hand_idx]):
		return "illegal"
	var void_card: Dictionary
	var disc_card: Dictionary
	if void_hand_idx > discard_hand_idx:
		void_card = hand[void_hand_idx] as Dictionary
		hand.remove_at(void_hand_idx)
		disc_card = hand[discard_hand_idx] as Dictionary
		hand.remove_at(discard_hand_idx)
	else:
		disc_card = hand[discard_hand_idx] as Dictionary
		hand.remove_at(discard_hand_idx)
		void_card = hand[void_hand_idx] as Dictionary
		hand.remove_at(void_hand_idx)
	pl["crypt"].append(disc_card)
	_log("P%d discards 1 card to pay for Void." % p)
	var frame := {
		"kind": "incantation",
		"is_void": true,
		"card": void_card,
		"label": "Void",
		"cost": 0,
		"payload": {"verb": "void", "verb_raw": "Void", "value": 0}
	}
	_open_void_window_or_resolve(p, frame)
	return "ok"


func submit_void_skip(p: int) -> String:
	if not can_submit_void(p):
		return "illegal"
	_void_deadline_ms = 0
	_resolve_pending_stack_tail()
	return "ok"


func can_play_incantation(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or _card_kind(c) != "incantation":
		return false
	var verb := str(c.get("verb", ""))
	var vl := verb.to_lower()
	var n: int = int(c["value"])
	if n < 1 and vl != "wrath":
		return false
	var n_eff := effective_incantation_cost(p, verb, n)
	if vl == "renew" and _ritual_crypt_cards(_players[p]).is_empty():
		if n_eff <= 0:
			return false
		if has_active_incantation_lane(p, n_eff):
			return false
		if not _can_sacrifice(p, n_eff):
			return false
	if vl == "wrath":
		return not (_players[p]["field"] as Array).is_empty()
	if n_eff <= 0:
		return true
	if has_active_incantation_lane(p, n_eff):
		return true
	return _can_sacrifice(p, n_eff)


func can_play_dethrone(p: int, hand_idx: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
		return false
	var c: Variant = _card_at_hand(p, hand_idx)
	if c == null or not CardTraits.is_dethrone(c as Dictionary):
		return false
	var n := int(c.get("value", 4))
	if n != 4:
		return false
	if not has_active_ritual_lane(p, n) and not _can_sacrifice(p, n):
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
		"renew":
			return "illegal"
		"wrath":
			if effective_wrath_destroy_count(p, value) == 0:
				return "illegal"
			_destroy_rituals_by_mids(opp, wrath_resolved)
			return "ok"
		"deluge":
			if value < 2 or value > 4:
				return "illegal"
			var threshold := value - 1
			var destroyed := _destroy_birds_with_power_at_most(threshold)
			_log("Deluge %d destroys %d wild bird(s) with power %d or less, then unnests all surviving birds." % [value, destroyed, threshold])
			return "ok"
		"tears":
			var tidx := int(ctx.get("tears_crypt_idx", -1))
			var pl_t: Dictionary = _players[p]
			var cidx := _bird_crypt_index_to_crypt_index(pl_t, tidx)
			if cidx < 0:
				return "illegal_target"
			var crypt_t: Array = pl_t["crypt"]
			var bcard: Dictionary = (crypt_t[cidx] as Dictionary).duplicate(true)
			crypt_t.remove_at(cidx)
			var bmid := _next_bird_mid(pl_t)
			var bird := {
				"mid": bmid,
				"bird_id": str(bcard.get("bird_id", "")),
				"name": str(bcard.get("name", "Bird")),
				"cost": int(bcard.get("cost", 0)),
				"power": int(bcard.get("power", 0)),
				"damage": 0,
				"nest_temple_mid": -1,
				"rings": []
			}
			pl_t["bird_field"].append(bird)
			_log("P%d Tears revives %s from crypt." % [p, bird["name"]])
			return "ok"
		"flight":
			var draw_n := (_players[p]["bird_field"] as Array).size()
			_draw_n(p, draw_n)
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
		"deluge":
			if value < 2 or value > 4:
				return "illegal"
			return "ok"
		"tears":
			var tidx := int(ctx.get("tears_crypt_idx", -1))
			var bcards: Array = _bird_crypt_cards(_players[p])
			if tidx < 0 or tidx >= bcards.size():
				return "illegal_target"
			return "ok"
		"flight":
			return "ok"
		"seek":
			return "ok"
		"revive":
			return _validate_revive_chain(p, value, ctx)
		"renew":
			return _validate_renew_ctx(p, ctx)
		_:
			return "ok"


func _validate_revive_chain(p: int, _value: int, ctx: Dictionary) -> String:
	var steps: Array = ctx.get("revive_steps", []) as Array
	if steps.is_empty():
		steps = [ctx]
	var yytzr_renew_idx := int(ctx.get("yytzr_renew_ritual_crypt_idx", -1))
	var want_steps := steps.size()
	if want_steps != 1:
		return "illegal"
	if yytzr_renew_idx >= 0:
		if not _noble_on_field(p, "yytzr_occultation"):
			return "illegal"
		var rituals: Array = _ritual_crypt_cards(_players[p])
		if yytzr_renew_idx >= rituals.size():
			return "illegal_target"
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
		if cv == "revive" or cv == "tears":
			return "illegal"
		var nested: Dictionary = d.get("nested", {}) as Dictionary
		var wr_mids: Array = nested.get("wrath_mids", []) as Array
		if _validate_play_ctx(p, cv, cn, wr_mids, nested) != "ok":
			return "illegal"
	return "ok"


func _run_revive_steps_after_payment(p: int, value: int, ctx: Dictionary, payment_text: String, revive_wrapper: Dictionary) -> String:
	var steps: Array = ctx.get("revive_steps", []) as Array
	var yytzr_renew_idx := int(ctx.get("yytzr_renew_ritual_crypt_idx", -1))
	if steps.is_empty():
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
		_log("P%d plays Revive %d (%s) — skipped." % [p, value, payment_text], _incantation_log_meta("revive", value, "Revive"))
		_check_power_win(p)
		return "ok"
	_log("P%d plays Revive %d (%s)." % [p, value, payment_text], _incantation_log_meta("revive", value, "Revive"))
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
				_log("P%d Revive %d: Woe pending on P%d." % [p, value, wt], _incantation_log_meta("woe", cn, "Woe"))
				return "ok"
		if cv == "renew":
			var rerr := _renew_subcast_play_ritual_from_nested(p, nested, payment_text, cn)
			if rerr != "ok":
				crypt.insert(crypt_idx, crypt_card)
				return rerr
			pl["inc_abyss"].append(crypt_card)
			_queue_post_effect_scion_trigger(p, "renew")
			_log("P%d Revive casts Renew %d from crypt (%s)." % [p, cn, payment_text], _incantation_log_meta("renew", cn, "Renew"))
			_check_power_win(p)
			continue
		var err := execute_incantation_effect(p, cv, cn, wr_r, nested)
		if err != "ok":
			crypt.insert(crypt_idx, crypt_card)
			return err
		pl["inc_abyss"].append(crypt_card)
		_log("P%d Revive casts %s %d from crypt (%s)." % [p, cv, cn, payment_text], _incantation_log_meta(cv, cn, cv.capitalize()))
		_check_power_win(p)
	if yytzr_renew_idx >= 0:
		var rg: Array = _ritual_crypt_cards(pl)
		if yytzr_renew_idx < 0 or yytzr_renew_idx >= rg.size():
			return "illegal_target"
		var gidx := _ritual_crypt_index_to_crypt_index(pl, yytzr_renew_idx)
		if gidx < 0:
			return "illegal_target"
		var crypt_y: Array = pl["crypt"] as Array
		var rc: Dictionary = (crypt_y[gidx] as Dictionary).duplicate(true)
		crypt_y.remove_at(gidx)
		var ymid := _next_mid(pl)
		pl["field"].append({"mid": ymid, "value": int(rc.get("value", 0))})
		_log("P%d Yytzr: Revive also plays %d-Ritual from crypt." % [p, int(rc.get("value", 0))], _incantation_log_meta("renew", 0, "Renew"))
		_queue_post_effect_scion_trigger(p, "renew")
	pl["crypt"].append(revive_wrapper)
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
	var needs_cost_discard := false
	match nid:
		"bndrr_incantation":
			if v != "burn" or value != 2:
				return "illegal"
		"wndrr_incantation":
			if v != "woe" or value != 3:
				return "illegal"
			if int(ctx.get("woe_target", -1)) != 1 - p:
				return "illegal"
			needs_cost_discard = true
		"sndrr_incantation":
			if v != "seek" or value != 1:
				return "illegal"
			needs_cost_discard = true
		_:
			return "illegal"
	var cost_idx := -1
	if needs_cost_discard:
		var hand_sz_cost: int = (_players[p]["hand"] as Array).size()
		cost_idx = int(ctx.get("discard_hand_idx", -1))
		if cost_idx < 0 or cost_idx >= hand_sz_cost:
			return "illegal"
	if _validate_play_ctx(p, v, value, wrath_mids, ctx) != "ok":
		return "illegal"
	if needs_cost_discard:
		var pl_pay: Dictionary = _players[p]
		var hand_pay: Array = pl_pay["hand"]
		_move_hand_card_to_discard(pl_pay, hand_pay, cost_idx)
		_log("P%d discards 1 card to activate %s." % [p, str(noble.get("name", nid))])
	var wr_r: Array = []
	if v == "wrath":
		wr_r = _wrath_resolve_mids(1 - p, value, wrath_mids, p)
	if v == "woe":
		var wt := int(ctx.get("woe_target", -1))
		var opp := 1 - p
		var need := _woe_discard_need(p, value, wt)
		# Wndrr's noble activation uses Woe 3 but should only force 1 discard.
		if nid == "wndrr_incantation":
			need = mini(1, (_players[wt]["hand"] as Array).size())
		if wt == opp and need > 0:
			_woe_pending_instigator = p
			_woe_pending_victim = wt
			_woe_pending_amount = need
			_woe_pending_spell_card = null
			_woe_pending_spell_to_abyss = false
			_woe_pending_revive_wrapper = null
			_woe_pending_noble_mid = noble_mid
			_log("P%d activates Wndrr; Woe pending on P%d." % [p, wt], _incantation_log_meta("woe", value, "Woe"))
			return "ok"
	match nid:
		"bndrr_incantation":
			_log("P%d activates Bndrr (Burn 2)." % p, _incantation_log_meta("burn", value, "Burn"))
		"wndrr_incantation":
			_log("P%d activates Wndrr (Woe 3)." % p, _incantation_log_meta("woe", value, "Woe"))
		"sndrr_incantation":
			_log("P%d activates Sndrr (Seek 1)." % p, _incantation_log_meta("seek", value, "Seek"))
		_:
			pass
	var err := execute_incantation_effect(p, v, value, wr_r, ctx)
	if err != "ok":
		return err
	_queue_post_effect_scion_trigger(p, v)
	_mark_noble_used_this_turn(p, noble_mid)
	_check_power_win(p)
	return "ok"


func apply_noble_revive_from_crypt(p: int, noble_mid: int, ctx: Dictionary) -> String:
	if not can_activate_noble(p, noble_mid):
		return "illegal"
	var noble := _find_noble_on_field(p, noble_mid)
	if str(noble.get("noble_id", "")) != "rndrr_incantation":
		return "illegal"
	if _validate_play_ctx(p, "revive", 1, [], ctx) != "ok":
		return "illegal"
	var pl: Dictionary = _players[p]
	var steps: Array = ctx.get("revive_steps", []) as Array
	if steps.is_empty():
		steps = [ctx]
	var yytzr_renew_idx := int(ctx.get("yytzr_renew_ritual_crypt_idx", -1))
	if steps.size() != 1:
		return "illegal"
	if yytzr_renew_idx >= 0 and not _noble_on_field(p, "yytzr_occultation"):
		return "illegal"
	var d0: Dictionary = steps[0]
	if bool(d0.get("revive_skip", false)):
		_mark_noble_used_this_turn(p, noble_mid)
		_log("P%d activates Rndrr (Revive 2 skipped)." % p, _incantation_log_meta("revive", 2, "Revive"))
		return "ok"
	_log("P%d activates Rndrr (Revive from crypt)." % p, _incantation_log_meta("revive", 2, "Revive"))
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
		if cv == "renew":
			var rerr := _renew_subcast_play_ritual_from_nested(p, nested, "Rndrr", cn)
			if rerr != "ok":
				crypt.insert(crypt_idx, crypt_card)
				return rerr
			pl["inc_abyss"].append(crypt_card)
			_log("P%d Revive casts Renew %d from crypt (Rndrr)." % [p, cn], _incantation_log_meta("renew", cn, "Renew"))
			_queue_post_effect_scion_trigger(p, "renew")
			_check_power_win(p)
			continue
		var err := execute_incantation_effect(p, cv, cn, wr_r, nested)
		if err != "ok":
			crypt.insert(crypt_idx, crypt_card)
			return err
		pl["inc_abyss"].append(crypt_card)
		_log("P%d Revive casts %s %d from crypt (Rndrr)." % [p, cv, cn], _incantation_log_meta(cv, cn, cv.capitalize()))
		_queue_post_effect_scion_trigger(p, cv)
		_check_power_win(p)
	if yytzr_renew_idx >= 0:
		var rg: Array = _ritual_crypt_cards(pl)
		if yytzr_renew_idx < 0 or yytzr_renew_idx >= rg.size():
			return "illegal_target"
		var gidx := _ritual_crypt_index_to_crypt_index(pl, yytzr_renew_idx)
		if gidx < 0:
			return "illegal_target"
		var crypt_y: Array = pl["crypt"] as Array
		var rc: Dictionary = (crypt_y[gidx] as Dictionary).duplicate(true)
		crypt_y.remove_at(gidx)
		var ymid := _next_mid(pl)
		pl["field"].append({"mid": ymid, "value": int(rc.get("value", 0))})
		_log("P%d Yytzr: Revive also plays %d-Ritual from crypt." % [p, int(rc.get("value", 0))], _incantation_log_meta("renew", 0, "Renew"))
		_queue_post_effect_scion_trigger(p, "renew")
	_mark_noble_used_this_turn(p, noble_mid)
	_queue_post_effect_scion_trigger(p, "revive")
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
	var crypt_arr: Array = pl["crypt"] as Array
	var c: Dictionary = (crypt_arr[global_crypt_idx] as Dictionary).duplicate(true)
	crypt_arr.remove_at(global_crypt_idx)
	var mid := _next_mid(pl)
	pl["field"].append({"mid": mid, "value": int(c["value"])})
	_mark_noble_used_this_turn(p, noble_mid)
	_log("P%d plays %d-Ritual from crypt (Aeoiu)." % [p, int(c["value"])])
	_check_power_win(p)
	return "ok"


func _renew_subcast_play_ritual_from_nested(p: int, nested: Dictionary, payment_text: String, renew_value: int) -> String:
	var ridx := int(nested.get("renew_ritual_crypt_idx", -1))
	var pl: Dictionary = _players[p]
	var rg: Array = _ritual_crypt_cards(pl)
	if ridx < 0 or ridx >= rg.size():
		return "illegal_target"
	var global_crypt_idx := _ritual_crypt_index_to_crypt_index(pl, ridx)
	if global_crypt_idx < 0:
		return "illegal_target"
	var crypt: Array = pl["crypt"] as Array
	var c: Dictionary = (crypt[global_crypt_idx] as Dictionary).duplicate(true)
	crypt.remove_at(global_crypt_idx)
	var mid := _next_mid(pl)
	pl["field"].append({"mid": mid, "value": int(c["value"])})
	_log("P%d Revive subcast: Renew plays %d-Ritual from crypt (%s)." % [p, int(c["value"]), payment_text], _incantation_log_meta("renew", renew_value, "Renew"))
	return "ok"


func _apply_renew_ritual_from_crypt(p: int, n: int, ctx: Dictionary, payment_text: String, renew_card: Dictionary) -> void:
	var pl: Dictionary = _players[p]
	var crypt_idx := int(ctx.get("renew_ritual_crypt_idx", -1))
	var rg: Array = _ritual_crypt_cards(pl)
	if crypt_idx < 0 or crypt_idx >= rg.size():
		return
	if ctx.has("renew_second_ritual_crypt_idx"):
		return
	var global_crypt_idx := _ritual_crypt_index_to_crypt_index(pl, crypt_idx)
	if global_crypt_idx < 0:
		return
	var c: Dictionary = ((pl["crypt"] as Array)[global_crypt_idx] as Dictionary).duplicate(true)
	(pl["crypt"] as Array).remove_at(global_crypt_idx)
	var mid := _next_mid(pl)
	pl["field"].append({"mid": mid, "value": int(c["value"])})
	_log("P%d plays Renew %d (%s)." % [p, n, payment_text], _incantation_log_meta("renew", n, "Renew"))
	_log("P%d plays %d-Ritual from crypt (Renew)." % [p, int(c["value"])])
	_queue_post_effect_scion_trigger(p, "renew")
	pl["crypt"].append(renew_card)
	_check_power_win(p)


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
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
		return false
	var t := _find_temple_on_field(p, temple_mid)
	if t.is_empty():
		return false
	if int(t.get("used_turn", -1)) == turn_number:
		return false
	var tid := str(t.get("temple_id", ""))
	if tid == TEMPLE_EYRIE:
		return false
	if tid == TEMPLE_DELPHA:
		var pl: Dictionary = _players[p]
		if _ritual_crypt_cards(pl).is_empty():
			return false
		if (pl["field"] as Array).is_empty():
			return false
	if tid == TEMPLE_YTRIA:
		if (_players[p]["hand"] as Array).is_empty():
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
	_log("P%d activates Phaedra (Insight 1, draw 1)." % p)
	var err := execute_incantation_effect(p, "insight", 1, [], ctx)
	if err != "ok":
		return err
	_queue_post_effect_scion_trigger(p, "insight")
	if _scion_waiting_on_response():
		_scion_pending["deferred_phaedra_temple_draw"] = true
	else:
		_draw_n(p, 1)
	_mark_temple_used_this_turn(p, temple_mid)
	_check_power_win(p)
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
	var abyss_ritual := {"mid": ritual_mid, "type": "ritual", "value": x}
	pl["field"] = keep
	pl["inc_abyss"].append(abyss_ritual)
	_log("P%d activates Delpha (send ritual %d to abyss, Burn %d, ritual from crypt)." % [p, ritual_mid, x])
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
	_check_power_win(p)
	return "ok"


func _gotha_draw_value_for_card(c: Dictionary) -> int:
	var k := _card_kind(c)
	if k == "ritual":
		return maxi(0, int(c.get("value", 0)))
	if k == "incantation":
		return maxi(0, int(c.get("value", 0)))
	if k == "noble":
		return maxi(0, _noble_play_cost(str(c.get("noble_id", ""))))
	if k == "bird":
		return maxi(0, int(c.get("cost", 0)))
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
	if _card_kind(c) == "temple":
		return "illegal"
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


func apply_temple_ytria(p: int, temple_mid: int) -> String:
	if not can_activate_temple(p, temple_mid):
		return "illegal"
	var t := _find_temple_on_field(p, temple_mid)
	if str(t.get("temple_id", "")) != TEMPLE_YTRIA:
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	var draw_n := hand.size()
	if draw_n < 1:
		return "illegal"
	for i in range(hand.size() - 1, -1, -1):
		_move_hand_card_to_discard(pl, hand, i)
	_draw_n(p, draw_n)
	_mark_temple_used_this_turn(p, temple_mid)
	_log("P%d activates Ytria (discard %d, draw %d)." % [p, draw_n, draw_n])
	_check_power_win(p)
	return "ok"


func play_incantation(p: int, hand_idx: int, sacrifice_mids: Array, wrath_mids: Array = [], ctx: Dictionary = {}) -> String:
	if not can_play_incantation(p, hand_idx):
		return "illegal"
	var c: Dictionary = _card_at_hand(p, hand_idx)
	var n: int = int(c["value"])
	if n < 1 and str(c.get("verb", "")).to_lower() != "wrath":
		return "illegal"
	if str(c.get("verb", "")).to_lower() == "void":
		return "illegal"
	var verb_raw: String = str(c.get("verb", ""))
	var verb: String = verb_raw.to_lower()
	var n_eff := effective_incantation_cost(p, verb, n)
	var wrath_one := verb == "wrath"
	var need_sac := (n_eff > 0 and not has_active_incantation_lane(p, n_eff)) or wrath_one
	var mids: Dictionary = {}
	if need_sac:
		for m in sacrifice_mids:
			mids[int(m)] = true
		if wrath_one:
			if mids.size() != 1:
				return "illegal_sacrifice"
			var ok_one := false
			for mid in mids:
				ok_one = _ritual_mid_on_player_field(p, int(mid))
				break
			if not ok_one:
				return "illegal_sacrifice"
		elif not _sacrifice_valid(p, n_eff, mids):
			mids.clear()
			for mid in _greedy_sacrifice_mids_for_player(p, n_eff):
				mids[int(mid)] = true
			if not _sacrifice_valid(p, n_eff, mids):
				return "illegal_sacrifice"
	var ctx_use: Dictionary = ctx.duplicate(true)
	if verb == "wrath":
		var werr := _validate_wrath_instigator_sacrifice(p, need_sac, mids, ctx_use)
		if werr != "ok":
			return werr
		if not need_sac:
			var wtx := int(ctx_use.get("wrath_instigator_sac_mid", -1))
			if wtx >= 0:
				mids[wtx] = true
	if verb == "renew":
		if _validate_renew_ctx_presacrifice(p, ctx_use, mids, {}) != "ok":
			return "illegal"
	elif verb == "revive":
		if _validate_revive_chain(p, n, ctx_use) != "ok":
			return "illegal"
	elif _validate_play_ctx(p, verb, n, wrath_mids, ctx_use) != "ok":
		return "illegal"
	var payment_text: String
	if wrath_one:
		payment_text = "0-cost Wrath — paid by sacrificing one ritual"
	else:
		payment_text = _incantation_payment_text(p, n_eff, need_sac, mids)
	_apply_sacrifice(p, mids)
	var pl: Dictionary = _players[p]
	pl["hand"].remove_at(hand_idx)
	var label := incantation_display_name(verb, verb_raw, n)
	var frame := {
		"kind": "incantation",
		"card": c,
		"label": label,
		"cost": n,
		"payload": {
			"verb": verb,
			"verb_raw": verb_raw,
			"value": n,
			"wrath_mids": wrath_mids.duplicate(),
			"ctx": ctx_use,
			"payment_text": payment_text
		}
	}
	_open_void_window_or_resolve(p, frame)
	return "ok"


func _finalize_play_incantation(p: int, card: Dictionary, payload: Dictionary) -> void:
	var pl: Dictionary = _players[p]
	var verb := str(payload.get("verb", "")).to_lower()
	var verb_raw := str(payload.get("verb_raw", verb))
	var n := int(payload.get("value", 0))
	var wrath_mids: Array = payload.get("wrath_mids", []) as Array
	var ctx_use: Dictionary = payload.get("ctx", {}) as Dictionary
	var payment_text := str(payload.get("payment_text", ""))
	var play_disp := incantation_display_name(verb, verb_raw, n)
	var play_meta := _incantation_log_meta(verb, n, verb_raw)
	if verb == "revive":
		var rr := _run_revive_steps_after_payment(p, n, ctx_use, payment_text, card)
		if rr == "ok":
			_queue_post_effect_scion_trigger(p, "revive")
		return
	if verb == "renew":
		_apply_renew_ritual_from_crypt(p, n, ctx_use, payment_text, card)
		return
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
			_woe_pending_spell_card = card
			_woe_pending_spell_to_abyss = false
			_woe_pending_revive_wrapper = null
			_woe_pending_noble_mid = -1
			_log("P%d plays %s (%s); Woe pending on P%d." % [p, play_disp, payment_text, wt], play_meta)
			return
	_log("P%d plays %s (%s)." % [p, play_disp, payment_text], play_meta)
	execute_incantation_effect(p, verb, n, wrath_resolved, ctx_use)
	_queue_post_effect_scion_trigger(p, verb)
	pl["crypt"].append(card)
	_check_power_win(p)


func play_dethrone(p: int, hand_idx: int, noble_mids: Array = [], sacrifice_mids: Array = []) -> String:
	if not can_play_dethrone(p, hand_idx):
		return "illegal"
	var pl: Dictionary = _players[p]
	var hand: Array = pl["hand"]
	var c: Dictionary = hand[hand_idx]
	var n := int(c.get("value", 4))
	var need_sac := not has_active_ritual_lane(p, n)
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
	var frame := {
		"kind": "dethrone",
		"card": c,
		"label": "Dethrone %d" % n,
		"cost": n,
		"payload": {"noble_mids": destroyed.duplicate(), "value": n}
	}
	_open_void_window_or_resolve(p, frame)
	return "ok"


func _finalize_play_dethrone(p: int, card: Dictionary, payload: Dictionary) -> void:
	var pl: Dictionary = _players[p]
	var n := int(payload.get("value", 4))
	var noble_mids: Array = payload.get("noble_mids", []) as Array
	var destroyed := _dethrone_resolve_mids(1 - p, noble_mids)
	_log("P%d plays Dethrone %d." % [p, n])
	if not destroyed.is_empty():
		_destroy_nobles_by_mids(1 - p, destroyed)
	pl["crypt"].append(card)


func can_activate_noble(p: int, noble_mid: int) -> bool:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return false
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return false
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return false
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
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
		if _validate_play_ctx(p, "insight", 1, [], ctx) != "ok":
			return "illegal"
		_log("P%d activates Indrr (Insight %d)." % [p, insight_effective_n(p, 1)], _incantation_log_meta("insight", 1, "Insight"))
		execute_incantation_effect(p, "insight", 1, [], ctx)
		_queue_post_effect_scion_trigger(p, "insight")
		_mark_noble_used_this_turn(p, noble_mid)
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


func _ritual_mid_on_player_field(p: int, mid: int) -> bool:
	for x in (_players[p]["field"] as Array):
		if int(x.get("mid", -1)) == mid:
			return true
	return false


func _validate_wrath_instigator_sacrifice(p: int, need_sac: bool, payment_mids: Dictionary, ctx: Dictionary) -> String:
	var tx := int(ctx.get("wrath_instigator_sac_mid", -1))
	if need_sac:
		if tx >= 0 and payment_mids.has(tx):
			return "illegal_wrath_sac"
		return "ok"
	if tx < 0 or not _ritual_mid_on_player_field(p, tx):
		return "illegal_wrath_sac"
	if payment_mids.has(tx):
		return "illegal_wrath_sac"
	return "ok"


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
		if cost <= 0:
			return "free via ring reduction"
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
	if execute_incantation_effect(p, v, value, wr, ctx) != "ok":
		return
	_queue_post_effect_scion_trigger(p, v)
	_check_power_win(p)


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
	# Printed cost 0 (normal); 4 is legacy deck data.
	if value == 0 or value == 4:
		return 1
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


func _apply_damage_to_selected_birds(p: int, selected_mids: Dictionary, assign: Dictionary) -> Array:
	var dead: Array = []
	var birds: Array = _players[p]["bird_field"]
	for i in birds.size():
		var b: Dictionary = birds[i]
		var mid := int(b.get("mid", -1))
		if not selected_mids.has(mid):
			continue
		b["damage"] = int(b.get("damage", 0)) + int(assign.get(mid, 0))
		birds[i] = b
		if int(b.get("damage", 0)) >= int(b.get("power", 0)):
			dead.append(mid)
	return dead


func _destroy_birds_by_mids(target: int, mids: Array) -> void:
	if mids.is_empty():
		return
	var kill: Dictionary = {}
	for m in mids:
		kill[int(m)] = true
	var pl: Dictionary = _players[target]
	var keep: Array = []
	for b in pl["bird_field"]:
		var bd := b as Dictionary
		var bmid := int(bd.get("mid", -1))
		if kill.has(bmid):
			var ntm := _bird_nest_temple_mid(bd)
			if ntm >= 0:
				_remove_bird_from_temple_nest(target, ntm, bmid)
			_shed_rings_to_crypt(pl, bd)
			var to_crypt := bd.duplicate(true)
			to_crypt.erase("damage")
			to_crypt.erase("nest_temple_mid")
			to_crypt.erase("rings")
			pl["crypt"].append(to_crypt)
		else:
			var kept := bd.duplicate(true)
			kept["damage"] = 0
			keep.append(kept)
	pl["bird_field"] = keep
	_log("Bird fight destroys %d bird(s) on P%d." % [mids.size(), target])


func _destroy_birds_with_power_at_most(power: int) -> int:
	var total := 0
	for p in range(2):
		var pl: Dictionary = _players[p]
		var keep: Array = []
		for b in pl["bird_field"]:
			var bd := b as Dictionary
			if power > 0 and int(bd.get("power", 0)) <= power and _bird_nest_temple_mid(bd) < 0:
				_shed_rings_to_crypt(pl, bd)
				var to_crypt := bd.duplicate(true)
				to_crypt.erase("damage")
				to_crypt.erase("nest_temple_mid")
				to_crypt.erase("rings")
				pl["crypt"].append(to_crypt)
				total += 1
			else:
				var kept := bd.duplicate(true)
				kept["damage"] = 0
				keep.append(kept)
		pl["bird_field"] = keep
		_unnest_all_birds(p)
	return total


func _unnest_all_birds(p: int) -> void:
	var pl: Dictionary = _players[p]
	var bf: Array = pl["bird_field"]
	for i in bf.size():
		var bd: Dictionary = bf[i]
		if int(bd.get("nest_temple_mid", -1)) >= 0:
			bd["nest_temple_mid"] = -1
			bf[i] = bd
	var tf: Array = _temple_field_safe(p)
	for j in tf.size():
		var td: Dictionary = tf[j]
		if not (td.get("nested_bird_mids", []) as Array).is_empty() or bool(td.get("nested", false)):
			td["nested_bird_mids"] = []
			td["nested"] = false
			tf[j] = td


func resolve_bird_fight(p: int, attacker_mids: Array, defender_mid: int, attacker_damage_assign: Dictionary = {}) -> String:
	if phase != Phase.MAIN or _is_mulligan_active() or p != current:
		return "illegal"
	if bird_fight_used_this_turn:
		return "illegal"
	if _woe_waiting_on_response() and p == _woe_pending_instigator:
		return "illegal"
	if _scion_waiting_on_response() and p == int(_scion_pending.get("player", -1)):
		return "illegal"
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return "illegal"
	if _pending_stack_blocks_action(p):
		return "illegal"
	if attacker_mids.is_empty():
		return "illegal"
	var opp := 1 - p
	var target := _find_bird_on_field(opp, defender_mid)
	if target.is_empty():
		return "illegal_target"
	if _bird_nest_temple_mid(target) >= 0:
		return "illegal_target"
	var selected_att: Dictionary = {}
	var attack_power := 0
	for m in attacker_mids:
		var mid := int(m)
		if selected_att.has(mid):
			return "illegal"
		var b := _find_bird_on_field(p, mid)
		if b.is_empty():
			return "illegal"
		if _bird_nest_temple_mid(b) >= 0:
			return "illegal"
		selected_att[mid] = true
		attack_power += int(b.get("power", 0))
	var defend_power := int(target.get("power", 0))
	var assigned_to_attackers := 0
	for k in attacker_damage_assign.keys():
		var amid := int(k)
		if not selected_att.has(amid):
			return "illegal_assign"
		var dmg := int(attacker_damage_assign[k])
		if dmg < 0:
			return "illegal_assign"
		assigned_to_attackers += dmg
	if assigned_to_attackers != defend_power:
		return "illegal_assign"
	var dead_att := _apply_damage_to_selected_birds(p, selected_att, attacker_damage_assign)
	var dead_def := _apply_damage_to_selected_birds(opp, {defender_mid: true}, {defender_mid: attack_power})
	_destroy_birds_by_mids(p, dead_att)
	_destroy_birds_by_mids(opp, dead_def)
	bird_fight_used_this_turn = true
	_log("P%d resolves bird fight with %d attacker(s)." % [p, attacker_mids.size()])
	return "ok"


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
		var nd := x as Dictionary
		if kill.has(int(nd["mid"])):
			_shed_rings_to_crypt(pl, nd)
			var to_crypt := nd.duplicate(true)
			to_crypt.erase("rings")
			pl["crypt"].append(to_crypt)
		else:
			keep.append(nd)
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
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return false
	if _pending_stack_blocks_action(p):
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
	pl["crypt"].append(c)


func _inc_crypt_cards(pl: Dictionary) -> Array:
	var out: Array = []
	for c in (pl["crypt"] as Array):
		if _card_kind(c) == "incantation":
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


func _bird_crypt_cards(pl: Dictionary) -> Array:
	var out: Array = []
	for c in (pl["crypt"] as Array):
		if _card_kind(c) == "bird":
			out.append(c)
	return out


func _bird_crypt_index_to_crypt_index(pl: Dictionary, bird_idx: int) -> int:
	if bird_idx < 0:
		return -1
	var seen := 0
	var crypt: Array = pl["crypt"]
	for i in crypt.size():
		if _card_kind(crypt[i]) == "bird":
			if seen == bird_idx:
				return i
			seen += 1
	return -1


func _inc_crypt_index_to_crypt_index(pl: Dictionary, inc_idx: int) -> int:
	if inc_idx < 0:
		return -1
	var seen := 0
	var crypt: Array = pl["crypt"]
	for i in crypt.size():
		if _card_kind(crypt[i]) == "incantation":
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
	if _eyrie_waiting_on_response() and p == _eyrie_pending_player:
		return "illegal"
	if _pending_stack_blocks_action(p):
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
	_log("P%d ends turn." % p)
	if goldfish:
		current = 0
	else:
		current = 1 - p
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


func _log(s: String, meta: Dictionary = {}) -> void:
	var entry := {
		"text": s,
		"turn": turn_number,
		"player": current,
		"starter": _starting_player,
	}
	if not meta.is_empty():
		entry["meta"] = meta.duplicate(true)
	log_lines.append(entry)
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

extends RefCounted
class_name ArcanaCpuOpponent

const CPU_ACTION_SEC := 1.618
const _GameSnapshotUtils = preload("res://game_snapshot_utils.gd")
const _CardTraits = preload("res://card_traits.gd")

static func greedy_sacrifice_mids(snap: Dictionary, need: int) -> Array:
	var field: Array = snap.get("your_field", [])
	var items: Array = []
	for x in field:
		items.append({"mid": int(x.get("mid", 0)), "v": int(x.get("value", 0))})
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


static func greedy_wrath_mids(opp_field: Array, need: int) -> Array:
	var items: Array = []
	for x in opp_field:
		items.append({"mid": int(x.get("mid", 0)), "v": int(x.get("value", 0))})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["v"] < b["v"]
	)
	var out: Array = []
	for i in mini(need, items.size()):
		out.append(items[i]["mid"])
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


func run_turn(host: Node) -> void:
	if host._match == null:
		return
	var snap: Dictionary
	while true:
		await host.get_tree().create_timer(CPU_ACTION_SEC).timeout
		snap = host._match.snapshot(1)
		if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
			return
		if bool(snap.get("woe_pending_you_respond", false)):
			var hwo: Array = snap.get("your_hand", [])
			var needw := int(snap.get("woe_pending_amount", 0))
			var idxsw: Array = []
			for wi in mini(needw, hwo.size()):
				idxsw.append(wi)
			host._try_submit_woe_discard(1, idxsw, true)
			continue
		if bool(snap.get("eyrie_pending_you_respond", false)):
			var picks: Array = []
			var cands: Array = snap.get("eyrie_bird_candidates", []) as Array
			var rem := int(snap.get("eyrie_pending_remaining", 0))
			for ci in mini(rem, cands.size()):
				picks.append(int((cands[ci] as Dictionary).get("deck_idx", -1)))
			if host._match.apply_eyrie_submit(1, picks) == "ok":
				host._broadcast_sync(false)
			continue
		if bool(snap.get("scion_pending_you_respond", false)):
			var st := str(snap.get("scion_pending_type", ""))
			var sid := int(snap.get("scion_pending_id", -1))
			if st == "rmrsk_draw":
				if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid}, false):
					host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
				continue
			if st == "smrsk_burn":
				var ff: Array = snap.get("your_field", [])
				if ff.is_empty():
					host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
				else:
					if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid, "ritual_mid": int(ff[0].get("mid", -1))}, false):
						host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
				continue
			if st == "tmrsk_woe":
				if not host._try_submit_scion_trigger(1, "accept", {"scion_id": sid, "woe_target": 0}, false):
					host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
				continue
			host._try_submit_scion_trigger(1, "skip", {"scion_id": sid}, false)
			continue
		if int(snap.get("current", -1)) != int(snap.get("you", -2)):
			return
		var hand: Array = snap.get("your_hand", [])
		var played_ritual := false
		for i in hand.size():
			if host._card_type(hand[i]) != "ritual":
				continue
			if host._match.can_play_ritual(1, i):
				host._try_play_ritual(1, i, false)
				played_ritual = true
			break
		if played_ritual:
			continue
		var played_noble := false
		for i in hand.size():
			if host._card_type(hand[i]) != "noble":
				continue
			if host._match.can_play_noble(1, i):
				host._try_play_noble(1, i, false)
				played_noble = true
			break
		if played_noble:
			continue
		var played_bird := false
		for i in hand.size():
			if host._card_type(hand[i]) != "bird":
				continue
			if host._match.can_play_bird(1, i):
				host._try_play_bird(1, i, false)
				played_bird = true
			break
		if played_bird:
			continue
		var played_temple := false
		for i in hand.size():
			if host._card_type(hand[i]) != "temple":
				continue
			if not host._match.can_play_temple(1, i):
				break
			var tid_t := str((hand[i] as Dictionary).get("temple_id", ""))
			var cost_t: int = _GameSnapshotUtils.temple_cost_for_id(tid_t)
			var sac_t: Array = greedy_sacrifice_mids(snap, cost_t)
			var sum_t := 0
			var fld_t: Array = snap.get("your_field", [])
			for mid in sac_t:
				for x in fld_t:
					if int(x.get("mid", 0)) == int(mid):
						sum_t += int(x.get("value", 0))
						break
			if sum_t < cost_t:
				break
			if host._match.play_temple(1, i, sac_t) == "ok":
				host._broadcast_sync(false)
				played_temple = true
			break
		if played_temple:
			continue
		if host._has_nest_action_available(snap):
			var nest_bid := -1
			for bn in snap.get("your_birds", []) as Array:
				var bnd := bn as Dictionary
				if int(bnd.get("nest_temple_mid", -1)) >= 0:
					continue
				nest_bid = int(bnd.get("mid", -1))
				break
			if nest_bid >= 0:
				var did_nest := false
				for tn in snap.get("your_temples", []) as Array:
					var tdn := tn as Dictionary
					if not host._temple_has_nest_room(snap, tdn):
						continue
					var tmid_n := int(tdn.get("mid", -1))
					if host._match.nest_bird(1, nest_bid, tmid_n) == "ok":
						host._broadcast_sync(false)
						await host.get_tree().create_timer(CPU_ACTION_SEC).timeout
						did_nest = true
					break
				if did_nest:
					snap = host._match.snapshot(1)
					continue
		var noble_field: Array = snap.get("your_nobles", [])
		for nn in noble_field:
			var nmid := int(nn.get("mid", -1))
			if not host._match.can_activate_noble(1, nmid):
				continue
			var nid2 := str(nn.get("noble_id", ""))
			var ok_act := false
			if nid2 == "bndrr_incantation":
				ok_act = host._match.apply_noble_spell_like(1, nmid, "burn", 2, [], {"mill_target": 0}) == "ok"
			elif nid2 == "wndrr_incantation":
				var hand_w: Array = snap.get("your_hand", []) as Array
				if not hand_w.is_empty():
					ok_act = host._match.apply_noble_spell_like(1, nmid, "woe", 2, [], {"woe_target": 0, "discard_hand_idx": 0}) == "ok"
			elif nid2 == "sndrr_incantation":
				var hand_s: Array = snap.get("your_hand", []) as Array
				if not hand_s.is_empty():
					ok_act = host._match.apply_noble_spell_like(1, nmid, "seek", 1, [], {"discard_hand_idx": 0}) == "ok"
			elif nid2 == "rndrr_incantation":
				ok_act = host._match.apply_noble_revive_from_crypt(1, nmid, {"revive_steps": [{"revive_skip": true}]}) == "ok"
			elif nid2 == "indrr_incantation":
				var tgt_i := 0
				var idn: int = host._match.insight_effective_n(1, 1)
				var peek2: Array = host._match.insight_peek_top_cards(tgt_i, idn)
				var perm_i: Array = []
				for ii in peek2.size():
					perm_i.append(ii)
				ok_act = host._match.activate_noble_with_insight(1, nmid, tgt_i, perm_i, []) == "ok"
			elif nid2 == "aeoiu_rituals":
				var rgc: Array = _GameSnapshotUtils.filtered_crypt_cards(_GameSnapshotUtils.your_crypt_cards_from_snap(snap), ["ritual"])
				if rgc.is_empty():
					ok_act = false
				else:
					ok_act = host._match.apply_aeoiu_ritual_from_crypt(1, nmid, 0) == "ok"
			else:
				ok_act = host._match.activate_noble(1, nmid) == "ok"
			if ok_act:
				host._broadcast_sync(false)
				await host.get_tree().create_timer(CPU_ACTION_SEC).timeout
			break
		var playable: Array[int] = []
		for j in hand.size():
			var ctype: String = host._card_type(hand[j])
			if ctype != "incantation":
				continue
			if _CardTraits.is_dethrone(hand[j]):
				var opp_nobles_a: Array = snap.get("opp_nobles", [])
				var need_d := int(hand[j].get("value", 4))
				var fld_d: Array = snap.get("your_field", [])
				var ok_lane_d: bool = host._match.has_active_ritual_lane(1, need_d)
				var tot_d := 0
				for x in fld_d:
					tot_d += int(x.get("value", 0))
				if not opp_nobles_a.is_empty() and (ok_lane_d or tot_d >= need_d):
					playable.append(j)
				continue
			var n: int = int(hand[j].get("value", 0))
			var fld: Array = snap.get("your_field", [])
			var ok_lane: bool = host._match.has_active_ritual_lane(1, n)
			var tot := 0
			for x in fld:
				tot += int(x.get("value", 0))
			if str(hand[j].get("verb", "")).to_lower() == "tears":
				var birds_c := _GameSnapshotUtils.filtered_crypt_cards(_GameSnapshotUtils.your_crypt_cards_from_snap(snap), ["bird"])
				if birds_c.is_empty():
					continue
			if ok_lane or tot >= n:
				playable.append(j)
		if playable.is_empty():
			break
		var k := randi_range(0, playable.size())
		for _t in k:
			snap = host._match.snapshot(1)
			if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
				return
			if int(snap.get("current", -1)) != int(snap.get("you", -2)):
				return
			hand = snap.get("your_hand", [])
			playable.clear()
			for j in hand.size():
				var ctype2: String = host._card_type(hand[j])
				if ctype2 != "incantation":
					continue
				if _CardTraits.is_dethrone(hand[j]):
					var opp_nobles_b: Array = snap.get("opp_nobles", [])
					var need_d2 := int(hand[j].get("value", 4))
					var fld_d2: Array = snap.get("your_field", [])
					var ok_lane_d2: bool = host._match.has_active_ritual_lane(1, need_d2)
					var tot_d2 := 0
					for x in fld_d2:
						tot_d2 += int(x.get("value", 0))
					if not opp_nobles_b.is_empty() and (ok_lane_d2 or tot_d2 >= need_d2):
						playable.append(j)
					continue
				var n2: int = int(hand[j].get("value", 0))
				var fld2: Array = snap.get("your_field", [])
				var ok2: bool = host._match.has_active_ritual_lane(1, n2)
				var tot2 := 0
				for x in fld2:
					tot2 += int(x.get("value", 0))
				if str(hand[j].get("verb", "")).to_lower() == "tears":
					var birds_c2 := _GameSnapshotUtils.filtered_crypt_cards(_GameSnapshotUtils.your_crypt_cards_from_snap(snap), ["bird"])
					if birds_c2.is_empty():
						continue
				if ok2 or tot2 >= n2:
					playable.append(j)
			if playable.is_empty():
				break
			var pick := playable[randi_range(0, playable.size() - 1)]
			if _CardTraits.is_dethrone(hand[pick]):
				var opp_nobles: Array = snap.get("opp_nobles", [])
				if not opp_nobles.is_empty():
					var tmid := int(opp_nobles[0].get("mid", -1))
					var dn := int(hand[pick].get("value", 4))
					var dsac: Array = []
					if not host._match.has_active_ritual_lane(1, dn):
						dsac = greedy_sacrifice_mids(snap, dn)
					host._try_play_dethrone(1, pick, [tmid], dsac, false)
					await host.get_tree().create_timer(CPU_ACTION_SEC).timeout
					continue
			var nv: int = int(hand[pick].get("value", 0))
			var sac: Array = []
			if not host._match.has_active_ritual_lane(1, nv):
				sac = greedy_sacrifice_mids(snap, nv)
			var wm: Array = []
			var vrb := str(hand[pick].get("verb", "")).to_lower()
			if vrb == "wrath":
				var opp_f: Array = snap.get("opp_field", [])
				var wn := mini(host._match.effective_wrath_destroy_count(1, nv), opp_f.size())
				if wn > 0:
					wm = greedy_wrath_mids(opp_f, wn)
			var ictx := {}
			match vrb:
				"seek":
					ictx = {}
				"burn":
					ictx = {"mill_target": 0}
				"woe":
					ictx = {"woe_target": 0}
				"insight":
					var tgt0 := 0
					var idnv: int = host._match.insight_effective_n(1, nv)
					var pk: Array = host._match.insight_peek_top_cards(tgt0, idnv)
					var prm: Array = []
					for ii in pk.size():
						prm.append(ii)
					ictx = {"insight_target": tgt0, "insight_top": prm, "insight_bottom": []}
				"revive":
					ictx = {"revive_steps": [{"revive_skip": true}]}
				"tears":
					ictx = {"tears_crypt_idx": 0}
				_:
					ictx = {}
			host._try_play_inc(1, pick, sac, wm, ictx, false)
			await host.get_tree().create_timer(CPU_ACTION_SEC).timeout
		snap = host._match.snapshot(1)
		if bool(snap.get("woe_pending_you_respond", false)) or bool(snap.get("scion_pending_you_respond", false)):
			continue
		if not bool(snap.get("your_bird_fight_used", false)):
			var your_birds: Array = snap.get("your_birds", []) as Array
			var opp_birds: Array = snap.get("opp_birds", []) as Array
			var att_mid := -1
			for yb in your_birds:
				var ybd := yb as Dictionary
				if int(ybd.get("nest_temple_mid", -1)) >= 0:
					continue
				att_mid = int(ybd.get("mid", -1))
				break
			var def_mid := -1
			var def_power := 0
			for ob in opp_birds:
				var obd := ob as Dictionary
				if int(obd.get("nest_temple_mid", -1)) >= 0:
					continue
				def_mid = int(obd.get("mid", -1))
				def_power = int(obd.get("power", 0))
				break
			if att_mid >= 0 and def_mid >= 0:
				var assign := {att_mid: def_power}
				host._try_resolve_bird_fight(1, [att_mid], def_mid, assign, false)
				await host.get_tree().create_timer(CPU_ACTION_SEC).timeout
				snap = host._match.snapshot(1)
				if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
					return
				if int(snap.get("current", -1)) != int(snap.get("you", -2)):
					return
		break
	snap = host._match.snapshot(1)
	if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return
	if int(snap.get("current", -1)) != int(snap.get("you", -2)):
		return
	if not bool(snap.get("discard_draw_used", true)) and randf() < 0.35:
		var harr: Array = snap.get("your_hand", [])
		var hs := harr.size()
		if hs > 0:
			host._try_discard_draw(1, randi_range(0, hs - 1), false)
			await host.get_tree().create_timer(CPU_ACTION_SEC).timeout
	snap = host._match.snapshot(1)
	if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return
	if int(snap.get("current", -1)) != int(snap.get("you", -2)):
		return
	var disc := ai_end_discards_from_snap(snap)
	host._try_end_turn(1, disc, true)


func run_mulligan_step(host: Node) -> void:
	if host._match == null:
		return
	var snap: Dictionary = host._match.snapshot(1)
	if not bool(snap.get("mulligan_active", false)):
		return
	if int(snap.get("current", -1)) != 1:
		return
	var bottom_needed := int(snap.get("your_mulligan_bottom_needed", 0))
	if bottom_needed > 0:
		var hand: Array = snap.get("your_hand", [])
		if hand.is_empty():
			return
		host._try_mulligan_bottom(1, randi_range(0, hand.size() - 1), true)
		return
	var can_take := bool(snap.get("your_can_mulligan", false))
	var take := false
	if can_take:
		var hand_now: Array = snap.get("your_hand", [])
		var rituals := 0
		for c in hand_now:
			if host._card_type(c) == "ritual":
				rituals += 1
		take = rituals <= 1
	host._try_choose_mulligan(1, take, true)

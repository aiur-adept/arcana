extends Control

const IncludedDecks = preload("res://included_decks.gd")
const CardPreviewPresenter = preload("res://card_preview_presenter.gd")

class InsightDnDSlot extends Panel:
	var slot_index: int = 0
	var game: Control
	func _get_drag_data(_at_position: Vector2) -> Variant:
		var px := ColorRect.new()
		px.custom_minimum_size = Vector2(50.0 * CARD_SCALE, RITUAL_CARD_H)
		px.color = Color(0.25, 0.4, 0.65, 0.92)
		set_drag_preview(px)
		return {"insight_slot": slot_index}
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return game != null and typeof(data) == TYPE_DICTIONARY and data.has("insight_slot")
	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if game != null and typeof(data) == TYPE_DICTIONARY:
			game._insight_swap_slots(int(data["insight_slot"]), slot_index)


## Normal play: 1p vs CPU in one process (mock client/server — no second executable).
## Real PvP: set USE_NETWORK_MULTIPLAYER = true, or pass --arcana-network-host on the command line.

const USE_NETWORK_MULTIPLAYER := false
const PORT_MIN := 17777
const PORT_MAX := 17799
const DEFAULT_DECK_PATH := "user://decks/default_deck.json"
const SELECTED_DECK_PATH_FILE := "user://selected_deck_path.txt"
const CPU_ACTION_SEC := 1.618
const CARD_SCALE := 1.618
const RITUAL_CARD_ASPECT := 2.5 / 3.5
const RITUAL_CARD_H := 72.0 * CARD_SCALE
const HAND_CARD_W := 72.0 * CARD_SCALE
const HAND_CARD_H := 102.0 * CARD_SCALE
var _bound_port: int = PORT_MIN
var _deck_path: String = DEFAULT_DECK_PATH

@onready var status_label: Label = %StatusLabel
@onready var log_label: RichTextLabel = %LogLabel
@onready var hand_row: HBoxContainer = %HandRow
@onready var end_turn_button: Button = %EndTurnButton
@onready var discard_draw_button: Button = %DiscardDrawButton
@onready var field_you_cards: HBoxContainer = %FieldYouCards
@onready var field_opp_cards: HBoxContainer = %FieldOppCards
@onready var you_stats_label: Label = %YouStatsLabel
@onready var opp_stats_label: Label = %OppStatsLabel
@onready var sacrifice_row: HBoxContainer = %SacrificeRow
@onready var sacrifice_hint: Label = %SacrificeHint
@onready var sacrifice_confirm_button: Button = %SacrificeConfirmButton
@onready var sacrifice_cancel_button: Button = %SacrificeCancelButton
@onready var quit_to_menu_button: Button = %QuitToMenuButton
@onready var quit_confirm_dialog: ConfirmationDialog = %QuitConfirmDialog

var _host: bool = false
var _my_player: int = 0
var _last_snap: Dictionary = {}
var _match: ArcanaMatchState
var _mode_discard_draw: bool = false
var _selecting_end_discard: bool = false
var _end_discard_needed: int = 0
var _end_discard_picked: Dictionary = {}
const INC_PICK_NONE := 0
const INC_PICK_SAC := 1
const INC_PICK_WRATH := 2
const INC_PICK_DETHRONE := 3
const INC_PICK_BURN_TGT := 4
const INC_PICK_WOE_TGT := 5
const INC_PICK_WOE_SELF := 6
const INC_PICK_REVIVE := 7
const INC_PICK_YTTR := 8
var _sacrifice_selecting: bool = false
var _inc_pick_phase: int = INC_PICK_NONE
var _pending_inc_hand_idx: int = -1
var _pending_inc_n: int = 0
var _sacrifice_need: int = 0
var _pending_wrath_need: int = 0
var _pending_dethrone_hand_idx: int = -1
var _dethrone_selected_mid: int = -1
var _sacrifice_selected_mids: Dictionary = {}
var _wrath_selected_mids: Dictionary = {}
var _locked_sacrifice_mids: Array = []
var _effect_sac: Array = []

var _insight_open: bool = false
var _insight_hand_idx: int = -1
var _insight_noble_mid: int = -1
var _insight_n: int = 0
var _insight_sac: Array = []
var _insight_target: int = 0
var _insight_order: Array = []
var _insight_overlay: Control
var _insight_cards_row: HBoxContainer
var _insight_hint_label: Label
var _insight_btn_confirm: Button
var _insight_btn_cancel: Button
var _insight_btn_yours: Button
var _insight_btn_opps: Button
var _insight_revive_crypt_idx: int = -1

var _burn_woe_overlay: Control
var _burn_woe_title: Label
var _burn_woe_hint: Label
var _tgt_left_btn: Button
var _tgt_right_btn: Button
var _burn_woe_confirm: Button
var _burn_woe_cancel: Button
var _burn_woe_mode: String = ""
var _pending_mill_target: int = -1
var _pending_woe_target: int = -1
var _woe_self_picking: bool = false
var _woe_self_need: int = 0
var _woe_self_picked: Dictionary = {}
var _revive_overlay: Control
var _revive_crypt_row: VBoxContainer
var _revive_skip_btn: Button
var _revive_cancel_btn: Button
var _revive_pick_phase: bool = false
var _nested_revive_crypt_idx: int = -1
var _nested_revive_value: int = 0
var _wrath_is_revive_nested: bool = false
var _noble_spell_mid: int = -1
var _pending_noble_woe_mid: int = -1
var _revive_ui_for_noble_mid: int = -1

var _yytzr_pending_first_ctx: Dictionary = {}
var _yytzr_first_step: Dictionary = {}
var _yytzr_waits_second_crypt: bool = false
var _yytzr_extra_sac_mids: Array = []

var _aeoiu_overlay: Control
var _aeoiu_crypt_row: VBoxContainer
var _aeoiu_noble_mid: int = -1

var _hover_preview: Dictionary = {}
var _game_end_overlay: Control
var _game_end_modal: PanelContainer
var _game_end_title: Label
var _game_end_body: Label
var _game_end_play_again: Button
var _game_end_main_menu: Button
var _end_discard_modal: PanelContainer
var _end_discard_label: Label
var _end_discard_confirm_button: Button
var _mulligan_bar: PanelContainer
var _mulligan_label: Label
var _mulligan_keep_button: Button
var _mulligan_take_button: Button


func _is_network_pvp() -> bool:
	if USE_NETWORK_MULTIPLAYER:
		return true
	for a in OS.get_cmdline_args():
		if a == "--arcana-network-host" or a == "--pvp-host":
			return true
	return false


func _player_has_noble_id(snap: Dictionary, noble_id: String) -> bool:
	var nl: Array = snap.get("your_nobles", []) as Array
	for n in nl:
		if str(n.get("noble_id", "")) == noble_id:
			return true
	return false


func _insight_depth_for(snap: Dictionary, base: int) -> int:
	return base + (1 if _player_has_noble_id(snap, "xytzr_emanation") else 0)


func _wrath_effective_destroy_count(snap: Dictionary, n: int) -> int:
	var b := _wrath_destroy_count(n)
	if b <= 0:
		return 0
	if _player_has_noble_id(snap, "zytzr_annihilation"):
		return b + 1
	return b


func _woe_discard_count_ui(snap: Dictionary, base_val: int, victim_is_you: bool) -> int:
	var hand_sz: int
	if victim_is_you:
		hand_sz = (snap.get("your_hand", []) as Array).size()
	else:
		hand_sz = int(snap.get("opp_hand", 0))
	var extra := 1 if _player_has_noble_id(snap, "zytzr_annihilation") else 0
	return mini(base_val + extra, hand_sz)


func _yytzr_should_offer_bonus(ctx: Dictionary) -> bool:
	if _yytzr_waits_second_crypt:
		return false
	if _pending_inc_n != 1:
		return false
	if not _player_has_noble_id(_last_snap, "yytzr_occultation"):
		return false
	var st: Array = ctx.get("revive_steps", []) as Array
	if st.size() != 1:
		return false
	return not bool((st[0] as Dictionary).get("revive_skip", false))


func _yytzr_clear_bonus_state() -> void:
	_yytzr_waits_second_crypt = false
	_yytzr_first_step = {}
	_yytzr_extra_sac_mids.clear()
	_yytzr_pending_first_ctx = {}


func _ready() -> void:
	set_multiplayer_authority(1)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.clip_text = true
	_build_insight_overlay()
	_build_burn_woe_revive_overlays()
	_build_hover_preview_panel()
	_build_game_end_modal()
	_build_end_discard_modal()
	_build_mulligan_bar()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	discard_draw_button.pressed.connect(_on_discard_draw_pressed)
	sacrifice_confirm_button.pressed.connect(_on_sacrifice_confirm_pressed)
	sacrifice_cancel_button.pressed.connect(_on_sacrifice_cancel_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	quit_confirm_dialog.confirmed.connect(_on_quit_to_menu_confirmed)
	if _is_network_pvp():
		_host = true
		_my_player = 0
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.connected_to_server.connect(_on_connected_ok)
		var peer: ENetMultiplayerPeer = null
		for p in range(PORT_MIN, PORT_MAX + 1):
			var attempt := ENetMultiplayerPeer.new()
			if attempt.create_server(p) == OK:
				_bound_port = p
				peer = attempt
				break
		if peer == null:
			status_label.text = "Could not bind server (UDP %d–%d)." % [PORT_MIN, PORT_MAX]
			return
		multiplayer.multiplayer_peer = peer
		status_label.text = "Hosting PvP on port %d — waiting for opponent…" % _bound_port
		return
	_host = true
	_my_player = 0
	status_label.text = "You vs CPU — shuffle up."
	_start_match()


func _arcana_port_from_cmd() -> int:
	for a in OS.get_cmdline_args():
		if a.begins_with("--arcana-port="):
			var v := int(a.get_slice("=", 1))
			if v > 0 and v < 65536:
				return v
	return PORT_MIN


func _connect_client_to_host() -> void:
	var port := _arcana_port_from_cmd()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", port) != OK:
		status_label.text = "Could not create client to 127.0.0.1:%d." % port
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_ok)
	status_label.text = "Connecting to 127.0.0.1:%d…" % port


func _on_connected_ok() -> void:
	if _is_network_pvp() and not multiplayer.is_server():
		status_label.text = "Connected to host."


func _on_peer_connected(id: int) -> void:
	if not _host or not _is_network_pvp():
		return
	if id != 0:
		status_label.text = "Peer %d joined. Shuffling…" % id
		_start_match()


func _start_match() -> void:
	var cards := _load_deck_cards()
	if cards.is_empty():
		status_label.text = "No deck at %s — use deck editor first." % _deck_path
		return
	_hide_game_end_modal()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var p0_first := rng.randi_range(0, 1) == 0
	_match = ArcanaMatchState.new(cards.duplicate(true), cards.duplicate(true), p0_first, rng)
	_broadcast_sync()


func _build_insight_overlay() -> void:
	_insight_overlay = Control.new()
	_insight_overlay.name = "InsightOverlay"
	_insight_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_insight_overlay.visible = false
	_insight_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_insight_overlay.z_index = 100
	add_child(_insight_overlay)
	var back := ColorRect.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0, 0, 0, 0.58)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	_insight_overlay.add_child(back)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_insight_overlay.add_child(cc)
	var inner := VBoxContainer.new()
	cc.add_child(inner)
	var title := Label.new()
	title.text = "Insight — reorder top of deck"
	inner.add_child(title)
	var h := HBoxContainer.new()
	_insight_btn_yours = Button.new()
	_insight_btn_yours.text = "Your deck"
	_insight_btn_opps = Button.new()
	_insight_btn_opps.text = "Opponent deck"
	h.add_child(_insight_btn_yours)
	h.add_child(_insight_btn_opps)
	inner.add_child(h)
	_insight_hint_label = Label.new()
	_insight_hint_label.custom_minimum_size = Vector2(420, 0)
	inner.add_child(_insight_hint_label)
	_insight_cards_row = HBoxContainer.new()
	_insight_cards_row.add_theme_constant_override("separation", 8)
	inner.add_child(_insight_cards_row)
	var row2 := HBoxContainer.new()
	_insight_btn_confirm = Button.new()
	_insight_btn_confirm.text = "Confirm order"
	_insight_btn_cancel = Button.new()
	_insight_btn_cancel.text = "Cancel"
	row2.add_child(_insight_btn_confirm)
	row2.add_child(_insight_btn_cancel)
	inner.add_child(row2)
	_insight_btn_yours.pressed.connect(_on_insight_target_yours)
	_insight_btn_opps.pressed.connect(_on_insight_target_opps)
	_insight_btn_confirm.pressed.connect(_on_insight_confirm_pressed)
	_insight_btn_cancel.pressed.connect(_on_insight_cancel_pressed)


func _build_burn_woe_revive_overlays() -> void:
	_burn_woe_overlay = Control.new()
	_burn_woe_overlay.name = "BurnWoeOverlay"
	_burn_woe_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_burn_woe_overlay.visible = false
	_burn_woe_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_burn_woe_overlay.z_index = 99
	add_child(_burn_woe_overlay)
	var back := ColorRect.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0, 0, 0, 0.55)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	_burn_woe_overlay.add_child(back)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_burn_woe_overlay.add_child(cc)
	var inner := VBoxContainer.new()
	cc.add_child(inner)
	_burn_woe_title = Label.new()
	inner.add_child(_burn_woe_title)
	var h := HBoxContainer.new()
	_tgt_left_btn = Button.new()
	_tgt_right_btn = Button.new()
	h.add_child(_tgt_left_btn)
	h.add_child(_tgt_right_btn)
	inner.add_child(h)
	_burn_woe_hint = Label.new()
	_burn_woe_hint.custom_minimum_size = Vector2(400, 0)
	inner.add_child(_burn_woe_hint)
	var row2 := HBoxContainer.new()
	_burn_woe_confirm = Button.new()
	_burn_woe_confirm.text = "Confirm"
	_burn_woe_cancel = Button.new()
	_burn_woe_cancel.text = "Cancel"
	row2.add_child(_burn_woe_confirm)
	row2.add_child(_burn_woe_cancel)
	inner.add_child(row2)
	_tgt_left_btn.pressed.connect(_on_burn_woe_left_pressed)
	_tgt_right_btn.pressed.connect(_on_burn_woe_right_pressed)
	_burn_woe_confirm.pressed.connect(_on_burn_woe_confirm_pressed)
	_burn_woe_cancel.pressed.connect(_on_burn_woe_cancel_pressed)
	_revive_overlay = Control.new()
	_revive_overlay.name = "ReviveOverlay"
	_revive_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_revive_overlay.visible = false
	_revive_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_revive_overlay.z_index = 98
	add_child(_revive_overlay)
	var back2 := ColorRect.new()
	back2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back2.color = Color(0, 0, 0, 0.55)
	_revive_overlay.add_child(back2)
	var cc2 := CenterContainer.new()
	cc2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_revive_overlay.add_child(cc2)
	var inner2 := VBoxContainer.new()
	cc2.add_child(inner2)
	var rt := Label.new()
	rt.text = "Revive — cast from crypt or skip"
	inner2.add_child(rt)
	_revive_crypt_row = VBoxContainer.new()
	inner2.add_child(_revive_crypt_row)
	var row3 := HBoxContainer.new()
	_revive_skip_btn = Button.new()
	_revive_skip_btn.text = "Skip (no effect)"
	row3.add_child(_revive_skip_btn)
	_revive_cancel_btn = Button.new()
	_revive_cancel_btn.text = "Cancel"
	row3.add_child(_revive_cancel_btn)
	inner2.add_child(row3)
	_revive_skip_btn.pressed.connect(_on_revive_skip_pressed)
	_revive_cancel_btn.pressed.connect(_on_revive_cancel_pressed)
	_aeoiu_overlay = Control.new()
	_aeoiu_overlay.name = "AeoiuOverlay"
	_aeoiu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aeoiu_overlay.visible = false
	_aeoiu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_aeoiu_overlay.z_index = 97
	add_child(_aeoiu_overlay)
	var back_a := ColorRect.new()
	back_a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back_a.color = Color(0, 0, 0, 0.55)
	_aeoiu_overlay.add_child(back_a)
	var cca := CenterContainer.new()
	cca.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aeoiu_overlay.add_child(cca)
	var inner_a := VBoxContainer.new()
	cca.add_child(inner_a)
	var lae := Label.new()
	lae.text = "Aeoiu — choose a ritual from your crypt"
	inner_a.add_child(lae)
	_aeoiu_crypt_row = VBoxContainer.new()
	inner_a.add_child(_aeoiu_crypt_row)
	var ae_row := HBoxContainer.new()
	var ae_cancel := Button.new()
	ae_cancel.text = "Cancel"
	ae_row.add_child(ae_cancel)
	inner_a.add_child(ae_row)
	ae_cancel.pressed.connect(_on_aeoiu_cancel_pressed)


func _clear_burn_woe_overlay() -> void:
	if _burn_woe_overlay:
		_burn_woe_overlay.visible = false
	_burn_woe_mode = ""
	_inc_pick_phase = INC_PICK_NONE


func _clear_woe_self_pick() -> void:
	_woe_self_picking = false
	_woe_self_need = 0
	_woe_self_picked.clear()


func _clear_revive_overlay() -> void:
	if _revive_overlay:
		_revive_overlay.visible = false
	_revive_pick_phase = false
	for c in _revive_crypt_row.get_children():
		c.queue_free()


func _begin_burn_target_ui(hand_idx: int, n: int, sac_mids: Array) -> void:
	_pending_inc_hand_idx = hand_idx
	_pending_inc_n = n
	_effect_sac = sac_mids.duplicate()
	_burn_woe_mode = "burn"
	var y := int(_last_snap.get("you", 0))
	_pending_mill_target = y
	_burn_woe_title.text = "Burn — choose which deck to mill"
	_tgt_left_btn.text = "Your deck"
	_tgt_right_btn.text = "Opponent deck"
	_burn_woe_hint.text = "Then confirm."
	_burn_woe_overlay.visible = true
	_inc_pick_phase = INC_PICK_BURN_TGT
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _begin_woe_target_ui(hand_idx: int, n: int, sac_mids: Array) -> void:
	_pending_inc_hand_idx = hand_idx
	_pending_inc_n = n
	_effect_sac = sac_mids.duplicate()
	_burn_woe_mode = "woe"
	var y := int(_last_snap.get("you", 0))
	_pending_woe_target = y
	_burn_woe_title.text = "Woe — who discards?"
	_tgt_left_btn.text = "You"
	_tgt_right_btn.text = "Opponent"
	_burn_woe_hint.text = "If you discard, you will choose cards from your hand next."
	_burn_woe_overlay.visible = true
	_inc_pick_phase = INC_PICK_WOE_TGT
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _on_burn_woe_left_pressed() -> void:
	var y := int(_last_snap.get("you", 0))
	if _burn_woe_mode == "burn" or _burn_woe_mode == "noble_burn" or _burn_woe_mode == "revive_burn":
		_pending_mill_target = y
	elif _burn_woe_mode == "woe" or _burn_woe_mode == "noble_woe" or _burn_woe_mode == "revive_woe":
		_pending_woe_target = y


func _on_burn_woe_right_pressed() -> void:
	var y := int(_last_snap.get("you", 0))
	if _burn_woe_mode == "burn" or _burn_woe_mode == "noble_burn" or _burn_woe_mode == "revive_burn":
		_pending_mill_target = 1 - y
	elif _burn_woe_mode == "woe" or _burn_woe_mode == "noble_woe" or _burn_woe_mode == "revive_woe":
		_pending_woe_target = 1 - y


func _on_burn_woe_confirm_pressed() -> void:
	if _burn_woe_mode == "noble_burn":
		var ctxb := {"mill_target": _pending_mill_target}
		if _is_network_client():
			submit_noble_spell_like.rpc_id(1, _noble_spell_mid, "burn", 1, [], ctxb)
		else:
			if _match != null:
				_match.apply_noble_spell_like(_my_player_for_action(), _noble_spell_mid, "burn", 1, [], ctxb)
		_noble_spell_mid = -1
		_clear_incantation_flow_ui()
		_broadcast_sync(true)
		return
	if _burn_woe_mode == "noble_woe":
		var yb := int(_last_snap.get("you", 0))
		if _pending_woe_target == yb:
			_clear_burn_woe_overlay()
			_pending_noble_woe_mid = _noble_spell_mid
			_woe_self_picking = true
			_woe_self_need = _woe_discard_count_ui(_last_snap, 1, true)
			_woe_self_picked.clear()
			_inc_pick_phase = INC_PICK_WOE_SELF
			status_label.text = "Wndrr: tap %d card(s) to discard." % _woe_self_need
		else:
			var ctxw := {"woe_target": _pending_woe_target}
			if _is_network_client():
				submit_noble_spell_like.rpc_id(1, _noble_spell_mid, "woe", 1, [], ctxw)
			else:
				if _match != null:
					_match.apply_noble_spell_like(_my_player_for_action(), _noble_spell_mid, "woe", 1, [], ctxw)
			_noble_spell_mid = -1
			_clear_incantation_flow_ui()
			_broadcast_sync(true)
		return
	if _burn_woe_mode == "burn":
		var ctx := {"mill_target": _pending_mill_target}
		_submit_inc_play_full(_effect_sac, [], ctx)
	elif _burn_woe_mode == "revive_burn":
		var steps := [{"revive_skip": false, "revive_crypt_idx": _nested_revive_crypt_idx, "nested": {"mill_target": _pending_mill_target}}]
		_finalize_revive_cast({"revive_steps": steps})
	elif _burn_woe_mode == "woe":
		var y := int(_last_snap.get("you", 0))
		if _pending_woe_target == y:
			_clear_burn_woe_overlay()
			_woe_self_picking = true
			_woe_self_need = _woe_discard_count_ui(_last_snap, _pending_inc_n, true)
			_woe_self_picked.clear()
			_inc_pick_phase = INC_PICK_WOE_SELF
			status_label.text = "Woe: tap %d card(s) in your hand to discard." % _woe_self_need
		else:
			var ctx2 := {"woe_target": _pending_woe_target}
			_submit_inc_play_full(_effect_sac, [], ctx2)
	elif _burn_woe_mode == "revive_woe":
		var y2 := int(_last_snap.get("you", 0))
		if _pending_woe_target == y2:
			_clear_burn_woe_overlay()
			_woe_self_picking = true
			_woe_self_need = _woe_discard_count_ui(_last_snap, _nested_revive_value, true)
			_woe_self_picked.clear()
			_inc_pick_phase = INC_PICK_WOE_SELF
			_burn_woe_mode = "revive_woe_self"
			status_label.text = "Revive Woe: tap %d card(s) to discard." % _woe_self_need
		else:
			var ctx3 := {"revive_steps": [{"revive_skip": false, "revive_crypt_idx": _nested_revive_crypt_idx, "nested": {"woe_target": _pending_woe_target}}]}
			_finalize_revive_cast(ctx3)


func _on_burn_woe_cancel_pressed() -> void:
	_clear_incantation_flow_ui()
	if not _last_snap.is_empty():
		_apply_snap(_last_snap)


func _begin_revive_hand_ui(hand_idx: int, n: int, sac_mids: Array, for_noble_mid: int = -1) -> void:
	_revive_ui_for_noble_mid = for_noble_mid
	_pending_inc_hand_idx = hand_idx
	_pending_inc_n = n
	_effect_sac = sac_mids.duplicate()
	_revive_pick_phase = true
	for c in _revive_crypt_row.get_children():
		c.queue_free()
	var crypt: Array = _last_snap.get("your_inc_discard_cards", []) as Array
	var idx := 0
	for card in crypt:
		if _card_type(card) != "incantation":
			idx += 1
			continue
		var b := Button.new()
		var v := str(card.get("verb", ""))
		var vv := int(card.get("value", 0))
		b.text = "%s %d (crypt #%d)" % [v, vv, idx]
		var capture := idx
		b.pressed.connect(func() -> void:
			_on_revive_crypt_chosen(capture)
		)
		_revive_crypt_row.add_child(b)
		idx += 1
	_revive_overlay.visible = true
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _on_revive_skip_pressed() -> void:
	if _revive_ui_for_noble_mid >= 0:
		var nm := _revive_ui_for_noble_mid
		_revive_ui_for_noble_mid = -1
		var ctxs := {"revive_steps": [{"revive_skip": true}]}
		if _is_network_client():
			submit_noble_revive.rpc_id(1, nm, ctxs)
		else:
			if _match != null:
				_match.apply_noble_revive_from_crypt(_my_player_for_action(), nm, ctxs)
		_clear_incantation_flow_ui()
		_broadcast_sync(true)
		return
	var steps := [{"revive_skip": true}]
	var ctx := {"revive_steps": steps}
	if _yytzr_waits_second_crypt:
		_finalize_revive_cast(ctx)
	else:
		_submit_inc_play_full(_effect_sac, [], ctx)


func _on_revive_cancel_pressed() -> void:
	if _yytzr_waits_second_crypt:
		_yytzr_clear_bonus_state()
	_clear_incantation_flow_ui()
	if not _last_snap.is_empty():
		_apply_snap(_last_snap)


func _on_revive_crypt_chosen(crypt_idx: int) -> void:
	var idisc: Array = _last_snap.get("your_inc_discard_cards", []) as Array
	if crypt_idx < 0 or crypt_idx >= idisc.size():
		return
	var card: Dictionary = idisc[crypt_idx]
	var v := str(card.get("verb", "")).to_lower()
	var val := int(card.get("value", 0))
	_nested_revive_crypt_idx = crypt_idx
	_nested_revive_value = val
	_clear_revive_overlay()
	if v == "seek":
		var steps := [{"revive_skip": false, "revive_crypt_idx": crypt_idx, "nested": {}}]
		_finalize_revive_cast({"revive_steps": steps})
	elif v == "burn":
		_burn_woe_mode = "revive_burn"
		_pending_mill_target = int(_last_snap.get("you", 0))
		_burn_woe_title.text = "Revive: Burn — choose deck"
		_tgt_left_btn.text = "Your deck"
		_tgt_right_btn.text = "Opponent deck"
		_burn_woe_hint.text = "Confirm to cast from crypt."
		_burn_woe_overlay.visible = true
		_inc_pick_phase = INC_PICK_BURN_TGT
	elif v == "woe":
		_burn_woe_mode = "revive_woe"
		_pending_woe_target = int(_last_snap.get("you", 0))
		_burn_woe_title.text = "Revive: Woe — who discards?"
		_tgt_left_btn.text = "You"
		_tgt_right_btn.text = "Opponent"
		_burn_woe_overlay.visible = true
		_inc_pick_phase = INC_PICK_WOE_TGT
	elif v == "insight":
		_begin_insight_ui(_pending_inc_hand_idx, _insight_depth_for(_last_snap, val), _effect_sac, -1, crypt_idx)
	elif v == "wrath":
		var wneed := mini(_wrath_effective_destroy_count(_last_snap, val), (_last_snap.get("opp_field", []) as Array).size())
		if wneed == 0:
			var steps2 := [{"revive_skip": false, "revive_crypt_idx": crypt_idx, "nested": {"wrath_mids": []}}]
			_finalize_revive_cast({"revive_steps": steps2})
		else:
			_enter_wrath_only_mode(_pending_inc_hand_idx, val, wneed, "Revive Wrath", true)
	else:
		status_label.text = "Cannot revive that card type from UI."


func _finalize_revive_cast(ctx: Dictionary) -> void:
	if _revive_ui_for_noble_mid >= 0:
		var nm := _revive_ui_for_noble_mid
		_revive_ui_for_noble_mid = -1
		if _is_network_client():
			submit_noble_revive.rpc_id(1, nm, ctx)
		else:
			if _match != null:
				_match.apply_noble_revive_from_crypt(_my_player_for_action(), nm, ctx)
		_clear_incantation_flow_ui()
		_broadcast_sync(true)
	else:
		if _yytzr_waits_second_crypt:
			var steps2: Array = ctx.get("revive_steps", []) as Array
			if steps2.is_empty() or bool((steps2[0] as Dictionary).get("revive_skip", false)):
				var subf := _yytzr_pending_first_ctx.duplicate(true)
				_yytzr_clear_bonus_state()
				_submit_inc_play_full(_effect_sac, [], subf)
				return
			var s2: Dictionary = (steps2[0] as Dictionary).duplicate(true)
			var merged := {
				"revive_steps": [_yytzr_first_step.duplicate(true), s2],
				"yytzr_extra_sac_mids": _yytzr_extra_sac_mids.duplicate()
			}
			_yytzr_clear_bonus_state()
			_submit_inc_play_full(_effect_sac, [], merged)
			return
		if _yytzr_should_offer_bonus(ctx):
			_yytzr_pending_first_ctx = ctx.duplicate(true)
			_start_yytzr_bonus_sacrifice_ui()
			return
		_submit_inc_play_full(_effect_sac, [], ctx)


func _finalize_revive_wrath_submit(wrath_mids: Array) -> void:
	var ctxw := {"revive_steps": [{"revive_skip": false, "revive_crypt_idx": _nested_revive_crypt_idx, "nested": {"wrath_mids": wrath_mids}}]}
	_finalize_revive_cast(ctxw)


func _build_hover_preview_panel() -> void:
	_hover_preview = CardPreviewPresenter.build_preview_panel(self, {
		"mode": "corner",
		"card_scale": CARD_SCALE,
		"card_aspect": RITUAL_CARD_ASPECT
	})


func _show_card_hover_preview(card: Dictionary) -> void:
	CardPreviewPresenter.show_preview(_hover_preview, card)


func _hide_card_hover_preview() -> void:
	CardPreviewPresenter.hide_preview(_hover_preview)


func _load_deck_cards() -> Array:
	_deck_path = _resolve_selected_deck_path()
	var data: Dictionary = {}
	if IncludedDecks.is_token(_deck_path):
		data = IncludedDecks.payload_for_slug(IncludedDecks.slug_from_token(_deck_path))
		if data.is_empty():
			return []
	else:
		if not FileAccess.file_exists(_deck_path):
			return []
		var f := FileAccess.open(_deck_path, FileAccess.READ)
		if f == null:
			return []
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			return []
		data = parsed as Dictionary
	var cards: Array = data.get("cards", [])
	var out: Array = []
	for c in cards:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cd: Dictionary = (c as Dictionary).duplicate(true)
		if _card_type(cd) == "dethrone":
			var dv := int(cd.get("value", 4))
			if dv != 4:
				continue
			cd["value"] = 4
		elif _card_type(cd) == "incantation" and str(cd.get("verb", "")).to_lower() == "wrath":
			cd["value"] = 4
		out.append(cd)
	return out


func _resolve_selected_deck_path() -> String:
	if not FileAccess.file_exists(SELECTED_DECK_PATH_FILE):
		return IncludedDecks.default_play_path()
	var f := FileAccess.open(SELECTED_DECK_PATH_FILE, FileAccess.READ)
	if f == null:
		return IncludedDecks.default_play_path()
	var selected := f.get_as_text().strip_edges()
	if selected.is_empty():
		return IncludedDecks.default_play_path()
	return selected


func _peer_to_player(peer_id: int) -> int:
	return 0 if peer_id == 1 else 1


func _sender_peer() -> int:
	var sid := multiplayer.get_remote_sender_id()
	if sid == 0:
		return multiplayer.get_unique_id()
	return sid


func _is_network_client() -> bool:
	return _is_network_pvp() and multiplayer.multiplayer_peer != null and not multiplayer.is_server()


func _broadcast_sync(trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	_apply_snap(_match.snapshot(0))
	if _is_network_pvp():
		for peer_id in multiplayer.get_peers():
			sync_state.rpc_id(peer_id, _match.snapshot(1))
	if trigger_cpu_check and not _is_network_pvp():
		_after_sync_local_cpu()


func _after_sync_local_cpu() -> void:
	if _match == null:
		return
	var s0 := _match.snapshot(0)
	var s1 := _match.snapshot(1)
	if int(s0.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return
	if bool(s1.get("woe_pending_you_respond", false)):
		call_deferred("_run_cpu_turn")
		return
	if bool(s0.get("mulligan_active", false)):
		if int(s0.get("current", -1)) == 1:
			call_deferred("_run_cpu_mulligan_step")
		return
	if int(s0.get("current", -1)) != 1:
		return
	call_deferred("_run_cpu_turn")


@rpc("authority", "reliable")
func sync_state(snap: Dictionary) -> void:
	_apply_snap(snap)


func _apply_snap(snap: Dictionary) -> void:
	_last_snap = snap
	if snap.is_empty():
		return
	_hide_card_hover_preview()
	if _insight_open:
		_clear_insight_ui()
	if _sacrifice_selecting:
		_clear_sacrifice_mode()
	var yp: int = int(snap.get("your_power", 0))
	var op: int = int(snap.get("opp_power", 0))
	var your_hand: Array = snap.get("your_hand", []) as Array
	var your_hand_n := your_hand.size()
	var opp_hand_n := int(snap.get("opp_hand", 0))
	var your_deck_n := int(snap.get("your_deck", 0))
	var opp_deck_n := int(snap.get("opp_deck", 0))
	you_stats_label.text = "You\nPower: %d\nHand: %d\nDeck: %d" % [yp, your_hand_n, your_deck_n]
	opp_stats_label.text = "Opponent\nPower: %d\nHand: %d\nDeck: %d" % [op, opp_hand_n, opp_deck_n]
	_rebuild_ritual_field(field_you_cards, snap.get("your_field", []), true)
	_rebuild_ritual_field(field_opp_cards, snap.get("opp_field", []), false)
	var logs: Array = snap.get("log", [])
	var tail := ""
	for i in mini(12, logs.size()):
		tail = str(logs[logs.size() - 1 - i]) + "\n" + tail
	log_label.text = tail
	var cur: int = int(snap.get("current", 0))
	var you: int = int(snap.get("you", 0))
	var phase: int = int(snap.get("phase", 0))
	if phase == int(ArcanaMatchState.Phase.GAME_OVER):
		_clear_sacrifice_mode()
		_hide_mulligan_bar()
		_end_game_ui(snap)
		return
	if bool(snap.get("mulligan_active", false)):
		_show_mulligan_ui(snap)
		end_turn_button.disabled = true
		discard_draw_button.disabled = true
		_rebuild_hand(snap.get("your_hand", []))
		_hide_end_discard_modal()
		return
	_hide_mulligan_bar()
	_hide_game_end_modal()
	var mine := cur == you
	var ui_block := _sacrifice_selecting or _insight_open or _woe_self_picking or bool(snap.get("woe_pending_waiting", false))
	if _burn_woe_overlay != null and _burn_woe_overlay.visible:
		ui_block = true
	if _revive_overlay != null and _revive_overlay.visible:
		ui_block = true
	if bool(snap.get("woe_pending_you_respond", false)):
		status_label.text = "Woe: choose %d card(s) from your hand to discard." % int(snap.get("woe_pending_amount", 0))
	else:
		_woe_self_picked.clear()
	if bool(snap.get("woe_pending_waiting", false)):
		status_label.text = "Waiting for opponent to discard for Woe…"
	end_turn_button.disabled = not mine or ui_block
	discard_draw_button.disabled = not mine or bool(snap.get("discard_draw_used", true)) or ui_block
	_rebuild_hand(snap.get("your_hand", []))
	if bool(snap.get("woe_pending_you_respond", false)):
		_update_woe_discard_status()
	elif _selecting_end_discard:
		_show_end_discard_modal()
	else:
		_hide_end_discard_modal()


func _end_game_ui(snap: Dictionary) -> void:
	var w: int = int(snap.get("winner", -1))
	var you: int = int(snap.get("you", 0))
	var msg := "Draw."
	var title := "Draw"
	if w >= 0:
		if w == you:
			title = "Victory"
			msg = "You win!"
		else:
			title = "Defeat"
			msg = "Opponent wins."
	if bool(snap.get("empty_deck_end", false)) and w >= 0:
		msg = "Empty deck — " + msg
	elif bool(snap.get("empty_deck_end", false)):
		msg = "Empty deck — draw."
	status_label.text = msg
	end_turn_button.disabled = true
	discard_draw_button.disabled = true
	_clear_sacrifice_mode()
	_clear_insight_ui()
	_hide_card_hover_preview()
	_hide_end_discard_modal()
	_show_game_end_modal(title, msg)


func _build_game_end_modal() -> void:
	_game_end_overlay = Control.new()
	_game_end_overlay.name = "GameEndOverlay"
	_game_end_overlay.visible = false
	_game_end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_end_overlay.z_index = 119
	_game_end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_game_end_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_end_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_end_overlay.add_child(center)
	_game_end_modal = PanelContainer.new()
	_game_end_modal.name = "GameEndModal"
	_game_end_modal.visible = true
	_game_end_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_end_modal.z_index = 120
	_game_end_modal.custom_minimum_size = Vector2(420, 190)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	sb.border_color = Color(0.66, 0.72, 0.86)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	_game_end_modal.add_theme_stylebox_override("panel", sb)
	center.add_child(_game_end_modal)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_game_end_modal.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	_game_end_title = Label.new()
	_game_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_end_title.add_theme_font_size_override("font_size", 30)
	v.add_child(_game_end_title)
	_game_end_body = Label.new()
	_game_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_game_end_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_game_end_play_again = Button.new()
	_game_end_play_again.text = "Play Again"
	_game_end_main_menu = Button.new()
	_game_end_main_menu.text = "Main Menu"
	row.add_child(_game_end_play_again)
	row.add_child(_game_end_main_menu)
	_game_end_play_again.pressed.connect(_on_game_end_play_again_pressed)
	_game_end_main_menu.pressed.connect(_on_game_end_main_menu_pressed)


func _show_game_end_modal(title: String, body: String) -> void:
	if _game_end_modal == null:
		return
	_game_end_title.text = title
	_game_end_body.text = body
	_game_end_overlay.visible = true
	_game_end_play_again.disabled = false
	if _is_network_client():
		_game_end_play_again.text = "Play Again (request host)"
	else:
		_game_end_play_again.text = "Play Again"


func _hide_game_end_modal() -> void:
	if _game_end_overlay != null:
		_game_end_overlay.visible = false
		_game_end_play_again.disabled = false
		_game_end_play_again.text = "Play Again"


func _build_end_discard_modal() -> void:
	_end_discard_modal = PanelContainer.new()
	_end_discard_modal.name = "EndDiscardModal"
	_end_discard_modal.visible = false
	_end_discard_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_discard_modal.z_index = 110
	_end_discard_modal.anchor_left = 0.5
	_end_discard_modal.anchor_top = 0.5
	_end_discard_modal.anchor_right = 0.5
	_end_discard_modal.anchor_bottom = 0.5
	_end_discard_modal.offset_left = -180
	_end_discard_modal.offset_top = -70
	_end_discard_modal.offset_right = 180
	_end_discard_modal.offset_bottom = 70
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	sb.border_color = Color(0.66, 0.72, 0.86)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	_end_discard_modal.add_theme_stylebox_override("panel", sb)
	add_child(_end_discard_modal)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_end_discard_modal.add_child(margin)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	_end_discard_label = Label.new()
	_end_discard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_discard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_discard_label.text = "Select cards to discard"
	v.add_child(_end_discard_label)
	_end_discard_confirm_button = Button.new()
	_end_discard_confirm_button.text = "Confirm discard"
	_end_discard_confirm_button.pressed.connect(_on_end_discard_confirm_pressed)
	v.add_child(_end_discard_confirm_button)


func _show_end_discard_modal() -> void:
	if _end_discard_modal != null:
		_end_discard_modal.visible = true


func _hide_end_discard_modal() -> void:
	if _end_discard_modal != null:
		_end_discard_modal.visible = false


func _build_mulligan_bar() -> void:
	_mulligan_bar = PanelContainer.new()
	_mulligan_bar.name = "MulliganBar"
	_mulligan_bar.visible = false
	_mulligan_bar.anchor_left = 0.5
	_mulligan_bar.anchor_right = 0.5
	_mulligan_bar.anchor_top = 0.5
	_mulligan_bar.anchor_bottom = 0.5
	_mulligan_bar.offset_left = -300
	_mulligan_bar.offset_right = 300
	_mulligan_bar.offset_top = -44
	_mulligan_bar.offset_bottom = 44
	_mulligan_bar.z_index = 90
	add_child(_mulligan_bar)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_mulligan_bar.add_child(vb)
	_mulligan_label = Label.new()
	_mulligan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mulligan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_mulligan_label)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	_mulligan_keep_button = Button.new()
	_mulligan_keep_button.text = "Keep hand"
	hb.add_child(_mulligan_keep_button)
	_mulligan_take_button = Button.new()
	_mulligan_take_button.text = "Mulligan"
	hb.add_child(_mulligan_take_button)
	_mulligan_keep_button.pressed.connect(_on_mulligan_keep_pressed)
	_mulligan_take_button.pressed.connect(_on_mulligan_take_pressed)


func _hide_mulligan_bar() -> void:
	if _mulligan_bar != null:
		_mulligan_bar.visible = false


func _show_mulligan_ui(snap: Dictionary) -> void:
	if _mulligan_bar == null:
		return
	_mulligan_bar.visible = true
	var mine := int(snap.get("current", -1)) == int(snap.get("you", 0))
	var bottom_needed := int(snap.get("your_mulligan_bottom_needed", 0))
	var pending_decision := bool(snap.get("your_mulligan_decision_pending", false))
	if not mine:
		_mulligan_label.text = "Opponent resolving opening hand."
		_mulligan_keep_button.visible = false
		_mulligan_take_button.visible = false
		return
	if bottom_needed > 0:
		_mulligan_label.text = "London mulligan: click 1 card in hand to put on bottom."
		_mulligan_keep_button.visible = false
		_mulligan_take_button.visible = false
		return
	if pending_decision:
		_mulligan_label.text = "Opening hand: keep 5 cards or take one London mulligan."
		_mulligan_keep_button.visible = true
		_mulligan_take_button.visible = true
		_mulligan_take_button.disabled = not bool(snap.get("your_can_mulligan", false))
		return
	_mulligan_label.text = "Waiting for opponent opening-hand decision."
	_mulligan_keep_button.visible = false
	_mulligan_take_button.visible = false


func _on_end_discard_confirm_pressed() -> void:
	if bool(_last_snap.get("woe_pending_you_respond", false)):
		_confirm_woe_discard()
	else:
		_confirm_end_turn_discard()


func _on_game_end_play_again_pressed() -> void:
	if _is_network_client():
		_game_end_play_again.disabled = true
		_game_end_play_again.text = "Waiting for host..."
		request_play_again.rpc_id(1)
		return
	_start_match()


func _on_game_end_main_menu_pressed() -> void:
	_on_quit_to_menu_confirmed()


func _field_ritual_total_value(field: Array) -> int:
	var t := 0
	for x in field:
		t += int(x.get("value", 0))
	return t


func _sacrifice_selected_sum(snap: Dictionary) -> int:
	var field: Array = snap.get("your_field", [])
	var s := 0
	for x in field:
		var mid := int(x.get("mid", 0))
		if _sacrifice_selected_mids.has(mid):
			s += int(x.get("value", 0))
	return s


func _enter_sacrifice_mode(hand_idx: int, need: int, card_label: String) -> void:
	_sacrifice_selecting = true
	_inc_pick_phase = INC_PICK_SAC
	_pending_inc_hand_idx = hand_idx
	_pending_inc_n = need
	_sacrifice_need = need
	_sacrifice_selected_mids.clear()
	_wrath_selected_mids.clear()
	_locked_sacrifice_mids.clear()
	sacrifice_row.visible = true
	sacrifice_confirm_button.text = "Confirm sacrifice"
	sacrifice_hint.text = "Sacrifice for %s (need sum ≥ %d). Click your rituals, then confirm." % [card_label, need]
	_update_inc_modal_ui()
	_rebuild_ritual_field(field_you_cards, _last_snap.get("your_field", []), true)
	_rebuild_ritual_field(field_opp_cards, _last_snap.get("opp_field", []), false)
	_rebuild_hand(_last_snap.get("your_hand", []))


func _enter_wrath_only_mode(hand_idx: int, n: int, wneed: int, card_label: String, for_revive: bool = false) -> void:
	_wrath_is_revive_nested = for_revive
	_sacrifice_selecting = true
	_inc_pick_phase = INC_PICK_WRATH
	_pending_inc_hand_idx = hand_idx
	_pending_inc_n = n
	_pending_wrath_need = wneed
	_sacrifice_selected_mids.clear()
	_wrath_selected_mids.clear()
	_locked_sacrifice_mids.clear()
	sacrifice_row.visible = true
	sacrifice_confirm_button.text = "Confirm destroy"
	sacrifice_hint.text = "Wrath: select exactly %d opponent ritual(s) to destroy (%s). Then confirm." % [wneed, card_label]
	_update_inc_modal_ui()
	_rebuild_ritual_field(field_you_cards, _last_snap.get("your_field", []), true)
	_rebuild_ritual_field(field_opp_cards, _last_snap.get("opp_field", []), false)
	_rebuild_hand(_last_snap.get("your_hand", []))


func _start_yytzr_bonus_sacrifice_ui() -> void:
	var st: Array = _yytzr_pending_first_ctx.get("revive_steps", []) as Array
	if st.is_empty():
		return
	_yytzr_first_step = (st[0] as Dictionary).duplicate(true)
	_sacrifice_selecting = true
	_inc_pick_phase = INC_PICK_YTTR
	_sacrifice_need = 2
	_sacrifice_selected_mids.clear()
	sacrifice_row.visible = true
	sacrifice_confirm_button.text = "Confirm sacrifice"
	sacrifice_hint.text = "Yytzr: sacrifice rituals totaling at least 2 for a second crypt cast."
	_update_inc_modal_ui()
	_rebuild_ritual_field(field_you_cards, _last_snap.get("your_field", []), true)
	_rebuild_ritual_field(field_opp_cards, _last_snap.get("opp_field", []), false)
	_rebuild_hand(_last_snap.get("your_hand", []))
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _clear_sacrifice_mode() -> void:
	_sacrifice_selecting = false
	_inc_pick_phase = INC_PICK_NONE
	_pending_inc_hand_idx = -1
	_pending_inc_n = 0
	_sacrifice_need = 0
	_pending_wrath_need = 0
	_pending_dethrone_hand_idx = -1
	_dethrone_selected_mid = -1
	_sacrifice_selected_mids.clear()
	_wrath_selected_mids.clear()
	_locked_sacrifice_mids.clear()
	sacrifice_row.visible = false
	sacrifice_confirm_button.text = "Confirm sacrifice"
	sacrifice_confirm_button.disabled = true


func _update_inc_modal_ui() -> void:
	if not _sacrifice_selecting:
		return
	if _inc_pick_phase == INC_PICK_YTTR:
		var sumy := _sacrifice_selected_sum(_last_snap)
		sacrifice_confirm_button.disabled = sumy < 2
	elif _inc_pick_phase == INC_PICK_SAC:
		var sumv := _sacrifice_selected_sum(_last_snap)
		sacrifice_confirm_button.disabled = sumv < _sacrifice_need
	elif _inc_pick_phase == INC_PICK_WRATH:
		sacrifice_confirm_button.disabled = _wrath_selected_mids.size() != _pending_wrath_need
	elif _inc_pick_phase == INC_PICK_DETHRONE:
		sacrifice_confirm_button.disabled = _dethrone_selected_mid < 0


func _on_sacrifice_field_clicked(mid: int) -> void:
	if not _sacrifice_selecting:
		return
	if _inc_pick_phase != INC_PICK_SAC and _inc_pick_phase != INC_PICK_YTTR:
		return
	if _sacrifice_selected_mids.has(mid):
		_sacrifice_selected_mids.erase(mid)
	else:
		_sacrifice_selected_mids[mid] = true
	_update_inc_modal_ui()
	_rebuild_ritual_field(field_you_cards, _last_snap.get("your_field", []), true)


func _on_wrath_field_clicked(mid: int) -> void:
	if not _sacrifice_selecting or _inc_pick_phase != INC_PICK_WRATH:
		return
	if _wrath_selected_mids.has(mid):
		_wrath_selected_mids.erase(mid)
	else:
		if _wrath_selected_mids.size() >= _pending_wrath_need:
			return
		_wrath_selected_mids[mid] = true
	_update_inc_modal_ui()
	_rebuild_ritual_field(field_opp_cards, _last_snap.get("opp_field", []), false)


func _enter_dethrone_mode(hand_idx: int, locked_sacrifice_mids: Array = []) -> void:
	_sacrifice_selecting = true
	_inc_pick_phase = INC_PICK_DETHRONE
	_pending_dethrone_hand_idx = hand_idx
	_dethrone_selected_mid = -1
	_locked_sacrifice_mids = locked_sacrifice_mids.duplicate()
	sacrifice_row.visible = true
	sacrifice_confirm_button.text = "Confirm destroy"
	if _locked_sacrifice_mids.is_empty():
		sacrifice_hint.text = "Dethrone 4: select one opponent noble to destroy."
	else:
		sacrifice_hint.text = "Dethrone 4: sacrifice locked, now select one opponent noble to destroy."
	_update_inc_modal_ui()
	_rebuild_ritual_field(field_you_cards, _last_snap.get("your_field", []), true)
	_rebuild_ritual_field(field_opp_cards, _last_snap.get("opp_field", []), false)
	_rebuild_hand(_last_snap.get("your_hand", []))


func _on_dethrone_field_clicked(mid: int) -> void:
	if not _sacrifice_selecting or _inc_pick_phase != INC_PICK_DETHRONE:
		return
	_dethrone_selected_mid = mid
	_update_inc_modal_ui()
	_rebuild_ritual_field(field_opp_cards, _last_snap.get("opp_field", []), false)


func _submit_inc_play(sac: Array, wrath_mids: Array) -> void:
	_submit_inc_play_full(sac, wrath_mids, {})


func _submit_inc_play_full(sac: Array, wrath_mids: Array, ctx: Dictionary = {}) -> void:
	if _is_network_client():
		submit_play_inc.rpc_id(1, _pending_inc_hand_idx, sac, wrath_mids, ctx)
		_clear_incantation_flow_ui()
		return
	if _match == null:
		return
	if _match.play_incantation(_my_player_for_action(), _pending_inc_hand_idx, sac, wrath_mids, ctx) != "ok":
		status_label.text = "Could not play incantation."
		return
	_clear_incantation_flow_ui()
	_broadcast_sync(true)


func _clear_incantation_flow_ui() -> void:
	_yytzr_clear_bonus_state()
	_clear_sacrifice_mode()
	_clear_insight_ui()
	_clear_burn_woe_overlay()
	_clear_woe_self_pick()
	_clear_revive_overlay()
	_pending_noble_woe_mid = -1
	_noble_spell_mid = -1


func _submit_dethrone_play(hand_idx: int, noble_mids: Array, sacrifice_mids: Array = []) -> void:
	if _is_network_client():
		submit_play_dethrone.rpc_id(1, hand_idx, noble_mids, sacrifice_mids)
		_clear_sacrifice_mode()
		return
	if _match == null:
		return
	if str(_match.call("play_dethrone", _my_player_for_action(), hand_idx, noble_mids, sacrifice_mids)) != "ok":
		status_label.text = "Could not play Dethrone."
		return
	_clear_sacrifice_mode()
	_broadcast_sync(true)


func _submit_noble_activate_with_insight(noble_mid: int, insight_target: int, insight_perm: Array) -> void:
	if _is_network_client():
		submit_activate_noble_with_insight.rpc_id(1, noble_mid, insight_target, insight_perm)
		_clear_insight_ui()
		return
	if _match == null:
		return
	if _match.activate_noble_with_insight(_my_player_for_action(), noble_mid, insight_target, insight_perm) != "ok":
		status_label.text = "Could not activate noble."
		return
	_clear_insight_ui()
	_broadcast_sync(true)


func _begin_insight_ui(hand_idx: int, n: int, sac_mids: Array, noble_mid: int = -1, revive_crypt_idx: int = -1) -> void:
	_insight_hand_idx = hand_idx
	_insight_noble_mid = noble_mid
	_insight_revive_crypt_idx = revive_crypt_idx
	_insight_n = n
	_insight_sac = sac_mids.duplicate()
	_pending_inc_hand_idx = hand_idx
	if _match == null:
		return
	_insight_open = true
	_insight_target = int(_last_snap.get("you", 0))
	_insight_order.clear()
	_insight_overlay.visible = true
	end_turn_button.disabled = true
	discard_draw_button.disabled = true
	_insight_refresh_insight_panel()
	_rebuild_hand(_last_snap.get("your_hand", []))


func _clear_insight_ui() -> void:
	if _insight_overlay:
		_insight_overlay.visible = false
	_insight_open = false
	_insight_hand_idx = -1
	_insight_noble_mid = -1
	_insight_revive_crypt_idx = -1
	_insight_sac.clear()
	_insight_order.clear()
	for c in _insight_cards_row.get_children():
		c.queue_free()


func _insight_refresh_insight_panel() -> void:
	if _match == null:
		return
	for c in _insight_cards_row.get_children():
		c.queue_free()
	_insight_order.clear()
	var peek: Array = _match.insight_peek_top_cards(_insight_target, _insight_n)
	var take: int = peek.size()
	for i in take:
		_insight_order.append(i)
	var insight_card_w := 54.0 * CARD_SCALE
	var insight_card_h := 78.0 * CARD_SCALE
	for slot in take:
		var p: InsightDnDSlot = InsightDnDSlot.new()
		p.game = self
		p.slot_index = slot
		p.custom_minimum_size = Vector2(insight_card_w, insight_card_h)
		var sb := StyleBoxFlat.new()
		sb.set_border_width_all(2)
		sb.bg_color = Color(0.12, 0.14, 0.2)
		sb.border_color = Color(0.7, 0.75, 0.95)
		p.add_theme_stylebox_override("panel", sb)
		var cctr := CenterContainer.new()
		cctr.set_anchors_preset(Control.PRESET_FULL_RECT)
		cctr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(cctr)
		var lbl := Label.new()
		lbl.name = "CardLbl"
		lbl.text = _card_label(peek[_insight_order[slot]])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 15)
		cctr.add_child(lbl)
		_insight_cards_row.add_child(p)
	if take == 0:
		_insight_hint_label.text = "No cards left in that deck."
	elif take == 1:
		_insight_hint_label.text = "One card on top — confirm or switch deck."
	else:
		_insight_hint_label.text = "Next draw is leftmost. Drag a card onto another to swap."
	_insight_btn_confirm.disabled = false


func _insight_swap_slots(a: int, b: int) -> void:
	if a == b or not _insight_open or _match == null:
		return
	if a < 0 or b < 0 or a >= _insight_order.size() or b >= _insight_order.size():
		return
	var t: Variant = _insight_order[a]
	_insight_order[a] = _insight_order[b]
	_insight_order[b] = t
	var peek: Array = _match.insight_peek_top_cards(_insight_target, _insight_n)
	for child in _insight_cards_row.get_children():
		if child is InsightDnDSlot:
			var ch: InsightDnDSlot = child
			var lbl := child.find_child("CardLbl", true, false)
			if lbl:
				var oi: int = int(_insight_order[ch.slot_index])
				lbl.text = _card_label(peek[oi])


func _on_insight_target_yours() -> void:
	if not _insight_open:
		return
	_insight_target = int(_last_snap.get("you", 0))
	_insight_refresh_insight_panel()


func _on_insight_target_opps() -> void:
	if not _insight_open:
		return
	_insight_target = 1 - int(_last_snap.get("you", 0))
	_insight_refresh_insight_panel()


func _on_insight_confirm_pressed() -> void:
	if not _insight_open or _match == null:
		return
	var peek: Array = _match.insight_peek_top_cards(_insight_target, _insight_n)
	var take: int = peek.size()
	var perm: Array = []
	if take == 0:
		perm = []
	else:
		var ok := _insight_order.size() == take
		if ok:
			var seen: Dictionary = {}
			for x in _insight_order:
				var v := int(x)
				if v < 0 or v >= take or seen.has(v):
					ok = false
					break
				seen[v] = true
			ok = ok and seen.size() == take
		if ok:
			perm = _insight_order.duplicate()
		else:
			for i in take:
				perm.append(i)
	if _insight_noble_mid >= 0:
		_submit_noble_activate_with_insight(_insight_noble_mid, _insight_target, perm)
		return
	if _insight_revive_crypt_idx >= 0:
		var ctxr := {"revive_steps": [{"revive_skip": false, "revive_crypt_idx": _insight_revive_crypt_idx, "nested": {"insight_target": _insight_target, "insight_perm": perm}}]}
		if _revive_ui_for_noble_mid >= 0:
			_finalize_revive_cast(ctxr)
		else:
			_submit_inc_play_full(_insight_sac, [], ctxr)
		return
	_submit_inc_play_full(_insight_sac, [], {"insight_target": _insight_target, "insight_perm": perm})


func _on_insight_cancel_pressed() -> void:
	if not _insight_open:
		return
	_clear_insight_ui()
	if not _last_snap.is_empty():
		_apply_snap(_last_snap)


func _on_sacrifice_confirm_pressed() -> void:
	if not _sacrifice_selecting:
		return
	if _inc_pick_phase == INC_PICK_YTTR:
		var sumy := _sacrifice_selected_sum(_last_snap)
		if sumy < 2:
			return
		var sac_y: Array = []
		for k in _sacrifice_selected_mids.keys():
			sac_y.append(int(k))
		var hi_y := _pending_inc_hand_idx
		var nn_y := _pending_inc_n
		var esac_y := _effect_sac.duplicate()
		_yytzr_extra_sac_mids = sac_y
		_yytzr_waits_second_crypt = true
		_clear_sacrifice_mode()
		_begin_revive_hand_ui(hi_y, nn_y, esac_y)
		return
	if _inc_pick_phase == INC_PICK_SAC:
		var sumv := _sacrifice_selected_sum(_last_snap)
		if sumv < _sacrifice_need:
			return
		var sac: Array = []
		for k in _sacrifice_selected_mids.keys():
			sac.append(int(k))
		if _pending_dethrone_hand_idx >= 0:
			var dhi := _pending_dethrone_hand_idx
			_enter_dethrone_mode(dhi, sac)
			return
		var hand: Array = _last_snap.get("your_hand", [])
		if _pending_inc_hand_idx < 0 or _pending_inc_hand_idx >= hand.size():
			return
		var verb := str(hand[_pending_inc_hand_idx].get("verb", "")).to_lower()
		var opp_f: Array = _last_snap.get("opp_field", [])
		var wneed := mini(_wrath_effective_destroy_count(_last_snap, _pending_inc_n), opp_f.size())
		if verb == "wrath" and wneed > 0:
			_locked_sacrifice_mids = sac
			_inc_pick_phase = INC_PICK_WRATH
			_sacrifice_selected_mids.clear()
			_wrath_selected_mids.clear()
			_pending_wrath_need = wneed
			sacrifice_confirm_button.text = "Confirm destroy"
			sacrifice_hint.text = "Wrath: select exactly %d opponent ritual(s) to destroy. Then confirm." % wneed
			_update_inc_modal_ui()
			_rebuild_ritual_field(field_you_cards, _last_snap.get("your_field", []), true)
			_rebuild_ritual_field(field_opp_cards, _last_snap.get("opp_field", []), false)
			return
		if verb == "insight":
			var hi := _pending_inc_hand_idx
			var nn := _pending_inc_n
			_clear_sacrifice_mode()
			_begin_insight_ui(hi, _insight_depth_for(_last_snap, nn), sac)
			return
		if verb == "burn":
			var hi_b := _pending_inc_hand_idx
			var nn_b := _pending_inc_n
			_clear_sacrifice_mode()
			_begin_burn_target_ui(hi_b, nn_b, sac)
			return
		if verb == "woe":
			var hi_w := _pending_inc_hand_idx
			var nn_w := _pending_inc_n
			_clear_sacrifice_mode()
			_begin_woe_target_ui(hi_w, nn_w, sac)
			return
		if verb == "revive":
			var hi_r := _pending_inc_hand_idx
			var nn_r := _pending_inc_n
			_clear_sacrifice_mode()
			_begin_revive_hand_ui(hi_r, nn_r, sac)
			return
		_submit_inc_play(sac, [])
	elif _inc_pick_phase == INC_PICK_WRATH:
		if _wrath_selected_mids.size() != _pending_wrath_need:
			return
		var wm: Array = []
		for k in _wrath_selected_mids.keys():
			wm.append(int(k))
		if _wrath_is_revive_nested:
			_wrath_is_revive_nested = false
			_finalize_revive_wrath_submit(wm)
			_clear_sacrifice_mode()
			if _match != null:
				_broadcast_sync(true)
			return
		_submit_inc_play_full(_locked_sacrifice_mids.duplicate(), wm, {})
	elif _inc_pick_phase == INC_PICK_DETHRONE:
		if _pending_dethrone_hand_idx < 0 or _dethrone_selected_mid < 0:
			return
		_submit_dethrone_play(_pending_dethrone_hand_idx, [_dethrone_selected_mid], _locked_sacrifice_mids.duplicate())


func _on_sacrifice_cancel_pressed() -> void:
	if not _sacrifice_selecting:
		return
	if _inc_pick_phase == INC_PICK_YTTR:
		var pend := _yytzr_pending_first_ctx.duplicate(true)
		_yytzr_clear_bonus_state()
		_clear_sacrifice_mode()
		if not pend.is_empty():
			_submit_inc_play_full(_effect_sac, [], pend)
		elif not _last_snap.is_empty():
			_apply_snap(_last_snap)
		return
	_clear_sacrifice_mode()
	if not _last_snap.is_empty():
		_apply_snap(_last_snap)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _insight_open:
		get_viewport().set_input_as_handled()
		_on_insight_cancel_pressed()
		return
	if event.is_action_pressed("ui_cancel") and _sacrifice_selecting:
		get_viewport().set_input_as_handled()
		_on_sacrifice_cancel_pressed()


func _rebuild_ritual_field(row: HBoxContainer, field: Variant, ours: bool) -> void:
	for c in row.get_children():
		c.queue_free()
	var nobles: Array = _last_snap.get("your_nobles", []) if ours else _last_snap.get("opp_nobles", [])
	var no_rituals: bool = typeof(field) != TYPE_ARRAY or field.is_empty()
	if no_rituals and nobles.is_empty():
		var empty := Label.new()
		empty.text = "—"
		empty.modulate = Color(0.45, 0.45, 0.5)
		row.add_child(empty)
		return
	if no_rituals:
		field = []
	var act: Array = ArcanaMatchState.active_mask_for_field(field)
	var by_value: Dictionary = {}
	for i in field.size():
		var v: int = int(field[i].get("value", 0))
		if not by_value.has(v):
			by_value[v] = []
		var arr: Array = by_value[v]
		arr.append({
			"value": v,
			"mid": int(field[i].get("mid", 0)),
			"active": i < act.size() and bool(act[i])
		})
		by_value[v] = arr
	var values: Array = by_value.keys()
	values.sort()
	for v in values:
		var pick_mode := 0
		if ours and _sacrifice_selecting and _inc_pick_phase == INC_PICK_SAC:
			pick_mode = 1
		elif not ours and _sacrifice_selecting and _inc_pick_phase == INC_PICK_WRATH:
			pick_mode = 2
		row.add_child(_make_ritual_stack(by_value[v], ours, pick_mode))
	for noble in nobles:
		row.add_child(_make_noble_card(noble, ours))


func _make_ritual_stack(cards: Array, ours: bool, pick_mode: int) -> Control:
	var shift := 12.0 * CARD_SCALE
	var w := RITUAL_CARD_H * RITUAL_CARD_ASPECT
	var h := RITUAL_CARD_H
	var count := cards.size()
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(w + shift * maxi(0, count - 1), h)
	for i in count:
		var d: Dictionary = cards[i]
		var mid: int = int(d.get("mid", -1))
		var picked := (pick_mode == 1 and _sacrifice_selected_mids.has(mid)) or (pick_mode == 2 and _wrath_selected_mids.has(mid))
		var card := _make_ritual_card(
			int(d.get("value", 0)),
			ours,
			bool(d.get("active", true)),
			mid,
			pick_mode,
			picked
		)
		card.position = Vector2(shift * i, 0)
		card.z_index = i
		stack.add_child(card)
	return stack


func _make_ritual_card(value: int, ours: bool, active: bool, ritual_mid: int = -1, pick_mode: int = 0, picked: bool = false) -> Control:
	var w := RITUAL_CARD_H * RITUAL_CARD_ASPECT
	var h := RITUAL_CARD_H
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(3 if picked else 2)
	if ours:
		sb.bg_color = Color(0.04, 0.04, 0.06)
		if pick_mode == 1:
			sb.border_color = Color(0.35, 0.85, 0.45) if picked else Color(0.95, 0.95, 0.95)
		else:
			sb.border_color = Color(0.95, 0.95, 0.95)
	else:
		sb.bg_color = Color(0.96, 0.96, 0.96)
		if pick_mode == 2:
			sb.border_color = Color(0.95, 0.45, 0.35) if picked else Color(0.5, 0.5, 0.55)
		else:
			sb.border_color = Color(0.06, 0.06, 0.08)
	panel.add_theme_stylebox_override("panel", sb)
	if pick_mode == 1 and ritual_mid >= 0:
		var mid_cap := ritual_mid
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb := ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					_on_sacrifice_field_clicked(mid_cap)
		)
	if pick_mode == 2 and ritual_mid >= 0:
		var mid_w := ritual_mid
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb := ev as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
					_on_wrath_field_clicked(mid_w)
		)
	var rv := value
	panel.mouse_entered.connect(func() -> void:
		_show_card_hover_preview({"type": "ritual", "value": rv})
	)
	panel.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(cc)
	var lbl := Label.new()
	lbl.text = str(value)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if ours:
		lbl.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	else:
		lbl.add_theme_color_override("font_color", Color(0.06, 0.06, 0.08))
	lbl.add_theme_font_size_override("font_size", 26)
	cc.add_child(lbl)
	if not active:
		panel.modulate = Color(0.58, 0.58, 0.62)
	return panel


func _make_noble_card(noble: Dictionary, ours: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(RITUAL_CARD_H * RITUAL_CARD_ASPECT, RITUAL_CARD_H)
	var noble_name := _short_noble_name(str(noble.get("name", "Noble")))
	var used_turn := int(noble.get("used_turn", -1))
	var exhausted := used_turn == int(_last_snap.get("turn_number", -999))
	btn.text = noble_name
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2)
	sb.bg_color = Color(0.13, 0.1, 0.18) if ours else Color(0.86, 0.84, 0.91)
	sb.border_color = Color(0.84, 0.7, 1.0) if ours else Color(0.35, 0.28, 0.5)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_color_override("font_color", Color(0.96, 0.93, 1.0) if ours else Color(0.17, 0.12, 0.24))
	var mid := int(noble.get("mid", -1))
	var can_pick_dethrone := not ours and _sacrifice_selecting and _inc_pick_phase == INC_PICK_DETHRONE
	var can_activate := ours and not exhausted and not _sacrifice_selecting and not _insight_open and int(_last_snap.get("current", -1)) == int(_last_snap.get("you", -2))
	btn.disabled = false
	if can_pick_dethrone:
		btn.pressed.connect(func() -> void:
			_on_dethrone_field_clicked(mid)
		)
	elif can_activate:
		btn.pressed.connect(func() -> void:
			_on_noble_activate_pressed(mid)
		)
	else:
		btn.disabled = true
	if can_pick_dethrone and _dethrone_selected_mid == mid:
		var sb_sel := sb.duplicate()
		sb_sel.border_color = Color(1.0, 0.45, 0.45)
		sb_sel.set_border_width_all(3)
		btn.add_theme_stylebox_override("normal", sb_sel)
	if exhausted:
		btn.modulate = Color(0.62, 0.62, 0.62, 1.0)
	var noble_view := noble.duplicate(true)
	noble_view["type"] = "noble"
	btn.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(noble_view)
	)
	btn.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	return btn


func _on_noble_activate_pressed(noble_mid: int) -> void:
	var yours: Array = _last_snap.get("your_nobles", [])
	for noble in yours:
		if int(noble.get("mid", -1)) != noble_mid:
			continue
		var nid := str(noble.get("noble_id", ""))
		if nid == "indrr_incantation":
			_begin_insight_ui(-1, _insight_depth_for(_last_snap, 2), [], noble_mid)
			return
		if nid == "bndrr_incantation":
			_start_noble_burn(noble_mid)
			return
		if nid == "wndrr_incantation":
			_start_noble_woe(noble_mid)
			return
		if nid == "rndrr_incantation":
			_start_noble_revive(noble_mid)
			return
		if nid == "sndrr_incantation":
			if _is_network_client():
				submit_noble_spell_like.rpc_id(1, noble_mid, "seek", 1, [], {})
			else:
				if _match != null:
					_match.apply_noble_spell_like(_my_player_for_action(), noble_mid, "seek", 1, [], {})
			_broadcast_sync(true)
			return
		if nid == "aeoiu_rituals":
			_start_aeoiu_ritual_pick(noble_mid)
			return
		break
	if _is_network_client():
		submit_activate_noble.rpc_id(1, noble_mid)
		return
	if _match == null:
		return
	if _match.activate_noble(_my_player_for_action(), noble_mid) != "ok":
		return
	_broadcast_sync(true)


func _start_noble_burn(noble_mid: int) -> void:
	_noble_spell_mid = noble_mid
	_burn_woe_mode = "noble_burn"
	_pending_mill_target = int(_last_snap.get("you", 0))
	_burn_woe_title.text = "Bndrr — choose deck to mill"
	_tgt_left_btn.text = "Your deck"
	_tgt_right_btn.text = "Opponent deck"
	_burn_woe_hint.text = "Confirm."
	_burn_woe_overlay.visible = true
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _start_noble_woe(noble_mid: int) -> void:
	_noble_spell_mid = noble_mid
	_burn_woe_mode = "noble_woe"
	_pending_woe_target = int(_last_snap.get("you", 0))
	_burn_woe_title.text = "Wndrr — who discards?"
	_tgt_left_btn.text = "You"
	_tgt_right_btn.text = "Opponent"
	_burn_woe_hint.text = "Confirm."
	_burn_woe_overlay.visible = true
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _start_noble_revive(noble_mid: int) -> void:
	_effect_sac = []
	_pending_inc_n = 1
	_pending_inc_hand_idx = -1
	_begin_revive_hand_ui(-1, 1, [], noble_mid)


func _start_aeoiu_ritual_pick(noble_mid: int) -> void:
	_aeoiu_noble_mid = noble_mid
	for c in _aeoiu_crypt_row.get_children():
		c.queue_free()
	var rg: Array = _last_snap.get("your_ritual_grave_cards", []) as Array
	var idx := 0
	for i in rg.size():
		var card: Dictionary = rg[i]
		var vv := int(card.get("value", 0))
		var b := Button.new()
		b.text = "Ritual %d (grave #%d)" % [vv, idx]
		var capture := idx
		b.pressed.connect(func() -> void:
			_on_aeoiu_grave_chosen(capture)
		)
		_aeoiu_crypt_row.add_child(b)
		idx += 1
	if _aeoiu_crypt_row.get_child_count() == 0:
		status_label.text = "No rituals in your crypt."
		return
	_aeoiu_overlay.visible = true
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _on_aeoiu_grave_chosen(grave_idx: int) -> void:
	var nm := _aeoiu_noble_mid
	_aeoiu_overlay.visible = false
	_aeoiu_noble_mid = -1
	end_turn_button.disabled = false
	discard_draw_button.disabled = false
	if _is_network_client():
		submit_aeoiu_ritual.rpc_id(1, nm, grave_idx)
	else:
		if _match != null:
			_match.apply_aeoiu_ritual_from_crypt(_my_player_for_action(), nm, grave_idx)
	_broadcast_sync(true)


func _on_aeoiu_cancel_pressed() -> void:
	_aeoiu_overlay.visible = false
	_aeoiu_noble_mid = -1
	end_turn_button.disabled = false
	discard_draw_button.disabled = false


func _rebuild_hand(hand: Variant) -> void:
	for c in hand_row.get_children():
		c.queue_free()
	if typeof(hand) != TYPE_ARRAY:
		return
	var hand_arr := hand as Array
	var card_counts: Dictionary = {}
	for card in hand_arr:
		var key := _hand_card_stack_key(card)
		card_counts[key] = int(card_counts.get(key, 0)) + 1
	var rendered_keys: Dictionary = {}
	var mine: bool = int(_last_snap.get("current", -1)) == int(_last_snap.get("you", -2))
	var woe_you := bool(_last_snap.get("woe_pending_you_respond", false))
	var group_duplicates := true
	var ritual_used := mine and bool(_last_snap.get("your_ritual_played", false))
	var noble_used := mine and bool(_last_snap.get("your_noble_played", false))
	var idx := 0
	for card in hand_arr:
		var stack_key := _hand_card_stack_key(card)
		if group_duplicates and rendered_keys.has(stack_key):
			idx += 1
			continue
		rendered_keys[stack_key] = true
		var ctype := _card_type(card)
		var ritual_blocked := ritual_used and ctype == "ritual"
		var noble_blocked := noble_used and ctype == "noble"
		var play_type_blocked := (ritual_blocked or noble_blocked) and not _mode_discard_draw and not _selecting_end_discard
		var waiting_input_window := mine or woe_you
		var is_disabled := (not waiting_input_window and not _selecting_end_discard and not _mode_discard_draw) or _sacrifice_selecting or _insight_open or play_type_blocked
		var picked_count := 0
		if woe_you:
			picked_count = int(_woe_self_picked.get(stack_key, 0))
		elif _selecting_end_discard:
			picked_count = int(_end_discard_picked.get(stack_key, 0))
		var picked := picked_count > 0
		var stack_count := int(card_counts.get(stack_key, 0))
		var widget := _make_hand_card_widget(card, is_disabled, picked, stack_count, picked_count)
		if not mine:
			widget.modulate = Color(0.55, 0.55, 0.58)
		var capture := idx
		var tap := widget.find_child("Tap", true, false)
		if tap is Button:
			(tap as Button).pressed.connect(func() -> void:
				_on_hand_pressed(capture)
			)
		hand_row.add_child(widget)
		idx += 1


func _make_hand_card_widget(card: Variant, disabled: bool, picked: bool, stack_count: int, picked_count: int = 0) -> Control:
	var depth := 0
	if stack_count == 2:
		depth = 1
	elif stack_count >= 3:
		depth = 2
	var shift := 6.0 * CARD_SCALE
	var w := HAND_CARD_W
	var h := HAND_CARD_H
	var shell := Control.new()
	shell.custom_minimum_size = Vector2(w + shift * depth, h)
	shell.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in depth:
		var back := Panel.new()
		back.position = Vector2(i * shift, 0)
		back.size = Vector2(w, h)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bsb := StyleBoxFlat.new()
		bsb.set_corner_radius_all(3)
		bsb.set_border_width_all(2)
		bsb.bg_color = Color(0.11, 0.11, 0.14)
		bsb.border_color = Color(0.46, 0.46, 0.52)
		back.add_theme_stylebox_override("panel", bsb)
		shell.add_child(back)
	var tap := Button.new()
	tap.name = "Tap"
	tap.text = _card_label(card)
	tap.position = Vector2(depth * shift, 0)
	tap.size = Vector2(w, h)
	tap.disabled = disabled
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(3 if picked else 2)
	sb.bg_color = Color(0.04, 0.04, 0.06)
	sb.border_color = Color(0.7, 0.9, 1.0) if picked else Color(0.92, 0.92, 0.95)
	tap.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.border_color = Color(0.84, 0.96, 1.0) if picked else Color(1.0, 1.0, 1.0)
	tap.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := sb.duplicate()
	sb_pressed.bg_color = Color(0.08, 0.08, 0.12)
	tap.add_theme_stylebox_override("pressed", sb_pressed)
	var sb_dis := sb.duplicate()
	sb_dis.bg_color = Color(0.08, 0.08, 0.1)
	sb_dis.border_color = Color(0.45, 0.45, 0.5)
	tap.add_theme_stylebox_override("disabled", sb_dis)
	tap.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	tap.add_theme_color_override("font_hover_color", Color(0.98, 0.98, 0.98))
	tap.add_theme_color_override("font_pressed_color", Color(0.98, 0.98, 0.98))
	tap.add_theme_color_override("font_disabled_color", Color(0.7, 0.7, 0.76))
	tap.add_theme_font_size_override("font_size", 16)
	var hover_card: Dictionary = card.duplicate(true) if typeof(card) == TYPE_DICTIONARY else {}
	shell.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(hover_card)
	)
	shell.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	tap.mouse_entered.connect(func() -> void:
		_show_card_hover_preview(hover_card)
	)
	tap.mouse_exited.connect(func() -> void:
		_hide_card_hover_preview()
	)
	shell.add_child(tap)
	if stack_count > 1:
		var badge := Label.new()
		badge.text = "x%d" % stack_count
		badge.position = Vector2(depth * shift + w - 26, 4)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(22, 16)
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color(0.95, 0.95, 0.99))
		shell.add_child(badge)
	if _selecting_end_discard and picked_count > 0:
		var pick_badge := Label.new()
		pick_badge.text = "-%d" % picked_count
		pick_badge.position = Vector2(depth * shift + 4, 4)
		pick_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pick_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pick_badge.custom_minimum_size = Vector2(24, 16)
		pick_badge.add_theme_font_size_override("font_size", 12)
		pick_badge.add_theme_color_override("font_color", Color(1.0, 0.86, 0.86))
		shell.add_child(pick_badge)
	elif bool(_last_snap.get("woe_pending_you_respond", false)) and picked:
		var woe_badge := Label.new()
		woe_badge.text = "W"
		woe_badge.position = Vector2(depth * shift + 6, 4)
		woe_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		woe_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		woe_badge.custom_minimum_size = Vector2(16, 16)
		woe_badge.add_theme_font_size_override("font_size", 12)
		woe_badge.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
		shell.add_child(woe_badge)
	return shell


func _hand_card_stack_key(card: Variant) -> String:
	var t := _card_type(card)
	if t == "ritual":
		return "r:%d" % int(card.get("value", 0))
	if t == "noble":
		return "n:%s" % str(card.get("noble_id", ""))
	if t == "dethrone":
		return "dethrone"
	return "i:%s:%d" % [str(card.get("verb", "")).to_lower(), int(card.get("value", 0))]


func _card_type(card: Variant) -> String:
	return str(card.get("type", "")).to_lower()


func _card_label(card: Variant) -> String:
	var t := _card_type(card)
	if t == "ritual":
		return "%d-R" % int(card.get("value", 0))
	if t == "noble":
		return _short_noble_name(str(card.get("name", "Noble")))
	if t == "dethrone":
		return "Dethrone 4"
	return "%s %d" % [str(card.get("verb", "")), int(card.get("value", 0))]


func _short_noble_name(full_name: String) -> String:
	var idx := full_name.find(",")
	if idx <= 0:
		return full_name
	return full_name.substr(0, idx).strip_edges()


func _on_hand_pressed(hand_idx: int) -> void:
	if _match == null and not _is_network_client():
		return
	if _is_network_client() and _last_snap.is_empty():
		return
	var snap: Dictionary = _last_snap
	if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return
	var woe_you := bool(snap.get("woe_pending_you_respond", false))
	if bool(snap.get("mulligan_active", false)):
		if int(snap.get("current", -1)) != int(snap.get("you", 0)):
			return
		if int(snap.get("your_mulligan_bottom_needed", 0)) > 0:
			if _is_network_client():
				submit_mulligan_bottom.rpc_id(1, hand_idx)
			else:
				_try_mulligan_bottom(_my_player_for_action(), hand_idx)
		return
	if int(snap.get("current", -1)) != int(snap.get("you", 0)) and not woe_you:
		return
	var hand: Array = snap.get("your_hand", [])
	if hand_idx < 0 or hand_idx >= hand.size():
		return
	var c: Dictionary = hand[hand_idx]
	if woe_you:
		var need_w := int(snap.get("woe_pending_amount", 0))
		var stack_key_w := _hand_card_stack_key(c)
		var stack_total_w := 0
		for card_in_hand_w in hand:
			if _hand_card_stack_key(card_in_hand_w) == stack_key_w:
				stack_total_w += 1
		var stack_picked_w := int(_woe_self_picked.get(stack_key_w, 0))
		var total_picked_w := _woe_discard_selected_total()
		if total_picked_w < need_w and stack_picked_w < stack_total_w:
			_woe_self_picked[stack_key_w] = stack_picked_w + 1
		elif stack_picked_w > 0:
			stack_picked_w -= 1
			if stack_picked_w <= 0:
				_woe_self_picked.erase(stack_key_w)
			else:
				_woe_self_picked[stack_key_w] = stack_picked_w
		_update_woe_discard_status()
		_rebuild_hand(hand)
		return
	if _woe_self_picking and _pending_noble_woe_mid >= 0:
		if _woe_self_picked.has(hand_idx):
			_woe_self_picked.erase(hand_idx)
		else:
			if _woe_self_picked.size() < _woe_self_need:
				_woe_self_picked[hand_idx] = true
		if _woe_self_need > 0 and _woe_self_picked.size() == _woe_self_need:
			var idxsn: Array = []
			for kn in _woe_self_picked.keys():
				idxsn.append(int(kn))
			idxsn.sort()
			var ctxn := {"woe_target": int(snap.get("you", 0)), "woe_indices": idxsn}
			if _is_network_client():
				submit_noble_spell_like.rpc_id(1, _pending_noble_woe_mid, "woe", 1, [], ctxn)
			else:
				if _match != null:
					_match.apply_noble_spell_like(_my_player_for_action(), _pending_noble_woe_mid, "woe", 1, [], ctxn)
			_pending_noble_woe_mid = -1
			_woe_self_picking = false
			_woe_self_picked.clear()
			_noble_spell_mid = -1
			_broadcast_sync(true)
		else:
			_rebuild_hand(hand)
		return
	if _woe_self_picking and _burn_woe_mode != "revive_woe_self":
		if _woe_self_picked.has(hand_idx):
			_woe_self_picked.erase(hand_idx)
		else:
			if _woe_self_picked.size() < _woe_self_need:
				_woe_self_picked[hand_idx] = true
		if _woe_self_need > 0 and _woe_self_picked.size() == _woe_self_need:
			var idxs2: Array = []
			for k2 in _woe_self_picked.keys():
				idxs2.append(int(k2))
			idxs2.sort()
			var ctxw := {"woe_target": int(snap.get("you", 0)), "woe_indices": idxs2}
			_woe_self_picking = false
			_woe_self_picked.clear()
			_submit_inc_play_full(_effect_sac, [], ctxw)
		else:
			_rebuild_hand(hand)
		return
	if _woe_self_picking and _burn_woe_mode == "revive_woe_self":
		if _woe_self_picked.has(hand_idx):
			_woe_self_picked.erase(hand_idx)
		else:
			if _woe_self_picked.size() < _woe_self_need:
				_woe_self_picked[hand_idx] = true
		if _woe_self_need > 0 and _woe_self_picked.size() == _woe_self_need:
			var idxs3: Array = []
			for k3 in _woe_self_picked.keys():
				idxs3.append(int(k3))
			idxs3.sort()
			var ctxv2 := {"revive_steps": [{"revive_skip": false, "revive_crypt_idx": _nested_revive_crypt_idx, "nested": {"woe_target": int(snap.get("you", 0)), "woe_indices": idxs3}}]}
			_woe_self_picking = false
			_burn_woe_mode = ""
			_woe_self_picked.clear()
			_finalize_revive_cast(ctxv2)
		else:
			_rebuild_hand(hand)
		return
	if _insight_open:
		return
	if _sacrifice_selecting:
		return
	if _mode_discard_draw:
		_mode_discard_draw = false
		if _is_network_client():
			submit_discard_draw.rpc_id(1, hand_idx)
		else:
			_try_discard_draw(_my_player_for_action(), hand_idx)
		return
	if _selecting_end_discard:
		var stack_key := _hand_card_stack_key(c)
		var stack_total := 0
		for card_in_hand in hand:
			if _hand_card_stack_key(card_in_hand) == stack_key:
				stack_total += 1
		var stack_picked := int(_end_discard_picked.get(stack_key, 0))
		var total_picked := _end_discard_selected_total()
		if total_picked < _end_discard_needed and stack_picked < stack_total:
			_end_discard_picked[stack_key] = stack_picked + 1
		elif stack_picked > 0:
			stack_picked -= 1
			if stack_picked <= 0:
				_end_discard_picked.erase(stack_key)
			else:
				_end_discard_picked[stack_key] = stack_picked
		_update_end_discard_status()
		_rebuild_hand(snap.get("your_hand", []))
		return
	if _card_type(c) == "ritual":
		if bool(snap.get("your_ritual_played", false)):
			status_label.text = "You already played a ritual this turn."
			return
		if _is_network_client():
			submit_play_ritual.rpc_id(1, hand_idx)
		else:
			_try_play_ritual(_my_player_for_action(), hand_idx)
	elif _card_type(c) == "noble":
		if bool(snap.get("your_noble_played", false)):
			status_label.text = "You already played a noble this turn."
			return
		if _is_network_client():
			submit_play_noble.rpc_id(1, hand_idx)
		else:
			_try_play_noble(_my_player_for_action(), hand_idx)
	elif _card_type(c) == "dethrone":
		var opp_nobles: Array = snap.get("opp_nobles", [])
		if opp_nobles.is_empty():
			status_label.text = "Opponent has no nobles to dethrone."
			return
		var n := int(c.get("value", 4))
		var field: Array = snap.get("your_field", [])
		var has_lane := ArcanaMatchState.has_lane_for_field(field, n)
		if not has_lane and _field_ritual_total_value(field) < n:
			status_label.text = "Not enough ritual value on your field to pay for Dethrone %d." % n
			return
		if has_lane:
			if opp_nobles.size() == 1:
				var only_mid := int(opp_nobles[0].get("mid", -1))
				if _is_network_client():
					submit_play_dethrone.rpc_id(1, hand_idx, [only_mid], [])
				else:
					_try_play_dethrone(_my_player_for_action(), hand_idx, [only_mid], [], true)
				return
			_enter_dethrone_mode(hand_idx)
			return
		_enter_sacrifice_mode(hand_idx, n, "Dethrone %d" % n)
		_pending_dethrone_hand_idx = hand_idx
	else:
		var n: int = int(c.get("value", 0))
		var verb := str(c.get("verb", "")).to_lower()
		var field: Array = snap.get("your_field", [])
		if ArcanaMatchState.has_lane_for_field(field, n):
			if verb == "wrath":
				var opp_field: Array = snap.get("opp_field", [])
				var wneed := mini(_wrath_effective_destroy_count(_last_snap, n), opp_field.size())
				if wneed == 0:
					if _is_network_client():
						submit_play_inc.rpc_id(1, hand_idx, [], [], {})
					else:
						_try_play_inc(_my_player_for_action(), hand_idx, [], [], {})
				else:
					_enter_wrath_only_mode(hand_idx, n, wneed, "%s %d" % [verb, n])
				return
			if verb == "insight":
				_begin_insight_ui(hand_idx, _insight_depth_for(_last_snap, n), [])
				return
			if verb == "seek":
				if _is_network_client():
					submit_play_inc.rpc_id(1, hand_idx, [], [], {})
				else:
					_try_play_inc(_my_player_for_action(), hand_idx, [], [], {})
				return
			if verb == "burn":
				_begin_burn_target_ui(hand_idx, n, [])
				return
			if verb == "woe":
				_begin_woe_target_ui(hand_idx, n, [])
				return
			if verb == "revive":
				_begin_revive_hand_ui(hand_idx, n, [])
				return
			if _is_network_client():
				submit_play_inc.rpc_id(1, hand_idx, [], [], {})
			else:
				_try_play_inc(_my_player_for_action(), hand_idx, [], [], {})
			return
		if _field_ritual_total_value(field) < n:
			status_label.text = "Not enough ritual value on your field to pay for this incantation."
			return
		_enter_sacrifice_mode(hand_idx, n, "%s %d" % [verb, n])


func _my_player_for_action() -> int:
	if _is_network_pvp() and multiplayer.is_server():
		return 0
	if _is_network_pvp():
		return 1
	return 0


func _greedy_sacrifice_mids(snap: Dictionary, need: int) -> Array:
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


func _greedy_wrath_mids(opp_field: Array, need: int) -> Array:
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


func _wrath_destroy_count(value: int) -> int:
	if value == 4:
		return 2
	return 0


func _try_play_ritual(player: int, hand_idx: int, trigger_cpu_check: bool = true) -> bool:
	if _match == null:
		return false
	if _match.play_ritual(player, hand_idx) != "ok":
		status_label.text = "Can't play that now (not your turn or invalid index)."
		return false
	_broadcast_sync(trigger_cpu_check)
	return true


func _try_play_noble(player: int, hand_idx: int, trigger_cpu_check: bool = true) -> bool:
	if _match == null:
		return false
	if _match.play_noble(player, hand_idx) != "ok":
		status_label.text = "Can't play that noble now."
		return false
	_broadcast_sync(trigger_cpu_check)
	return true


func _try_play_inc(player: int, hand_idx: int, sacrifice_mids: Array, wrath_mids: Array = [], ctx: Dictionary = {}, trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	if _match.play_incantation(player, hand_idx, sacrifice_mids, wrath_mids, ctx) != "ok":
		return
	_broadcast_sync(trigger_cpu_check)


func _try_submit_woe_discard(player: int, indices: Array, trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	if _match.submit_woe_discard(player, indices) != "ok":
		return
	_broadcast_sync(trigger_cpu_check)


func _try_play_dethrone(player: int, hand_idx: int, noble_mids: Array = [], sacrifice_mids: Array = [], trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	if str(_match.call("play_dethrone", player, hand_idx, noble_mids, sacrifice_mids)) != "ok":
		return
	_broadcast_sync(trigger_cpu_check)


func _try_discard_draw(player: int, hand_idx: int, trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	if _match.discard_for_draw(player, hand_idx) != "ok":
		return
	_broadcast_sync(trigger_cpu_check)


func _try_end_turn(player: int, discard_indices: Array, trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	if _match.end_turn(player, discard_indices) != "ok":
		status_label.text = "Could not end turn with selected discards."
		return
	_broadcast_sync(trigger_cpu_check)


func _end_discard_selected_total() -> int:
	var total := 0
	for v in _end_discard_picked.values():
		total += int(v)
	return total


func _end_discard_indices_from_hand(hand: Array) -> Array:
	var grouped_indices: Dictionary = {}
	for i in hand.size():
		var key_i := _hand_card_stack_key(hand[i])
		if not grouped_indices.has(key_i):
			grouped_indices[key_i] = []
		var arr_i: Array = grouped_indices[key_i]
		arr_i.append(i)
		grouped_indices[key_i] = arr_i
	var indices: Array = []
	for key in _end_discard_picked.keys():
		var need_from_key := int(_end_discard_picked.get(key, 0))
		var picks_for_key: Array = grouped_indices.get(key, [])
		for j in mini(need_from_key, picks_for_key.size()):
			indices.append(picks_for_key[j])
	return indices


func _confirm_end_turn_discard() -> void:
	if not _selecting_end_discard:
		return
	var snap: Dictionary = _last_snap
	var hand_sel: Array = snap.get("your_hand", [])
	var picked := _end_discard_selected_total()
	if picked < _end_discard_needed:
		_update_end_discard_status()
		return
	var indices := _end_discard_indices_from_hand(hand_sel)
	_selecting_end_discard = false
	_end_discard_picked.clear()
	_hide_end_discard_modal()
	if _is_network_client():
		submit_end_turn.rpc_id(1, indices)
	else:
		_try_end_turn(_my_player_for_action(), indices)


func _update_end_discard_status() -> void:
	var selected := _end_discard_selected_total()
	status_label.text = "Select %d card(s) to discard, then press End Turn. Selected %d/%d." % [_end_discard_needed, selected, _end_discard_needed]
	if _end_discard_label != null:
		_end_discard_label.text = "Select cards to discard\nSelected %d/%d" % [selected, _end_discard_needed]
	if _end_discard_confirm_button != null:
		_end_discard_confirm_button.disabled = selected < _end_discard_needed
	if _selecting_end_discard:
		_show_end_discard_modal()
	else:
		_hide_end_discard_modal()


func _woe_discard_selected_total() -> int:
	var total := 0
	for v in _woe_self_picked.values():
		total += int(v)
	return total


func _woe_discard_indices_from_hand(hand: Array) -> Array:
	var grouped_indices: Dictionary = {}
	for i in hand.size():
		var key_i := _hand_card_stack_key(hand[i])
		if not grouped_indices.has(key_i):
			grouped_indices[key_i] = []
		var arr_i: Array = grouped_indices[key_i]
		arr_i.append(i)
		grouped_indices[key_i] = arr_i
	var indices: Array = []
	for key in _woe_self_picked.keys():
		var need_from_key := int(_woe_self_picked.get(key, 0))
		var picks_for_key: Array = grouped_indices.get(key, [])
		for j in mini(need_from_key, picks_for_key.size()):
			indices.append(picks_for_key[j])
	return indices


func _update_woe_discard_status() -> void:
	var need := int(_last_snap.get("woe_pending_amount", 0))
	var selected := _woe_discard_selected_total()
	status_label.text = "Woe: select %d card(s). Selected %d/%d." % [need, selected, need]
	if _end_discard_label != null:
		_end_discard_label.text = "Woe discard\nSelected %d/%d" % [selected, need]
	if _end_discard_confirm_button != null:
		_end_discard_confirm_button.text = "Confirm discard"
		_end_discard_confirm_button.disabled = selected < need
	_show_end_discard_modal()


func _confirm_woe_discard() -> void:
	if not bool(_last_snap.get("woe_pending_you_respond", false)):
		return
	var need := int(_last_snap.get("woe_pending_amount", 0))
	if _woe_discard_selected_total() < need:
		_update_woe_discard_status()
		return
	var idxs: Array = _woe_discard_indices_from_hand(_last_snap.get("your_hand", []) as Array)
	idxs.sort()
	if _is_network_client():
		submit_woe_discard.rpc_id(1, idxs)
		_woe_self_picked.clear()
	else:
		if _match != null:
			var wr := _match.submit_woe_discard(_my_player_for_action(), idxs)
			if wr != "ok":
				status_label.text = "Woe discard selection rejected (%s). Re-select cards." % wr
				_update_woe_discard_status()
				return
			_woe_self_picked.clear()
	_broadcast_sync(true)


func _run_cpu_turn() -> void:
	if _match == null:
		return
	var snap: Dictionary
	while true:
		await get_tree().create_timer(CPU_ACTION_SEC).timeout
		snap = _match.snapshot(1)
		if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
			return
		if bool(snap.get("woe_pending_you_respond", false)):
			var hwo: Array = snap.get("your_hand", [])
			var needw := int(snap.get("woe_pending_amount", 0))
			var idxsw: Array = []
			for wi in mini(needw, hwo.size()):
				idxsw.append(wi)
			_try_submit_woe_discard(1, idxsw, false)
			continue
		if int(snap.get("current", -1)) != int(snap.get("you", -2)):
			return
		var hand: Array = snap.get("your_hand", [])
		var played_ritual := false
		for i in hand.size():
			if _card_type(hand[i]) != "ritual":
				continue
			if _match.can_play_ritual(1, i):
				_try_play_ritual(1, i, false)
				played_ritual = true
			break
		if played_ritual:
			continue
		var played_noble := false
		for i in hand.size():
			if _card_type(hand[i]) != "noble":
				continue
			if _match.can_play_noble(1, i):
				_try_play_noble(1, i, false)
				played_noble = true
			break
		if played_noble:
			continue
		var noble_field: Array = snap.get("your_nobles", [])
		for nn in noble_field:
			var nmid := int(nn.get("mid", -1))
			if not _match.can_activate_noble(1, nmid):
				continue
			var nid2 := str(nn.get("noble_id", ""))
			var ok_act := false
			if nid2 == "bndrr_incantation":
				ok_act = _match.apply_noble_spell_like(1, nmid, "burn", 1, [], {"mill_target": 0}) == "ok"
			elif nid2 == "wndrr_incantation":
				ok_act = _match.apply_noble_spell_like(1, nmid, "woe", 1, [], {"woe_target": 0}) == "ok"
			elif nid2 == "sndrr_incantation":
				ok_act = _match.apply_noble_spell_like(1, nmid, "seek", 1, [], {}) == "ok"
			elif nid2 == "rndrr_incantation":
				ok_act = _match.apply_noble_revive_from_crypt(1, nmid, {"revive_steps": [{"revive_skip": true}]}) == "ok"
			elif nid2 == "indrr_incantation":
				var tgt_i := 0
				var idn: int = _match.insight_effective_n(1, 2)
				var peek2: Array = _match.insight_peek_top_cards(tgt_i, idn)
				var perm_i: Array = []
				for ii in peek2.size():
					perm_i.append(ii)
				ok_act = _match.activate_noble_with_insight(1, nmid, tgt_i, perm_i) == "ok"
			elif nid2 == "aeoiu_rituals":
				var rgc: Array = snap.get("your_ritual_grave_cards", []) as Array
				if rgc.is_empty():
					ok_act = false
				else:
					ok_act = _match.apply_aeoiu_ritual_from_crypt(1, nmid, 0) == "ok"
			else:
				ok_act = _match.activate_noble(1, nmid) == "ok"
			if ok_act:
				_broadcast_sync(false)
				await get_tree().create_timer(CPU_ACTION_SEC).timeout
			break
		var playable: Array[int] = []
		for j in hand.size():
			var ctype := _card_type(hand[j])
			if ctype == "dethrone":
				var opp_nobles_a: Array = snap.get("opp_nobles", [])
				var need_d := int(hand[j].get("value", 4))
				var fld_d: Array = snap.get("your_field", [])
				var ok_lane_d := ArcanaMatchState.has_lane_for_field(fld_d, need_d)
				var tot_d := 0
				for x in fld_d:
					tot_d += int(x.get("value", 0))
				if not opp_nobles_a.is_empty() and (ok_lane_d or tot_d >= need_d):
					playable.append(j)
				continue
			if ctype != "incantation":
				continue
			var n: int = int(hand[j].get("value", 0))
			var fld: Array = snap.get("your_field", [])
			var ok_lane := ArcanaMatchState.has_lane_for_field(fld, n)
			var tot := 0
			for x in fld:
				tot += int(x.get("value", 0))
			if ok_lane or tot >= n:
				playable.append(j)
		if playable.is_empty():
			break
		var k := randi_range(0, playable.size())
		for _t in k:
			snap = _match.snapshot(1)
			if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
				return
			if int(snap.get("current", -1)) != int(snap.get("you", -2)):
				return
			hand = snap.get("your_hand", [])
			playable.clear()
			for j in hand.size():
				var ctype2 := _card_type(hand[j])
				if ctype2 == "dethrone":
					var opp_nobles_b: Array = snap.get("opp_nobles", [])
					var need_d2 := int(hand[j].get("value", 4))
					var fld_d2: Array = snap.get("your_field", [])
					var ok_lane_d2 := ArcanaMatchState.has_lane_for_field(fld_d2, need_d2)
					var tot_d2 := 0
					for x in fld_d2:
						tot_d2 += int(x.get("value", 0))
					if not opp_nobles_b.is_empty() and (ok_lane_d2 or tot_d2 >= need_d2):
						playable.append(j)
					continue
				if ctype2 != "incantation":
					continue
				var n2: int = int(hand[j].get("value", 0))
				var fld2: Array = snap.get("your_field", [])
				var ok2 := ArcanaMatchState.has_lane_for_field(fld2, n2)
				var tot2 := 0
				for x in fld2:
					tot2 += int(x.get("value", 0))
				if ok2 or tot2 >= n2:
					playable.append(j)
			if playable.is_empty():
				break
			var pick := playable[randi_range(0, playable.size() - 1)]
			if _card_type(hand[pick]) == "dethrone":
				var opp_nobles: Array = snap.get("opp_nobles", [])
				if not opp_nobles.is_empty():
					var tmid := int(opp_nobles[0].get("mid", -1))
					var dn := int(hand[pick].get("value", 4))
					var dsac: Array = []
					if not ArcanaMatchState.has_lane_for_field(snap.get("your_field", []), dn):
						dsac = _greedy_sacrifice_mids(snap, dn)
					_try_play_dethrone(1, pick, [tmid], dsac, false)
					await get_tree().create_timer(CPU_ACTION_SEC).timeout
					continue
			var nv: int = int(hand[pick].get("value", 0))
			var sac: Array = []
			if not ArcanaMatchState.has_lane_for_field(snap.get("your_field", []), nv):
				sac = _greedy_sacrifice_mids(snap, nv)
			var wm: Array = []
			var vrb := str(hand[pick].get("verb", "")).to_lower()
			if vrb == "wrath":
				var opp_f: Array = snap.get("opp_field", [])
				var wn := mini(_match.effective_wrath_destroy_count(1, nv), opp_f.size())
				if wn > 0:
					wm = _greedy_wrath_mids(opp_f, wn)
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
					var idnv: int = _match.insight_effective_n(1, nv)
					var pk: Array = _match.insight_peek_top_cards(tgt0, idnv)
					var prm: Array = []
					for ii in pk.size():
						prm.append(ii)
					ictx = {"insight_target": tgt0, "insight_perm": prm}
				"revive":
					ictx = {"revive_steps": [{"revive_skip": true}]}
				_:
					ictx = {}
			_try_play_inc(1, pick, sac, wm, ictx, false)
			await get_tree().create_timer(CPU_ACTION_SEC).timeout
		break
	snap = _match.snapshot(1)
	if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return
	if int(snap.get("current", -1)) != int(snap.get("you", -2)):
		return
	if not bool(snap.get("discard_draw_used", true)) and randf() < 0.35:
		var harr: Array = snap.get("your_hand", [])
		var hs := harr.size()
		if hs > 0:
			_try_discard_draw(1, randi_range(0, hs - 1), false)
			await get_tree().create_timer(CPU_ACTION_SEC).timeout
	snap = _match.snapshot(1)
	if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return
	if int(snap.get("current", -1)) != int(snap.get("you", -2)):
		return
	var disc := _ai_end_discards_from_snap(snap)
	_try_end_turn(1, disc, true)


func _run_cpu_mulligan_step() -> void:
	if _match == null:
		return
	var snap := _match.snapshot(1)
	if not bool(snap.get("mulligan_active", false)):
		return
	if int(snap.get("current", -1)) != 1:
		return
	var bottom_needed := int(snap.get("your_mulligan_bottom_needed", 0))
	if bottom_needed > 0:
		var hand: Array = snap.get("your_hand", [])
		if hand.is_empty():
			return
		_try_mulligan_bottom(1, randi_range(0, hand.size() - 1), true)
		return
	var can_take := bool(snap.get("your_can_mulligan", false))
	var take := false
	if can_take:
		var hand_now: Array = snap.get("your_hand", [])
		var rituals := 0
		for c in hand_now:
			if _card_type(c) == "ritual":
				rituals += 1
		take = rituals <= 1
	_try_choose_mulligan(1, take, true)


func _ai_end_discards_from_snap(snap: Dictionary) -> Array:
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


func _try_choose_mulligan(player: int, take_mulligan: bool, trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	if _match.choose_starting_hand(player, take_mulligan) != "ok":
		return
	_broadcast_sync(trigger_cpu_check)


func _try_mulligan_bottom(player: int, hand_idx: int, trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	if _match.bottom_mulligan_card(player, hand_idx) != "ok":
		return
	_broadcast_sync(trigger_cpu_check)


@rpc("any_peer", "reliable")
func submit_play_ritual(hand_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_play_ritual(pl, hand_idx)


@rpc("any_peer", "reliable")
func submit_play_noble(hand_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_play_noble(pl, hand_idx)


@rpc("any_peer", "reliable")
func submit_play_inc(hand_idx: int, sacrifice_mids: Array, wrath_mids: Array = [], ctx: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_play_inc(pl, hand_idx, sacrifice_mids, wrath_mids, ctx)


@rpc("any_peer", "reliable")
func submit_woe_discard(indices: Array) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_submit_woe_discard(pl, indices)


@rpc("any_peer", "reliable")
func submit_noble_spell_like(noble_mid: int, verb: String, value: int, wrath_mids: Array, ctx: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.apply_noble_spell_like(pl, noble_mid, verb, value, wrath_mids, ctx) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_noble_revive(noble_mid: int, ctx: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.apply_noble_revive_from_crypt(pl, noble_mid, ctx) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_play_dethrone(hand_idx: int, noble_mids: Array = [], sacrifice_mids: Array = []) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_play_dethrone(pl, hand_idx, noble_mids, sacrifice_mids)


@rpc("any_peer", "reliable")
func submit_activate_noble(noble_mid: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.activate_noble(pl, noble_mid) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_activate_noble_with_insight(noble_mid: int, insight_target: int, insight_perm: Array = []) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.activate_noble_with_insight(pl, noble_mid, insight_target, insight_perm) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_aeoiu_ritual(noble_mid: int, grave_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.apply_aeoiu_ritual_from_crypt(pl, noble_mid, grave_idx) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_discard_draw(hand_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_discard_draw(pl, hand_idx)


@rpc("any_peer", "reliable")
func submit_end_turn(discard_indices: Array) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_end_turn(pl, discard_indices)


@rpc("any_peer", "reliable")
func submit_choose_mulligan(take_mulligan: bool) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_choose_mulligan(pl, take_mulligan)


@rpc("any_peer", "reliable")
func submit_mulligan_bottom(hand_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_mulligan_bottom(pl, hand_idx)


@rpc("any_peer", "reliable")
func request_play_again() -> void:
	if not multiplayer.is_server():
		return
	_start_match()


func _on_end_turn_pressed() -> void:
	if _insight_open:
		return
	if _sacrifice_selecting:
		_on_sacrifice_cancel_pressed()
	if _match == null and not _is_network_client():
		return
	if _is_network_client() and _last_snap.is_empty():
		return
	var snap: Dictionary = _last_snap
	if _selecting_end_discard:
		_confirm_end_turn_discard()
		return
	var hand: Array = snap.get("your_hand", [])
	var need := maxi(0, hand.size() - 7)
	if need == 0:
		if _is_network_client():
			submit_end_turn.rpc_id(1, [])
		else:
			_try_end_turn(_my_player_for_action(), [])
		return
	_selecting_end_discard = true
	_end_discard_needed = need
	_end_discard_picked.clear()
	_update_end_discard_status()
	_show_end_discard_modal()
	_rebuild_hand(hand)


func _on_discard_draw_pressed() -> void:
	if _insight_open:
		return
	if _sacrifice_selecting:
		return
	_mode_discard_draw = true
	status_label.text = "Click a card to discard for draw."
	if not _last_snap.is_empty():
		_rebuild_hand(_last_snap.get("your_hand", []))


func _on_mulligan_keep_pressed() -> void:
	if _last_snap.is_empty():
		return
	if _is_network_client():
		submit_choose_mulligan.rpc_id(1, false)
	else:
		_try_choose_mulligan(_my_player_for_action(), false)


func _on_mulligan_take_pressed() -> void:
	if _last_snap.is_empty():
		return
	if _is_network_client():
		submit_choose_mulligan.rpc_id(1, true)
	else:
		_try_choose_mulligan(_my_player_for_action(), true)


func _on_quit_to_menu_pressed() -> void:
	quit_confirm_dialog.popup_centered()


func _on_quit_to_menu_confirmed() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://main_menu.tscn")

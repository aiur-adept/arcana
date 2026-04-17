extends Control

const IncludedDecks = preload("res://included_decks.gd")
const CardTraits = preload("res://card_traits.gd")
const CornerPipDraw = preload("res://corner_pip_draw.gd")
const CARD_TEXT_FONT: Font = preload("res://fonts/Macondo-Regular.ttf")
const _ArcanaCpuOpponent = preload("res://arcana_cpu_opponent.gd")
const _GameSnapshotUtils = preload("res://game_snapshot_utils.gd")
const _InsightDnDSlot = preload("res://insight_dnd_slot.gd")
const _GameRitualFieldView = preload("res://game_ritual_field_view.gd")

var _cpu_opponent: RefCounted = _ArcanaCpuOpponent.new()
var _ritual_field: RefCounted

## Normal play: 1p vs CPU in one process (mock client/server — no second executable).
## Real PvP: set USE_NETWORK_MULTIPLAYER = true, or pass --arcana-network-host on the command line.

const USE_NETWORK_MULTIPLAYER := false
const PORT_MIN := 17777
const PORT_MAX := 17799
const DEFAULT_DECK_PATH := "user://decks/default_deck.json"
const SELECTED_DECK_PATH_FILE := "user://selected_deck_path.txt"
const PLAY_MODE_FILE := "user://arcana_play_mode.txt"
const CPU_ACTION_SEC := 1.618
const CARD_SCALE := 1.618
const HAND_CARD_W := 72.0 * CARD_SCALE
const HAND_CARD_H := 102.0 * CARD_SCALE
const HAND_CARD_FONT_SIZE := 21
const HAND_CARD_BADGE_FONT_SIZE := 15
const UI_BUTTON_MIN_HEIGHT := 48.0
const UI_BUTTON_PAD_X := 18.0
const UI_BUTTON_PAD_Y := 10.0
var _bound_port: int = PORT_MIN
var _deck_path: String = DEFAULT_DECK_PATH

@onready var status_label: Label = %StatusLabel
@onready var log_label: RichTextLabel = %LogLabel
@onready var left_action_panel: PanelContainer = %LeftActionPanel
@onready var left_action_hamburger_button: Button = %LeftActionHamburgerButton
@onready var left_action_expanded_panel: PanelContainer = %LeftActionExpandedPanel
@onready var left_action_close_button: Button = %LeftActionCloseButton
@onready var concede_button: Button = %ConcedeButton
@onready var exit_match_button: Button = %ExitMatchButton
@onready var hand_row: HBoxContainer = %HandRow
@onready var crypt_button: Button = %CryptButton
@onready var opp_crypt_button: Button = %OppCryptButton
@onready var abyss_button: Button = %AbyssButton
@onready var opp_abyss_button: Button = %OppAbyssButton
@onready var end_turn_button: Button = %EndTurnButton
@onready var bird_fight_button: Button = %BirdFightButton
@onready var discard_draw_button: Button = %DiscardDrawButton
@onready var field_you_cards: HBoxContainer = %FieldYouCards
@onready var field_opp_cards: HBoxContainer = %FieldOppCards
@onready var field_you_nobles: HBoxContainer = %FieldYouNobles
@onready var field_opp_nobles: HBoxContainer = %FieldOppNobles
@onready var field_you_birds: HBoxContainer = %FieldYouBirds
@onready var field_opp_birds: HBoxContainer = %FieldOppBirds
@onready var field_you_temples: HBoxContainer = %FieldYouTemples
@onready var field_opp_temples: HBoxContainer = %FieldOppTemples
@onready var you_stats_label: RichTextLabel = %YouStatsLabel
@onready var opp_stats_label: RichTextLabel = %OppStatsLabel
@onready var sacrifice_row: HBoxContainer = %SacrificeRow
@onready var sacrifice_hint: Label = %SacrificeHint
@onready var sacrifice_confirm_button: Button = %SacrificeConfirmButton
@onready var sacrifice_cancel_button: Button = %SacrificeCancelButton
@onready var quit_to_menu_button: Button = %QuitToMenuButton
@onready var pause_overlay: Control = %PauseOverlay
@onready var pause_return_button: Button = %PauseReturnButton
@onready var pause_quit_button: Button = %PauseQuitButton
@onready var concede_confirm_dialog: ConfirmationDialog = %ConcedeConfirmDialog
@onready var exit_confirm_dialog: ConfirmationDialog = %ExitConfirmDialog

var _host: bool = false
var _my_player: int = 0
var _goldfish: bool = false
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
const INC_PICK_SMRSK := 9
const INC_PICK_RMRSK := 10
const INC_PICK_BIRD_ATTACK := 11
const INC_PICK_BIRD_TARGET := 12
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
var _insight_top_order: Array = []
var _insight_bottom_order: Array = []
var _insight_overlay: Control
var _insight_cards_row: HBoxContainer
var _insight_cards_row_bottom: HBoxContainer
var _insight_hint_label: Label
var _insight_btn_confirm: Button
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
var _smrsk_selected_mid: int = -1
var _last_scion_prompt_id: int = -1

var _aeoiu_overlay: Control
var _aeoiu_crypt_row: VBoxContainer
var _aeoiu_noble_mid: int = -1

var _delpha_overlay: Control
var _delpha_ritual_row: VBoxContainer
var _delpha_crypt_row: VBoxContainer
var _delpha_temple_mid: int = -1
var _delpha_ritual_mid: int = -1
var _delpha_x: int = 0

var _sacrifice_for_temple: bool = false
var _insight_temple_mid: int = -1
var _gotha_picking: bool = false
var _gotha_temple_mid: int = -1

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
var _crypt_hover_popup: PanelContainer
var _crypt_hover_label: RichTextLabel
var _crypt_modal_overlay: Control
var _crypt_modal_list: VBoxContainer
var _crypt_modal_close_button: Button
var _crypt_modal_title: Label
var _crypt_modal_hint: Label
var _crypt_focus_opponent: bool = false
var _crypt_focus_zone: String = "crypt"
var _bird_attack_selected: Dictionary = {}
var _bird_defender_mid: int = -1
var _bird_assign_overlay: Control
var _bird_assign_hint: Label
var _bird_assign_row: HBoxContainer
var _bird_assign_confirm: Button
var _bird_assign_reset: Button
var _bird_assign_cancel: Button
var _bird_assign_remaining: int = 0
var _bird_damage_assign: Dictionary = {}


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
	_ritual_field = _GameRitualFieldView.new(self)
	set_multiplayer_authority(1)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.clip_text = true
	_build_insight_overlay()
	_build_burn_woe_revive_overlays()
	_build_hover_preview_panel()
	_build_game_end_modal()
	_build_end_discard_modal()
	_build_mulligan_bar()
	_build_crypt_ui()
	_build_bird_assign_overlay()
	_build_delpha_overlay()
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	bird_fight_button.visible = false
	discard_draw_button.pressed.connect(_on_discard_draw_pressed)
	sacrifice_confirm_button.pressed.connect(_on_sacrifice_confirm_pressed)
	sacrifice_cancel_button.pressed.connect(_on_sacrifice_cancel_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	left_action_hamburger_button.pressed.connect(_on_left_action_hamburger_pressed)
	left_action_close_button.pressed.connect(_on_left_action_close_pressed)
	concede_button.pressed.connect(_on_concede_pressed)
	exit_match_button.pressed.connect(_on_exit_match_pressed)
	pause_return_button.pressed.connect(_on_pause_return_pressed)
	pause_quit_button.pressed.connect(_on_pause_quit_pressed)
	concede_confirm_dialog.confirmed.connect(_on_concede_confirmed)
	exit_confirm_dialog.confirmed.connect(_on_exit_match_confirmed)
	pause_overlay.visible = false
	_apply_ui_button_padding(end_turn_button)
	_apply_ui_button_padding(bird_fight_button)
	_apply_ui_button_padding(discard_draw_button)
	_apply_ui_button_padding(concede_button)
	_apply_ui_button_padding(exit_match_button)
	_apply_ui_button_padding(crypt_button)
	_apply_ui_button_padding(opp_crypt_button)
	_apply_ui_button_padding(abyss_button)
	_apply_ui_button_padding(opp_abyss_button)
	_apply_ui_button_padding(sacrifice_confirm_button)
	_apply_ui_button_padding(sacrifice_cancel_button)
	_apply_ui_button_padding(quit_to_menu_button)
	_apply_ui_button_padding(pause_return_button)
	_apply_ui_button_padding(pause_quit_button)
	left_action_hamburger_button.custom_minimum_size = Vector2(38, 34)
	left_action_hamburger_button.add_theme_font_size_override("font_size", 20)
	left_action_close_button.custom_minimum_size = Vector2(34, 30)
	var left_panel_style := StyleBoxFlat.new()
	left_panel_style.bg_color = Color(0, 0, 0, 1)
	left_panel_style.border_color = Color(0.18, 0.18, 0.18, 1)
	left_panel_style.set_border_width_all(1)
	left_panel_style.set_corner_radius_all(8)
	left_action_expanded_panel.add_theme_stylebox_override("panel", left_panel_style)
	_set_left_action_expanded(false)
	crypt_button.mouse_entered.connect(_on_crypt_button_mouse_entered)
	crypt_button.mouse_exited.connect(_on_crypt_button_mouse_exited)
	crypt_button.pressed.connect(_on_crypt_button_pressed)
	opp_crypt_button.mouse_entered.connect(_on_opp_crypt_button_mouse_entered)
	opp_crypt_button.mouse_exited.connect(_on_opp_crypt_button_mouse_exited)
	opp_crypt_button.pressed.connect(_on_opp_crypt_button_pressed)
	abyss_button.mouse_entered.connect(_on_abyss_button_mouse_entered)
	abyss_button.mouse_exited.connect(_on_abyss_button_mouse_exited)
	abyss_button.pressed.connect(_on_abyss_button_pressed)
	opp_abyss_button.mouse_entered.connect(_on_opp_abyss_button_mouse_entered)
	opp_abyss_button.mouse_exited.connect(_on_opp_abyss_button_mouse_exited)
	opp_abyss_button.pressed.connect(_on_opp_abyss_button_pressed)
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
	_goldfish = _read_play_mode_goldfish()
	if _goldfish:
		status_label.text = "Goldfish — solo practice (no opponent)."
	else:
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
	if _goldfish:
		_match = ArcanaMatchState.new(cards.duplicate(true), [], true, rng, true)
	else:
		var p0_first := rng.randi_range(0, 1) == 0
		_match = ArcanaMatchState.new(cards.duplicate(true), cards.duplicate(true), p0_first, rng, false)
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
	back.color = Color(0, 0, 0, 1)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	_insight_overlay.add_child(back)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_insight_overlay.add_child(cc)
	var inner := VBoxContainer.new()
	cc.add_child(inner)
	var title := Label.new()
	title.text = "Insight — top of deck and bottom of library"
	inner.add_child(title)
	var h := HBoxContainer.new()
	_insight_btn_yours = Button.new()
	_insight_btn_yours.text = "Your deck"
	_insight_btn_opps = Button.new()
	_insight_btn_opps.text = "Opponent deck"
	_apply_ui_button_padding(_insight_btn_yours)
	_apply_ui_button_padding(_insight_btn_opps)
	h.add_child(_insight_btn_yours)
	h.add_child(_insight_btn_opps)
	inner.add_child(h)
	_insight_hint_label = Label.new()
	_insight_hint_label.custom_minimum_size = Vector2(480, 0)
	inner.add_child(_insight_hint_label)
	var lab_top := Label.new()
	lab_top.text = "Top (next draw left)"
	inner.add_child(lab_top)
	_insight_cards_row = HBoxContainer.new()
	_insight_cards_row.add_theme_constant_override("separation", 8)
	inner.add_child(_insight_cards_row)
	var lab_bot := Label.new()
	lab_bot.text = "Bottom of library (left shallow → right deep)"
	inner.add_child(lab_bot)
	_insight_cards_row_bottom = HBoxContainer.new()
	_insight_cards_row_bottom.add_theme_constant_override("separation", 8)
	inner.add_child(_insight_cards_row_bottom)
	var row2 := HBoxContainer.new()
	_insight_btn_confirm = Button.new()
	_insight_btn_confirm.text = "Confirm"
	_apply_ui_button_padding(_insight_btn_confirm)
	row2.add_child(_insight_btn_confirm)
	inner.add_child(row2)
	_insight_btn_yours.pressed.connect(_on_insight_target_yours)
	_insight_btn_opps.pressed.connect(_on_insight_target_opps)
	_insight_btn_confirm.pressed.connect(_on_insight_confirm_pressed)


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
	_apply_ui_button_padding(_tgt_left_btn)
	_apply_ui_button_padding(_tgt_right_btn)
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
	_apply_ui_button_padding(_burn_woe_confirm)
	_apply_ui_button_padding(_burn_woe_cancel)
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
	_apply_ui_button_padding(_revive_skip_btn)
	_apply_ui_button_padding(_revive_cancel_btn)
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
	_apply_ui_button_padding(ae_cancel)
	ae_row.add_child(ae_cancel)
	inner_a.add_child(ae_row)
	ae_cancel.pressed.connect(_on_aeoiu_cancel_pressed)


func _build_delpha_overlay() -> void:
	_delpha_overlay = Control.new()
	_delpha_overlay.name = "DelphaOverlay"
	_delpha_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_delpha_overlay.visible = false
	_delpha_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_delpha_overlay.z_index = 97
	add_child(_delpha_overlay)
	var back_d := ColorRect.new()
	back_d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back_d.color = Color(0, 0, 0, 0.55)
	_delpha_overlay.add_child(back_d)
	var ccd := CenterContainer.new()
	ccd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_delpha_overlay.add_child(ccd)
	var inner_d := VBoxContainer.new()
	inner_d.add_theme_constant_override("separation", 10)
	ccd.add_child(inner_d)
	var ld := Label.new()
	ld.text = "Delpha — choose one of your rituals to send to the abyss. Its power is X."
	inner_d.add_child(ld)
	_delpha_ritual_row = VBoxContainer.new()
	_delpha_ritual_row.add_theme_constant_override("separation", 6)
	inner_d.add_child(_delpha_ritual_row)
	_delpha_crypt_row = VBoxContainer.new()
	_delpha_crypt_row.add_theme_constant_override("separation", 6)
	inner_d.add_child(_delpha_crypt_row)
	var de_row := HBoxContainer.new()
	var de_cancel := Button.new()
	de_cancel.text = "Cancel"
	_apply_ui_button_padding(de_cancel)
	de_row.add_child(de_cancel)
	inner_d.add_child(de_row)
	de_cancel.pressed.connect(_on_delpha_cancel_pressed)


func _on_delpha_cancel_pressed() -> void:
	if _delpha_overlay:
		_delpha_overlay.visible = false
	_delpha_temple_mid = -1
	_delpha_ritual_mid = -1
	_delpha_x = 0
	end_turn_button.disabled = false
	discard_draw_button.disabled = false


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
	elif _burn_woe_mode == "tmrsk_woe":
		_pending_woe_target = y
	elif _burn_woe_mode == "woe" or _burn_woe_mode == "noble_woe" or _burn_woe_mode == "revive_woe":
		_pending_woe_target = y


func _on_burn_woe_right_pressed() -> void:
	var y := int(_last_snap.get("you", 0))
	if _burn_woe_mode == "burn" or _burn_woe_mode == "noble_burn" or _burn_woe_mode == "revive_burn":
		_pending_mill_target = 1 - y
	elif _burn_woe_mode == "tmrsk_woe":
		_pending_woe_target = 1 - y
	elif _burn_woe_mode == "woe" or _burn_woe_mode == "noble_woe" or _burn_woe_mode == "revive_woe":
		_pending_woe_target = 1 - y


func _on_burn_woe_confirm_pressed() -> void:
	if _burn_woe_mode == "tmrsk_woe":
		var ys := int(_last_snap.get("you", 0))
		var sid := int(_last_snap.get("scion_pending_id", -1))
		if _pending_woe_target == ys:
			_clear_burn_woe_overlay()
			_woe_self_picking = true
			_woe_self_need = _woe_discard_count_ui(_last_snap, 1, true)
			_woe_self_picked.clear()
			_inc_pick_phase = INC_PICK_WOE_SELF
			_burn_woe_mode = "tmrsk_woe_self"
			status_label.text = "Tmrsk Woe: tap %d card(s) to discard." % _woe_self_need
		else:
			var ctxt := {"scion_id": sid, "woe_target": _pending_woe_target}
			if _is_network_client():
				submit_scion_trigger_response.rpc_id(1, "accept", ctxt)
			else:
				if _match != null:
					_match.submit_scion_trigger_response(_my_player_for_action(), "accept", ctxt)
			_clear_incantation_flow_ui()
			_broadcast_sync(true)
		return
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
	var crypt: Array = _filtered_crypt_cards(_your_crypt_cards_from_snap(_last_snap), ["incantation", "dethrone"])
	var idx := 0
	for card in crypt:
		var b := Button.new()
		var v := str(card.get("verb", ""))
		var vv := int(card.get("value", 0))
		b.text = "%s %d (crypt #%d)" % [v, vv, idx]
		if v.to_lower() == "wrath":
			b.disabled = true
			b.tooltip_text = "Wrath cannot be selected by Revive."
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
	var idisc: Array = _filtered_crypt_cards(_your_crypt_cards_from_snap(_last_snap), ["incantation", "dethrone"])
	if crypt_idx < 0 or crypt_idx >= idisc.size():
		return
	var card: Dictionary = idisc[crypt_idx]
	var v := str(card.get("verb", "")).to_lower()
	if v == "wrath":
		status_label.text = "Wrath cannot be selected with Revive."
		return
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
		"z_index": 4096
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


func _read_play_mode_goldfish() -> bool:
	var f := FileAccess.open(PLAY_MODE_FILE, FileAccess.READ)
	if f == null:
		return false
	return f.get_as_text().strip_edges() == "goldfish"


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
	if trigger_cpu_check and not _is_network_pvp() and not _goldfish:
		_after_sync_local_cpu()


func _after_sync_local_cpu() -> void:
	if _match == null:
		return
	var s0 := _match.snapshot(0)
	var s1 := _match.snapshot(1)
	if int(s0.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return
	if bool(s1.get("woe_pending_you_respond", false)):
		call_deferred("_deferred_cpu_turn")
		return
	if bool(s1.get("scion_pending_you_respond", false)):
		call_deferred("_deferred_cpu_turn")
		return
	if bool(s0.get("mulligan_active", false)):
		if int(s0.get("current", -1)) == 1:
			call_deferred("_deferred_cpu_mulligan")
		return
	if int(s0.get("current", -1)) != 1:
		return
	call_deferred("_deferred_cpu_turn")


func _deferred_cpu_turn() -> void:
	await _cpu_opponent.run_turn(self)


func _deferred_cpu_mulligan() -> void:
	await _cpu_opponent.run_mulligan_step(self)


@rpc("authority", "reliable")
func sync_state(snap: Dictionary) -> void:
	_apply_snap(snap)


func _should_abort_sacrifice_for_snap(snap: Dictionary) -> bool:
	if int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
		return true
	if bool(snap.get("mulligan_active", false)):
		return true
	var you := int(snap.get("you", 0))
	if int(snap.get("current", -1)) != you:
		return true
	if _pending_inc_hand_idx < 0:
		return true
	var h: Array = snap.get("your_hand", []) as Array
	return _pending_inc_hand_idx >= h.size()


func _prune_sacrifice_picks_for_snap(snap: Dictionary) -> void:
	var yf: Array = snap.get("your_field", []) as Array
	var yok: Dictionary = {}
	for x in yf:
		yok[int(x.get("mid", -1))] = true
	for k in _sacrifice_selected_mids.keys().duplicate():
		if not yok.has(int(k)):
			_sacrifice_selected_mids.erase(k)
	var of: Array = snap.get("opp_field", []) as Array
	var ook: Dictionary = {}
	for x in of:
		ook[int(x.get("mid", -1))] = true
	for k2 in _wrath_selected_mids.keys().duplicate():
		if not ook.has(int(k2)):
			_wrath_selected_mids.erase(k2)


func _apply_snap(snap: Dictionary) -> void:
	_last_snap = snap
	if snap.is_empty():
		return
	_hide_card_hover_preview()
	if _insight_open:
		_clear_insight_ui()
	if _sacrifice_selecting and _should_abort_sacrifice_for_snap(snap):
		_clear_sacrifice_mode()
	if _burn_woe_overlay != null and _burn_woe_overlay.visible and _burn_woe_mode == "tmrsk_woe":
		_clear_burn_woe_overlay()
	if _delpha_overlay != null and _delpha_overlay.visible:
		if int(snap.get("current", -1)) != int(snap.get("you", 0)):
			_on_delpha_cancel_pressed()
	if _gotha_picking:
		if int(snap.get("current", -1)) != int(snap.get("you", 0)) or int(snap.get("phase", -1)) == int(ArcanaMatchState.Phase.GAME_OVER):
			_gotha_picking = false
			_gotha_temple_mid = -1
	var yp: int = int(snap.get("your_power", 0))
	var op: int = int(snap.get("opp_power", 0))
	var your_hand: Array = snap.get("your_hand", []) as Array
	var your_hand_n := your_hand.size()
	var opp_hand_n := int(snap.get("opp_hand", 0))
	var your_deck_n := int(snap.get("your_deck", 0))
	var opp_deck_n := int(snap.get("opp_deck", 0))
	you_stats_label.text = _format_player_stats("You", yp, your_hand_n, your_deck_n)
	if bool(snap.get("goldfish", false)):
		opp_stats_label.text = _format_player_stats("(no opponent)", op, opp_hand_n, opp_deck_n)
	else:
		opp_stats_label.text = _format_player_stats("Opponent", op, opp_hand_n, opp_deck_n)
	_update_crypt_button_and_popups(snap)
	if _sacrifice_selecting:
		_prune_sacrifice_picks_for_snap(snap)
	_rebuild_field_strips_from_snap(snap)
	var logs: Array = snap.get("log", [])
	var tail := ""
	for i in logs.size():
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
		bird_fight_button.disabled = true
		discard_draw_button.disabled = true
		_rebuild_hand(snap.get("your_hand", []))
		_hide_end_discard_modal()
		return
	_hide_mulligan_bar()
	_hide_game_end_modal()
	var mine := cur == you
	var scion_waiting := bool(snap.get("scion_pending_waiting", false))
	var scion_respond := bool(snap.get("scion_pending_you_respond", false))
	var ui_block := _sacrifice_selecting or _insight_open or _woe_self_picking or bool(snap.get("woe_pending_waiting", false)) or scion_waiting or scion_respond
	if _delpha_overlay != null and _delpha_overlay.visible:
		ui_block = true
	if _gotha_picking:
		ui_block = true
	if _burn_woe_overlay != null and _burn_woe_overlay.visible:
		ui_block = true
	if _revive_overlay != null and _revive_overlay.visible:
		ui_block = true
	if _bird_assign_overlay != null and _bird_assign_overlay.visible:
		ui_block = true
	if bool(snap.get("woe_pending_you_respond", false)):
		status_label.text = "Woe: choose %d card(s) from your hand to discard." % int(snap.get("woe_pending_amount", 0))
	else:
		_woe_self_picked.clear()
	if bool(snap.get("woe_pending_waiting", false)):
		status_label.text = "Waiting for opponent to discard for Woe…"
	if scion_waiting:
		status_label.text = "Waiting for opponent to resolve scion trigger…"
	if scion_respond:
		_show_scion_prompt_ui(snap)
	else:
		_last_scion_prompt_id = -1
	end_turn_button.disabled = not mine or ui_block
	bird_fight_button.disabled = not mine or ui_block or bool(snap.get("your_bird_fight_used", false))
	discard_draw_button.disabled = not mine or bool(snap.get("discard_draw_used", true)) or ui_block
	_rebuild_hand(snap.get("your_hand", []))
	if bool(snap.get("woe_pending_you_respond", false)):
		_update_woe_discard_status()
	elif _selecting_end_discard:
		_show_end_discard_modal()
	else:
		_hide_end_discard_modal()
	if _sacrifice_selecting:
		_update_inc_modal_ui()


func _format_player_stats(player_name: String, power: int, hand_n: int, deck_n: int) -> String:
	return "%s\nPower: [font_size=24]%d[/font_size]\nHand: %d\nDeck: %d" % [player_name, power, hand_n, deck_n]


func _end_game_ui(snap: Dictionary) -> void:
	var w: int = int(snap.get("winner", -1))
	var you: int = int(snap.get("you", 0))
	var msg := "Draw."
	var title := "Draw"
	if bool(snap.get("goldfish", false)):
		if bool(snap.get("empty_deck_end", false)) and w >= 0 and w != you:
			title = "Defeat"
			msg = "Your deck is empty."
		elif w == you:
			title = "Victory"
			msg = "You reached 20 ritual power."
		elif w >= 0:
			title = "Defeat"
			msg = "You conceded."
		else:
			msg = "Draw."
	else:
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
	bird_fight_button.disabled = true
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
	_apply_ui_button_padding(_game_end_play_again)
	_apply_ui_button_padding(_game_end_main_menu)
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
	_apply_ui_button_padding(_end_discard_confirm_button)
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
	_apply_ui_button_padding(_mulligan_keep_button)
	_apply_ui_button_padding(_mulligan_take_button)
	hb.add_child(_mulligan_take_button)
	_mulligan_keep_button.pressed.connect(_on_mulligan_keep_pressed)
	_mulligan_take_button.pressed.connect(_on_mulligan_take_pressed)


func _build_bird_assign_overlay() -> void:
	_bird_assign_overlay = Control.new()
	_bird_assign_overlay.name = "BirdAssignOverlay"
	_bird_assign_overlay.visible = false
	_bird_assign_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_bird_assign_overlay.z_index = 123
	_bird_assign_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bird_assign_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.64)
	_bird_assign_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bird_assign_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 240)
	center.add_child(panel)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.1, 0.13, 0.98)
	ps.border_color = Color(0.56, 0.86, 0.99)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", ps)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	_bird_assign_hint = Label.new()
	_bird_assign_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_bird_assign_hint)
	_bird_assign_row = HBoxContainer.new()
	_bird_assign_row.add_theme_constant_override("separation", 8)
	vb.add_child(_bird_assign_row)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vb.add_child(btn_row)
	_bird_assign_confirm = Button.new()
	_bird_assign_confirm.text = "Confirm damage"
	_bird_assign_confirm.disabled = true
	_apply_ui_button_padding(_bird_assign_confirm)
	_bird_assign_confirm.pressed.connect(_on_bird_assign_confirm_pressed)
	btn_row.add_child(_bird_assign_confirm)
	_bird_assign_reset = Button.new()
	_bird_assign_reset.text = "Reset"
	_apply_ui_button_padding(_bird_assign_reset)
	_bird_assign_reset.pressed.connect(_on_bird_assign_reset_pressed)
	btn_row.add_child(_bird_assign_reset)
	_bird_assign_cancel = Button.new()
	_bird_assign_cancel.text = "Cancel"
	_apply_ui_button_padding(_bird_assign_cancel)
	_bird_assign_cancel.pressed.connect(_on_bird_assign_cancel_pressed)
	btn_row.add_child(_bird_assign_cancel)


func _build_crypt_ui() -> void:
	_crypt_hover_popup = PanelContainer.new()
	_crypt_hover_popup.name = "CryptHoverPopup"
	_crypt_hover_popup.visible = false
	_crypt_hover_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crypt_hover_popup.z_index = 124
	_crypt_hover_popup.custom_minimum_size = Vector2(320, 0)
	add_child(_crypt_hover_popup)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.06, 0.06, 0.08, 1.0)
	hover_style.border_color = Color(0.7, 0.74, 0.82)
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(10)
	_crypt_hover_popup.add_theme_stylebox_override("panel", hover_style)
	var hover_margin := MarginContainer.new()
	hover_margin.add_theme_constant_override("margin_left", 12)
	hover_margin.add_theme_constant_override("margin_top", 10)
	hover_margin.add_theme_constant_override("margin_right", 12)
	hover_margin.add_theme_constant_override("margin_bottom", 10)
	_crypt_hover_popup.add_child(hover_margin)
	_crypt_hover_label = RichTextLabel.new()
	_crypt_hover_label.bbcode_enabled = false
	_crypt_hover_label.fit_content = true
	_crypt_hover_label.scroll_active = false
	_crypt_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_margin.add_child(_crypt_hover_label)

	_crypt_modal_overlay = Control.new()
	_crypt_modal_overlay.name = "CryptModalOverlay"
	_crypt_modal_overlay.visible = false
	_crypt_modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_crypt_modal_overlay.z_index = 130
	_crypt_modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_crypt_modal_overlay)
	var crypt_back := ColorRect.new()
	crypt_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crypt_back.color = Color(0, 0, 0, 1)
	crypt_back.mouse_filter = Control.MOUSE_FILTER_STOP
	_crypt_modal_overlay.add_child(crypt_back)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crypt_modal_overlay.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 360)
	cc.add_child(panel)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.09, 0.12, 1.0)
	pstyle.border_color = Color(0.72, 0.78, 0.9)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", pstyle)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	vb.add_child(title_row)
	_crypt_modal_title = Label.new()
	_crypt_modal_title.text = "Your crypt"
	_crypt_modal_title.add_theme_font_size_override("font_size", 22)
	_crypt_modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_crypt_modal_title)
	_crypt_modal_close_button = Button.new()
	_crypt_modal_close_button.text = "X"
	_crypt_modal_close_button.custom_minimum_size = Vector2(36, 32)
	_apply_ui_button_padding(_crypt_modal_close_button)
	_crypt_modal_close_button.pressed.connect(_hide_crypt_modal)
	title_row.add_child(_crypt_modal_close_button)
	_crypt_modal_hint = Label.new()
	_crypt_modal_hint.text = "Hover stacks for preview."
	vb.add_child(_crypt_modal_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_crypt_modal_list = VBoxContainer.new()
	_crypt_modal_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_crypt_modal_list)


func _your_crypt_cards_from_snap(snap: Dictionary) -> Array:
	return _GameSnapshotUtils.your_crypt_cards_from_snap(snap)


func _opp_crypt_cards_from_snap(snap: Dictionary) -> Array:
	return _GameSnapshotUtils.opp_crypt_cards_from_snap(snap)


func _your_abyss_cards_from_snap(snap: Dictionary) -> Array:
	return _GameSnapshotUtils.your_abyss_cards_from_snap(snap)


func _opp_abyss_cards_from_snap(snap: Dictionary) -> Array:
	return _GameSnapshotUtils.opp_abyss_cards_from_snap(snap)


func _active_crypt_cards_from_snap(snap: Dictionary) -> Array:
	if _crypt_focus_zone == "abyss":
		return _opp_abyss_cards_from_snap(snap) if _crypt_focus_opponent else _your_abyss_cards_from_snap(snap)
	return _opp_crypt_cards_from_snap(snap) if _crypt_focus_opponent else _your_crypt_cards_from_snap(snap)


func _filtered_crypt_cards(cards: Array, kinds: Array) -> Array:
	return _GameSnapshotUtils.filtered_crypt_cards(cards, kinds)


func _crypt_stack_entries(cards: Array) -> Array:
	return _GameSnapshotUtils.crypt_stack_entries(cards)


func _update_crypt_button_and_popups(snap: Dictionary) -> void:
	crypt_button.text = "Crypt (%d)" % _your_crypt_cards_from_snap(snap).size()
	opp_crypt_button.text = "Opponent crypt (%d)" % _opp_crypt_cards_from_snap(snap).size()
	abyss_button.text = "Abyss (%d)" % _your_abyss_cards_from_snap(snap).size()
	opp_abyss_button.text = "Opponent abyss (%d)" % _opp_abyss_cards_from_snap(snap).size()
	abyss_button.visible = _your_abyss_cards_from_snap(snap).size() > 0
	opp_abyss_button.visible = _opp_abyss_cards_from_snap(snap).size() > 0
	if _crypt_hover_popup.visible:
		_show_crypt_hover_popup()
	if _crypt_modal_overlay.visible:
		_rebuild_crypt_modal()


func _show_crypt_hover_popup() -> void:
	if _crypt_focus_zone == "crypt" or _crypt_focus_zone == "abyss":
		return
	if _crypt_modal_overlay.visible:
		return
	var cards := _active_crypt_cards_from_snap(_last_snap)
	var stacks := _crypt_stack_entries(cards)
	var pile_name := "abyss" if _crypt_focus_zone == "abyss" else "crypt"
	if stacks.is_empty():
		_crypt_hover_label.text = ("%s is empty." % pile_name.capitalize()) if not _crypt_focus_opponent else ("Opponent %s is empty." % pile_name)
	else:
		var lines: Array[String] = []
		var shown := mini(6, stacks.size())
		for i in shown:
			var d: Dictionary = stacks[i]
			lines.append("%s x%d" % [_card_label(d.get("card", {})), int(d.get("count", 0))])
		if stacks.size() > shown:
			lines.append("+%d more stacks" % (stacks.size() - shown))
		_crypt_hover_label.text = "\n".join(lines)
	_crypt_hover_popup.visible = true
	var source_btn: Button
	if _crypt_focus_zone == "abyss":
		source_btn = opp_abyss_button if _crypt_focus_opponent else abyss_button
	else:
		source_btn = opp_crypt_button if _crypt_focus_opponent else crypt_button
	var pos := source_btn.global_position + Vector2(0, source_btn.size.y + 8)
	var vp := get_viewport_rect().size
	var popup_size := _crypt_hover_popup.size
	if popup_size.x <= 0:
		popup_size.x = _crypt_hover_popup.custom_minimum_size.x
	if popup_size.y <= 0:
		popup_size.y = 140
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - popup_size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - popup_size.y - 8.0))
	_crypt_hover_popup.global_position = pos


func _hide_crypt_hover_popup() -> void:
	if _crypt_hover_popup != null:
		_crypt_hover_popup.visible = false


func _rebuild_crypt_modal() -> void:
	for c in _crypt_modal_list.get_children():
		c.queue_free()
	var pile_name := "abyss" if _crypt_focus_zone == "abyss" else "crypt"
	_crypt_modal_title.text = ("Opponent %s" % pile_name) if _crypt_focus_opponent else ("Your %s" % pile_name)
	_crypt_modal_hint.text = ("Known cards in opponent %s." % pile_name)
	if not _crypt_focus_opponent:
		_crypt_modal_hint.text = "Hover stacks for preview."
	var cards := _active_crypt_cards_from_snap(_last_snap)
	var stacks := _crypt_stack_entries(cards)
	if stacks.is_empty():
		var empty := Label.new()
		empty.text = "No cards in %s." % pile_name
		_crypt_modal_list.add_child(empty)
		return
	for d in stacks:
		var card: Dictionary = d.get("card", {})
		var count := int(d.get("count", 0))
		var row_btn := Button.new()
		row_btn.text = "%s x%d" % [_card_label(card), count]
		row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_ui_button_padding(row_btn)
		row_btn.mouse_entered.connect(func() -> void:
			_show_card_hover_preview(card.duplicate(true))
		)
		row_btn.mouse_exited.connect(func() -> void:
			_hide_card_hover_preview()
		)
		_crypt_modal_list.add_child(row_btn)


func _show_crypt_modal() -> void:
	_hide_crypt_hover_popup()
	_rebuild_crypt_modal()
	_crypt_modal_overlay.visible = true
	_crypt_modal_close_button.grab_focus()


func _hide_crypt_modal() -> void:
	_crypt_modal_overlay.visible = false
	_hide_card_hover_preview()


func _on_crypt_button_mouse_entered() -> void:
	_crypt_focus_zone = "crypt"
	_crypt_focus_opponent = false
	_show_crypt_hover_popup()


func _on_crypt_button_mouse_exited() -> void:
	_hide_crypt_hover_popup()


func _on_crypt_button_pressed() -> void:
	_crypt_focus_zone = "crypt"
	_crypt_focus_opponent = false
	_show_crypt_modal()


func _on_opp_crypt_button_mouse_entered() -> void:
	_crypt_focus_zone = "crypt"
	_crypt_focus_opponent = true
	_show_crypt_hover_popup()


func _on_opp_crypt_button_mouse_exited() -> void:
	_hide_crypt_hover_popup()


func _on_opp_crypt_button_pressed() -> void:
	_crypt_focus_zone = "crypt"
	_crypt_focus_opponent = true
	_show_crypt_modal()


func _on_abyss_button_mouse_entered() -> void:
	_crypt_focus_zone = "abyss"
	_crypt_focus_opponent = false
	_show_crypt_hover_popup()


func _on_abyss_button_mouse_exited() -> void:
	_hide_crypt_hover_popup()


func _on_abyss_button_pressed() -> void:
	_crypt_focus_zone = "abyss"
	_crypt_focus_opponent = false
	_show_crypt_modal()


func _on_opp_abyss_button_mouse_entered() -> void:
	_crypt_focus_zone = "abyss"
	_crypt_focus_opponent = true
	_show_crypt_hover_popup()


func _on_opp_abyss_button_mouse_exited() -> void:
	_hide_crypt_hover_popup()


func _on_opp_abyss_button_pressed() -> void:
	_crypt_focus_zone = "abyss"
	_crypt_focus_opponent = true
	_show_crypt_modal()


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
	_rebuild_field_strips_from_snap(_last_snap)
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
	_rebuild_field_strips_from_snap(_last_snap)
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
	_rebuild_field_strips_from_snap(_last_snap)
	_rebuild_hand(_last_snap.get("your_hand", []))
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _clear_sacrifice_mode() -> void:
	_sacrifice_for_temple = false
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
	_smrsk_selected_mid = -1
	_bird_attack_selected.clear()
	_bird_defender_mid = -1
	if _bird_assign_overlay != null:
		_bird_assign_overlay.visible = false
	sacrifice_row.visible = false
	sacrifice_confirm_button.text = "Confirm sacrifice"
	sacrifice_cancel_button.text = "Cancel"
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
	elif _inc_pick_phase == INC_PICK_SMRSK:
		sacrifice_confirm_button.disabled = _smrsk_selected_mid < 0
	elif _inc_pick_phase == INC_PICK_RMRSK:
		sacrifice_confirm_button.disabled = false
	elif _inc_pick_phase == INC_PICK_BIRD_ATTACK:
		sacrifice_confirm_button.disabled = _bird_attack_selected.is_empty()
	elif _inc_pick_phase == INC_PICK_BIRD_TARGET:
		sacrifice_confirm_button.disabled = _bird_defender_mid < 0


func _show_scion_prompt_ui(snap: Dictionary) -> void:
	var sid := int(snap.get("scion_pending_id", -1))
	if sid >= 0 and sid == _last_scion_prompt_id:
		return
	_last_scion_prompt_id = sid
	var st := str(snap.get("scion_pending_type", ""))
	if st == "rmrsk_draw":
		_sacrifice_selecting = true
		_inc_pick_phase = INC_PICK_RMRSK
		sacrifice_row.visible = true
		sacrifice_confirm_button.text = "Draw 1"
		sacrifice_cancel_button.text = "Skip"
		sacrifice_hint.text = "Rmrsk: after Insight, draw a card?"
		_update_inc_modal_ui()
		_rebuild_hand(snap.get("your_hand", []))
		return
	if st == "smrsk_burn":
		_sacrifice_selecting = true
		_inc_pick_phase = INC_PICK_SMRSK
		_smrsk_selected_mid = -1
		sacrifice_row.visible = true
		sacrifice_confirm_button.text = "Sacrifice and Burn self"
		sacrifice_cancel_button.text = "Skip"
		sacrifice_hint.text = "Smrsk: choose one ritual to sacrifice; then Burn yourself by its power."
		_update_inc_modal_ui()
		_rebuild_field_strips_from_snap(snap)
		return
	if st == "tmrsk_woe":
		_burn_woe_mode = "tmrsk_woe"
		_pending_woe_target = int(snap.get("you", 0))
		_burn_woe_title.text = "Tmrsk — Woe 1: who discards?"
		_tgt_left_btn.text = "You"
		_tgt_right_btn.text = "Opponent"
		_burn_woe_hint.text = "Choose target, then confirm."
		_burn_woe_overlay.visible = true
		_inc_pick_phase = INC_PICK_WOE_TGT
		end_turn_button.disabled = true
		discard_draw_button.disabled = true


func _on_sacrifice_field_clicked(mid: int) -> void:
	if not _sacrifice_selecting:
		return
	if _inc_pick_phase != INC_PICK_SAC and _inc_pick_phase != INC_PICK_YTTR:
		if _inc_pick_phase == INC_PICK_SMRSK:
			_smrsk_selected_mid = -1 if _smrsk_selected_mid == mid else mid
			_update_inc_modal_ui()
			_rebuild_field_strips_from_snap(_last_snap)
		return
	if _sacrifice_selected_mids.has(mid):
		_sacrifice_selected_mids.erase(mid)
	else:
		_sacrifice_selected_mids[mid] = true
	_update_inc_modal_ui()
	_rebuild_field_strips_from_snap(_last_snap)


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
	_rebuild_field_strips_from_snap(_last_snap)


func _on_bird_attacker_clicked(mid: int) -> void:
	if not _sacrifice_selecting or _inc_pick_phase != INC_PICK_BIRD_ATTACK:
		return
	if _bird_attack_selected.has(mid):
		_bird_attack_selected.erase(mid)
	else:
		_bird_attack_selected[mid] = true
	_update_inc_modal_ui()
	_rebuild_field_strips_from_snap(_last_snap)


func _on_bird_target_clicked(mid: int) -> void:
	if not _sacrifice_selecting or _inc_pick_phase != INC_PICK_BIRD_TARGET:
		return
	_bird_defender_mid = mid
	_update_inc_modal_ui()
	_rebuild_field_strips_from_snap(_last_snap)


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
	_rebuild_field_strips_from_snap(_last_snap)
	_rebuild_hand(_last_snap.get("your_hand", []))


func _on_dethrone_field_clicked(mid: int) -> void:
	if not _sacrifice_selecting or _inc_pick_phase != INC_PICK_DETHRONE:
		return
	_dethrone_selected_mid = mid
	_update_inc_modal_ui()
	_rebuild_field_strips_from_snap(_last_snap)


func _submit_inc_play(sac: Array, wrath_mids: Array) -> void:
	_submit_inc_play_full(sac, wrath_mids, {})


func _submit_inc_play_full(sac: Array, wrath_mids: Array, ctx: Dictionary = {}) -> void:
	if _is_network_client():
		submit_play_inc.rpc_id(1, _pending_inc_hand_idx, sac, wrath_mids, ctx)
		_clear_incantation_flow_ui()
		return
	if _match == null:
		return
	var perr := _match.play_incantation(_my_player_for_action(), _pending_inc_hand_idx, sac, wrath_mids, ctx)
	if perr != "ok":
		status_label.text = "Could not play incantation (%s)." % perr
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


func _submit_noble_activate_with_insight(noble_mid: int, insight_target: int, insight_top: Array, insight_bottom: Array) -> void:
	if _is_network_client():
		submit_activate_noble_with_insight.rpc_id(1, noble_mid, insight_target, insight_top, insight_bottom)
		_clear_insight_ui()
		return
	if _match == null:
		return
	if _match.activate_noble_with_insight(_my_player_for_action(), noble_mid, insight_target, insight_top, insight_bottom) != "ok":
		status_label.text = "Could not activate noble."
		return
	_clear_insight_ui()
	_broadcast_sync(true)


func _submit_temple_phaedra_insight(temple_mid: int, insight_target: int, insight_top: Array, insight_bottom: Array) -> void:
	if _is_network_client():
		submit_temple_phaedra_insight.rpc_id(1, temple_mid, insight_target, insight_top, insight_bottom)
		_clear_insight_ui()
		return
	if _match == null:
		return
	if _match.apply_temple_phaedra_insight(_my_player_for_action(), temple_mid, insight_target, insight_top, insight_bottom) != "ok":
		status_label.text = "Could not activate Phaedra."
		return
	_clear_insight_ui()
	_broadcast_sync(true)


func _begin_insight_ui(hand_idx: int, n: int, sac_mids: Array, noble_mid: int = -1, revive_crypt_idx: int = -1, temple_mid: int = -1) -> void:
	_insight_hand_idx = hand_idx
	_insight_noble_mid = noble_mid
	_insight_temple_mid = temple_mid
	_insight_revive_crypt_idx = revive_crypt_idx
	_insight_n = n
	_insight_sac = sac_mids.duplicate()
	_pending_inc_hand_idx = hand_idx
	if _match == null:
		return
	_insight_open = true
	_insight_target = int(_last_snap.get("you", 0))
	_insight_reset_orders_for_current_deck()
	_insight_overlay.visible = true
	end_turn_button.disabled = true
	discard_draw_button.disabled = true
	_insight_refresh_insight_panel()
	_rebuild_hand(_last_snap.get("your_hand", []))


func _clear_insight_ui() -> void:
	_hide_card_hover_preview()
	if _insight_overlay:
		_insight_overlay.visible = false
	_insight_open = false
	_insight_hand_idx = -1
	_insight_noble_mid = -1
	_insight_temple_mid = -1
	_insight_revive_crypt_idx = -1
	_insight_sac.clear()
	_insight_top_order.clear()
	_insight_bottom_order.clear()
	for c in _insight_cards_row.get_children():
		c.queue_free()
	for c in _insight_cards_row_bottom.get_children():
		c.queue_free()


func _insight_reset_orders_for_current_deck() -> void:
	if _match == null:
		return
	var peek: Array = _match.insight_peek_top_cards(_insight_target, _insight_n)
	_insight_top_order.clear()
	_insight_bottom_order.clear()
	for i in peek.size():
		_insight_top_order.append(i)


func _insight_refresh_insight_panel() -> void:
	if _match == null:
		return
	for c in _insight_cards_row.get_children():
		c.queue_free()
	for c in _insight_cards_row_bottom.get_children():
		c.queue_free()
	var peek: Array = _match.insight_peek_top_cards(_insight_target, _insight_n)
	var take: int = peek.size()
	if _insight_top_order.size() + _insight_bottom_order.size() != take:
		_insight_reset_orders_for_current_deck()
		peek = _match.insight_peek_top_cards(_insight_target, _insight_n)
		take = peek.size()
	var insight_card_w := 54.0 * CARD_SCALE * 2.0
	var insight_card_h := 78.0 * CARD_SCALE * 2.0
	if _insight_top_order.is_empty() and take > 0:
		var ph: Panel = _insight_make_insight_slot(peek, -1, "top", 0, insight_card_w, insight_card_h, true)
		_insight_cards_row.add_child(ph)
	else:
		for si in range(_insight_top_order.size()):
			var oi: int = int(_insight_top_order[si])
			var p: Panel = _insight_make_insight_slot(peek, oi, "top", si, insight_card_w, insight_card_h, false)
			_insight_cards_row.add_child(p)
		var tail_t: Panel = _insight_make_insight_slot(peek, -1, "top", _insight_top_order.size(), insight_card_w * 0.45, insight_card_h, true)
		var lt := tail_t.find_child("CardLbl", true, false)
		if lt:
			lt.text = "+"
		_insight_cards_row.add_child(tail_t)
	if _insight_bottom_order.is_empty() and take > 0:
		var phb: Panel = _insight_make_insight_slot(peek, -1, "bottom", 0, insight_card_w, insight_card_h, true)
		_insight_cards_row_bottom.add_child(phb)
	else:
		for si in range(_insight_bottom_order.size()):
			var oib: int = int(_insight_bottom_order[si])
			var pb: Panel = _insight_make_insight_slot(peek, oib, "bottom", si, insight_card_w, insight_card_h, false)
			_insight_cards_row_bottom.add_child(pb)
		var tail_b: Panel = _insight_make_insight_slot(peek, -1, "bottom", _insight_bottom_order.size(), insight_card_w * 0.45, insight_card_h, true)
		var lb := tail_b.find_child("CardLbl", true, false)
		if lb:
			lb.text = "+"
		_insight_cards_row_bottom.add_child(tail_b)
	if take == 0:
		_insight_hint_label.text = "No cards left in that deck."
	elif take == 1:
		_insight_hint_label.text = "Drag between top and bottom rows, or swap within a row. Confirm when done."
	else:
		_insight_hint_label.text = "Top row: next draw is left. Bottom row: left shallow, right deep. Drag between rows or swap."
	_insight_btn_confirm.disabled = false


func _insight_make_insight_slot(peek: Array, orig_idx: int, zone: String, slot_idx: int, cw: float, ch: float, empty_ph: bool) -> Panel:
	var p: Panel = _InsightDnDSlot.new()
	p.game = self
	p.insight_zone = zone
	p.slot_index = slot_idx
	p.can_drag = not empty_ph
	p.custom_minimum_size = Vector2(cw, ch)
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(2)
	sb.bg_color = Color(0.12, 0.14, 0.2) if not empty_ph else Color(0.1, 0.11, 0.14)
	sb.border_color = Color(0.7, 0.75, 0.95) if zone == "top" else Color(0.55, 0.72, 0.6)
	p.add_theme_stylebox_override("panel", sb)
	var cctr := CenterContainer.new()
	cctr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cctr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(cctr)
	var lbl := Label.new()
	lbl.name = "CardLbl"
	if empty_ph:
		lbl.text = "…" if zone == "top" else "…"
	else:
		lbl.text = _card_label(peek[orig_idx])
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", CARD_TEXT_FONT)
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cctr.add_child(lbl)
	if not empty_ph and orig_idx >= 0 and typeof(peek[orig_idx]) == TYPE_DICTIONARY:
		var hc: Dictionary = (peek[orig_idx] as Dictionary).duplicate(true)
		p.mouse_entered.connect(func() -> void:
			_show_card_hover_preview(hc)
		)
		p.mouse_exited.connect(func() -> void:
			_hide_card_hover_preview()
		)
	return p


func _insight_handle_drop(from_z: String, from_i: int, to_z: String, to_i: int) -> void:
	if not _insight_open or _match == null:
		return
	var arr_f: Array = _insight_top_order if from_z == "top" else _insight_bottom_order
	var arr_t: Array = _insight_top_order if to_z == "top" else _insight_bottom_order
	if from_i < 0 or from_i >= arr_f.size():
		return
	if to_i < 0:
		return
	if from_z == to_z:
		if from_i == to_i:
			return
		if to_i > arr_t.size():
			return
		if to_i == arr_t.size():
			var tv: Variant = arr_f[from_i]
			arr_f.remove_at(from_i)
			arr_f.append(tv)
			_insight_refresh_insight_panel()
			return
		var t: Variant = arr_f[from_i]
		arr_f[from_i] = arr_f[to_i]
		arr_f[to_i] = t
	else:
		var v: Variant = arr_f[from_i]
		arr_f.remove_at(from_i)
		var ins: int = clampi(to_i, 0, arr_t.size())
		arr_t.insert(ins, v)
	_insight_refresh_insight_panel()


func _on_insight_target_yours() -> void:
	if not _insight_open:
		return
	_insight_target = int(_last_snap.get("you", 0))
	_insight_reset_orders_for_current_deck()
	_insight_refresh_insight_panel()


func _on_insight_target_opps() -> void:
	if not _insight_open:
		return
	_insight_target = 1 - int(_last_snap.get("you", 0))
	_insight_reset_orders_for_current_deck()
	_insight_refresh_insight_panel()


func _on_insight_confirm_pressed() -> void:
	if not _insight_open or _match == null:
		return
	var peek: Array = _match.insight_peek_top_cards(_insight_target, _insight_n)
	var take: int = peek.size()
	var top_a: Array = []
	var bot_a: Array = []
	if take == 0:
		pass
	else:
		var ok := _insight_top_order.size() + _insight_bottom_order.size() == take
		if ok:
			var seen: Dictionary = {}
			for x in _insight_top_order:
				var v := int(x)
				if v < 0 or v >= take or seen.has(v):
					ok = false
					break
				seen[v] = true
			for x in _insight_bottom_order:
				var v2 := int(x)
				if v2 < 0 or v2 >= take or seen.has(v2):
					ok = false
					break
				seen[v2] = true
			ok = ok and seen.size() == take
		if ok:
			top_a = _insight_top_order.duplicate()
			bot_a = _insight_bottom_order.duplicate()
		else:
			for i in take:
				top_a.append(i)
	if _insight_temple_mid >= 0:
		_submit_temple_phaedra_insight(_insight_temple_mid, _insight_target, top_a, bot_a)
		return
	if _insight_noble_mid >= 0:
		_submit_noble_activate_with_insight(_insight_noble_mid, _insight_target, top_a, bot_a)
		return
	if _insight_revive_crypt_idx >= 0:
		var ctxr := {"revive_steps": [{"revive_skip": false, "revive_crypt_idx": _insight_revive_crypt_idx, "nested": {"insight_target": _insight_target, "insight_top": top_a, "insight_bottom": bot_a}}]}
		if _revive_ui_for_noble_mid >= 0:
			_finalize_revive_cast(ctxr)
		else:
			_submit_inc_play_full(_insight_sac, [], ctxr)
		return
	_submit_inc_play_full(_insight_sac, [], {"insight_target": _insight_target, "insight_top": top_a, "insight_bottom": bot_a})


func _on_bird_fight_pressed() -> void:
	_start_bird_fight_from_mid(-1)


func _start_bird_fight_from_mid(initial_mid: int) -> void:
	if _match == null and not _is_network_client():
		return
	if _is_network_client() and _last_snap.is_empty():
		return
	var snap: Dictionary = _last_snap
	if int(snap.get("current", -1)) != int(snap.get("you", -2)):
		return
	if bool(snap.get("your_bird_fight_used", false)):
		status_label.text = "You already used bird fight this turn."
		return
	var yours: Array = snap.get("your_birds", []) as Array
	var opp: Array = snap.get("opp_birds", []) as Array
	if yours.is_empty() or opp.is_empty():
		status_label.text = "Bird fight requires at least one bird on each side."
		return
	_sacrifice_selecting = true
	_inc_pick_phase = INC_PICK_BIRD_ATTACK
	_bird_attack_selected.clear()
	if initial_mid >= 0:
		_bird_attack_selected[initial_mid] = true
	_bird_defender_mid = -1
	sacrifice_row.visible = true
	sacrifice_confirm_button.text = "Select target"
	sacrifice_cancel_button.text = "Cancel"
	sacrifice_hint.text = "Bird fight: choose one or more of your birds to attack."
	_update_inc_modal_ui()
	_rebuild_field_strips_from_snap(_last_snap)


func _bird_name_by_mid(arr: Array, mid: int) -> String:
	for b in arr:
		var bd := b as Dictionary
		if int(bd.get("mid", -1)) == mid:
			return str(bd.get("name", "Bird"))
	return "Bird"


func _open_bird_assign_overlay() -> void:
	var snap: Dictionary = _last_snap
	var opp_birds: Array = snap.get("opp_birds", []) as Array
	var target := _bird_name_by_mid(opp_birds, _bird_defender_mid)
	var target_power := 0
	for b in opp_birds:
		var bd := b as Dictionary
		if int(bd.get("mid", -1)) == _bird_defender_mid:
			target_power = int(bd.get("power", 0))
			break
	for c in _bird_assign_row.get_children():
		c.queue_free()
	_bird_damage_assign.clear()
	_bird_assign_remaining = target_power
	for k in _bird_attack_selected.keys():
		_bird_damage_assign[int(k)] = 0
	for k in _bird_attack_selected.keys():
		var mid := int(k)
		var b := Button.new()
		b.name = "BirdAssign_%d" % mid
		var mid_cap := mid
		b.pressed.connect(func() -> void:
			if _bird_assign_remaining <= 0:
				return
			_bird_damage_assign[mid_cap] = int(_bird_damage_assign.get(mid_cap, 0)) + 1
			_bird_assign_remaining -= 1
			_refresh_bird_assign_ui(target)
		)
		_apply_ui_button_padding(b)
		_bird_assign_row.add_child(b)
	_refresh_bird_assign_ui(target)
	_bird_assign_overlay.visible = true


func _refresh_bird_assign_ui(target_name: String) -> void:
	_bird_assign_hint.text = "Assign %d incoming damage from %s across your attacking birds." % [_bird_assign_remaining, target_name]
	for c in _bird_assign_row.get_children():
		if not (c is Button):
			continue
		var b := c as Button
		var mid := int(str(b.name).get_slice("_", 1))
		var nm := _bird_name_by_mid(_last_snap.get("your_birds", []) as Array, mid)
		b.text = "%s: %d" % [nm, int(_bird_damage_assign.get(mid, 0))]
	_bird_assign_confirm.disabled = _bird_assign_remaining != 0


func _on_bird_assign_reset_pressed() -> void:
	var target := _bird_name_by_mid(_last_snap.get("opp_birds", []) as Array, _bird_defender_mid)
	_bird_assign_remaining = 0
	for k in _bird_attack_selected.keys():
		_bird_damage_assign[int(k)] = 0
	var opp_birds: Array = _last_snap.get("opp_birds", []) as Array
	for b in opp_birds:
		var bd := b as Dictionary
		if int(bd.get("mid", -1)) == _bird_defender_mid:
			_bird_assign_remaining = int(bd.get("power", 0))
			break
	_refresh_bird_assign_ui(target)


func _on_bird_assign_confirm_pressed() -> void:
	if _bird_assign_remaining != 0:
		return
	var attackers: Array = []
	for k in _bird_attack_selected.keys():
		attackers.append(int(k))
	var assign := _bird_damage_assign.duplicate(true)
	_bird_assign_overlay.visible = false
	if _is_network_client():
		submit_bird_fight.rpc_id(1, attackers, _bird_defender_mid, assign)
	else:
		_try_resolve_bird_fight(_my_player_for_action(), attackers, _bird_defender_mid, assign)
	_clear_sacrifice_mode()


func _on_bird_assign_cancel_pressed() -> void:
	_bird_assign_overlay.visible = false
	_clear_sacrifice_mode()
	_rebuild_field_strips_from_snap(_last_snap)


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
	if _inc_pick_phase == INC_PICK_SMRSK:
		if _smrsk_selected_mid < 0:
			return
		var sid := int(_last_snap.get("scion_pending_id", -1))
		var ctxs := {"scion_id": sid, "ritual_mid": _smrsk_selected_mid}
		if _is_network_client():
			submit_scion_trigger_response.rpc_id(1, "accept", ctxs)
		else:
			if _match != null:
				_match.submit_scion_trigger_response(_my_player_for_action(), "accept", ctxs)
		_clear_sacrifice_mode()
		_broadcast_sync(true)
		return
	if _inc_pick_phase == INC_PICK_RMRSK:
		var sidr := int(_last_snap.get("scion_pending_id", -1))
		var ctxr := {"scion_id": sidr}
		if _is_network_client():
			submit_scion_trigger_response.rpc_id(1, "accept", ctxr)
		else:
			if _match != null:
				_match.submit_scion_trigger_response(_my_player_for_action(), "accept", ctxr)
		_clear_sacrifice_mode()
		_broadcast_sync(true)
		return
	if _inc_pick_phase == INC_PICK_BIRD_ATTACK:
		if _bird_attack_selected.is_empty():
			return
		_inc_pick_phase = INC_PICK_BIRD_TARGET
		sacrifice_confirm_button.text = "Assign damage"
		sacrifice_hint.text = "Bird fight: choose one opponent bird target."
		_update_inc_modal_ui()
		_rebuild_field_strips_from_snap(_last_snap)
		return
	if _inc_pick_phase == INC_PICK_BIRD_TARGET:
		if _bird_defender_mid < 0:
			return
		_open_bird_assign_overlay()
		return
	if _inc_pick_phase == INC_PICK_SAC:
		var sumv := _sacrifice_selected_sum(_last_snap)
		if sumv < _sacrifice_need:
			return
		var sac: Array = []
		for k in _sacrifice_selected_mids.keys():
			sac.append(int(k))
		if _sacrifice_for_temple:
			var hi_t := _pending_inc_hand_idx
			_clear_sacrifice_mode()
			if _is_network_client():
				submit_play_temple.rpc_id(1, hi_t, sac)
			else:
				_try_play_temple(_my_player_for_action(), hi_t, sac)
			_broadcast_sync(true)
			return
		if _pending_dethrone_hand_idx >= 0:
			var dhi := _pending_dethrone_hand_idx
			_enter_dethrone_mode(dhi, sac)
			return
		var hand: Array = _last_snap.get("your_hand", [])
		if _pending_inc_hand_idx < 0 or _pending_inc_hand_idx >= hand.size():
			status_label.text = "That card is no longer in your hand — cancel and try again."
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
			_rebuild_field_strips_from_snap(_last_snap)
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
	if _inc_pick_phase == INC_PICK_SMRSK:
		var sid2 := int(_last_snap.get("scion_pending_id", -1))
		var ctx_skip := {"scion_id": sid2}
		if _is_network_client():
			submit_scion_trigger_response.rpc_id(1, "skip", ctx_skip)
		else:
			if _match != null:
				_match.submit_scion_trigger_response(_my_player_for_action(), "skip", ctx_skip)
		_clear_sacrifice_mode()
		_broadcast_sync(true)
		return
	if _inc_pick_phase == INC_PICK_RMRSK:
		var sidr2 := int(_last_snap.get("scion_pending_id", -1))
		var ctx_skip_r := {"scion_id": sidr2}
		if _is_network_client():
			submit_scion_trigger_response.rpc_id(1, "skip", ctx_skip_r)
		else:
			if _match != null:
				_match.submit_scion_trigger_response(_my_player_for_action(), "skip", ctx_skip_r)
		_clear_sacrifice_mode()
		_broadcast_sync(true)
		return
	_clear_sacrifice_mode()
	if not _last_snap.is_empty():
		_apply_snap(_last_snap)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _insight_open:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and _sacrifice_selecting:
		get_viewport().set_input_as_handled()
		_on_sacrifice_cancel_pressed()
		return
	if event.is_action_pressed("ui_cancel") and _crypt_modal_overlay != null and _crypt_modal_overlay.visible:
		get_viewport().set_input_as_handled()
		_hide_crypt_modal()
		return

func _rebuild_field_strips_from_snap(snap: Dictionary) -> void:
	var your_rituals: Array = snap.get("your_field", []) as Array
	var opp_rituals: Array = snap.get("opp_field", []) as Array
	var your_nobles: Array = snap.get("your_nobles", []) as Array
	var opp_nobles: Array = snap.get("opp_nobles", []) as Array
	var your_birds: Array = snap.get("your_birds", []) as Array
	var opp_birds: Array = snap.get("opp_birds", []) as Array
	var your_temples: Array = snap.get("your_temples", []) as Array
	var opp_temples: Array = snap.get("opp_temples", []) as Array
	_rebuild_ritual_field(field_you_cards, your_rituals, true)
	_rebuild_ritual_field(field_opp_cards, opp_rituals, false)
	_ritual_field.rebuild_noble_field(field_you_nobles, your_nobles, true)
	_ritual_field.rebuild_noble_field(field_opp_nobles, opp_nobles, false)
	_ritual_field.rebuild_bird_field(field_you_birds, your_birds, true)
	_ritual_field.rebuild_bird_field(field_opp_birds, opp_birds, false)
	_ritual_field.rebuild_temple_field(field_you_temples, your_temples, true)
	_ritual_field.rebuild_temple_field(field_opp_temples, opp_temples, false)
	_set_zone_visible(field_you_nobles, not your_nobles.is_empty())
	_set_zone_visible(field_opp_nobles, not opp_nobles.is_empty())
	_set_zone_visible(field_you_birds, not your_birds.is_empty())
	_set_zone_visible(field_opp_birds, not opp_birds.is_empty())
	_set_zone_visible(field_you_temples, not your_temples.is_empty())
	_set_zone_visible(field_opp_temples, not opp_temples.is_empty())


func _rebuild_ritual_field(row: HBoxContainer, field: Variant, ours: bool) -> void:
	_ritual_field.rebuild_ritual_field(row, field, ours)


func _set_zone_visible(zone_row: HBoxContainer, zone_visible: bool) -> void:
	var zone_col := zone_row.get_parent()
	if zone_col is CanvasItem:
		(zone_col as CanvasItem).visible = zone_visible



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
	if (_last_snap.get("your_ritual_crypt_cards", []) as Array).is_empty():
		status_label.text = "No rituals in your crypt."
		return
	if _match != null and not _is_network_client() and not _match.can_activate_noble(_my_player_for_action(), noble_mid):
		status_label.text = "Cannot use Aeoiu right now."
		return
	_aeoiu_noble_mid = noble_mid
	for c in _aeoiu_crypt_row.get_children():
		c.queue_free()
	var rg: Array = _filtered_crypt_cards(_your_crypt_cards_from_snap(_last_snap), ["ritual"])
	var idx := 0
	for i in rg.size():
		var card: Dictionary = rg[i]
		var vv := int(card.get("value", 0))
		var b := Button.new()
		b.text = "Ritual %d (crypt #%d)" % [vv, idx]
		var capture := idx
		b.pressed.connect(func() -> void:
			_on_aeoiu_crypt_chosen(capture)
		)
		_aeoiu_crypt_row.add_child(b)
		idx += 1
	if _aeoiu_crypt_row.get_child_count() == 0:
		status_label.text = "No rituals in your crypt."
		return
	_aeoiu_overlay.visible = true
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _on_aeoiu_crypt_chosen(crypt_idx: int) -> void:
	var nm := _aeoiu_noble_mid
	_aeoiu_overlay.visible = false
	_aeoiu_noble_mid = -1
	end_turn_button.disabled = false
	discard_draw_button.disabled = false
	if _is_network_client():
		submit_aeoiu_ritual.rpc_id(1, nm, crypt_idx)
		return
	if _match != null:
		var res: String = _match.apply_aeoiu_ritual_from_crypt(_my_player_for_action(), nm, crypt_idx)
		if res != "ok":
			status_label.text = "Could not play that ritual from the crypt."
		_broadcast_sync(true)


func _on_aeoiu_cancel_pressed() -> void:
	_aeoiu_overlay.visible = false
	_aeoiu_noble_mid = -1
	end_turn_button.disabled = false
	discard_draw_button.disabled = false


func _temple_field_input_ok() -> bool:
	if _sacrifice_selecting or _insight_open:
		return false
	if _gotha_picking:
		return false
	if _delpha_overlay != null and _delpha_overlay.visible:
		return false
	if _burn_woe_overlay != null and _burn_woe_overlay.visible:
		return false
	if _revive_overlay != null and _revive_overlay.visible:
		return false
	if _woe_self_picking:
		return false
	return true


func _enter_temple_sacrifice_mode(hand_idx: int) -> void:
	_sacrifice_for_temple = true
	var cost := 7
	var hand: Array = _last_snap.get("your_hand", []) as Array
	if hand_idx >= 0 and hand_idx < hand.size():
		var c: Dictionary = hand[hand_idx] as Dictionary
		if str(c.get("temple_id", "")) == "ytria_cycles":
			cost = 9
	_enter_sacrifice_mode(hand_idx, cost, "Temple")


func _on_temple_activate_pressed(temple_mid: int) -> void:
	var yours: Array = _last_snap.get("your_temples", [])
	for tt in yours:
		if int(tt.get("mid", -1)) != temple_mid:
			continue
		var tid := str(tt.get("temple_id", ""))
		if tid == "phaedra_illusion":
			_begin_insight_ui(-1, _insight_depth_for(_last_snap, 1), [], -1, -1, temple_mid)
			return
		if tid == "delpha_oracles":
			_start_delpha_pick(temple_mid)
			return
		if tid == "gotha_illness":
			_gotha_picking = true
			_gotha_temple_mid = temple_mid
			status_label.text = "Gotha: discard a non-temple card of power/cost N in your hand to draw N cards."
			_rebuild_hand(_last_snap.get("your_hand", []))
			return
		if tid == "ytria_cycles":
			if _is_network_client():
				submit_temple_ytria.rpc_id(1, temple_mid)
			else:
				if _match == null or _match.apply_temple_ytria(_my_player_for_action(), temple_mid) != "ok":
					status_label.text = "Could not activate Ytria."
			_broadcast_sync(true)
			return
		break


func _start_delpha_pick(temple_mid: int) -> void:
	var deck_n := int(_last_snap.get("your_deck", 0))
	if deck_n < 2:
		status_label.text = "Need at least 2 cards in deck for Delpha."
		return
	var rg: Array = _last_snap.get("your_ritual_crypt_cards", []) as Array
	if rg.is_empty():
		status_label.text = "No rituals in your crypt."
		return
	var field: Array = _last_snap.get("your_field", []) as Array
	if field.is_empty():
		status_label.text = "Need a ritual on your field for Delpha."
		return
	if _match != null and not _is_network_client() and not _match.can_activate_temple(_my_player_for_action(), temple_mid):
		status_label.text = "Cannot use Delpha right now."
		return
	_delpha_temple_mid = temple_mid
	_delpha_ritual_mid = -1
	_delpha_x = 0
	for c in _delpha_ritual_row.get_children():
		c.queue_free()
	for r in field:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var rm := int(r.get("mid", -1))
		var rv := int(r.get("value", 0))
		if rm < 0 or rv < 1:
			continue
		if deck_n < 2 * rv:
			continue
		var rb := Button.new()
		rb.text = "Field ritual %d (mid %d)" % [rv, rm]
		var rm_cap := rm
		var rv_cap := rv
		rb.pressed.connect(func() -> void:
			_on_delpha_ritual_chosen(rm_cap, rv_cap)
		)
		_delpha_ritual_row.add_child(rb)
	if _delpha_ritual_row.get_child_count() == 0:
		status_label.text = "No field ritual has valid power X for your current deck size."
		return
	for c in _delpha_crypt_row.get_children():
		c.queue_free()
	var rg2: Array = _filtered_crypt_cards(_your_crypt_cards_from_snap(_last_snap), ["ritual"])
	var idx := 0
	for i in rg2.size():
		var card: Dictionary = rg2[i]
		var vv := int(card.get("value", 0))
		var b := Button.new()
		b.text = "Ritual %d (crypt #%d)" % [vv, idx]
		var capture := idx
		b.pressed.connect(func() -> void:
			_on_delpha_crypt_chosen(capture)
		)
		b.disabled = true
		_delpha_crypt_row.add_child(b)
		idx += 1
	if _delpha_crypt_row.get_child_count() == 0:
		status_label.text = "No rituals in your crypt."
		return
	_delpha_overlay.visible = true
	end_turn_button.disabled = true
	discard_draw_button.disabled = true


func _on_delpha_ritual_chosen(ritual_mid: int, x: int) -> void:
	_delpha_ritual_mid = ritual_mid
	_delpha_x = x
	for c in _delpha_crypt_row.get_children():
		if c is Button:
			(c as Button).disabled = false


func _on_delpha_crypt_chosen(crypt_idx: int) -> void:
	var tm := _delpha_temple_mid
	var ritual_mid := _delpha_ritual_mid
	var x := _delpha_x
	if ritual_mid < 0 or x < 1:
		status_label.text = "Pick a field ritual first."
		return
	_delpha_overlay.visible = false
	_delpha_temple_mid = -1
	_delpha_ritual_mid = -1
	_delpha_x = 0
	end_turn_button.disabled = false
	discard_draw_button.disabled = false
	if _is_network_client():
		submit_temple_delpha.rpc_id(1, tm, ritual_mid, crypt_idx)
		return
	if _match != null:
		var res: String = _match.apply_temple_delpha(_my_player_for_action(), tm, ritual_mid, crypt_idx)
		if res != "ok":
			status_label.text = "Could not activate Delpha."
		_broadcast_sync(true)


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
	var temple_used := mine and bool(_last_snap.get("your_temple_played", false))
	var bird_used := mine and bool(_last_snap.get("your_bird_played", false))
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
		var temple_blocked := temple_used and ctype == "temple"
		var bird_blocked := bird_used and ctype == "bird"
		var play_type_blocked := (ritual_blocked or noble_blocked or temple_blocked or bird_blocked) and not _mode_discard_draw and not _selecting_end_discard
		var waiting_input_window := mine or woe_you
		var gotha_pick := mine and _gotha_picking
		var is_disabled := ((not waiting_input_window and not _selecting_end_discard and not _mode_discard_draw) or _sacrifice_selecting or _insight_open or play_type_blocked) and not gotha_pick
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
	var ctype := _card_type(card)
	var is_ritual := ctype == "ritual"
	var is_bird := ctype == "bird"
	var is_noble := ctype == "noble"
	var is_temple := ctype == "temple"
	var ritual_gold := Color(0.95, 0.78, 0.24)
	var ritual_gold_strong := Color(1.0, 0.86, 0.35)
	var noble_purple := Color(0.84, 0.7, 1.0)
	var noble_purple_strong := Color(0.95, 0.82, 1.0)
	var temple_teal := Color(0.35, 0.88, 0.82)
	var temple_teal_strong := Color(0.5, 0.96, 0.92)
	var bird_black := Color(0.05, 0.05, 0.05)
	var bird_black_strong := Color(0.0, 0.0, 0.0)
	var noble_bg := Color(0.13, 0.1, 0.18)
	var temple_bg := Color(0.08, 0.14, 0.13)
	var bird_bg := Color(0.97, 0.97, 0.97)
	for i in depth:
		var back := Panel.new()
		back.position = Vector2(i * shift, 0)
		back.size = Vector2(w, h)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bsb := StyleBoxFlat.new()
		bsb.set_corner_radius_all(3)
		bsb.set_border_width_all(2)
		if is_noble:
			bsb.bg_color = Color(0.11, 0.09, 0.15)
			bsb.border_color = Color(0.5, 0.42, 0.62)
		elif is_bird:
			bsb.bg_color = Color(0.9, 0.9, 0.9)
			bsb.border_color = Color(0.25, 0.25, 0.25)
		elif is_temple:
			bsb.bg_color = Color(0.07, 0.11, 0.11)
			bsb.border_color = Color(0.28, 0.55, 0.52)
		else:
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
	tap.add_theme_font_override("font", CARD_TEXT_FONT)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(3 if picked else 2)
	sb.bg_color = noble_bg if is_noble else (bird_bg if is_bird else (temple_bg if is_temple else Color(0.04, 0.04, 0.06)))
	if is_ritual:
		sb.border_color = ritual_gold_strong if picked else ritual_gold
	elif is_noble:
		sb.border_color = noble_purple_strong if picked else noble_purple
	elif is_bird:
		sb.border_color = bird_black_strong if picked else bird_black
	elif is_temple:
		sb.border_color = temple_teal_strong if picked else temple_teal
	else:
		sb.border_color = Color(0.7, 0.9, 1.0) if picked else Color(0.92, 0.92, 0.95)
	tap.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	if is_ritual:
		sb_hover.border_color = ritual_gold_strong if picked else Color(1.0, 0.9, 0.48)
	elif is_noble:
		sb_hover.border_color = noble_purple_strong if picked else Color(0.92, 0.82, 1.0)
	elif is_bird:
		sb_hover.border_color = bird_black_strong if picked else Color(0.15, 0.15, 0.15)
	elif is_temple:
		sb_hover.border_color = temple_teal_strong if picked else Color(0.65, 1.0, 0.95)
	else:
		sb_hover.border_color = Color(0.84, 0.96, 1.0) if picked else Color(1.0, 1.0, 1.0)
	tap.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := sb.duplicate()
	sb_pressed.bg_color = Color(0.17, 0.14, 0.22) if is_noble else (Color(0.9, 0.9, 0.9) if is_bird else (Color(0.1, 0.14, 0.14) if is_temple else Color(0.08, 0.08, 0.12)))
	tap.add_theme_stylebox_override("pressed", sb_pressed)
	var sb_dis := sb.duplicate()
	sb_dis.bg_color = Color(0.1, 0.08, 0.14) if is_noble else (Color(0.88, 0.88, 0.88) if is_bird else (Color(0.07, 0.1, 0.1) if is_temple else Color(0.08, 0.08, 0.1)))
	if is_ritual:
		sb_dis.border_color = Color(0.56, 0.5, 0.32)
	elif is_noble:
		sb_dis.border_color = Color(0.45, 0.38, 0.58)
	elif is_bird:
		sb_dis.border_color = Color(0.3, 0.3, 0.3)
	elif is_temple:
		sb_dis.border_color = Color(0.25, 0.42, 0.4)
	else:
		sb_dis.border_color = Color(0.45, 0.45, 0.5)
	tap.add_theme_stylebox_override("disabled", sb_dis)
	if is_ritual:
		tap.add_theme_color_override("font_color", ritual_gold)
	elif is_noble:
		tap.add_theme_color_override("font_color", Color(0.96, 0.93, 1.0))
	elif is_bird:
		tap.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	elif is_temple:
		tap.add_theme_color_override("font_color", Color(0.88, 0.98, 0.95))
	else:
		tap.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	if is_ritual:
		tap.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.48))
	elif is_noble:
		tap.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 1.0))
	elif is_bird:
		tap.add_theme_color_override("font_hover_color", Color(0.05, 0.05, 0.05))
	elif is_temple:
		tap.add_theme_color_override("font_hover_color", Color(0.75, 1.0, 0.96))
	else:
		tap.add_theme_color_override("font_hover_color", Color(0.98, 0.98, 0.98))
	if is_ritual:
		tap.add_theme_color_override("font_focus_color", ritual_gold)
	elif is_noble:
		tap.add_theme_color_override("font_focus_color", Color(0.96, 0.93, 1.0))
	elif is_bird:
		tap.add_theme_color_override("font_focus_color", Color(0.05, 0.05, 0.05))
	elif is_temple:
		tap.add_theme_color_override("font_focus_color", Color(0.88, 0.98, 0.95))
	else:
		tap.add_theme_color_override("font_focus_color", Color(0.98, 0.98, 0.98))
	if is_ritual:
		tap.add_theme_color_override("font_pressed_color", ritual_gold_strong)
	elif is_noble:
		tap.add_theme_color_override("font_pressed_color", noble_purple_strong)
	elif is_bird:
		tap.add_theme_color_override("font_pressed_color", bird_black_strong)
	elif is_temple:
		tap.add_theme_color_override("font_pressed_color", temple_teal_strong)
	else:
		tap.add_theme_color_override("font_pressed_color", Color(0.98, 0.98, 0.98))
	if is_ritual:
		tap.add_theme_color_override("font_disabled_color", Color(0.62, 0.56, 0.38))
	elif is_noble:
		tap.add_theme_color_override("font_disabled_color", Color(0.58, 0.52, 0.68))
	elif is_bird:
		tap.add_theme_color_override("font_disabled_color", Color(0.25, 0.25, 0.25))
	elif is_temple:
		tap.add_theme_color_override("font_disabled_color", Color(0.45, 0.58, 0.55))
	else:
		tap.add_theme_color_override("font_disabled_color", Color(0.7, 0.7, 0.76))
	tap.add_theme_font_size_override("font_size", HAND_CARD_FONT_SIZE)
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
	var pip_spec := _card_corner_pip_spec(card)
	if int(pip_spec.get("count", 0)) > 0:
		var pip_icon := _make_corner_pip_icon(int(pip_spec.get("count", 0)), bool(pip_spec.get("filled", false)))
		pip_icon.position = Vector2(depth * shift + w - pip_icon.custom_minimum_size.x - 4, h - pip_icon.custom_minimum_size.y - 4)
		shell.add_child(pip_icon)
	if stack_count > 1:
		var badge := Label.new()
		badge.text = "x%d" % stack_count
		badge.position = Vector2(depth * shift + w - 52, 4)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(44, 32)
		badge.add_theme_font_override("font", CARD_TEXT_FONT)
		badge.add_theme_font_size_override("font_size", HAND_CARD_BADGE_FONT_SIZE)
		badge.add_theme_color_override("font_color", Color(0.95, 0.95, 0.99))
		shell.add_child(badge)
	if _selecting_end_discard and picked_count > 0:
		var pick_badge := Label.new()
		pick_badge.text = "-%d" % picked_count
		pick_badge.position = Vector2(depth * shift + 4, 4)
		pick_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pick_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pick_badge.custom_minimum_size = Vector2(48, 32)
		pick_badge.add_theme_font_override("font", CARD_TEXT_FONT)
		pick_badge.add_theme_font_size_override("font_size", HAND_CARD_BADGE_FONT_SIZE)
		pick_badge.add_theme_color_override("font_color", Color(1.0, 0.86, 0.86))
		shell.add_child(pick_badge)
	elif bool(_last_snap.get("woe_pending_you_respond", false)) and picked:
		var woe_badge := Label.new()
		woe_badge.text = "W"
		woe_badge.position = Vector2(depth * shift + 6, 4)
		woe_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		woe_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		woe_badge.custom_minimum_size = Vector2(32, 32)
		woe_badge.add_theme_font_override("font", CARD_TEXT_FONT)
		woe_badge.add_theme_font_size_override("font_size", HAND_CARD_BADGE_FONT_SIZE)
		woe_badge.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
		shell.add_child(woe_badge)
	return shell


func _card_corner_pip_spec(card: Variant) -> Dictionary:
	return _GameSnapshotUtils.card_corner_pip_spec(card)


func _noble_cost_for_id(nid: String) -> int:
	return _GameSnapshotUtils.noble_cost_for_id(nid)


func _make_corner_pip_icon(count: int, filled: bool) -> TextureRect:
	var n := clampi(count, 0, 24)
	var dot_r: int = 4
	var icon_size: int = 28
	if n > 1:
		var remaining: int = n
		var ring: int = 1
		var step: float = 6.0
		var max_ring_radius: int = 0
		while remaining > 0:
			var cap: int = ring * 6
			var take: int = mini(remaining, cap)
			var radius: int = int(round(ring * step))
			max_ring_radius = maxi(max_ring_radius, radius)
			remaining -= take
			ring += 1
		icon_size = maxi(28, 2 * (max_ring_radius + dot_r) + 2)
	var center := Vector2i(icon_size >> 1, icon_size >> 1)
	var image := Image.create(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if n == 1:
		CornerPipDraw.draw_dot_on_image(image, center, dot_r, filled)
	else:
		var remaining2: int = n
		var ring2: int = 1
		var step2: float = 6.0
		while remaining2 > 0:
			var cap2: int = ring2 * 6
			var take2: int = mini(remaining2, cap2)
			var radius2: int = int(round(ring2 * step2))
			for i in take2:
				var ang := TAU * (float(i) / float(take2)) - PI / 2.0
				var px := center.x + int(round(cos(ang) * radius2))
				var py := center.y + int(round(sin(ang) * radius2))
				CornerPipDraw.draw_dot_on_image(image, Vector2i(px, py), dot_r, filled)
			remaining2 -= take2
			ring2 += 1
	var tex := ImageTexture.create_from_image(image)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP
	rect.custom_minimum_size = Vector2(icon_size, icon_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _hand_card_stack_key(card: Variant) -> String:
	return _GameSnapshotUtils.hand_card_stack_key(card)


func _card_type(card: Variant) -> String:
	return _GameSnapshotUtils.card_type(card)


func _card_label(card: Variant) -> String:
	return _GameSnapshotUtils.card_label(card)


func _short_noble_name(full_name: String) -> String:
	return _GameSnapshotUtils.short_noble_name(full_name)


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
	if _woe_self_picking and _burn_woe_mode != "revive_woe_self" and _burn_woe_mode != "tmrsk_woe_self":
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
	if _woe_self_picking and _burn_woe_mode == "tmrsk_woe_self":
		if _woe_self_picked.has(hand_idx):
			_woe_self_picked.erase(hand_idx)
		else:
			if _woe_self_picked.size() < _woe_self_need:
				_woe_self_picked[hand_idx] = true
		if _woe_self_need > 0 and _woe_self_picked.size() == _woe_self_need:
			var idxs4: Array = []
			for k4 in _woe_self_picked.keys():
				idxs4.append(int(k4))
			idxs4.sort()
			var sidt := int(snap.get("scion_pending_id", -1))
			var ctxt := {"scion_id": sidt, "woe_target": int(snap.get("you", 0)), "woe_indices": idxs4}
			_woe_self_picking = false
			_burn_woe_mode = ""
			_woe_self_picked.clear()
			if _is_network_client():
				submit_scion_trigger_response.rpc_id(1, "accept", ctxt)
			else:
				if _match != null:
					_match.submit_scion_trigger_response(_my_player_for_action(), "accept", ctxt)
			_broadcast_sync(true)
		else:
			_rebuild_hand(hand)
		return
	if _gotha_picking:
		if str(c.get("type", "")).to_lower() == "temple":
			status_label.text = "Gotha cannot discard temple cards."
			return
		if _is_network_client():
			submit_temple_gotha.rpc_id(1, _gotha_temple_mid, hand_idx)
		else:
			if _match == null or _match.apply_temple_gotha(_my_player_for_action(), _gotha_temple_mid, hand_idx) != "ok":
				status_label.text = "Could not activate Gotha."
		_gotha_picking = false
		_gotha_temple_mid = -1
		_broadcast_sync(true)
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
	elif _card_type(c) == "bird":
		if bool(snap.get("your_bird_played", false)):
			status_label.text = "You already played a bird this turn."
			return
		if _is_network_client():
			submit_play_bird.rpc_id(1, hand_idx)
		else:
			_try_play_bird(_my_player_for_action(), hand_idx)
	elif _card_type(c) == "temple":
		if bool(snap.get("your_temple_played", false)):
			status_label.text = "You already played a temple this turn."
			return
		var field_ty: Array = snap.get("your_field", [])
		if _field_ritual_total_value(field_ty) < 7:
			status_label.text = "Not enough ritual value on your field to sacrifice for a temple (need 7)."
			return
		_enter_temple_sacrifice_mode(hand_idx)
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


func _try_play_bird(player: int, hand_idx: int, trigger_cpu_check: bool = true) -> bool:
	if _match == null:
		return false
	if _match.play_bird(player, hand_idx) != "ok":
		status_label.text = "Can't play that bird now."
		return false
	_broadcast_sync(trigger_cpu_check)
	return true


func _try_play_temple(player: int, hand_idx: int, sacrifice_mids: Array, trigger_cpu_check: bool = true) -> bool:
	if _match == null:
		return false
	if _match.play_temple(player, hand_idx, sacrifice_mids) != "ok":
		status_label.text = "Can't play that temple now."
		return false
	_broadcast_sync(trigger_cpu_check)
	return true


func _try_resolve_bird_fight(player: int, attacker_mids: Array, defender_mid: int, assign: Dictionary, trigger_cpu_check: bool = true) -> bool:
	if _match == null:
		return false
	if _match.resolve_bird_fight(player, attacker_mids, defender_mid, assign) != "ok":
		status_label.text = "Could not resolve bird fight."
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


func _try_submit_scion_trigger(player: int, action: String, ctx: Dictionary = {}, trigger_cpu_check: bool = true) -> bool:
	if _match == null:
		return false
	if _match.submit_scion_trigger_response(player, action, ctx) != "ok":
		return false
	_broadcast_sync(trigger_cpu_check)
	return true


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


func _try_concede(player: int, trigger_cpu_check: bool = true) -> void:
	if _match == null:
		return
	if _match.concede(player) != "ok":
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
func submit_play_bird(hand_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_play_bird(pl, hand_idx)


@rpc("any_peer", "reliable")
func submit_play_temple(hand_idx: int, sacrifice_mids: Array) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_play_temple(pl, hand_idx, sacrifice_mids)


@rpc("any_peer", "reliable")
func submit_bird_fight(attacker_mids: Array, defender_mid: int, assign: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_resolve_bird_fight(pl, attacker_mids, defender_mid, assign)


@rpc("any_peer", "reliable")
func submit_temple_phaedra_insight(temple_mid: int, insight_target: int, insight_top: Array = [], insight_bottom: Array = []) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.apply_temple_phaedra_insight(pl, temple_mid, insight_target, insight_top, insight_bottom) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_temple_delpha(temple_mid: int, ritual_mid: int, crypt_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.apply_temple_delpha(pl, temple_mid, ritual_mid, crypt_idx) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_temple_gotha(temple_mid: int, hand_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.apply_temple_gotha(pl, temple_mid, hand_idx) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_temple_ytria(temple_mid: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.apply_temple_ytria(pl, temple_mid) == "ok":
		_broadcast_sync(true)


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
func submit_scion_trigger_response(action: String, ctx: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_submit_scion_trigger(pl, action, ctx)


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
func submit_activate_noble_with_insight(noble_mid: int, insight_target: int, insight_top: Array = [], insight_bottom: Array = []) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.activate_noble_with_insight(pl, noble_mid, insight_target, insight_top, insight_bottom) == "ok":
		_broadcast_sync(true)


@rpc("any_peer", "reliable")
func submit_aeoiu_ritual(noble_mid: int, crypt_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	if _match.apply_aeoiu_ritual_from_crypt(pl, noble_mid, crypt_idx) == "ok":
		_broadcast_sync(true)
		return
	var snd := multiplayer.get_remote_sender_id()
	if snd != 0:
		notify_aeoiu_failed.rpc_id(snd, "Could not play that ritual from the crypt.")


@rpc("authority", "reliable")
func notify_aeoiu_failed(msg: String) -> void:
	status_label.text = msg


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
func submit_concede() -> void:
	if not multiplayer.is_server():
		return
	if _match == null:
		return
	var pl := _peer_to_player(_sender_peer())
	_try_concede(pl)


@rpc("any_peer", "reliable")
func request_play_again() -> void:
	if not multiplayer.is_server():
		return
	_start_match()


func _on_end_turn_pressed() -> void:
	if _insight_open:
		return
	if _gotha_picking:
		_gotha_picking = false
		_gotha_temple_mid = -1
	if _delpha_overlay != null and _delpha_overlay.visible:
		_on_delpha_cancel_pressed()
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
	_show_pause_overlay()


func _on_concede_pressed() -> void:
	concede_confirm_dialog.popup_centered()


func _on_exit_match_pressed() -> void:
	exit_confirm_dialog.popup_centered()


func _on_concede_confirmed() -> void:
	if _is_network_client():
		submit_concede.rpc_id(1)
	else:
		_try_concede(_my_player_for_action())


func _on_exit_match_confirmed() -> void:
	_on_quit_to_menu_confirmed()


func _set_left_action_expanded(expanded: bool) -> void:
	left_action_expanded_panel.visible = expanded
	left_action_hamburger_button.visible = not expanded


func _on_left_action_hamburger_pressed() -> void:
	_set_left_action_expanded(true)


func _on_left_action_close_pressed() -> void:
	_set_left_action_expanded(false)


func _on_quit_to_menu_confirmed() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _apply_ui_button_padding(btn: Button) -> void:
	if btn == null:
		return
	btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, UI_BUTTON_MIN_HEIGHT)
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := btn.get_theme_stylebox(style_name)
		if style == null:
			continue
		var padded := style.duplicate()
		padded.content_margin_left = maxf(padded.content_margin_left, UI_BUTTON_PAD_X)
		padded.content_margin_right = maxf(padded.content_margin_right, UI_BUTTON_PAD_X)
		padded.content_margin_top = maxf(padded.content_margin_top, UI_BUTTON_PAD_Y)
		padded.content_margin_bottom = maxf(padded.content_margin_bottom, UI_BUTTON_PAD_Y)
		btn.add_theme_stylebox_override(style_name, padded)


func _show_pause_overlay() -> void:
	pause_overlay.visible = true
	pause_return_button.grab_focus()


func _hide_pause_overlay() -> void:
	pause_overlay.visible = false


func _on_pause_return_pressed() -> void:
	_hide_pause_overlay()


func _on_pause_quit_pressed() -> void:
	_on_quit_to_menu_confirmed()

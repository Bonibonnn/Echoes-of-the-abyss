extends Control

# A separate LAN lobby. It does not touch the normal character-select or
# World scenes, so the tested single-player game remains its own path.

@export_file("*.tscn") var main_menu_scene := "res://main_menu.tscn"

@onready var lobby_card := get_node_or_null(^"lobby_card") as Control
@onready var ip_address := get_node_or_null(^"lobby_card/ip_address") as LineEdit
@onready var host_button := get_node_or_null(^"lobby_card/host_button") as Button
@onready var join_button := get_node_or_null(^"lobby_card/join_button") as Button
@onready var start_button := get_node_or_null(^"lobby_card/start_button") as Button
@onready var leave_button := get_node_or_null(^"lobby_card/leave_button") as Button
@onready var back_button := get_node_or_null(^"lobby_card/back_button") as Button
@onready var host_ip_label := get_node_or_null(^"lobby_card/host_ip_label") as Label
@onready var players_label := get_node_or_null(^"lobby_card/players_label") as Label
@onready var status_label := get_node_or_null(^"lobby_card/status_label") as Label
@onready var selection_panel := get_node_or_null(^"selection_panel") as Control
@onready var knight_button := get_node_or_null(^"selection_panel/knight_button") as Button
@onready var archer_button := get_node_or_null(^"selection_panel/archer_button") as Button
@onready var mage_button := get_node_or_null(^"selection_panel/mage_button") as Button
@onready var priest_button := get_node_or_null(^"selection_panel/priest_button") as Button
@onready var ready_button := get_node_or_null(^"selection_panel/ready_button") as Button
@onready var selection_start_button := get_node_or_null(^"selection_panel/start_button") as Button
@onready var selection_leave_button := get_node_or_null(^"selection_panel/leave_button") as Button
@onready var local_choice_label := get_node_or_null(^"selection_panel/local_choice_label") as Label
@onready var knight_state_label := get_node_or_null(^"selection_panel/knight_state_label") as Label
@onready var archer_state_label := get_node_or_null(^"selection_panel/archer_state_label") as Label
@onready var mage_state_label := get_node_or_null(^"selection_panel/mage_state_label") as Label
@onready var priest_state_label := get_node_or_null(^"selection_panel/priest_state_label") as Label
@onready var host_roster_label := get_node_or_null(^"selection_panel/roster_panel/host_roster_label") as Label
@onready var joiner_roster_label := get_node_or_null(^"selection_panel/roster_panel/joiner_roster_label") as Label
@onready var selection_status_label := get_node_or_null(^"selection_panel/status_label") as Label


func _ready() -> void:
	if host_button != null:
		host_button.pressed.connect(_on_host_pressed)
	if join_button != null:
		join_button.pressed.connect(_on_join_pressed)
	if leave_button != null:
		leave_button.pressed.connect(_on_leave_pressed)
	if back_button != null:
		back_button.pressed.connect(_on_back_pressed)
	if knight_button != null:
		knight_button.pressed.connect(_on_knight_pressed)
	if archer_button != null:
		archer_button.pressed.connect(_on_archer_pressed)
	if mage_button != null:
		mage_button.pressed.connect(_on_mage_pressed)
	if priest_button != null:
		priest_button.pressed.connect(_on_priest_pressed)
	if ready_button != null:
		ready_button.pressed.connect(_on_ready_pressed)
	if selection_start_button != null:
		selection_start_button.pressed.connect(_on_selection_start_pressed)
	if selection_leave_button != null:
		selection_leave_button.pressed.connect(_on_selection_leave_pressed)

	if not LanSession.status_changed.is_connected(_on_session_status_changed):
		LanSession.status_changed.connect(_on_session_status_changed)
	if not LanSession.lobby_changed.is_connected(_refresh_lobby):
		LanSession.lobby_changed.connect(_refresh_lobby)

	_refresh_lobby()
	_on_session_status_changed(LanSession.current_status)


func _on_host_pressed() -> void:
	LanSession.host_session()


func _on_join_pressed() -> void:
	var address := ip_address.text if ip_address != null else ""
	LanSession.join_session(address)


func _on_leave_pressed() -> void:
	LanSession.leave_session("Left the LAN lobby.")


func _on_back_pressed() -> void:
	LanSession.leave_session("Left multiplayer.")
	var error := get_tree().change_scene_to_file(main_menu_scene)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %d" % error)


func _refresh_lobby() -> void:
	var connected_players := LanSession.get_connected_peer_ids().size()
	var is_active := LanSession.is_active()
	var is_host := LanSession.is_host()
	# Host/Join stays visible while waiting. Once both peers are connected, the
	# same lobby becomes the synchronized character-select and ready-up screen.
	var show_selection := is_active and LanSession.is_in_lobby() and connected_players == 2

	if lobby_card != null:
		lobby_card.visible = not show_selection
	if selection_panel != null:
		selection_panel.visible = show_selection

	if host_button != null:
		host_button.disabled = is_active
	if join_button != null:
		join_button.disabled = is_active
	if ip_address != null:
		ip_address.editable = not is_active
	if start_button != null:
		start_button.visible = is_host
		start_button.disabled = true
	if leave_button != null:
		leave_button.disabled = not is_active

	if host_ip_label != null:
		host_ip_label.text = _get_host_address_hint(is_host)
	if players_label != null:
		players_label.text = "Players connected: %d / 2" % connected_players

	if not show_selection:
		return

	var local_peer_id := LanSession.get_local_peer_id()
	var local_character := LanSession.get_selected_character(local_peer_id)
	var local_ready := LanSession.is_local_player_ready()

	if knight_button != null:
		knight_button.disabled = not LanSession.is_in_lobby()
		knight_button.button_pressed = local_character == LanSession.KNIGHT_CHARACTER_ID
	if archer_button != null:
		archer_button.disabled = not LanSession.is_in_lobby()
		archer_button.button_pressed = local_character == LanSession.ARCHER_CHARACTER_ID
		# Archer has no separate pressed portrait yet, so this brightens it when
		# selected while its state label gives clear feedback.
		archer_button.modulate = Color.WHITE if local_character == LanSession.ARCHER_CHARACTER_ID else Color(0.88, 0.94, 1.0, 1.0)
	if mage_button != null:
		mage_button.disabled = not LanSession.is_in_lobby()
		mage_button.button_pressed = local_character == LanSession.MAGE_CHARACTER_ID
		# Mage uses the same bright selected treatment as Archer because it has
		# one portrait texture for all button states.
		mage_button.modulate = Color.WHITE if local_character == LanSession.MAGE_CHARACTER_ID else Color(0.88, 0.94, 1.0, 1.0)
	if priest_button != null:
		priest_button.disabled = not LanSession.is_in_lobby()
		priest_button.button_pressed = local_character == LanSession.PRIEST_CHARACTER_ID
		# Priest uses the same bright selected treatment as Archer and Mage.
		priest_button.modulate = Color.WHITE if local_character == LanSession.PRIEST_CHARACTER_ID else Color(0.88, 0.94, 1.0, 1.0)
	if knight_state_label != null:
		knight_state_label.text = "SELECTED" if local_character == LanSession.KNIGHT_CHARACTER_ID else "LAN READY"
	if archer_state_label != null:
		archer_state_label.text = "SELECTED" if local_character == LanSession.ARCHER_CHARACTER_ID else "LAN READY"
	if mage_state_label != null:
		mage_state_label.text = "SELECTED" if local_character == LanSession.MAGE_CHARACTER_ID else "LAN READY"
	if priest_state_label != null:
		priest_state_label.text = "SELECTED" if local_character == LanSession.PRIEST_CHARACTER_ID else "LAN READY"
	if local_choice_label != null:
		local_choice_label.text = "Your selection: %s" % LanSession.get_character_display_name(local_character)
	if ready_button != null:
		ready_button.disabled = not LanSession.has_local_character_selected()
		ready_button.text = "CANCEL READY" if local_ready else "READY UP"
	if selection_start_button != null:
		selection_start_button.visible = is_host
		selection_start_button.disabled = not LanSession.can_start_match()

	if host_roster_label != null:
		host_roster_label.text = _get_roster_line("HOST", 1)
	if joiner_roster_label != null:
		joiner_roster_label.text = _get_roster_line("PLAYER 2", _get_joiner_peer_id())


func _get_host_address_hint(is_host: bool) -> String:
	if not is_host:
		return "Enter the host IP to join. Port 7001 is automatic."

	var ip_options: PackedStringArray = LanSession.get_lan_ip_options()
	if ip_options.is_empty():
		return "No LAN IPv4 found. Connect to Wi-Fi/Ethernet, then Host again."

	return "Share with Player 2: %s (port %d)" % [ip_options[0], LanSession.PORT]


func _on_session_status_changed(message: String) -> void:
	if status_label != null:
		status_label.text = message
	if selection_status_label != null:
		selection_status_label.text = message


func _on_knight_pressed() -> void:
	LanSession.select_local_character(LanSession.KNIGHT_CHARACTER_ID)


func _on_archer_pressed() -> void:
	LanSession.select_local_character(LanSession.ARCHER_CHARACTER_ID)


func _on_mage_pressed() -> void:
	LanSession.select_local_character(LanSession.MAGE_CHARACTER_ID)


func _on_priest_pressed() -> void:
	LanSession.select_local_character(LanSession.PRIEST_CHARACTER_ID)


func _on_ready_pressed() -> void:
	LanSession.set_local_player_ready(not LanSession.is_local_player_ready())


func _on_selection_start_pressed() -> void:
	LanSession.start_match()


func _on_selection_leave_pressed() -> void:
	LanSession.leave_session("Left the LAN character lobby.")


func _get_joiner_peer_id() -> int:
	for peer_id in LanSession.get_connected_peer_ids():
		if peer_id != 1:
			return peer_id
	return 0


func _get_roster_line(player_name: String, peer_id: int) -> String:
	if peer_id <= 0:
		return "%s: Waiting for player" % player_name

	var character_name := LanSession.get_character_display_name(LanSession.get_selected_character(peer_id))
	var ready_text := "READY" if LanSession.is_peer_ready(peer_id) else "WAITING"
	return "%s: %s — %s" % [player_name, character_name, ready_text]

extends Node

# This Autoload is the one persistent owner of the LAN connection. Unlike a
# scene script, it stays alive while both computers change from the lobby into
# the shared match.

signal status_changed(message: String)
signal lobby_changed()
signal match_loading(match_id: int)
signal match_started(match_id: int)

const PORT := 7001
const MAX_CLIENTS := 1
const KNIGHT_CHARACTER_ID := "knight"
const ARCHER_CHARACTER_ID := "archer"
const MAGE_CHARACTER_ID := "mage"
const PRIEST_CHARACTER_ID := "priest"
const LOBBY_SCENE_PATH := "res://Scenes/lan_lobby.tscn"
const MATCH_SCENE_PATH := "res://Scenes/lan_world.tscn"

# Only this script creates or closes the peer. Gameplay scenes use the peer
# through Godot's MultiplayerAPI, but never take ownership of it.
var network_peer: ENetMultiplayerPeer
var session_phase := "idle"
var current_status := "Choose Host, or enter the host IP and choose Join."

# A transition number prevents an old delayed RPC from opening a later match.
var active_match_id := -1
var scene_change_scheduled := false

# The host is the source of truth for these dictionaries. Clients receive a
# read-only roster for their lobby display.
var lobby_peers: Dictionary = {}
var selected_character_by_peer: Dictionary = {}
var ready_by_peer: Dictionary = {}
var expected_match_peers: Dictionary = {}
var loaded_match_peers: Dictionary = {}


func _ready() -> void:
	# These signals belong to the Autoload rather than the lobby or match scene,
	# so scene changes cannot accidentally disconnect them.
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


# Starts a two-player LAN server on this computer.
func host_session() -> int:
	if is_active():
		_set_status("Leave the current LAN session before hosting another one.")
		return ERR_ALREADY_IN_USE

	network_peer = ENetMultiplayerPeer.new()
	var error := network_peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		network_peer = null
		_set_status("Could not host on port %d. Error code: %d" % [PORT, error])
		return error

	multiplayer.multiplayer_peer = network_peer
	session_phase = "lobby"
	lobby_peers.clear()
	selected_character_by_peer.clear()
	ready_by_peer.clear()
	var host_peer_id := multiplayer.get_unique_id()
	lobby_peers[host_peer_id] = true
	selected_character_by_peer[host_peer_id] = ""
	ready_by_peer[host_peer_id] = false
	expected_match_peers.clear()
	loaded_match_peers.clear()
	active_match_id = -1
	_set_status("Hosting at %s:%d. Waiting for one player." % [_get_lan_ip(), PORT])
	lobby_changed.emit()
	return OK


# Connects this computer to a LAN host. The host still decides when the match
# begins and which scene both peers load.
func join_session(address: String) -> int:
	if is_active():
		_set_status("Leave the current LAN session before joining another one.")
		return ERR_ALREADY_IN_USE

	var cleaned_address := address.strip_edges()
	if cleaned_address.is_empty():
		_set_status("Enter the host computer's IPv4 address first.")
		return ERR_INVALID_PARAMETER

	network_peer = ENetMultiplayerPeer.new()
	var error := network_peer.create_client(cleaned_address, PORT)
	if error != OK:
		network_peer = null
		_set_status("Could not connect to %s:%d. Error code: %d" % [cleaned_address, PORT, error])
		return error

	multiplayer.multiplayer_peer = network_peer
	session_phase = "connecting"
	lobby_peers.clear()
	selected_character_by_peer.clear()
	ready_by_peer.clear()
	expected_match_peers.clear()
	loaded_match_peers.clear()
	active_match_id = -1
	_set_status("Connecting to %s:%d..." % [cleaned_address, PORT])
	lobby_changed.emit()
	return OK


# Closes only a session created by this Autoload. The old standalone LAN test
# keeps owning its own peer, so running it directly still behaves as before.
func leave_session(final_message: String = "Session closed.") -> void:
	if network_peer != null:
		network_peer.close()

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	network_peer = null
	session_phase = "idle"
	active_match_id = -1
	scene_change_scheduled = false
	lobby_peers.clear()
	selected_character_by_peer.clear()
	ready_by_peer.clear()
	expected_match_peers.clear()
	loaded_match_peers.clear()
	_set_status(final_message)
	lobby_changed.emit()


func is_active() -> bool:
	return network_peer != null


func is_host() -> bool:
	return is_active() and multiplayer.is_server()


func is_in_lobby() -> bool:
	return session_phase == "lobby"


func is_match_active() -> bool:
	return session_phase == "match"


# The host may start only after both players selected a LAN-ready character
# and explicitly pressed Ready. This is host-owned, so a client cannot invent
# a class that has no network controller yet.
func can_start_match() -> bool:
	if not is_host() or session_phase != "lobby" or lobby_peers.size() != MAX_CLIENTS + 1:
		return false

	for peer_id in lobby_peers:
		if not is_lan_ready_character(get_selected_character(int(peer_id))):
			return false
		if not is_peer_ready(int(peer_id)):
			return false

	return true


func get_connected_peer_ids() -> PackedInt32Array:
	var ids: Array[int] = []
	for peer_id in lobby_peers:
		ids.append(int(peer_id))
	ids.sort()
	return PackedInt32Array(ids)


func get_local_peer_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 0


func get_selected_character(peer_id: int) -> String:
	return str(selected_character_by_peer.get(peer_id, ""))


func is_peer_ready(peer_id: int) -> bool:
	return bool(ready_by_peer.get(peer_id, false))


func has_local_character_selected() -> bool:
	return is_lan_ready_character(get_selected_character(get_local_peer_id()))


func is_local_player_ready() -> bool:
	return is_peer_ready(get_local_peer_id())


func get_character_display_name(character_id: String) -> String:
	match character_id:
		KNIGHT_CHARACTER_ID:
			return "Knight"
		ARCHER_CHARACTER_ID:
			return "Archer"
		MAGE_CHARACTER_ID:
			return "Mage"
		PRIEST_CHARACTER_ID:
			return "Priest"
		_:
			return "No character selected"


# Keep the supported-class rule in one place. The lobby uses this for its
# buttons, while the host uses it again before it approves a selection.
func is_lan_ready_character(character_id: String) -> bool:
	return (
		character_id == KNIGHT_CHARACTER_ID
		or character_id == ARCHER_CHARACTER_ID
		or character_id == MAGE_CHARACTER_ID
		or character_id == PRIEST_CHARACTER_ID
	)


# A player may request only a supported character for their own peer ID. The
# host uses Godot's sender ID, never an ID supplied in the request.
func select_local_character(character_id: String) -> void:
	if not is_active() or session_phase != "lobby":
		return

	if is_host():
		_set_host_character_selection(get_local_peer_id(), character_id)
	else:
		request_character_selection.rpc_id(1, character_id)


@rpc("any_peer", "call_remote", "reliable")
func request_character_selection(character_id: String) -> void:
	if not is_host() or session_phase != "lobby":
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id > 0:
		_set_host_character_selection(sender_id, character_id)


func _set_host_character_selection(peer_id: int, character_id: String) -> void:
	if not is_host() or not lobby_peers.has(peer_id):
		return
	if not is_lan_ready_character(character_id):
		return

	selected_character_by_peer[peer_id] = character_id
	# Selecting again always removes Ready. This keeps future class changes from
	# silently carrying an old ready state into a different character.
	ready_by_peer[peer_id] = false
	_set_status("Player %d selected %s." % [peer_id, get_character_display_name(character_id)])
	_broadcast_lobby_state()


func set_local_player_ready(wants_ready: bool) -> void:
	if not is_active() or session_phase != "lobby":
		return

	if is_host():
		_set_host_player_ready(get_local_peer_id(), wants_ready)
	else:
		request_player_ready.rpc_id(1, wants_ready)


@rpc("any_peer", "call_remote", "reliable")
func request_player_ready(wants_ready: bool) -> void:
	if not is_host() or session_phase != "lobby":
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id > 0:
		_set_host_player_ready(sender_id, wants_ready)


func _set_host_player_ready(peer_id: int, wants_ready: bool) -> void:
	if not is_host() or not lobby_peers.has(peer_id):
		return
	if wants_ready and not is_lan_ready_character(get_selected_character(peer_id)):
		_set_status("Player %d must select a LAN-ready character before readying up." % peer_id)
		return

	ready_by_peer[peer_id] = wants_ready
	var ready_text := "Ready" if wants_ready else "not ready"
	_set_status("Player %d is %s." % [peer_id, ready_text])
	_broadcast_lobby_state()


func get_lan_ip() -> String:
	return _get_lan_ip()


# This is a host-only action. Clients cannot choose their own match scene or
# force everyone else to switch maps.
func start_match() -> void:
	if not is_host():
		_set_status("Only the host can start the match.")
		return
	if not can_start_match():
		_set_status("Both players must select a LAN-ready character and press Ready first.")
		return

	active_match_id += 1
	expected_match_peers.clear()
	loaded_match_peers.clear()
	for peer_id in lobby_peers:
		expected_match_peers[int(peer_id)] = true

	session_phase = "loading"
	_broadcast_lobby_state()
	load_match.rpc(MATCH_SCENE_PATH, active_match_id)


# This server-authority RPC runs from an Autoload path that exists on both
# computers before, during, and after the scene transition.
@rpc("authority", "call_local", "reliable")
func load_match(scene_path: String, requested_match_id: int) -> void:
	if not is_active() or scene_path != MATCH_SCENE_PATH:
		return
	if requested_match_id < active_match_id:
		return

	active_match_id = requested_match_id
	session_phase = "loading"
	scene_change_scheduled = true
	_set_status("Loading the shared LAN match...")
	lobby_changed.emit()
	match_loading.emit(active_match_id)
	call_deferred("_change_to_match_scene", requested_match_id)


# Deferring prevents the current lobby scene from being freed while this RPC
# callback is still running.
func _change_to_match_scene(requested_match_id: int) -> void:
	if not scene_change_scheduled or requested_match_id != active_match_id:
		return

	scene_change_scheduled = false
	var error := get_tree().change_scene_to_file(MATCH_SCENE_PATH)
	if error != OK:
		_set_status("Could not load the LAN match. Error code: %d" % error)


# Called by lan_knight_match.gd only after that scene's _ready has run. The
# host waits for every expected peer before it creates player nodes or sends
# gameplay RPCs to the new scene path.
func notify_local_match_loaded(loaded_match_id: int) -> void:
	if not is_active() or session_phase != "loading":
		return
	if loaded_match_id != active_match_id:
		return

	if is_host():
		_mark_match_peer_loaded(multiplayer.get_unique_id(), loaded_match_id)
	else:
		report_match_loaded.rpc_id(1, loaded_match_id)


@rpc("any_peer", "call_remote", "reliable")
func report_match_loaded(loaded_match_id: int) -> void:
	if not is_host() or loaded_match_id != active_match_id:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return

	_mark_match_peer_loaded(sender_id, loaded_match_id)


func _mark_match_peer_loaded(peer_id: int, loaded_match_id: int) -> void:
	if not is_host() or loaded_match_id != active_match_id:
		return
	if not expected_match_peers.has(peer_id):
		return

	loaded_match_peers[peer_id] = true
	if loaded_match_peers.size() != expected_match_peers.size():
		return

	# The new match root now exists at the same path on both computers, so its
	# player-spawn and combat RPCs are safe to begin.
	begin_match_gameplay.rpc(active_match_id)


@rpc("authority", "call_local", "reliable")
func begin_match_gameplay(loaded_match_id: int) -> void:
	if loaded_match_id != active_match_id:
		return

	session_phase = "match"
	_set_status("Shared LAN match started.")
	lobby_changed.emit()
	match_started.emit(active_match_id)


# The host shares a display-only roster with the client. The parallel arrays
# keep class and ready records aligned with the stable sorted peer-ID array.
func _broadcast_lobby_state() -> void:
	if not is_host():
		return

	var peer_ids := get_connected_peer_ids()
	var selected_characters := PackedStringArray()
	var ready_peer_ids := PackedInt32Array()
	for peer_id in peer_ids:
		selected_characters.append(get_selected_character(peer_id))
		if is_peer_ready(peer_id):
			ready_peer_ids.append(peer_id)

	apply_lobby_state.rpc(peer_ids, selected_characters, ready_peer_ids, session_phase)


@rpc("authority", "call_local", "reliable")
func apply_lobby_state(
	peer_ids: PackedInt32Array,
	selected_characters: PackedStringArray,
	ready_peer_ids: PackedInt32Array,
	new_phase: String
) -> void:
	lobby_peers.clear()
	selected_character_by_peer.clear()
	ready_by_peer.clear()

	for index in range(peer_ids.size()):
		var peer_id := int(peer_ids[index])
		lobby_peers[peer_id] = true
		selected_character_by_peer[peer_id] = selected_characters[index] if index < selected_characters.size() else ""
		ready_by_peer[peer_id] = ready_peer_ids.has(peer_id)

	session_phase = new_phase
	lobby_changed.emit()


func _on_peer_connected(peer_id: int) -> void:
	# The server sees all new connections. A client gets its roster through the
	# reliable apply_lobby_state RPC instead.
	if not is_host():
		return

	if session_phase != "lobby":
		# This first version deliberately does not allow a late join mid-match.
		network_peer.disconnect_peer(peer_id)
		return

	lobby_peers[peer_id] = true
	selected_character_by_peer[peer_id] = ""
	ready_by_peer[peer_id] = false
	_set_status("Player %d joined. Both players can now choose Knight, Archer, Mage, or Priest." % peer_id)
	_broadcast_lobby_state()


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_active() or not is_host():
		return

	lobby_peers.erase(peer_id)
	selected_character_by_peer.erase(peer_id)
	ready_by_peer.erase(peer_id)
	if session_phase == "lobby":
		_set_status("Player %d left. Waiting for one player." % peer_id)
		_broadcast_lobby_state()
		return

	# A match transition without both peers would leave gameplay in an unknown
	# state, so close this small test session and return the host to the lobby.
	call_deferred("_end_match_after_disconnect", peer_id)


func _on_connected_to_server() -> void:
	# A fast host can send load_match before this connection callback reaches the
	# client. Do not overwrite that newer loading state back to "lobby".
	if not is_active() or is_host() or session_phase != "connecting":
		return

	session_phase = "lobby"
	_set_status("Connected. Waiting for the host to start the match.")
	lobby_changed.emit()


func _on_connection_failed() -> void:
	if not is_active():
		return
	leave_session("Connection failed. Check the IP, Wi-Fi, and Windows Firewall.")


func _on_server_disconnected() -> void:
	if not is_active() or is_host():
		return

	leave_session("The host disconnected.")
	call_deferred("_return_to_lobby_after_disconnect")


func _end_match_after_disconnect(peer_id: int) -> void:
	if not is_active() or not is_host() or session_phase == "lobby":
		return

	leave_session("Player %d left, so the LAN match was closed." % peer_id)
	_return_to_lobby_after_disconnect()


func _return_to_lobby_after_disconnect() -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.scene_file_path == LOBBY_SCENE_PATH:
		return

	var error := get_tree().change_scene_to_file(LOBBY_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the LAN lobby. Error code: %d" % error)


func _set_status(message: String) -> void:
	current_status = message
	status_changed.emit(message)


func _get_lan_ip() -> String:
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127."):
			return address
	return "your IPv4 address"

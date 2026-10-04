extends Node2D

# A safe, stand-alone LAN proof of concept. It does not use the real combat,
# world, dungeon, or playable-character scenes.

const PORT := 7000
# One joining client plus the host keeps this proof of concept two-player only.
const MAX_CLIENTS := 1

@export var network_player_scene: PackedScene

@onready var players := get_node_or_null(^"players") as Node2D
@onready var ip_address := get_node_or_null(^"interface/panel/ip_address") as LineEdit
@onready var host_button := get_node_or_null(^"interface/panel/host_button") as Button
@onready var join_button := get_node_or_null(^"interface/panel/join_button") as Button
@onready var leave_button := get_node_or_null(^"interface/panel/leave_button") as Button
@onready var status_label := get_node_or_null(^"interface/panel/status_label") as Label

var network_peer: ENetMultiplayerPeer


func _ready() -> void:
	if host_button != null and not host_button.pressed.is_connected(host_game):
		host_button.pressed.connect(host_game)
	if join_button != null and not join_button.pressed.is_connected(join_game):
		join_button.pressed.connect(join_game)
	if leave_button != null and not leave_button.pressed.is_connected(leave_game):
		leave_button.pressed.connect(leave_game)

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

	_set_network_buttons(false)
	_set_status("Choose Host, or enter the host IP and choose Join.")


# Starts a LAN server on this computer and creates Player 1.
func host_game() -> void:
	if network_peer != null:
		return

	network_peer = ENetMultiplayerPeer.new()
	var error := network_peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		network_peer = null
		_set_status("Could not host on port %d. Error code: %d" % [PORT, error])
		return

	multiplayer.multiplayer_peer = network_peer
	_set_network_buttons(true)
	spawn_player(multiplayer.get_unique_id())
	_set_status("Hosting at %s:%d. Enter this IP on the other computer." % [_get_lan_ip(), PORT])


# Connects this game instance to a host on the same Wi-Fi or local network.
func join_game() -> void:
	if network_peer != null:
		return

	var address := ip_address.text.strip_edges() if ip_address != null else ""
	if address.is_empty():
		_set_status("Enter the host computer's IPv4 address first.")
		return

	network_peer = ENetMultiplayerPeer.new()
	var error := network_peer.create_client(address, PORT)
	if error != OK:
		network_peer = null
		_set_status("Could not connect to %s:%d. Error code: %d" % [address, PORT, error])
		return

	multiplayer.multiplayer_peer = network_peer
	_set_network_buttons(true)
	_set_status("Connecting to %s:%d..." % [address, PORT])


# The host creates the new player on every peer, then sends existing players
# specifically to the joining peer so both games have matching node paths.
func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var existing_player_ids: Array[int] = []
	if players != null:
		for player in players.get_children():
			existing_player_ids.append(player.get_multiplayer_authority())

	spawn_player.rpc(peer_id)
	for existing_player_id in existing_player_ids:
		spawn_player.rpc_id(peer_id, existing_player_id)

	_set_status("Player %d joined the test." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if players == null:
		return

	var player := players.get_node_or_null(NodePath(str(peer_id)))
	if player != null:
		player.queue_free()

	_set_status("Player %d left the test." % peer_id)


func _on_connected_to_server() -> void:
	_set_status("Connected. Use WASD to move your diamond.")


func _on_connection_failed() -> void:
	_set_status("Connection failed. Check the IP, Wi-Fi, and Windows Firewall.")
	_reset_network()


func _on_server_disconnected() -> void:
	_set_status("The host disconnected.")
	_reset_network()


# This RPC is only allowed from the server. call_local lets the host see itself.
@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int) -> void:
	if players == null or network_player_scene == null:
		return
	if players.get_node_or_null(NodePath(str(peer_id))) != null:
		return

	var player := network_player_scene.instantiate() as CharacterBody2D
	if player == null:
		push_error("Network Player Scene must have a CharacterBody2D root.")
		return

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.position = Vector2(360, 280) if peer_id == 1 else Vector2(520, 280)
	# A stable explicit name keeps the RPC path identical on every computer.
	players.add_child(player, true)


func leave_game() -> void:
	_set_status("Left the LAN test.")
	_reset_network()


func _reset_network() -> void:
	if network_peer != null:
		network_peer.close()

	multiplayer.multiplayer_peer = null
	network_peer = null

	if players != null:
		for player in players.get_children():
			player.queue_free()

	_set_network_buttons(false)


func _set_network_buttons(is_connected: bool) -> void:
	if host_button != null:
		host_button.disabled = is_connected
	if join_button != null:
		join_button.disabled = is_connected
	if leave_button != null:
		leave_button.disabled = not is_connected


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


# Finds one non-loopback IPv4 address to show the host. If multiple adapters are
# active, choose the address that matches the local network in Windows settings.
func _get_lan_ip() -> String:
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127."):
			return address
	return "your IPv4 address"


func _exit_tree() -> void:
	if network_peer != null:
		network_peer.close()


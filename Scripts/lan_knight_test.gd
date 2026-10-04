extends Node2D

# This is a separate LAN step. It does not change the main menu, World,
# Dungeon, normal player scene, enemies, or combat scripts.
# It now proves host-approved attacks, shared enemy/player health, a
# host-controlled chasing slime, shared player death/respawn, and
# host-authoritative Knight movement.

const PORT := 7001
# One joining client plus the host keeps this test to two players.
const MAX_CLIENTS := 1

# The host owns these values. Clients only ask to attack; they never choose
# damage, target health, or whether their attack reached the target.
const ATTACK_DAMAGE := 1
const ATTACK_COOLDOWN := 0.60
const ATTACK_HIT_DELAY := 0.26
const ATTACK_DURATION := 0.88

# The host also owns every Knight's health. The lava zone is only a controlled
# test source; it is not part of the real game's combat yet.
const PLAYER_MAX_HEALTH := 5
const DAMAGE_ZONE_DAMAGE := 1
const DAMAGE_ZONE_TICK_SECONDS := 1.0
const PLAYER_DAMAGE_INVULNERABILITY := 0.65
const PLAYER_RESPAWN_DELAY := 2.0

# Clients send only a direction. If an input packet (including a release) is
# lost, the host stops that Knight shortly after instead of letting it slide.
const MOVEMENT_INPUT_TIMEOUT := 0.25

@export var network_player_scene: PackedScene

@onready var players := get_node_or_null(^"players") as Node2D
@onready var training_dummy := get_node_or_null(^"training_dummy") as Node2D
@onready var damage_zone := get_node_or_null(^"damage_zone") as Area2D
@onready var ip_address := get_node_or_null(^"interface/panel/ip_address") as LineEdit
@onready var host_button := get_node_or_null(^"interface/panel/host_button") as Button
@onready var join_button := get_node_or_null(^"interface/panel/join_button") as Button
@onready var leave_button := get_node_or_null(^"interface/panel/leave_button") as Button
@onready var status_label := get_node_or_null(^"interface/panel/status_label") as Label

var network_peer: ENetMultiplayerPeer
var next_attack_time_by_peer: Dictionary = {}
var next_attack_sequence_by_peer: Dictionary = {}
var active_attack_sequence_by_peer: Dictionary = {}

# Each peer owns only its latest input. The host owns simulation and gives each
# resulting position a sequence number so old movement packets are ignored.
var movement_input_by_peer: Dictionary = {}
var last_movement_input_time_by_peer: Dictionary = {}
var last_movement_input_sequence_by_peer: Dictionary = {}
var next_movement_state_sequence_by_peer: Dictionary = {}

# These dictionaries are the host's source of truth for player life state.
var player_health_by_peer: Dictionary = {}
var player_dead_by_peer: Dictionary = {}
var player_state_revision_by_peer: Dictionary = {}
var next_player_damage_time_by_peer: Dictionary = {}
var next_damage_zone_tick_by_peer: Dictionary = {}
var respawn_token_by_peer: Dictionary = {}


func _ready() -> void:
	# Connect the menu buttons once when this test scene opens.
	if host_button != null and not host_button.pressed.is_connected(host_game):
		host_button.pressed.connect(host_game)
	if join_button != null and not join_button.pressed.is_connected(join_game):
		join_button.pressed.connect(join_game)
	if leave_button != null and not leave_button.pressed.is_connected(leave_game):
		leave_button.pressed.connect(leave_game)

	# These multiplayer signals tell the host or joining player what happened.
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


# Only the host moves Knights and checks the lava zone. Clients supply input
# but never choose a final position, wall result, collision, or damage result.
func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or players == null:
		return

	_simulate_host_player_movement()

	if damage_zone == null:
		return

	var now := Time.get_ticks_msec() / 1000.0
	for player in players.get_children():
		var peer_id := player.get_multiplayer_authority()
		if bool(player_dead_by_peer.get(peer_id, false)):
			continue
		if now < float(next_damage_zone_tick_by_peer.get(peer_id, 0.0)):
			continue

		var player_position: Vector2 = player.get(&"global_position")
		if bool(damage_zone.call(&"contains_global_position", player_position)):
			next_damage_zone_tick_by_peer[peer_id] = now + DAMAGE_ZONE_TICK_SECONDS
			damage_player_on_server(peer_id, DAMAGE_ZONE_DAMAGE)


# Starts a LAN server on this computer and creates the host Knight.
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

	# Reset this LAN-only enemy whenever a fresh host session begins.
	if training_dummy != null:
		training_dummy.call(&"reset_for_network_session")

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
		_set_status("Could not connect to %s:%d. Error code: %d" % [address, error])
		return

	multiplayer.multiplayer_peer = network_peer
	_set_network_buttons(true)
	_set_status("Connecting to %s:%d..." % [address, PORT])


# Only the host creates player nodes. It creates the joining Knight on both
# computers, then sends the host Knight to the joining computer.
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

	# The fixed test objects already exist in both scenes. Send their host-owned
	# state after the peer-ID player nodes have been created.
	if training_dummy != null:
		training_dummy.call(&"send_state_to_peer", peer_id)
	_send_player_states_to_peer(peer_id)

	_set_status("Player %d joined the Knight test." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if players != null:
		var player := players.get_node_or_null(NodePath(str(peer_id)))
		if player != null:
			player.queue_free()

	next_attack_time_by_peer.erase(peer_id)
	next_attack_sequence_by_peer.erase(peer_id)
	active_attack_sequence_by_peer.erase(peer_id)
	player_health_by_peer.erase(peer_id)
	player_dead_by_peer.erase(peer_id)
	player_state_revision_by_peer.erase(peer_id)
	next_player_damage_time_by_peer.erase(peer_id)
	next_damage_zone_tick_by_peer.erase(peer_id)
	respawn_token_by_peer.erase(peer_id)
	movement_input_by_peer.erase(peer_id)
	last_movement_input_time_by_peer.erase(peer_id)
	last_movement_input_sequence_by_peer.erase(peer_id)
	next_movement_state_sequence_by_peer.erase(peer_id)
	_set_status("Player %d left the Knight test." % peer_id)


func _on_connected_to_server() -> void:
	_set_status("Connected. The host now confirms Knight movement, slime combat, and respawn.")


func _on_connection_failed() -> void:
	_set_status("Connection failed. Check the IP, Wi-Fi, and Windows Firewall.")
	_reset_network()


func _on_server_disconnected() -> void:
	_set_status("The host disconnected.")
	_reset_network()


# A stable peer-ID node name makes the RPC path identical on both computers.
# call_local means the host also receives the same spawn instruction.
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
	player.position = _get_spawn_position(peer_id)
	players.add_child(player, true)

	# Only the server creates the canonical health and movement records.
	if multiplayer.is_server():
		_initialize_player_life(peer_id)
		_initialize_player_movement(peer_id)


# A client can submit only its own movement direction. The server gets the
# sender ID from Godot rather than trusting a player ID supplied by the client.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_movement_input(
	direction: Vector2,
	input_sequence: int,
	observed_life_revision: int
) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return

	submit_host_movement_input(sender_id, direction, input_sequence, observed_life_revision)


# The host player calls this same validation path directly. Input is clamped,
# sequenced, and discarded if it belongs to an old death/respawn life state.
func submit_host_movement_input(
	peer_id: int,
	direction: Vector2,
	input_sequence: int,
	observed_life_revision: int
) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	if not direction.is_finite():
		return
	if observed_life_revision != int(player_state_revision_by_peer.get(peer_id, -1)):
		return
	if input_sequence <= int(last_movement_input_sequence_by_peer.get(peer_id, -1)):
		return
	if _get_network_player(peer_id) == null:
		return

	movement_input_by_peer[peer_id] = direction.limit_length(1.0)
	last_movement_input_sequence_by_peer[peer_id] = input_sequence
	last_movement_input_time_by_peer[peer_id] = Time.get_ticks_msec() / 1000.0


# Clients can only request an attack from the host. The sender ID comes from
# Godot itself, not from a value supplied by the client. requested_facing makes
# a quick turn-and-click use the intended direction, never a client position.
@rpc("any_peer", "call_remote", "reliable")
func request_attack(requested_facing: int, observed_life_revision: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if observed_life_revision != int(player_state_revision_by_peer.get(sender_id, -1)):
		return

	request_host_attack(sender_id, requested_facing)


# The host also uses this helper for its own Knight. It checks the caller,
# life state, cooldown, and player node before it starts an attack.
func request_host_attack(peer_id: int, requested_facing: int = 0) -> void:
	if not multiplayer.is_server() or bool(player_dead_by_peer.get(peer_id, false)):
		return

	var player := _get_network_player(peer_id)
	if player == null or player.get_multiplayer_authority() != peer_id:
		return

	# A facing direction is safe to accept as input; the host still owns the
	# Knight position and its Area2D overlap when it evaluates damage.
	if requested_facing != 0:
		player.call(&"set_host_facing", requested_facing)

	# Never let a new request replace an attack that has not finished yet.
	if active_attack_sequence_by_peer.has(peer_id):
		return

	var now := Time.get_ticks_msec() / 1000.0
	var next_attack_time := float(next_attack_time_by_peer.get(peer_id, 0.0))
	if now < next_attack_time:
		return

	var sequence := int(next_attack_sequence_by_peer.get(peer_id, 0)) + 1
	next_attack_sequence_by_peer[peer_id] = sequence
	active_attack_sequence_by_peer[peer_id] = sequence
	next_attack_time_by_peer[peer_id] = now + ATTACK_COOLDOWN
	_clear_host_movement_input(peer_id)

	var facing_direction := int(player.get(&"facing_direction"))
	if facing_direction == 0:
		facing_direction = 1

	# This reliable RPC makes every screen show the same attack state.
	start_attack_visual.rpc(peer_id, sequence, facing_direction)
	_resolve_attack_after_delay(peer_id, sequence)
	_finish_attack_after_delay(peer_id, sequence)


# The root node keeps host authority, so it can safely broadcast attack visuals
# even for a Knight whose movement authority belongs to the joining player.
@rpc("authority", "call_local", "reliable")
func start_attack_visual(peer_id: int, sequence: int, facing_direction: int) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"start_network_attack", sequence, facing_direction)


@rpc("authority", "call_local", "reliable")
func finish_attack_visual(peer_id: int, sequence: int) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"finish_network_attack", sequence)


# The host waits until the sword visually reaches its contact frame, then asks
# the permanent LAN-only Area2D hitboxes whether the Knight really touched it.
func _resolve_attack_after_delay(peer_id: int, sequence: int) -> void:
	await get_tree().create_timer(ATTACK_HIT_DELAY).timeout

	if active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return
	if bool(player_dead_by_peer.get(peer_id, false)):
		return

	var player := _get_network_player(peer_id)
	if player == null or training_dummy == null:
		return

	# Only the host's copy of player_hitbox decides contact. The client never
	# reports a hit or chooses the target's new health.
	if bool(player.call(&"has_player_hitbox_overlap", training_dummy)):
		training_dummy.call(&"take_server_hit", ATTACK_DAMAGE)


func _finish_attack_after_delay(peer_id: int, sequence: int) -> void:
	await get_tree().create_timer(ATTACK_DURATION).timeout

	if active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return

	active_attack_sequence_by_peer.erase(peer_id)
	finish_attack_visual.rpc(peer_id, sequence)


# The lava pad calls this host-only helper indirectly through _physics_process.
# Later real enemies will use the same kind of host-owned damage entry point.
func damage_player_on_server(peer_id: int, damage: int) -> void:
	if not multiplayer.is_server() or damage <= 0:
		return
	if bool(player_dead_by_peer.get(peer_id, false)):
		return
	if _get_network_player(peer_id) == null:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now < float(next_player_damage_time_by_peer.get(peer_id, 0.0)):
		return

	var current_health := int(player_health_by_peer.get(peer_id, PLAYER_MAX_HEALTH))
	if current_health <= 0:
		return

	next_player_damage_time_by_peer[peer_id] = now + PLAYER_DAMAGE_INVULNERABILITY
	var new_health := maxi(0, current_health - damage)
	var new_revision := int(player_state_revision_by_peer.get(peer_id, 0)) + 1
	var defeated := new_health == 0

	player_health_by_peer[peer_id] = new_health
	player_state_revision_by_peer[peer_id] = new_revision
	player_dead_by_peer[peer_id] = defeated

	# A defeated Knight cannot finish an old queued attack after dying.
	if defeated:
		active_attack_sequence_by_peer.erase(peer_id)
		next_attack_time_by_peer.erase(peer_id)
		_clear_host_movement_input(peer_id)

	apply_player_state.rpc(peer_id, new_health, PLAYER_MAX_HEALTH, new_revision, defeated, Vector2.ZERO, false)

	if defeated:
		var token := int(respawn_token_by_peer.get(peer_id, 0)) + 1
		respawn_token_by_peer[peer_id] = token
		_respawn_player_after_delay(peer_id, token)


# Health, death, and respawn are sent from the root because it belongs to the
# host. A joining Knight's node is owned by the joining player, not the host.
@rpc("authority", "call_local", "reliable")
func apply_player_state(
	peer_id: int,
	current_health: int,
	maximum_health: int,
	revision: int,
	defeated: bool,
	move_to: Vector2,
	should_move: bool
) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(
			&"apply_network_health_state",
			current_health,
			maximum_health,
			revision,
			defeated,
			move_to,
			should_move
		)


func _initialize_player_life(peer_id: int) -> void:
	if player_health_by_peer.has(peer_id):
		return

	player_health_by_peer[peer_id] = PLAYER_MAX_HEALTH
	player_dead_by_peer[peer_id] = false
	player_state_revision_by_peer[peer_id] = 0
	apply_player_state.rpc(peer_id, PLAYER_MAX_HEALTH, PLAYER_MAX_HEALTH, 0, false, Vector2.ZERO, false)


func _initialize_player_movement(peer_id: int) -> void:
	movement_input_by_peer[peer_id] = Vector2.ZERO
	last_movement_input_time_by_peer[peer_id] = 0.0
	last_movement_input_sequence_by_peer[peer_id] = -1
	next_movement_state_sequence_by_peer[peer_id] = 0


# A late joiner receives an authoritative position through the existing
# reliable life-state RPC. This avoids waiting for a disposable motion packet.
func _send_player_states_to_peer(joining_peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	for player_id in player_health_by_peer:
		var peer_id := int(player_id)
		var player := _get_network_player(peer_id)
		var player_position := Vector2.ZERO
		if player is Node2D:
			player_position = player.global_position

		apply_player_state.rpc_id(
			joining_peer_id,
			peer_id,
			int(player_health_by_peer[player_id]),
			PLAYER_MAX_HEALTH,
			int(player_state_revision_by_peer.get(player_id, 0)),
			bool(player_dead_by_peer.get(player_id, false)),
			player_position,
			true
		)


# A token prevents an old timer from reviving someone who disconnected, left the
# test, or already received a newer life state.
func _respawn_player_after_delay(peer_id: int, token: int) -> void:
	await get_tree().create_timer(PLAYER_RESPAWN_DELAY).timeout

	if not multiplayer.is_server():
		return
	if int(respawn_token_by_peer.get(peer_id, -1)) != token:
		return
	if not bool(player_dead_by_peer.get(peer_id, false)):
		return
	if _get_network_player(peer_id) == null:
		return

	var new_revision := int(player_state_revision_by_peer.get(peer_id, 0)) + 1
	player_health_by_peer[peer_id] = PLAYER_MAX_HEALTH
	player_dead_by_peer[peer_id] = false
	player_state_revision_by_peer[peer_id] = new_revision
	next_player_damage_time_by_peer.erase(peer_id)
	next_damage_zone_tick_by_peer.erase(peer_id)
	_clear_host_movement_input(peer_id)

	apply_player_state.rpc(
		peer_id,
		PLAYER_MAX_HEALTH,
		PLAYER_MAX_HEALTH,
		new_revision,
		false,
		_get_spawn_position(peer_id),
		true
	)


func _get_spawn_position(peer_id: int) -> Vector2:
	return Vector2(460, 450) if peer_id == 1 else Vector2(600, 450)



# Runs on the host each physics frame. It performs every move_and_slide call,
# so wall collisions and positions are one shared truth for both computers.
func _simulate_host_player_movement() -> void:
	if players == null:
		return

	var now := Time.get_ticks_msec() / 1000.0
	for child in players.get_children():
		var player := child as CharacterBody2D
		if player == null:
			continue

		var peer_id := player.get_multiplayer_authority()
		var direction := Vector2.ZERO
		var last_input_time := float(last_movement_input_time_by_peer.get(peer_id, 0.0))

		if not bool(player_dead_by_peer.get(peer_id, false)):
			if now - last_input_time <= MOVEMENT_INPUT_TIMEOUT:
				direction = movement_input_by_peer.get(peer_id, Vector2.ZERO)

		player.call(&"simulate_host_movement", direction)

		var state_sequence := int(next_movement_state_sequence_by_peer.get(peer_id, 0)) + 1
		next_movement_state_sequence_by_peer[peer_id] = state_sequence

		var facing := int(player.get(&"facing_direction"))
		if facing == 0:
			facing = 1

		# A fast, ordered snapshot can be discarded safely because the next host
		# result replaces it. Health/death/respawn remain reliable RPCs.
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			sync_player_motion.rpc(
				peer_id,
				player.global_position,
				facing,
				bool(player.call(&"is_host_walking")),
				state_sequence,
				int(player_state_revision_by_peer.get(peer_id, 0))
			)


# This root-owned RPC works even though a joining Knight still owns its camera
# and keyboard node. The root itself is always owned by the host.
@rpc("authority", "call_remote", "unreliable_ordered", 2)
func sync_player_motion(
	peer_id: int,
	network_position: Vector2,
	network_facing: int,
	network_is_walking: bool,
	motion_sequence: int,
	motion_life_revision: int
) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(
			&"apply_network_motion_state",
			network_position,
			network_facing,
			network_is_walking,
			motion_sequence,
			motion_life_revision
		)


# Zeroes movement without resetting its sequence number. A later, newer input
# can still be accepted after an attack, defeat, or respawn.
func _clear_host_movement_input(peer_id: int) -> void:
	movement_input_by_peer[peer_id] = Vector2.ZERO
	last_movement_input_time_by_peer[peer_id] = Time.get_ticks_msec() / 1000.0


# The LAN slime asks the host for a target; it never accepts a target chosen by
# either player. Defeated Knights are ignored until the host respawns them.
func get_nearest_alive_player(from_position: Vector2) -> CharacterBody2D:
	if not multiplayer.is_server() or players == null:
		return null

	var closest_player: CharacterBody2D = null
	var closest_distance_squared := INF

	for child in players.get_children():
		var candidate := child as CharacterBody2D
		if candidate == null:
			continue

		var peer_id := candidate.get_multiplayer_authority()
		if bool(player_dead_by_peer.get(peer_id, false)):
			continue

		var distance_squared := from_position.distance_squared_to(candidate.global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_player = candidate

	return closest_player


# This gives the host slime a fresh, living target at its hit moment. It keeps
# an old queued attack from damaging a Knight who died or disconnected.
func get_alive_player(peer_id: int) -> CharacterBody2D:
	if not multiplayer.is_server() or bool(player_dead_by_peer.get(peer_id, false)):
		return null

	return _get_network_player(peer_id) as CharacterBody2D

func _get_network_player(peer_id: int) -> Node:
	if players == null:
		return null
	return players.get_node_or_null(NodePath(str(peer_id)))


func leave_game() -> void:
	_set_status("Left the LAN Knight test.")
	_reset_network()


func _reset_network() -> void:
	if network_peer != null:
		network_peer.close()

	multiplayer.multiplayer_peer = null
	network_peer = null

	if players != null:
		for player in players.get_children():
			player.queue_free()

	next_attack_time_by_peer.clear()
	next_attack_sequence_by_peer.clear()
	active_attack_sequence_by_peer.clear()
	player_health_by_peer.clear()
	player_dead_by_peer.clear()
	player_state_revision_by_peer.clear()
	next_player_damage_time_by_peer.clear()
	next_damage_zone_tick_by_peer.clear()
	respawn_token_by_peer.clear()
	movement_input_by_peer.clear()
	last_movement_input_time_by_peer.clear()
	last_movement_input_sequence_by_peer.clear()
	next_movement_state_sequence_by_peer.clear()
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


# Shows a usable local IPv4 address to the host. If several adapters are
# active, use the address that matches the local network in Windows settings.
func _get_lan_ip() -> String:
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127."):
			return address
	return "your IPv4 address"


func _exit_tree() -> void:
	if network_peer != null:
		network_peer.close()







extends Node2D

# The existing LAN scene keeps its stable name and group for compatibility,
# but it can now host a Knight, Archer, Mage, or Priest. The host remains the only
# authority for movement, combat, health, projectiles, and skill cooldowns.

const DEFAULT_PLAYER_MAX_HEALTH := 5
const DAMAGE_ZONE_DAMAGE := 1
const DAMAGE_ZONE_TICK_SECONDS := 1.0
const PLAYER_DAMAGE_INVULNERABILITY := 0.65
const PLAYER_RESPAWN_DELAY := 2.0
const MOVEMENT_INPUT_TIMEOUT := 0.25

# Dynamic LAN summons use the normal art scenes, but replace their local AI
# script with network_enemy.gd before they enter the scene tree.
const NETWORK_ENEMY_SCRIPT: Script = preload("res://Scripts/network_enemy.gd")
const LAN_SUMMON_EFFECT_SCENE: PackedScene = preload("res://Scenes/summon.tscn")
const NETWORK_SKELETON_ARROW_SCENE: PackedScene = preload("res://Scenes/network_skeleton_arrow.tscn")
const LAN_ENEMY_SCENES: Dictionary = {
	&"bat": preload("res://Scenes/bat.tscn"),
	&"slime": preload("res://Scenes/slime.tscn"),
	&"werewolf": preload("res://Scenes/werewolf.tscn"),
	&"werebear": preload("res://Scenes/werebear.tscn"),
	&"orc": preload("res://Scenes/enemy.tscn"),
	&"armored_orc": preload("res://Scenes/armored_orc.tscn"),
	&"orc_rider": preload("res://Scenes/orc_rider.tscn"),
	&"elite_orc": preload("res://Scenes/elite_orc.tscn"),
	&"skeleton": preload("res://Scenes/skeleton.tscn"),
	&"skeleton_archer": preload("res://Scenes/skeleton_archer.tscn"),
	&"armored_skeleton": preload("res://Scenes/armored_skeleton.tscn"),
	&"greatsword_skeleton": preload("res://Scenes/greatsword_skeleton.tscn"),
	&"necromancer": preload("res://Scenes/necromancer.tscn"),
}

@export var network_knight_player_scene: PackedScene
@export var network_archer_player_scene: PackedScene
@export var network_archer_arrow_scene: PackedScene
@export var network_mage_player_scene: PackedScene
@export var network_mage_fireball_scene: PackedScene
@export var network_mage_freeze_effect_scene: PackedScene
@export var network_priest_player_scene: PackedScene
@export var network_priest_auraplosion_effect_scene: PackedScene
@export var network_priest_heal_effect_scene: PackedScene

@onready var players := get_node_or_null(^"players") as Node2D
@onready var projectiles := get_node_or_null(^"projectiles") as Node2D
@onready var dynamic_enemies := get_node_or_null(^"dynamic_enemies") as Node2D
@onready var damage_zone := get_node_or_null(^"damage_zone") as Area2D
@onready var status_label := get_node_or_null(^"interface/panel/status_label") as Label
@onready var leave_button := get_node_or_null(^"interface/panel/leave_button") as Button

var match_is_active := false
var match_id := -1

# Shared host-owned player state. Joining players only supply movement and
# button intentions; they never decide positions, hits, health, or cooldowns.
var next_attack_sequence_by_peer: Dictionary = {}
var active_attack_sequence_by_peer: Dictionary = {}
var movement_input_by_peer: Dictionary = {}
var last_movement_input_time_by_peer: Dictionary = {}
var last_movement_input_sequence_by_peer: Dictionary = {}
var next_movement_state_sequence_by_peer: Dictionary = {}
var player_health_by_peer: Dictionary = {}
var player_dead_by_peer: Dictionary = {}
var player_state_revision_by_peer: Dictionary = {}
var next_player_damage_time_by_peer: Dictionary = {}
var next_damage_zone_tick_by_peer: Dictionary = {}
var respawn_token_by_peer: Dictionary = {}
var player_stunned_until_by_peer: Dictionary = {}

# Knight-only host state. Its actions now follow the same authoritative pattern
# as the other three classes: clients can request a button press, but cannot
# choose their own damage, cooldown, block window, or heavy-strike hit time.
var next_knight_action_time_by_key: Dictionary = {}
var knight_blocking_by_peer: Dictionary = {}
var knight_block_token_by_peer: Dictionary = {}

# Archer-only host state. It lives in this root instead of the visual player
# scene, so clients cannot fake a cooldown, strengthened hit, or dash speed.
var next_archer_attack_time_by_peer: Dictionary = {}
var next_archer_dash_time_by_peer: Dictionary = {}
var archer_dash_end_time_by_peer: Dictionary = {}
var archer_dash_direction_by_peer: Dictionary = {}
var archer_dash_speed_by_peer: Dictionary = {}
var next_archer_strength_time_by_peer: Dictionary = {}
var archer_strengthened_by_peer: Dictionary = {}
var archer_strength_token_by_peer: Dictionary = {}

# The host creates and moves these arrows. Every peer receives the same arrow
# scene and its snapshots, while only the host can turn a collision into damage.
var next_archer_arrow_id := 0
var active_archer_arrow_damage_by_id: Dictionary = {}

# Skeleton Archer arrows use their own replicated IDs so they never overlap
# with player Archer arrows, even when both fly at the same time.
var next_skeleton_arrow_id: int = 0
var active_skeleton_arrow_damage_by_id: Dictionary = {}

# Mage actions follow the same host-authority rule as Archer. Each action has
# its own cooldown key, while active_attack_sequence_by_peer prevents any cast
# from overlapping with another attack or skill.
var next_mage_action_time_by_key: Dictionary = {}
var next_mage_fireball_id := 0
var active_mage_fireball_config_by_id: Dictionary = {}
var mage_fireball_impact_token_by_id: Dictionary = {}

# Priest uses host-owned action cooldowns, self-healing, and a blue shield.
# Unlike a local visual tint, these dictionaries prevent clients from faking a
# heal or ignoring server-side damage.
var next_priest_action_time_by_key: Dictionary = {}
var priest_invulnerable_by_peer: Dictionary = {}
var next_priest_invulnerability_time_by_peer: Dictionary = {}
var priest_invulnerability_token_by_peer: Dictionary = {}

# IDs make summoned/spawned enemy paths identical on every connected computer.
var next_dynamic_enemy_id: int = 0
var next_lan_summon_effect_id: int = 0


func _ready() -> void:
	if leave_button != null:
		leave_button.pressed.connect(_on_leave_pressed)

	if not LanSession.match_started.is_connected(_on_match_started):
		LanSession.match_started.connect(_on_match_started)

	if not LanSession.is_active():
		_set_status("Open this scene through the LAN lobby.")
		return

	match_id = LanSession.active_match_id
	_set_status("Waiting for all LAN players to finish loading...")
	LanSession.notify_local_match_loaded(match_id)

	# This also supports reopening the scene after an already-complete handshake.
	if LanSession.is_match_active():
		_on_match_started(match_id)


# LanSession emits this only once both computers have loaded this same scene.
func _on_match_started(started_match_id: int) -> void:
	if started_match_id != match_id or match_is_active:
		return

	match_is_active = true
	_set_status("Host controls movement, combat, healing, shields, enemies, damage, and respawn.")

	if not multiplayer.is_server():
		return

	_reset_match_records()
	_reset_lan_enemies()

	# The character ID came from the host-approved lobby roster. Its RPC path is
	# stable on both computers because each spawned player uses its peer ID name.
	for peer_id in LanSession.get_connected_peer_ids():
		spawn_player.rpc(peer_id, LanSession.get_selected_character(peer_id))


func _physics_process(_delta: float) -> void:
	if not match_is_active or not multiplayer.is_server() or players == null:
		return

	_simulate_host_player_movement()
	_sync_archer_arrow_snapshots()
	_sync_skeleton_arrow_snapshots()
	_sync_mage_fireball_snapshots()

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


# A stable peer-ID node name keeps the child path identical even in a mixed
# Knight/Archer/Mage/Priest match. Only the host-approved character decides the
# scene, while the peer ID keeps every replicated node path stable.
@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int, approved_character: String) -> void:
	if players == null:
		return
	if players.get_node_or_null(NodePath(str(peer_id))) != null:
		return

	var player_scene := _get_network_player_scene(approved_character)
	if player_scene == null:
		push_error("The LAN match received a character that is not network-ready: %s" % approved_character)
		return

	var player := player_scene.instantiate() as CharacterBody2D
	if player == null:
		push_error("A LAN player scene must have a CharacterBody2D root.")
		return

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.position = _get_spawn_position(peer_id)
	if player.has_method(&"set_selected_character"):
		player.call(&"set_selected_character", approved_character)
	players.add_child(player, true)

	if multiplayer.is_server():
		_initialize_player_life(peer_id)
		_initialize_player_movement(peer_id)


func _get_network_player_scene(character_id: String) -> PackedScene:
	if character_id == LanSession.KNIGHT_CHARACTER_ID:
		return network_knight_player_scene
	if character_id == LanSession.ARCHER_CHARACTER_ID:
		return network_archer_player_scene
	if character_id == LanSession.MAGE_CHARACTER_ID:
		return network_mage_player_scene
	if character_id == LanSession.PRIEST_CHARACTER_ID:
		return network_priest_player_scene
	return null


# A client sends only its current direction. The host gets the true sender ID,
# clamps it, sequences it, and performs every move_and_slide call itself.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_movement_input(
	direction: Vector2,
	input_sequence: int,
	observed_life_revision: int
) -> void:
	if not match_is_active or not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id > 0:
		submit_host_movement_input(sender_id, direction, input_sequence, observed_life_revision)


func submit_host_movement_input(
	peer_id: int,
	direction: Vector2,
	input_sequence: int,
	observed_life_revision: int
) -> void:
	if not match_is_active or not multiplayer.is_server() or peer_id <= 0:
		return
	if not direction.is_finite():
		return
	if observed_life_revision != int(player_state_revision_by_peer.get(peer_id, -1)):
		return
	if input_sequence <= int(last_movement_input_sequence_by_peer.get(peer_id, -1)):
		return
	if _get_network_player(peer_id) == null:
		return
	if _is_player_stunned(peer_id):
		movement_input_by_peer[peer_id] = Vector2.ZERO
		last_movement_input_sequence_by_peer[peer_id] = input_sequence
		last_movement_input_time_by_peer[peer_id] = Time.get_ticks_msec() / 1000.0
		return

	movement_input_by_peer[peer_id] = direction.limit_length(1.0)
	last_movement_input_sequence_by_peer[peer_id] = input_sequence
	last_movement_input_time_by_peer[peer_id] = Time.get_ticks_msec() / 1000.0


# The old basic-attack RPC stays as a small compatibility route for an already
# open older client. New Knight scenes use request_knight_action for all four
# buttons, including Attack 2, Q, and E.
@rpc("any_peer", "call_remote", "reliable")
func request_attack(requested_facing: int, observed_life_revision: int) -> void:
	if not match_is_active or not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if observed_life_revision != int(player_state_revision_by_peer.get(sender_id, -1)):
		return
	request_host_knight_action(sender_id, "attack1", requested_facing)


# Every new Knight input has a life revision so the host ignores a late click
# from before a death or respawn. The action name is only an intention; the
# configuration below comes from the host's Knight player scene.
@rpc("any_peer", "call_remote", "reliable")
func request_knight_action(
	action_id: String,
	requested_facing: int,
	observed_life_revision: int
) -> void:
	if not match_is_active or not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if observed_life_revision != int(player_state_revision_by_peer.get(sender_id, -1)):
		return
	request_host_knight_action(sender_id, action_id, requested_facing)


func request_host_attack(peer_id: int, requested_facing: int = 0) -> void:
	request_host_knight_action(peer_id, "attack1", requested_facing)


func request_host_knight_action(
	peer_id: int,
	action_id: String,
	requested_facing: int = 0
) -> void:
	if not match_is_active or not multiplayer.is_server() or bool(player_dead_by_peer.get(peer_id, false)) or _is_player_stunned(peer_id):
		return
	if LanSession.get_selected_character(peer_id) != LanSession.KNIGHT_CHARACTER_ID:
		return

	var player := _get_network_player(peer_id)
	if player == null or player.get_multiplayer_authority() != peer_id:
		return
	if requested_facing != 0:
		player.call(&"set_host_facing", requested_facing)
	if active_attack_sequence_by_peer.has(peer_id):
		return
	if action_id == "skill2" and bool(knight_blocking_by_peer.get(peer_id, false)):
		return

	var config := _get_knight_action_config(player, action_id)
	if config.is_empty():
		return

	var now := Time.get_ticks_msec() / 1000.0
	var cooldown_key := _get_knight_cooldown_key(peer_id, action_id)
	if now < float(next_knight_action_time_by_key.get(cooldown_key, 0.0)):
		return

	var sequence := int(next_attack_sequence_by_peer.get(peer_id, 0)) + 1
	next_attack_sequence_by_peer[peer_id] = sequence
	active_attack_sequence_by_peer[peer_id] = sequence
	_clear_host_movement_input(peer_id)

	var facing_direction := int(player.get(&"facing_direction"))
	if facing_direction == 0:
		facing_direction = 1

	start_knight_action_visual.rpc(peer_id, sequence, facing_direction, action_id)

	if action_id == "skill2":
		var block_token := int(knight_block_token_by_peer.get(peer_id, 0)) + 1
		knight_block_token_by_peer[peer_id] = block_token
		knight_blocking_by_peer[peer_id] = true
		_finish_knight_block_after_delay(peer_id, sequence, block_token, config)
		return

	var cooldown := maxf(0.01, float(config.get("cooldown", 0.01)))
	next_knight_action_time_by_key[cooldown_key] = now + cooldown
	_resolve_knight_action_after_delay(peer_id, sequence, config)
	_finish_knight_action_after_delay(peer_id, sequence, config)


func _get_knight_action_config(player: Node, action_id: String) -> Dictionary:
	if player == null or not player.has_method(&"get_network_knight_action_config"):
		return {}
	var config_value: Variant = player.call(&"get_network_knight_action_config", action_id)
	return config_value if config_value is Dictionary else {}


func _get_knight_cooldown_key(peer_id: int, action_id: String) -> String:
	return "%d:%s" % [peer_id, action_id]


@rpc("authority", "call_local", "reliable")
func start_knight_action_visual(
	peer_id: int,
	sequence: int,
	facing_direction: int,
	action_id: String
) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"start_network_knight_action", sequence, facing_direction, action_id)


@rpc("authority", "call_local", "reliable")
func finish_knight_action_visual(peer_id: int, sequence: int) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"finish_network_knight_action", sequence)


func _resolve_knight_action_after_delay(peer_id: int, sequence: int, config: Dictionary) -> void:
	var action_duration := maxf(0.01, float(config.get("duration", 0.01)))
	var hit_time := clampf(float(config.get("hit_time", 0.0)), 0.0, action_duration)
	await get_tree().create_timer(hit_time).timeout
	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return
	if bool(player_dead_by_peer.get(peer_id, false)):
		return

	var player := _get_network_player(peer_id)
	if player == null or not player.has_method(&"has_player_hitbox_overlap"):
		return

	# The host still requires the Knight's real forward Area2D overlap. Checking
	# every living LAN enemy lets a wide swing hit a small group without trusting
	# a client to name or choose its own target.
	for enemy: Node2D in _get_lan_enemies():
		if not _is_valid_lan_enemy_target(enemy):
			continue
		var enemy_body: CharacterBody2D = enemy as CharacterBody2D
		if enemy_body != null and bool(player.call(&"has_player_hitbox_overlap", enemy_body)):
			_damage_lan_enemy(enemy, int(config.get("damage", 0)))


func _finish_knight_action_after_delay(peer_id: int, sequence: int, config: Dictionary) -> void:
	var action_duration := maxf(0.01, float(config.get("duration", 0.01)))
	await get_tree().create_timer(action_duration).timeout
	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return

	active_attack_sequence_by_peer.erase(peer_id)
	finish_knight_action_visual.rpc(peer_id, sequence)


# E ends normally once the one-shot block animation finishes. Its cooldown starts
# at that moment, just as it does when the normal Knight's block window expires.
func _finish_knight_block_after_delay(
	peer_id: int,
	sequence: int,
	block_token: int,
	config: Dictionary
) -> void:
	var block_duration := maxf(0.01, float(config.get("duration", 0.01)))
	await get_tree().create_timer(block_duration).timeout
	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return
	if int(knight_block_token_by_peer.get(peer_id, -1)) != block_token:
		return
	if not bool(knight_blocking_by_peer.get(peer_id, false)):
		return

	_end_knight_block(peer_id, sequence, config)


# Called only by damage_player_on_server after the host confirms a real incoming
# hit. It consumes the block instead of changing health and starts cooldown.
func _consume_knight_block(peer_id: int) -> bool:
	if LanSession.get_selected_character(peer_id) != LanSession.KNIGHT_CHARACTER_ID:
		return false
	if not bool(knight_blocking_by_peer.get(peer_id, false)):
		return false

	var player := _get_network_player(peer_id)
	var config := _get_knight_action_config(player, "skill2")
	var sequence := int(active_attack_sequence_by_peer.get(peer_id, -1))
	if config.is_empty() or sequence < 0:
		return false

	_end_knight_block(peer_id, sequence, config)
	return true


func _end_knight_block(peer_id: int, sequence: int, config: Dictionary) -> void:
	knight_blocking_by_peer[peer_id] = false
	knight_block_token_by_peer[peer_id] = int(knight_block_token_by_peer.get(peer_id, 0)) + 1
	var cooldown := maxf(0.01, float(config.get("cooldown", 0.01)))
	next_knight_action_time_by_key[_get_knight_cooldown_key(peer_id, "skill2")] = Time.get_ticks_msec() / 1000.0 + cooldown

	if active_attack_sequence_by_peer.get(peer_id, -1) == sequence:
		active_attack_sequence_by_peer.erase(peer_id)
		finish_knight_action_visual.rpc(peer_id, sequence)


# Mage requests contain only the spell button, facing, and the life revision
# the client last saw. The host chooses whether a target exists, when the cast
# releases, which debuff applies, and what damage is dealt.
@rpc("any_peer", "call_remote", "reliable")
func request_mage_action(
	action_id: String,
	requested_facing: int,
	observed_life_revision: int
) -> void:
	if not match_is_active or not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if observed_life_revision != int(player_state_revision_by_peer.get(sender_id, -1)):
		return

	request_host_mage_action(sender_id, action_id, requested_facing)


func request_host_mage_action(
	peer_id: int,
	action_id: String,
	requested_facing: int = 0
) -> void:
	if not match_is_active or not multiplayer.is_server() or bool(player_dead_by_peer.get(peer_id, false)) or _is_player_stunned(peer_id):
		return
	if LanSession.get_selected_character(peer_id) != LanSession.MAGE_CHARACTER_ID:
		return

	var player := _get_network_player(peer_id)
	if player == null or player.get_multiplayer_authority() != peer_id:
		return
	if active_attack_sequence_by_peer.has(peer_id):
		return
	if requested_facing != 0:
		player.call(&"set_host_facing", requested_facing)

	var config := _get_mage_action_config(player, action_id)
	if config.is_empty():
		return

	# The normal Mage only starts targeted spells if an enemy is currently in
	# range. Attack 1 and the forward fireball can still be cast into open space.
	if action_id == "attack2":
		if _get_nearest_lan_enemy_for_player(player, float(config.get("target_range", 0.0))) == null:
			return
	elif action_id == "skill1":
		if _get_nearest_lan_enemy_for_player(player, float(config.get("target_range", 0.0))) == null:
			return
	elif action_id != "attack1" and action_id != "skill2":
		return

	var now := Time.get_ticks_msec() / 1000.0
	var cooldown_key := _get_mage_cooldown_key(peer_id, action_id)
	if now < float(next_mage_action_time_by_key.get(cooldown_key, 0.0)):
		return

	var sequence := int(next_attack_sequence_by_peer.get(peer_id, 0)) + 1
	var cooldown := maxf(0.01, float(config.get("cooldown", 0.01)))
	next_attack_sequence_by_peer[peer_id] = sequence
	active_attack_sequence_by_peer[peer_id] = sequence
	next_mage_action_time_by_key[cooldown_key] = now + cooldown
	_clear_host_movement_input(peer_id)

	var facing_direction := int(player.get(&"facing_direction"))
	if facing_direction == 0:
		facing_direction = 1

	start_mage_action_visual.rpc(peer_id, sequence, facing_direction, action_id)
	_release_mage_action_after_delay(peer_id, sequence, action_id, config)
	_finish_mage_action_after_delay(peer_id, sequence, config)


func _get_mage_action_config(player: Node, action_id: String) -> Dictionary:
	if player == null or not player.has_method(&"get_network_mage_action_config"):
		return {}
	var config_value: Variant = player.call(&"get_network_mage_action_config", action_id)
	return config_value if config_value is Dictionary else {}


func _get_mage_cooldown_key(peer_id: int, action_id: String) -> String:
	return "%d:%s" % [peer_id, action_id]


@rpc("authority", "call_local", "reliable")
func start_mage_action_visual(
	peer_id: int,
	sequence: int,
	facing_direction: int,
	action_id: String
) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"start_network_mage_action", sequence, facing_direction, action_id)


@rpc("authority", "call_local", "reliable")
func finish_mage_action_visual(peer_id: int, sequence: int) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"finish_network_mage_action", sequence)


func _release_mage_action_after_delay(
	peer_id: int,
	sequence: int,
	action_id: String,
	config: Dictionary
) -> void:
	var cast_duration := maxf(0.01, float(config.get("cast_duration", 0.01)))
	var release_time := clampf(float(config.get("release_time", 0.0)), 0.0, cast_duration)
	await get_tree().create_timer(release_time).timeout

	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return
	if bool(player_dead_by_peer.get(peer_id, false)):
		return

	var player := _get_network_player(peer_id)
	if player == null:
		return

	match action_id:
		"attack1":
			_apply_mage_close_freeze(player, config)
		"attack2":
			_apply_mage_fire_explosion(player, config)
		"skill1":
			_apply_mage_freeze_area(player, config)
		"skill2":
			_spawn_mage_fireball_on_server(peer_id, player, config)


func _finish_mage_action_after_delay(peer_id: int, sequence: int, config: Dictionary) -> void:
	var cast_duration := maxf(0.01, float(config.get("cast_duration", 0.01)))
	await get_tree().create_timer(cast_duration).timeout
	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return

	active_attack_sequence_by_peer.erase(peer_id)
	finish_mage_action_visual.rpc(peer_id, sequence)


func _apply_mage_close_freeze(player: Node, config: Dictionary) -> void:
	var player_body: Node2D = player as Node2D
	if player_body == null:
		return

	var radius := maxf(0.0, float(config.get("range", 0.0)))
	var freeze_duration := float(config.get("freeze_duration", 0.0))
	for enemy: Node2D in _get_alive_lan_enemies_in_radius(player_body.global_position, radius):
		_apply_lan_enemy_freeze(enemy, freeze_duration)


func _apply_mage_fire_explosion(player: Node, config: Dictionary) -> void:
	var target_range := maxf(0.0, float(config.get("target_range", 0.0)))
	var target := _get_nearest_lan_enemy_for_player(player, target_range)
	if target == null:
		return

	# The host chooses one nearby target as the explosion center, then resolves
	# damage and burn for every living LAN enemy inside the visible radius.
	var explosion_radius := maxf(0.0, float(config.get("explosion_radius", 0.0)))
	if explosion_radius <= 0.0:
		return

	var damage := int(config.get("damage", 0))
	var burn_duration := float(config.get("burn_duration", 0.0))
	var burn_damage := int(config.get("burn_damage", 0))
	var burn_interval := float(config.get("burn_interval", 0.0))
	for enemy: Node2D in _get_alive_lan_enemies_in_radius(target.global_position, explosion_radius):
		_damage_lan_enemy(enemy, damage)
		_apply_lan_enemy_burn(enemy, burn_duration, burn_damage, burn_interval)


func _apply_mage_freeze_area(player: Node, config: Dictionary) -> void:
	var target_range := maxf(0.0, float(config.get("target_range", 0.0)))
	var target := _get_nearest_lan_enemy_for_player(player, target_range)
	if target == null:
		return

	var target_position: Vector2 = target.global_position
	spawn_network_mage_freeze_effect.rpc(target_position)
	_apply_lan_enemy_freeze(target, float(config.get("freeze_duration", 0.0)))


# Priest requests have the same trust boundary as Mage requests: a client may
# say which button it pressed, but only the host decides range, damage, healing,
# cooldowns, and whether the blue invulnerability shield is truly active.
@rpc("any_peer", "call_remote", "reliable")
func request_priest_action(
	action_id: String,
	requested_facing: int,
	observed_life_revision: int
) -> void:
	if not match_is_active or not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if observed_life_revision != int(player_state_revision_by_peer.get(sender_id, -1)):
		return

	request_host_priest_action(sender_id, action_id, requested_facing)


func request_host_priest_action(
	peer_id: int,
	action_id: String,
	requested_facing: int = 0
) -> void:
	if not match_is_active or not multiplayer.is_server() or bool(player_dead_by_peer.get(peer_id, false)) or _is_player_stunned(peer_id):
		return
	if LanSession.get_selected_character(peer_id) != LanSession.PRIEST_CHARACTER_ID:
		return

	var player := _get_network_player(peer_id)
	if player == null or player.get_multiplayer_authority() != peer_id:
		return
	if active_attack_sequence_by_peer.has(peer_id):
		return
	if requested_facing != 0:
		player.call(&"set_host_facing", requested_facing)

	var config := _get_priest_action_config(player, action_id)
	if config.is_empty():
		return

	# Attack 2 needs a valid host-side target before its cast begins. Q begins
	# when at least one living party member in its healing circle needs health.
	if action_id == "attack2":
		if _get_nearest_lan_enemy_for_player(player, float(config.get("target_range", 0.0))) == null:
			return
	elif action_id == "skill1":
		var heal_radius: float = maxf(0.0, float(config.get("heal_radius", 0.0)))
		if not _has_healable_lan_player_in_radius(player.global_position, heal_radius):
			return
	elif action_id != "attack1" and action_id != "skill2":
		return

	var now := Time.get_ticks_msec() / 1000.0
	if action_id == "skill2":
		if bool(priest_invulnerable_by_peer.get(peer_id, false)):
			return
		if now < float(next_priest_invulnerability_time_by_peer.get(peer_id, 0.0)):
			return

		next_priest_invulnerability_time_by_peer[peer_id] = now + maxf(0.01, float(config.get("cooldown", 0.01)))
		var invulnerability_token := int(priest_invulnerability_token_by_peer.get(peer_id, 0)) + 1
		priest_invulnerability_token_by_peer[peer_id] = invulnerability_token
		_set_priest_invulnerable(peer_id, true)
		_expire_priest_invulnerability_after_delay(peer_id, invulnerability_token, maxf(0.01, float(config.get("duration", 0.01))))
		return

	var cooldown_key := _get_priest_cooldown_key(peer_id, action_id)
	if now < float(next_priest_action_time_by_key.get(cooldown_key, 0.0)):
		return

	var sequence := int(next_attack_sequence_by_peer.get(peer_id, 0)) + 1
	var cooldown := maxf(0.01, float(config.get("cooldown", 0.01)))
	next_attack_sequence_by_peer[peer_id] = sequence
	active_attack_sequence_by_peer[peer_id] = sequence
	next_priest_action_time_by_key[cooldown_key] = now + cooldown
	_clear_host_movement_input(peer_id)

	var facing_direction := int(player.get(&"facing_direction"))
	if facing_direction == 0:
		facing_direction = 1

	start_priest_action_visual.rpc(peer_id, sequence, facing_direction, action_id)
	_release_priest_action_after_delay(peer_id, sequence, action_id, config)
	_finish_priest_action_after_delay(peer_id, sequence, config)


func _get_priest_action_config(player: Node, action_id: String) -> Dictionary:
	if player == null or not player.has_method(&"get_network_priest_action_config"):
		return {}
	var config_value: Variant = player.call(&"get_network_priest_action_config", action_id)
	return config_value if config_value is Dictionary else {}


func _get_priest_cooldown_key(peer_id: int, action_id: String) -> String:
	return "%d:%s" % [peer_id, action_id]


@rpc("authority", "call_local", "reliable")
func start_priest_action_visual(
	peer_id: int,
	sequence: int,
	facing_direction: int,
	action_id: String
) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"start_network_priest_action", sequence, facing_direction, action_id)


@rpc("authority", "call_local", "reliable")
func finish_priest_action_visual(peer_id: int, sequence: int) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"finish_network_priest_action", sequence)


func _release_priest_action_after_delay(
	peer_id: int,
	sequence: int,
	action_id: String,
	config: Dictionary
) -> void:
	var cast_duration := maxf(0.01, float(config.get("cast_duration", 0.01)))
	var release_time := clampf(float(config.get("release_time", 0.0)), 0.0, cast_duration)
	await get_tree().create_timer(release_time).timeout

	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return
	if bool(player_dead_by_peer.get(peer_id, false)):
		return

	var player := _get_network_player(peer_id)
	if player == null:
		return

	match action_id:
		"attack1":
			_apply_priest_close_auraplosion(player, config)
		"attack2":
			_apply_priest_ranged_auraplosion(player, config)
		"skill1":
			_apply_priest_heal(peer_id, player, config)


func _finish_priest_action_after_delay(peer_id: int, sequence: int, config: Dictionary) -> void:
	var cast_duration := maxf(0.01, float(config.get("cast_duration", 0.01)))
	await get_tree().create_timer(cast_duration).timeout
	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return

	active_attack_sequence_by_peer.erase(peer_id)
	finish_priest_action_visual.rpc(peer_id, sequence)


func _apply_priest_close_auraplosion(player: Node, config: Dictionary) -> void:
	var player_body: Node2D = player as Node2D
	if player_body == null:
		return

	var radius := maxf(0.0, float(config.get("range", 0.0)))
	var damage := int(config.get("damage", 0))
	for enemy: Node2D in _get_alive_lan_enemies_in_radius(player_body.global_position, radius):
		_damage_lan_enemy(enemy, damage)


func _apply_priest_ranged_auraplosion(player: Node, config: Dictionary) -> void:
	var target := _get_nearest_lan_enemy_for_player(player, maxf(0.0, float(config.get("target_range", 0.0))))
	if target == null:
		return

	var target_position: Vector2 = target.global_position
	spawn_network_priest_auraplosion_effect.rpc(target_position)
	_damage_lan_enemy(target, int(config.get("damage", 0)))


func _apply_priest_heal(_peer_id: int, player: Node, config: Dictionary) -> void:
	var priest: Node2D = player as Node2D
	if priest == null:
		return

	# Q keeps its self-heal, then also restores every living teammate close to
	# the Priest. The host chooses the targets so every computer sees the same HP.
	var heal_amount: int = int(config.get("heal_amount", 0))
	var heal_radius: float = maxf(0.0, float(config.get("heal_radius", 0.0)))
	for target: CharacterBody2D in get_alive_players_in_radius(priest.global_position, heal_radius):
		var target_peer_id: int = target.get_multiplayer_authority()
		if heal_player_on_server(target_peer_id, heal_amount):
			# Only show the animated heal on players who actually regained HP.
			spawn_network_priest_heal_effect.rpc(target.global_position)


# Returns true only when an alive player inside the Priest's Q circle is hurt.
# This lets a full-health Priest heal an injured teammate without wasting Q.
func _has_healable_lan_player_in_radius(center: Vector2, radius: float) -> bool:
	for candidate: CharacterBody2D in get_alive_players_in_radius(center, radius):
		var candidate_peer_id: int = candidate.get_multiplayer_authority()
		var maximum_health: int = _get_player_max_health(candidate_peer_id)
		var current_health: int = int(player_health_by_peer.get(candidate_peer_id, maximum_health))
		if current_health < maximum_health:
			return true
	return false


func _set_priest_invulnerable(peer_id: int, enabled: bool) -> void:
	if LanSession.get_selected_character(peer_id) != LanSession.PRIEST_CHARACTER_ID:
		return

	priest_invulnerable_by_peer[peer_id] = enabled
	set_priest_invulnerable_visual.rpc(peer_id, enabled)


@rpc("authority", "call_local", "reliable")
func set_priest_invulnerable_visual(peer_id: int, enabled: bool) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"set_network_invulnerable", enabled)


func _expire_priest_invulnerability_after_delay(peer_id: int, token: int, duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	if not match_is_active or not multiplayer.is_server():
		return
	if int(priest_invulnerability_token_by_peer.get(peer_id, -1)) != token:
		return
	_set_priest_invulnerable(peer_id, false)


# Archer requests contain only a named button, facing, and optional dash
# direction. The host validates the class and chooses all combat values.
@rpc("any_peer", "call_remote", "reliable")
func request_archer_action(
	action_id: String,
	requested_facing: int,
	requested_direction: Vector2,
	observed_life_revision: int
) -> void:
	if not match_is_active or not multiplayer.is_server() or not requested_direction.is_finite():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if observed_life_revision != int(player_state_revision_by_peer.get(sender_id, -1)):
		return
	request_host_archer_action(sender_id, action_id, requested_facing, requested_direction)


func request_host_archer_action(
	peer_id: int,
	action_id: String,
	requested_facing: int = 0,
	requested_direction: Vector2 = Vector2.ZERO
) -> void:
	if not match_is_active or not multiplayer.is_server() or bool(player_dead_by_peer.get(peer_id, false)) or _is_player_stunned(peer_id):
		return
	if LanSession.get_selected_character(peer_id) != LanSession.ARCHER_CHARACTER_ID:
		return
	if not requested_direction.is_finite():
		return

	var player := _get_network_player(peer_id)
	if player == null or player.get_multiplayer_authority() != peer_id:
		return
	if active_attack_sequence_by_peer.has(peer_id) or _is_archer_dashing(peer_id):
		return
	if requested_facing != 0:
		player.call(&"set_host_facing", requested_facing)

	var now := Time.get_ticks_msec() / 1000.0
	match action_id:
		"attack1", "attack2":
			_begin_archer_arrow_attack(peer_id, player, action_id, now)
		"skill1":
			_begin_archer_dash(peer_id, player, requested_direction, now)
		"skill2":
			_begin_archer_strengthen(peer_id, player, now)


func _begin_archer_arrow_attack(peer_id: int, player: Node, action_id: String, now: float) -> void:
	if now < float(next_archer_attack_time_by_peer.get(peer_id, 0.0)):
		return

	var config := _get_archer_attack_config(player, action_id)
	if config.is_empty():
		return

	var sequence := int(next_attack_sequence_by_peer.get(peer_id, 0)) + 1
	var cooldown := maxf(0.01, float(config.get("cooldown", 0.01)))
	next_attack_sequence_by_peer[peer_id] = sequence
	active_attack_sequence_by_peer[peer_id] = sequence
	next_archer_attack_time_by_peer[peer_id] = now + cooldown
	_clear_host_movement_input(peer_id)

	var facing_direction := int(player.get(&"facing_direction"))
	if facing_direction == 0:
		facing_direction = 1

	start_archer_attack_visual.rpc(peer_id, sequence, facing_direction, action_id)
	_release_archer_arrow_after_delay(peer_id, sequence, action_id, config)
	_finish_archer_attack_after_delay(peer_id, sequence, config)


func _get_archer_attack_config(player: Node, action_id: String) -> Dictionary:
	if player == null or not player.has_method(&"get_network_archer_attack_config"):
		return {}
	var config_value: Variant = player.call(&"get_network_archer_attack_config", action_id)
	return config_value if config_value is Dictionary else {}


@rpc("authority", "call_local", "reliable")
func start_archer_attack_visual(
	peer_id: int,
	sequence: int,
	facing_direction: int,
	action_id: String
) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"start_network_archer_attack", sequence, facing_direction, action_id)


@rpc("authority", "call_local", "reliable")
func finish_archer_attack_visual(peer_id: int, sequence: int) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"finish_network_archer_attack", sequence)


func _release_archer_arrow_after_delay(
	peer_id: int,
	sequence: int,
	action_id: String,
	config: Dictionary
) -> void:
	var attack_duration := maxf(0.01, float(config.get("duration", 0.01)))
	var release_time := clampf(float(config.get("release_time", 0.0)), 0.0, attack_duration)
	await get_tree().create_timer(release_time).timeout

	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return
	if bool(player_dead_by_peer.get(peer_id, false)):
		return

	var damage := int(config.get("damage", 1))
	var arrow_scale := float(config.get("arrow_scale", 1.0))
	if action_id == "attack1" and bool(archer_strengthened_by_peer.get(peer_id, false)):
		var player := _get_network_player(peer_id)
		var strength_config := _get_archer_strength_config(player)
		damage += int(strength_config.get("bonus_damage", 0))
		arrow_scale = float(strength_config.get("arrow_scale", arrow_scale))
		_set_archer_strengthened(peer_id, false)

	_spawn_archer_arrow_on_server(peer_id, damage, arrow_scale)


func _finish_archer_attack_after_delay(peer_id: int, sequence: int, config: Dictionary) -> void:
	var duration := maxf(0.01, float(config.get("duration", 0.01)))
	await get_tree().create_timer(duration).timeout
	if not match_is_active or active_attack_sequence_by_peer.get(peer_id, -1) != sequence:
		return

	active_attack_sequence_by_peer.erase(peer_id)
	finish_archer_attack_visual.rpc(peer_id, sequence)


func _begin_archer_dash(peer_id: int, player: Node, requested_direction: Vector2, now: float) -> void:
	if now < float(next_archer_dash_time_by_peer.get(peer_id, 0.0)):
		return

	var config := _get_archer_dash_config(player)
	if config.is_empty():
		return

	var dash_direction := requested_direction.limit_length(1.0)
	if dash_direction.is_zero_approx():
		var facing_direction := int(player.get(&"facing_direction"))
		dash_direction = Vector2(1.0 if facing_direction >= 0 else -1.0, 0.0)
	if not is_zero_approx(dash_direction.x):
		player.call(&"set_host_facing", 1 if dash_direction.x > 0.0 else -1)

	var duration := maxf(0.01, float(config.get("duration", 0.01)))
	next_archer_dash_time_by_peer[peer_id] = now + maxf(0.01, float(config.get("cooldown", 0.01)))
	archer_dash_end_time_by_peer[peer_id] = now + duration
	archer_dash_direction_by_peer[peer_id] = dash_direction
	archer_dash_speed_by_peer[peer_id] = maxf(1.0, float(config.get("speed", 1.0)))
	_clear_host_movement_input(peer_id)
	start_archer_dash_visual.rpc(peer_id, dash_direction)


func _get_archer_dash_config(player: Node) -> Dictionary:
	if player == null or not player.has_method(&"get_network_dash_config"):
		return {}
	var config_value: Variant = player.call(&"get_network_dash_config")
	return config_value if config_value is Dictionary else {}


@rpc("authority", "call_local", "reliable")
func start_archer_dash_visual(peer_id: int, dash_direction: Vector2) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"start_network_archer_dash", dash_direction)


@rpc("authority", "call_local", "reliable")
func finish_archer_dash_visual(peer_id: int) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"finish_network_archer_dash")


func _begin_archer_strengthen(peer_id: int, player: Node, now: float) -> void:
	if now < float(next_archer_strength_time_by_peer.get(peer_id, 0.0)):
		return

	var config := _get_archer_strength_config(player)
	if config.is_empty():
		return

	next_archer_strength_time_by_peer[peer_id] = now + maxf(0.01, float(config.get("cooldown", 0.01)))
	var token := int(archer_strength_token_by_peer.get(peer_id, 0)) + 1
	archer_strength_token_by_peer[peer_id] = token
	_set_archer_strengthened(peer_id, true)
	_expire_archer_strength_after_delay(peer_id, token, maxf(0.01, float(config.get("duration", 0.01))))


func _get_archer_strength_config(player: Node) -> Dictionary:
	if player == null or not player.has_method(&"get_network_strength_config"):
		return {}
	var config_value: Variant = player.call(&"get_network_strength_config")
	return config_value if config_value is Dictionary else {}


func _expire_archer_strength_after_delay(peer_id: int, token: int, duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	if not match_is_active or not multiplayer.is_server():
		return
	if int(archer_strength_token_by_peer.get(peer_id, -1)) != token:
		return
	_set_archer_strengthened(peer_id, false)


func _set_archer_strengthened(peer_id: int, enabled: bool) -> void:
	if LanSession.get_selected_character(peer_id) != LanSession.ARCHER_CHARACTER_ID:
		return

	archer_strengthened_by_peer[peer_id] = enabled
	set_archer_strengthened_visual.rpc(peer_id, enabled)


@rpc("authority", "call_local", "reliable")
func set_archer_strengthened_visual(peer_id: int, enabled: bool) -> void:
	var player := _get_network_player(peer_id)
	if player != null:
		player.call(&"set_network_strengthened", enabled)


func _is_archer_dashing(peer_id: int) -> bool:
	return Time.get_ticks_msec() / 1000.0 < float(archer_dash_end_time_by_peer.get(peer_id, 0.0))


# Host-only network arrow management.
func _spawn_archer_arrow_on_server(peer_id: int, damage: int, arrow_scale: float) -> void:
	if not match_is_active or not multiplayer.is_server() or damage <= 0:
		return

	var player := _get_network_player(peer_id)
	if player == null:
		return

	var facing_direction := int(player.get(&"facing_direction"))
	if facing_direction == 0:
		facing_direction = 1
	var spawn_offset := Vector2(26.0, -4.0)
	if player.has_method(&"get_network_arrow_spawn_offset"):
		var offset_value: Variant = player.call(&"get_network_arrow_spawn_offset")
		if offset_value is Vector2:
			spawn_offset = offset_value

	next_archer_arrow_id += 1
	var arrow_id := next_archer_arrow_id
	var direction := Vector2(facing_direction, 0.0)
	var player_position: Vector2 = player.get(&"global_position")
	var spawn_position: Vector2 = player_position + Vector2(spawn_offset.x * facing_direction, spawn_offset.y)
	active_archer_arrow_damage_by_id[arrow_id] = damage
	spawn_network_archer_arrow.rpc(arrow_id, spawn_position, direction, arrow_scale)


@rpc("authority", "call_local", "reliable")
func spawn_network_archer_arrow(
	arrow_id: int,
	spawn_position: Vector2,
	direction: Vector2,
	arrow_scale: float
) -> void:
	if projectiles == null or network_archer_arrow_scene == null:
		return

	var arrow_path := NodePath("archer_arrow_%d" % arrow_id)
	if projectiles.get_node_or_null(arrow_path) != null:
		return

	var arrow := network_archer_arrow_scene.instantiate() as Area2D
	if arrow == null:
		push_error("Network Archer Arrow Scene must have an Area2D root.")
		return

	arrow.name = String(arrow_path)
	projectiles.add_child(arrow, true)
	arrow.global_position = spawn_position
	arrow.call(&"launch", arrow_id, direction, arrow_scale)


func _sync_archer_arrow_snapshots() -> void:
	for arrow_id_value in active_archer_arrow_damage_by_id:
		var arrow_id := int(arrow_id_value)
		var arrow := _get_network_archer_arrow(arrow_id)
		if arrow == null:
			_despawn_archer_arrow_on_server(arrow_id)
			continue
		sync_network_archer_arrow.rpc(arrow_id, arrow.global_position, arrow.rotation)


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func sync_network_archer_arrow(arrow_id: int, network_position: Vector2, network_rotation: float) -> void:
	var arrow := _get_network_archer_arrow(arrow_id)
	if arrow != null:
		arrow.call(&"apply_network_position", network_position, network_rotation)


# Called directly only by the host arrow scene after its Area2D meets a body.
func server_resolve_archer_arrow_collision(arrow_id: int, body: Node2D) -> void:
	if not match_is_active or not multiplayer.is_server() or not active_archer_arrow_damage_by_id.has(arrow_id):
		return

	if _is_valid_lan_enemy_target(body):
		_damage_lan_enemy(body, int(active_archer_arrow_damage_by_id[arrow_id]))
	_despawn_archer_arrow_on_server(arrow_id)


func server_expire_archer_arrow(arrow_id: int) -> void:
	if not match_is_active or not multiplayer.is_server():
		return
	_despawn_archer_arrow_on_server(arrow_id)


func _despawn_archer_arrow_on_server(arrow_id: int) -> void:
	if not active_archer_arrow_damage_by_id.has(arrow_id):
		return
	active_archer_arrow_damage_by_id.erase(arrow_id)
	despawn_network_archer_arrow.rpc(arrow_id)


@rpc("authority", "call_local", "reliable")
func despawn_network_archer_arrow(arrow_id: int) -> void:
	var arrow := _get_network_archer_arrow(arrow_id)
	if arrow != null:
		arrow.queue_free()


func _get_network_archer_arrow(arrow_id: int) -> Area2D:
	if projectiles == null:
		return null
	return projectiles.get_node_or_null(NodePath("archer_arrow_%d" % arrow_id)) as Area2D


# Host-only Skeleton Archer arrow management. These arrows are not player
# controlled: their target, damage, collision, and lifetime all stay server-side.
func spawn_network_skeleton_arrow_on_server(
	spawn_position: Vector2,
	flight_direction: Vector2,
	damage: int,
	range_limit: float
) -> void:
	if not match_is_active or not multiplayer.is_server() or damage <= 0:
		return
	if flight_direction.is_zero_approx():
		return

	next_skeleton_arrow_id += 1
	var arrow_id: int = next_skeleton_arrow_id
	active_skeleton_arrow_damage_by_id[arrow_id] = damage
	spawn_network_skeleton_arrow.rpc(
		arrow_id,
		spawn_position + flight_direction.normalized() * 14.0,
		flight_direction,
		range_limit
	)


@rpc("authority", "call_local", "reliable")
func spawn_network_skeleton_arrow(
	arrow_id: int,
	spawn_position: Vector2,
	flight_direction: Vector2,
	range_limit: float
) -> void:
	if projectiles == null or NETWORK_SKELETON_ARROW_SCENE == null:
		return

	var arrow_path: NodePath = NodePath("skeleton_arrow_%d" % arrow_id)
	if projectiles.get_node_or_null(arrow_path) != null:
		return

	var arrow: Area2D = NETWORK_SKELETON_ARROW_SCENE.instantiate() as Area2D
	if arrow == null:
		push_error("Network Skeleton Arrow Scene must have an Area2D root.")
		return

	arrow.name = String(arrow_path)
	projectiles.add_child(arrow, true)
	arrow.global_position = spawn_position
	arrow.call(&"launch", arrow_id, flight_direction, range_limit)


func _sync_skeleton_arrow_snapshots() -> void:
	for arrow_id_value: Variant in active_skeleton_arrow_damage_by_id:
		var arrow_id: int = int(arrow_id_value)
		var arrow: Area2D = _get_network_skeleton_arrow(arrow_id)
		if arrow == null:
			_despawn_skeleton_arrow_on_server(arrow_id)
			continue
		sync_network_skeleton_arrow.rpc(arrow_id, arrow.global_position, arrow.rotation)


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func sync_network_skeleton_arrow(arrow_id: int, network_position: Vector2, network_rotation: float) -> void:
	var arrow: Area2D = _get_network_skeleton_arrow(arrow_id)
	if arrow != null:
		arrow.call(&"apply_network_position", network_position, network_rotation)


func server_resolve_skeleton_arrow_collision(arrow_id: int, body: Node2D) -> void:
	if not match_is_active or not multiplayer.is_server() or not active_skeleton_arrow_damage_by_id.has(arrow_id):
		return

	var player: CharacterBody2D = body as CharacterBody2D
	if player != null and players != null and player.get_parent() == players:
		var peer_id: int = player.get_multiplayer_authority()
		if get_alive_player(peer_id) == player:
			damage_player_on_server(peer_id, int(active_skeleton_arrow_damage_by_id[arrow_id]))
	_despawn_skeleton_arrow_on_server(arrow_id)


func server_expire_skeleton_arrow(arrow_id: int) -> void:
	if match_is_active and multiplayer.is_server():
		_despawn_skeleton_arrow_on_server(arrow_id)


func _despawn_skeleton_arrow_on_server(arrow_id: int) -> void:
	if not active_skeleton_arrow_damage_by_id.has(arrow_id):
		return
	active_skeleton_arrow_damage_by_id.erase(arrow_id)
	despawn_network_skeleton_arrow.rpc(arrow_id)


@rpc("authority", "call_local", "reliable")
func despawn_network_skeleton_arrow(arrow_id: int) -> void:
	var arrow: Area2D = _get_network_skeleton_arrow(arrow_id)
	if arrow != null:
		arrow.queue_free()


func _get_network_skeleton_arrow(arrow_id: int) -> Area2D:
	if projectiles == null:
		return null
	return projectiles.get_node_or_null(NodePath("skeleton_arrow_%d" % arrow_id)) as Area2D


# Host-only Mage fireball management. The projectile scene exists on every
# peer, but the host alone moves it, accepts collisions, and applies burn.
func _spawn_mage_fireball_on_server(peer_id: int, player: Node, config: Dictionary) -> void:
	if not match_is_active or not multiplayer.is_server() or player == null:
		return

	var facing_direction := int(player.get(&"facing_direction"))
	if facing_direction == 0:
		facing_direction = 1

	var spawn_offset := Vector2(26.0, -4.0)
	var offset_value: Variant = config.get("spawn_offset", spawn_offset)
	if offset_value is Vector2:
		spawn_offset = offset_value

	next_mage_fireball_id += 1
	var fireball_id := next_mage_fireball_id
	var player_position: Vector2 = player.get(&"global_position")
	var spawn_position: Vector2 = player_position + Vector2(spawn_offset.x * facing_direction, spawn_offset.y)
	var direction := Vector2(facing_direction, 0.0)
	active_mage_fireball_config_by_id[fireball_id] = {
		"damage": int(config.get("damage", 0)),
		"burn_duration": float(config.get("burn_duration", 0.0)),
		"burn_damage": int(config.get("burn_damage", 0)),
		"burn_interval": float(config.get("burn_interval", 0.0)),
	}
	spawn_network_mage_fireball.rpc(fireball_id, spawn_position, direction)


@rpc("authority", "call_local", "reliable")
func spawn_network_mage_fireball(
	fireball_id: int,
	spawn_position: Vector2,
	direction: Vector2
) -> void:
	if projectiles == null or network_mage_fireball_scene == null:
		return

	var fireball_path := NodePath("mage_fireball_%d" % fireball_id)
	if projectiles.get_node_or_null(fireball_path) != null:
		return

	var fireball := network_mage_fireball_scene.instantiate() as Area2D
	if fireball == null:
		push_error("Network Mage Fireball Scene must have an Area2D root.")
		return

	fireball.name = String(fireball_path)
	projectiles.add_child(fireball, true)
	fireball.global_position = spawn_position
	fireball.call(&"launch", fireball_id, direction)


func _sync_mage_fireball_snapshots() -> void:
	for fireball_id_value in active_mage_fireball_config_by_id:
		var fireball_id := int(fireball_id_value)
		var fireball := _get_network_mage_fireball(fireball_id)
		if fireball == null:
			_despawn_mage_fireball_on_server(fireball_id)
			continue
		sync_network_mage_fireball.rpc(fireball_id, fireball.global_position, fireball.rotation)


@rpc("authority", "call_remote", "unreliable_ordered", 4)
func sync_network_mage_fireball(
	fireball_id: int,
	network_position: Vector2,
	network_rotation: float
) -> void:
	var fireball := _get_network_mage_fireball(fireball_id)
	if fireball != null:
		fireball.call(&"apply_network_position", network_position, network_rotation)


# Called directly by the host-owned fireball Area2D. A real slime impact gets
# the one-shot impact animation; walls and the maximum distance simply remove
# the projectile without pretending it damaged an enemy.
func server_resolve_mage_fireball_collision(fireball_id: int, body: Node2D) -> void:
	if not match_is_active or not multiplayer.is_server() or not active_mage_fireball_config_by_id.has(fireball_id):
		return

	if _is_valid_lan_enemy_target(body):
		var hit_config: Variant = active_mage_fireball_config_by_id.get(fireball_id, {})
		if hit_config is Dictionary:
			_damage_lan_enemy(body, int(hit_config.get("damage", 0)))
			_apply_lan_enemy_burn(
				body,
				float(hit_config.get("burn_duration", 0.0)),
				int(hit_config.get("burn_damage", 0)),
				float(hit_config.get("burn_interval", 0.0))
			)
		_begin_mage_fireball_impact(fireball_id)
		return

	_despawn_mage_fireball_on_server(fireball_id)


func server_expire_mage_fireball(fireball_id: int) -> void:
	if not match_is_active or not multiplayer.is_server():
		return
	_despawn_mage_fireball_on_server(fireball_id)


func _begin_mage_fireball_impact(fireball_id: int) -> void:
	if not active_mage_fireball_config_by_id.has(fireball_id):
		return

	var token := int(mage_fireball_impact_token_by_id.get(fireball_id, 0)) + 1
	mage_fireball_impact_token_by_id[fireball_id] = token
	begin_network_mage_fireball_impact.rpc(fireball_id)
	_despawn_mage_fireball_after_impact(fireball_id, token)


@rpc("authority", "call_local", "reliable")
func begin_network_mage_fireball_impact(fireball_id: int) -> void:
	var fireball := _get_network_mage_fireball(fireball_id)
	if fireball != null:
		fireball.call(&"begin_network_impact")


func _despawn_mage_fireball_after_impact(fireball_id: int, token: int) -> void:
	await get_tree().create_timer(0.6).timeout
	if not match_is_active or not multiplayer.is_server():
		return
	if int(mage_fireball_impact_token_by_id.get(fireball_id, -1)) != token:
		return
	_despawn_mage_fireball_on_server(fireball_id)


func _despawn_mage_fireball_on_server(fireball_id: int) -> void:
	if not active_mage_fireball_config_by_id.has(fireball_id):
		return
	active_mage_fireball_config_by_id.erase(fireball_id)
	mage_fireball_impact_token_by_id.erase(fireball_id)
	despawn_network_mage_fireball.rpc(fireball_id)


@rpc("authority", "call_local", "reliable")
func despawn_network_mage_fireball(fireball_id: int) -> void:
	var fireball := _get_network_mage_fireball(fireball_id)
	if fireball != null:
		fireball.queue_free()


func _get_network_mage_fireball(fireball_id: int) -> Area2D:
	if projectiles == null:
		return null
	return projectiles.get_node_or_null(NodePath("mage_fireball_%d" % fireball_id)) as Area2D


# Q's freeze art is visual only. The host has already chosen the target and
# applied the real debuff before the scene is spawned on either computer.
@rpc("authority", "call_local", "reliable")
func spawn_network_mage_freeze_effect(spawn_position: Vector2) -> void:
	if projectiles == null or network_mage_freeze_effect_scene == null:
		return

	var effect := network_mage_freeze_effect_scene.instantiate() as Area2D
	if effect == null:
		push_error("Network Mage Freeze Effect Scene must have an Area2D root.")
		return

	projectiles.add_child(effect, true)
	effect.global_position = spawn_position
	effect.call(&"play_effect")


# Priest's effect scenes are visual-only. The reliable spawn occurs only after
# the host has already confirmed the target hit or the restored health value.
@rpc("authority", "call_local", "reliable")
func spawn_network_priest_auraplosion_effect(spawn_position: Vector2) -> void:
	if projectiles == null or network_priest_auraplosion_effect_scene == null:
		return

	var effect := network_priest_auraplosion_effect_scene.instantiate() as Area2D
	if effect == null:
		push_error("Network Priest Auraplosion Effect Scene must have an Area2D root.")
		return

	projectiles.add_child(effect, true)
	effect.global_position = spawn_position
	effect.call(&"play_effect")


@rpc("authority", "call_local", "reliable")
func spawn_network_priest_heal_effect(spawn_position: Vector2) -> void:
	if projectiles == null or network_priest_heal_effect_scene == null:
		return

	var effect := network_priest_heal_effect_scene.instantiate() as Area2D
	if effect == null:
		push_error("Network Priest Heal Effect Scene must have an Area2D root.")
		return

	projectiles.add_child(effect, true)
	effect.global_position = spawn_position
	effect.call(&"play_effect")


func damage_player_on_server(peer_id: int, damage: int) -> void:
	if not match_is_active or not multiplayer.is_server() or damage <= 0:
		return
	if bool(player_dead_by_peer.get(peer_id, false)) or _get_network_player(peer_id) == null:
		return

	var now := Time.get_ticks_msec() / 1000.0
	# Knight E consumes one real server-side hit before health changes. It also
	# starts the normal short protection window so overlapping enemy checks from
	# this same moment cannot immediately drain health after the shield is used.
	if _consume_knight_block(peer_id):
		next_player_damage_time_by_peer[peer_id] = now + PLAYER_DAMAGE_INVULNERABILITY
		return

	# The blue Priest shield is checked before the normal short post-hit
	# protection, so a blocked hit does not consume either protection timer.
	if (
		LanSession.get_selected_character(peer_id) == LanSession.PRIEST_CHARACTER_ID
		and bool(priest_invulnerable_by_peer.get(peer_id, false))
	):
		return

	if now < float(next_player_damage_time_by_peer.get(peer_id, 0.0)):
		return

	var maximum_health := _get_player_max_health(peer_id)
	var current_health := int(player_health_by_peer.get(peer_id, maximum_health))
	if current_health <= 0:
		return

	next_player_damage_time_by_peer[peer_id] = now + PLAYER_DAMAGE_INVULNERABILITY
	var new_health := maxi(0, current_health - damage)
	var new_revision := int(player_state_revision_by_peer.get(peer_id, 0)) + 1
	var defeated := new_health == 0

	player_health_by_peer[peer_id] = new_health
	player_state_revision_by_peer[peer_id] = new_revision
	player_dead_by_peer[peer_id] = defeated

	# Priest casts are interruptible by an actual damaging hit, just like the
	# normal Priest. Removing the active sequence also cancels the delayed heal
	# or spell release that the host scheduled for that cast.
	if not defeated and LanSession.get_selected_character(peer_id) == LanSession.PRIEST_CHARACTER_ID:
		var interrupted_sequence := int(active_attack_sequence_by_peer.get(peer_id, -1))
		if interrupted_sequence >= 0:
			active_attack_sequence_by_peer.erase(peer_id)
			finish_priest_action_visual.rpc(peer_id, interrupted_sequence)

	if defeated:
		active_attack_sequence_by_peer.erase(peer_id)
		_clear_host_movement_input(peer_id)
		_clear_knight_special_state(peer_id)
		_clear_archer_special_state(peer_id)
		_clear_priest_special_state(peer_id)

	# Send every health change, not just defeat, so both health bars and hurt
	# flashes stay accurate for Knights, Archers, Mages, and Priests alike.
	apply_player_state.rpc(peer_id, new_health, maximum_health, new_revision, defeated, Vector2.ZERO, false)

	if defeated:
		var token := int(respawn_token_by_peer.get(peer_id, 0)) + 1
		respawn_token_by_peer[peer_id] = token
		_respawn_player_after_delay(peer_id, token)


# Host-only health restoration used by Priest's Q. The same player-life
# dictionary and reliable state RPC keep both health bars in agreement.
# Returning true lets Q show its visual only when health really changed.
func heal_player_on_server(peer_id: int, amount: int) -> bool:
	if not match_is_active or not multiplayer.is_server() or amount <= 0:
		return false
	if bool(player_dead_by_peer.get(peer_id, false)) or _get_network_player(peer_id) == null:
		return false

	var maximum_health: int = _get_player_max_health(peer_id)
	var current_health: int = int(player_health_by_peer.get(peer_id, maximum_health))
	var new_health: int = mini(maximum_health, current_health + amount)
	if new_health <= current_health:
		return false

	var new_revision: int = int(player_state_revision_by_peer.get(peer_id, 0)) + 1
	player_health_by_peer[peer_id] = new_health
	player_state_revision_by_peer[peer_id] = new_revision
	apply_player_state.rpc(peer_id, new_health, maximum_health, new_revision, false, Vector2.ZERO, false)
	return true


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

	player_stunned_until_by_peer.erase(peer_id)
	var maximum_health := _get_player_max_health(peer_id)
	player_health_by_peer[peer_id] = maximum_health
	player_dead_by_peer[peer_id] = false
	player_state_revision_by_peer[peer_id] = 0
	apply_player_state.rpc(peer_id, maximum_health, maximum_health, 0, false, Vector2.ZERO, false)


func _get_player_max_health(peer_id: int) -> int:
	var player := _get_network_player(peer_id)
	if player != null and player.has_method(&"get_network_max_health"):
		return maxi(1, int(player.call(&"get_network_max_health")))
	return DEFAULT_PLAYER_MAX_HEALTH


func _initialize_player_movement(peer_id: int) -> void:
	movement_input_by_peer[peer_id] = Vector2.ZERO
	last_movement_input_time_by_peer[peer_id] = 0.0
	last_movement_input_sequence_by_peer[peer_id] = -1
	next_movement_state_sequence_by_peer[peer_id] = 0


func _respawn_player_after_delay(peer_id: int, token: int) -> void:
	await get_tree().create_timer(PLAYER_RESPAWN_DELAY).timeout
	if not match_is_active or not multiplayer.is_server():
		return
	if int(respawn_token_by_peer.get(peer_id, -1)) != token:
		return
	if not bool(player_dead_by_peer.get(peer_id, false)) or _get_network_player(peer_id) == null:
		return

	var maximum_health := _get_player_max_health(peer_id)
	var new_revision := int(player_state_revision_by_peer.get(peer_id, 0)) + 1
	player_health_by_peer[peer_id] = maximum_health
	player_dead_by_peer[peer_id] = false
	player_state_revision_by_peer[peer_id] = new_revision
	next_player_damage_time_by_peer.erase(peer_id)
	next_damage_zone_tick_by_peer.erase(peer_id)
	player_stunned_until_by_peer.erase(peer_id)
	_clear_host_movement_input(peer_id)
	_clear_knight_special_state(peer_id)
	_clear_archer_special_state(peer_id)
	_clear_priest_special_state(peer_id)

	apply_player_state.rpc(
		peer_id,
		maximum_health,
		maximum_health,
		new_revision,
		false,
		_get_spawn_position(peer_id),
		true
	)


func _clear_archer_special_state(peer_id: int) -> void:
	archer_dash_end_time_by_peer.erase(peer_id)
	archer_dash_direction_by_peer.erase(peer_id)
	archer_dash_speed_by_peer.erase(peer_id)
	archer_strength_token_by_peer[peer_id] = int(archer_strength_token_by_peer.get(peer_id, 0)) + 1
	if bool(archer_strengthened_by_peer.get(peer_id, false)):
		_set_archer_strengthened(peer_id, false)
	else:
		archer_strengthened_by_peer.erase(peer_id)


func _clear_knight_special_state(peer_id: int) -> void:
	# Incrementing the token cancels a pending block-expiry timer after death or
	# respawn. Cooldowns intentionally remain in their own dictionary.
	knight_block_token_by_peer[peer_id] = int(knight_block_token_by_peer.get(peer_id, 0)) + 1
	knight_blocking_by_peer.erase(peer_id)


func _clear_priest_special_state(peer_id: int) -> void:
	next_priest_invulnerability_time_by_peer.erase(peer_id)
	priest_invulnerability_token_by_peer[peer_id] = int(priest_invulnerability_token_by_peer.get(peer_id, 0)) + 1
	if bool(priest_invulnerable_by_peer.get(peer_id, false)):
		_set_priest_invulnerable(peer_id, false)
	else:
		priest_invulnerable_by_peer.erase(peer_id)


func _get_spawn_position(peer_id: int) -> Vector2:
	# The standalone LAN arena uses the same sorted roster order as lan_world,
	# so all four players get a separate fallback position during testing.
	var peer_ids: PackedInt32Array = LanSession.get_connected_peer_ids()
	var spawn_index: int = peer_ids.find(peer_id)
	match spawn_index:
		0:
			return Vector2(460, 450)
		1:
			return Vector2(600, 450)
		2:
			return Vector2(460, 550)
		3:
			return Vector2(600, 550)
		_:
			return Vector2(460, 450)


# Every move_and_slide call runs on the host. Dash uses a host timer and
# direction, so even that fast movement still respects shared wall collision.
func _simulate_host_player_movement() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for child in players.get_children():
		var player := child as CharacterBody2D
		if player == null:
			continue

		var peer_id := player.get_multiplayer_authority()
		var direction := Vector2.ZERO
		var last_input_time := float(last_movement_input_time_by_peer.get(peer_id, 0.0))
		if not _is_player_stunned(peer_id) and not bool(player_dead_by_peer.get(peer_id, false)) and now - last_input_time <= MOVEMENT_INPUT_TIMEOUT:
			direction = movement_input_by_peer.get(peer_id, Vector2.ZERO)

		var is_archer := LanSession.get_selected_character(peer_id) == LanSession.ARCHER_CHARACTER_ID
		if is_archer:
			var dash_end_time := float(archer_dash_end_time_by_peer.get(peer_id, 0.0))
			if dash_end_time > now:
				direction = archer_dash_direction_by_peer.get(peer_id, Vector2.ZERO)
				var dash_speed := float(archer_dash_speed_by_peer.get(peer_id, 0.0))
				player.call(&"simulate_host_movement", direction, dash_speed)
			elif dash_end_time > 0.0:
				archer_dash_end_time_by_peer.erase(peer_id)
				archer_dash_direction_by_peer.erase(peer_id)
				archer_dash_speed_by_peer.erase(peer_id)
				finish_archer_dash_visual.rpc(peer_id)
				player.call(&"simulate_host_movement", direction, -1.0)
			else:
				player.call(&"simulate_host_movement", direction, -1.0)
		else:
			player.call(&"simulate_host_movement", direction)

		var state_sequence := int(next_movement_state_sequence_by_peer.get(peer_id, 0)) + 1
		next_movement_state_sequence_by_peer[peer_id] = state_sequence

		var facing := int(player.get(&"facing_direction"))
		if facing == 0:
			facing = 1

		sync_player_motion.rpc(
			peer_id,
			player.global_position,
			facing,
			bool(player.call(&"is_host_walking")),
			state_sequence,
			int(player_state_revision_by_peer.get(peer_id, 0))
		)


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


func _clear_host_movement_input(peer_id: int) -> void:
	movement_input_by_peer[peer_id] = Vector2.ZERO
	last_movement_input_time_by_peer[peer_id] = Time.get_ticks_msec() / 1000.0


# The host slime calls these generic helpers through the stable group name.
func get_nearest_alive_player(from_position: Vector2) -> CharacterBody2D:
	if not match_is_active or not multiplayer.is_server() or players == null:
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


func get_alive_player(peer_id: int) -> CharacterBody2D:
	if not match_is_active or not multiplayer.is_server() or bool(player_dead_by_peer.get(peer_id, false)):
		return null
	return _get_network_player(peer_id) as CharacterBody2D


# Circular enemy attacks use this host-only helper so a spin, slam, or
# Deathplosion damages every nearby LAN player, not just the chased target.
func get_alive_players_in_radius(center: Vector2, radius: float) -> Array[CharacterBody2D]:
	var targets: Array[CharacterBody2D] = []
	if not match_is_active or not multiplayer.is_server() or players == null or radius <= 0.0:
		return targets

	var radius_squared: float = radius * radius
	for child: Node in players.get_children():
		var candidate: CharacterBody2D = child as CharacterBody2D
		if candidate == null:
			continue
		var peer_id: int = candidate.get_multiplayer_authority()
		if bool(player_dead_by_peer.get(peer_id, false)):
			continue
		if center.distance_squared_to(candidate.global_position) <= radius_squared:
			targets.append(candidate)
	return targets


# Stun is host-owned just like health. It stops host simulation immediately and
# rejects new movement/attack requests until its timer reaches zero.
func stun_player_on_server(peer_id: int, duration: float) -> void:
	if not match_is_active or not multiplayer.is_server() or duration <= 0.0:
		return
	if bool(player_dead_by_peer.get(peer_id, false)) or _get_network_player(peer_id) == null:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	player_stunned_until_by_peer[peer_id] = maxf(
		float(player_stunned_until_by_peer.get(peer_id, 0.0)),
		now + duration
	)
	_clear_host_movement_input(peer_id)
	# Any queued attack hit checks its sequence before dealing damage. Removing
	# this record makes a stun stop an unfinished player action immediately.
	active_attack_sequence_by_peer.erase(peer_id)


func _is_player_stunned(peer_id: int) -> bool:
	return Time.get_ticks_msec() / 1000.0 < float(player_stunned_until_by_peer.get(peer_id, 0.0))


func _get_network_player(peer_id: int) -> Node:
	if players == null:
		return null
	return players.get_node_or_null(NodePath(str(peer_id)))


# Used by the graveyard spawner and Necromancer. The host creates a predictable
# ID, then a reliable RPC creates the same LAN-only enemy path on every peer.
func spawn_lan_enemy_on_server(profile: StringName, spawn_position: Vector2) -> Node2D:
	if not match_is_active or not multiplayer.is_server() or dynamic_enemies == null:
		return null
	if not LAN_ENEMY_SCENES.has(profile):
		push_error("No LAN scene is registered for enemy profile: %s" % profile)
		return null

	next_dynamic_enemy_id += 1
	var enemy_id: int = next_dynamic_enemy_id
	spawn_dynamic_lan_enemy.rpc(enemy_id, String(profile), spawn_position)
	return dynamic_enemies.get_node_or_null(NodePath("enemy_%d" % enemy_id)) as Node2D


# A Necromancer wave gets the existing summon.tscn visual at every skeleton
# spawn point. It is visual-only; the host still creates and controls the
# actual summoned enemy immediately after this effect starts.
func spawn_lan_summon_effect_on_server(spawn_position: Vector2) -> void:
	if not match_is_active or not multiplayer.is_server() or projectiles == null:
		return

	next_lan_summon_effect_id += 1
	spawn_lan_summon_effect.rpc(next_lan_summon_effect_id, spawn_position)


@rpc("authority", "call_local", "reliable")
func spawn_lan_summon_effect(effect_id: int, spawn_position: Vector2) -> void:
	if projectiles == null or LAN_SUMMON_EFFECT_SCENE == null:
		return

	var effect_name: StringName = StringName("lan_summon_effect_%d" % effect_id)
	if projectiles.get_node_or_null(NodePath(effect_name)) != null:
		return

	var effect: Area2D = LAN_SUMMON_EFFECT_SCENE.instantiate() as Area2D
	if effect == null:
		push_error("summon.tscn must have an Area2D root.")
		return

	effect.name = effect_name
	projectiles.add_child(effect, true)
	effect.global_position = spawn_position
	if effect.has_method(&"activate"):
		effect.call(&"activate")


@rpc("authority", "call_local", "reliable")
func spawn_dynamic_lan_enemy(enemy_id: int, profile: String, spawn_position: Vector2) -> void:
	if dynamic_enemies == null:
		return

	var enemy_name: StringName = StringName("enemy_%d" % enemy_id)
	if dynamic_enemies.get_node_or_null(NodePath(enemy_name)) != null:
		return

	var profile_name: StringName = StringName(profile)
	var scene_value: Variant = LAN_ENEMY_SCENES.get(profile_name, null)
	var enemy_scene: PackedScene = scene_value as PackedScene
	if enemy_scene == null:
		push_error("Could not load LAN enemy profile: %s" % profile)
		return

	var enemy: CharacterBody2D = enemy_scene.instantiate() as CharacterBody2D
	if enemy == null:
		push_error("LAN enemy scenes must have CharacterBody2D roots.")
		return

	# Replacing the script before add_child prevents the normal local AI from
	# ever entering the tree or running on a joining computer.
	enemy.set_script(NETWORK_ENEMY_SCRIPT)
	enemy.name = enemy_name
	enemy.set(&"enemy_profile", profile_name)
	dynamic_enemies.add_child(enemy, true)
	enemy.global_position = spawn_position
	if enemy.has_method(&"play_server_spawn_summon"):
		enemy.call(&"play_server_spawn_summon")


# World and dungeon subclasses override this for their gate/boss completion.
func on_lan_enemy_defeated(_profile: StringName) -> void:
	pass


func _reset_lan_enemies() -> void:
	if dynamic_enemies != null:
		for enemy: Node in dynamic_enemies.get_children():
			enemy.queue_free()
		next_dynamic_enemy_id = 0
	for enemy: Node2D in _get_lan_enemies():
		if enemy.has_method(&"reset_for_network_session"):
			enemy.call(&"reset_for_network_session")


# Every LAN enemy is pre-placed at the same node path on both computers. The
# group lets the host expand beyond one slime without accepting target choices
# from a client or touching normal single-player enemy nodes.
func _get_lan_enemies() -> Array[Node2D]:
	var enemies: Array[Node2D] = []
	var group_members: Array[Node] = get_tree().get_nodes_in_group(&"lan_enemy")

	for member: Node in group_members:
		if not is_instance_valid(member) or member.is_queued_for_deletion():
			continue

		var enemy: Node2D = member as Node2D
		if enemy != null and enemy.is_inside_tree():
			enemies.append(enemy)

	return enemies


# This is the shared combat contract for the LAN enemy roster. It avoids the
# previously freed-target error by validating the instance before casting it,
# reading its state, or applying host-approved damage.
func _is_valid_lan_enemy_target(candidate: Node) -> bool:
	if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return false
	if not candidate.is_in_group(&"lan_enemy"):
		return false

	var enemy: Node2D = candidate as Node2D
	if enemy == null or not enemy.is_inside_tree():
		return false
	if not enemy.has_method(&"is_lan_enemy_alive") or not enemy.has_method(&"take_server_hit"):
		return false

	var alive_value: Variant = enemy.call(&"is_lan_enemy_alive")
	return alive_value is bool and bool(alive_value)


func _get_nearest_alive_lan_enemy(origin: Vector2, maximum_range: float) -> Node2D:
	if maximum_range <= 0.0:
		return null

	var nearest_enemy: Node2D = null
	var nearest_distance_squared: float = maximum_range * maximum_range
	for enemy: Node2D in _get_lan_enemies():
		if not _is_valid_lan_enemy_target(enemy):
			continue

		var distance_squared: float = origin.distance_squared_to(enemy.global_position)
		if distance_squared <= nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_enemy = enemy

	return nearest_enemy


func _get_alive_lan_enemies_in_radius(center: Vector2, radius: float) -> Array[Node2D]:
	var enemies_in_radius: Array[Node2D] = []
	if radius <= 0.0:
		return enemies_in_radius

	var radius_squared: float = radius * radius
	for enemy: Node2D in _get_lan_enemies():
		if not _is_valid_lan_enemy_target(enemy):
			continue
		if center.distance_squared_to(enemy.global_position) <= radius_squared:
			enemies_in_radius.append(enemy)

	return enemies_in_radius


func _get_nearest_lan_enemy_for_player(player: Node, target_range: float) -> Node2D:
	var player_body: Node2D = player as Node2D
	if player_body == null:
		return null
	return _get_nearest_alive_lan_enemy(player_body.global_position, target_range)


func _damage_lan_enemy(enemy: Node2D, damage: int) -> void:
	if damage <= 0 or not _is_valid_lan_enemy_target(enemy):
		return
	enemy.call(&"take_server_hit", damage)


func _apply_lan_enemy_freeze(enemy: Node2D, duration: float) -> void:
	if duration <= 0.0 or not _is_valid_lan_enemy_target(enemy):
		return
	if enemy.has_method(&"apply_server_freeze"):
		enemy.call(&"apply_server_freeze", duration)


func _apply_lan_enemy_burn(
	enemy: Node2D,
	duration: float,
	damage_per_tick: int,
	tick_interval: float
) -> void:
	if (
		duration <= 0.0
		or damage_per_tick <= 0
		or tick_interval <= 0.0
		or not _is_valid_lan_enemy_target(enemy)
	):
		return
	if enemy.has_method(&"apply_server_burn"):
		enemy.call(&"apply_server_burn", duration, damage_per_tick, tick_interval)


func _reset_match_records() -> void:
	for player in players.get_children():
		player.queue_free()
	if projectiles != null:
		for projectile in projectiles.get_children():
			projectile.queue_free()

	next_knight_action_time_by_key.clear()
	knight_blocking_by_peer.clear()
	knight_block_token_by_peer.clear()
	next_attack_sequence_by_peer.clear()
	active_attack_sequence_by_peer.clear()
	movement_input_by_peer.clear()
	last_movement_input_time_by_peer.clear()
	last_movement_input_sequence_by_peer.clear()
	next_movement_state_sequence_by_peer.clear()
	player_health_by_peer.clear()
	player_dead_by_peer.clear()
	player_state_revision_by_peer.clear()
	next_player_damage_time_by_peer.clear()
	next_damage_zone_tick_by_peer.clear()
	respawn_token_by_peer.clear()
	player_stunned_until_by_peer.clear()
	next_archer_attack_time_by_peer.clear()
	next_archer_dash_time_by_peer.clear()
	archer_dash_end_time_by_peer.clear()
	archer_dash_direction_by_peer.clear()
	archer_dash_speed_by_peer.clear()
	next_archer_strength_time_by_peer.clear()
	archer_strengthened_by_peer.clear()
	archer_strength_token_by_peer.clear()
	active_archer_arrow_damage_by_id.clear()
	next_archer_arrow_id = 0
	active_skeleton_arrow_damage_by_id.clear()
	next_skeleton_arrow_id = 0
	next_mage_action_time_by_key.clear()
	active_mage_fireball_config_by_id.clear()
	mage_fireball_impact_token_by_id.clear()
	next_mage_fireball_id = 0
	next_priest_action_time_by_key.clear()
	priest_invulnerable_by_peer.clear()
	next_priest_invulnerability_time_by_peer.clear()
	priest_invulnerability_token_by_peer.clear()
	next_lan_summon_effect_id = 0


func _on_leave_pressed() -> void:
	match_is_active = false
	LanSession.leave_session("Left the LAN match.")
	var error := get_tree().change_scene_to_file(LanSession.LOBBY_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the LAN lobby. Error code: %d" % error)


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message

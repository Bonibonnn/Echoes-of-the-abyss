extends CharacterBody2D

# LAN-only Archer controller. Like network_knight_player.gd, it sends only
# input intentions to the host. The host owns movement, arrows, damage, and
# every cooldown, so a player cannot create a local-only arrow or damage.

@export_category("LAN Archer Stats")
@export var movement_speed := 135.0
@export var network_max_health := 4

@export_category("Attack 1 - Basic Arrow")
@export var basic_attack_damage := 1
@export var basic_attack_cooldown := 0.45
@export var basic_attack_duration := 1.8
@export var basic_arrow_release_time := 1.2

@export_category("Attack 2 - Heavy Arrow")
@export var heavy_attack_damage := 3
@export var heavy_attack_cooldown := 1.1
@export var heavy_attack_duration := 2.4
@export var heavy_arrow_release_time := 1.92
@export var heavy_arrow_scale := 1.35

@export_category("Skill 1 - Dash")
@export var dash_speed := 420.0
@export var dash_duration := 0.18
@export var dash_cooldown := 1.5

@export_category("Skill 2 - Strengthen")
@export var strength_bonus_damage := 2
@export var strength_duration := 6.0
@export var strength_cooldown := 8.0
@export var strengthened_arrow_scale := 1.2
@export var strengthened_character_tint := Color(1.0, 0.25, 0.25, 1.0)

@export_category("Projectile")
@export var arrow_spawn_offset := Vector2(26.0, -4.0)

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
@onready var camera := get_node_or_null(^"Camera2D") as Camera2D
@onready var collision_shape := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
@onready var peer_label := get_node_or_null(^"peer_label") as Label
@onready var health_label := get_node_or_null(^"health_label") as Label
@onready var health_bar := get_node_or_null(^"health_bar") as ProgressBar

var facing_direction := 1
var is_network_attacking := false
var is_network_dashing := false
var is_network_strengthened := false
var active_attack_sequence := -1
var last_movement_state := false

# The local player sends directions and button choices, never a transform.
var local_input_sequence := 0
var local_facing_intent := 1
var last_server_motion_sequence := -1

# The host sends the real life state. Clients use it only for display and for
# tagging their next input packet with the correct revision.
var health := 4
var max_health := 4
var health_revision := 0
var is_network_defeated := false
var hurt_flash_time_left := 0.0
var player_title := "Archer"


func _ready() -> void:
	_refresh_player_title()

	# Only the locally controlled character owns this computer's camera.
	if camera != null:
		camera.enabled = is_multiplayer_authority()

	if peer_label != null:
		var peer_color := Color(0.4, 0.82, 1.0, 1.0) if get_multiplayer_authority() == 1 else Color(1.0, 0.62, 0.45, 1.0)
		peer_label.add_theme_color_override(&"font_color", peer_color)

	local_facing_intent = facing_direction
	_refresh_life_ui()
	_update_visuals(false)


# Called from the reliable host-owned spawn RPC before this node enters the
# tree. It makes the roster class visible above the character.
func set_selected_character(approved_character: String) -> void:
	if approved_character != "archer":
		return
	_refresh_player_title()
	if is_inside_tree():
		_refresh_life_ui()


func get_network_max_health() -> int:
	return maxi(1, network_max_health)


# The host reads these values from its Archer scene. No client-provided RPC
# chooses damage, timing, or arrow scale.
func get_network_archer_attack_config(action_id: String) -> Dictionary:
	if action_id == "attack1":
		return {
			"damage": basic_attack_damage,
			"cooldown": basic_attack_cooldown,
			"duration": basic_attack_duration,
			"release_time": basic_arrow_release_time,
			"arrow_scale": 1.0,
		}
	if action_id == "attack2":
		return {
			"damage": heavy_attack_damage,
			"cooldown": heavy_attack_cooldown,
			"duration": heavy_attack_duration,
			"release_time": heavy_arrow_release_time,
			"arrow_scale": heavy_arrow_scale,
		}
	return {}


func get_network_dash_config() -> Dictionary:
	return {
		"speed": dash_speed,
		"duration": dash_duration,
		"cooldown": dash_cooldown,
	}


func get_network_strength_config() -> Dictionary:
	return {
		"bonus_damage": strength_bonus_damage,
		"duration": strength_duration,
		"cooldown": strength_cooldown,
		"arrow_scale": strengthened_arrow_scale,
	}


func get_network_arrow_spawn_offset() -> Vector2:
	return arrow_spawn_offset


func _refresh_player_title() -> void:
	var owner_title := "Host" if get_multiplayer_authority() == 1 else "Joiner"
	player_title = "%s Archer" % owner_title


func _process(delta: float) -> void:
	if is_network_defeated:
		return

	if hurt_flash_time_left > 0.0:
		hurt_flash_time_left = maxf(0.0, hurt_flash_time_left - delta)
	_refresh_body_modulate()


func _physics_process(_delta: float) -> void:
	# Remote replicas never read the local keyboard; they only show snapshots.
	if not is_multiplayer_authority():
		return

	var direction := Vector2.ZERO
	if not is_network_defeated and not is_network_attacking and not is_network_dashing:
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if not is_zero_approx(direction.x):
			local_facing_intent = 1 if direction.x > 0.0 else -1

		# The order matches the normal Archer: Q, E, heavy arrow, basic arrow.
		if InputMap.has_action(&"skill1") and Input.is_action_just_pressed(&"skill1"):
			var dash_direction := direction
			if dash_direction.is_zero_approx():
				dash_direction = Vector2(local_facing_intent, 0.0)
			_request_archer_action_from_host("skill1", dash_direction)
			direction = Vector2.ZERO
		elif InputMap.has_action(&"skill2") and Input.is_action_just_pressed(&"skill2"):
			_request_archer_action_from_host("skill2", Vector2.ZERO)
		elif InputMap.has_action(&"attack2") and Input.is_action_just_pressed(&"attack2"):
			_request_archer_action_from_host("attack2", Vector2.ZERO)
		elif InputMap.has_action(&"attack") and Input.is_action_just_pressed(&"attack"):
			_request_archer_action_from_host("attack1", Vector2.ZERO)
			direction = Vector2.ZERO

	_submit_movement_input_to_host(direction)


# Sends a button intention. The host determines whether the action is allowed
# for this class and whether its cooldown has actually finished.
func _request_archer_action_from_host(action_id: String, requested_direction: Vector2) -> void:
	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return

	if multiplayer.is_server():
		arena.call(
			&"request_host_archer_action",
			get_multiplayer_authority(),
			action_id,
			local_facing_intent,
			requested_direction
		)
	else:
		arena.rpc_id(
			1,
			&"request_archer_action",
			action_id,
			local_facing_intent,
			requested_direction,
			health_revision
		)


func _submit_movement_input_to_host(direction: Vector2) -> void:
	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return

	local_input_sequence += 1
	if multiplayer.is_server():
		arena.call(
			&"submit_host_movement_input",
			get_multiplayer_authority(),
			direction,
			local_input_sequence,
			health_revision
		)
	else:
		arena.rpc_id(
			1,
			&"submit_movement_input",
			direction,
			local_input_sequence,
			health_revision
		)


# The host is the only copy that calls move_and_slide. Dash speed is supplied
# by the host root only while its authoritative dash timer is active.
func simulate_host_movement(direction: Vector2, speed_override: float = -1.0) -> void:
	if not multiplayer.is_server():
		return

	if is_network_defeated or is_network_attacking:
		velocity = Vector2.ZERO
		_update_visuals(false)
		return

	var safe_direction := direction.limit_length(1.0)
	if not is_zero_approx(safe_direction.x):
		facing_direction = 1 if safe_direction.x > 0.0 else -1

	var active_speed := speed_override if speed_override > 0.0 else movement_speed
	velocity = safe_direction * active_speed
	move_and_slide()
	_update_visuals(not safe_direction.is_zero_approx())


func set_host_facing(network_facing: int) -> void:
	if not multiplayer.is_server() or is_network_defeated or network_facing == 0:
		return

	facing_direction = 1 if network_facing > 0 else -1
	_update_visuals(false)


func is_host_walking() -> bool:
	return last_movement_state


func apply_network_motion_state(
	network_position: Vector2,
	network_facing: int,
	network_is_walking: bool,
	motion_sequence: int,
	motion_life_revision: int
) -> void:
	if motion_life_revision != health_revision or motion_sequence <= last_server_motion_sequence:
		return

	last_server_motion_sequence = motion_sequence
	if is_network_defeated:
		return

	global_position = network_position
	facing_direction = 1 if network_facing >= 0 else -1
	if is_multiplayer_authority():
		local_facing_intent = facing_direction
	_update_visuals(network_is_walking)


# Both peers receive the same action animation chosen by the host.
func start_network_archer_attack(sequence: int, network_facing: int, action_id: String) -> void:
	if is_network_defeated or sequence < active_attack_sequence:
		return

	active_attack_sequence = sequence
	is_network_attacking = true
	facing_direction = 1 if network_facing >= 0 else -1
	velocity = Vector2.ZERO

	if animated_sprite != null:
		animated_sprite.flip_h = facing_direction < 0
		animated_sprite.play(&"attack2" if action_id == "attack2" else &"attack1")


func finish_network_archer_attack(sequence: int) -> void:
	if is_network_defeated or sequence != active_attack_sequence:
		return

	is_network_attacking = false
	_update_visuals(last_movement_state)


# Dash deliberately reuses the walk animation because the normal Archer has no
# dash animation. The root still controls its speed and exact end time.
func start_network_archer_dash(network_direction: Vector2) -> void:
	if is_network_defeated:
		return

	is_network_dashing = true
	if not is_zero_approx(network_direction.x):
		facing_direction = 1 if network_direction.x > 0.0 else -1
	_update_visuals(true)


func finish_network_archer_dash() -> void:
	if is_network_defeated:
		return

	is_network_dashing = false
	_update_visuals(false)


# E changes only the visual here. The host remembers the actual buff and uses
# it when it releases the next basic arrow.
func set_network_strengthened(enabled: bool) -> void:
	is_network_strengthened = enabled
	_refresh_body_modulate()


func apply_network_health_state(
	new_health: int,
	new_max_health: int,
	new_revision: int,
	defeated: bool,
	move_to: Vector2,
	should_move: bool
) -> void:
	if new_revision < health_revision:
		return

	var was_defeated := is_network_defeated
	var took_damage := new_health < health

	health = clampi(new_health, 0, new_max_health)
	max_health = maxi(1, new_max_health)
	health_revision = new_revision
	is_network_defeated = defeated

	if should_move:
		global_position = move_to

	if is_network_defeated:
		is_network_attacking = false
		is_network_dashing = false
		active_attack_sequence = -1
		velocity = Vector2.ZERO
		hurt_flash_time_left = 0.0
		_set_body_collision_enabled(false)
	elif was_defeated or should_move:
		is_network_dashing = false
		hurt_flash_time_left = 0.0
		_set_body_collision_enabled(true)
		_update_visuals(false)
	elif took_damage:
		hurt_flash_time_left = 0.16

	_refresh_body_modulate()
	_refresh_life_ui()


func _set_body_collision_enabled(is_enabled: bool) -> void:
	if collision_shape != null:
		collision_shape.set_deferred(&"disabled", not is_enabled)


func _refresh_life_ui() -> void:
	if peer_label != null:
		peer_label.text = "%s — Defeated" % player_title if is_network_defeated else player_title
	if health_label != null:
		health_label.text = "Respawning..." if is_network_defeated else "HP: %d / %d" % [health, max_health]
	if health_bar != null:
		health_bar.max_value = max_health
		health_bar.value = health


func _refresh_body_modulate() -> void:
	if animated_sprite == null:
		return
	if is_network_defeated:
		animated_sprite.modulate = Color(0.4, 0.4, 0.45, 1.0)
	elif hurt_flash_time_left > 0.0:
		animated_sprite.modulate = Color(1.0, 0.5, 0.5, 1.0)
	else:
		animated_sprite.modulate = strengthened_character_tint if is_network_strengthened else Color.WHITE


func _update_visuals(is_walking: bool) -> void:
	last_movement_state = is_walking
	if animated_sprite == null or is_network_attacking or is_network_defeated:
		return

	animated_sprite.flip_h = facing_direction < 0
	var next_animation: StringName = &"walk" if is_walking or is_network_dashing else &"idle"
	if animated_sprite.animation != next_animation:
		animated_sprite.play(next_animation)
	elif not animated_sprite.is_playing():
		animated_sprite.play()

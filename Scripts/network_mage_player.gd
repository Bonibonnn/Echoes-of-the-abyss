extends CharacterBody2D

# LAN-only Mage controller.
#
# This scene never decides a hit, target, cooldown, or spell position by
# itself. It sends input intentions to lan_knight_match.gd, and the host tells
# every computer which cast animation, health value, and movement to show.

@export_category("LAN Mage Stats")
@export var movement_speed := 120.0
@export var network_max_health := 4

@export_category("Attack 1 - Close Freeze")
@export var close_freeze_radius := 30.0
@export var close_freeze_duration := 3.0
@export var close_freeze_cooldown := 0.8
@export var close_freeze_cast_duration := 3.0
@export var close_freeze_release_time := 1.0

@export_category("Attack 2 - Fire Explosion")
@export var fire_explosion_damage := 2
@export var fire_explosion_radius := 30.0
@export var fire_explosion_target_range := 340.0
@export var fire_explosion_cooldown := 1.25
@export var fire_explosion_cast_duration := 2.8
@export var fire_explosion_release_time := 1.02

@export_category("Skill 1 - Freeze Area")
@export var freeze_area_target_range := 130.0
@export var freeze_area_duration := 2.5
@export var freeze_area_cooldown := 5.0
@export var freeze_area_cast_duration := 1.2
@export var freeze_area_release_time := 0.35

@export_category("Skill 2 - Fireball")
@export var fireball_damage := 2
@export var fireball_cooldown := 4.0
@export var fireball_cast_duration := 1.8
@export var fireball_release_time := 1.0
@export var fireball_spawn_offset := Vector2(26.0, -4.0)

@export_category("Burn and Freeze")
@export var burn_duration := 4.0
@export var burn_damage_per_tick := 1
@export var burn_tick_interval := 1.0
@export var burn_orange := Color(1.0, 0.38, 0.06, 1.0)
@export var freeze_dark_blue := Color(0.12, 0.22, 0.55, 1.0)

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
@onready var camera := get_node_or_null(^"Camera2D") as Camera2D
@onready var collision_shape := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
@onready var peer_label := get_node_or_null(^"peer_label") as Label
@onready var health_label := get_node_or_null(^"health_label") as Label
@onready var health_bar := get_node_or_null(^"health_bar") as ProgressBar

var facing_direction := 1
var is_network_casting := false
var active_cast_sequence := -1
var last_movement_state := false

# Local input values are not game state. They only tell the host what this
# player is trying to do.
var local_input_sequence := 0
var local_facing_intent := 1
var last_server_motion_sequence := -1

# The host sends life state to both screens. The revision lets the host ignore
# an action request that was made before a damage or respawn update arrived.
var health := 4
var max_health := 4
var health_revision := 0
var is_network_defeated := false
var hurt_flash_time_left := 0.0
var player_title := "Mage"


func _ready() -> void:
	_refresh_player_title()
	_set_cast_animations_non_looping()

	# Only the owner of this player node may move this computer's camera.
	if camera != null:
		camera.enabled = is_multiplayer_authority()

	if peer_label != null:
		var peer_color: Color = Color(0.4, 0.82, 1.0, 1.0) if get_multiplayer_authority() == 1 else Color(1.0, 0.62, 0.45, 1.0)
		peer_label.add_theme_color_override(&"font_color", peer_color)

	local_facing_intent = facing_direction
	_refresh_life_ui()
	_update_visuals(false)


# Called by the shared match before this player is added to the Players node.
func set_selected_character(approved_character: String) -> void:
	if approved_character != "mage":
		return
	_refresh_player_title()
	if is_inside_tree():
		_refresh_life_ui()


func get_network_max_health() -> int:
	return maxi(1, network_max_health)


# The host reads all balance values from its Mage scene. A network request only
# contains an action name and facing direction, never damage or a target.
func get_network_mage_action_config(action_id: String) -> Dictionary:
	match action_id:
		"attack1":
			return {
				"cooldown": close_freeze_cooldown,
				"cast_duration": close_freeze_cast_duration,
				"release_time": close_freeze_release_time,
				"range": close_freeze_radius,
				"freeze_duration": close_freeze_duration,
			}
		"attack2":
			return {
				"cooldown": fire_explosion_cooldown,
				"cast_duration": fire_explosion_cast_duration,
				"release_time": fire_explosion_release_time,
				"target_range": fire_explosion_target_range,
				"explosion_radius": fire_explosion_radius,
				"damage": fire_explosion_damage,
				"burn_duration": burn_duration,
				"burn_damage": burn_damage_per_tick,
				"burn_interval": burn_tick_interval,
			}
		"skill1":
			return {
				"cooldown": freeze_area_cooldown,
				"cast_duration": freeze_area_cast_duration,
				"release_time": freeze_area_release_time,
				"target_range": freeze_area_target_range,
				"freeze_duration": freeze_area_duration,
			}
		"skill2":
			return {
				"cooldown": fireball_cooldown,
				"cast_duration": fireball_cast_duration,
				"release_time": fireball_release_time,
				"damage": fireball_damage,
				"burn_duration": burn_duration,
				"burn_damage": burn_damage_per_tick,
				"burn_interval": burn_tick_interval,
				"spawn_offset": fireball_spawn_offset,
			}
	return {}


func _refresh_player_title() -> void:
	var owner_title := "Host" if get_multiplayer_authority() == 1 else "Joiner"
	player_title = "%s Mage" % owner_title


func _set_cast_animations_non_looping() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	for animation_name: StringName in [&"attack1", &"attack2", &"skill1", &"skill2"]:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			animated_sprite.sprite_frames.set_animation_loop_mode(animation_name, SpriteFrames.LOOP_NONE)


func _process(delta: float) -> void:
	if is_network_defeated:
		return

	if hurt_flash_time_left > 0.0:
		hurt_flash_time_left = maxf(0.0, hurt_flash_time_left - delta)
		_refresh_body_modulate()


func _physics_process(_delta: float) -> void:
	# Remote Mage nodes display server snapshots only; they never read this
	# computer's keyboard, mouse, or input map.
	if not is_multiplayer_authority():
		return

	var direction := Vector2.ZERO
	if not is_network_defeated and not is_network_casting:
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if not is_zero_approx(direction.x):
			local_facing_intent = 1 if direction.x > 0.0 else -1

		# This matches the normal Mage's controls: Q, E, right-click, left-click.
		if InputMap.has_action(&"skill1") and Input.is_action_just_pressed(&"skill1"):
			_request_mage_action_from_host("skill1")
			direction = Vector2.ZERO
		elif InputMap.has_action(&"skill2") and Input.is_action_just_pressed(&"skill2"):
			_request_mage_action_from_host("skill2")
			direction = Vector2.ZERO
		elif InputMap.has_action(&"attack2") and Input.is_action_just_pressed(&"attack2"):
			_request_mage_action_from_host("attack2")
			direction = Vector2.ZERO
		elif InputMap.has_action(&"attack") and Input.is_action_just_pressed(&"attack"):
			_request_mage_action_from_host("attack1")
			direction = Vector2.ZERO

	_submit_movement_input_to_host(direction)


func _request_mage_action_from_host(action_id: String) -> void:
	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return

	if multiplayer.is_server():
		arena.call(
			&"request_host_mage_action",
			get_multiplayer_authority(),
			action_id,
			local_facing_intent
		)
	else:
		arena.rpc_id(
			1,
			&"request_mage_action",
			action_id,
			local_facing_intent,
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


# The host is the only copy that moves through walls and calls move_and_slide.
func simulate_host_movement(direction: Vector2) -> void:
	if not multiplayer.is_server():
		return

	if is_network_defeated or is_network_casting:
		velocity = Vector2.ZERO
		_update_visuals(false)
		return

	var safe_direction := direction.limit_length(1.0)
	if not is_zero_approx(safe_direction.x):
		facing_direction = 1 if safe_direction.x > 0.0 else -1

	velocity = safe_direction * movement_speed
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


# Both computers play the exact cast chosen by the host. The player script has
# no local timer that can decide whether the spell actually releases.
func start_network_mage_action(sequence: int, network_facing: int, action_id: String) -> void:
	if is_network_defeated or sequence < active_cast_sequence:
		return

	active_cast_sequence = sequence
	is_network_casting = true
	facing_direction = 1 if network_facing >= 0 else -1
	velocity = Vector2.ZERO

	if animated_sprite != null:
		animated_sprite.flip_h = facing_direction < 0
		animated_sprite.play(StringName(action_id))
		animated_sprite.frame = 0
		animated_sprite.frame_progress = 0.0


func finish_network_mage_action(sequence: int) -> void:
	if is_network_defeated or sequence != active_cast_sequence:
		return

	is_network_casting = false
	_update_visuals(last_movement_state)


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
		is_network_casting = false
		active_cast_sequence = -1
		velocity = Vector2.ZERO
		hurt_flash_time_left = 0.0
		_set_body_collision_enabled(false)
	elif was_defeated or should_move:
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
		animated_sprite.modulate = Color.WHITE


func _update_visuals(is_walking: bool) -> void:
	last_movement_state = is_walking
	if animated_sprite == null or is_network_casting or is_network_defeated:
		return

	animated_sprite.flip_h = facing_direction < 0
	var next_animation: StringName = &"walk" if is_walking else &"idle"
	if animated_sprite.animation != next_animation:
		animated_sprite.play(next_animation)
	elif not animated_sprite.is_playing():
		animated_sprite.play()

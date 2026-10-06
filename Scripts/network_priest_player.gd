extends CharacterBody2D

# LAN-only Priest controller.
#
# This node sends movement and button intentions only. The shared LAN match
# running on the host validates every target, cooldown, heal, and damage block
# before it tells both computers which animation and visual state to show.

@export_category("LAN Priest Stats")
@export var movement_speed := 115.0
@export var network_max_health := 6

@export_category("Attack 1 - Close Auraplosion")
@export var close_attack_damage := 2
@export var close_attack_radius := 70.0
@export var close_attack_cooldown := 0.7
@export var close_attack_cast_duration := 1.8
@export var close_attack_release_time := 1.0

@export_category("Attack 2 - Ranged Auraplosion")
@export var ranged_attack_damage := 3
@export var ranged_target_range := 360.0
@export var ranged_attack_cooldown := 1.25
@export var ranged_attack_cast_duration := 1.8
@export var ranged_attack_release_time := 1.0

@export_category("Skill 1 - Heal")
@export var heal_amount := 3
# Q heals the Priest and every living LAN teammate inside this circle.
@export_range(1.0, 500.0, 1.0, "suffix:px") var heal_radius := 110.0
@export var heal_cooldown := 5.0
@export var heal_cast_duration := 1.2
@export var heal_release_time := 1.0

@export_category("Skill 2 - Invulnerability")
@export var invulnerability_duration := 2.0
@export var invulnerability_cooldown := 8.0
@export var invulnerability_blue := Color(0.35, 0.7, 1.0, 1.0)

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
@onready var camera := get_node_or_null(^"Camera2D") as Camera2D
@onready var collision_shape := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
@onready var peer_label := get_node_or_null(^"peer_label") as Label
@onready var health_label := get_node_or_null(^"health_label") as Label
@onready var health_bar := get_node_or_null(^"health_bar") as ProgressBar

var facing_direction := 1
var is_network_casting := false
var is_network_invulnerable := false
var active_cast_sequence := -1
var last_movement_state := false

# Input values are merely requests to the host. They are not authoritative
# position, cooldown, target, health, or invulnerability state.
var local_input_sequence := 0
var local_facing_intent := 1
var last_server_motion_sequence := -1

var health := 6
var max_health := 6
var health_revision := 0
var is_network_defeated := false
var hurt_flash_time_left := 0.0
var player_title := "Priest"


func _ready() -> void:
	_refresh_player_title()
	_set_cast_animations_non_looping()

	# The local player alone owns this computer's camera.
	if camera != null:
		camera.enabled = is_multiplayer_authority()

	if peer_label != null:
		var peer_color: Color = Color(0.4, 0.82, 1.0, 1.0) if get_multiplayer_authority() == 1 else Color(1.0, 0.62, 0.45, 1.0)
		peer_label.add_theme_color_override(&"font_color", peer_color)

	local_facing_intent = facing_direction
	_refresh_life_ui()
	_update_visuals(false)


func set_selected_character(approved_character: String) -> void:
	if approved_character != "priest":
		return
	_refresh_player_title()
	if is_inside_tree():
		_refresh_life_ui()


func get_network_max_health() -> int:
	return maxi(1, network_max_health)


# Only the host reads these values. A client never sends damage, target range,
# heal strength, invulnerability duration, or cooldowns across the network.
func get_network_priest_action_config(action_id: String) -> Dictionary:
	match action_id:
		"attack1":
			return {
				"cooldown": close_attack_cooldown,
				"cast_duration": close_attack_cast_duration,
				"release_time": close_attack_release_time,
				"damage": close_attack_damage,
				"range": close_attack_radius,
			}
		"attack2":
			return {
				"cooldown": ranged_attack_cooldown,
				"cast_duration": ranged_attack_cast_duration,
				"release_time": ranged_attack_release_time,
				"damage": ranged_attack_damage,
				"target_range": ranged_target_range,
			}
		"skill1":
			return {
				"cooldown": heal_cooldown,
				"cast_duration": heal_cast_duration,
				"release_time": heal_release_time,
				"heal_amount": heal_amount,
				"heal_radius": heal_radius,
			}
		"skill2":
			return {
				"cooldown": invulnerability_cooldown,
				"duration": invulnerability_duration,
			}
	return {}


func _refresh_player_title() -> void:
	var owner_title := "Host" if get_multiplayer_authority() == 1 else "Joiner"
	player_title = "%s Priest" % owner_title


func _set_cast_animations_non_looping() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	for animation_name: StringName in [&"attack1", &"attack2", &"heal"]:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			animated_sprite.sprite_frames.set_animation_loop_mode(animation_name, SpriteFrames.LOOP_NONE)


func _process(delta: float) -> void:
	if is_network_defeated:
		return

	if hurt_flash_time_left > 0.0:
		hurt_flash_time_left = maxf(0.0, hurt_flash_time_left - delta)
		_refresh_body_modulate()


func _physics_process(_delta: float) -> void:
	# Remote Priest nodes never read the local keyboard, mouse, or input map.
	if not is_multiplayer_authority():
		return

	var direction := Vector2.ZERO
	if not is_network_defeated and not is_network_casting:
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if not is_zero_approx(direction.x):
			local_facing_intent = 1 if direction.x > 0.0 else -1

		# Q heals, E applies the blue damage shield, right-click is ranged, and
		# left-click is the close auraplosion—matching the normal Priest controls.
		if InputMap.has_action(&"skill1") and Input.is_action_just_pressed(&"skill1"):
			_request_priest_action_from_host("skill1")
			direction = Vector2.ZERO
		elif InputMap.has_action(&"skill2") and Input.is_action_just_pressed(&"skill2"):
			_request_priest_action_from_host("skill2")
		elif InputMap.has_action(&"attack2") and Input.is_action_just_pressed(&"attack2"):
			_request_priest_action_from_host("attack2")
			direction = Vector2.ZERO
		elif InputMap.has_action(&"attack") and Input.is_action_just_pressed(&"attack"):
			_request_priest_action_from_host("attack1")
			direction = Vector2.ZERO

	_submit_movement_input_to_host(direction)


func _request_priest_action_from_host(action_id: String) -> void:
	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return

	if multiplayer.is_server():
		arena.call(
			&"request_host_priest_action",
			get_multiplayer_authority(),
			action_id,
			local_facing_intent
		)
	else:
		arena.rpc_id(
			1,
			&"request_priest_action",
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


# The host alone moves this body through walls and other collision shapes.
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


# E has no cast animation. The host only uses this for the three actions that
# lock movement and play an animation: attack1, attack2, and heal.
func start_network_priest_action(sequence: int, network_facing: int, action_id: String) -> void:
	if is_network_defeated or sequence < active_cast_sequence:
		return

	active_cast_sequence = sequence
	is_network_casting = true
	facing_direction = 1 if network_facing >= 0 else -1
	velocity = Vector2.ZERO

	var animation_name: StringName = &"heal" if action_id == "skill1" else StringName(action_id)
	if animated_sprite != null:
		animated_sprite.flip_h = facing_direction < 0
		animated_sprite.play(animation_name)
		animated_sprite.frame = 0
		animated_sprite.frame_progress = 0.0


func finish_network_priest_action(sequence: int) -> void:
	if is_network_defeated or sequence != active_cast_sequence:
		return

	is_network_casting = false
	_update_visuals(last_movement_state)


# The blue tint is only visual here. The host stores the real protection flag
# and ignores an incoming hit before it changes health.
func set_network_invulnerable(enabled: bool) -> void:
	is_network_invulnerable = enabled
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
		is_network_casting = false
		is_network_invulnerable = false
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
	elif is_network_invulnerable:
		animated_sprite.modulate = invulnerability_blue
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

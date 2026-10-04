extends CharacterBody2D

# LAN-only Knight controller.
#
# This scene does not use the normal player.gd script, so single-player stays
# untouched. The local computer sends only button and movement intentions; the
# host validates all Knight damage, cooldowns, blocking, and movement before
# synchronizing the result to both players.

@export_category("LAN Knight Stats")
@export var movement_speed := 120.0
@export var network_max_health := 5

@export_category("Attack 1 - Basic Slash")
@export var attack1_damage := 1
@export var attack1_cooldown := 0.60
@export var attack1_duration := 0.88
@export var attack1_hit_time := 0.26

@export_category("Attack 2 - Two-Swing Combo")
# The combo has two visible swings but deals one combined damage event, matching
# the normal Knight. This keeps the target's hurt protection from eating hit two.
@export var attack2_total_damage := 2
@export var attack2_cooldown := 3.0
@export var attack2_duration := 1.25
@export var attack2_hit_time := 0.18

@export_category("Skill 1 - Heavy Strike")
# Q: a slow, strong melee hit. Damage does not cancel this cast or show a hurt
# tint, but the host can still reduce the Knight's real health while it is cast.
@export var skill1_damage := 4
@export var skill1_cast_duration := 2.2
@export var skill1_hit_time := 0.75
@export var skill1_cooldown := 2.2

@export_category("Skill 2 - Block")
# E: absorbs exactly one host-approved incoming damage event, then starts its
# two-second cooldown. Its window lasts through the block animation.
@export var block_duration := 0.8
@export var block_cooldown := 2.0

@onready var animated_sprite := get_node_or_null(^"animated_sprite") as AnimatedSprite2D
@onready var camera := get_node_or_null(^"camera") as Camera2D
@onready var collision_shape := get_node_or_null(^"collision_shape") as CollisionShape2D
@onready var player_hitbox := get_node_or_null(^"player_hitbox") as Area2D
@onready var player_hitbox_collision_shape := get_node_or_null(^"player_hitbox/collision_shape") as CollisionShape2D
@onready var peer_label := get_node_or_null(^"peer_label") as Label
@onready var health_label := get_node_or_null(^"health_label") as Label
@onready var health_bar := get_node_or_null(^"health_bar") as ProgressBar

var facing_direction := 1
var is_network_attacking := false
var is_network_heavy_casting := false
var is_network_blocking := false
var active_attack_sequence := -1
var active_action_id: StringName = &""
var last_movement_state := false

# The local peer only sends these input intentions. The host returns the real
# resulting position with its own increasing motion sequence.
var local_input_sequence := 0
var local_facing_intent := 1
var last_server_motion_sequence := -1

# The host supplies these values through the root LAN-match RPC.
var health := 5
var max_health := 5
var health_revision := 0
var is_network_defeated := false
var hurt_flash_time_left := 0.0
var player_title := "Knight"


func _ready() -> void:
	var peer_id := get_multiplayer_authority()
	_refresh_player_title()
	_set_action_animations_non_looping()

	# Each running game follows only the Knight controlled by that game.
	if camera != null:
		camera.enabled = is_multiplayer_authority()

	if peer_label != null:
		var label_color: Color = Color(0.4, 0.82, 1.0, 1.0) if peer_id == 1 else Color(1.0, 0.62, 0.45, 1.0)
		peer_label.add_theme_color_override(&"font_color", label_color)

	local_facing_intent = facing_direction
	_sync_player_hitbox()
	_refresh_life_ui()
	_update_visuals(false)


# Called by the reliable host-owned spawn RPC. The Knight scene accepts only
# the approved Knight roster entry; it cannot be used to impersonate a class.
func set_selected_character(approved_character: String) -> void:
	if approved_character != "knight":
		return
	_refresh_player_title()
	if is_inside_tree():
		_refresh_life_ui()


func get_network_max_health() -> int:
	return maxi(1, network_max_health)


# Only the host reads this configuration. A client cannot submit its own damage,
# hit timing, or block duration through an RPC.
func get_network_knight_action_config(action_id: String) -> Dictionary:
	match action_id:
		"attack1":
			return {
				"damage": attack1_damage,
				"cooldown": attack1_cooldown,
				"duration": attack1_duration,
				"hit_time": attack1_hit_time,
			}
		"attack2":
			return {
				"damage": attack2_total_damage,
				"cooldown": attack2_cooldown,
				"duration": attack2_duration,
				"hit_time": attack2_hit_time,
			}
		"skill1":
			return {
				"damage": skill1_damage,
				"cooldown": skill1_cooldown,
				"duration": skill1_cast_duration,
				"hit_time": skill1_hit_time,
			}
		"skill2":
			return {
				"cooldown": block_cooldown,
				"duration": block_duration,
			}
	return {}


func _refresh_player_title() -> void:
	var owner_title := "Host" if get_multiplayer_authority() == 1 else "Joiner"
	player_title = "%s Knight" % owner_title


func _set_action_animations_non_looping() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	for animation_name: StringName in [&"attack", &"attack2", &"skill", &"block"]:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			animated_sprite.sprite_frames.set_animation_loop_mode(animation_name, SpriteFrames.LOOP_NONE)


func _process(delta: float) -> void:
	if is_network_defeated:
		return

	if hurt_flash_time_left > 0.0:
		hurt_flash_time_left = maxf(0.0, hurt_flash_time_left - delta)
	_refresh_body_modulate()


func _physics_process(_delta: float) -> void:
	# A remote replica never reads this computer's controls.
	if not is_multiplayer_authority():
		return

	var direction := Vector2.ZERO
	if not is_network_defeated and not is_network_attacking:
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if not is_zero_approx(direction.x):
			local_facing_intent = 1 if direction.x > 0.0 else -1

		# Keep the same control order as the normal Knight: Q heavy strike,
		# E block, right-click combo, then left-click basic slash.
		if InputMap.has_action(&"skill1") and Input.is_action_just_pressed(&"skill1"):
			_request_knight_action_from_host("skill1")
			direction = Vector2.ZERO
		elif InputMap.has_action(&"skill2") and Input.is_action_just_pressed(&"skill2"):
			_request_knight_action_from_host("skill2")
			direction = Vector2.ZERO
		elif InputMap.has_action(&"attack2") and Input.is_action_just_pressed(&"attack2"):
			_request_knight_action_from_host("attack2")
			direction = Vector2.ZERO
		elif InputMap.has_action(&"attack") and Input.is_action_just_pressed(&"attack"):
			_request_knight_action_from_host("attack1")
			direction = Vector2.ZERO

	_submit_movement_input_to_host(direction)


# Sends only a named action and the local left/right facing. The host validates
# the selected class, life revision, cooldown, animation timing, and hitbox.
func _request_knight_action_from_host(action_id: String) -> void:
	if is_network_defeated:
		return

	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return

	if multiplayer.is_server():
		arena.call(
			&"request_host_knight_action",
			get_multiplayer_authority(),
			action_id,
			local_facing_intent
		)
	else:
		arena.rpc_id(
			1,
			&"request_knight_action",
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


# Runs only on the host. This remains the only method that calls
# move_and_slide(), so wall collision has one shared answer for every peer.
func simulate_host_movement(direction: Vector2) -> void:
	if not multiplayer.is_server():
		return

	if is_network_defeated or is_network_attacking:
		velocity = Vector2.ZERO
		_update_visuals(false)
		return

	var safe_direction: Vector2 = direction.limit_length(1.0)
	if not is_zero_approx(safe_direction.x):
		facing_direction = 1 if safe_direction.x > 0.0 else -1

	velocity = safe_direction * movement_speed
	move_and_slide()
	_update_visuals(not safe_direction.is_zero_approx())


func set_host_facing(network_facing: int) -> void:
	if not multiplayer.is_server() or is_network_defeated or network_facing == 0:
		return

	facing_direction = 1 if network_facing > 0 else -1
	_sync_player_hitbox()
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

	_sync_player_hitbox()
	_update_visuals(network_is_walking)


# The match root calls this only after the host approves a Knight action. An old
# finish RPC cannot cut off a newer action because every action has a sequence.
func start_network_knight_action(sequence: int, network_facing: int, action_id: String) -> void:
	if is_network_defeated or sequence < active_attack_sequence:
		return

	active_attack_sequence = sequence
	active_action_id = StringName(action_id)
	is_network_attacking = true
	is_network_heavy_casting = action_id == "skill1"
	is_network_blocking = action_id == "skill2"
	facing_direction = 1 if network_facing >= 0 else -1
	_sync_player_hitbox()
	velocity = Vector2.ZERO

	var animation_name := _get_animation_for_action(action_id)
	if animated_sprite != null:
		animated_sprite.flip_h = facing_direction < 0
		animated_sprite.play(animation_name)
		animated_sprite.frame = 0
		animated_sprite.frame_progress = 0.0


func finish_network_knight_action(sequence: int) -> void:
	if is_network_defeated or sequence != active_attack_sequence:
		return

	_clear_action_visual_state()
	_update_visuals(last_movement_state)


func _get_animation_for_action(action_id: String) -> StringName:
	match action_id:
		"attack2":
			return &"attack2"
		"skill1":
			return &"skill"
		"skill2":
			return &"block"
	return &"attack"


func _clear_action_visual_state() -> void:
	is_network_attacking = false
	is_network_heavy_casting = false
	is_network_blocking = false
	active_action_id = &""


# The host calls this on an exact impact frame. The Area2D overlap is the only
# evidence that a Knight melee action connected with the shared training slime.
func has_player_hitbox_overlap(target: CharacterBody2D) -> bool:
	if not multiplayer.is_server() or is_network_defeated or not is_network_attacking:
		return false
	if player_hitbox == null or target == null:
		return false

	_sync_player_hitbox()
	return player_hitbox.overlaps_body(target)


# Mirrors the small forward rectangle whenever the Knight turns left/right.
func _sync_player_hitbox() -> void:
	if player_hitbox != null:
		player_hitbox.scale = Vector2(
			absf(player_hitbox.scale.x) * float(facing_direction),
			player_hitbox.scale.y
		)


# Host-owned health only affects this node's visuals and UI. A heavy-strike hit
# deliberately suppresses the red hurt flash but does not stop the cast.
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
		_clear_action_visual_state()
		active_attack_sequence = -1
		velocity = Vector2.ZERO
		hurt_flash_time_left = 0.0
		_set_body_collision_enabled(false)
	elif was_defeated or should_move:
		hurt_flash_time_left = 0.0
		_set_body_collision_enabled(true)
		_update_visuals(false)
	elif took_damage and not is_network_heavy_casting:
		hurt_flash_time_left = 0.16

	_refresh_body_modulate()
	_refresh_life_ui()


func _set_body_collision_enabled(is_enabled: bool) -> void:
	if collision_shape != null:
		collision_shape.set_deferred(&"disabled", not is_enabled)
	if player_hitbox_collision_shape != null:
		player_hitbox_collision_shape.set_deferred(&"disabled", not is_enabled)


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
	elif hurt_flash_time_left > 0.0 and not is_network_heavy_casting:
		animated_sprite.modulate = Color(1.0, 0.5, 0.5, 1.0)
	else:
		animated_sprite.modulate = Color.WHITE


func _update_visuals(is_walking: bool) -> void:
	last_movement_state = is_walking
	_sync_player_hitbox()
	if animated_sprite == null or is_network_attacking or is_network_defeated:
		return

	animated_sprite.flip_h = facing_direction < 0
	var next_animation: StringName = &"walk" if is_walking else &"idle"

	# Only change animation when needed, so it does not restart every frame.
	if animated_sprite.animation != next_animation:
		animated_sprite.play(next_animation)
	elif not animated_sprite.is_playing():
		animated_sprite.play()

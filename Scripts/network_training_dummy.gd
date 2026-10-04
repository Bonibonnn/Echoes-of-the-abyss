extends CharacterBody2D

# This is the shared behavior for pre-placed LAN melee enemies. It does not use
# normal Combatant scripts, so the host alone chooses targets, movement, attacks,
# health, debuffs, and player damage while the other computer only receives state.

@export_category("Identity and Animations")
@export var enemy_display_name: String = "Host Slime"
@export var attack_animation: StringName = &"attack1"
@export var hurt_animation: StringName = &""
@export var death_animation: StringName = &""

@export_category("Movement and Health")
@export var max_health := 6
@export var hurt_duration := 0.16

# The player_hitbox and enemy_hitbox shapes are stored in this separate LAN
# scene. The host queries them only at the attack's contact frame.
@export var detection_range := 260.0
@export var chase_speed := 65.0
@export var attack_damage := 1
@export var attack_cooldown := 1.35
@export var attack_hit_delay := 0.52
@export var attack_duration := 1.20

@onready var animated_sprite := get_node_or_null(^"animated_sprite") as AnimatedSprite2D
@onready var health_bar := get_node_or_null(^"health_bar") as ProgressBar
@onready var health_label := get_node_or_null(^"health_label") as Label
@onready var status_label := get_node_or_null(^"status_label") as Label
@onready var collision_shape := get_node_or_null(^"collision_shape") as CollisionShape2D
@onready var enemy_hitbox := get_node_or_null(^"enemy_hitbox") as Area2D
@onready var enemy_hitbox_collision_shape := get_node_or_null(^"enemy_hitbox/collision_shape") as CollisionShape2D

# Health and its revision are host-owned. A higher revision always wins over an
# older network packet, so a late packet cannot revive a defeated slime.
var health := 0
var state_revision := 0
var is_defeated := false
var hurt_flash_time_left := 0.0

# Mage debuffs are also host-owned. Tokens refresh an existing freeze or burn
# instead of leaving old timer coroutines running after a spell is recast.
var is_network_frozen := false
var is_network_burning := false
var freeze_token := 0
var burn_token := 0
var debuff_revision := 0

# The host uses this token to cancel an old queued hit when the slime dies or a
# newer attack has begun. Clients use it only to keep attack visuals in order.
var attack_token := 0
var is_host_attacking := false
var next_attack_time := 0.0
var facing_direction := 1
var last_movement_state := false
var home_position := Vector2.ZERO


func _ready() -> void:
	# The LAN controller finds every shared enemy through this group. Each scene
	# stays at the same node path on both computers, which keeps its RPC calls safe.
	add_to_group(&"lan_enemy")
	home_position = global_position
	health = max_health
	_prepare_one_shot_animations()
	_sync_enemy_hitbox()
	_refresh_visuals()
	_update_visuals(false)


# This stable interface lets the controller reject dead or unrelated collision
# bodies before it applies any host-authoritative attack damage.
func is_lan_enemy_alive() -> bool:
	return not is_defeated and is_inside_tree()


func _process(delta: float) -> void:
	# The red flash and spell tints are cosmetic. The host still owns the actual
	# freeze, burn, HP, and death state.
	if animated_sprite == null or is_defeated:
		return

	if hurt_flash_time_left > 0.0:
		hurt_flash_time_left = maxf(0.0, hurt_flash_time_left - delta)
		if is_zero_approx(hurt_flash_time_left):
			_update_visuals(last_movement_state)
	_refresh_body_modulate()


func _physics_process(_delta: float) -> void:
	# Joining computers never run the AI. They only receive the host's motion,
	# attack visuals, health, and defeat state.
	if not multiplayer.is_server() or is_defeated:
		return

	# Freeze stops this host-controlled slime immediately. Burn may still tick
	# while frozen, but it never allows the slime to chase or deal damage.
	if is_network_frozen:
		velocity = Vector2.ZERO
		_update_visuals(false)
		_send_host_state(false)
		return

	if is_host_attacking:
		velocity = Vector2.ZERO
		_send_host_state(false)
		return

	var target := _get_nearest_alive_player()
	if target == null or global_position.distance_to(target.global_position) > detection_range:
		velocity = Vector2.ZERO
		_update_visuals(false)
		_send_host_state(false)
		return

	var to_target := target.global_position - global_position
	if absf(to_target.x) > 0.5:
		facing_direction = 1 if to_target.x > 0.0 else -1
	_sync_enemy_hitbox()

	# Stop at the front attack Area2D's contact range. The same host checks run again at the later
	# hit moment, so running away during the animation avoids the damage.
	if _is_valid_host_attack_target(target):
		velocity = Vector2.ZERO
		_update_visuals(false)
		_send_host_state(false)
		_start_host_attack(target.get_multiplayer_authority())
		return

	velocity = to_target.normalized() * chase_speed
	move_and_slide()
	_update_visuals(true)
	_send_host_state(true)


# Finds the nearest living Knight through the host-owned arena root.
func _get_nearest_alive_player() -> CharacterBody2D:
	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return null

	return arena.call(&"get_nearest_alive_player", global_position) as CharacterBody2D


# Gets the original target again immediately before an attack lands.
func _get_alive_player(peer_id: int) -> CharacterBody2D:
	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return null

	return arena.call(&"get_alive_player", peer_id) as CharacterBody2D


# Starts one server-approved attack. The real hit is delayed to match the
# six-frame attack1 animation, which plays once at five frames per second.
func _start_host_attack(target_peer_id: int) -> void:
	if is_host_attacking or is_defeated:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now < next_attack_time:
		return

	attack_token += 1
	var token := attack_token
	is_host_attacking = true
	next_attack_time = now + attack_cooldown
	velocity = Vector2.ZERO

	# Reliable messages keep the attack animation synchronized on both screens.
	start_host_attack_visual.rpc(token, facing_direction)
	_resolve_host_attack_after_delay(target_peer_id, token)
	_finish_host_attack_after_delay(token)


# The host checks the live target a second time after the visual wind-up. This
# is why an attack does not damage a Knight who escaped before the impact.
func _resolve_host_attack_after_delay(target_peer_id: int, token: int) -> void:
	await get_tree().create_timer(attack_hit_delay).timeout

	if not multiplayer.is_server() or is_defeated:
		return
	if not is_host_attacking or token != attack_token:
		return

	var target := _get_alive_player(target_peer_id)
	if target == null or not _is_valid_host_attack_target(target):
		return

	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena != null:
		arena.call(&"damage_player_on_server", target_peer_id, attack_damage)


# Finishes the non-looping attack after its full animation duration.
func _finish_host_attack_after_delay(token: int) -> void:
	await get_tree().create_timer(attack_duration).timeout

	if token != attack_token:
		return

	is_host_attacking = false
	_finish_host_attack_visual.rpc(token)


# Freeze needs to cancel an animation that may already be halfway through.
# Passing the new token makes an older delayed finish RPC harmless on clients.
@rpc("authority", "call_local", "reliable")
func cancel_host_attack_visual(cancel_token: int) -> void:
	if is_defeated:
		return

	attack_token = maxi(attack_token, cancel_token)
	is_host_attacking = false
	velocity = Vector2.ZERO
	_update_visuals(false)


# This shared state only starts the animation. It never decides damage.
@rpc("authority", "call_local", "reliable")
func start_host_attack_visual(token: int, network_facing: int) -> void:
	if is_defeated or token < attack_token:
		return

	attack_token = token
	is_host_attacking = true
	facing_direction = 1 if network_facing >= 0 else -1
	_sync_enemy_hitbox()
	velocity = Vector2.ZERO

	if animated_sprite != null:
		animated_sprite.flip_h = facing_direction < 0
		if _has_animation(attack_animation):
			animated_sprite.play(attack_animation)


# This shared state ends the animation. The sequence token prevents an older
# finish RPC from stopping a newer attack.
@rpc("authority", "call_local", "reliable")
func _finish_host_attack_visual(token: int) -> void:
	if is_defeated or token != attack_token:
		return

	is_host_attacking = false
	_update_visuals(false)


# The host sends frequent movement snapshots; they are deliberately unreliable
# because a newer position will replace an older one almost immediately.
func _send_host_state(is_walking: bool) -> void:
	last_movement_state = is_walking

	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		sync_host_state.rpc(global_position, facing_direction, is_walking, state_revision)


@rpc("authority", "call_remote", "unreliable")
func sync_host_state(
	network_position: Vector2,
	network_facing: int,
	network_is_walking: bool,
	network_state_revision: int
) -> void:
	if network_state_revision < state_revision:
		return

	# A late joiner still needs the exact position of a defeated slime, but it
	# must not restart any animation after the host has marked it defeated.
	global_position = network_position
	facing_direction = 1 if network_facing >= 0 else -1
	_sync_enemy_hitbox()
	last_movement_state = network_is_walking

	if is_defeated:
		return

	_update_visuals(network_is_walking)


# The root already proved that the host's player_hitbox overlaps this slime.
# This function changes health only on the host; a client cannot call it to
# invent damage or bypass the Area2D contact check.
func take_server_hit(damage: int) -> void:
	if not multiplayer.is_server() or is_defeated or damage <= 0:
		return

	var new_health := maxi(0, health - damage)
	state_revision += 1
	apply_state.rpc(new_health, state_revision, new_health == 0)


# Called only from the host LAN match when a Mage spell has already passed its
# range/target validation. Recasting refreshes duration instead of stacking
# multiple movement-stopping timer loops.
func apply_server_freeze(duration: float) -> void:
	if not multiplayer.is_server() or is_defeated or duration <= 0.0:
		return

	freeze_token += 1
	var token := freeze_token
	is_network_frozen = true
	_cancel_host_attack_for_debuff()
	_broadcast_debuff_state()
	_expire_server_freeze_after_delay(token, duration)


func _expire_server_freeze_after_delay(token: int, duration: float) -> void:
	await get_tree().create_timer(duration).timeout
	if not multiplayer.is_server() or is_defeated or token != freeze_token:
		return

	is_network_frozen = false
	_broadcast_debuff_state()


# Burn is refreshed the same way as freeze. It does not stack parallel tick
# loops, so a repeated Mage spell resets its four-second duration cleanly.
func apply_server_burn(duration: float, damage_per_tick: int, tick_interval: float) -> void:
	if (
		not multiplayer.is_server()
		or is_defeated
		or duration <= 0.0
		or damage_per_tick <= 0
		or tick_interval <= 0.0
	):
		return

	burn_token += 1
	var token := burn_token
	is_network_burning = true
	_broadcast_debuff_state()
	_run_server_burn(token, duration, damage_per_tick, tick_interval)


func _run_server_burn(token: int, duration: float, damage_per_tick: int, tick_interval: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		var wait_seconds := minf(tick_interval, duration - elapsed)
		await get_tree().create_timer(wait_seconds).timeout
		if not multiplayer.is_server() or is_defeated or token != burn_token:
			return

		elapsed += wait_seconds
		take_server_hit(damage_per_tick)

	if not multiplayer.is_server() or is_defeated or token != burn_token:
		return

	is_network_burning = false
	_broadcast_debuff_state()


func _cancel_host_attack_for_debuff() -> void:
	attack_token += 1
	is_host_attacking = false
	velocity = Vector2.ZERO
	cancel_host_attack_visual.rpc(attack_token)


func _broadcast_debuff_state() -> void:
	if not multiplayer.is_server():
		return

	debuff_revision += 1
	apply_network_debuff_state.rpc(is_network_frozen, is_network_burning, debuff_revision)
	_refresh_visuals()


func _clear_server_debuffs() -> void:
	if not multiplayer.is_server():
		return

	freeze_token += 1
	burn_token += 1
	is_network_frozen = false
	is_network_burning = false
	_broadcast_debuff_state()


@rpc("authority", "call_local", "reliable")
func apply_network_debuff_state(frozen: bool, burning: bool, new_revision: int) -> void:
	if new_revision < debuff_revision:
		return

	debuff_revision = new_revision
	is_network_frozen = frozen
	is_network_burning = burning
	_refresh_body_modulate()
	_refresh_visuals()


# This checks the enemy_hitbox Area2D at both the start and impact frame.
# It is mirrored with the sprite, so an attack cannot land behind the slime.
func _is_valid_host_attack_target(target: CharacterBody2D) -> bool:
	if enemy_hitbox == null or target == null:
		return false

	_sync_enemy_hitbox()
	return enemy_hitbox.overlaps_body(target)


# Late joiners receive the already-moving slime's exact life, location, and
# current attack visual instead of seeing a fresh full-health idle slime.
func send_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	apply_state.rpc_id(peer_id, health, state_revision, is_defeated)
	apply_network_debuff_state.rpc_id(peer_id, is_network_frozen, is_network_burning, debuff_revision)
	sync_host_state.rpc_id(peer_id, global_position, facing_direction, last_movement_state, state_revision)

	if is_host_attacking and not is_defeated:
		start_host_attack_visual.rpc_id(peer_id, attack_token, facing_direction)


# Only the host changes this state. Every peer redraws the health bar and
# defeat state from this reliable update.
@rpc("authority", "call_local", "reliable")
func apply_state(new_health: int, new_revision: int, defeated: bool) -> void:
	if new_revision < state_revision:
		return

	var took_damage := new_health < health
	health = clampi(new_health, 0, max_health)
	state_revision = new_revision
	is_defeated = defeated

	if is_defeated:
		# Cancel a waiting attack so it cannot deal damage after death.
		attack_token += 1
		is_host_attacking = false
		velocity = Vector2.ZERO
		hurt_flash_time_left = 0.0
		if multiplayer.is_server():
			_clear_server_debuffs()
		_set_body_collision_enabled(false)
	elif took_damage:
		hurt_flash_time_left = maxf(0.0, hurt_duration)
		_set_body_collision_enabled(true)
		_update_visuals(last_movement_state)
	else:
		_set_body_collision_enabled(true)
		_update_visuals(last_movement_state)

	_refresh_visuals()


# The root calls this only when it begins a fresh hosted LAN session. The slime
# stays at one stable scene path rather than being freed and re-instanced.
func reset_for_network_session() -> void:
	if not multiplayer.is_server():
		return

	attack_token += 1
	is_host_attacking = false
	next_attack_time = 0.0
	velocity = Vector2.ZERO
	facing_direction = 1
	_sync_enemy_hitbox()
	last_movement_state = false
	global_position = home_position
	state_revision += 1
	_clear_server_debuffs()

	apply_state.rpc(max_health, state_revision, false)
	_send_host_state(false)



# Mirrors the forward Area2D rectangle without moving the slime body collider.
func _sync_enemy_hitbox() -> void:
	if enemy_hitbox != null:
		enemy_hitbox.scale = Vector2(
			absf(enemy_hitbox.scale.x) * float(facing_direction),
			enemy_hitbox.scale.y
		)


# The body is what the Knight's player_hitbox detects. The slime's own
# enemy_hitbox is disabled at death so it cannot hurt a respawning Knight.
func _set_body_collision_enabled(is_enabled: bool) -> void:
	if collision_shape != null:
		collision_shape.set_deferred(&"disabled", not is_enabled)
	if enemy_hitbox_collision_shape != null:
		enemy_hitbox_collision_shape.set_deferred(&"disabled", not is_enabled)


func _refresh_visuals() -> void:
	if health_bar != null:
		health_bar.max_value = max_health
		health_bar.value = health

	if health_label != null:
		health_label.text = "%s: %d / %d" % [enemy_display_name, health, max_health]

	if status_label != null:
		if is_defeated:
			status_label.text = "Defeated"
		elif is_network_frozen:
			status_label.text = "Frozen"
		elif is_network_burning:
			status_label.text = "Burning"
		else:
			status_label.text = "Host controls chase + damage"

	if animated_sprite != null and is_defeated:
		if _has_animation(death_animation):
			if animated_sprite.animation != death_animation:
				animated_sprite.play(death_animation)
		else:
			animated_sprite.stop()
		animated_sprite.modulate = Color(0.38, 0.38, 0.44, 1.0)
	elif animated_sprite != null:
		_refresh_body_modulate()


func _refresh_body_modulate() -> void:
	if animated_sprite == null:
		return
	if is_defeated:
		animated_sprite.modulate = Color(0.38, 0.38, 0.44, 1.0)
	elif hurt_flash_time_left > 0.0:
		animated_sprite.modulate = Color(1.0, 0.48, 0.48, 1.0)
	elif is_network_frozen:
		# Freeze takes visual priority when burn and freeze overlap.
		animated_sprite.modulate = Color(0.12, 0.22, 0.55, 1.0)
	elif is_network_burning:
		animated_sprite.modulate = Color(1.0, 0.38, 0.06, 1.0)
	else:
		animated_sprite.modulate = Color.WHITE


func _update_visuals(is_walking: bool) -> void:
	last_movement_state = is_walking
	if animated_sprite == null or is_defeated or is_host_attacking:
		return
	if hurt_flash_time_left > 0.0 and _has_animation(hurt_animation):
		if animated_sprite.animation != hurt_animation:
			animated_sprite.play(hurt_animation)
		return

	animated_sprite.flip_h = facing_direction < 0
	var next_animation: StringName = &"walk" if is_walking else &"idle"

	# Avoid restarting the looping idle/walk animation every physics frame.
	if animated_sprite.animation != next_animation:
		animated_sprite.play(next_animation)
	elif not animated_sprite.is_playing():
		animated_sprite.play()


func _prepare_one_shot_animations() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	for animation_name: StringName in [attack_animation, hurt_animation, death_animation]:
		if _has_animation(animation_name):
			animated_sprite.sprite_frames.set_animation_loop_mode(animation_name, SpriteFrames.LOOP_NONE)


func _has_animation(animation_name: StringName) -> bool:
	return (
		animated_sprite != null
		and animated_sprite.sprite_frames != null
		and not animation_name.is_empty()
		and animated_sprite.sprite_frames.has_animation(animation_name)
	)

extends CharacterBody2D

# LAN-only replacement for the normal single-player enemy scripts. It reuses
# each enemy's existing sprite scene, but only the host runs AI, chooses attacks,
# applies damage, and decides health/debuff state.

# Each profile contains the balance already used by the single-player roster.
# The host may pick from any ready attack that can reach its current target.
const PROFILES: Dictionary = {
	&"bat": {
		"display_name": "Bat", "health": 2, "speed": 90.0,
		"attacks": [{"id": &"attack1", "animation": &"attack1", "damage": 1, "range": 40.0, "cooldown": 1.15, "hit_delay": 0.28, "duration": 0.75, "mode": "front", "weight": 1.0}],
	},
	&"slime": {
		"display_name": "Slime", "health": 3, "speed": 75.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 1, "range": 42.0, "cooldown": 1.25, "hit_delay": 0.45, "duration": 1.0, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 2, "range": 48.0, "cooldown": 3.0, "hit_delay": 0.55, "duration": 1.1, "mode": "front", "weight": 1.0},
		],
	},
	&"werewolf": {
		"display_name": "Werewolf", "health": 3, "speed": 90.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 1, "range": 46.0, "cooldown": 1.2, "hit_delay": 0.35, "duration": 0.85, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 1, "range": 150.0, "cooldown": 4.5, "hit_delay": 0.2, "duration": 0.9, "mode": "dash", "dash_speed": 250.0, "dash_radius": 30.0, "dash_tick": 0.35, "weight": 1.0},
		],
	},
	&"werebear": {
		"display_name": "Werebear", "health": 25, "speed": 55.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 2, "range": 52.0, "cooldown": 1.4, "hit_delay": 0.42, "duration": 1.0, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 2, "range": 56.0, "cooldown": 3.2, "hit_delay": 0.38, "duration": 1.1, "mode": "front", "hits": 2, "hit_interval": 0.26, "weight": 1.0},
			{"id": &"attack3", "animation": &"attack3", "damage": 1, "range": 78.0, "cooldown": 6.0, "hit_delay": 0.62, "duration": 1.25, "mode": "circle", "stun": 2.0, "weight": 0.65},
		],
	},
	&"orc": {
		"display_name": "Orc", "health": 3, "speed": 90.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack", "damage": 1, "range": 44.0, "cooldown": 1.15, "hit_delay": 0.38, "duration": 0.85, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 2, "range": 48.0, "cooldown": 2.8, "hit_delay": 0.5, "duration": 1.0, "mode": "front", "weight": 1.0},
		],
	},
	&"armored_orc": {
		"display_name": "Armored Orc", "health": 6, "speed": 70.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 2, "range": 48.0, "cooldown": 1.35, "hit_delay": 0.42, "duration": 0.95, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 1, "range": 76.0, "cooldown": 2.4, "hit_delay": 0.48, "duration": 1.0, "mode": "front_range", "weight": 1.0},
			{"id": &"attack3", "animation": &"attack3", "damage": 0, "range": 72.0, "cooldown": 5.5, "hit_delay": 0.6, "duration": 1.2, "mode": "circle", "stun": 1.6, "weight": 0.55},
		],
	},
	&"orc_rider": {
		"display_name": "Orc Rider", "health": 6, "speed": 100.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 2, "range": 60.0, "cooldown": 1.2, "hit_delay": 0.35, "duration": 0.8, "mode": "front_range", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 3, "range": 48.0, "cooldown": 3.0, "hit_delay": 0.46, "duration": 1.0, "mode": "front", "weight": 1.0},
			{"id": &"attack3", "animation": &"attack3", "damage": 2, "range": 70.0, "cooldown": 4.5, "hit_delay": 0.58, "duration": 1.05, "mode": "circle", "weight": 0.7},
		],
	},
	&"elite_orc": {
		"display_name": "Elite Orc", "health": 40, "speed": 58.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 3, "range": 54.0, "cooldown": 1.45, "hit_delay": 0.45, "duration": 1.0, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 3, "range": 82.0, "cooldown": 10.0, "hit_delay": 0.72, "duration": 1.35, "mode": "circle", "weight": 0.8},
			{"id": &"attack3", "animation": &"attack3", "damage": 5, "range": 62.0, "cooldown": 20.0, "hit_delay": 0.78, "duration": 1.45, "mode": "front", "weight": 0.35},
		],
	},
	&"skeleton": {
		"display_name": "Skeleton", "health": 4, "speed": 75.0,
		"attacks": [{"id": &"attack1", "animation": &"attack", "damage": 1, "range": 42.0, "cooldown": 1.2, "hit_delay": 0.4, "duration": 0.9, "mode": "front", "weight": 1.0}],
	},
	&"skeleton_archer": {
		"display_name": "Skeleton Archer", "health": 3, "speed": 65.0,
		"attacks": [{"id": &"attack1", "animation": &"attack1", "damage": 1, "range": 220.0, "cooldown": 1.8, "hit_delay": 0.56, "duration": 1.0, "mode": "ranged", "weight": 1.0}],
	},
	&"armored_skeleton": {
		"display_name": "Armored Skeleton", "health": 8, "speed": 65.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 2, "range": 52.0, "cooldown": 1.35, "hit_delay": 0.45, "duration": 0.95, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 1, "range": 66.0, "cooldown": 3.4, "hit_delay": 0.55, "duration": 1.15, "mode": "circle", "weight": 1.0},
		],
	},
	&"greatsword_skeleton": {
		"display_name": "Greatsword Skeleton", "health": 6, "speed": 65.0,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 2, "range": 54.0, "cooldown": 1.4, "hit_delay": 0.45, "duration": 1.0, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 3, "range": 56.0, "cooldown": 3.2, "hit_delay": 0.58, "duration": 1.2, "mode": "front", "weight": 1.0},
			{"id": &"attack3", "animation": &"attack3", "damage": 1, "range": 86.0, "cooldown": 2.6, "hit_delay": 0.46, "duration": 1.0, "mode": "front_range", "weight": 1.0},
		],
	},
	&"necromancer": {
		"display_name": "Necromancer", "health": 35, "speed": 60.0, "boss": true,
		"attacks": [
			{"id": &"attack1", "animation": &"attack1", "damage": 2, "range": 50.0, "cooldown": 1.3, "hit_delay": 0.4, "duration": 0.9, "mode": "front", "weight": 3.0},
			{"id": &"attack2", "animation": &"attack2", "damage": 5, "range": 70.0, "cooldown": 30.0, "hit_delay": 0.5, "duration": 1.8, "mode": "circle", "weight": 0.8},
			{"id": &"attack3", "animation": &"attack3", "damage": 2, "range": 80.0, "cooldown": 7.0, "hit_delay": 1.0, "duration": 2.0, "mode": "circle", "weight": 0.7},
		],
	},
}

@export_category("Identity and Animations")
@export var enemy_profile: StringName = &""
@export var enemy_display_name: String = "Host Slime"
@export var attack_animation: StringName = &"attack1"
@export var hurt_animation: StringName = &""
@export var death_animation: StringName = &""

@export_category("Movement and Health")
@export var max_health: int = 6
@export var hurt_duration: float = 0.16

# The player_hitbox and enemy_hitbox shapes are stored in this separate LAN
# scene. The host queries them only at the attack's contact frame.
@export var detection_range: float = 260.0
@export var chase_speed: float = 65.0
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.35
@export var attack_hit_delay: float = 0.52
@export var attack_duration: float = 1.20
@export var attack_options: Array[Dictionary] = []

@onready var animated_sprite := _find_animated_sprite()
@onready var health_bar := get_node_or_null(^"health_bar") as ProgressBar
@onready var health_label := get_node_or_null(^"health_label") as Label
@onready var status_label := get_node_or_null(^"status_label") as Label
@onready var collision_shape := _find_body_collision_shape()
@onready var enemy_hitbox := _find_primary_hitbox()
@onready var enemy_hitbox_collision_shape := _find_hitbox_collision_shape(enemy_hitbox)
@onready var attack_pivot := get_node_or_null(^"attack_pivot") as Node2D

# Health and its revision are host-owned. A higher revision always wins over an
# older network packet, so a late packet cannot revive a defeated slime.
var health: int = 0
var state_revision: int = 0
var is_defeated: bool = false
var hurt_flash_time_left: float = 0.0

# Mage debuffs are also host-owned. Tokens refresh an existing freeze or burn
# instead of leaving old timer coroutines running after a spell is recast.
var is_network_frozen: bool = false
var is_network_burning: bool = false
var freeze_token: int = 0
var burn_token: int = 0
var debuff_revision: int = 0

# The host uses this token to cancel an old queued hit when the slime dies or a
# newer attack has begun. Clients use it only to keep attack visuals in order.
var attack_token: int = 0
var is_host_attacking: bool = false
var next_attack_time: float = 0.0
var next_attack_time_by_id: Dictionary = {}
var active_attack_config: Dictionary = {}
var is_host_dashing: bool = false
var dash_direction := Vector2.ZERO
var dash_end_time: float = 0.0
var next_dash_damage_time_by_peer: Dictionary = {}
var facing_direction: int = 1
var last_movement_state: bool = false
var home_position := Vector2.ZERO
var hitbox_base_scale := Vector2.ONE
var attack_pivot_base_scale := Vector2.ONE
var profile_is_boss: bool = false
var necromancer_wave_index: int = 0
var necromancer_is_shielded: bool = false
var necromancer_summon_token: int = 0
var active_summon_paths: Array[NodePath] = []


func _ready() -> void:
	_apply_profile()
	# The LAN controller finds every shared enemy through this group. Each scene
	# stays at the same node path on both computers, which keeps its RPC calls safe.
	add_to_group(&"lan_enemy")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_configure_lan_collision_layers()
	home_position = global_position
	health = max_health
	if attack_pivot != null:
		attack_pivot_base_scale = attack_pivot.scale
	if enemy_hitbox != null:
		hitbox_base_scale = enemy_hitbox.scale
	_prepare_one_shot_animations()
	_sync_enemy_hitbox()
	_refresh_visuals()
	_update_visuals(false)


# This stable interface lets the controller reject dead or unrelated collision
# bodies before it applies any host-authoritative attack damage.
func is_lan_enemy_alive() -> bool:
	return not is_defeated and is_inside_tree()


# These read-only helpers let the LAN dungeon draw its boss bar without ever
# giving a client permission to modify the Necromancer's health.
func get_lan_health() -> int:
	return health


func get_lan_max_health() -> int:
	return max_health


func is_lan_boss() -> bool:
	return profile_is_boss


# A LAN wrapper usually sets just enemy_profile. The table above fills in its
# original health, speed, damage, cooldowns, and animation names at runtime.
func _apply_profile() -> void:
	if enemy_profile.is_empty():
		if attack_options.is_empty():
			attack_options.append({
				"id": &"attack1",
				"animation": attack_animation,
				"damage": attack_damage,
				"range": 48.0,
				"cooldown": attack_cooldown,
				"hit_delay": attack_hit_delay,
				"duration": attack_duration,
				"mode": "front",
				"weight": 1.0,
			})
		return

	var profile_value: Variant = PROFILES.get(enemy_profile, {})
	if not (profile_value is Dictionary):
		push_error("Unknown LAN enemy profile: %s" % enemy_profile)
		return

	var profile: Dictionary = profile_value
	enemy_display_name = str(profile.get("display_name", enemy_display_name))
	max_health = maxi(1, int(profile.get("health", max_health)))
	chase_speed = maxf(0.0, float(profile.get("speed", chase_speed)))
	detection_range = maxf(0.0, float(profile.get("detection", detection_range)))
	hurt_animation = &"hurt"
	death_animation = &"death"
	profile_is_boss = bool(profile.get("boss", false))
	attack_options.clear()

	var attacks_value: Variant = profile.get("attacks", [])
	if attacks_value is Array:
		for raw_attack: Variant in attacks_value:
			if raw_attack is Dictionary:
				var attack_config: Dictionary = raw_attack
				attack_options.append(attack_config)

	if not attack_options.is_empty():
		attack_animation = StringName(attack_options[0].get("animation", attack_animation))


# Normal scenes use several node-name styles. This makes the LAN script work
# with the existing art scenes without changing a single-player scene.
func _find_animated_sprite() -> AnimatedSprite2D:
	var named_sprite: AnimatedSprite2D = get_node_or_null(^"animated_sprite") as AnimatedSprite2D
	if named_sprite == null:
		named_sprite = get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
	return named_sprite


func _find_body_collision_shape() -> CollisionShape2D:
	var named_shape: CollisionShape2D = get_node_or_null(^"collision_shape") as CollisionShape2D
	if named_shape == null:
		named_shape = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	return named_shape


func _find_primary_hitbox() -> Area2D:
	var direct_hitbox: Area2D = get_node_or_null(^"enemy_hitbox") as Area2D
	if direct_hitbox != null:
		return direct_hitbox
	return get_node_or_null(^"attack_pivot/attack_hitbox") as Area2D


func _find_hitbox_collision_shape(hitbox: Area2D) -> CollisionShape2D:
	if hitbox == null:
		return null
	var lower_shape: CollisionShape2D = hitbox.get_node_or_null(^"collision_shape") as CollisionShape2D
	if lower_shape != null:
		return lower_shape
	return hitbox.get_node_or_null(^"CollisionShape2D") as CollisionShape2D


# The reused normal scenes retain these connections. LAN detection is measured
# directly by the host in _physics_process, so the old callbacks intentionally
# do nothing instead of starting a second local AI loop.
func _on_detection_area_body_entered(_body: Node2D) -> void:
	pass


func _on_detection_area_body_exited(_body: Node2D) -> void:
	pass


# Normal enemies were built for the old local player layer. The LAN controller
# uses layer 2 for players and layer 4 for damageable enemies, so normalize it.
func _configure_lan_collision_layers() -> void:
	collision_layer = 4
	collision_mask = 1
	for child: Node in find_children("*", "Area2D", true, false):
		var area: Area2D = child as Area2D
		if area == null:
			continue
		if area.name == &"detection_area":
			area.monitoring = false
			continue
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitoring = true


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

	# A shielded Necromancer cannot move or attack until every summoned skeleton
	# from its current wave has been defeated.
	if profile_is_boss and necromancer_is_shielded:
		velocity = Vector2.ZERO
		if _are_necromancer_summons_defeated():
			_set_necromancer_shield.rpc(false)
		_update_visuals(false)
		_send_host_state(false)
		return

	if profile_is_boss:
		var next_wave: int = _get_necromancer_wave_to_summon()
		if next_wave >= 0:
			_begin_necromancer_summon(next_wave)
			return

	# Freeze stops this host-controlled enemy immediately. Burn may still tick
	# while frozen, but it never allows the enemy to chase or deal damage.
	if is_network_frozen:
		velocity = Vector2.ZERO
		_update_visuals(false)
		_send_host_state(false)
		return

	if is_host_attacking:
		if is_host_dashing:
			_simulate_host_dash()
		else:
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

	var attack_config: Dictionary = _choose_host_attack(target)
	if not attack_config.is_empty():
		velocity = Vector2.ZERO
		_update_visuals(false)
		_send_host_state(false)
		_start_host_attack(target.get_multiplayer_authority(), attack_config)
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


# Chooses from every ready attack that can reach the nearest target. Only the
# host makes this random choice; the selected animation is sent to all clients.
func _choose_host_attack(target: CharacterBody2D) -> Dictionary:
	if target == null:
		return {}

	var now: float = Time.get_ticks_msec() / 1000.0
	var available: Array[Dictionary] = []
	var total_weight: float = 0.0
	for option: Dictionary in attack_options:
		var attack_id: StringName = StringName(option.get("id", &"attack1"))
		if now < float(next_attack_time_by_id.get(attack_id, 0.0)):
			continue
		if not _is_attack_target_in_range(target, option):
			continue
		available.append(option)
		total_weight += maxf(0.01, float(option.get("weight", 1.0)))

	if available.is_empty():
		return {}

	var roll: float = randf() * total_weight
	for option: Dictionary in available:
		roll -= maxf(0.01, float(option.get("weight", 1.0)))
		if roll <= 0.0:
			return option
	return available.back()


func _is_attack_target_in_range(target: CharacterBody2D, config: Dictionary) -> bool:
	if target == null:
		return false

	var mode: String = str(config.get("mode", "front"))
	var attack_range: float = maxf(0.0, float(config.get("range", 0.0)))
	var in_front: bool = (target.global_position.x - global_position.x) * facing_direction >= 0.0
	var close_enough: bool = global_position.distance_to(target.global_position) <= attack_range
	if mode == "circle" or mode == "ranged" or mode == "dash":
		return close_enough
	if mode == "front_range":
		return in_front and close_enough
	if enemy_hitbox != null:
		_sync_enemy_hitbox()
		return enemy_hitbox.overlaps_body(target)
	return in_front and close_enough


# Starts one server-approved attack. The real hit is delayed to match the
# chosen animation, and all damage is rechecked at the later contact frame.
func _start_host_attack(target_peer_id: int, config: Dictionary) -> void:
	if is_host_attacking or is_defeated:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	var attack_id: StringName = StringName(config.get("id", &"attack1"))
	if now < float(next_attack_time_by_id.get(attack_id, 0.0)):
		return

	attack_token += 1
	var token: int = attack_token
	is_host_attacking = true
	active_attack_config = config.duplicate(true)
	next_attack_time = now + maxf(0.0, float(config.get("cooldown", attack_cooldown)))
	next_attack_time_by_id[attack_id] = next_attack_time
	velocity = Vector2.ZERO
	if str(config.get("mode", "front")) == "dash":
		var target: CharacterBody2D = _get_alive_player(target_peer_id)
		dash_direction = (target.global_position - global_position).normalized() if target != null else Vector2(facing_direction, 0.0)
		if dash_direction.is_zero_approx():
			dash_direction = Vector2(facing_direction, 0.0)
		is_host_dashing = true
		dash_end_time = now + maxf(0.1, float(config.get("duration", attack_duration)))
		next_dash_damage_time_by_peer.clear()

	# Reliable messages keep the attack animation synchronized on both screens.
	var animation_name: StringName = StringName(config.get("animation", attack_animation))
	start_host_attack_visual.rpc(token, facing_direction, animation_name)
	if not is_host_dashing:
		_resolve_host_attack_after_delay(target_peer_id, token, active_attack_config)
	_finish_host_attack_after_delay(token, active_attack_config)


# The host checks the live target a second time after the visual wind-up. This
# is why an attack does not damage a Knight who escaped before the impact.
func _resolve_host_attack_after_delay(target_peer_id: int, token: int, config: Dictionary) -> void:
	var hit_count: int = maxi(1, int(config.get("hits", 1)))
	for hit_index: int in range(hit_count):
		var wait_time: float = maxf(0.0, float(config.get("hit_delay", attack_hit_delay))) if hit_index == 0 else maxf(0.0, float(config.get("hit_interval", 0.2)))
		await get_tree().create_timer(wait_time).timeout

		if not multiplayer.is_server() or is_defeated or not is_host_attacking or token != attack_token:
			return
		_resolve_configured_attack(target_peer_id, config)


func _resolve_configured_attack(target_peer_id: int, config: Dictionary) -> void:
	var arena: Node = get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return

	var mode: String = str(config.get("mode", "front"))
	var damage: int = maxi(0, int(config.get("damage", attack_damage)))
	var stun_duration: float = maxf(0.0, float(config.get("stun", 0.0)))
	if mode == "circle":
		var players_value: Variant = arena.call(&"get_alive_players_in_radius", global_position, float(config.get("range", 0.0)))
		if players_value is Array:
			for raw_player: Variant in players_value:
				var player: CharacterBody2D = raw_player as CharacterBody2D
				if player == null:
					continue
				var peer_id: int = player.get_multiplayer_authority()
				if damage > 0:
					arena.call(&"damage_player_on_server", peer_id, damage)
				if stun_duration > 0.0:
					arena.call(&"stun_player_on_server", peer_id, stun_duration)
		return

	var target: CharacterBody2D = _get_alive_player(target_peer_id)
	if target == null or not _is_attack_target_in_range(target, config):
		return
	if mode == "ranged":
		var flight_direction: Vector2 = (target.global_position - global_position).normalized()
		if flight_direction.is_zero_approx():
			flight_direction = Vector2(facing_direction, 0.0)
		arena.call(
			&"spawn_network_skeleton_arrow_on_server",
			global_position,
			flight_direction,
			damage,
			float(config.get("range", 220.0))
		)
		return
	if damage > 0:
		arena.call(&"damage_player_on_server", target_peer_id, damage)
	if stun_duration > 0.0:
		arena.call(&"stun_player_on_server", target_peer_id, stun_duration)


# Finishes the non-looping attack after its full animation duration.
func _finish_host_attack_after_delay(token: int, config: Dictionary) -> void:
	await get_tree().create_timer(maxf(0.1, float(config.get("duration", attack_duration)))).timeout

	if token != attack_token:
		return

	is_host_attacking = false
	is_host_dashing = false
	active_attack_config.clear()
	_finish_host_attack_visual.rpc(token)


# The Werewolf's second attack moves its body on the host while repeatedly
# checking nearby players. Player damage protection still prevents frame spam.
func _simulate_host_dash() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now >= dash_end_time:
		is_host_dashing = false
		velocity = Vector2.ZERO
		_send_host_state(false)
		return

	var dash_speed: float = maxf(0.0, float(active_attack_config.get("dash_speed", 0.0)))
	velocity = dash_direction * dash_speed
	move_and_slide()
	_send_host_state(true)

	var arena: Node = get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return
	var radius: float = maxf(0.0, float(active_attack_config.get("dash_radius", 0.0)))
	var players_value: Variant = arena.call(&"get_alive_players_in_radius", global_position, radius)
	if not (players_value is Array):
		return

	var tick_seconds: float = maxf(0.1, float(active_attack_config.get("dash_tick", 0.35)))
	var damage: int = maxi(0, int(active_attack_config.get("damage", 1)))
	for raw_player: Variant in players_value:
		var player: CharacterBody2D = raw_player as CharacterBody2D
		if player == null:
			continue
		var peer_id: int = player.get_multiplayer_authority()
		if now < float(next_dash_damage_time_by_peer.get(peer_id, 0.0)):
			continue
		next_dash_damage_time_by_peer[peer_id] = now + tick_seconds
		if damage > 0:
			arena.call(&"damage_player_on_server", peer_id, damage)


# The Necromancer uses the same replicated health and attack system as normal
# enemies, then adds three shielded summon waves between its attacks.
func _get_necromancer_wave_to_summon() -> int:
	if not profile_is_boss or necromancer_is_shielded or is_host_attacking:
		return -1
	match necromancer_wave_index:
		0:
			return 0 if health <= int(ceil(float(max_health) * 0.75)) else -1
		1:
			return 1 if health <= int(ceil(float(max_health) * 0.50)) else -1
		2:
			return 2 if health <= int(ceil(float(max_health) * 0.25)) else -1
		_:
			return -1


func _get_necromancer_wave_profiles(wave_index: int) -> PackedStringArray:
	match wave_index:
		0:
			return PackedStringArray(["skeleton", "skeleton", "skeleton_archer"])
		1:
			return PackedStringArray(["armored_skeleton", "armored_skeleton", "skeleton_archer", "skeleton_archer"])
		2:
			return PackedStringArray(["greatsword_skeleton", "armored_skeleton", "armored_skeleton", "skeleton_archer", "skeleton_archer"])
		_:
			return PackedStringArray()


func _begin_necromancer_summon(wave_index: int) -> void:
	if not multiplayer.is_server() or wave_index < 0 or is_defeated:
		return

	necromancer_summon_token += 1
	var summon_token: int = necromancer_summon_token
	attack_token += 1
	var visual_token: int = attack_token
	is_host_attacking = true
	velocity = Vector2.ZERO
	_set_necromancer_shield.rpc(true)
	var summon_animation: StringName = &"summon" if wave_index == 0 else &"summon2"
	start_host_attack_visual.rpc(visual_token, facing_direction, summon_animation)

	await get_tree().create_timer(1.5).timeout
	if not multiplayer.is_server() or is_defeated or summon_token != necromancer_summon_token:
		return

	var arena: Node = get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		_set_necromancer_shield.rpc(false)
		is_host_attacking = false
		return

	active_summon_paths.clear()
	var profiles: PackedStringArray = _get_necromancer_wave_profiles(wave_index)
	for spawn_index: int in range(profiles.size()):
		var angle: float = TAU * float(spawn_index) / float(maxi(1, profiles.size()))
		var spawn_position: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * 48.0
		arena.call(&"spawn_lan_summon_effect_on_server", spawn_position)
		var spawned_value: Variant = arena.call(&"spawn_lan_enemy_on_server", StringName(profiles[spawn_index]), spawn_position)
		var spawned_enemy: Node2D = spawned_value as Node2D
		if spawned_enemy != null:
			active_summon_paths.append(spawned_enemy.get_path())

	necromancer_wave_index = wave_index + 1
	is_host_attacking = false
	_finish_host_attack_visual.rpc(visual_token)
	if active_summon_paths.is_empty():
		_set_necromancer_shield.rpc(false)


func _are_necromancer_summons_defeated() -> bool:
	if active_summon_paths.is_empty():
		return false
	for summon_path: NodePath in active_summon_paths:
		var summon: Node = get_node_or_null(summon_path)
		if summon != null and summon.has_method(&"is_lan_enemy_alive"):
			var alive_value: Variant = summon.call(&"is_lan_enemy_alive")
			if alive_value is bool and bool(alive_value):
				return false
	return true


@rpc("authority", "call_local", "reliable")
func _set_necromancer_shield(enabled: bool) -> void:
	necromancer_is_shielded = enabled
	if not enabled:
		active_summon_paths.clear()
	_refresh_visuals()


# Freeze needs to cancel an animation that may already be halfway through.
# Passing the new token makes an older delayed finish RPC harmless on clients.
@rpc("authority", "call_local", "reliable")
func cancel_host_attack_visual(cancel_token: int) -> void:
	if is_defeated:
		return

	attack_token = maxi(attack_token, cancel_token)
	is_host_attacking = false
	is_host_dashing = false
	active_attack_config.clear()
	velocity = Vector2.ZERO
	_update_visuals(false)


# This shared state only starts the animation. It never decides damage.
@rpc("authority", "call_local", "reliable")
func start_host_attack_visual(token: int, network_facing: int, animation_name: StringName) -> void:
	if is_defeated or token < attack_token:
		return

	attack_token = token
	is_host_attacking = true
	facing_direction = 1 if network_facing >= 0 else -1
	_sync_enemy_hitbox()
	velocity = Vector2.ZERO

	if animated_sprite != null:
		animated_sprite.flip_h = facing_direction < 0
		if _has_animation(animation_name):
			animated_sprite.play(_find_animation_name(animation_name))


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


# The LAN root already validated the player's attack before it calls this.
# This function changes health only on the host; a client cannot call it to
# invent damage or bypass the Area2D contact check.
func take_server_hit(damage: int) -> void:
	if not multiplayer.is_server() or is_defeated or necromancer_is_shielded or damage <= 0:
		return

	var new_health: int = maxi(0, health - damage)
	var defeated: bool = new_health == 0
	state_revision += 1
	apply_state.rpc(new_health, state_revision, defeated)
	if defeated:
		_notify_host_defeat()


func _notify_host_defeat() -> void:
	if not multiplayer.is_server():
		return
	var arena: Node = get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena != null and arena.has_method(&"on_lan_enemy_defeated"):
		arena.call(&"on_lan_enemy_defeated", enemy_profile)


# A skeleton created by the graveyard or Necromancer appears through its
# existing one-shot summon animation before its host AI is allowed to move it.
func play_server_spawn_summon() -> void:
	if not multiplayer.is_server() or is_defeated or not _has_animation(&"summon"):
		return

	attack_token += 1
	var token: int = attack_token
	is_host_attacking = true
	velocity = Vector2.ZERO
	start_host_attack_visual.rpc(token, facing_direction, &"summon")
	_finish_host_attack_after_delay(token, {"duration": 0.8})


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
	is_host_dashing = false
	active_attack_config.clear()
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


# This remains useful for the older one-attack training scenes that reuse the
# same LAN contract. Profile attacks use _is_attack_target_in_range instead.
func _is_valid_host_attack_target(target: CharacterBody2D) -> bool:
	if enemy_hitbox == null or target == null:
		return false

	_sync_enemy_hitbox()
	return enemy_hitbox.overlaps_body(target)


# Late joiners receive the already-moving enemy's exact life, location, and
# current attack visual instead of seeing a fresh full-health idle enemy.
func send_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	apply_state.rpc_id(peer_id, health, state_revision, is_defeated)
	apply_network_debuff_state.rpc_id(peer_id, is_network_frozen, is_network_burning, debuff_revision)
	sync_host_state.rpc_id(peer_id, global_position, facing_direction, last_movement_state, state_revision)
	if profile_is_boss:
		_set_necromancer_shield.rpc_id(peer_id, necromancer_is_shielded)

	if is_host_attacking and not is_defeated:
		var active_animation: StringName = StringName(active_attack_config.get("animation", attack_animation))
		start_host_attack_visual.rpc_id(peer_id, attack_token, facing_direction, active_animation)


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
		is_host_dashing = false
		active_attack_config.clear()
		necromancer_is_shielded = false
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


# The root calls this only when it begins a fresh hosted LAN session. The enemy
# stays at one stable scene path rather than being freed and re-instanced.
func reset_for_network_session() -> void:
	if not multiplayer.is_server():
		return

	attack_token += 1
	is_host_attacking = false
	is_host_dashing = false
	active_attack_config.clear()
	next_attack_time = 0.0
	next_attack_time_by_id.clear()
	next_dash_damage_time_by_peer.clear()
	necromancer_wave_index = 0
	necromancer_summon_token += 1
	active_summon_paths.clear()
	_set_necromancer_shield.rpc(false)
	velocity = Vector2.ZERO
	facing_direction = 1
	_sync_enemy_hitbox()
	last_movement_state = false
	global_position = home_position
	state_revision += 1
	_clear_server_debuffs()

	apply_state.rpc(max_health, state_revision, false)
	_send_host_state(false)



# Mirrors forward hitboxes without moving the enemy's body collider.
func _sync_enemy_hitbox() -> void:
	if attack_pivot != null:
		attack_pivot.scale = Vector2(
			absf(attack_pivot_base_scale.x) * float(facing_direction),
			attack_pivot_base_scale.y
		)
	# Hitboxes inside attack_pivot are already mirrored by that parent. Scaling
	# them again would flip twice and make attacks land on the wrong side.
	var hitbox_is_under_pivot: bool = attack_pivot != null and enemy_hitbox != null and attack_pivot.is_ancestor_of(enemy_hitbox)
	if enemy_hitbox != null and not hitbox_is_under_pivot:
		enemy_hitbox.scale = Vector2(
			absf(hitbox_base_scale.x) * float(facing_direction),
			hitbox_base_scale.y
		)


# The body is what the Knight's player_hitbox detects. The enemy's own
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
		elif necromancer_is_shielded:
			status_label.text = "Shielded: defeat the summons"
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
	elif necromancer_is_shielded:
		animated_sprite.modulate = Color(0.55, 0.75, 1.0, 1.0)
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

	var one_shot_animations: Array[StringName] = [attack_animation, hurt_animation, death_animation, &"summon", &"summon2"]
	for config: Dictionary in attack_options:
		one_shot_animations.append(StringName(config.get("animation", &"")))

	for animation_name: StringName in one_shot_animations:
		if _has_animation(animation_name):
			animated_sprite.sprite_frames.set_animation_loop_mode(_find_animation_name(animation_name), SpriteFrames.LOOP_NONE)


func _has_animation(animation_name: StringName) -> bool:
	return _find_animation_name(animation_name) != &""


func _find_animation_name(requested_name: StringName) -> StringName:
	if animated_sprite == null or animated_sprite.sprite_frames == null or requested_name.is_empty():
		return &""

	var requested_lower: String = String(requested_name).to_lower()
	for available_name: StringName in animated_sprite.sprite_frames.get_animation_names():
		if String(available_name).to_lower() == requested_lower:
			return available_name
	return &""

class_name Combatant
extends CharacterBody2D

signal died
signal health_changed(current_health: int, maximum_health: int)

# Shared top-down combat for the player and every melee enemy.
# It supports either a modern attack_pivot/attack_hitbox setup or the existing
# player_hitbox/enemy_hitbox nodes in this project.

@export_category("Attack Hitbox")
@export_range(0.0, 5.0, 0.01) var attack_hit_delay := 0.18
@export var legacy_hitbox_offset := Vector2(24.0, 0.0)

@export_category("Damage Protection")
# This is separate from the hurt animation length. It stops several enemies
# from damaging the same target on the same frame, without blocking a real combo.
@export_range(0.0, 2.0, 0.01) var damage_invulnerability_time := 0.12

const ONE_SHOT_ANIMATIONS := [
	&"attack", &"attack1", &"attack2", &"attack3",
	&"skill", &"skill1", &"skill2", &"fireball",
	&"block", &"heal", &"summon", &"summon2", &"hurt", &"death"
]

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
@onready var attack_pivot := get_node_or_null(^"attack_pivot") as Node2D
@onready var attack_hitbox := _find_attack_hitbox()

var health := 1
var facing_direction := 1
var is_attacking := false
var is_hurt := false
var is_dead := false
var is_damage_invulnerable := false
var is_frozen := false
var is_stunned := false
var is_burning := false
var is_summoning := false

var _attack_token := 0
var _damage_invulnerability_token := 0
var _freeze_token := 0
var _stun_token := 0
var _burn_token := 0
var _pivot_scale := Vector2.ONE
var _hitbox_position := Vector2.ZERO
var _hitbox_scale := Vector2.ONE
var _hitbox_has_forward_shape := false
var _normal_sprite_self_modulate := Color.WHITE
var _freeze_tint := Color(0.12, 0.22, 0.55, 1.0)
var _burn_tint := Color(1.0, 0.38, 0.06, 1.0)


func _ready() -> void:
	# FLOATING prevents platformer floor behaviour in a top-down RPG.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	set_health(get_max_health())
	set_one_shot_animations()
	_cache_attack_transforms()
	if animated_sprite != null:
		# self_modulate lets status colours layer over character-specific modulate
		# effects such as the Necromancer shield and the Priest's blue skill.
		_normal_sprite_self_modulate = animated_sprite.self_modulate

	if attack_hitbox == null:
		if requires_attack_hitbox():
			push_warning("Add an Area2D named attack_hitbox, player_hitbox, or enemy_hitbox.")
		return

	attack_hitbox.monitoring = true
	sync_attack_hitbox()


# Child scripts override these values with their exported settings.
func get_max_health() -> int:
	return 1


# Sets health safely and tells the health bar to redraw.
# Player, Priest, and future characters can all use this shared helper.
func set_health(new_health: int) -> void:
	health = clampi(new_health, 0, get_max_health())
	health_changed.emit(health, get_max_health())


func get_hurt_duration() -> float:
	return 0.3


func get_death_duration() -> float:
	return 0.8


func requires_attack_hitbox() -> bool:
	return true


func is_busy() -> bool:
	return is_dead or is_hurt or is_attacking or is_frozen or is_stunned or is_summoning


# Changes the left/right sprite direction and mirrors the forward hitbox.
func set_facing_from_x(horizontal_direction: float) -> void:
	if is_zero_approx(horizontal_direction) or is_attacking:
		return

	facing_direction = 1 if horizontal_direction > 0.0 else -1
	if animated_sprite != null:
		animated_sprite.flip_h = facing_direction < 0
	sync_attack_hitbox()


func sync_attack_hitbox() -> void:
	if attack_pivot != null:
		attack_pivot.scale = Vector2(absf(_pivot_scale.x) * facing_direction, _pivot_scale.y)
		return

	if attack_hitbox == null:
		return

	# Existing scenes already offset their CollisionShape2D forward. Mirror that
	# shape instead of adding a second offset, which caused hits behind/too far.
	if _hitbox_has_forward_shape:
		attack_hitbox.position = _hitbox_position
		attack_hitbox.scale = Vector2(absf(_hitbox_scale.x) * facing_direction, _hitbox_scale.y)
	else:
		attack_hitbox.position = _hitbox_position + Vector2(absf(legacy_hitbox_offset.x) * facing_direction, legacy_hitbox_offset.y)
		attack_hitbox.scale = _hitbox_scale


func can_hit_target(target: Node2D) -> bool:
	return attack_hitbox != null and _is_target_in_front(target) and attack_hitbox.overlaps_body(target)


# Starts one swing. The animation length is respected even when an older scene
# has a shorter cooldown value, so attacks and hurt/death animations do not cut off.
func start_melee_attack(
	animation_name: StringName,
	damage: int,
	target_group: StringName,
	attack_cooldown: float,
	hit_delay: float = -1.0
) -> void:
	var token := begin_attack(animation_name)
	if token < 0:
		return

	var attack_duration := maxf(attack_cooldown, get_animation_duration(animation_name))
	var requested_delay := attack_hit_delay if hit_delay < 0.0 else hit_delay
	var safe_hit_delay := minf(maxf(0.0, requested_delay), attack_duration)

	await wait_for_gameplay_time(safe_hit_delay).timeout
	if not is_attack_token_active(token):
		return

	deal_melee_damage(damage, target_group)
	await wait_for_gameplay_time(attack_duration - safe_hit_delay).timeout
	finish_attack(token)


func begin_attack(animation_name: StringName) -> int:
	if is_busy():
		return -1

	is_attacking = true
	_attack_token += 1
	velocity = Vector2.ZERO
	# Restart a finished one-shot animation every time a new attack begins.
	play_animation(animation_name, true)
	return _attack_token


func is_attack_token_active(token: int) -> bool:
	return token == _attack_token and is_attacking and not is_hurt and not is_dead and not is_stunned


func finish_attack(token: int) -> void:
	if token == _attack_token and not is_dead:
		is_attacking = false
		# Leave the final attack frame immediately instead of looking frozen.
		update_idle_or_walk_animation()


# Plays an appearance animation and holds the Combatant still until it ends.
# Enemy spawners use this so their normal AI cannot instantly replace summon
# with idle or walk on the next physics frame.
func play_summon_animation() -> void:
	if is_dead or is_busy():
		return

	var summon_duration: float = get_animation_duration(&"summon")
	if summon_duration <= 0.0:
		return

	is_summoning = true
	velocity = Vector2.ZERO
	play_animation(&"summon", true)
	await wait_for_gameplay_time(summon_duration).timeout

	if is_dead or not is_summoning:
		return

	is_summoning = false
	update_idle_or_walk_animation()


# Only applies damage during the chosen contact frame and inside the front hitbox.
func deal_melee_damage(damage: int, target_group: StringName) -> void:
	if attack_hitbox == null or damage <= 0:
		return

	for body in attack_hitbox.get_overlapping_bodies():
		if body is Node2D and body.is_in_group(target_group) and _is_target_in_front(body) and body.has_method(&"take_damage"):
			body.call(&"take_damage", damage)


func take_damage(damage: int) -> void:
	# Hurt is a visual/action state. This brief timer is the actual protection
	# against several attacks landing on the very same instant.
	if is_dead or is_damage_invulnerable or damage <= 0:
		return
	# A real hit interrupts the spawn animation so hurt/death remains visible.
	is_summoning = false

	set_health(health - damage)
	if health == 0:
		die()
		return

	_start_damage_invulnerability()

	# A later combo hit can damage a target during its hurt animation, but it does
	# not restart that animation or interrupt the target a second time.
	if is_hurt:
		return

	# A hit cancels the old attack token, so an interrupted swing cannot damage later.
	_attack_token += 1
	is_attacking = false
	is_hurt = true
	velocity = Vector2.ZERO
	play_animation(&"hurt", true)
	await wait_for_gameplay_time(maxf(get_hurt_duration(), get_animation_duration(&"hurt"))).timeout
	if not is_dead:
		is_hurt = false
		if not is_frozen and not is_stunned:
			update_idle_or_walk_animation()


func _start_damage_invulnerability() -> void:
	_damage_invulnerability_token += 1
	var token := _damage_invulnerability_token
	is_damage_invulnerable = true
	await wait_for_gameplay_time(damage_invulnerability_time).timeout
	if token == _damage_invulnerability_token:
		is_damage_invulnerable = false


# Stops movement and attacks for the duration. Reapplying freeze refreshes it.
func apply_freeze(
	duration: float,
	tint: Color = Color(0.12, 0.22, 0.55, 1.0)
) -> void:
	if is_dead or duration <= 0.0:
		return

	_freeze_token += 1
	var token := _freeze_token
	_freeze_tint = tint
	is_frozen = true
	is_summoning = false

	# Cancel an in-progress delayed hit so a frozen enemy cannot strike later.
	_attack_token += 1
	is_attacking = false
	velocity = Vector2.ZERO
	_refresh_status_tint()

	await wait_for_gameplay_time(duration).timeout
	if token != _freeze_token or is_dead:
		return

	is_frozen = false
	_refresh_status_tint()
	if not is_hurt and not is_stunned:
		update_idle_or_walk_animation()


# Stops movement and all actions for the duration. Reapplying stun refreshes it.
func apply_stun(duration: float) -> void:
	if is_dead or duration <= 0.0:
		return

	_stun_token += 1
	var token := _stun_token
	is_stunned = true
	is_summoning = false

	# Cancel a delayed swing so a stunned target cannot attack later.
	_attack_token += 1
	is_attacking = false
	velocity = Vector2.ZERO

	await wait_for_gameplay_time(duration).timeout
	if token != _stun_token or is_dead:
		return

	is_stunned = false
	if not is_hurt and not is_frozen:
		update_idle_or_walk_animation()


# Deals damage at intervals. Reapplying burn refreshes its duration rather than
# creating extra overlapping damage loops.
func apply_burn(
	duration: float,
	tick_damage := 1,
	tick_interval := 1.0,
	tint: Color = Color(1.0, 0.38, 0.06, 1.0)
) -> void:
	if is_dead or duration <= 0.0 or tick_damage <= 0 or tick_interval <= 0.0:
		return

	_burn_token += 1
	var token := _burn_token
	_burn_tint = tint
	is_burning = true
	_refresh_status_tint()

	var remaining_time := duration
	while remaining_time > 0.0:
		var wait_time := minf(tick_interval, remaining_time)
		await wait_for_gameplay_time(wait_time).timeout
		if token != _burn_token or is_dead:
			return

		remaining_time -= wait_time
		take_damage(tick_damage)
		if is_dead:
			return

	if token == _burn_token:
		is_burning = false
		_refresh_status_tint()


# Freeze colour has priority. When it ends, an active burn becomes orange again.
func _refresh_status_tint() -> void:
	if animated_sprite == null:
		return

	if is_frozen:
		animated_sprite.self_modulate = _freeze_tint
	elif is_burning:
		animated_sprite.self_modulate = _burn_tint
	else:
		animated_sprite.self_modulate = _normal_sprite_self_modulate


func die() -> void:
	if is_dead:
		return

	is_dead = true
	_attack_token += 1
	is_attacking = false
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	if attack_hitbox != null:
		attack_hitbox.set_deferred(&"monitoring", false)
	play_animation(&"death", true)
	died.emit()
	await wait_for_gameplay_time(maxf(get_death_duration(), get_animation_duration(&"death"))).timeout
	queue_free()


func update_idle_or_walk_animation() -> void:
	play_animation(&"idle" if velocity.is_zero_approx() else &"walk")


# Uses physics-time timers so combat pauses cleanly with the game.
func wait_for_gameplay_time(seconds: float) -> SceneTreeTimer:
	return get_tree().create_timer(maxf(0.0, seconds), false, true)


func get_animation_duration(animation_name: StringName) -> float:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return 0.0

	var actual_name := _find_animation_name(animation_name)
	if actual_name == &"":
		return 0.0

	var speed := animated_sprite.sprite_frames.get_animation_speed(actual_name)
	return float(animated_sprite.sprite_frames.get_frame_count(actual_name)) / speed if speed > 0.0 else 0.0


func set_one_shot_animations() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	for animation_name in ONE_SHOT_ANIMATIONS:
		var actual_name := _find_animation_name(animation_name)
		if actual_name != &"":
			# Godot 4.7 replacement for the deprecated set_animation_loop().
			animated_sprite.sprite_frames.set_animation_loop_mode(actual_name, SpriteFrames.LOOP_NONE)


func play_animation(animation_name: StringName, restart := false) -> void:
	if animated_sprite == null:
		return

	var actual_name := _find_animation_name(animation_name)
	if actual_name == &"":
		return

	if restart or animated_sprite.animation != actual_name:
		animated_sprite.play(actual_name)
		if restart:
			animated_sprite.frame = 0
			animated_sprite.frame_progress = 0.0


func _cache_attack_transforms() -> void:
	if attack_pivot != null:
		_pivot_scale = attack_pivot.scale
	if attack_hitbox != null:
		_hitbox_position = attack_hitbox.position
		_hitbox_scale = attack_hitbox.scale
		_hitbox_has_forward_shape = _has_forward_collision_shape()


func _has_forward_collision_shape() -> bool:
	if attack_hitbox == null:
		return false

	for child in attack_hitbox.get_children():
		if child is CollisionShape2D and not child.disabled and not is_zero_approx(child.position.x):
			return true
	return false


func _is_target_in_front(target: Node2D) -> bool:
	return (target.global_position.x - global_position.x) * facing_direction >= 0.0


func _find_animation_name(requested_name: StringName) -> StringName:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return &""

	var requested_lower := String(requested_name).to_lower()
	for available_name in animated_sprite.sprite_frames.get_animation_names():
		if String(available_name).to_lower() == requested_lower:
			return available_name
	return &""


func _find_attack_hitbox() -> Area2D:
	for node_path in [^"attack_pivot/attack_hitbox", ^"attack_hitbox", ^"player_hitbox", ^"enemy_hitbox"]:
		var hitbox := get_node_or_null(node_path) as Area2D
		if hitbox != null:
			return hitbox
	return null

# Restores health without going above the character's maximum health.
func restore_health(amount: int) -> void:
	if is_dead or amount <= 0:
		return

	var new_health := mini(get_max_health(), health + amount)
	if new_health == health:
		return

	health = new_health
	health_changed.emit(health, get_max_health())

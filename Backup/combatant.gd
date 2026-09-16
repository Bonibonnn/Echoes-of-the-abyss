class_name Combatant
extends CharacterBody2D

signal died

# Shared melee combat for the player and every enemy.
# Preferred node setup:
# CharacterBody2D
# ├── AnimatedSprite2D
# └── attack_pivot (Node2D)
#     └── attack_hitbox (Area2D)
#         └── CollisionShape2D
#
# Older scenes are also supported when their Area2D is named player_hitbox
# or enemy_hitbox and is a direct child of the CharacterBody2D.

@export_category("Attack Hitbox")
@export var attack_hit_delay := 0.18
@export var legacy_hitbox_offset := Vector2(24.0, 0.0)

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var attack_pivot: Node2D = get_node_or_null("attack_pivot")
@onready var attack_hitbox: Area2D = _find_attack_hitbox()

var health := 1
var facing_direction := 1
var is_attacking := false
var is_hurt := false
var is_dead := false

var _attack_token := 0
var _pivot_scale := Vector2.ONE


func _ready() -> void:
	health = get_max_health()
	set_one_shot_animations()

	if attack_pivot != null:
		_pivot_scale = attack_pivot.scale

	if not requires_attack_hitbox():
		return

	if attack_hitbox == null:
		push_warning("Add an Area2D named 'attack_hitbox' (or use player_hitbox/enemy_hitbox).")
	else:
		attack_hitbox.monitoring = true
		sync_attack_hitbox()


func get_max_health() -> int:
	return 1


func get_hurt_duration() -> float:
	return 0.3


func get_death_duration() -> float:
	return 0.8


func requires_attack_hitbox() -> bool:
	return true


func is_busy() -> bool:
	return is_dead or is_hurt or is_attacking


func set_facing_from_x(horizontal_direction: float) -> void:
	if horizontal_direction == 0.0 or is_attacking:
		return

	facing_direction = 1 if horizontal_direction > 0.0 else -1
	if animated_sprite != null:
		animated_sprite.flip_h = facing_direction < 0
	sync_attack_hitbox()


func sync_attack_hitbox() -> void:
	if attack_hitbox == null:
		return

	if attack_pivot != null:
		attack_pivot.scale = Vector2(abs(_pivot_scale.x) * facing_direction, _pivot_scale.y)
	else:
		attack_hitbox.position = Vector2(abs(legacy_hitbox_offset.x) * facing_direction, legacy_hitbox_offset.y)


func can_hit_target(target: Node2D) -> bool:
	return attack_hitbox != null and attack_hitbox.overlaps_body(target)


func start_melee_attack(
		animation_name: StringName,
		damage: int,
		target_group: StringName,
		attack_duration: float,
		hit_delay: float = -1.0
	) -> void:
	var token := begin_attack(animation_name)
	if token < 0:
		return

	var requested_hit_delay: float = attack_hit_delay if hit_delay < 0.0 else hit_delay
	var safe_hit_delay: float = minf(requested_hit_delay, attack_duration)
	await get_tree().create_timer(safe_hit_delay).timeout
	if not is_attack_token_active(token):
		return

	deal_melee_damage(damage, target_group)

	var recovery_time: float = maxf(0.0, attack_duration - safe_hit_delay)
	await get_tree().create_timer(recovery_time).timeout
	finish_attack(token)


func begin_attack(animation_name: StringName) -> int:
	if is_busy():
		return -1

	is_attacking = true
	_attack_token += 1
	velocity = Vector2.ZERO
	play_animation(animation_name)
	return _attack_token


func is_attack_token_active(token: int) -> bool:
	return token == _attack_token and is_attacking and not is_hurt and not is_dead


func finish_attack(token: int) -> void:
	if token == _attack_token and not is_dead:
		is_attacking = false


func deal_melee_damage(damage: int, target_group: StringName) -> void:
	if attack_hitbox == null:
		return

	# Damage is checked only at the contact frame and only inside the forward Area2D.
	for body in attack_hitbox.get_overlapping_bodies():
		if body.is_in_group(target_group) and body.has_method("take_damage"):
			body.take_damage(damage)


func take_damage(damage: int) -> void:
	if is_dead or is_hurt:
		return

	health -= damage
	if health <= 0:
		die()
		return

	# Being hit interrupts an attack, so the old swing cannot damage afterward.
	_attack_token += 1
	is_attacking = false
	is_hurt = true
	velocity = Vector2.ZERO
	play_animation("hurt")
	await get_tree().create_timer(get_hurt_duration()).timeout
	if not is_dead:
		is_hurt = false


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
		attack_hitbox.monitoring = false
	play_animation("death")
	died.emit()
	await get_tree().create_timer(get_death_duration()).timeout
	queue_free()


func update_idle_or_walk_animation() -> void:
	if velocity == Vector2.ZERO:
		play_animation("idle")
	else:
		play_animation("walk")


func set_one_shot_animations() -> void:
	if animated_sprite == null:
		return

	for animation_name in ["attack", "attack1", "attack2", "summon", "hurt", "death"]:
		for available_name in animated_sprite.sprite_frames.get_animation_names():
			if String(available_name).to_lower() == animation_name:
				animated_sprite.sprite_frames.set_animation_loop(available_name, false)


func play_animation(animation_name: StringName) -> void:
	if animated_sprite == null:
		return

	for available_name in animated_sprite.sprite_frames.get_animation_names():
		if String(available_name).to_lower() == String(animation_name).to_lower():
			animated_sprite.play(available_name)
			return


func _find_attack_hitbox() -> Area2D:
	for node_path in ["attack_pivot/attack_hitbox", "attack_hitbox", "player_hitbox", "enemy_hitbox"]:
		var node := get_node_or_null(node_path)
		if node is Area2D:
			return node
	return null

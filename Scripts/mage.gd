extends Combatant

# Mage player controller for Godot 4.7.
#
# Mage scene setup:
# mage (CharacterBody2D with this script)
# ├── AnimatedSprite2D
# └── CollisionShape2D
#
# Assign your separate Area2D scenes in the Inspector:
# - Freeze Area Scene: the Q area spell.
# - Fireball Scene: the E projectile spell.

@export_category("Movement")
@export var speed := 120.0

@export_category("Health")
@export var max_health := 4

@export_category("Spell Scenes")
@export var freeze_area_scene: PackedScene
@export var fireball_scene: PackedScene
@export var fireball_spawn_offset := Vector2(26.0, -4.0)

@export_category("Attack 1 - Close Freeze")
# Left-click: freezes every enemy near the Mage. The visual is inside attack1.
@export_range(1.0, 1000.0, 1.0, "suffix:px") var close_freeze_radius := 72.0
@export_range(0.1, 10.0, 0.1, "suffix:s") var close_freeze_duration := 1.5
@export_range(0.1, 5.0, 0.01) var close_freeze_cooldown := 0.8
@export_range(0.0, 5.0, 0.01) var close_freeze_release_time := 0.2

@export_category("Attack 2 - Fire Explosion")
# Right-click: explodes at the nearest enemy, damaging and burning every enemy
# inside the explosion radius.
@export var fire_explosion_damage := 2
@export_range(1.0, 1000.0, 1.0, "suffix:px") var fire_explosion_radius := 70.0
@export_range(1.0, 2000.0, 1.0, "suffix:px") var fire_explosion_target_range := 340.0
@export_range(0.1, 10.0, 0.01) var fire_explosion_cooldown := 1.25
@export_range(0.0, 5.0, 0.01) var fire_explosion_release_time := 0.3

@export_category("Skill 1 - Freeze Area")
# Q: places your Freeze Area2D on the nearest enemy and freezes enemies inside it.
@export_range(1.0, 2000.0, 1.0, "suffix:px") var freeze_area_target_range := 360.0
@export_range(0.1, 10.0, 0.1, "suffix:s") var freeze_area_duration := 2.5
@export_range(0.1, 60.0, 0.1) var freeze_area_cooldown := 5.0
@export_range(0.0, 5.0, 0.01) var freeze_area_release_time := 0.35

@export_category("Skill 2 - Fireball")
# E: plays this Mage animation, then launches a fireball forward.
# Default name is skill2; change this in the Inspector if yours is named fireball.
@export var fireball_cast_animation: StringName = &"skill2"
@export var fireball_impact_damage := 2
@export_range(0.1, 60.0, 0.1) var fireball_cooldown := 4.0
@export_range(0.0, 5.0, 0.01) var fireball_release_time := 0.25

@export_category("Burn Debuff")
# Burn deals one damage after each interval, until its duration finishes.
@export_range(0.1, 20.0, 0.1, "suffix:s") var burn_duration := 4.0
@export_range(1, 99, 1) var burn_damage_per_tick := 1
@export_range(0.1, 10.0, 0.1, "suffix:s") var burn_tick_interval := 1.0
@export var burn_orange := Color(1.0, 0.38, 0.06, 1.0)

@export_category("Freeze Debuff")
@export var freeze_dark_blue := Color(0.12, 0.22, 0.55, 1.0)

@export_category("Hurt and Death")
@export var hurt_duration := 0.3
@export var death_duration := 0.8

var close_freeze_cooldown_left := 0.0
var fire_explosion_cooldown_left := 0.0
var freeze_area_cooldown_left := 0.0
var fireball_cooldown_left := 0.0


func _ready() -> void:
	super()
	add_to_group(&"player")

	if freeze_area_scene == null:
		push_warning("Assign your Freeze Area2D scene to Freeze Area Scene.")
	if fireball_scene == null:
		push_warning("Assign your fireball Area2D scene to Fireball Scene.")


# Mage attacks use radius checks and spawned spells, not the normal melee hitbox.
func requires_attack_hitbox() -> bool:
	return false


func _input(event: InputEvent) -> void:
	if is_busy():
		return

	# Input Map: attack = left-click, attack2 = right-click, skill1 = Q, skill2 = E.
	if InputMap.has_action(&"skill1") and event.is_action_pressed(&"skill1"):
		start_freeze_area()
		return

	if InputMap.has_action(&"skill2") and event.is_action_pressed(&"skill2"):
		start_fireball()
		return

	if InputMap.has_action(&"attack2") and event.is_action_pressed(&"attack2"):
		start_fire_explosion()
		return

	if event.is_action_pressed(&"attack"):
		start_close_freeze()


func _physics_process(delta: float) -> void:
	close_freeze_cooldown_left = maxf(0.0, close_freeze_cooldown_left - delta)
	fire_explosion_cooldown_left = maxf(0.0, fire_explosion_cooldown_left - delta)
	freeze_area_cooldown_left = maxf(0.0, freeze_area_cooldown_left - delta)
	fireball_cooldown_left = maxf(0.0, fireball_cooldown_left - delta)

	if is_dead:
		return

	if is_busy():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	set_facing_from_x(direction.x)
	velocity = direction * speed
	move_and_slide()
	update_idle_or_walk_animation()


# Attack 1: freeze all nearby enemies. It intentionally deals no direct damage.
func start_close_freeze() -> void:
	if close_freeze_cooldown_left > 0.0:
		return

	var token := begin_attack(&"attack1")
	if token < 0:
		return

	close_freeze_cooldown_left = close_freeze_cooldown
	var cast_duration := maxf(get_animation_duration(&"attack1"), close_freeze_release_time)
	var release_time := clampf(close_freeze_release_time, 0.0, cast_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	freeze_enemies_in_radius(global_position, close_freeze_radius, close_freeze_duration)

	await wait_for_gameplay_time(cast_duration - release_time).timeout
	finish_attack(token)


# Attack 2: damages and burns all enemies around the chosen target's position.
func start_fire_explosion() -> void:
	if fire_explosion_cooldown_left > 0.0:
		return

	var target := find_nearest_enemy_in_range(fire_explosion_target_range)
	if target == null:
		return

	var token := begin_attack(&"attack2")
	if token < 0:
		return

	fire_explosion_cooldown_left = fire_explosion_cooldown
	var cast_duration := maxf(get_animation_duration(&"attack2"), fire_explosion_release_time)
	var release_time := clampf(fire_explosion_release_time, 0.0, cast_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	if is_instance_valid(target) and is_valid_enemy_target(target, fire_explosion_target_range):
		apply_fire_explosion(target.global_position)

	await wait_for_gameplay_time(cast_duration - release_time).timeout
	finish_attack(token)


# Q: puts the separate Freeze Area2D exactly on the selected enemy.
func start_freeze_area() -> void:
	if freeze_area_cooldown_left > 0.0 or freeze_area_scene == null:
		return

	var target := find_nearest_enemy_in_range(freeze_area_target_range)
	if target == null:
		return

	var token := begin_attack(&"skill1")
	if token < 0:
		return

	freeze_area_cooldown_left = freeze_area_cooldown
	var cast_duration := maxf(get_animation_duration(&"skill1"), freeze_area_release_time)
	var release_time := clampf(freeze_area_release_time, 0.0, cast_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	if is_instance_valid(target) and is_valid_enemy_target(target, freeze_area_target_range):
		spawn_freeze_area(target.global_position)

	await wait_for_gameplay_time(cast_duration - release_time).timeout
	finish_attack(token)


# E: plays the Mage's fireball cast animation, then fires the Area2D projectile.
func start_fireball() -> void:
	if fireball_cooldown_left > 0.0 or fireball_scene == null:
		return

	var token := begin_attack(fireball_cast_animation)
	if token < 0:
		return

	fireball_cooldown_left = fireball_cooldown
	var cast_duration := maxf(get_animation_duration(fireball_cast_animation), fireball_release_time)
	var release_time := clampf(fireball_release_time, 0.0, cast_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	spawn_fireball()

	await wait_for_gameplay_time(cast_duration - release_time).timeout
	finish_attack(token)


# Creates the moving fireball after its cast animation reaches the release frame.
func spawn_fireball() -> void:
	var fireball := fireball_scene.instantiate() as Area2D
	if fireball == null:
		push_error("Fireball Scene must have an Area2D as its root node.")
		return
	if not fireball.has_method(&"launch"):
		push_error("Attach Scripts/mage_fireball.gd to the root Area2D of the fireball scene.")
		fireball.queue_free()
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		fireball.queue_free()
		return

	scene_root.add_child(fireball)
	fireball.global_position = global_position + Vector2(
		fireball_spawn_offset.x * facing_direction,
		fireball_spawn_offset.y
	)
	fireball.call(
		&"launch",
		Vector2(facing_direction, 0.0),
		fireball_impact_damage,
		&"enemy",
		self,
		burn_duration,
		burn_damage_per_tick,
		burn_tick_interval,
		burn_orange
	)


# Q's scene uses its own Area2D overlap to freeze every enemy within its shape.
func spawn_freeze_area(spawn_position: Vector2) -> void:
	var freeze_area := freeze_area_scene.instantiate() as Area2D
	if freeze_area == null:
		push_error("Freeze Area Scene must have an Area2D as its root node.")
		return
	if not freeze_area.has_method(&"activate"):
		push_error("Attach Scripts/freeze_area.gd to the root Area2D of the Freeze Area scene.")
		freeze_area.queue_free()
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		freeze_area.queue_free()
		return

	scene_root.add_child(freeze_area)
	freeze_area.global_position = spawn_position
	freeze_area.call(&"activate", freeze_area_duration, &"enemy", freeze_dark_blue)


func freeze_enemies_in_radius(center: Vector2, radius: float, duration: float) -> void:
	var radius_squared := radius * radius

	for body in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := body as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or not enemy.has_method(&"apply_freeze"):
			continue

		if center.distance_squared_to(enemy.global_position) <= radius_squared:
			enemy.call(&"apply_freeze", duration, freeze_dark_blue)


func apply_fire_explosion(center: Vector2) -> void:
	var radius_squared := fire_explosion_radius * fire_explosion_radius

	for body in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := body as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or not enemy.has_method(&"take_damage"):
			continue

		if center.distance_squared_to(enemy.global_position) <= radius_squared:
			enemy.call(&"take_damage", fire_explosion_damage)
			if enemy.has_method(&"apply_burn"):
				enemy.call(
					&"apply_burn",
					burn_duration,
					burn_damage_per_tick,
					burn_tick_interval,
					burn_orange
				)


func find_nearest_enemy_in_range(target_range: float) -> Node2D:
	var closest_enemy: Node2D
	var closest_distance_squared := target_range * target_range

	for body in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := body as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or not enemy.has_method(&"take_damage"):
			continue

		var distance_squared := global_position.distance_squared_to(enemy.global_position)
		if distance_squared <= closest_distance_squared:
			closest_enemy = enemy
			closest_distance_squared = distance_squared

	return closest_enemy


func is_valid_enemy_target(target: Node2D, target_range: float) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.has_method(&"take_damage")
		and global_position.distance_squared_to(target.global_position) <= target_range * target_range
	)


func get_max_health() -> int:
	return max_health


func get_hurt_duration() -> float:
	return hurt_duration


func get_death_duration() -> float:
	return death_duration

extends Combatant

# Priest player controller for Godot 4.7.
#
# Priest scene setup:
# priest (CharacterBody2D with this script)
# ├── AnimatedSprite2D
# └── CollisionShape2D
#
# Drag your two separate Area2D scenes into the Inspector slots:
# - auraplosion (range).tscn -> Auraplosion Scene (Attack 2 visual)
# - heal.tscn                 -> Heal Scene (Q visual)

@export_category("Movement")
@export var speed := 115.0

@export_category("Health")
@export var max_health := 6

@export_category("Animated Effect Scenes")
# This animated Area2D is placed directly on the selected enemy for Attack 2.
@export var auraplosion_scene: PackedScene
# This animated Area2D is placed on the Priest after Q restores health.
@export var heal_scene: PackedScene

@export_category("Attack 1 - Close Auraplosion")
# The auraplosion visual is already inside the Priest's attack1 animation.
# This radius decides which nearby enemies receive damage at the hit moment.
@export var close_attack_damage := 2
@export_range(1.0, 1000.0, 1.0, "suffix:px") var close_attack_radius := 70.0
@export_range(0.1, 5.0, 0.01) var close_attack_cooldown := 0.7
@export_range(0.0, 5.0, 0.01) var close_attack_release_time := 0.2

@export_category("Attack 2 - Ranged Auraplosion")
# Attack 2 selects the nearest enemy in this range, then places the animated
# auraplosion exactly at that enemy's current position. It damages one enemy.
@export var ranged_attack_damage := 3
@export_range(1.0, 2000.0, 1.0, "suffix:px") var ranged_target_range := 360.0
@export_range(0.1, 10.0, 0.01) var ranged_attack_cooldown := 1.25
@export_range(0.0, 5.0, 0.01) var ranged_attack_release_time := 0.3

@export_category("Skill 1 - Heal")
# Q: plays the Priest animation named "heal", then restores health.
@export var heal_amount := 3
@export_range(0.1, 60.0, 0.1) var heal_cooldown := 5.0
@export_range(0.0, 5.0, 0.01) var heal_release_time := 0.45

@export_category("Skill 2 - Invulnerability")
# E: has no animation. The sprite is blue while damage is ignored.
@export_range(0.1, 10.0, 0.1) var invulnerability_duration := 2.0
@export_range(0.1, 60.0, 0.1) var invulnerability_cooldown := 8.0
@export var invulnerability_blue := Color(0.35, 0.7, 1.0, 1.0)

@export_category("Hurt and Death")
@export var hurt_duration := 0.3
@export var death_duration := 0.8

var close_attack_cooldown_left := 0.0
var ranged_attack_cooldown_left := 0.0
var heal_cooldown_left := 0.0
var invulnerability_cooldown_left := 0.0
var invulnerability_time_left := 0.0
var is_invulnerable := false
var _normal_sprite_modulate := Color.WHITE


func _ready() -> void:
	super()
	add_to_group(&"player")

	# Keep the original colour so E can restore it when invulnerability ends.
	if animated_sprite != null:
		_normal_sprite_modulate = animated_sprite.modulate

	if auraplosion_scene == null:
		push_warning("Assign auraplosion (range).tscn to Auraplosion Scene.")
	if heal_scene == null:
		push_warning("Assign heal.tscn to Heal Scene.")


# All Priest damage is handled by this script, not a forward melee hitbox.
func requires_attack_hitbox() -> bool:
	return false


func _input(event: InputEvent) -> void:
	if is_busy():
		return

	# Input Map: attack = left-click, attack2 = right-click, skill1 = Q, skill2 = E.
	if InputMap.has_action(&"skill1") and event.is_action_pressed(&"skill1"):
		start_heal()
		return

	if InputMap.has_action(&"skill2") and event.is_action_pressed(&"skill2"):
		start_invulnerability()
		return

	if InputMap.has_action(&"attack2") and event.is_action_pressed(&"attack2"):
		start_ranged_auraplosion()
		return

	if event.is_action_pressed(&"attack"):
		start_close_auraplosion()


func _physics_process(delta: float) -> void:
	# Cooldowns continue counting down while the Priest moves or uses an ability.
	close_attack_cooldown_left = maxf(0.0, close_attack_cooldown_left - delta)
	ranged_attack_cooldown_left = maxf(0.0, ranged_attack_cooldown_left - delta)
	heal_cooldown_left = maxf(0.0, heal_cooldown_left - delta)
	invulnerability_cooldown_left = maxf(0.0, invulnerability_cooldown_left - delta)

	if is_invulnerable:
		invulnerability_time_left = maxf(0.0, invulnerability_time_left - delta)
		if invulnerability_time_left <= 0.0:
			set_invulnerability(false)

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


# Attack 1: visual comes from the built-in attack1 animation; damage is radial.
func start_close_auraplosion() -> void:
	if close_attack_cooldown_left > 0.0:
		return

	var token := begin_attack(&"attack1")
	if token < 0:
		return

	close_attack_cooldown_left = close_attack_cooldown
	# Cooldown only limits the next cast; it does not make a short animation freeze.
	var attack_duration := maxf(get_animation_duration(&"attack1"), close_attack_release_time)
	var release_time := clampf(close_attack_release_time, 0.0, attack_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	damage_nearby_enemies()

	await wait_for_gameplay_time(attack_duration - release_time).timeout
	finish_attack(token)


# Attack 2: selects one enemy, then places the animated Area2D effect on it.
func start_ranged_auraplosion() -> void:
	if ranged_attack_cooldown_left > 0.0:
		return
	# Choose the target when the cast begins so the spell cannot jump to another enemy.
	var target := find_nearest_enemy_in_range()
	if target == null:
		return

	var token := begin_attack(&"attack2")
	if token < 0:
		return

	ranged_attack_cooldown_left = ranged_attack_cooldown
	# Cooldown only limits the next cast; it does not make a short animation freeze.
	var attack_duration := maxf(get_animation_duration(&"attack2"), ranged_attack_release_time)
	var release_time := clampf(ranged_attack_release_time, 0.0, attack_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	if (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.has_method(&"take_damage")
		and global_position.distance_squared_to(target.global_position) <= ranged_target_range * ranged_target_range
	):
		# The visual follows the target's exact position at the moment of impact.
		spawn_auraplosion_on(target)
		target.call(&"take_damage", ranged_attack_damage)

	await wait_for_gameplay_time(attack_duration - release_time).timeout
	finish_attack(token)


# Q: a normal cast that can be interrupted by a damaging hit before it heals.
func start_heal() -> void:
	if heal_cooldown_left > 0.0 or health >= max_health:
		return

	var token := begin_attack(&"heal")
	if token < 0:
		return

	heal_cooldown_left = heal_cooldown
	var cast_duration := maxf(get_animation_duration(&"heal"), heal_release_time)
	var release_time := clampf(heal_release_time, 0.0, cast_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	set_health(health + heal_amount)
	spawn_heal_effect()

	await wait_for_gameplay_time(cast_duration - release_time).timeout
	finish_attack(token)


# E: no animation; the Priest stays mobile and becomes blue/invulnerable.
func start_invulnerability() -> void:
	if invulnerability_cooldown_left > 0.0 or is_invulnerable:
		return

	invulnerability_cooldown_left = invulnerability_cooldown
	invulnerability_time_left = invulnerability_duration
	set_invulnerability(true)


func set_invulnerability(enabled: bool) -> void:
	is_invulnerable = enabled

	if animated_sprite != null:
		animated_sprite.modulate = invulnerability_blue if enabled else _normal_sprite_modulate


# Applies Attack 1 damage to every living enemy inside the circular radius.
func damage_nearby_enemies() -> void:
	var radius_squared := close_attack_radius * close_attack_radius

	for body in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := body as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or not enemy.has_method(&"take_damage"):
			continue

		if global_position.distance_squared_to(enemy.global_position) <= radius_squared:
			enemy.call(&"take_damage", close_attack_damage)


# Attack 2 chooses the closest valid enemy inside its target range.
func find_nearest_enemy_in_range() -> Node2D:
	var closest_enemy: Node2D
	var closest_distance_squared := ranged_target_range * ranged_target_range

	for body in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := body as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or not enemy.has_method(&"take_damage"):
			continue

		var distance_squared := global_position.distance_squared_to(enemy.global_position)
		if distance_squared <= closest_distance_squared:
			closest_enemy = enemy
			closest_distance_squared = distance_squared

	return closest_enemy


# Creates the animated Attack 2 effect at the selected enemy's exact location.
func spawn_auraplosion_on(target: Node2D) -> void:
	var effect := create_animated_effect(auraplosion_scene, "auraplosion (range).tscn")
	if effect == null:
		return

	effect.global_position = target.global_position
	effect.call(&"activate")


# Creates the animated Q effect at the Priest's exact location.
func spawn_heal_effect() -> void:
	var effect := create_animated_effect(heal_scene, "heal.tscn")
	if effect == null:
		return

	effect.global_position = global_position
	effect.call(&"activate")


# Both effect scenes are Area2D roots with an activate() function in their script.
func create_animated_effect(effect_scene: PackedScene, scene_label: String) -> Area2D:
	if effect_scene == null:
		push_warning("Assign %s in the Priest Inspector." % scene_label)
		return null

	var effect := effect_scene.instantiate() as Area2D
	if effect == null:
		push_error("%s must have an Area2D as its root node." % scene_label)
		return null
	if not effect.has_method(&"activate"):
		push_error("Attach an effect script with activate() to the root Area2D of %s." % scene_label)
		effect.queue_free()
		return null

	var scene_root := get_tree().current_scene
	if scene_root == null:
		effect.queue_free()
		return null

	scene_root.add_child(effect)
	return effect


# E ignores every incoming hit. Normal damage behaviour resumes when E ends.
func take_damage(damage: int) -> void:
	if is_invulnerable:
		return

	super(damage)


func get_max_health() -> int:
	return max_health


func get_hurt_duration() -> float:
	return hurt_duration


func get_death_duration() -> float:
	return death_duration

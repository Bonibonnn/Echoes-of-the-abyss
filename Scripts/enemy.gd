extends CharacterBody2D

@export var chase_speed := 90.0
@export var max_health := 3
@export var attack_damage := 1
@export var attack_cooldown := 1.0
@export var attack_range := 40.0
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@onready var detection_area: Area2D = get_node_or_null("detection_area")
@onready var enemy_hitbox: Area2D = get_node_or_null("enemy_hitbox")
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

var player: Node2D
var health: int
var is_attacking := false
var can_attack := true
var is_hurt := false
var is_dead := false


func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	set_one_shot_animations()

	if detection_area == null:
		push_error("Add an Area2D child named 'detection_area' to the enemy.")
		return

	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	if is_hurt:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_instance_valid(player):
		if player_is_in_attack_range() and can_attack:
			attack()
			move_and_slide()
			return
		else:
			velocity = global_position.direction_to(player.global_position) * chase_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	update_movement_animation()


func attack() -> void:
	is_attacking = true
	can_attack = false
	velocity = Vector2.ZERO
	play_animation("attack")

	var player_was_hit := false
	if enemy_hitbox != null:
		for area in enemy_hitbox.get_overlapping_areas():
			if area.name.to_lower() == "player_hitbox":
				var target := area.get_parent()
				if target.is_in_group("player") and target.has_method("take_damage"):
					target.take_damage(attack_damage)
					player_was_hit = true

		# This also supports players that use a CollisionShape2D on their root body.
		if not player_was_hit:
			for body in enemy_hitbox.get_overlapping_bodies():
				if body.is_in_group("player") and body.has_method("take_damage"):
					body.take_damage(attack_damage)
					player_was_hit = true

	# Fallback for an unconfigured hitbox: attack when the player is close.
	if not player_was_hit and is_instance_valid(player) and player.has_method("take_damage"):
		player.take_damage(attack_damage)

	await get_tree().create_timer(attack_cooldown).timeout
	is_attacking = false
	can_attack = true


func player_is_in_attack_range() -> bool:
	if is_instance_valid(player) and global_position.distance_to(player.global_position) <= attack_range:
		return true

	if enemy_hitbox == null:
		return false

	for area in enemy_hitbox.get_overlapping_areas():
		if area.name.to_lower() == "player_hitbox" and area.get_parent() == player:
			return true

	for body in enemy_hitbox.get_overlapping_bodies():
		if body == player:
			return true
	return false


func take_damage(damage: int) -> void:
	if is_hurt:
		return

	health -= damage
	if health <= 0:
		die()
		return

	is_hurt = true
	velocity = Vector2.ZERO
	if animated_sprite != null:
		play_animation("hurt")
	await get_tree().create_timer(hurt_duration).timeout
	is_hurt = false


func die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	if detection_area != null:
		detection_area.monitoring = false
	if enemy_hitbox != null:
		enemy_hitbox.monitoring = false
	play_animation("death")
	await get_tree().create_timer(death_duration).timeout
	queue_free()


func set_one_shot_animations() -> void:
	if animated_sprite == null:
		return

	for animation_name in ["attack", "hurt", "death"]:
		for available_name in animated_sprite.sprite_frames.get_animation_names():
			if String(available_name).to_lower() == animation_name:
				animated_sprite.sprite_frames.set_animation_loop(available_name, false)


func play_animation(animation_name: StringName) -> void:
	if animated_sprite == null:
		push_warning("The enemy needs an AnimatedSprite2D child.")
		return

	for available_name in animated_sprite.sprite_frames.get_animation_names():
		if String(available_name).to_lower() == String(animation_name).to_lower():
			animated_sprite.play(available_name)
			return

	push_warning("Enemy animation not found: " + String(animation_name))


func update_movement_animation() -> void:
	if animated_sprite == null:
		return

	if velocity.x < 0.0:
		animated_sprite.flip_h = true
	elif velocity.x > 0.0:
		animated_sprite.flip_h = false

	if velocity == Vector2.ZERO:
		animated_sprite.play("idle")
	else:
		animated_sprite.play("walk")


func _on_detection_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name.to_lower() == "player":
		player = body


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == player:
		player = null

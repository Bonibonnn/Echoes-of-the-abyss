extends CharacterBody2D

@export var speed := 120.0
@export var max_health := 5
@export var attack_damage := 1
@export var attack_cooldown := 0.5
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var player_hitbox: Area2D = get_node_or_null("player_hitbox")

var health: int
var is_attacking := false
var can_attack := true
var is_hurt := false
var is_dead := false


func _ready() -> void:
	add_to_group("player")
	health = max_health
	set_one_shot_animations()


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	if is_hurt:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed("ui_accept") and can_attack:
		attack()

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * speed
	move_and_slide()
	update_movement_animation(direction)


func attack() -> void:
	if player_hitbox == null:
		push_error("Add an Area2D child named 'player_hitbox' to the player.")
		return

	is_attacking = true
	can_attack = false
	velocity = Vector2.ZERO
	play_animation("attack")

	for body in player_hitbox.get_overlapping_bodies():
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			body.take_damage(attack_damage)

	await get_tree().create_timer(attack_cooldown).timeout
	is_attacking = false
	can_attack = true


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
	if player_hitbox != null:
		player_hitbox.monitoring = false
	play_animation("death")
	await get_tree().create_timer(death_duration).timeout
	queue_free()


func set_one_shot_animations() -> void:
	if animated_sprite == null:
		return

	for animation_name in ["attack", "hurt", "death"]:
		if animated_sprite.sprite_frames.has_animation(animation_name):
			animated_sprite.sprite_frames.set_animation_loop(animation_name, false)


func play_animation(animation_name: StringName) -> void:
	if animated_sprite != null and animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)


func update_movement_animation(direction: Vector2) -> void:
	if animated_sprite == null:
		return

	if direction.x < 0.0:
		animated_sprite.flip_h = true
	elif direction.x > 0.0:
		animated_sprite.flip_h = false

	if direction == Vector2.ZERO:
		animated_sprite.play("idle")
	else:
		animated_sprite.play("walk")

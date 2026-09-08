extends CharacterBody2D

@export var chase_speed := 60.0
@export var max_health := 15
@export var melee_damage := 2
@export var magic_damage := 5
@export var melee_range := 42.0
@export var magic_explosion_range := 70.0
@export var melee_cooldown := 0.9
@export var magic_cooldown := 1.8
@export var magic_hit_delay := 0.45
@export var hurt_duration := 0.3
@export var death_duration := 1.0

# Optional: assign a visual-only explosion scene that appears at the boss.
@export var magic_explosion_scene: PackedScene

@onready var detection_area: Area2D = get_node_or_null("detection_area")
@onready var enemy_hitbox: Area2D = get_node_or_null("enemy_hitbox")
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

var player: Node2D
var health: int
var is_attacking := false
var is_hurt := false
var is_dead := false
var can_attack := true


func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	set_one_shot_animations()

	if detection_area == null:
		push_error("Add an Area2D child named 'detection_area' to the necromancer.")
		return

	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(_delta: float) -> void:
	if is_dead or is_hurt or is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not is_instance_valid(player):
		velocity = Vector2.ZERO
		update_movement_animation()
		return

	var distance_to_player := global_position.distance_to(player.global_position)
	face_player()

	if can_attack:
		if distance_to_player <= melee_range:
			# At melee distance, the boss sometimes uses its stronger explosion.
			if randf() < 0.35:
				magic_attack()
			else:
				melee_attack()
			return
		if distance_to_player <= magic_explosion_range:
			magic_attack()
			return

	velocity = global_position.direction_to(player.global_position) * chase_speed
	move_and_slide()
	update_movement_animation()


func melee_attack() -> void:
	is_attacking = true
	can_attack = false
	velocity = Vector2.ZERO
	play_animation("attack1")

	if is_instance_valid(player) and player.has_method("take_damage"):
		player.take_damage(melee_damage)

	await get_tree().create_timer(melee_cooldown).timeout
	is_attacking = false
	can_attack = true


func magic_attack() -> void:
	is_attacking = true
	can_attack = false
	velocity = Vector2.ZERO
	play_animation("attack2")

	await get_tree().create_timer(magic_hit_delay).timeout
	spawn_magic_explosion(global_position)

	# The blast is centered on the necromancer, so step away before it lands.
	if is_instance_valid(player) and player.has_method("take_damage"):
		if player.global_position.distance_to(global_position) <= magic_explosion_range:
			player.take_damage(magic_damage)

	await get_tree().create_timer(magic_cooldown - magic_hit_delay).timeout
	is_attacking = false
	can_attack = true


func spawn_magic_explosion(target_position: Vector2) -> void:
	if magic_explosion_scene == null:
		return

	var explosion := magic_explosion_scene.instantiate() as Node2D
	if explosion == null:
		return

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = target_position


func take_damage(damage: int) -> void:
	if is_hurt or is_dead:
		return

	health -= damage
	if health <= 0:
		die()
		return

	is_hurt = true
	velocity = Vector2.ZERO
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


func face_player() -> void:
	if animated_sprite == null or not is_instance_valid(player):
		return

	if player.global_position.x < global_position.x:
		animated_sprite.flip_h = true
	elif player.global_position.x > global_position.x:
		animated_sprite.flip_h = false


func update_movement_animation() -> void:
	if velocity.x < 0.0 and animated_sprite != null:
		animated_sprite.flip_h = true
	elif velocity.x > 0.0 and animated_sprite != null:
		animated_sprite.flip_h = false

	if velocity == Vector2.ZERO:
		play_animation("idle")
	else:
		play_animation("walk")


func set_one_shot_animations() -> void:
	if animated_sprite == null:
		return

	for animation_name in ["attack1", "attack2", "hurt", "death"]:
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


func _on_detection_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name.to_lower() == "player":
		player = body


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == player:
		player = null

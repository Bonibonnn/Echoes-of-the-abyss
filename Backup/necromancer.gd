extends Combatant

@export var chase_speed := 60.0
@export var max_health := 15
@export var melee_damage := 2
@export var magic_damage := 5
@export var melee_range := 48.0
@export var magic_explosion_range := 70.0
@export var melee_cooldown := 0.9
@export var magic_cooldown := 1.8
@export var magic_hit_delay := 0.45
@export var hurt_duration := 0.3
@export var death_duration := 1.0

# Optional: assign a visual-only explosion scene that appears at the boss.
@export var magic_explosion_scene: PackedScene

@onready var detection_area: Area2D = get_node_or_null("detection_area")

var player: Node2D


func _ready() -> void:
	super()
	add_to_group("enemy")

	if detection_area == null:
		push_error("Add an Area2D child named 'detection_area' to the necromancer.")
		return

	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	if is_hurt or is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not is_instance_valid(player):
		velocity = Vector2.ZERO
		update_idle_or_walk_animation()
		return

	set_facing_from_x(player.global_position.x - global_position.x)
	var distance_to_player := global_position.distance_to(player.global_position)

	if distance_to_player <= melee_range and can_hit_target(player):
		if randf() < 0.35:
			magic_attack()
		else:
			start_melee_attack("attack1", melee_damage, "player", melee_cooldown)
		return

	# Attack 2 is intentionally radial: it is an explosion around the boss.
	if distance_to_player <= magic_explosion_range:
		magic_attack()
		return

	velocity = global_position.direction_to(player.global_position) * chase_speed
	move_and_slide()
	update_idle_or_walk_animation()


func magic_attack() -> void:
	var token := begin_attack("attack2")
	if token < 0:
		return

	await get_tree().create_timer(magic_hit_delay).timeout
	if not is_attack_token_active(token):
		return

	spawn_magic_explosion(global_position)
	if is_instance_valid(player) and player.has_method("take_damage"):
		if player.global_position.distance_to(global_position) <= magic_explosion_range:
			player.take_damage(magic_damage)

	await get_tree().create_timer(max(0.0, magic_cooldown - magic_hit_delay)).timeout
	finish_attack(token)


func spawn_magic_explosion(target_position: Vector2) -> void:
	if magic_explosion_scene == null:
		return

	var explosion := magic_explosion_scene.instantiate() as Node2D
	if explosion == null:
		return

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = target_position


func get_max_health() -> int:
	return max_health


func get_hurt_duration() -> float:
	return hurt_duration


func get_death_duration() -> float:
	return death_duration


func _on_detection_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name.to_lower() == "player":
		player = body


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == player:
		player = null

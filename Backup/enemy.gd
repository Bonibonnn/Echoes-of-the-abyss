extends Combatant

@export var chase_speed := 90.0
@export var max_health := 3
@export var attack_damage := 1
@export var attack_cooldown := 1.0
@export var attack_range := 48.0
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@onready var detection_area: Area2D = get_node_or_null("detection_area")

var player: Node2D


func _ready() -> void:
	super()
	add_to_group("enemy")

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

	if is_hurt or is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_instance_valid(player):
		set_facing_from_x(player.global_position.x - global_position.x)
		if global_position.distance_to(player.global_position) <= attack_range and can_hit_target(player):
			start_melee_attack("attack", attack_damage, "player", attack_cooldown)
			return

		velocity = global_position.direction_to(player.global_position) * chase_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	update_idle_or_walk_animation()


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

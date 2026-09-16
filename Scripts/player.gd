extends Combatant

@export var speed := 120.0
@export var max_health := 5
@export var attack_damage := 1
@export var attack_cooldown := 0.5
@export var hurt_duration := 0.3
@export var death_duration := 0.8


func _ready() -> void:
	super()
	add_to_group("player")


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	if is_hurt or is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed("attack"):
		start_melee_attack("attack", attack_damage, "enemy", attack_cooldown)
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	set_facing_from_x(direction.x)
	velocity = direction * speed
	move_and_slide()
	update_idle_or_walk_animation()


func get_max_health() -> int:
	return max_health


func get_hurt_duration() -> float:
	return hurt_duration


func get_death_duration() -> float:
	return death_duration

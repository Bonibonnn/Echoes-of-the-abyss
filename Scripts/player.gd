extends Combatant

@export var speed := 120.0
@export var max_health := 5
@export var attack_damage := 1
@export var attack_cooldown := 0.5
@export var hurt_duration := 0.3
@export var death_duration := 0.8


func _ready() -> void:
	super()
	add_to_group(&"player")


# _unhandled_input ignores clicks already used by UI buttons.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"attack") and not is_busy():
		start_melee_attack(&"attack", attack_damage, &"enemy", attack_cooldown)


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	if is_busy():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# These actions are already set to WASD in project.godot.
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
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

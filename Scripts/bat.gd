extends Combatant

# A simple, low-health flying enemy with one close attack.

@export_category("Movement and Health")
@export var chase_speed := 90.0
@export var max_health := 2
@export var hurt_duration := 0.25
@export var death_duration := 0.8

@export_category("Attack 1 - Bite")
@export var attack_damage := 1
@export var attack_cooldown := 1.2
@export var attack_range := 34.0
@export var bite_hit_delay := 0.6

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D

var player: Node2D


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the bat.")
		return

	# The detection area remembers the player while they are nearby.
	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	if is_busy():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_instance_valid(player):
		var to_player := player.global_position - global_position
		set_facing_from_x(to_player.x)

		if to_player.length_squared() <= attack_range * attack_range and can_hit_target(player):
			start_melee_attack(&"attack1", attack_damage, &"player", attack_cooldown, bite_hit_delay)
			return

		velocity = to_player.normalized() * chase_speed
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
	if body.is_in_group(&"player"):
		player = body


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == player:
		player = null

extends Combatant

@export_category("Movement and Health")
@export var chase_speed := 90.0
@export var max_health := 3

@export_category("Attack 1 - Slash")
@export var attack_damage := 1
@export var attack_cooldown := 1.0
@export var attack_range := 48.0

@export_category("Attack 2 - Heavy Slash")
# The heavy slash uses the new attack2 animation and deals two damage.
@export var heavy_slash_damage := 2
@export_range(0.1, 10.0, 0.01, "suffix:s") var heavy_slash_cooldown := 1.5
@export_range(0.0, 10.0, 0.01, "suffix:s") var heavy_slash_hit_delay := 0.6

@export_category("Animation Timing")
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D

var player: Node2D
var next_attack_is_heavy := false


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the enemy.")
		return

	# The signals remember the player while they are inside the chase range.
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
			use_next_attack()
			return

		velocity = to_player.normalized() * chase_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	update_idle_or_walk_animation()


# Alternate the normal slash and the slower, stronger heavy slash.
func use_next_attack() -> void:
	if next_attack_is_heavy:
		start_melee_attack(&"attack2", heavy_slash_damage, &"player", heavy_slash_cooldown, heavy_slash_hit_delay)
		next_attack_is_heavy = false
	else:
		start_melee_attack(&"attack", attack_damage, &"player", attack_cooldown)
		next_attack_is_heavy = true


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

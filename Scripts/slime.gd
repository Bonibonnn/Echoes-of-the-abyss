extends Combatant

# A small melee enemy that alternates between a weak bump and a stronger sword swing.

@export_category("Movement and Health")
@export var chase_speed := 75.0
@export var max_health := 3
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@export_category("Attack Reach")
@export var attack_range := 40.0

@export_category("Attack 1 - Bump")
@export var bump_damage := 1
@export var bump_cooldown := 1.2
@export var bump_hit_delay := 0.55

@export_category("Attack 2 - Sword")
@export var sword_damage := 2
@export var sword_cooldown := 1.8
@export var sword_hit_delay := 1.0

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D

var player: Node2D
var next_attack_is_sword := false


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the slime.")
		return

	# The detection area chooses who the slime follows.
	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	# Do not move while attacking, hurt, dead, or frozen.
	if is_busy():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_instance_valid(player):
		var to_player := player.global_position - global_position
		set_facing_from_x(to_player.x)

		# Actual damage still requires the player to touch enemy_hitbox in front
		# of the slime, preventing attacks through or behind the player.
		if to_player.length_squared() <= attack_range * attack_range and can_hit_target(player):
			use_next_attack()
			return

		velocity = to_player.normalized() * chase_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	update_idle_or_walk_animation()


# Uses bump first, then sword, then repeats. This makes the 2-damage move clear.
func use_next_attack() -> void:
	if next_attack_is_sword:
		start_melee_attack(&"attack2", sword_damage, &"player", sword_cooldown, sword_hit_delay)
		next_attack_is_sword = false
	else:
		start_melee_attack(&"attack1", bump_damage, &"player", bump_cooldown, bump_hit_delay)
		next_attack_is_sword = true


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

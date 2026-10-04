extends Combatant

# A basic ranged enemy. It chases until the player is in bow range, then fires
# one arrow attack using the dedicated arrow_skeleton scene.

@export_category("Movement and Health")
@export var chase_speed := 65.0
@export var max_health := 3
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@export_category("Ranged Attack")
@export var attack_range := 220.0
@export var attack_cooldown := 1.8
@export var arrow_release_time := 0.9
@export var arrow_damage := 1
@export var arrow_spawn_distance := 20.0
@export var arrow_scene: PackedScene = preload("res://Scenes/arrow_skeleton.tscn")

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D

var player: Node2D
var shot_direction := Vector2.RIGHT


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the skeleton archer.")
		return

	if arrow_scene == null:
		push_error("Assign arrow_skeleton.tscn to Arrow Scene.")

	# The detection area only chooses who to chase and shoot.
	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


# This enemy damages with arrows, so it does not need an enemy_hitbox.
func requires_attack_hitbox() -> bool:
	return false


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

		if to_player.length_squared() <= attack_range * attack_range:
			start_arrow_attack(to_player.normalized())
			return

		velocity = to_player.normalized() * chase_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	update_idle_or_walk_animation()


# Plays attack1, then releases one arrow near the middle of the animation.
func start_arrow_attack(aim_direction: Vector2) -> void:
	var token := begin_attack(&"attack1")
	if token < 0:
		return

	shot_direction = aim_direction.normalized()
	if shot_direction.is_zero_approx():
		shot_direction = Vector2(facing_direction, 0.0)

	var attack_duration := maxf(attack_cooldown, get_animation_duration(&"attack1"))
	var release_time := clampf(arrow_release_time, 0.0, attack_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	fire_arrow(shot_direction)

	await wait_for_gameplay_time(attack_duration - release_time).timeout
	finish_attack(token)


# Creates the dedicated arrow_skeleton projectile and sends it toward the player.
func fire_arrow(direction: Vector2) -> void:
	if arrow_scene == null:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var arrow := arrow_scene.instantiate() as Area2D
	if arrow == null:
		push_error("arrow_skeleton.tscn must have an Area2D root.")
		return
	if not arrow.has_method(&"launch"):
		push_error("Attach Scripts/arrow.gd to arrow_skeleton.tscn.")
		arrow.queue_free()
		return

	scene_root.add_child(arrow)
	arrow.global_position = global_position + direction * arrow_spawn_distance
	arrow.call(&"launch", direction, arrow_damage, &"player", self)


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

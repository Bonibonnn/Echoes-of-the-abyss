extends Combatant

# A quick mounted enemy. It cycles between a long tusk stab, a heavy swing,
# and a circular flail so players cannot safely stand on its sides.

@export_category("Movement and Health")
@export var chase_speed := 100.0
@export var max_health := 6
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@export_category("Attack 1 - Tusk Stab")
@export var tusk_damage := 2
@export_range(0.1, 10.0, 0.01) var tusk_recovery := 1.6
@export_range(1.0, 200.0, 1.0, "suffix:px") var tusk_range := 52.0
@export_range(0.0, 10.0, 0.01) var tusk_hit_delay := 0.9

@export_category("Attack 2 - Blunt Swing")
@export var blunt_swing_damage := 3
@export_range(0.1, 10.0, 0.01) var blunt_swing_recovery := 1.9
@export_range(0.0, 10.0, 0.01) var blunt_swing_hit_delay := 1.05

@export_category("Attack 3 - Circular Flail")
@export var flail_damage := 2
@export_range(0.1, 10.0, 0.01) var flail_recovery := 2.3
@export_range(0.0, 10.0, 0.01) var flail_hit_delay := 1.1

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D
@onready var swing_hitbox := get_node_or_null(^"attack_pivot/swing_hitbox") as Area2D
@onready var flail_hitbox := get_node_or_null(^"flail_hitbox") as Area2D

var player: Node2D
# 0 = tusk stab, 1 = blunt swing, 2 = circular flail.
var next_attack_index := 0


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the Orc Rider.")
		return

	if swing_hitbox == null:
		push_error("Add attack_pivot/swing_hitbox to the Orc Rider.")
	else:
		swing_hitbox.monitoring = true

	if flail_hitbox == null:
		push_error("Add an Area2D child named flail_hitbox to the Orc Rider.")
	else:
		flail_hitbox.monitoring = true

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

	if not is_instance_valid(player) or player.is_queued_for_deletion():
		player = null
		velocity = Vector2.ZERO
		update_idle_or_walk_animation()
		return

	var to_player := player.global_position - global_position
	set_facing_from_x(to_player.x)

	# The normal close-range order is: tusk -> swing -> flail.
	if next_attack_index == 2 and has_flail_target(player):
		start_flail_attack()
		next_attack_index = 0
		return

	if next_attack_index == 1 and can_swing_target(player):
		start_blunt_swing()
		next_attack_index = 2
		return

	if can_tusk_target(player):
		start_melee_attack(
			&"attack1",
			tusk_damage,
			&"player",
			tusk_recovery,
			tusk_hit_delay
		)
		next_attack_index = 1
		return

	# If the player avoids the narrow tusk hitbox, use whichever attack can
	# actually reach them instead of making the rider stand still.
	if can_swing_target(player):
		start_blunt_swing()
		next_attack_index = 2
		return

	if has_flail_target(player):
		start_flail_attack()
		next_attack_index = 0
		return

	velocity = to_player.normalized() * chase_speed
	move_and_slide()
	update_idle_or_walk_animation()


# Attack 2 has its own slightly wider forward hitbox.
func start_blunt_swing() -> void:
	var token := begin_attack(&"attack2")
	if token < 0:
		return

	var attack_duration := maxf(blunt_swing_recovery, get_animation_duration(&"attack2"))
	var hit_time := clampf(blunt_swing_hit_delay, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return
	deal_hitbox_damage(swing_hitbox, blunt_swing_damage, true)

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


# Attack 3 hits every player in the circle; it is intentionally not directional.
func start_flail_attack() -> void:
	var token := begin_attack(&"attack3")
	if token < 0:
		return

	var attack_duration := maxf(flail_recovery, get_animation_duration(&"attack3"))
	var hit_time := clampf(flail_hit_delay, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return
	deal_hitbox_damage(flail_hitbox, flail_damage, false)

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


# Applies damage only to overlapping player bodies. Directional attacks also
# require their target to be in front of the Orc Rider.
func deal_hitbox_damage(hitbox: Area2D, damage: int, require_front: bool) -> void:
	if hitbox == null:
		return

	for body in hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not (body is Node2D):
			continue

		var target := body as Node2D
		if target.is_queued_for_deletion():
			continue
		if not target.is_in_group(&"player") or not target.has_method(&"take_damage"):
			continue
		if require_front and not is_target_in_front(target):
			continue

		target.call(&"take_damage", damage)


func can_tusk_target(target: Node2D) -> bool:
	var distance_squared := global_position.distance_squared_to(target.global_position)
	return distance_squared <= tusk_range * tusk_range and can_hit_target(target)


func can_swing_target(target: Node2D) -> bool:
	return swing_hitbox != null and is_target_in_front(target) and swing_hitbox.overlaps_body(target)


func has_flail_target(target: Node2D) -> bool:
	return flail_hitbox != null and flail_hitbox.overlaps_body(target)


func is_target_in_front(target: Node2D) -> bool:
	return (target.global_position.x - global_position.x) * facing_direction >= 0.0


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


extends Combatant

# A tougher version of the regular Orc. It alternates a heavy blunt swing, a
# longer blunt thrust, and a ground pound that stuns but never deals damage.

@export_category("Movement and Health")
@export var chase_speed := 70.0
@export var max_health := 6
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@export_category("Attack 1 - Blunt Swing")
@export var blunt_swing_damage := 2
@export_range(0.1, 10.0, 0.01) var blunt_swing_cooldown := 1.6
@export_range(1.0, 200.0, 1.0, "suffix:px") var blunt_swing_range := 44.0
@export_range(0.0, 10.0, 0.01) var blunt_swing_hit_delay := 0.7

@export_category("Attack 2 - Long Blunt Thrust")
@export var blunt_thrust_damage := 1
@export_range(0.1, 10.0, 0.01) var blunt_thrust_cooldown := 1.8
@export_range(0.0, 10.0, 0.01) var blunt_thrust_hit_delay := 0.75

@export_category("Attack 3 - Ground Pound Stun")
# This attack intentionally does no damage; it only stops affected players.
@export_range(0.1, 10.0, 0.01) var groundpound_cooldown := 2.4
@export_range(0.0, 10.0, 0.01) var groundpound_hit_delay := 1.0
@export_range(0.1, 10.0, 0.1, "suffix:s") var groundpound_stun_duration := 1.5

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D
@onready var stab_hitbox := get_node_or_null(^"attack_pivot/stab_hitbox") as Area2D
@onready var groundpound_hitbox := get_node_or_null(^"groundpound_hitbox") as Area2D

var player: Node2D
var next_attack_index := 0


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the Armored Orc.")
		return

	if stab_hitbox == null:
		push_error("Add attack_pivot/stab_hitbox to the Armored Orc.")
	else:
		stab_hitbox.monitoring = true

	if groundpound_hitbox == null:
		push_error("Add an Area2D child named groundpound_hitbox to the Armored Orc.")
	else:
		groundpound_hitbox.monitoring = true

	# Detection remembers the player while they are inside the chase range.
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
	var distance_squared := to_player.length_squared()

	# The standard sequence is: heavy swing -> long thrust -> stun pound.
	if next_attack_index == 2 and can_groundpound_target(player):
		start_groundpound_attack()
		next_attack_index = 0
		return

	if next_attack_index == 1 and can_stab_target(player):
		start_blunt_thrust()
		next_attack_index = 2
		return

	# Attack 1 uses Combatant's normal front-only melee hitbox.
	if distance_squared <= blunt_swing_range * blunt_swing_range and can_hit_target(player):
		start_melee_attack(
			&"attack1",
			blunt_swing_damage,
			&"player",
			blunt_swing_cooldown,
			blunt_swing_hit_delay
		)
		next_attack_index = 1
		return

	# The longer thrust can catch a player outside normal swing distance.
	if can_stab_target(player):
		start_blunt_thrust()
		next_attack_index = 2
		return

	# The ground pound can still stun a player on either side of the Orc.
	if can_groundpound_target(player):
		start_groundpound_attack()
		next_attack_index = 0
		return

	velocity = to_player.normalized() * chase_speed
	move_and_slide()
	update_idle_or_walk_animation()


# Attack 2 owns its attack lifecycle because it uses a longer separate hitbox.
func start_blunt_thrust() -> void:
	var token := begin_attack(&"attack2")
	if token < 0:
		return

	var attack_duration := maxf(blunt_thrust_cooldown, get_animation_duration(&"attack2"))
	var hit_time := clampf(blunt_thrust_hit_delay, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return
	deal_stab_damage()

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


func deal_stab_damage() -> void:
	if stab_hitbox == null:
		return

	for body in stab_hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not (body is Node2D):
			continue

		var target := body as Node2D
		if target.is_queued_for_deletion():
			continue
		if target.is_in_group(&"player") and is_target_in_front(target) and target.has_method(&"take_damage"):
			target.call(&"take_damage", blunt_thrust_damage)


# Attack 3 has no damage call. It only applies the shared no-movement/no-action
# stun to every player inside the circular ground-pound hitbox.
func start_groundpound_attack() -> void:
	var token := begin_attack(&"attack3")
	if token < 0:
		return

	var attack_duration := maxf(groundpound_cooldown, get_animation_duration(&"attack3"))
	var hit_time := clampf(groundpound_hit_delay, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return
	apply_groundpound_stun()

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


func apply_groundpound_stun() -> void:
	if groundpound_hitbox == null:
		return

	for body in groundpound_hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not (body is Node2D):
			continue

		var target := body as Node2D
		if target.is_queued_for_deletion():
			continue
		if target.is_in_group(&"player") and target.has_method(&"apply_stun"):
			target.call(&"apply_stun", groundpound_stun_duration)


func can_stab_target(target: Node2D) -> bool:
	return stab_hitbox != null and is_target_in_front(target) and stab_hitbox.overlaps_body(target)


func can_groundpound_target(target: Node2D) -> bool:
	return groundpound_hitbox != null and groundpound_hitbox.overlaps_body(target)


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

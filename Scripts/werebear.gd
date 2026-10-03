extends Combatant

# A slow, durable mini-boss that cycles through a claw swipe, double swipe,
# and a forward slam. The slam deals a small hit, then briefly stuns its target.

@export_category("Movement and Health")
@export var chase_speed := 55.0
@export var max_health := 25
@export var hurt_duration := 0.35
@export var death_duration := 1.0

@export_category("Attack 1 - Claw Swipe")
@export var claw_damage := 2
@export_range(0.1, 10.0, 0.01) var claw_cooldown := 2.0
@export_range(1.0, 200.0, 1.0, "suffix:px") var claw_range := 48.0
@export_range(0.0, 10.0, 0.01) var claw_hit_delay := 0.9

@export_category("Attack 2 - Double Swipe")
# Each impact deals this amount. The two hit moments are far enough apart to
# pass Combatant's short damage-protection time.
@export var double_swipe_damage := 2
@export_range(0.1, 10.0, 0.01) var double_swipe_cooldown := 2.8
@export_range(0.0, 10.0, 0.01) var double_swipe_first_hit_delay := 0.8
@export_range(0.0, 10.0, 0.01) var double_swipe_second_hit_delay := 1.8

@export_category("Attack 3 - Stun Slam")
@export var slam_damage := 1
@export_range(0.1, 10.0, 0.01) var slam_cooldown := 2.2
@export_range(0.0, 10.0, 0.01) var slam_hit_delay := 1.0
@export_range(0.1, 10.0, 0.1, "suffix:s") var slam_stun_duration := 2.0

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D
@onready var slam_hitbox := get_node_or_null(^"attack_pivot/slam_hitbox") as Area2D

var player: Node2D
var next_attack_index := 0


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the Werebear.")
		return

	if slam_hitbox == null:
		push_error("Add attack_pivot/slam_hitbox to the Werebear.")
	else:
		slam_hitbox.monitoring = true

	# These guarded connections also work if the scene signal was already connected.
	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(_delta: float) -> void:
	if is_dead:
		return

	# Hurt, attack, freeze, and stun all stop the boss in place.
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

	# The normal attack order is: claw -> double swipe -> stun slam.
	if next_attack_index == 2 and can_slam_target(player):
		start_slam_attack()
		next_attack_index = 0
		return

	# Attack 1 and Attack 2 use the same close, front-facing hitbox.
	if to_player.length_squared() <= claw_range * claw_range and can_hit_target(player):
		if next_attack_index == 0:
			start_melee_attack(&"attack1", claw_damage, &"player", claw_cooldown, claw_hit_delay)
			next_attack_index = 1
		else:
			start_double_swipe()
			next_attack_index = 2
		return

	velocity = to_player.normalized() * chase_speed
	move_and_slide()
	update_idle_or_walk_animation()


# Attack 2 has two real damage moments instead of one long animation.
func start_double_swipe() -> void:
	var token := begin_attack(&"attack2")
	if token < 0:
		return

	var attack_duration := maxf(double_swipe_cooldown, get_animation_duration(&"attack2"))
	var first_hit_time := clampf(double_swipe_first_hit_delay, 0.0, attack_duration)
	var minimum_gap := damage_invulnerability_time + 0.01
	var second_hit_time := clampf(
		maxf(double_swipe_second_hit_delay, first_hit_time + minimum_gap),
		first_hit_time,
		attack_duration
	)

	await wait_for_gameplay_time(first_hit_time).timeout
	if not is_attack_token_active(token):
		return
	deal_melee_damage(double_swipe_damage, &"player")

	await wait_for_gameplay_time(second_hit_time - first_hit_time).timeout
	if not is_attack_token_active(token):
		return
	deal_melee_damage(double_swipe_damage, &"player")

	await wait_for_gameplay_time(attack_duration - second_hit_time).timeout
	finish_attack(token)


# Attack 3 uses its wider forward hitbox and applies stun at its impact moment.
func start_slam_attack() -> void:
	var token := begin_attack(&"attack3")
	if token < 0:
		return

	var attack_duration := maxf(slam_cooldown, get_animation_duration(&"attack3"))
	var hit_time := clampf(slam_hit_delay, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return
	deal_slam_damage()

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


# The slam remains front-facing, but its hitbox is wider than the claw hitbox.
func deal_slam_damage() -> void:
	if slam_hitbox == null:
		return

	for body in slam_hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not (body is Node2D):
			continue

		var target := body as Node2D
		if target.is_queued_for_deletion():
			continue
		if not target.is_in_group(&"player") or not is_target_in_front(target):
			continue
		if target.has_method(&"take_damage"):
			target.call(&"take_damage", slam_damage)
			# No special stun animation is required; Combatant keeps the player still.
			if target.has_method(&"apply_stun"):
				target.call(&"apply_stun", slam_stun_duration)


func can_slam_target(target: Node2D) -> bool:
	return slam_hitbox != null and is_target_in_front(target) and slam_hitbox.overlaps_body(target)


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

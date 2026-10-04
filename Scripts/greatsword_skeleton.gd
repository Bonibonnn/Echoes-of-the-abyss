extends Combatant

# A mid-health skeleton that cycles through a swing, a heavy strike, and a
# long-range stab. The stab has its own longer forward hitbox.

@export_category("Movement and Health")
@export var chase_speed := 65.0
@export var max_health := 6
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@export_category("Attack 1 - Greatsword Swing")
@export var swing_damage := 2
@export var swing_cooldown := 1.8
@export var swing_range := 44.0
@export var swing_hit_delay := 0.9

@export_category("Attack 2 - Heavy Strike")
@export var heavy_strike_damage := 3
@export var heavy_strike_cooldown := 2.4
@export var heavy_strike_hit_delay := 1.3

@export_category("Attack 3 - Long Stab")
@export var stab_damage := 1
@export var stab_cooldown := 1.6
@export var stab_range := 70.0
@export var stab_hit_delay := 0.8

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D
@onready var stab_hitbox := get_node_or_null(^"attack_pivot/stab_hitbox") as Area2D

var player: Node2D
var next_attack_index := 0


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the greatsword skeleton.")
		return

	if stab_hitbox == null:
		push_error("Add attack_pivot/stab_hitbox to the greatsword skeleton.")
	else:
		stab_hitbox.monitoring = true

	# Detection chooses who this enemy chases.
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

		# Attack3 is used from farther away or as the third step of the cycle.
		if next_attack_index == 2 and can_stab_target(player):
			start_stab_attack()
			next_attack_index = 0
			return

		# Attack1 and attack2 share the close, front-only enemy_hitbox.
		if to_player.length_squared() <= swing_range * swing_range and can_hit_target(player):
			if next_attack_index == 0:
				start_melee_attack(&"attack1", swing_damage, &"player", swing_cooldown, swing_hit_delay)
				next_attack_index = 1
			else:
				start_melee_attack(&"attack2", heavy_strike_damage, &"player", heavy_strike_cooldown, heavy_strike_hit_delay)
				next_attack_index = 2
			return

		# When the player is outside sword-swing range but inside stab range,
		# the skeleton uses its low-damage long stab immediately.
		if can_stab_target(player):
			start_stab_attack()
			next_attack_index = 0
			return

		velocity = to_player.normalized() * chase_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	update_idle_or_walk_animation()


# Attack3 needs its own hitbox because it reaches farther than the two swings.
func start_stab_attack() -> void:
	var token := begin_attack(&"attack3")
	if token < 0:
		return

	var attack_duration := maxf(stab_cooldown, get_animation_duration(&"attack3"))
	var hit_time := clampf(stab_hit_delay, 0.0, attack_duration)

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
			target.call(&"take_damage", stab_damage)


func can_stab_target(target: Node2D) -> bool:
	return stab_hitbox != null and is_target_in_front(target) and stab_hitbox.overlaps_body(target)


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

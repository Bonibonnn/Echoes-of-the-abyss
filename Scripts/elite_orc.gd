extends Combatant

# The Elite Orc is the overworld gatekeeper. It uses its axe at close range,
# then brings out its two high-damage attacks only after their cooldowns end.

@export_category("Movement and Health")
@export var chase_speed := 58.0
@export var max_health := 40
@export var hurt_duration := 0.35
@export var death_duration := 0.8

@export_category("Attack 1 - Axe Swipe")
@export var axe_damage := 3
# This is the time before the next normal axe swing, not a special cooldown.
@export_range(0.1, 10.0, 0.01) var axe_recovery := 1.6
@export_range(1.0, 200.0, 1.0, "suffix:px") var axe_range := 46.0
@export_range(0.0, 10.0, 0.01) var axe_hit_delay := 0.75

@export_category("Attack 2 - Whirlwind Strike")
@export var whirlwind_damage := 3
@export_range(0.1, 60.0, 0.1, "suffix:s") var whirlwind_cooldown := 10.0
@export_range(0.0, 10.0, 0.01) var whirlwind_hit_delay := 1.1

@export_category("Attack 3 - Devastating Blow")
@export var devastating_damage := 5
@export_range(0.1, 60.0, 0.1, "suffix:s") var devastating_cooldown := 20.0
@export_range(0.0, 10.0, 0.01) var devastating_hit_delay := 1.15

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D
@onready var whirlwind_hitbox := get_node_or_null(^"whirlwind_hitbox") as Area2D

var player: Node2D
var whirlwind_cooldown_left := 0.0
var devastating_cooldown_left := 0.0


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the Elite Orc.")
		return

	if whirlwind_hitbox == null:
		push_error("Add an Area2D child named whirlwind_hitbox to the Elite Orc.")
	else:
		whirlwind_hitbox.monitoring = true

	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)

	# The boss opens with normal axe swings. The large attacks become available
	# after 10 and 20 seconds instead of being unavoidable at the fight's start.
	whirlwind_cooldown_left = whirlwind_cooldown
	devastating_cooldown_left = devastating_cooldown


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# These are true ability cooldowns. They keep ticking while an animation plays,
	# so the boss never looks frozen for 10 or 20 seconds after attacking.
	whirlwind_cooldown_left = maxf(0.0, whirlwind_cooldown_left - delta)
	devastating_cooldown_left = maxf(0.0, devastating_cooldown_left - delta)

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

	# Attack 3 is the strongest forward hit. Its long animation gives the player
	# time to move out of the axe hitbox before its 5 damage lands.
	if devastating_cooldown_left <= 0.0 and can_use_axe_hitbox(player):
		start_devastating_blow()
		return

	# Attack 2 is circular, so it can hit a player standing on either side.
	if whirlwind_cooldown_left <= 0.0 and has_player_in_whirlwind_range():
		start_whirlwind_strike()
		return

	# Attack 1 is the repeatable close-range axe swipe.
	if can_use_axe_hitbox(player):
		start_melee_attack(
			&"attack1",
			axe_damage,
			&"player",
			axe_recovery,
			axe_hit_delay
		)
		return

	velocity = to_player.normalized() * chase_speed
	move_and_slide()
	update_idle_or_walk_animation()


# Starts the circular attack and gives one hit to every player in its radius.
func start_whirlwind_strike() -> void:
	var token := begin_attack(&"attack2")
	if token < 0:
		return

	whirlwind_cooldown_left = whirlwind_cooldown
	var attack_duration := maxf(0.1, get_animation_duration(&"attack2"))
	var hit_time := clampf(whirlwind_hit_delay, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return
	deal_whirlwind_damage()

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


# Attack 3 uses the regular front-only axe hitbox, but its cooldown is kept
# separately from the animation duration.
func start_devastating_blow() -> void:
	var token := begin_attack(&"attack3")
	if token < 0:
		return

	devastating_cooldown_left = devastating_cooldown
	var attack_duration := maxf(0.1, get_animation_duration(&"attack3"))
	var hit_time := clampf(devastating_hit_delay, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return
	deal_melee_damage(devastating_damage, &"player")

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


# Whirlwind deliberately does not use a facing check because it is a full circle.
func deal_whirlwind_damage() -> void:
	if whirlwind_hitbox == null:
		return

	for body in whirlwind_hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not (body is Node2D):
			continue

		var target := body as Node2D
		if target.is_queued_for_deletion():
			continue
		if target.is_in_group(&"player") and target.has_method(&"take_damage"):
			target.call(&"take_damage", whirlwind_damage)


func can_use_axe_hitbox(target: Node2D) -> bool:
	var distance_squared := global_position.distance_squared_to(target.global_position)
	return distance_squared <= axe_range * axe_range and can_hit_target(target)


func has_player_in_whirlwind_range() -> bool:
	return whirlwind_hitbox != null and is_instance_valid(player) and whirlwind_hitbox.overlaps_body(player)


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


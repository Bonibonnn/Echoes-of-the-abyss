extends Combatant

# A low-health, fast enemy. Its second attack dashes toward the player and
# leaves a short-lived slash trail over the exact ground it travelled across.

const DASH_TRAIL_SCENE := preload("res://Scenes/werewolf_dash_trail.tscn")

@export_category("Movement and Health")
@export var chase_speed := 90.0
@export var max_health := 3
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@export_category("Attack 1 - Claw Slash")
@export var slash_damage := 1
@export_range(0.1, 10.0, 0.01) var slash_cooldown := 1.8
@export_range(1.0, 200.0, 1.0, "suffix:px") var slash_range := 40.0
@export_range(0.0, 10.0, 0.01) var slash_hit_delay := 0.85

@export_category("Attack 2 - Dash Slash Trail")
# The trail applies one damage per tick while a player stands on it.
@export var dash_damage_per_tick := 1
@export_range(50.0, 1000.0, 1.0, "suffix:px/s") var dash_speed := 240.0
@export_range(0.05, 2.0, 0.01, "suffix:s") var dash_duration := 0.45
@export_range(1.0, 300.0, 1.0, "suffix:px") var dash_start_range := 140.0
@export_range(0.1, 10.0, 0.01, "suffix:s") var dash_cooldown := 2.8
@export_range(0.15, 2.0, 0.01, "suffix:s") var dash_damage_interval := 0.4
@export_range(0.1, 5.0, 0.01, "suffix:s") var trail_lifetime := 0.65
@export_range(4.0, 100.0, 1.0, "suffix:px") var trail_width := 18.0

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D

var player: Node2D
var dash_cooldown_left := 0.0
var next_attack_is_dash := false
var is_dashing := false
var dash_direction := Vector2.ZERO
var active_trail: Area2D


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the Werewolf.")
		return

	# Detection chooses which player this Werewolf chases.
	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(delta: float) -> void:
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)

	if is_dead:
		return

	# The dash coroutine moves the Werewolf itself, so this must happen before
	# Combatant's normal busy-state movement lock.
	if is_dashing:
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

	# Use a dash after a claw slash, or to quickly close a medium-distance gap.
	if dash_cooldown_left <= 0.0 and distance_squared <= dash_start_range * dash_start_range:
		if next_attack_is_dash or distance_squared > slash_range * slash_range:
			start_dash_attack(to_player)
			next_attack_is_dash = false
			return

	# Attack 1 is a normal, front-facing melee slash.
	if distance_squared <= slash_range * slash_range and can_hit_target(player):
		start_melee_attack(&"attack1", slash_damage, &"player", slash_cooldown, slash_hit_delay)
		next_attack_is_dash = true
		return

	velocity = to_player.normalized() * chase_speed
	move_and_slide()
	update_idle_or_walk_animation()


# Dashes a fixed short time toward the player. The trail expands only to the
# actual position reached, so it cannot damage through a wall that stops the dash.
func start_dash_attack(to_player: Vector2) -> void:
	if dash_cooldown_left > 0.0 or is_busy():
		return

	dash_direction = to_player.normalized()
	if dash_direction.is_zero_approx():
		dash_direction = Vector2(float(facing_direction), 0.0)
	set_facing_from_x(dash_direction.x)

	var token := begin_attack(&"attack2")
	if token < 0:
		return

	dash_cooldown_left = dash_cooldown
	is_dashing = true
	var trail := spawn_dash_trail(global_position)
	active_trail = trail
	var elapsed_time := 0.0
	var safe_dash_duration := minf(dash_duration, get_animation_duration(&"attack2"))

	while elapsed_time < safe_dash_duration:
		if not is_attack_token_active(token):
			break

		velocity = dash_direction * dash_speed
		move_and_slide()
		update_dash_trail(trail)

		await get_tree().physics_frame
		elapsed_time += get_physics_process_delta_time()

	is_dashing = false
	velocity = Vector2.ZERO
	finish_dash_trail(trail)
	active_trail = null

	if not is_attack_token_active(token):
		return

	# The attack stays busy until its full animation has finished.
	var attack_duration := maxf(dash_cooldown, get_animation_duration(&"attack2"))
	await wait_for_gameplay_time(maxf(0.0, attack_duration - safe_dash_duration)).timeout
	finish_attack(token)


# Creates one expanding Area2D instead of many overlapping hitboxes. That gives
# the whole dash path continuous damage while keeping its damage rate controlled.
func spawn_dash_trail(start_position: Vector2) -> Area2D:
	var trail := DASH_TRAIL_SCENE.instantiate() as Area2D
	if trail == null:
		push_error("werewolf_dash_trail.tscn must have an Area2D root.")
		return null

	var trail_parent := get_parent()
	if trail_parent == null:
		trail_parent = get_tree().current_scene
	if trail_parent == null:
		return null

	trail_parent.add_child(trail)
	if trail.has_method(&"begin_trail"):
		trail.call(
			&"begin_trail",
			start_position,
			dash_damage_per_tick,
			dash_damage_interval,
			trail_width,
			trail_lifetime
		)
	else:
		push_error("Attach werewolf_dash_trail.gd to werewolf_dash_trail.tscn.")
		trail.queue_free()
		return null

	return trail


func update_dash_trail(trail: Area2D) -> void:
	if is_instance_valid(trail) and trail.has_method(&"update_trail_end"):
		trail.call(&"update_trail_end", global_position)


func finish_dash_trail(trail: Area2D) -> void:
	if is_instance_valid(trail) and trail.has_method(&"finish_trail"):
		trail.call(&"finish_trail")


# Damage interrupts the dash immediately, so it cannot continue through hurt.
func take_damage(damage: int) -> void:
	if damage > 0:
		is_dashing = false
		velocity = Vector2.ZERO
	super(damage)


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

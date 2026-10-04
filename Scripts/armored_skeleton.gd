extends Combatant

# A tougher skeleton that alternates a strong forward halberd strike with a
# weaker circular spin. The spin can damage every player inside its circle.

@export_category("Movement and Health")
@export var chase_speed := 65.0
@export var max_health := 8
@export var hurt_duration := 0.3
@export var death_duration := 0.8

@export_category("Attack 1 - Halberd Strike")
@export var halberd_damage := 2
@export var halberd_cooldown := 1.6
@export var halberd_range := 42.0
@export var halberd_hit_delay := 0.85

@export_category("Attack 2 - Halberd Spin")
@export var spin_damage := 1
@export var spin_cooldown := 2.0
@export var spin_hit_delay := 0.9

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D
@onready var spin_hitbox := get_node_or_null(^"spin_hitbox") as Area2D

var player: Node2D
var next_attack_is_spin := false


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the armored skeleton.")
		return

	if spin_hitbox == null:
		push_error("Add an Area2D child named spin_hitbox to the armored skeleton.")
	else:
		spin_hitbox.monitoring = true

	# Detection chooses who the armored skeleton chases.
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

		# Spin is a circle, so it can hit players on every side.
		if next_attack_is_spin and has_player_in_spin_range():
			start_spin_attack()
			next_attack_is_spin = false
			return

		# The halberd strike uses the front-only enemy_hitbox from Combatant.
		if to_player.length_squared() <= halberd_range * halberd_range and can_hit_target(player):
			start_melee_attack(&"attack1", halberd_damage, &"player", halberd_cooldown, halberd_hit_delay)
			next_attack_is_spin = true
			return

		# If a player is beside or behind the skeleton, the spin is still useful.
		if has_player_in_spin_range():
			start_spin_attack()
			next_attack_is_spin = false
			return

		velocity = to_player.normalized() * chase_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	update_idle_or_walk_animation()


# Starts attack2 and applies one 1-damage hit to every player in the circle.
func start_spin_attack() -> void:
	var token := begin_attack(&"attack2")
	if token < 0:
		return

	var attack_duration := maxf(spin_cooldown, get_animation_duration(&"attack2"))
	var hit_time := clampf(spin_hit_delay, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return

	deal_spin_damage()

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


# Unlike a normal melee hit, this does not check facing direction.
func deal_spin_damage() -> void:
	if spin_hitbox == null:
		return

	for body in spin_hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not (body is Node2D):
			continue

		var target := body as Node2D
		if target.is_queued_for_deletion():
			continue
		if target.is_in_group(&"player") and target.has_method(&"take_damage"):
			target.call(&"take_damage", spin_damage)


func has_player_in_spin_range() -> bool:
	return spin_hitbox != null and is_instance_valid(player) and spin_hitbox.overlaps_body(player)


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

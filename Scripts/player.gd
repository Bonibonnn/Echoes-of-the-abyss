extends Combatant

@export_category("Movement")
@export var speed := 120.0

@export_category("Health")
@export var max_health := 5

@export_category("Attack 1")
@export var attack_damage := 1
@export var attack_cooldown := 0.5

@export_category("Attack 2 Combo")
# Attack 2 has two visual swings, but deals this total damage only once.
# That prevents the target's hurt state from blocking a second damage event.
@export var attack2_total_damage := 2
# This only disables Attack 2 for nine seconds; it does not lock movement for nine seconds.
@export_range(0.1, 60.0, 0.1) var attack2_cooldown := 9.0
# Set this to the first visible swing. The second swing is visual only.
@export_range(0.0, 10.0, 0.01) var attack2_hit_time := 0.18

@export_category("Skill 1 - Heavy Strike")
# Q: a slow, heavy attack. Its animation stays named "skill".
@export var skill_animation: StringName = &"skill"
@export var skill1_damage := 4
@export_range(0.1, 10.0, 0.01) var skill1_cast_time := 1.2
@export_range(0.0, 10.0, 0.01) var skill1_hit_time := 0.75

@export_category("Block Skill")
# E: cancels one incoming damage event, then cannot be used for two seconds.
@export var block_animation: StringName = &"block"
@export_range(0.05, 5.0, 0.01) var block_duration := 0.45
@export_range(0.1, 60.0, 0.1) var block_cooldown := 2.0

@export_category("Hurt and Death")
@export var hurt_duration := 0.3
@export var death_duration := 0.8

var attack2_cooldown_left := 0.0
var block_cooldown_left := 0.0
var is_casting_skill1 := false
var is_blocking := false


func _ready() -> void:
	super()
	add_to_group(&"player")


# _input receives gameplay controls before a non-interactive HUD can consume them.
func _input(event: InputEvent) -> void:
	if is_busy():
		return

	# Input Map names: skill1 = Q, skill2 = E, attack = left-click, attack2 = right-click.
	if InputMap.has_action(&"skill1") and event.is_action_pressed(&"skill1"):
		start_skill1()
		return

	# Knight's generic Skill 2 input plays its block-specific ability/animation.
	if InputMap.has_action(&"skill2") and event.is_action_pressed(&"skill2"):
		start_block()
		return

	if InputMap.has_action(&"attack2") and event.is_action_pressed(&"attack2"):
		start_attack2_combo()
		return

	if event.is_action_pressed(&"attack"):
		start_melee_attack(&"attack", attack_damage, &"enemy", attack_cooldown)


func _physics_process(delta: float) -> void:
	# Cooldowns keep counting down while the Knight is moving or casting.
	attack2_cooldown_left = maxf(0.0, attack2_cooldown_left - delta)
	block_cooldown_left = maxf(0.0, block_cooldown_left - delta)

	if is_dead:
		return

	if is_busy():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# These actions are already set to WASD in project.godot.
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	set_facing_from_x(direction.x)
	velocity = direction * speed
	move_and_slide()
	update_idle_or_walk_animation()


# Q: the Knight cannot be interrupted, but can still lose health while casting.
func start_skill1() -> void:
	var token := begin_attack(skill_animation)
	if token < 0:
		return

	var animation_duration := get_animation_duration(skill_animation)
	if animation_duration <= 0.0:
		# The heavy strike still works while its artwork is being set up.
		push_warning("Knight Q has no animation named \"%s\"; the skill will still work." % skill_animation)

	# The cast lasts at least this long, even if the sprite animation is shorter.
	var cast_duration := maxf(skill1_cast_time, animation_duration)
	var hit_time := clampf(skill1_hit_time, 0.0, cast_duration)
	is_casting_skill1 = true

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		is_casting_skill1 = false
		return

	deal_melee_damage(skill1_damage, &"enemy")

	await wait_for_gameplay_time(cast_duration - hit_time).timeout
	is_casting_skill1 = false
	finish_attack(token)


# E: blocks exactly one incoming hit during the block animation.
func start_block() -> void:
	if block_cooldown_left > 0.0:
		return

	var token := begin_attack(block_animation)
	if token < 0:
		return

	var animation_duration := get_animation_duration(block_animation)
	if animation_duration <= 0.0:
		# Blocking remains functional even while its artwork is being set up.
		push_warning("Knight E has no animation named \"%s\"; the block will still work." % block_animation)

	is_blocking = true
	# The block remains active for at least this long, even with a short animation.
	var block_window := maxf(block_duration, animation_duration)

	await wait_for_gameplay_time(block_window).timeout
	if token == _attack_token:
		# If no hit used the block, its window simply expires and starts cooldown.
		if is_blocking:
			is_blocking = false
			block_cooldown_left = block_cooldown
		finish_attack(token)


# Plays the two-swing animation, but applies one total damage event.
func start_attack2_combo() -> void:
	if attack2_cooldown_left > 0.0:
		return

	var token := begin_attack(&"attack2")
	if token < 0:
		return

	var attack_duration := get_animation_duration(&"attack2")
	if attack_duration <= 0.0:
		push_warning("The Knight needs a non-empty animation named attack2.")
		finish_attack(token)
		return

	# The cooldown starts when the combo begins, even if an enemy interrupts it.
	attack2_cooldown_left = attack2_cooldown
	var hit_time := clampf(attack2_hit_time, 0.0, attack_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return
	# The enemy plays hurt once while the rest of the combo animation continues.
	deal_melee_damage(attack2_total_damage, &"enemy")

	await wait_for_gameplay_time(attack_duration - hit_time).timeout
	finish_attack(token)


# Block consumes one hit before the shared combat script can remove health.
func take_damage(damage: int) -> void:
	if is_dead or damage <= 0:
		return

	if is_blocking:
		is_blocking = false
		# The two-second cooldown begins after the block absorbs one hit.
		block_cooldown_left = block_cooldown
		# Also absorbs any overlapping damage checks from the same instant.
		_start_damage_invulnerability()
		return

	if is_casting_skill1:
		# Q loses health normally, but does not play hurt or cancel the cast.
		if is_damage_invulnerable:
			return

		set_health(health - damage)
		if health == 0:
			is_casting_skill1 = false
			die()
			return

		_start_damage_invulnerability()
		return

	super(damage)


func get_max_health() -> int:
	return max_health


func get_hurt_duration() -> float:
	return hurt_duration


func get_death_duration() -> float:
	return death_duration

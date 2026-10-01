extends Combatant

# Scene setup expected by this script:
# archer (CharacterBody2D)
# ├── AnimatedSprite2D
# └── CollisionShape2D
#
# Your arrow is a separate arrow.tscn scene. Its root must be an Area2D
# with arrow.gd attached, plus a Sprite2D and CollisionShape2D as children.

@export_category("Movement")
@export var speed := 135.0

@export_category("Health")
@export var max_health := 4

@export_category("Arrow Projectile")
# Drag your separate arrow.tscn (whose root is an Area2D) into this slot.
@export var arrow_scene: PackedScene
# Position where every newly-created arrow begins, relative to the Archer.
@export var arrow_spawn_offset := Vector2(26.0, -4.0)

@export_category("Attack 1 - Basic Arrow")
@export var basic_attack_damage := 1
@export_range(0.1, 5.0, 0.01) var basic_attack_cooldown := 0.45
@export_range(0.0, 5.0, 0.01) var basic_arrow_release_time := 0.18

@export_category("Attack 2 - Heavy Arrow")
@export var heavy_attack_damage := 3
@export_range(0.1, 5.0, 0.01) var heavy_attack_cooldown := 1.1
@export_range(0.0, 5.0, 0.01) var heavy_arrow_release_time := 0.35
@export_range(1.0, 3.0, 0.05) var heavy_arrow_scale := 1.35

@export_category("Skill 1 - Dash")
# Q: no special animation needed; it reuses the walk animation.
@export var dash_speed := 420.0
@export_range(0.05, 2.0, 0.01) var dash_duration := 0.18
@export_range(0.1, 20.0, 0.1) var dash_cooldown := 1.5

@export_category("Skill 2 - Strengthen Basic Arrow")
# E: empowers the next basic arrow only. Heavy arrows are unchanged.
@export var strength_bonus_damage := 2
@export_range(0.1, 30.0, 0.1) var strength_duration := 6.0
@export_range(0.1, 60.0, 0.1) var strength_cooldown := 8.0
@export_range(1.0, 3.0, 0.05) var strengthened_arrow_scale := 1.2

@export_category("Hurt and Death")
@export var hurt_duration := 0.3
@export var death_duration := 0.8

var basic_attack_cooldown_left := 0.0
var heavy_attack_cooldown_left := 0.0
var dash_cooldown_left := 0.0
var dash_time_left := 0.0
var dash_direction := Vector2.ZERO
var is_dashing := false

var is_strengthened := false
var strength_time_left := 0.0
var strength_cooldown_left := 0.0


func _ready() -> void:
	super()
	add_to_group(&"player")

	if arrow_scene == null:
		push_warning("Assign your arrow.tscn Area2D scene to Arrow Scene in the Inspector.")


# Archer attacks are projectiles, so it does not need a melee player_hitbox.
func requires_attack_hitbox() -> bool:
	return false


func _input(event: InputEvent) -> void:
	if is_busy() or is_dashing:
		return

	# Generic inputs: skill1 = Q (dash), skill2 = E (strengthen).
	if InputMap.has_action(&"skill1") and event.is_action_pressed(&"skill1"):
		start_dash()
		return

	if InputMap.has_action(&"skill2") and event.is_action_pressed(&"skill2"):
		start_strengthen()
		return

	if InputMap.has_action(&"attack2") and event.is_action_pressed(&"attack2"):
		start_heavy_attack()
		return

	if event.is_action_pressed(&"attack"):
		start_basic_attack()


func _physics_process(delta: float) -> void:
	basic_attack_cooldown_left = maxf(0.0, basic_attack_cooldown_left - delta)
	heavy_attack_cooldown_left = maxf(0.0, heavy_attack_cooldown_left - delta)
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	strength_cooldown_left = maxf(0.0, strength_cooldown_left - delta)

	if is_strengthened:
		strength_time_left -= delta
		if strength_time_left <= 0.0:
			is_strengthened = false

	if is_dead:
		return

	if is_dashing:
		dash_time_left -= delta
		velocity = dash_direction * dash_speed
		# Dash deliberately reuses walk because there is no dash animation.
		play_animation(&"walk")
		move_and_slide()

		if dash_time_left <= 0.0:
			is_dashing = false
			velocity = Vector2.ZERO
			update_idle_or_walk_animation()
		return

	if is_busy():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	set_facing_from_x(direction.x)
	velocity = direction * speed
	move_and_slide()
	update_idle_or_walk_animation()


# Left-click: fires one basic arrow. E increases this arrow's damage once.
func start_basic_attack() -> void:
	if basic_attack_cooldown_left > 0.0:
		return

	var token := begin_attack(&"attack1")
	if token < 0:
		return

	basic_attack_cooldown_left = basic_attack_cooldown
	var attack_duration := maxf(basic_attack_cooldown, get_animation_duration(&"attack1"))
	var release_time := clampf(basic_arrow_release_time, 0.0, attack_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	var damage := basic_attack_damage
	var arrow_scale := 1.0

	# E is consumed only when a basic arrow is truly released.
	if is_strengthened:
		damage += strength_bonus_damage
		arrow_scale = strengthened_arrow_scale
		is_strengthened = false
		strength_time_left = 0.0

	fire_arrow(damage, arrow_scale)

	await wait_for_gameplay_time(attack_duration - release_time).timeout
	finish_attack(token)


# Right-click: fires a stronger, larger arrow. It does not consume E's buff.
func start_heavy_attack() -> void:
	if heavy_attack_cooldown_left > 0.0:
		return

	var token := begin_attack(&"attack2")
	if token < 0:
		return

	heavy_attack_cooldown_left = heavy_attack_cooldown
	var attack_duration := maxf(heavy_attack_cooldown, get_animation_duration(&"attack2"))
	var release_time := clampf(heavy_arrow_release_time, 0.0, attack_duration)

	await wait_for_gameplay_time(release_time).timeout
	if not is_attack_token_active(token):
		return

	fire_arrow(heavy_attack_damage, heavy_arrow_scale)

	await wait_for_gameplay_time(attack_duration - release_time).timeout
	finish_attack(token)


# Q: dash in the current WASD direction, or forward when standing still.
func start_dash() -> void:
	if dash_cooldown_left > 0.0 or is_busy():
		return

	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if direction.is_zero_approx():
		direction = Vector2(facing_direction, 0.0)

	dash_direction = direction.normalized()
	set_facing_from_x(dash_direction.x)
	is_dashing = true
	dash_time_left = dash_duration
	dash_cooldown_left = dash_cooldown


# E: empowers the next basic arrow. It uses no animation.
func start_strengthen() -> void:
	if strength_cooldown_left > 0.0 or is_busy():
		return

	is_strengthened = true
	strength_time_left = strength_duration
	strength_cooldown_left = strength_cooldown


# Creates a fresh copy of the separate arrow.tscn scene and launches it.
func fire_arrow(damage: int, arrow_scale: float = 1.0) -> void:
	if arrow_scene == null:
		push_warning("The Archer needs an arrow.tscn assigned to Arrow Scene.")
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var arrow := arrow_scene.instantiate() as Area2D
	if arrow == null:
		push_warning("Arrow Scene must have an Area2D as its root node.")
		return
	if not arrow.has_method(&"launch"):
		push_error("The root Area2D of arrow.tscn needs Scripts/arrow.gd attached.")
		arrow.queue_free()
		return

	scene_root.add_child(arrow)

	var direction := Vector2(facing_direction, 0.0)
	var spawn_position := global_position + Vector2(
		arrow_spawn_offset.x * facing_direction,
		arrow_spawn_offset.y
	)

	arrow.global_position = spawn_position
	arrow.scale *= arrow_scale
	arrow.call(&"launch", direction, damage, &"enemy", self)


# Taking damage interrupts a dash, but the dash has no invulnerability by default.
func take_damage(damage: int) -> void:
	is_dashing = false
	super(damage)


func get_max_health() -> int:
	return max_health


func get_hurt_duration() -> float:
	return hurt_duration


func get_death_duration() -> float:
	return death_duration

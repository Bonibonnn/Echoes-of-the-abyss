extends Area2D

@export_range(1.0, 2000.0, 1.0, "suffix:px/s") var speed := 430.0
@export_range(1.0, 2000.0, 1.0, "suffix:px") var max_distance := 450.0
@export_flags_2d_physics var hit_collision_mask := 1
@export var flight_animation: StringName = &"fly"
@export var impact_animation: StringName = &"impact"
@export var art_rotation_offset := 0.0

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D

var _is_flying := false
var _direction := Vector2.RIGHT
var _impact_damage := 1
var _target_group: StringName = &"enemy"
var _shooter: Node2D
var _distance_travelled := 0.0
var _burn_duration := 0.0
var _burn_damage_per_tick := 1
var _burn_tick_interval := 1.0
var _burn_tint := Color(1.0, 0.38, 0.06, 1.0)


func _ready() -> void:
	monitoring = true
	collision_mask = hit_collision_mask

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


# Called by mage.gd. The burn settings are passed in so all Mage skills use
# the same Inspector values.
func launch(
	flight_direction: Vector2,
	impact_damage: int,
	target_group: StringName,
	shooter: Node2D,
	burn_duration: float,
	burn_damage_per_tick: int,
	burn_tick_interval: float,
	burn_tint: Color
) -> void:
	_direction = flight_direction.normalized()
	if _direction.is_zero_approx():
		queue_free()
		return

	rotation = _direction.angle() + art_rotation_offset
	_impact_damage = impact_damage
	_target_group = target_group
	_shooter = shooter
	_burn_duration = burn_duration
	_burn_damage_per_tick = burn_damage_per_tick
	_burn_tick_interval = burn_tick_interval
	_burn_tint = burn_tint
	_distance_travelled = 0.0
	_is_flying = true
	play_flight_animation()


func _physics_process(delta: float) -> void:
	if not _is_flying:
		return

	var movement := _direction * speed * delta
	global_position += movement
	_distance_travelled += movement.length()

	# Frames 4 and 5 are reserved for a real enemy impact only.
	if _distance_travelled >= max_distance:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not _is_flying or body == _shooter:
		return

	# Walls and non-enemy bodies remove the fireball without playing impact.
	if not body.is_in_group(_target_group) or not body.has_method(&"take_damage"):
		queue_free()
		return

	# A fireball can affect exactly one enemy.
	_is_flying = false
	monitoring = false
	body.call(&"take_damage", _impact_damage)

	# Only the enemy that the fireball actually touched receives burn.
	if body.has_method(&"apply_burn"):
		body.call(
			&"apply_burn",
			_burn_duration,
			_burn_damage_per_tick,
			_burn_tick_interval,
			_burn_tint
		)

	await play_impact_animation()


func play_flight_animation() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(flight_animation):
		push_warning("Add a SpriteFrames animation named '%s' with source frames 0-3." % String(flight_animation))
		return

	# The flight animation is the only animation used before an enemy is hit.
	animated_sprite.sprite_frames.set_animation_loop_mode(
		flight_animation,
		SpriteFrames.LOOP_LINEAR
	)
	animated_sprite.play(flight_animation)
	animated_sprite.frame = 0
	animated_sprite.frame_progress = 0.0


func play_impact_animation() -> void:
	var lifetime := 0.1

	if animated_sprite != null and animated_sprite.sprite_frames != null:
		if animated_sprite.sprite_frames.has_animation(impact_animation):
			# These are source frames 4 and 5 only, and they play exactly once.
			animated_sprite.sprite_frames.set_animation_loop_mode(
				impact_animation,
				SpriteFrames.LOOP_NONE
			)
			animated_sprite.play(impact_animation)
			animated_sprite.frame = 0
			animated_sprite.frame_progress = 0.0

			var speed_value := animated_sprite.sprite_frames.get_animation_speed(impact_animation)
			if speed_value > 0.0:
				lifetime = float(animated_sprite.sprite_frames.get_frame_count(impact_animation)) / speed_value
		else:
			push_warning("Add a SpriteFrames animation named '%s' with source frames 4-5." % String(impact_animation))

	await get_tree().create_timer(maxf(0.1, lifetime), false, true).timeout
	queue_free()

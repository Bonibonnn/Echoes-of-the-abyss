extends Area2D

# A short-lived damaging line left behind by the Werewolf's dash. Its collision
# shape grows from the dash start to the real end position each physics frame.

@onready var collision_shape := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
@onready var trail_line := get_node_or_null(^"Line2D") as Line2D

var _shape: RectangleShape2D
var _damage := 1
var _tick_interval := 0.4
var _tick_time_left := 0.0
var _trail_width := 18.0
var _lifetime := 0.65
var _can_damage := false
var _is_finishing := false


func _ready() -> void:
	monitoring = true
	if collision_shape == null or not (collision_shape.shape is RectangleShape2D):
		push_error("The Werewolf dash trail needs a RectangleShape2D child.")
		return

	# Each active trail must own its shape because its length changes every frame.
	_shape = (collision_shape.shape as RectangleShape2D).duplicate() as RectangleShape2D
	collision_shape.shape = _shape


# Called immediately after the trail is added beside the Werewolf in the map.
func begin_trail(
	start_position: Vector2,
	damage: int,
	interval: float,
	new_trail_width: float,
	lifetime: float
) -> void:
	_damage = maxi(0, damage)
	_tick_interval = maxf(0.05, interval)
	_trail_width = maxf(1.0, new_trail_width)
	_lifetime = maxf(0.0, lifetime)
	global_position = start_position
	global_rotation = 0.0
	update_trail_end(start_position)
	call_deferred(&"_enable_damage_after_physics_frame")


# Keeps the Area2D and visible red line aligned with the travelled dash path.
func update_trail_end(end_position: Vector2) -> void:
	if _shape == null:
		return

	var path := end_position - global_position
	var length := maxf(path.length(), 4.0)
	if not path.is_zero_approx():
		global_rotation = path.angle()

	_shape.size = Vector2(length + _trail_width, _trail_width)
	collision_shape.position = Vector2(length * 0.5, 0.0)
	if trail_line != null:
		trail_line.width = maxf(2.0, _trail_width * 0.45)
		trail_line.points = PackedVector2Array([Vector2.ZERO, Vector2(length, 0.0)])


func _physics_process(delta: float) -> void:
	if not _can_damage or _damage <= 0:
		return

	_tick_time_left -= delta
	if _tick_time_left > 0.0:
		return
	_tick_time_left = _tick_interval

	for body in get_overlapping_bodies():
		if not is_instance_valid(body) or not (body is Node2D):
			continue

		var target := body as Node2D
		if target.is_queued_for_deletion():
			continue
		if target.is_in_group(&"player") and target.has_method(&"take_damage"):
			target.call(&"take_damage", _damage)


# Wait one physics frame before querying overlaps; a brand-new Area2D has no
# reliable overlap list until it has entered the physics world.
func _enable_damage_after_physics_frame() -> void:
	await get_tree().physics_frame
	if not is_queued_for_deletion():
		_can_damage = true


# The final dash path remains briefly, then cleans itself up.
func finish_trail() -> void:
	if _is_finishing:
		return

	_is_finishing = true
	await get_tree().create_timer(_lifetime, false, true).timeout
	queue_free()

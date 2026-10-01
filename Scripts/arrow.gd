extends Area2D

# The Archer creates a new arrow.tscn every time it fires.

@export_range(1.0, 2000.0, 1.0, "suffix:px/s") var speed := 550.0
@export_range(1.0, 2000.0, 1.0, "suffix:px") var max_distance := 500.0
@export_flags_2d_physics var hit_collision_mask := 1
# Arrow02 points right by default, so leave this at 0.0.
@export var art_rotation_offset := 0.0

var _is_flying := false
var _direction := Vector2.RIGHT
var _damage := 1
var _target_group: StringName = &"enemy"
var _distance_travelled := 0.0
var _shooter: Node2D


func _ready() -> void:
	# Area2D must monitor bodies for its body_entered signal to work.
	monitoring = true
	collision_mask = hit_collision_mask

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func launch(
	flight_direction: Vector2,
	damage: int,
	target_group: StringName,
	shooter: Node2D
) -> void:
	_direction = flight_direction.normalized()
	if _direction.is_zero_approx():
		queue_free()
		return

	rotation = _direction.angle() + art_rotation_offset
	_damage = damage
	_target_group = target_group
	_shooter = shooter
	_distance_travelled = 0.0
	_is_flying = true


func _physics_process(delta: float) -> void:
	if not _is_flying:
		return

	var movement := _direction * speed * delta
	global_position += movement
	_distance_travelled += movement.length()

	if _distance_travelled >= max_distance:
		queue_free()


# Called when the Area2D touches a CharacterBody2D, StaticBody2D, etc.
func _on_body_entered(body: Node2D) -> void:
	# Do not let the arrow hit the Archer who fired it.
	if not _is_flying or body == _shooter:
		return

	# A single arrow can only damage one body.
	_is_flying = false

	if body.is_in_group(_target_group) and body.has_method(&"take_damage"):
		body.call(&"take_damage", _damage)

	# The arrow is spent after it reaches an enemy, wall, or other body.
	queue_free()

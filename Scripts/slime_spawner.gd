extends Area2D

# A one-time map trap that creates a Slime at every child Marker2D named
# spawn_point, spawn_point2, and so on when a player enters this Area2D.

@export var slime_scene: PackedScene
@export var spawn_once := true

var has_spawned := false
var spawn_points: Array[Marker2D] = []


func _ready() -> void:
	# Find every marker that belongs to this trap. This supports any number of
	# points without changing the script again.
	for node in find_children("*", "Marker2D", true, false):
		if node is Marker2D and node.name.to_lower().begins_with("spawn_point"):
			spawn_points.append(node)

	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		spawn_slimes()


func spawn_slimes() -> void:
	if slime_scene == null or (spawn_once and has_spawned):
		return

	if spawn_points.is_empty():
		spawn_slime_at(global_position)
	else:
		for point in spawn_points:
			spawn_slime_at(point.global_position)

	has_spawned = true


func spawn_slime_at(spawn_position: Vector2) -> void:
	var slime := slime_scene.instantiate() as Node2D
	if slime == null:
		push_error("Slime Scene must have a Node2D root.")
		return

	# Put spawned enemies beside this trap under World, not inside the Area2D.
	var spawn_parent := get_parent()
	if spawn_parent == null:
		return

	spawn_parent.add_child(slime)
	slime.global_position = spawn_position

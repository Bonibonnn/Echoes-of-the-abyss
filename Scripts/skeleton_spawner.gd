extends Area2D

@export var skeleton_scene: PackedScene
@export var spawn_once := true

var has_spawned := false
var spawn_points: Array[Marker2D] = []


func _ready() -> void:
	# Every Marker2D whose name starts with spawn_point becomes one spawn location.
	for node in find_children("*", "Marker2D", true, false):
		if node is Marker2D and node.name.to_lower().begins_with("spawn_point"):
			spawn_points.append(node)

	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		spawn_skeletons()


func spawn_skeletons() -> void:
	if skeleton_scene == null or (spawn_once and has_spawned):
		return

	if spawn_points.is_empty():
		spawn_skeleton_at(global_position)
	else:
		for point in spawn_points:
			spawn_skeleton_at(point.global_position)

	has_spawned = true


func spawn_skeleton_at(spawn_position: Vector2) -> void:
	var skeleton := skeleton_scene.instantiate() as Node2D
	if skeleton == null:
		push_error("Skeleton Scene must have a Node2D root.")
		return

	# Spawn beside this area so it works in any map scene, not just the current root.
	var spawn_parent := get_parent()
	if spawn_parent == null:
		return

	spawn_parent.add_child(skeleton)
	skeleton.global_position = spawn_position

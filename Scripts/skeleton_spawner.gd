extends Area2D

@export var skeleton_scene: PackedScene
@export var spawn_once := true

var has_spawned := false
var spawn_points: Array[Marker2D] = []


func _ready() -> void:
	for node in find_children("*", "Marker2D", true, false):
		if node is Marker2D and node.name.to_lower().begins_with("spawn_point"):
			spawn_points.append(node)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name.to_lower() == "player":
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

	get_tree().current_scene.add_child(skeleton)
	skeleton.global_position = spawn_position

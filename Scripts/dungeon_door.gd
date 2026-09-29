extends Area2D

@export_file("*.tscn") var destination_scene := ""
@export var player_spawn_path: NodePath = ^"player_spawn"

var is_transitioning := false

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


# Carries the selected player (and its Camera2D) into the next map.
func _on_body_entered(body: Node2D) -> void:
	if is_transitioning or not body.is_in_group(&"player") or destination_scene.is_empty():
		return

	var packed_scene := ResourceLoader.load(destination_scene) as PackedScene
	var destination := packed_scene.instantiate() as Node2D if packed_scene != null else null
	if destination == null:
		push_error("Destination Scene must point to a Node2D scene.")
		return

	var spawn := destination.get_node_or_null(player_spawn_path) as Node2D
	var default_player := destination.get_node_or_null(^"player") as Node2D
	var spawn_position := default_player.position if default_player != null else body.position
	if spawn != null:
		spawn_position = destination.to_local(spawn.global_position)
	if default_player != null:
		default_player.free()

	var old_parent := body.get_parent()
	var old_global_position := body.global_position
	is_transitioning = true
	old_parent.remove_child(body)
	destination.add_child(body)
	body.position = spawn_position

	# change_scene_to_node keeps the prepared destination and frees the old map.
	var change_error := get_tree().change_scene_to_node(destination)
	if change_error != OK:
		destination.remove_child(body)
		old_parent.add_child(body)
		body.global_position = old_global_position
		is_transitioning = false
		push_error("Could not load the destination scene. Error code: %s" % change_error)

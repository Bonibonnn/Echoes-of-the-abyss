extends Control

@export_category("Knight Selection")
@export var world_scene: PackedScene
@export var knight_scene: PackedScene
@export var player_spawn_path: NodePath = ^"player_spawn"

@onready var knight_button: BaseButton = find_child("knight_button", true, false) as BaseButton

var is_loading := false


func _ready() -> void:
	if knight_button == null:
		push_error("Rename the Knight button node to knight_button.")
		return

	# Connect once so reopening this scene cannot add duplicate button signals.
	if not knight_button.pressed.is_connected(_on_knight_button_pressed):
		knight_button.pressed.connect(_on_knight_button_pressed)


func _on_knight_button_pressed() -> void:
	if is_loading:
		return

	if world_scene == null:
		push_error("Assign world.tscn to World Scene on the character-select UI.")
		return

	if knight_scene == null:
		push_error("Assign player.tscn to Knight Scene on the character-select UI.")
		return

	var world := world_scene.instantiate()
	var knight := knight_scene.instantiate() as Node2D
	if knight == null:
		push_error("Knight Scene needs a Node2D root, such as CharacterBody2D.")
		return

	world.add_child(knight)

	var player_spawn := world.get_node_or_null(player_spawn_path) as Node2D
	if player_spawn != null:
		knight.global_position = player_spawn.global_position
	else:
		push_warning("Add a Marker2D named player_spawn to the world, or change Player Spawn Path.")

	# Godot 4.7 safely swaps in a scene that was prepared off-tree.
	is_loading = true
	var change_error := get_tree().change_scene_to_node(world)
	if change_error != OK:
		is_loading = false
		push_error("Could not load the world scene. Error code: %s" % change_error)

extends Control

# Attach this script to the root of your character-selection UI scene.
# Then assign the two scene files in the Inspector.

@export_category("Knight Selection")
@export var world_scene: PackedScene
@export var knight_scene: PackedScene
@export var player_spawn_path: NodePath = ^"player_spawn"

@onready var knight_button: BaseButton = find_child("knight_button", true, false) as BaseButton

var is_loading := false


func _ready() -> void:
	if knight_button == null:
		push_error("Rename your Knight Character button node to 'knight_button'.")
		return

	if not knight_button.pressed.is_connected(_on_knight_button_pressed):
		knight_button.pressed.connect(_on_knight_button_pressed)


func _on_knight_button_pressed() -> void:
	if is_loading:
		return

	if world_scene == null:
		push_error("Assign your world .tscn file to World Scene on the character-select UI.")
		return

	if knight_scene == null:
		push_error("Assign your Knight/player .tscn file to Knight Scene on the character-select UI.")
		return

	var world := world_scene.instantiate()
	var knight := knight_scene.instantiate() as Node2D
	if knight == null:
		push_error("Knight Scene must have a Node2D-based root, such as CharacterBody2D.")
		return

	is_loading = true
	world.add_child(knight)

	var player_spawn := world.get_node_or_null(player_spawn_path) as Node2D
	if player_spawn != null:
		knight.global_position = player_spawn.global_position
	else:
		push_warning("Add a Marker2D named 'player_spawn' to the world, or change Player Spawn Path.")

	var old_scene := get_tree().current_scene
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if is_instance_valid(old_scene):
		old_scene.queue_free()

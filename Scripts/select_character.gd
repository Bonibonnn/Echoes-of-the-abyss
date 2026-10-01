extends Control

# These are the four playable character scenes used by your selection screen.
@export_category("Character Selection Scenes")
@export var world_scene: PackedScene = preload("res://Scenes/world.tscn")
@export var knight_scene: PackedScene = preload("res://Scenes/player.tscn")
@export var archer_scene: PackedScene = preload("res://Scenes/archer.tscn")
@export var mage_scene: PackedScene = preload("res://Scenes/mage.tscn")
@export var priest_scene: PackedScene = preload("res://Scenes/priest.tscn")
@export var player_spawn_path: NodePath = ^"player_spawn"

# These paths match the button names in select-character.tscn exactly.
@onready var knight_button := get_node_or_null(^"Knight Button") as BaseButton
@onready var archer_button := get_node_or_null(^"Archer Button") as BaseButton
@onready var mage_button := get_node_or_null(^"Wizard Button") as BaseButton
@onready var priest_button := get_node_or_null(^"Priest Button") as BaseButton

# Stops accidental double-clicks from loading more than one world.
var is_loading := false


func _ready() -> void:
	connect_character_button(knight_button, knight_scene, "Knight")
	connect_character_button(archer_button, archer_scene, "Archer")
	connect_character_button(mage_button, mage_scene, "Mage")
	connect_character_button(priest_button, priest_scene, "Priest")


# Connects one character portrait button to its matching player scene.
func connect_character_button(button: BaseButton, character_scene: PackedScene, character_name: String) -> void:
	if button == null:
		push_error("Cannot find the %s button in select-character.tscn." % character_name)
		return

	if character_scene == null:
		push_error("Assign the %s Scene in the SelectCharacter Inspector." % character_name)
		button.disabled = true
		return

	var callback := select_character.bind(character_scene, character_name)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


# Creates the selected character in world.tscn at its player_spawn Marker2D.
func select_character(character_scene: PackedScene, character_name: String) -> void:
	if is_loading:
		return

	if world_scene == null:
		push_error("Assign world.tscn to World Scene in the SelectCharacter Inspector.")
		return

	var world := world_scene.instantiate() as Node2D
	var character := character_scene.instantiate() as Node2D
	if world == null or character == null:
		push_error("%s or world.tscn needs a Node2D root." % character_name)
		return

	world.add_child(character)
	var player_spawn := world.get_node_or_null(player_spawn_path) as Node2D
	if player_spawn == null:
		push_error("Add a Marker2D named player_spawn to world.tscn.")
		character.queue_free()
		world.queue_free()
		return

	character.global_position = player_spawn.global_position
	is_loading = true
	var change_error := get_tree().change_scene_to_node(world)
	if change_error != OK:
		is_loading = false
		push_error("Could not start as %s. Error code: %s" % [character_name, change_error])

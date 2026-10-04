extends Control

# This is the one controller for the visual Main Menu scene. It keeps the
# collaborator's existing Options panel while using the project's real scene paths.

@export_category("Menu Scenes")
@export_file("*.tscn") var select_character_scene: String = "res://select-character.tscn"
@export_file("*.tscn") var multiplayer_scene: String = ""

@onready var start_button: Button = get_node_or_null(^"Start Button") as Button
@onready var options_button: Button = get_node_or_null(^"Options Button") as Button
@onready var multiplayer_button: Button = get_node_or_null(^"Mutiplayer Button") as Button
@onready var quit_button: Button = get_node_or_null(^"Quit Button") as Button
@onready var options_panel: Control = get_node_or_null(^"Option") as Control

# Prevents two fast clicks from trying to open two scenes at the same time.
var is_changing_scene: bool = false


func _ready() -> void:
	# Start with the main buttons visible and the built-in Options panel hidden.
	_show_main_menu()


# Starts the character-selection scene.
func _on_start_pressed() -> void:
	_open_menu_scene(select_character_scene, "Character selection")


# Opens the Options panel already included in main_menu.tscn.
func _on_options_pressed() -> void:
	_set_main_buttons_visible(false)
	if options_panel != null:
		options_panel.visible = true


# Multiplayer is intentionally left unassigned until its next LAN phase.
func _on_multiplayer_pressed() -> void:
	_open_menu_scene(multiplayer_scene, "Multiplayer")


# Closes the game.
func _on_quit_pressed() -> void:
	get_tree().quit()


# Returns from the Options panel to the main buttons.
func _on_back_pressed() -> void:
	_show_main_menu()


func _show_main_menu() -> void:
	if options_panel != null:
		options_panel.visible = false
	_set_main_buttons_visible(true)


func _set_main_buttons_visible(is_visible: bool) -> void:
	if start_button != null:
		start_button.visible = is_visible
	if options_button != null:
		options_button.visible = is_visible
	if multiplayer_button != null:
		multiplayer_button.visible = is_visible
	if quit_button != null:
		quit_button.visible = is_visible


# Changes scenes only when an assigned scene exists, so unfinished buttons do
# not cause a crash or a missing-file error.
func _open_menu_scene(scene_path: String, menu_name: String) -> void:
	if is_changing_scene:
		return

	if scene_path.is_empty():
		push_warning("%s is not set up yet." % menu_name)
		return

	if not ResourceLoader.exists(scene_path):
		push_error("Cannot find the %s scene: %s" % [menu_name, scene_path])
		return

	is_changing_scene = true
	var change_error: int = get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		is_changing_scene = false
		push_error("Could not open %s. Error code: %s" % [menu_name, change_error])

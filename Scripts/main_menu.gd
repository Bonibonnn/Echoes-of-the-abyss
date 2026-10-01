extends Control

# Assign future menu scenes in the Inspector once you create them.
@export_category("Menu Scenes")
@export_file("*.tscn") var select_character_scene: String = "res://select-character.tscn"
@export_file("*.tscn") var options_scene: String = ""
@export_file("*.tscn") var multiplayer_scene: String = ""

# Prevents double-clicks from trying to load two scenes at the same time.
var is_changing_scene := false


# Opens the character-selection screen when Start is pressed.
func _on_start_pressed() -> void:
	open_menu_scene(select_character_scene, "Character selection")


# Opens the future Options screen after you assign it in the Inspector.
func _on_options_pressed() -> void:
	open_menu_scene(options_scene, "Options")


# Opens the future Multiplayer screen after you assign it in the Inspector.
func _on_multiplayer_pressed() -> void:
	open_menu_scene(multiplayer_scene, "Multiplayer")


# Closes the game.
func _on_quit_pressed() -> void:
	get_tree().quit()


# Safely changes to an assigned menu scene and gives a useful debugger message
# if that scene has not been made yet.
func open_menu_scene(scene_path: String, menu_name: String) -> void:
	if is_changing_scene:
		return

	if scene_path.is_empty():
		push_warning("%s is not set up yet. Assign its scene in the MainMenu Inspector." % menu_name)
		return

	if not ResourceLoader.exists(scene_path):
		push_error("Cannot find the %s scene: %s" % [menu_name, scene_path])
		return

	is_changing_scene = true
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		is_changing_scene = false
		push_error("Could not open %s. Error code: %s" % [menu_name, change_error])

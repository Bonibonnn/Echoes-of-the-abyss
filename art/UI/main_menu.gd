extends Control

@export_file("*.tscn") var select_character_scene := "res://select character.tscn"


# Opens the active character-selection scene.
func _on_start_pressed() -> void:
	if select_character_scene.is_empty():
		push_error("Assign select character.tscn to Select Character Scene.")
		return

	get_tree().change_scene_to_file(select_character_scene)


func _on_options_pressed() -> void:
	pass


func _on_quit_pressed() -> void:
	get_tree().quit()

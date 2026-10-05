extends Control

# Controls the collaborator-made Death screen. Restart rebuilds the previous
# map with the same selected character; Quit closes the application.

@onready var restart_button := get_node_or_null(^"Panel/Restart") as Button
@onready var quit_button := get_node_or_null(^"Panel/Quit") as Button


func _ready() -> void:
	get_tree().paused = false

	if restart_button != null and not restart_button.pressed.is_connected(_on_restart_pressed):
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button != null and not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)


func _on_restart_pressed() -> void:
	GameFlow.restart_current_map()


func _on_quit_pressed() -> void:
	get_tree().quit()

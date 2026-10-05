extends Control

# The Victory screen has one exit: return to the main menu.

@onready var home_button := get_node_or_null(^"Panel/Home") as Button


func _ready() -> void:
	get_tree().paused = false

	if home_button != null and not home_button.pressed.is_connected(_on_home_pressed):
		home_button.pressed.connect(_on_home_pressed)


func _on_home_pressed() -> void:
	GameFlow.return_home()

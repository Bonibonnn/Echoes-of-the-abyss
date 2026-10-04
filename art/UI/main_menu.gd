extends Control

@export_file("*.tscn") var select_character_scene := "res://select character.tscn"

@onready var start_button: Button = $"Start Button"
@onready var options_button: Button = $"Options Button"
@onready var mutiplayer_button: Button = $"Mutiplayer Button"
@onready var quit_button: Button = $"Quit Button"
@onready var option: Panel = $Option


	
func _ready():
	start_button.visible = true
	options_button.visible = true
	mutiplayer_button.visible = true
	quit_button.visible = true
	option.visible = false

# Opens the active character-selection scene.
func _on_start_pressed() -> void:
	if select_character_scene.is_empty():
		push_error("Assign select character.tscn to Select Character Scene.")
		return
	
	get_tree().change_scene_to_file("res://art/UI/select character.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_options_button_pressed() -> void:
	print("Options Button") # Replace with function body.
	start_button.visible = false
	options_button.visible = false
	mutiplayer_button.visible = false
	quit_button.visible = false
	option.visible = true


func _on_back_pressed() -> void:
	_ready()

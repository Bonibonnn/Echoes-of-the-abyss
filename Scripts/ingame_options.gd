extends CanvasLayer

# A reusable pause menu for World and Dungeon.
# It changes display size, lowers only the Music bus,
# and can safely run while gameplay is paused.

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

@onready var options_button := get_node_or_null(^"Options") as Button
@onready var panel := get_node_or_null(^"Panel") as Panel
@onready var resume_button := get_node_or_null(^"Panel/Content/Resume") as Button
@onready var resolution_option := get_node_or_null(^"Panel/Content/ResolutionRow/Resolution") as OptionButton
@onready var music_slider := get_node_or_null(^"Panel/Content/MusicRow/Music") as HSlider
@onready var quit_button := get_node_or_null(^"Panel/Content/Quit") as Button
@onready var instructions := get_node_or_null(^"Panel/Content/Instructions") as Button

# Instruction Panel
@onready var panel_1 := get_node_or_null(^"Panel1") as Panel
@onready var back_button := get_node_or_null(^"Panel1/Back") as Button

var music_bus_id := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	music_bus_id = AudioServer.get_bus_index(&"Music")

	if music_bus_id < 0:
		push_warning("Add a Music bus to default_bus_layout.tres for the in-game volume slider.")

	_populate_resolution_options()
	_refresh_controls()

	# Hide both menus at the start
	close_options()

	# Options Button
	if options_button != null and not options_button.pressed.is_connected(open_options):
		options_button.pressed.connect(open_options)

	# Resume Button
	if resume_button != null and not resume_button.pressed.is_connected(close_options):
		resume_button.pressed.connect(close_options)

	# Resolution
	if resolution_option != null and not resolution_option.item_selected.is_connected(_on_resolution_selected):
		resolution_option.item_selected.connect(_on_resolution_selected)

	# Music
	if music_slider != null and not music_slider.value_changed.is_connected(_on_music_value_changed):
		music_slider.value_changed.connect(_on_music_value_changed)

	# Quit
	if quit_button != null and not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)

	# Instructions
	if instructions != null and not instructions.pressed.is_connected(_on_instructions_pressed):
		instructions.pressed.connect(_on_instructions_pressed)

	# Back Button from Instructions
	if back_button != null and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):

		# If Instructions is currently open,
		# ESC goes back to Options.
		if panel_1 != null and panel_1.visible:
			_on_back_pressed()

		# If Options is open, ESC closes it.
		elif panel != null and panel.visible:
			close_options()

		# Otherwise open Options.
		else:
			open_options()

		get_viewport().set_input_as_handled()


func open_options() -> void:
	_refresh_controls()

	# Make sure Instructions is hidden
	if panel_1 != null:
		panel_1.hide()

	# Show Options
	if panel != null:
		panel.show()

	# Hide Options button
	if options_button != null:
		options_button.hide()

	get_tree().paused = true


func close_options() -> void:
	get_tree().paused = false

	# Hide Options
	if panel != null:
		panel.hide()

	# Hide Instructions
	if panel_1 != null:
		panel_1.hide()

	# Show Options button again
	if options_button != null:
		options_button.show()


func _populate_resolution_options() -> void:
	if resolution_option == null or resolution_option.item_count > 0:
		return

	for resolution: Vector2i in RESOLUTIONS:
		resolution_option.add_item(
			"%d x %d" % [resolution.x, resolution.y]
		)


func _refresh_controls() -> void:
	_select_current_resolution()

	if music_slider != null and music_bus_id >= 0:
		var music_volume: float = db_to_linear(
			AudioServer.get_bus_volume_db(music_bus_id)
		)

		music_slider.set_value_no_signal(
			clampf(music_volume, 0.0, 1.0)
		)


func _select_current_resolution() -> void:
	if resolution_option == null:
		return

	var window_size: Vector2i = DisplayServer.window_get_size()

	for index: int in range(RESOLUTIONS.size()):
		if RESOLUTIONS[index] == window_size:
			resolution_option.select(index)
			return


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= RESOLUTIONS.size():
		return

	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED
	)

	DisplayServer.window_set_size(
		RESOLUTIONS[index]
	)


func _on_music_value_changed(new_value: float) -> void:
	if music_bus_id < 0:
		return

	AudioServer.set_bus_volume_db(
		music_bus_id,
		linear_to_db(maxf(new_value, 0.0001))
	)


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


# =========================
# INSTRUCTIONS
# =========================

func _on_instructions_pressed() -> void:
	# Hide Options Panel
	if panel != null:
		panel.hide()

	# Show Instructions Panel
	if panel_1 != null:
		panel_1.show()


func _on_back_pressed() -> void:
	# Hide Instructions Panel
	if panel_1 != null:
		panel_1.hide()

	# Show Options Panel again
	if panel != null:
		panel.show()

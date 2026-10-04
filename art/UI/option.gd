extends Panel


@export var resolution_option: OptionButton

func _ready():
	
	var resolutions = [
		Vector2i(1920, 1080),
		Vector2i(1600, 900),
		Vector2i(1280, 720),
		Vector2i(640,360),
		Vector2i(320,180)
	]
	for res in resolutions:
		resolution_option.add_item("%dx%d" % [res.x, res.y])
		
	load_current_settings()
	resolution_option.item_selected.connect(_on_resolution_selected)
		
func load_current_settings():
	var window_size = DisplayServer.window_get_size()
	for i in range(resolution_option.item_count):
		var res_text = resolution_option.get_item_text(i)
		var parts = res_text.split("x")
		if parts.size() == 2 and int(parts[0]) == window_size.x and int(parts[1]) == window_size.y:
			resolution_option.select(i)
			break

func _on_resolution_selected(index: int):
	var text = resolution_option.get_item_text(index)
	var parts = text.split("x")
	if parts.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))

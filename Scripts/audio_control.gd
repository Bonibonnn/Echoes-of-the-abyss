extends HSlider

@export var audio_bus_name: String

var audio_bus_id := -1


func _ready() -> void:
	# UI_music is an AudioStreamPlayer node, while Music is the actual bus.
	audio_bus_id = AudioServer.get_bus_index(audio_bus_name)
	if audio_bus_id < 0:
		push_warning("Audio bus not found: %s" % audio_bus_name)
		return

	value = db_to_linear(AudioServer.get_bus_volume_db(audio_bus_id))

func _on_value_changed(value: float) -> void:
	if audio_bus_id < 0:
		return

	# Avoid negative infinity when the slider is dragged all the way to zero.
	var db := linear_to_db(maxf(value, 0.0001))
	AudioServer.set_bus_volume_db(audio_bus_id, db)

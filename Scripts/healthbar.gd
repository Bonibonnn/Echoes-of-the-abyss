extends Control

@export_range(0.05, 2.0, 0.01) var health_change_time := 0.20

@onready var health_bar := get_node_or_null(^"CanvasLayer/health_bar") as ProgressBar

var player: Combatant
var health_tween: Tween


func _ready() -> void:
	if health_bar == null:
		push_error("Cannot find CanvasLayer/health_bar.")
		set_process(false)
		return

	health_bar.show_percentage = false
	health_bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END
	health_bar.min_value = 0.0
	health_bar.max_value = 1.0
	health_bar.value = 0.0

	call_deferred(&"find_player")


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		find_player()


func find_player() -> void:
	var found_player := get_tree().get_first_node_in_group(&"player") as Combatant
	if found_player == null or found_player == player:
		return

	player = found_player

	if not player.health_changed.is_connected(_on_health_changed):
		player.health_changed.connect(_on_health_changed)

	# Shows full health immediately when the character appears.
	health_bar.max_value = player.get_max_health()
	health_bar.value = player.health


func _on_health_changed(current_health: int, maximum_health: int) -> void:
	health_bar.max_value = maximum_health

	if health_tween != null and health_tween.is_valid():
		health_tween.kill()

	health_tween = create_tween()
	health_tween.tween_property(
		health_bar,
		"value",
		float(current_health),
		health_change_time
	)
# HUD should never capture mouse clicks or keyboard focus.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.focus_mode = Control.FOCUS_NONE

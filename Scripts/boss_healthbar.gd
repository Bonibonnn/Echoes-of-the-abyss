extends Control

# A reusable top-screen health bar for the scene's final boss.
@export var boss_group: StringName = &"final_boss"
@export var boss_display_name := "NECROMANCER"
@export_range(0.05, 2.0, 0.01, "suffix:s") var health_change_time := 0.20

@onready var boss_name_label := get_node_or_null(^"panel/boss_name") as Label
@onready var health_bar := get_node_or_null(^"panel/health_bar") as ProgressBar

var boss: Combatant
var health_tween: Tween


func _ready() -> void:
	# HUD controls must not block game input behind them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

	if boss_name_label == null or health_bar == null:
		push_error("Boss health bar needs panel/boss_name and panel/health_bar.")
		hide()
		set_process(false)
		return

	boss_name_label.text = boss_display_name
	boss_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar.focus_mode = Control.FOCUS_NONE
	health_bar.show_percentage = false
	health_bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END
	health_bar.min_value = 0.0
	health_bar.max_value = 1.0
	health_bar.value = 0.0
	hide()

	# The Necromancer joins final_boss during its own _ready(), so wait one frame.
	call_deferred(&"find_boss")


func _process(_delta: float) -> void:
	if not is_instance_valid(boss):
		find_boss()


func find_boss() -> void:
	var found_boss: Combatant = get_tree().get_first_node_in_group(boss_group) as Combatant
	if found_boss == null:
		hide()
		return
	if found_boss == boss:
		return

	boss = found_boss
	if not boss.health_changed.is_connected(_on_boss_health_changed):
		boss.health_changed.connect(_on_boss_health_changed)
	if not boss.died.is_connected(_on_boss_died):
		boss.died.connect(_on_boss_died)

	# Start full immediately when the boss enters the dungeon.
	health_bar.max_value = boss.get_max_health()
	health_bar.value = boss.health
	show()


func _on_boss_health_changed(current_health: int, maximum_health: int) -> void:
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


func _on_boss_died() -> void:
	# GameFlow changes to Victory after the death animation; hide the HUD at once.
	hide()

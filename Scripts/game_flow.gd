extends Node

# Persistent single-player flow. It remembers the active map and selected
# character so the Death screen can restart the real map, not the Death UI.

const MAIN_MENU_SCENE_PATH := "res://main_menu.tscn"
const DEATH_SCENE_PATH := "res://art/UI/DeathScenes.tscn"
const VICTORY_SCENE_PATH := "res://art/UI/VictoryScenes.tscn"
const WORLD_SCENE_PATH := "res://Scenes/world.tscn"
const DUNGEON_SCENE_PATH := "res://Scenes/dungeon.tscn"

var restart_scene_path := ""
var player_scene_path := ""
var is_transitioning := false


func _ready() -> void:
	# This singleton must keep working while the in-game Options panel pauses play.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)

	call_deferred("_watch_existing_combatants")


func _on_node_added(node: Node) -> void:
	# Player scripts add their groups during _ready(), so defer the connection
	# until that setup has finished.
	if node is Combatant:
		call_deferred("_watch_combatant", node)


func _watch_existing_combatants() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	_watch_combatant(scene_root)
	for child: Node in scene_root.find_children("*", "", true, false):
		_watch_combatant(child)


func _watch_combatant(node: Node) -> void:
	var combatant: Combatant = node as Combatant
	if combatant == null:
		return

	var callback: Callable = _on_combatant_died.bind(combatant)
	if not combatant.died.is_connected(callback):
		combatant.died.connect(callback)


func _on_combatant_died(combatant: Combatant) -> void:
	if is_transitioning or not _is_single_player_gameplay_scene():
		return

	if combatant.is_in_group(&"player"):
		show_death_after_animation(combatant)
	elif combatant.is_in_group(&"final_boss"):
		show_victory_after_animation(combatant)


func show_death_after_animation(player: Combatant) -> void:
	is_transitioning = true
	_remember_restart_state(player)
	await _wait_for_death_animation(player)
	get_tree().paused = false
	_change_scene(DEATH_SCENE_PATH)


func show_victory_after_animation(boss: Combatant) -> void:
	is_transitioning = true
	await _wait_for_death_animation(boss)
	get_tree().paused = false
	_change_scene(VICTORY_SCENE_PATH)


func restart_current_map() -> void:
	if is_transitioning:
		return

	if restart_scene_path.is_empty() or player_scene_path.is_empty():
		push_warning("No map and character are saved for Restart. Returning Home instead.")
		return_home()
		return

	var map_scene: PackedScene = load(restart_scene_path) as PackedScene
	var player_scene: PackedScene = load(player_scene_path) as PackedScene
	if map_scene == null or player_scene == null:
		push_error("Could not load the saved map or selected character for Restart.")
		return_home()
		return

	var new_map: Node2D = map_scene.instantiate() as Node2D
	var new_player: Node2D = player_scene.instantiate() as Node2D
	if new_map == null or new_player == null:
		push_error("Restart needs Node2D roots for both the map and character.")
		return_home()
		return

	# Maps normally contain no player, but remove one if a future map ships with
	# a default player before adding the saved selected character.
	var default_player := new_map.get_node_or_null(^"player") as Node
	if default_player != null:
		default_player.free()

	new_map.add_child(new_player)
	var spawn_point := new_map.get_node_or_null(^"player_spawn") as Node2D
	if spawn_point != null:
		new_player.global_position = spawn_point.global_position

	is_transitioning = true
	get_tree().paused = false
	var change_error: int = get_tree().change_scene_to_node(new_map)
	if change_error != OK:
		is_transitioning = false
		new_map.queue_free()
		push_error("Could not restart the map. Error code: %s" % change_error)
		return

	is_transitioning = false


func return_home() -> void:
	if is_transitioning:
		return

	is_transitioning = true
	restart_scene_path = ""
	player_scene_path = ""
	get_tree().paused = false
	_change_scene(MAIN_MENU_SCENE_PATH)


func _remember_restart_state(player: Combatant) -> void:
	var map_path := _current_gameplay_scene_path()
	if not map_path.is_empty():
		restart_scene_path = map_path

	if not player.scene_file_path.is_empty():
		player_scene_path = player.scene_file_path


func _wait_for_death_animation(combatant: Combatant) -> void:
	var wait_time: float = maxf(
		combatant.get_death_duration(),
		combatant.get_animation_duration(&"death")
	)
	await get_tree().create_timer(wait_time, true).timeout


func _is_single_player_gameplay_scene() -> bool:
	return not _current_gameplay_scene_path().is_empty()


func _current_gameplay_scene_path() -> String:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return ""

	var scene_path: String = current_scene.scene_file_path
	if scene_path == WORLD_SCENE_PATH or scene_path == DUNGEON_SCENE_PATH:
		return scene_path

	# change_scene_to_node() preserves the source scene path, but these fallbacks
	# keep Restart reliable if a map was created from a PackedScene at runtime.
	if current_scene.name == &"world":
		return WORLD_SCENE_PATH
	if current_scene.name == &"dungeon":
		return DUNGEON_SCENE_PATH

	return ""


func _change_scene(scene_path: String) -> void:
	var change_error: int = get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		is_transitioning = false
		push_error("Could not open scene: %s (error %s)" % [scene_path, change_error])
		return

	is_transitioning = false

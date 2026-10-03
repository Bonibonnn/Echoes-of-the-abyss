extends Area2D

@export_file("*.tscn") var destination_scene := ""
@export var player_spawn_path: NodePath = ^"player_spawn"

@export_category("Gatekeeper")
# Leave this off for ordinary doors. The World portal turns it on for the Elite Orc.
@export var starts_locked := false
@export var required_boss_path: NodePath
@export var portal_visual_path: NodePath
@export var locked_portal_color := Color(0.3, 0.3, 0.45, 1.0)

var is_transitioning := false
var is_locked := false
var _gatekeeper: Node
var _portal_visual: CanvasItem
var _portal_normal_modulate := Color.WHITE


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if not portal_visual_path.is_empty():
		_portal_visual = get_node_or_null(portal_visual_path) as CanvasItem
		if _portal_visual != null:
			_portal_normal_modulate = _portal_visual.modulate

	if starts_locked:
		lock_for_gatekeeper(get_node_or_null(required_boss_path))
	else:
		_set_portal_visual_locked(false)


# Locks this door until the given Combatant emits its shared died signal.
func lock_for_gatekeeper(boss: Node) -> void:
	is_locked = true
	_gatekeeper = boss
	_set_portal_visual_locked(true)

	if boss == null:
		push_warning("A locked dungeon door needs an assigned Gatekeeper.")
		return

	if boss.has_signal(&"died"):
		if not boss.is_connected(&"died", _on_gatekeeper_died):
			boss.connect(&"died", _on_gatekeeper_died)
	else:
		push_warning("The assigned Gatekeeper needs a died signal to unlock this door.")


# Opens the portal immediately after its gatekeeper has been defeated.
func unlock_gate() -> void:
	if not is_locked:
		return

	is_locked = false
	_gatekeeper = null
	_set_portal_visual_locked(false)

	# A player standing in the portal when the boss dies can enter right away.
	call_deferred("_transfer_waiting_player")


func _on_gatekeeper_died() -> void:
	unlock_gate()


func _set_portal_visual_locked(locked: bool) -> void:
	if _portal_visual == null:
		return

	_portal_visual.modulate = locked_portal_color if locked else _portal_normal_modulate


func _transfer_waiting_player() -> void:
	for body in get_overlapping_bodies():
		if body is Node2D:
			_on_body_entered(body)
			return


# Carries the selected player (and its Camera2D) into the next map.
func _on_body_entered(body: Node2D) -> void:
	if is_locked or is_transitioning or not body.is_in_group(&"player") or destination_scene.is_empty():
		return

	var packed_scene := ResourceLoader.load(destination_scene) as PackedScene
	var destination := packed_scene.instantiate() as Node2D if packed_scene != null else null
	if destination == null:
		push_error("Destination Scene must point to a Node2D scene.")
		return

	var spawn := destination.get_node_or_null(player_spawn_path) as Node2D
	var default_player := destination.get_node_or_null(^"player") as Node2D
	var spawn_position := default_player.position if default_player != null else body.position
	if spawn != null:
		spawn_position = destination.to_local(spawn.global_position)
	if default_player != null:
		default_player.free()

	var old_parent := body.get_parent()
	var old_global_position := body.global_position
	is_transitioning = true
	old_parent.remove_child(body)
	destination.add_child(body)
	body.position = spawn_position

	# change_scene_to_node keeps the prepared destination and frees the old map.
	var change_error := get_tree().change_scene_to_node(destination)
	if change_error != OK:
		destination.remove_child(body)
		old_parent.add_child(body)
		body.global_position = old_global_position
		is_transitioning = false
		push_error("Could not load the destination scene. Error code: %s" % change_error)

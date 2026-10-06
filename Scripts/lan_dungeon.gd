extends "res://Scripts/lan_knight_match.gd"

# Separate LAN dungeon wrapper. It inherits the finished dungeon artwork and
# collision map, removes only the local single-player systems, then runs the
# shared host-authoritative players and enemy roster.

@export var player_spawn_paths: Array[NodePath] = [
	^"lan_player_1_spawn",
	^"lan_player_2_spawn",
	^"lan_player_3_spawn",
	^"lan_player_4_spawn",
]

const SINGLE_PLAYER_ONLY_NODE_PATHS: Array[NodePath] = [
	^"enemies",
	^"random_skeleton_spawner",
	^"necromancer",
	^"ingame_options",
	^"CanvasLayer",
]

@onready var lan_necromancer: Node2D = get_node_or_null(^"lan_necromancer") as Node2D
@onready var boss_bar: ProgressBar = get_node_or_null(^"interface/boss_panel/boss_bar") as ProgressBar
@onready var boss_label: Label = get_node_or_null(^"interface/boss_panel/boss_label") as Label

var necromancer_defeated: bool = false


func _ready() -> void:
	_remove_single_player_dungeon_systems()
	super()


func _process(_delta: float) -> void:
	_refresh_boss_healthbar()


func _on_match_started(started_match_id: int) -> void:
	super(started_match_id)
	if match_is_active:
		necromancer_defeated = false
		_set_status("LAN Dungeon loaded. Defeat the Necromancer together.")


func _get_spawn_position(peer_id: int) -> Vector2:
	var peer_ids: PackedInt32Array = LanSession.get_connected_peer_ids()
	var spawn_index: int = peer_ids.find(peer_id)
	if spawn_index >= 0 and spawn_index < player_spawn_paths.size():
		var spawn_marker: Marker2D = get_node_or_null(player_spawn_paths[spawn_index]) as Marker2D
		if spawn_marker != null:
			return spawn_marker.global_position

	var original_spawn: Marker2D = get_node_or_null(^"player_spawn") as Marker2D
	if original_spawn != null:
		var spawn_offset: Vector2 = Vector2.ZERO
		match spawn_index:
			0:
				spawn_offset = Vector2(-18.0, -18.0)
			1:
				spawn_offset = Vector2(18.0, -18.0)
			2:
				spawn_offset = Vector2(-18.0, 18.0)
			3:
				spawn_offset = Vector2(18.0, 18.0)
		return original_spawn.global_position + spawn_offset

	return super(peer_id)


func on_lan_enemy_defeated(profile: StringName) -> void:
	if profile != &"necromancer" or not multiplayer.is_server() or necromancer_defeated:
		return
	necromancer_defeated = true
	_set_status("The Necromancer is defeated. The LAN dungeon is clear!")


func _refresh_boss_healthbar() -> void:
	if boss_bar == null or boss_label == null:
		return
	if lan_necromancer == null or not lan_necromancer.has_method(&"get_lan_health"):
		boss_bar.visible = false
		boss_label.visible = false
		return

	var health_value: Variant = lan_necromancer.call(&"get_lan_health")
	var maximum_value: Variant = lan_necromancer.call(&"get_lan_max_health")
	var current_health: int = int(health_value)
	var maximum_health: int = maxi(1, int(maximum_value))
	boss_bar.visible = not necromancer_defeated
	boss_label.visible = not necromancer_defeated
	boss_bar.max_value = maximum_health
	boss_bar.value = current_health
	boss_label.text = "Necromancer: %d / %d" % [current_health, maximum_health]


func _remove_single_player_dungeon_systems() -> void:
	for node_path: NodePath in SINGLE_PLAYER_ONLY_NODE_PATHS:
		var single_player_node: Node = get_node_or_null(node_path)
		if single_player_node != null:
			single_player_node.free()

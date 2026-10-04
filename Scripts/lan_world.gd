extends "res://Scripts/lan_knight_match.gd"

# This LAN-only World keeps the normal World scene unchanged.  It reuses the
# tested host-authority controller, but puts the two selected players at the
# real World entrance instead of the old training arena.

@export var host_spawn_path: NodePath = ^"lan_host_spawn"
@export var joiner_spawn_path: NodePath = ^"lan_joiner_spawn"

# These are normal single-player systems.  Later LAN steps will replace them
# with more synchronized enemies, portal travel, and a multiplayer health display.
const SINGLE_PLAYER_ONLY_NODE_PATHS: Array[NodePath] = [
	^"skeleton_spawner",
	^"dungeon_door",
	^"elite_orc",
	^"CanvasLayer",
]


func _ready() -> void:
	# Remove only single-player gameplay from this inherited copy.  The map,
	# walls, portal artwork, and World music remain available to both players.
	_remove_single_player_world_systems()
	super()


func _on_match_started(started_match_id: int) -> void:
	super(started_match_id)

	if match_is_active:
		_set_status("LAN World loaded. A shared Slime and Skeleton are active east of the entrance.")


func _get_spawn_position(peer_id: int) -> Vector2:
	# Peer 1 is always the host; the other peer is the joiner.  Separate markers
	# keep their bodies from appearing on top of each other at the map entrance.
	var spawn_path: NodePath = host_spawn_path if peer_id == 1 else joiner_spawn_path
	var spawn_marker: Marker2D = get_node_or_null(spawn_path) as Marker2D
	if spawn_marker != null:
		return spawn_marker.global_position

	# This fallback still lets the map work if either LAN marker is accidentally
	# removed while editing the scene.
	var original_spawn: Marker2D = get_node_or_null(^"player_spawn") as Marker2D
	if original_spawn != null:
		var side_offset: float = -18.0 if peer_id == 1 else 18.0
		return original_spawn.global_position + Vector2(side_offset, 0.0)

	return super(peer_id)


func _remove_single_player_world_systems() -> void:
	for node_path in SINGLE_PLAYER_ONLY_NODE_PATHS:
		var single_player_node: Node = get_node_or_null(node_path)
		if single_player_node != null:
			single_player_node.free()

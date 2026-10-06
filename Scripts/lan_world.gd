extends "res://Scripts/lan_knight_match.gd"

# This LAN-only World keeps the normal World scene unchanged.  It reuses the
# tested host-authority controller, but puts all four selected players at the
# real World entrance instead of the old training arena.

# These markers are read in the sorted LAN roster order: host, Player 2,
# Player 3, then Player 4. Keeping the paths here makes their purpose clear
# when this LAN-only scene is edited later.
@export var player_spawn_paths: Array[NodePath] = [
	^"lan_player_1_spawn",
	^"lan_player_2_spawn",
	^"lan_player_3_spawn",
	^"lan_player_4_spawn",
]

# These are normal single-player systems.  Later LAN steps will replace them
# with more synchronized enemies, portal travel, and a multiplayer health display.
const SINGLE_PLAYER_ONLY_NODE_PATHS: Array[NodePath] = [
	^"enemies1",
	^"enemies2",
	^"slime_spawner",
	^"dungeon_door",
	^"ingame_options",
	^"elite_orc",
	^"CanvasLayer",
]

@onready var lan_dungeon_portal: Area2D = get_node_or_null(^"lan_dungeon_portal") as Area2D


func _ready() -> void:
	# Remove only single-player gameplay from this inherited copy.  The map,
	# walls, portal artwork, and World music remain available to both players.
	_remove_single_player_world_systems()
	super()


func _on_match_started(started_match_id: int) -> void:
	super(started_match_id)

	if match_is_active:
		_set_status("LAN World loaded. Clear the Elite Orc gate to open the shared dungeon portal.")


func _get_spawn_position(peer_id: int) -> Vector2:
	# A client can receive any valid ENet peer ID, so map by sorted roster slot
	# instead of assuming players will always use IDs 1, 2, 3, and 4.
	var peer_ids: PackedInt32Array = LanSession.get_connected_peer_ids()
	var spawn_index: int = peer_ids.find(peer_id)
	if spawn_index >= 0 and spawn_index < player_spawn_paths.size():
		var spawn_marker: Marker2D = get_node_or_null(player_spawn_paths[spawn_index]) as Marker2D
		if spawn_marker != null:
			return spawn_marker.global_position

	# This fallback still gives all four players separate positions if a marker is
	# accidentally removed while editing the scene.
	var original_spawn: Marker2D = get_node_or_null(^"player_spawn") as Marker2D
	if original_spawn != null:
		var spawn_offset := Vector2.ZERO
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


func _remove_single_player_world_systems() -> void:
	for node_path in SINGLE_PLAYER_ONLY_NODE_PATHS:
		var single_player_node: Node = get_node_or_null(node_path)
		if single_player_node != null:
			single_player_node.free()


# The Elite Orc is the LAN gatekeeper. Only its host-confirmed defeat opens
# the portal; simply walking into it cannot move one player ahead of the party.
func on_lan_enemy_defeated(profile: StringName) -> void:
	if profile != &"elite_orc" or not multiplayer.is_server() or lan_dungeon_portal == null:
		return
	lan_dungeon_portal.call(&"unlock_from_host")
	_set_status("Elite Orc defeated! Step into the portal to move the whole party to the dungeon.")


func request_lan_dungeon_transition() -> void:
	if not multiplayer.is_server() or lan_dungeon_portal == null:
		return
	var unlocked_value: Variant = lan_dungeon_portal.call(&"is_lan_portal_unlocked")
	if unlocked_value is bool and bool(unlocked_value):
		LanSession.request_dungeon_transition()

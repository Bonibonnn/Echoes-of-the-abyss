extends Area2D

# A LAN-only replacement for the normal one-player dungeon door. The Elite
# Orc death unlocks it for everyone, and the host moves the entire party using
# LanSession's shared scene-loading handshake.

# The Area2D and inherited AnimatedSprite2D are siblings in lan_world.tscn.
@export var portal_visual_path: NodePath = ^"../portal"

var is_unlocked: bool = false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_refresh_portal_visual()


func unlock_from_host() -> void:
	if multiplayer.is_server():
		set_lan_portal_unlocked.rpc(true)


func reset_for_network_session() -> void:
	if multiplayer.is_server():
		set_lan_portal_unlocked.rpc(false)


func is_lan_portal_unlocked() -> bool:
	return is_unlocked


@rpc("authority", "call_local", "reliable")
func set_lan_portal_unlocked(unlocked: bool) -> void:
	is_unlocked = unlocked
	_refresh_portal_visual()


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server() or not is_unlocked:
		return

	var arena: Node = get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null:
		return
	var players_node: Node = arena.get_node_or_null(^"players")
	if players_node != null and body.get_parent() == players_node:
		arena.call(&"request_lan_dungeon_transition")


func _refresh_portal_visual() -> void:
	var portal_visual: CanvasItem = get_node_or_null(portal_visual_path) as CanvasItem
	if portal_visual == null:
		return
	portal_visual.modulate = Color.WHITE if is_unlocked else Color(0.25, 0.28, 0.36, 0.95)

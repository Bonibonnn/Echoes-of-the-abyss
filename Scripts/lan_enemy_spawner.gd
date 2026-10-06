extends Area2D

# LAN-only trap/graveyard spawner. Only the host rolls random variants and
# creates enemies, then the normal LAN enemy RPC creates the same result for
# every connected computer.

@export var profiles: PackedStringArray = PackedStringArray()
@export var spawn_only_once: bool = true
@export var choose_random_profiles: bool = false

var has_spawned: bool = false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server() or profiles.is_empty():
		return
	if spawn_only_once and has_spawned:
		return

	var arena: Node = get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena == null or not _is_lan_player_body(body, arena):
		return

	# Mark it first so simultaneous overlap signals from a four-player party
	# cannot make the same trap spawn its enemies more than once.
	has_spawned = true
	var profile_cursor: int = 0
	for child: Node in get_children():
		var spawn_marker: Marker2D = child as Marker2D
		if spawn_marker == null:
			continue

		var profile_name: StringName = _pick_profile(profile_cursor)
		profile_cursor += 1
		if not profile_name.is_empty():
			arena.call(&"spawn_lan_enemy_on_server", profile_name, spawn_marker.global_position)


func reset_for_network_session() -> void:
	if multiplayer.is_server():
		has_spawned = false


func _pick_profile(index: int) -> StringName:
	if profiles.is_empty():
		return &""
	if choose_random_profiles:
		var random_index: int = randi_range(0, profiles.size() - 1)
		return StringName(profiles[random_index])
	return StringName(profiles[index % profiles.size()])


func _is_lan_player_body(body: Node2D, arena: Node) -> bool:
	var players_node: Node = arena.get_node_or_null(^"players")
	return players_node != null and body.get_parent() == players_node

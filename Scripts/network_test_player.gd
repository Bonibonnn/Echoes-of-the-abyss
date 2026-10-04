extends CharacterBody2D

# This intentionally simple player is only for the LAN proof of concept.
# It does not use Combatant or any real character script.

@export var movement_speed := 180.0

@onready var camera := get_node_or_null(^"camera") as Camera2D
@onready var peer_label := get_node_or_null(^"peer_label") as Label


func _ready() -> void:
	var peer_id := get_multiplayer_authority()

	if camera != null:
		# Each game instance follows only the player it owns.
		camera.enabled = is_multiplayer_authority()

	if peer_label != null:
		peer_label.text = "Player %d" % peer_id

	# Blue is the host; coral identifies the joining player.
	modulate = Color(0.35, 0.75, 1.0, 1.0) if peer_id == 1 else Color(1.0, 0.48, 0.38, 1.0)


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = direction * movement_speed
	move_and_slide()

	# This is a lightweight visual position sync only. Real combat is purposely
	# excluded until the basic host/join test is confirmed working.
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		sync_position.rpc(global_position)


# Each player owns its own test character, so its position can be sent directly
# to the other connected peer. Unreliable packets keep movement responsive.
@rpc("authority", "call_remote", "unreliable")
func sync_position(network_position: Vector2) -> void:
	global_position = network_position


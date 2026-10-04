extends Area2D

# Visual projectile for the LAN Archer. It exists on both computers, but only
# the host advances it and accepts body collisions. The host root broadcasts
# motion and the reliable despawn, so an arrow can never deal damage twice.

@export var speed := 550.0
@export var max_distance := 500.0

var projectile_id := -1
var direction := Vector2.RIGHT
var distance_travelled := 0.0
var is_flying := false


func _ready() -> void:
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func launch(
	new_projectile_id: int,
	flight_direction: Vector2,
	arrow_scale: float
) -> void:
	projectile_id = new_projectile_id
	direction = flight_direction.normalized()
	if direction.is_zero_approx():
		is_flying = false
		return

	scale = Vector2.ONE * arrow_scale
	rotation = direction.angle()
	distance_travelled = 0.0
	is_flying = true


func _physics_process(delta: float) -> void:
	# Clients never move the real collision Area2D. They receive snapshots from
	# the host through apply_network_position instead.
	if not is_flying or not multiplayer.is_server():
		return

	var movement := direction * speed * delta
	global_position += movement
	distance_travelled += movement.length()
	if distance_travelled >= max_distance:
		is_flying = false
		var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
		if arena != null:
			arena.call(&"server_expire_archer_arrow", projectile_id)


func apply_network_position(network_position: Vector2, network_rotation: float) -> void:
	if multiplayer.is_server() or not is_flying:
		return
	global_position = network_position
	rotation = network_rotation


func _on_body_entered(body: Node2D) -> void:
	if not is_flying or not multiplayer.is_server():
		return

	# A hit is final immediately. The root decides whether the body was the
	# LAN slime and then reliably removes this arrow on both computers.
	is_flying = false
	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena != null:
		arena.call(&"server_resolve_archer_arrow_collision", projectile_id, body)

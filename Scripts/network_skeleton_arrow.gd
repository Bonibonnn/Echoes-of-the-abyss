extends Area2D

# LAN-only Skeleton Archer projectile. The host moves and resolves it, while
# other players receive motion snapshots and the same reliable despawn event.

@export var speed: float = 360.0
@export var maximum_distance: float = 260.0

var projectile_id: int = -1
var direction: Vector2 = Vector2.RIGHT
var distance_travelled: float = 0.0
var is_flying: bool = false


func _ready() -> void:
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func launch(new_projectile_id: int, flight_direction: Vector2, range_limit: float) -> void:
	projectile_id = new_projectile_id
	direction = flight_direction.normalized()
	if direction.is_zero_approx():
		is_flying = false
		return

	maximum_distance = maxf(1.0, range_limit)
	rotation = direction.angle()
	distance_travelled = 0.0
	is_flying = true


func _physics_process(delta: float) -> void:
	if not is_flying or not multiplayer.is_server():
		return

	var movement: Vector2 = direction * speed * delta
	global_position += movement
	distance_travelled += movement.length()
	if distance_travelled >= maximum_distance:
		is_flying = false
		var arena: Node = get_tree().get_first_node_in_group(&"lan_knight_test")
		if arena != null:
			arena.call(&"server_expire_skeleton_arrow", projectile_id)


func apply_network_position(network_position: Vector2, network_rotation: float) -> void:
	if multiplayer.is_server() or not is_flying:
		return
	global_position = network_position
	rotation = network_rotation


func _on_body_entered(body: Node2D) -> void:
	if not is_flying or not multiplayer.is_server():
		return

	is_flying = false
	var arena: Node = get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena != null:
		arena.call(&"server_resolve_skeleton_arrow_collision", projectile_id, body)

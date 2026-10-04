extends Area2D

# LAN-only fireball. The host moves the Area2D and decides a collision; other
# computers only display the spawn, snapshots, and one-shot impact animation.

@export var speed := 430.0
@export var max_distance := 450.0
@export var impact_lifetime := 0.6

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D

var projectile_id := -1
var direction := Vector2.RIGHT
var distance_travelled := 0.0
var is_flying := false
var is_impacting := false


func _ready() -> void:
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func launch(new_projectile_id: int, flight_direction: Vector2) -> void:
	projectile_id = new_projectile_id
	direction = flight_direction.normalized()
	if direction.is_zero_approx():
		return

	rotation = direction.angle()
	distance_travelled = 0.0
	is_flying = true
	is_impacting = false
	_play_flight_animation()


func _physics_process(delta: float) -> void:
	if not is_flying or not multiplayer.is_server():
		return

	var movement := direction * speed * delta
	global_position += movement
	distance_travelled += movement.length()
	if distance_travelled >= max_distance:
		is_flying = false
		var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
		if arena != null:
			arena.call(&"server_expire_mage_fireball", projectile_id)


func apply_network_position(network_position: Vector2, network_rotation: float) -> void:
	if multiplayer.is_server() or not is_flying:
		return
	global_position = network_position
	rotation = network_rotation


func begin_network_impact() -> void:
	if is_impacting:
		return

	is_flying = false
	is_impacting = true
	monitoring = false
	if animated_sprite != null and animated_sprite.sprite_frames != null:
		if animated_sprite.sprite_frames.has_animation(&"impact"):
			animated_sprite.sprite_frames.set_animation_loop_mode(&"impact", SpriteFrames.LOOP_NONE)
			animated_sprite.play(&"impact")
			animated_sprite.frame = 0
			animated_sprite.frame_progress = 0.0


func _play_flight_animation() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(&"fly"):
		return

	animated_sprite.sprite_frames.set_animation_loop_mode(&"fly", SpriteFrames.LOOP_LINEAR)
	animated_sprite.play(&"fly")
	animated_sprite.frame = 0
	animated_sprite.frame_progress = 0.0


func _on_body_entered(body: Node2D) -> void:
	if not is_flying or not multiplayer.is_server():
		return

	is_flying = false
	var arena := get_tree().get_first_node_in_group(&"lan_knight_test")
	if arena != null:
		arena.call(&"server_resolve_mage_fireball_collision", projectile_id, body)

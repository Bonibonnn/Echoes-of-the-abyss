extends Area2D

# A visible, non-blocking lava pad for the LAN health test. The root test scene
# asks whether a host-side player position is inside; this node never damages
# anybody by itself.

@export var zone_size := Vector2(190, 140)


func contains_global_position(world_position: Vector2) -> bool:
	var local_position := to_local(world_position)
	var local_rect := Rect2(-zone_size * 0.5, zone_size)
	return local_rect.has_point(local_position)


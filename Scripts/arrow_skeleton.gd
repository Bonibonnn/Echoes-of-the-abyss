extends "res://Scripts/arrow.gd"

# The skeleton arrow uses the shared projectile movement and launch function,
# but it flies through other enemies instead of being spent by a friendly body.


func _on_body_entered(body: Node2D) -> void:
	if not _is_flying or body == _shooter:
		return

	# Ignore other CharacterBody2D enemies, but still stop on the player,
	# a wall, or any other non-character obstacle.
	if body is CharacterBody2D and not body.is_in_group(_target_group):
		return

	_is_flying = false
	if body.is_in_group(_target_group) and body.has_method(&"take_damage"):
		body.call(&"take_damage", _damage)

	queue_free()

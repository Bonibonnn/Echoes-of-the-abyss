extends Area2D

# LAN-only visual effect for Priest's ranged auraplosion and self-heal. The
# host has already resolved damage or healing before spawning this effect, so
# it never has collision or local gameplay authority.

@export var minimum_lifetime := 0.7

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D


func play_effect() -> void:
	var lifetime := minimum_lifetime
	if animated_sprite != null and animated_sprite.sprite_frames != null:
		var animation_name: StringName = animated_sprite.animation
		if animated_sprite.sprite_frames.has_animation(animation_name):
			animated_sprite.sprite_frames.set_animation_loop_mode(animation_name, SpriteFrames.LOOP_NONE)
			animated_sprite.play(animation_name)
			animated_sprite.frame = 0
			animated_sprite.frame_progress = 0.0
			var animation_speed := animated_sprite.sprite_frames.get_animation_speed(animation_name)
			if animation_speed > 0.0:
				lifetime = maxf(
					lifetime,
					float(animated_sprite.sprite_frames.get_frame_count(animation_name)) / animation_speed
				)

	_remove_after_effect(lifetime)


func _remove_after_effect(lifetime: float) -> void:
	await get_tree().create_timer(maxf(0.05, lifetime), false, true).timeout
	queue_free()

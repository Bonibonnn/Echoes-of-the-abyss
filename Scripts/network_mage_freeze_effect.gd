extends Area2D

# Visual-only LAN freeze effect. The host has already applied the actual
# freeze before it spawns this effect, so clients can never use this node to
# create their own local debuff.

@export var minimum_lifetime := 0.7

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D


func play_effect() -> void:
	var lifetime := minimum_lifetime
	if animated_sprite != null and animated_sprite.sprite_frames != null:
		var chosen_animation: StringName = animated_sprite.animation
		if animated_sprite.sprite_frames.has_animation(chosen_animation):
			animated_sprite.sprite_frames.set_animation_loop_mode(chosen_animation, SpriteFrames.LOOP_NONE)
			animated_sprite.play(chosen_animation)
			animated_sprite.frame = 0
			animated_sprite.frame_progress = 0.0
			var animation_speed := animated_sprite.sprite_frames.get_animation_speed(chosen_animation)
			if animation_speed > 0.0:
				lifetime = maxf(
					lifetime,
					float(animated_sprite.sprite_frames.get_frame_count(chosen_animation)) / animation_speed
				)

	_remove_after_effect(lifetime)


func _remove_after_effect(lifetime: float) -> void:
	await get_tree().create_timer(maxf(0.05, lifetime), false, true).timeout
	queue_free()

extends Area2D

# Leave empty to play the scene's currently selected animation.
@export var animation_name: StringName = &""
@export_range(0.05, 5.0, 0.01, "suffix:s") var minimum_lifetime := 0.75

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D


# Called when the Priest's heal animation reaches its healing moment.
func activate() -> void:
	var lifetime := minimum_lifetime

	if animated_sprite != null and animated_sprite.sprite_frames != null:
		var chosen_animation := animation_name if animation_name != &"" else animated_sprite.animation
		if animated_sprite.sprite_frames.has_animation(chosen_animation):
			# The effect plays once and then removes itself.
			animated_sprite.sprite_frames.set_animation_loop_mode(
				chosen_animation,
				SpriteFrames.LOOP_NONE
			)
			animated_sprite.play(chosen_animation)
			animated_sprite.frame = 0
			animated_sprite.frame_progress = 0.0
			lifetime = maxf(lifetime, get_animation_duration(chosen_animation))

	await get_tree().create_timer(lifetime, false, true).timeout
	queue_free()


func get_animation_duration(chosen_animation: StringName) -> float:
	var speed := animated_sprite.sprite_frames.get_animation_speed(chosen_animation)
	if speed <= 0.0:
		return 0.0

	return float(animated_sprite.sprite_frames.get_frame_count(chosen_animation)) / speed

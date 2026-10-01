extends Area2D

@export_flags_2d_physics var hit_collision_mask := 1
# Leave empty to play the AnimatedSprite2D's selected animation.
@export var animation_name: StringName = &""
@export_range(0.05, 5.0, 0.01, "suffix:s") var minimum_lifetime := 0.7

@onready var animated_sprite := get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D


func _ready() -> void:
	monitoring = true
	collision_mask = hit_collision_mask


# Called by mage.gd after this Area2D is placed on the selected enemy.
func activate(freeze_duration: float, target_group: StringName, freeze_tint: Color) -> void:
	var lifetime := play_effect_animation()

	# A newly-created Area2D needs one physics frame before overlaps are reliable.
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		var enemy := body as Node2D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if enemy.is_in_group(target_group) and enemy.has_method(&"apply_freeze"):
			enemy.call(&"apply_freeze", freeze_duration, freeze_tint)

	await get_tree().create_timer(lifetime, false, true).timeout
	queue_free()


func play_effect_animation() -> float:
	var lifetime := minimum_lifetime
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return lifetime

	var chosen_animation := animation_name if animation_name != &"" else animated_sprite.animation
	if not animated_sprite.sprite_frames.has_animation(chosen_animation):
		return lifetime

	# The effect removes itself after one complete animation.
	animated_sprite.sprite_frames.set_animation_loop_mode(
		chosen_animation,
		SpriteFrames.LOOP_NONE
	)
	animated_sprite.play(chosen_animation)
	animated_sprite.frame = 0
	animated_sprite.frame_progress = 0.0

	var speed := animated_sprite.sprite_frames.get_animation_speed(chosen_animation)
	if speed > 0.0:
		lifetime = maxf(
			lifetime,
			float(animated_sprite.sprite_frames.get_frame_count(chosen_animation)) / speed
		)

	return lifetime

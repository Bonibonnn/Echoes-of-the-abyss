extends Combatant

@export var chase_speed := 60.0
@export var max_health := 15
@export var melee_damage := 2
@export var magic_damage := 5
@export var melee_range := 48.0
@export var magic_explosion_range := 70.0
@export var melee_cooldown := 0.9
@export var melee_recovery := 0.25
@export var magic_cast_recovery := 1.8
@export var magic_cooldown := 30.0
@export var magic_hit_delay := 0.45
@export var hurt_duration := 0.3
@export var death_duration := 1.0

@export_category("Skeleton Summon")
@export var skeleton_scene: PackedScene
@export_range(0.0, 1.0) var summon_health_ratio := 0.5
@export var summon_cast_time := 0.8
@export var summon_animation: StringName = &"summon"
@export var shield_tint := Color(0.55, 0.75, 1.0, 1.0)
@export var summon_effect_animation: StringName = &"summon"

@export var magic_explosion_scene: PackedScene

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D
@onready var summon_point := get_node_or_null(^"enemy_hitbox/summon_point") as Marker2D
@onready var summon_effect := get_node_or_null(^"enemy_hitbox/summon_point/animation_effect") as AnimatedSprite2D

var player: Node2D
var magic_cooldown_remaining := 0.0
var melee_recovery_remaining := 0.0
var summoned_skeleton: Node2D
var has_summoned := false
var is_shielded := false
var normal_sprite_tint := Color.WHITE


func _ready() -> void:
	super()
	add_to_group(&"enemy")

	if animated_sprite != null:
		normal_sprite_tint = animated_sprite.modulate

	if summon_effect != null:
		summon_effect.hide()

	if skeleton_scene == null:
		push_warning("Assign skeleton.tscn to the Necromancer Skeleton Scene field.")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the necromancer.")
		return

	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)

	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(delta: float) -> void:
	magic_cooldown_remaining = maxf(0.0, magic_cooldown_remaining - delta)
	melee_recovery_remaining = maxf(0.0, melee_recovery_remaining - delta)

	if is_dead:
		return

	# The boss pauses while its summoned skeleton is alive.
	if is_shielded:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_busy():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not is_instance_valid(player):
		velocity = Vector2.ZERO
		update_idle_or_walk_animation()
		return

	if should_summon_skeleton():
		summon_skeleton()
		return

	var to_player := player.global_position - global_position
	set_facing_from_x(to_player.x)

	var distance_squared := to_player.length_squared()

	if distance_squared <= melee_range * melee_range and can_hit_target(player):
		if magic_is_ready() and randf() < 0.35:
			magic_attack()
		elif melee_recovery_remaining <= 0.0:
			# Small gap after a melee attack so it returns to idle properly.
			melee_recovery_remaining = maxf(
				melee_cooldown,
				get_animation_duration(&"attack1")
			) + melee_recovery

			start_melee_attack(
				&"attack1",
				melee_damage,
				&"player",
				melee_cooldown
			)
		else:
			velocity = Vector2.ZERO
			update_idle_or_walk_animation()

		return

	# attack2 is a close radial magic explosion.
	if distance_squared <= magic_explosion_range * magic_explosion_range and magic_is_ready():
		magic_attack()
		return

	velocity = to_player.normalized() * chase_speed
	move_and_slide()
	update_idle_or_walk_animation()


func magic_attack() -> void:
	if not magic_is_ready():
		return

	var token := begin_attack(&"attack2")

	if token < 0:
		return

	magic_cooldown_remaining = magic_cooldown

	var cast_duration := maxf(
		magic_cast_recovery,
		get_animation_duration(&"attack2")
	)

	var safe_hit_delay := minf(
		maxf(0.0, magic_hit_delay),
		cast_duration
	)

	await wait_for_gameplay_time(safe_hit_delay).timeout

	if not is_attack_token_active(token):
		return

	spawn_magic_explosion(global_position)

	if is_instance_valid(player) and player.has_method("take_damage"):
		if player.global_position.distance_to(global_position) <= magic_explosion_range:
			player.take_damage(magic_damage)

	await wait_for_gameplay_time(cast_duration - safe_hit_delay).timeout
	finish_attack(token)


func magic_is_ready() -> bool:
	return magic_cooldown_remaining <= 0.0


func should_summon_skeleton() -> bool:
	return not has_summoned and skeleton_scene != null and health <= max_health * summon_health_ratio


func summon_skeleton() -> void:
	var token := begin_attack(summon_animation)

	if token < 0:
		return

	# The boss becomes invulnerable while summoning.
	set_summon_shield(true, false)
	play_summon_effect()

	await wait_for_gameplay_time(
		maxf(summon_cast_time, get_animation_duration(summon_animation))
	).timeout

	if not is_attack_token_active(token):
		set_summon_shield(false)
		stop_summon_effect()
		return

	var skeleton := skeleton_scene.instantiate() as Node2D

	if skeleton == null:
		set_summon_shield(false)
		stop_summon_effect()
		finish_attack(token)
		return

	var scene_root := get_tree().current_scene

	if scene_root == null:
		set_summon_shield(false)
		stop_summon_effect()
		finish_attack(token)
		return

	scene_root.add_child(skeleton)

	skeleton.global_position = (
		summon_point.global_position
		if summon_point != null
		else global_position + Vector2(facing_direction * 32.0, 0.0)
	)

	summoned_skeleton = skeleton
	has_summoned = true
	set_summon_shield(true)

	var combat_skeleton := skeleton as Combatant

	if combat_skeleton != null:
		combat_skeleton.died.connect(
			_on_summoned_skeleton_defeated.bind(skeleton)
		)

	skeleton.tree_exited.connect(
		_on_summoned_skeleton_removed.bind(skeleton)
	)

	stop_summon_effect()
	finish_attack(token)


func play_summon_effect() -> void:
	if summon_effect == null:
		return

	if summon_effect.sprite_frames == null:
		return

	if not summon_effect.sprite_frames.has_animation(summon_effect_animation):
		push_warning("Add a summon animation to animation_effect.")
		return

	summon_effect.show()
	summon_effect.play(summon_effect_animation)


func stop_summon_effect() -> void:
	if summon_effect == null:
		return

	summon_effect.stop()
	summon_effect.hide()


func set_summon_shield(value: bool, play_idle_animation := true) -> void:
	is_shielded = value

	if animated_sprite == null:
		return

	if is_shielded:
		# Intended boss phase: kill the skeleton before the boss moves again.
		animated_sprite.modulate = shield_tint

		if play_idle_animation:
			play_animation(&"idle")
	else:
		animated_sprite.modulate = normal_sprite_tint

		if play_idle_animation:
			play_animation(&"idle")


func _on_summoned_skeleton_defeated(skeleton: Node2D) -> void:
	if skeleton == summoned_skeleton:
		summoned_skeleton = null
		set_summon_shield(false)


func _on_summoned_skeleton_removed(skeleton: Node2D) -> void:
	if skeleton == summoned_skeleton:
		summoned_skeleton = null
		set_summon_shield(false)


func take_damage(damage: int) -> void:
	if is_shielded:
		return

	super(damage)


func spawn_magic_explosion(target_position: Vector2) -> void:
	if magic_explosion_scene == null:
		return

	var explosion := magic_explosion_scene.instantiate() as Node2D

	if explosion == null:
		return

	var scene_root := get_tree().current_scene

	if scene_root == null:
		return

	scene_root.add_child(explosion)
	explosion.global_position = target_position


func get_max_health() -> int:
	return max_health


func get_hurt_duration() -> float:
	return hurt_duration


func get_death_duration() -> float:
	return death_duration


func _on_detection_area_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		player = body


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body == player:
		player = null

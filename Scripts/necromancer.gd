extends Combatant

@export var chase_speed := 60.0
@export var max_health := 35
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

@export_category("Attack 3 - Deathplosion")
# A close radial blast. It damages every player inside the radius at once.
@export var deathplosion_scene: PackedScene = preload("res://Scenes/deathplosion.tscn")
@export var deathplosion_damage := 2
@export var deathplosion_range := 80.0
@export var deathplosion_cooldown := 7.0
@export var deathplosion_hit_delay := 1.0
@export var deathplosion_cast_recovery := 2.0

@export_category("Summon Waves")
# Each phase uses these scene references, so every Skeleton keeps its own AI,
# stats, and summon animation.
@export var regular_skeleton_scene: PackedScene = preload("res://Scenes/skeleton.tscn")
@export var skeleton_archer_scene: PackedScene = preload("res://Scenes/skeleton_archer.tscn")
@export var armored_skeleton_scene: PackedScene = preload("res://Scenes/armored_skeleton.tscn")
@export var greatsword_skeleton_scene: PackedScene = preload("res://Scenes/greatsword_skeleton.tscn")
@export_range(0.0, 1.0) var summon_75_health_ratio := 0.75
@export_range(0.0, 1.0) var summon_50_health_ratio := 0.5
@export_range(0.0, 1.0) var summon_25_health_ratio := 0.25
@export var summon_cast_time := 2.0
@export var summon_animation: StringName = &"summon2"
@export var summon_spawn_radius := 42.0
@export var shield_tint := Color(0.55, 0.75, 1.0, 1.0)
@export var summon_effect_scene: PackedScene = preload("res://Scenes/summon.tscn")

@export var magic_explosion_scene: PackedScene

@onready var detection_area := get_node_or_null(^"detection_area") as Area2D
@onready var summon_point := get_node_or_null(^"enemy_hitbox/summon_point") as Marker2D
@onready var summon_effect := get_node_or_null(^"enemy_hitbox/summon_point/animation_effect") as AnimatedSprite2D

var player: Node2D
var magic_cooldown_remaining := 0.0
var deathplosion_cooldown_remaining := 0.0
var melee_recovery_remaining := 0.0
var active_summons: Array[Node2D] = []
var has_summoned_75 := false
var has_summoned_50 := false
var has_summoned_25 := false
var is_shielded := false
var normal_sprite_tint := Color.WHITE


func _ready() -> void:
	super()
	add_to_group(&"enemy")
	# GameFlow uses this specific group, so only the Necromancer can open Victory.
	add_to_group(&"final_boss")

	if animated_sprite != null:
		normal_sprite_tint = animated_sprite.modulate

	if summon_effect != null:
		summon_effect.hide()

	if not has_all_summon_scenes():
		push_warning("Assign all four Skeleton scene fields for the Necromancer summon waves.")

	if detection_area == null:
		push_error("Add an Area2D child named detection_area to the necromancer.")
		return

	if not detection_area.body_entered.is_connected(_on_detection_area_body_entered):
		detection_area.body_entered.connect(_on_detection_area_body_entered)

	if not detection_area.body_exited.is_connected(_on_detection_area_body_exited):
		detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(delta: float) -> void:
	magic_cooldown_remaining = maxf(0.0, magic_cooldown_remaining - delta)
	deathplosion_cooldown_remaining = maxf(0.0, deathplosion_cooldown_remaining - delta)
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

	if should_summon_wave():
		summon_skeleton_wave()
		return

	var to_player := player.global_position - global_position
	set_facing_from_x(to_player.x)

	var distance_squared := to_player.length_squared()

	# attack3 is a close radial deathplosion, so it can hurt every nearby player.
	if deathplosion_is_ready() and has_player_in_deathplosion_range():
		deathplosion_attack()
		return

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


# attack3 deals one 2-damage hit to every player inside its circular radius.
func deathplosion_attack() -> void:
	if not deathplosion_is_ready():
		return

	var token: int = begin_attack(&"attack3")
	if token < 0:
		return

	deathplosion_cooldown_remaining = deathplosion_cooldown
	var cast_duration: float = maxf(
		deathplosion_cast_recovery,
		get_animation_duration(&"attack3")
	)
	var hit_time: float = minf(maxf(0.0, deathplosion_hit_delay), cast_duration)

	await wait_for_gameplay_time(hit_time).timeout
	if not is_attack_token_active(token):
		return

	deal_deathplosion_damage()

	await wait_for_gameplay_time(cast_duration - hit_time).timeout
	finish_attack(token)


func deathplosion_is_ready() -> bool:
	return deathplosion_cooldown_remaining <= 0.0


func has_player_in_deathplosion_range() -> bool:
	var range_squared: float = deathplosion_range * deathplosion_range
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var target: Node2D = node as Node2D
		if target != null and not target.is_queued_for_deletion() and target.global_position.distance_squared_to(global_position) <= range_squared:
			return true

	return false


func deal_deathplosion_damage() -> void:
	var range_squared: float = deathplosion_range * deathplosion_range

	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var target: Node2D = node as Node2D
		if target == null or target.is_queued_for_deletion():
			continue
		if not target.has_method(&"take_damage"):
			continue
		if target.global_position.distance_squared_to(global_position) <= range_squared:
			# The visual appears on each player hit, not on the Necromancer.
			spawn_deathplosion(target.global_position)
			target.call(&"take_damage", deathplosion_damage)


func should_summon_wave() -> bool:
	return get_next_summon_wave() != 0 and has_all_summon_scenes()


# Returns the next threshold in order, so only one wave can be active at once.
func get_next_summon_wave() -> int:
	if not has_summoned_75 and health <= max_health * summon_75_health_ratio:
		return 75
	if not has_summoned_50 and health <= max_health * summon_50_health_ratio:
		return 50
	if not has_summoned_25 and health <= max_health * summon_25_health_ratio:
		return 25

	return 0


func summon_skeleton_wave() -> void:
	var wave: int = get_next_summon_wave()
	if wave == 0:
		return

	var wave_scenes: Array[PackedScene] = get_summon_wave_scenes(wave)
	if wave_scenes.is_empty():
		push_warning("The Necromancer summon wave has no valid Skeleton scenes.")
		return

	var token: int = begin_attack(summon_animation)

	if token < 0:
		return

	# The boss becomes invulnerable while summoning.
	set_summon_shield(true, false)

	await wait_for_gameplay_time(
		maxf(summon_cast_time, get_animation_duration(summon_animation))
	).timeout

	if not is_attack_token_active(token):
		set_summon_shield(false)
		return

	spawn_summon_wave(wave_scenes)
	if active_summons.is_empty():
		# Do not consume this phase if a scene could not be created.
		set_summon_shield(false)
	else:
		mark_summon_wave_completed(wave)

	finish_attack(token)


func has_all_summon_scenes() -> bool:
	return (
		regular_skeleton_scene != null
		and skeleton_archer_scene != null
		and armored_skeleton_scene != null
		and greatsword_skeleton_scene != null
	)


func get_summon_wave_scenes(wave: int) -> Array[PackedScene]:
	var wave_scenes: Array[PackedScene] = []

	match wave:
		75:
			# Early wave: 2 regular Skeletons and 1 Skeleton Archer.
			wave_scenes.append(regular_skeleton_scene)
			wave_scenes.append(regular_skeleton_scene)
			wave_scenes.append(skeleton_archer_scene)
		50:
			# 2 Armored Skeletons and 2 Skeleton Archers.
			wave_scenes.append(armored_skeleton_scene)
			wave_scenes.append(armored_skeleton_scene)
			wave_scenes.append(skeleton_archer_scene)
			wave_scenes.append(skeleton_archer_scene)
		25:
			# Final wave: 1 Greatsword Skeleton, 2 Armored Skeletons, 2 Archers.
			wave_scenes.append(greatsword_skeleton_scene)
			wave_scenes.append(armored_skeleton_scene)
			wave_scenes.append(armored_skeleton_scene)
			wave_scenes.append(skeleton_archer_scene)
			wave_scenes.append(skeleton_archer_scene)

	return wave_scenes


func mark_summon_wave_completed(wave: int) -> void:
	match wave:
		75:
			has_summoned_75 = true
		50:
			has_summoned_50 = true
		25:
			has_summoned_25 = true


# Adds the whole wave around the summon marker so the Skeletons do not overlap.
func spawn_summon_wave(wave_scenes: Array[PackedScene]) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	var total_summons: int = wave_scenes.size()
	for index: int in range(total_summons):
		var skeleton_scene: PackedScene = wave_scenes[index]
		var skeleton: Node2D = skeleton_scene.instantiate() as Node2D
		if skeleton == null:
			push_error("Every Necromancer Skeleton scene must have a Node2D root.")
			continue

		scene_root.add_child(skeleton)
		skeleton.global_position = get_summon_position(index, total_summons)
		active_summons.append(skeleton)
		# Add one fresh summon.tscn effect at every Skeleton spawn location.
		spawn_summon_effect_at(skeleton.global_position)

		var combat_skeleton: Combatant = skeleton as Combatant
		if combat_skeleton != null:
			combat_skeleton.play_summon_animation()
			combat_skeleton.died.connect(
				_on_summoned_skeleton_defeated.bind(skeleton)
			)

		skeleton.tree_exited.connect(
			_on_summoned_skeleton_removed.bind(skeleton)
		)


# Places one Skeleton in a circle around the summoning marker.
func get_summon_position(index: int, total_summons: int) -> Vector2:
	var center: Vector2 = (
		summon_point.global_position
		if summon_point != null
		else global_position + Vector2(facing_direction * 32.0, 0.0)
	)
	if total_summons <= 1:
		return center

	var angle: float = -PI * 0.5 + TAU * float(index) / float(total_summons)
	return center + Vector2(cos(angle), sin(angle)) * summon_spawn_radius


func spawn_summon_effect_at(effect_position: Vector2) -> void:
	if summon_effect_scene == null:
		return

	var effect: Area2D = summon_effect_scene.instantiate() as Area2D
	if effect == null:
		push_error("summon.tscn must have an Area2D root.")
		return
	if not effect.has_method(&"activate"):
		push_error("Attach Scripts/auraplosion.gd to summon.tscn.")
		effect.queue_free()
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		effect.queue_free()
		return

	scene_root.add_child(effect)
	effect.global_position = effect_position
	effect.call(&"activate")


func set_summon_shield(value: bool, play_idle_animation := true) -> void:
	is_shielded = value

	if animated_sprite == null:
		return

	if is_shielded:
		# Intended boss phase: kill the entire Skeleton wave before the boss moves.
		animated_sprite.modulate = shield_tint

		if play_idle_animation:
			play_animation(&"idle")
	else:
		animated_sprite.modulate = normal_sprite_tint

		if play_idle_animation:
			play_animation(&"idle")


func _on_summoned_skeleton_defeated(skeleton: Node2D) -> void:
	remove_active_summon(skeleton)


func _on_summoned_skeleton_removed(skeleton: Node2D) -> void:
	remove_active_summon(skeleton)


func remove_active_summon(skeleton: Node2D) -> void:
	if not active_summons.has(skeleton):
		return

	active_summons.erase(skeleton)
	if active_summons.is_empty():
		set_summon_shield(false)


func take_damage(damage: int) -> void:
	if is_shielded:
		return

	super(damage)


func spawn_deathplosion(target_position: Vector2) -> void:
	if deathplosion_scene == null:
		return

	var effect: Area2D = deathplosion_scene.instantiate() as Area2D
	if effect == null:
		push_error("deathplosion.tscn must have an Area2D root.")
		return
	if not effect.has_method(&"activate"):
		push_error("Attach Scripts/auraplosion.gd to deathplosion.tscn.")
		effect.queue_free()
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		effect.queue_free()
		return

	scene_root.add_child(effect)
	effect.global_position = target_position
	effect.call(&"activate")


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

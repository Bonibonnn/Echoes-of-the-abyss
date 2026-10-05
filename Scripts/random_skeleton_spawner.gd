extends Area2D

# A graveyard encounter trigger. When a player enters this Area2D, every child
# Marker2D named spawn_point, spawn_point2, and so on receives one Skeleton.
# The Skeleton type at each point is selected randomly from this list.

@export var skeleton_variants: Array[PackedScene] = [
	preload("res://Scenes/skeleton.tscn"),
	preload("res://Scenes/armored_skeleton.tscn"),
	preload("res://Scenes/greatsword_skeleton.tscn"),
	preload("res://Scenes/skeleton_archer.tscn"),
]
@export var spawn_once: bool = true

var has_spawned: bool = false
var spawn_points: Array[Marker2D] = []
var random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	# Each child marker whose name starts with spawn_point is a possible location.
	for child: Node in find_children("*", "Marker2D", true, false):
		var spawn_point: Marker2D = child as Marker2D
		if spawn_point != null and spawn_point.name.to_lower().begins_with("spawn_point"):
			spawn_points.append(spawn_point)

	random_number_generator.randomize()
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		spawn_random_skeletons()


# Spawns exactly one random Skeleton variant at every graveyard spawn marker.
func spawn_random_skeletons() -> void:
	if spawn_once and has_spawned:
		return
	if skeleton_variants.is_empty():
		push_warning("Add at least one scene to Skeleton Variants.")
		return

	if spawn_points.is_empty():
		spawn_random_skeleton_at(global_position)
	else:
		for spawn_point: Marker2D in spawn_points:
			spawn_random_skeleton_at(spawn_point.global_position)

	has_spawned = true


func spawn_random_skeleton_at(spawn_position: Vector2) -> void:
	var skeleton_scene: PackedScene = get_random_skeleton_scene()
	if skeleton_scene == null:
		push_warning("Skeleton Variants only contains empty scene entries.")
		return

	var skeleton: Node2D = skeleton_scene.instantiate() as Node2D
	if skeleton == null:
		push_error("Every Skeleton Variant scene must have a Node2D root.")
		return

	# Put each Skeleton beside the trigger under the map scene, not inside Area2D.
	var spawn_parent: Node = get_parent()
	if spawn_parent == null:
		return

	spawn_parent.add_child(skeleton)
	skeleton.global_position = spawn_position

	# Every Skeleton variant inherits Combatant and can play its own summon
	# animation before it begins chasing or attacking.
	var combat_skeleton: Combatant = skeleton as Combatant
	if combat_skeleton != null:
		combat_skeleton.play_summon_animation()


# Ignores empty Inspector entries, then picks one of the remaining variants.
func get_random_skeleton_scene() -> PackedScene:
	var valid_variants: Array[PackedScene] = []
	for skeleton_variant: PackedScene in skeleton_variants:
		if skeleton_variant != null:
			valid_variants.append(skeleton_variant)

	if valid_variants.is_empty():
		return null

	var random_index: int = random_number_generator.randi_range(0, valid_variants.size() - 1)
	return valid_variants[random_index]

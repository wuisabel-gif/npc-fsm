class_name NpcWorldAdapter
extends Node2D
## Godot-side implementation of the world boundary described by guard.nut.
## This object is not a Squirrel table and cannot be passed to guard.nut without
## a native bridge that converts these values/calls into Squirrel objects.

@export var target: Node2D
@export var navigation_agent: NavigationAgent2D
@export_range(0.0, 360.0, 1.0) var fov_degrees := 110.0
@export var sight_range := 260.0
@export_flags_2d_physics var collision_mask := 1

# Squirrel-compatible target shape: position, alive, and takeDamage(amount).
# A GDExtension binding can make the equivalent table and forward takeDamage.
func _squirrel_position(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}

func target_mapping() -> Dictionary:
	if not is_instance_valid(target):
		return {"position": _squirrel_position(Vector2.ZERO), "alive": false}
	return {
		"position": _squirrel_position(target.global_position),
		"alive": target.get("alive") if target.get("alive") != null else true,
		"takeDamage": func(amount: float):
			if target.has_method("take_damage"):
				target.take_damage(amount)
	}

# world.canSee(guard, target): facing cone followed by an occlusion ray.
func can_see(guard: Node2D, candidate: Node2D) -> bool:
	if not is_instance_valid(guard) or not is_instance_valid(candidate):
		return false
	var candidate_alive = candidate.get("alive")
	if candidate_alive != null and not candidate_alive:
		return false
	var offset := candidate.global_position - guard.global_position
	if offset.length() > sight_range:
		return false
	if offset.length_squared() > 0.001:
		var facing := Vector2.RIGHT.rotated(guard.global_rotation)
		if absf(rad_to_deg(facing.angle_to(offset))) > fov_degrees * 0.5:
			return false
	var query := PhysicsRayQueryParameters2D.create(
		guard.global_position, candidate.global_position, collision_mask)
	query.exclude = [guard]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == candidate

# world.moveToward(guard, destination, distance): ask NavigationAgent2D for
# the next path point, move the host actor, and return its authoritative position.
func move_toward(guard: CharacterBody2D, destination: Vector2, distance: float) -> Vector2:
	if navigation_agent == null:
		return guard.global_position
	navigation_agent.target_position = destination
	var next := navigation_agent.get_next_path_position()
	var delta := next - guard.global_position
	if delta.length() > 0.001:
		guard.velocity = delta.normalized() * distance
		guard.move_and_slide()
	else:
		guard.velocity = Vector2.ZERO
	return guard.global_position

# world.emit(guard, event, data): adapt canonical FSM events to Godot signals.
signal npc_event(guard: Node, event_name: String, data: Dictionary)

func emit_event(guard: Node, event_name: String, data: Dictionary = {}) -> void:
	npc_event.emit(guard, event_name, data)

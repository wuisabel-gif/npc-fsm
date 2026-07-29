class_name GodotGuardAgent
extends CharacterBody2D
## A deliberately incomplete host-side GDScript port, not guard.nut execution.
## Use a Squirrel VM/GDExtension for the canonical behavior instead.

signal npc_event(event_name: String, data: Dictionary)

@export var world_adapter: NpcWorldAdapter
@export var navigation_agent: NavigationAgent2D
@export var patrol_destination := Vector2.ZERO
@export var move_speed := 90.0

var state := "PATROL"
var suspicion := 0.0

func _ready() -> void:
	if world_adapter != null:
		world_adapter.npc_event.connect(_on_world_event)

func _physics_process(delta: float) -> void:
	if world_adapter == null or not is_instance_valid(world_adapter.target):
		return
	var candidate := world_adapter.target
	if world_adapter.can_see(self, candidate):
		suspicion = minf(1.0, suspicion + delta)
		if suspicion >= 1.0 and state != "CHASE":
			state = "CHASE"
			world_adapter.emit_event(self, "alert", {
				"position": candidate.global_position
			})
	else:
		suspicion = maxf(0.0, suspicion - delta * 0.5)

	if state == "CHASE":
		world_adapter.move_toward(self, candidate.global_position, move_speed * delta)
	else:
		world_adapter.move_toward(self, patrol_destination, move_speed * delta)

# This is the event-handling seam corresponding to world.emit in guard.nut.
func _on_world_event(guard: Node, event_name: String, data: Dictionary) -> void:
	if guard != self:
		return
	match event_name:
		"attack":
			# Replace with the game's authoritative combat call.
			pass
		"death":
			set_physics_process(false)
		"state", "alert", "waypoint", "damaged":
			pass # Animation/audio/UI can consume these payloads.
	npc_event.emit(event_name, data)

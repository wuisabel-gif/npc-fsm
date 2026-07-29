# Godot 4 integration example (host-side GDScript pattern)

This directory is a concrete **Godot 4 host-side integration pattern** for the
Squirrel `GuardNPC` contract. It is not a Squirrel runtime.

Godot does not natively embed Squirrel, so these files do **not** load or
execute `guard.nut`. `npc_world_adapter.gd` shows how a Godot scene can provide
real target mapping, 2D FOV/raycast visibility, `NavigationAgent2D` movement,
and event handling. `guard_agent.gd` is a deliberately small **conceptual
GDScript port** that calls that adapter; it is not claimed to be behaviorally
identical to `guard.nut` and is not a replacement for the canonical Squirrel
FSM.

For the actual `guard.nut` behavior from Godot, use a C++ GDExtension/module
(or another native Squirrel embedding) and bind the same four boundary values:

```text
world.target
world.canSee(guard, target)
world.moveToward(guard, destination, distance)
world.emit(guard, event, data)
```

The native wrapper should retain one Squirrel VM and one `GuardNPC` per actor,
then pass a mapped target/world table to `guard.update(delta, world)` each
frame. `host.cpp` and `doc/ENGINE-INTEGRATION.md` describe that direct-embedding
route. Do not mix the GDScript port with the Squirrel instance.

## Files

- `npc_world_adapter.gd` — real Godot-side adapter operations. Attach it to a
  scene node and assign `target` and a `NavigationAgent2D`.
- `guard_agent.gd` — minimal, illustrative host-side port showing the call
  sequence and event reactions. It is intentionally not a full port of
  `guard.nut`.
- `target_actor.gd` — tiny target node with the fields/method used by the
  adapter mapping.

## Wiring in a Godot 4 scene

1. Add a `Node2D` (or `CharacterBody2D`) named `NpcWorldAdapter` and attach
   `npc_world_adapter.gd`.
2. Assign its `target` to a `TargetActor`, and set `collision_mask` to the
   layers that should occlude sight. Set `fov_degrees` and `sight_range`.
3. Add a `CharacterBody2D` guard with a child `NavigationAgent2D`; attach
   `guard_agent.gd`, assign `world_adapter` and `navigation_agent`, and make
   sure a baked `NavigationRegion2D` covers the level.
4. Connect the guard's `npc_event` signal to animation/audio/UI code, or use
   the `_on_npc_event` example in `guard_agent.gd`.

The ray query is a straight 2D segment and the navigation call is asynchronous:
the adapter returns the actor's current authoritative position, matching the
Squirrel adapter contract when a path has not completed. Project-specific
collision layers, navigation map setup, and actor damage policy remain the
host's responsibility.

## What is verified here

The files are intentionally small source examples and have not been run in a
Godot project in this repository (there is no `project.godot` or Godot CI
configuration). The Squirrel implementation and its existing checks are
unchanged. Treat the GDScript as Godot 4 example code to review/adapt, not as a
claim of tested or direct Squirrel execution.

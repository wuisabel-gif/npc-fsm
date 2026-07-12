# npc-fsm

An engine-independent NPC behavior library written in **Squirrel**. It drives a guard with a finite-state machine you plug into your own game — no engine dependency.

## Behavior states

```text
PATROL ──sees player──> CHASE ──close enough──> ATTACK
   ^                       │                       │
   │                       │ target escapes        │ player moves away
   │                       v                       v
RETURN <─────────────── SEARCH <─────────────── CHASE
   │
   └──reaches route──> PATROL
```

The guard can:

- Walk through four patrol waypoints
- Detect the player within a sight radius
- Remember the player's last known position
- Chase the player
- Attack with damage and a cooldown
- Search after losing the player
- Return to its patrol route
- React to damage and die

## Files

- `guard.nut` — the reusable, engine-independent guard behavior. Drop this into your game. No `print`, no loop, no hardcoded player.
- `demo.nut` — an example host that wires the guard to a fake world and runs it (`sq demo.nut`). Prints a live ASCII arena each tick: `G` guard, `P` player, `o` waypoints, `x` dead guard.
- `test.nut` — self-check driving a guard through every state transition (`sq test.nut`).

## Run the demo

Install or build the official Squirrel interpreter, then:

```bash
sq demo.nut
```

Depending on your installation, the interpreter executable may have a different path or name.

## Plugging it into a game

The guard never touches the world directly — each frame your game hands it a `world` adapter and the guard talks back through it. Integration is one call per frame:

```squirrel
guard.update(deltaTime, world);                       // decide + act
guard.takeDamage(world, amount, attackerPosition);    // when the guard is hit
```

Your `world` object implements the engine boundary. Replace each stub with your real systems:

```text
world.target                     -> the entity the guard reacts to, or null
world.canSee(guard, target)      -> your field-of-view + raycast/occlusion test
world.emit(guard, event, data)   -> your animation / sound / UI / logging
world.moveToward(guard, dest, d) -> OPTIONAL: your navmesh/pathfinding/steering.
                                    Omit it to use the built-in straight-line move.
```

The target entity is duck-typed: it needs `.position {x,y}`, `.alive`, and `.takeDamage(amount)`. Events the guard emits: `state`, `waypoint`, `attack`, `damaged`, `death`. See `demo.nut` for a complete working host you can copy — swapping distance-based sight for a real FOV cone and `print` for animation calls is the entire integration.

## Suggested extensions

1. Add hearing: investigate the location of a loud sound.
2. Add suspicion: fill a detection meter instead of detecting instantly.
3. Add cover: select a nearby cover point when health is low.
4. Add communication: one guard alerts nearby guards.
5. Add personality parameters: cautious, aggressive, or cowardly.
6. Add animation callbacks for walking, running, attacking, and death.

## Why Squirrel fits

Squirrel supports classes, tables, arrays, functions, and embedding in native applications, so gameplay behavior can stay editable outside the C++ engine. This project uses classes for the player and guard and an explicit state machine for predictable behavior.

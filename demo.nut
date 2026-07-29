// Example host for guard.nut — sq demo.nut
// This is the "engine" side: it owns the world, the target entity, the loop,
// and it implements the `world` adapter the guard talks through. Replace the
// three adapter functions with your real FOV, event, and navigation systems.

dofile("guard.nut", true);
dofile("perception.nut", true); // optional host-side FOV example
dofile("player.nut", true);   // the example target entity

// The world adapter. THIS is the engine boundary — swap each function for your
// engine's real implementation. No world.moveToward here, so the guard uses its
// built-in straight-line movement; add one to route through your navmesh.
function makeWorld(target) {
    return {
        target = target,

        // Perception: a 75-degree patrol-facing cone plus an optional occlusion hook.
        // Replace patrolFacing() with the facing from your animation/locomotion system.
        fovHalfAngleDegrees = 75.0,
        occluded = null, // e.g. function(guard, target) { return nav.raycast(...); }
        canSee = function(guard, target) {
            return fovCanSee(guard, target, patrolFacing(guard),
                this.fovHalfAngleDegrees, this.occluded);
        },

        // Output: demo prints. Real engine: trigger animation / sound / UI here.
        emit = function(guard, event, data) {
            switch (event) {
                case "state":    print(format("  %s: %s -> %s\n", guard.name, data.from, data.to)); break;
                case "waypoint": print(format("  %s reached waypoint %d.\n", guard.name, data.index)); break;
                case "alert":    print(format("  %s spotted the target at %s!\n", guard.name, positionText(data.position))); break;
                case "attack":   print(format("  %s attacks!\n", guard.name)); break;
                case "damaged":  print(format("  %s takes %d damage; health=%d\n", guard.name, data.amount, data.health)); break;
                case "death":    print(format("  %s has been defeated.\n", guard.name)); break;
            }
        }
    };
}

function renderArena(player, guard, width, height) {
    // ponytail: ASCII debug view; a real engine renders sprites instead.
    for (local y = height - 1; y >= 0; y--) {
        local line = "  ";
        for (local x = 0; x < width; x++) {
            local cell = ".";
            foreach (p in guard.patrolPoints)
                if (p.x.tointeger() == x && p.y.tointeger() == y) cell = "o";
            if (player.alive && player.position.x.tointeger() == x && player.position.y.tointeger() == y) cell = "P";
            if (guard.position.x.tointeger() == x && guard.position.y.tointeger() == y) cell = (guard.state == "DEAD") ? "x" : "G";
            line += cell;
        }
        print(line + "\n");
    }
}

function scriptedPlayerMovement(time, player) {
    // This timeline deliberately demonstrates every major NPC state.
    if (time < 3.0)       player.moveTo(vec2(14, 5));   // outside vision
    else if (time < 7.0)  player.moveTo(vec2(7, 2));    // enters vision
    else if (time < 11.0) player.moveTo(vec2(4, 1));    // guard reaches attack range
    else if (time < 14.0) player.moveTo(vec2(18, 10));  // escapes; guard searches
    else if (time < 18.0) player.moveTo(vec2(14, 5));   // hidden while guard returns
    else                  player.moveTo(vec2(6, 5));     // re-enters vision
}

function main() {
    local patrolRoute = [vec2(0, 0), vec2(6, 0), vec2(6, 6), vec2(0, 6)];
    local player = Player(vec2(14, 5));
    local guard = GuardNPC("Guard", vec2(0, 0), patrolRoute);
    local world = makeWorld(player);

    local deltaTime = 0.5;
    local simulationLength = 24.0;
    local time = 0.0;

    print("=== SQUIRREL NPC BEHAVIOR DEMO ===\n");
    print("States: PATROL, CHASE, ATTACK, SEARCH, RETURN, DEAD\n\n");

    while (time <= simulationLength && player.alive) {
        scriptedPlayerMovement(time, player);
        print(format("[t=%4.1f] Player pos=%s hp=%d | %s\n",
            time, positionText(player.position), player.health, guard.status()));
        renderArena(player, guard, 20, 12);

        guard.update(deltaTime, world);   // <- the whole integration is this one call
        time += deltaTime;
    }

    print("\n=== SIMULATION COMPLETE ===\n");
}

main();

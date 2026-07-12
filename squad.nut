// Multi-guard example host for guard.nut — sq squad.nut
// Three guards share one world. When a guard's suspicion tops out it emits an
// "alert"; the host forwards that to any *nearby* guard (within alertRadius) via
// alertTo(), so they converge to investigate. A distant guard never hears it.
//
// This is the same guard.nut as the single demo — the squad behaviour lives
// entirely in the host's emit handler, not in the guard.

dofile("guard.nut", true);
dofile("player.nut", true);

function makeWorld(player, guards, alertRadius) {
    return {
        target = player,
        guards = guards,
        alertRadius = alertRadius,

        canSee = function(guard, t) {
            return t.alive && vecDistance(guard.position, t.position) <= guard.sightRange;
        },

        emit = function(guard, event, data) {
            switch (event) {
                case "state":
                    print(format("  %s: %s -> %s\n", guard.name, data.from, data.to));
                    break;
                case "alert":
                    print(format("  ** %s spotted the target at %s and radios it in **\n",
                        guard.name, positionText(data.position)));
                    // Forward to nearby guards only. `this` is the world (bound by world.emit()).
                    foreach (g in this.guards) {
                        if (g == guard || g.state == "DEAD") continue;
                        if (vecDistance(g.position, guard.position) <= this.alertRadius) {
                            print(format("     -> %s responds and moves to investigate.\n", g.name));
                            g.alertTo(this, data.position);
                        }
                    }
                    break;
                case "attack":  print(format("  %s attacks!\n", guard.name)); break;
                case "damaged": print(format("  %s takes %d damage; health=%d\n", guard.name, data.amount, data.health)); break;
                case "death":   print(format("  %s has been defeated.\n", guard.name)); break;
            }
        }
    };
}

function renderArena(player, guards, width, height) {
    for (local y = height - 1; y >= 0; y--) {
        local line = "  ";
        for (local x = 0; x < width; x++) {
            local cell = ".";
            if (player.alive && player.position.x.tointeger() == x && player.position.y.tointeger() == y) cell = "P";
            foreach (i, g in guards)
                if (g.position.x.tointeger() == x && g.position.y.tointeger() == y)
                    cell = (g.state == "DEAD") ? "x" : (i + 1).tostring();   // guards shown as 1,2,3
            line += cell;
        }
        print(line + "\n");
    }
}

function scriptedPlayerMovement(time, player) {
    // Sit in guard 1's view (out of guard 2's sight), get detected, then slip away
    // so the alerted guards search. Guard 3 is far off and never involved.
    if (time < 9.0)       player.moveTo(vec2(2, 4));    // in guard 1's view only -> detected
    else                  player.moveTo(vec2(1, 8));    // slip away; guards search
}

function main() {
    local player = Player(vec2(2, 4));
    local guards = [
        GuardNPC("Guard-1", vec2(4, 2),  [vec2(2, 2), vec2(6, 2), vec2(6, 6), vec2(2, 6)]),
        GuardNPC("Guard-2", vec2(11, 3), [vec2(10, 2), vec2(14, 2), vec2(14, 6), vec2(10, 6)]),
        GuardNPC("Guard-3", vec2(26, 12),[vec2(24, 11), vec2(29, 11), vec2(29, 14), vec2(24, 14)]),
    ];
    local world = makeWorld(player, guards, 10.0);  // guards within 10 units hear an alert

    local deltaTime = 0.5;
    local time = 0.0;

    print("=== SQUIRREL NPC SQUAD DEMO ===\n");
    print("Guard-1 and Guard-2 are close; Guard-3 patrols far away and won't hear the alert.\n\n");

    while (time <= 16.0 && player.alive) {
        scriptedPlayerMovement(time, player);
        print(format("[t=%4.1f] Player=%s | %s | %s | %s\n",
            time, positionText(player.position),
            guards[0].status(), guards[1].status(), guards[2].status()));
        renderArena(player, guards, 20, 9);

        foreach (g in guards) g.update(deltaTime, world);
        time += deltaTime;
    }

    print("\n=== SIMULATION COMPLETE ===\n");
}

main();

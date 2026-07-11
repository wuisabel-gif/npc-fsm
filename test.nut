// FSM self-check — sq test.nut
// Drives a guard through every transition and asserts the states occur in order.
// Doubles as the smallest possible host: a stub world + stub target.

dofile("guard.nut", true);

// Minimal target entity — the duck-type the guard needs.
local target = { position = vec2(100, 100), alive = true, takeDamage = function(n) {} };

// Minimal world adapter: distance sight, events ignored.
local world = {
    target = target,
    canSee = function(guard, t) {
        return t.alive && vecDistance(guard.position, t.position) <= guard.sightRange;
    },
    emit = function(guard, event, data) {}
};

// Step until the guard's state changes (or `cap` ticks pass), recording each new state.
function advance(guard, world, seen, cap) {
    local start = guard.state;
    for (local i = 0; i < cap; i++) {
        guard.update(0.5, world);
        if (guard.state != start) { seen.push(guard.state); return; }
    }
}

// Assert `expected` appears as an in-order subsequence of `seen`.
function assertOrder(seen, expected) {
    local j = 0;
    foreach (s in seen) if (j < expected.len() && s == expected[j]) j++;
    if (j != expected.len()) throw "expected FSM path not observed";
}

function run() {
    local route = [vec2(0, 0), vec2(6, 0), vec2(6, 6), vec2(0, 6)];
    local guard = GuardNPC("Test", vec2(0, 0), route);
    local seen = [guard.state];

    assert(guard.state == "PATROL");

    target.position = vec2(2, 0);                       // inside sight range -> CHASE
    advance(guard, world, seen, 2);
    advance(guard, world, seen, 20);                    // close the gap -> ATTACK

    target.position = vec2(100, 100);                   // escape -> CHASE -> SEARCH -> RETURN -> PATROL
    advance(guard, world, seen, 2);                     // ATTACK -> CHASE
    advance(guard, world, seen, 2);                     // CHASE -> SEARCH
    advance(guard, world, seen, 20);                    // SEARCH -> RETURN
    advance(guard, world, seen, 60);                    // RETURN -> PATROL (walk home)

    assertOrder(seen, ["PATROL", "CHASE", "ATTACK", "CHASE", "SEARCH", "RETURN", "PATROL"]);

    guard.takeDamage(world, 999, vec2(1, 0));           // lethal -> DEAD
    assert(guard.state == "DEAD");

    local path = "";
    foreach (s in seen) path += (path == "" ? "" : " -> ") + s;
    print("test.nut: all transitions OK  " + path + "\n");
}

run();

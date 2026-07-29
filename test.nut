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

function assertWorldError(world, expected) {
    local failed = false;
    try {
        validateWorld(world);
    } catch (error) {
        failed = true;
        assert(error == expected);
    }
    assert(failed);
}

// The adapter contract fails early with a useful error instead of a missing
// member/call error deep inside a state update.
function testWorldContract() {
    local valid = { target = null,
        canSee = function(guard, t) { return false; },
        emit = function(guard, event, data) {} };
    assert(validateWorld(valid) == valid);

    assertWorldError({ target = null, emit = valid.emit },
        "world.canSee(guard, target) callback is required");
    assertWorldError({ target = null, canSee = valid.canSee },
        "world.emit(guard, event, data) callback is required");
    assertWorldError({ target = null, canSee = valid.canSee,
        emit = valid.emit, moveToward = true },
        "world.moveToward(guard, destination, distance) must be a function");
    assertWorldError({ canSee = valid.canSee, emit = valid.emit },
        "world.target is required");
    print("test.nut: world contract OK\n");
}

// Omitting moveToward preserves the built-in straight-line fallback; supplying
// it delegates movement and uses the adapter's returned position.
function testOptionalMovement() {
    local route = [vec2(10, 0)];
    local noNavigation = { target = null,
        canSee = function(guard, t) { return false; },
        emit = function(guard, event, data) {} };
    local fallbackGuard = GuardNPC("Fallback", vec2(0, 0), route);
    fallbackGuard.update(1.0, noNavigation);
    assert(fallbackGuard.position.x > 0.0);
    assert(fallbackGuard.position.x < 10.0);

    local calls = 0;
    local navigation = { target = null,
        canSee = noNavigation.canSee, emit = noNavigation.emit,
        moveToward = function(guard, destination, distance) {
            calls++;
            return vec2(7, 3);
        } };
    local routedGuard = GuardNPC("Routed", vec2(0, 0), route);
    routedGuard.update(1.0, navigation);
    assert(calls == 1);
    assert(routedGuard.position.x == 7 && routedGuard.position.y == 3);
    print("test.nut: optional movement OK\n");
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

// alertTo(): a calm guard goes to investigate the reported spot; an already
// engaged (or dead) guard ignores the call.
function testAlert() {
    local route = [vec2(0, 0), vec2(6, 0), vec2(6, 6), vec2(0, 6)];

    local calm = GuardNPC("Calm", vec2(0, 0), route);
    calm.alertTo(world, vec2(5, 5));
    assert(calm.state == "SEARCH");
    assert(vecDistance(calm.lastKnownPlayerPosition, vec2(5, 5)) < 0.001);

    local engaged = GuardNPC("Engaged", vec2(0, 0), route);
    engaged.state = "ATTACK";
    engaged.alertTo(world, vec2(9, 9));
    assert(engaged.state == "ATTACK");

    print("test.nut: alertTo OK\n");
}

run();
testAlert();
testWorldContract();
testOptionalMovement();

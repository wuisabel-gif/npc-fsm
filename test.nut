// FSM self-check — sq test.nut
// Drives a guard through every transition and asserts the states occur in order.
// Doubles as the smallest possible host: a stub world + stub target.

dofile("guard.nut", true);
dofile("mock_world.nut", true);

// Minimal duck-typed target entity. The mock deliberately controls visibility
// independently of position, so adapter tests are deterministic.
local target = {
    position = vec2(100, 100), alive = true, damageTaken = 0,
    takeDamage = function(amount) { damageTaken += amount; }
};
local world = makeMockWorld(target, false);

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
    local noNavigation = makeMockWorld(null, false);
    assert(!("moveToward" in noNavigation));
    local fallbackGuard = GuardNPC("Fallback", vec2(0, 0), route);
    fallbackGuard.update(1.0, noNavigation);
    assert(fallbackGuard.position.x > 0.0);
    assert(fallbackGuard.position.x < 10.0);

    local navigation = makeMockWorld(null, false,
        function(guard, destination, distance) { return vec2(7, 3); });
    assert(("moveToward" in navigation) && typeof navigation.moveToward == "function");
    local routedGuard = GuardNPC("Routed", vec2(0, 0), route);
    routedGuard.update(1.0, navigation);
    assert(navigation.moveTowardCalls == 1);
    assert(routedGuard.position.x == 7 && routedGuard.position.y == 3);
    print("test.nut: optional movement OK\n");
}

function run() {
    local route = [vec2(0, 0), vec2(6, 0), vec2(6, 6), vec2(0, 6)];
    local guard = GuardNPC("Test", vec2(0, 0), route);
    local seen = [guard.state];

    assert(guard.state == "PATROL");

    world.setVisible(true);                            // deterministic -> CHASE
    target.position = vec2(2, 0);
    advance(guard, world, seen, 2);
    advance(guard, world, seen, 20);                    // close the gap -> ATTACK
    guard.update(0.5, world);                            // attack while engaged

    world.setVisible(false);                           // escape -> CHASE -> SEARCH -> RETURN -> PATROL
    target.position = vec2(100, 100);
    advance(guard, world, seen, 2);                     // ATTACK -> CHASE
    advance(guard, world, seen, 2);                     // CHASE -> SEARCH
    advance(guard, world, seen, 20);                    // SEARCH -> RETURN
    advance(guard, world, seen, 60);                    // RETURN -> PATROL (walk home)

    assertOrder(seen, ["PATROL", "CHASE", "ATTACK", "CHASE", "SEARCH", "RETURN", "PATROL"]);

    local alerts = world.eventsNamed("alert");
    assert(alerts.len() == 1);
    assert(alerts[0].guard == guard);
    assert(alerts[0].data.position.x == 2);

    local attacks = world.eventsNamed("attack");
    assert(attacks.len() >= 1);
    assert(attacks[0].guard == guard);
    assert(attacks[0].data.damage == guard.attackDamage);
    assert(target.damageTaken == guard.attackDamage);

    guard.takeDamage(world, 999, vec2(1, 0));           // lethal -> DEAD
    assert(guard.state == "DEAD");
    local deaths = world.eventsNamed("death");
    assert(deaths.len() == 1 && deaths[0].guard == guard);
    local stateEvents = world.eventsNamed("state");
    assert(stateEvents.len() > 0);

    // A dead guard must not call the adapter or emit another event.
    local eventCount = world.events.len();
    local seeCount = world.canSeeCalls;
    guard.update(10.0, world);
    guard.takeDamage(world, 1, vec2(2, 2));
    guard.alertTo(world, vec2(8, 8));
    assert(world.events.len() == eventCount);
    assert(world.canSeeCalls == seeCount);

    local path = "";
    foreach (s in seen) path += (path == "" ? "" : " -> ") + s;
    print("test.nut: all transitions OK  " + path + "\n");
}

// alertTo(): a calm guard goes to investigate the reported spot; an already
// engaged (or dead) guard ignores the call.
function testAlert() {
    local route = [vec2(0, 0), vec2(6, 0), vec2(6, 6), vec2(0, 6)];

    local calm = GuardNPC("Calm", vec2(0, 0), route);
    world.clearEvents();
    calm.alertTo(world, vec2(5, 5));
    assert(calm.state == "SEARCH");
    assert(vecDistance(calm.lastKnownPlayerPosition, vec2(5, 5)) < 0.001);
    local alerts = world.eventsNamed("state");
    assert(alerts.len() == 1 && alerts[0].data.from == "PATROL");

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

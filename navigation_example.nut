// Runnable deterministic navigation adapter example.
// Run: sq navigation_example.nut

dofile("guard.nut", true);
dofile("grid_navigation.nut", true);

function assertNear(actual, expected, message) {
    if (fabs(actual - expected) > 0.001) throw message;
}

local navigator = GridNavigator(7, 5, [
    vec2(2, 0), vec2(2, 1), vec2(2, 2), vec2(2, 3),
    vec2(4, 1), vec2(4, 2), vec2(4, 3)
]);

local target = { position = vec2(6, 4), alive = true,
    takeDamage = function(amount) {} };
local world = {
    target = target,
    canSee = function(guard, seenTarget) { return false; },
    emit = function(guard, event, data) {},
    moveToward = function(guard, destination, distance) {
        return navigator.moveToward(guard, destination, distance);
    }
};
validateWorld(world);

// The direct east route is walled off. The returned position must follow the
// deterministic north/east detour and must be assigned by GuardNPC.update().
local guard = GuardNPC("Navigator", vec2(0, 0), [vec2(6, 4)]);
guard.update(1.0, world);
assertNear(guard.position.x, 1.0, "first navigation step should move east");
assertNear(guard.position.y, 0.8, "first step should continue along the row");

guard.update(1.0, world);
assertNear(guard.position.x, 1.0, "detour should avoid blocked cell (2,0)");
assertNear(guard.position.y, 2.6, "detour should move around the wall");

local start = vec2(guard.position.x, guard.position.y);
local returned = navigator.moveToward(guard, vec2(2, 0), 10.0);
assertNear(returned.x, start.x, "blocked destination must not change x");
assertNear(returned.y, start.y, "blocked destination must not change y");

print("navigation_example.nut: grid adapter OK\n");
print("navigation_example.nut: authoritative position " +
    positionText(guard.position) + " (blocked cells avoided)\n");

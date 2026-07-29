// Deterministic world adapter for host-side tests.
//
// makeMockWorld(target, visible, moveTowardCallback) returns the same duck-typed
// adapter used by GuardNPC. Visibility is explicit (and does not depend on
// distance); movement is omitted unless a delegate is supplied, preserving the
// guard's built-in fallback. Every emit call is retained in world.events as
// {guard, event, data}; adapter call counters are available for assertions.

function makeMockWorld(target, visible = false, moveTowardCallback = null) {
    local world = {
        target = target,
        visible = visible,
        events = [],
        canSeeCalls = 0,
        emitCalls = 0,
        moveTowardCalls = 0
    };

    world.canSee <- function(guard, seenTarget) {
        canSeeCalls++;
        return visible && seenTarget != null && seenTarget.alive;
    };

    world.emit <- function(guard, event, data) {
        emitCalls++;
        events.push({ guard = guard, event = event, data = data });
    };

    // Do not install the property for the fallback case: GuardNPC detects the
    // optional adapter capability by member presence.
    if (moveTowardCallback != null) {
        world.moveToward <- function(guard, destination, distance) {
            moveTowardCalls++;
            return moveTowardCallback(guard, destination, distance);
        };
    }

    world.setVisible <- function(value) {
        visible = value;
        world.visible = value;
    };

    world.clearEvents <- function() {
        events.clear();
    };

    world.eventsNamed <- function(eventName) {
        local matches = [];
        foreach (entry in events)
            if (entry.event == eventName) matches.push(entry);
        return matches;
    };

    return world;
}

// Short alias for hosts that prefer a constructor-shaped name.
function MockWorld(target, visible = false, moveTowardCallback = null) {
    return makeMockWorld(target, visible, moveTowardCallback);
}

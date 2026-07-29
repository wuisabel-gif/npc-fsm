// Host-side perception helpers. The guard library deliberately does not depend on
// these; copy or replace this adapter with your engine's FOV and raycast code.

// Return true when target is inside a distance + facing cone. `occluded` is an
// optional function(guard, target) -> bool supplied by the host.
function fovCanSee(guard, target, facing, halfAngleDegrees, occluded) {
    if (target == null || !target.alive) return false;

    local offset = vecSub(target.position, guard.position);
    local distance = vecLength(offset);
    if (distance > guard.sightRange) return false;

    // A target at the guard's position is visible regardless of orientation.
    if (distance <= 0.0001) return true;

    local direction = vecNormalize(facing);
    if (vecLength(direction) <= 0.0001) return false;

    // Comparing the dot product avoids acos and is stable at the cone edges.
    local radians = halfAngleDegrees * 0.0174532925199433;
    local minimumDot = cos(radians);
    if (direction.x * (offset.x / distance)
        + direction.y * (offset.y / distance) < minimumDot) return false;

    return occluded == null || !occluded(guard, target);
}

// Example facing source: point along the current patrol leg. A real host should
// update this from its animation/locomotion component instead.
function patrolFacing(guard) {
    if (guard.patrolPoints.len() == 0) return vec2(1, 0);
    local destination = guard.patrolPoints[guard.patrolIndex];
    if (vecDistance(guard.position, destination) <= guard.waypointTolerance) {
        destination = guard.patrolPoints[(guard.patrolIndex + 1) % guard.patrolPoints.len()];
    }
    local facing = vecSub(destination, guard.position);
    return vecLength(facing) <= 0.0001 ? vec2(1, 0) : vecNormalize(facing);
}

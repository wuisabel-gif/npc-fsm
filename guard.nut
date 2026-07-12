// Reusable NPC guard behavior — engine-independent finite-state machine.
// dofile("guard.nut") in your game and drive it with your own `world` host.
//
// Each frame call:  guard.update(deltaTime, world)
// when the guard is hit:  guard.takeDamage(world, amount, attackerPosition)
// to summon it to a disturbance:  guard.alertTo(world, position)
//
// The `world` object is YOUR adapter into the engine. It must provide:
//   world.target                    -> the entity this guard reacts to, or null
//   world.canSee(guard, target)     -> bool. Your FOV + raycast/occlusion test.
//   world.emit(guard, event, data)  -> you react: animation, sound, UI, or log.
//   world.moveToward(guard,dest,max)-> OPTIONAL. Move via your navmesh/physics and
//                                      return the new position {x,y}. Omit it and the
//                                      guard uses the built-in straight-line fallback.
//
// The target entity is duck-typed — it must expose:
//   .position {x,y}   .alive (bool)   .takeDamage(amount)
//
// Events emitted through world.emit (data payload in braces):
//   "state"    {from, to}          "waypoint" {index}
//   "attack"   {damage}            "damaged"  {amount, health}
//   "death"    {}                  "alert"    {position}  <- guard just detected the target
//
// Detection is gradual: a suspicion meter fills while the target is visible and
// drains when it is not; CHASE begins only when it reaches 1.0. On detection the
// guard emits "alert" with the target's last known position — a host can forward
// that to nearby guards via their alertTo(world, position) to make a squad react.
//
// See demo.nut for a complete example host (distance-based sight, print events).

const STATE_PATROL = "PATROL";
const STATE_CHASE  = "CHASE";
const STATE_ATTACK = "ATTACK";
const STATE_SEARCH = "SEARCH";
const STATE_RETURN = "RETURN";
const STATE_DEAD   = "DEAD";

// --- vector helpers ------------------------------------------------------
// Your engine can ignore these and use its own math; they exist so a simple
// host works with zero extra code (see world.moveToward above).

function clamp(value, minimum, maximum) {
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
}

function vec2(x, y) {
    return { x = x.tofloat(), y = y.tofloat() };
}

function vecAdd(a, b)        { return vec2(a.x + b.x, a.y + b.y); }
function vecSub(a, b)        { return vec2(a.x - b.x, a.y - b.y); }
function vecScale(v, scalar) { return vec2(v.x * scalar, v.y * scalar); }
function vecLength(v)        { return sqrt(v.x * v.x + v.y * v.y); }
function vecDistance(a, b)   { return vecLength(vecSub(a, b)); }

function vecNormalize(v) {
    local length = vecLength(v);
    if (length <= 0.0001) return vec2(0, 0);
    return vecScale(v, 1.0 / length);
}

function moveToward(current, target, maxDistance) {
    local offset = vecSub(target, current);
    local distance = vecLength(offset);
    if (distance <= maxDistance || distance <= 0.0001) {
        return vec2(target.x, target.y);
    }
    return vecAdd(current, vecScale(vecNormalize(offset), maxDistance));
}

function positionText(position) {
    return format("(%.1f, %.1f)", position.x, position.y);
}

// --- the guard -----------------------------------------------------------

class GuardNPC {
    static VERSION = "0.1.0";   // read as GuardNPC.VERSION to check the vendored copy

    name = "Guard";
    position = null;
    patrolPoints = null;
    patrolIndex = 0;
    state = STATE_PATROL;

    health = 100;
    walkSpeed = 1.8;
    chaseSpeed = 3.4;
    sightRange = 8.0;
    attackRange = 1.4;
    loseTargetRange = 11.0;
    attackDamage = 12;
    attackCooldown = 1.25;
    attackTimer = 0.0;
    searchDuration = 4.0;
    searchTimer = 0.0;
    waypointTolerance = 0.15;

    // Detection is gradual: a 0..1 meter that fills while the target is visible
    // (faster up close) and drains when it is not. CHASE begins only at 1.0.
    suspicion = 0.0;
    suspicionRise = 1.6;      // per second at point-blank
    suspicionDecay = 0.5;     // per second while unseen
    suspicionFloor = 0.2;     // minimum fill rate at the edge of sight

    lastKnownPlayerPosition = null;
    homePosition = null;

    constructor(npcName, startPosition, points) {
        name = npcName;
        position = vec2(startPosition.x, startPosition.y);
        homePosition = vec2(startPosition.x, startPosition.y);
        patrolPoints = points;
        lastKnownPlayerPosition = vec2(startPosition.x, startPosition.y);
    }

    // Move via the host's navigation if it supplies one, else straight line.
    function step(world, dest, maxDist) {
        return ("moveToward" in world)
            ? world.moveToward(this, dest, maxDist)
            : moveToward(position, dest, maxDist);
    }

    // The target if the host says we can currently see it, else null.
    function perceive(world) {
        local t = world.target;
        return (t != null && world.canSee(this, t)) ? t : null;
    }

    function remember(target) {
        lastKnownPlayerPosition = vec2(target.position.x, target.position.y);
    }

    // Fill the suspicion meter while the target is visible, drain it otherwise.
    function senseSuspicion(deltaTime, world) {
        local seen = perceive(world);
        if (seen) {
            local d = vecDistance(position, seen.position);
            local closeness = clamp(1.0 - d / sightRange, suspicionFloor, 1.0);
            suspicion = clamp(suspicion + suspicionRise * closeness * deltaTime, 0.0, 1.0);
        } else {
            suspicion = clamp(suspicion - suspicionDecay * deltaTime, 0.0, 1.0);
        }
        return seen;
    }

    // Called from the calm states: once the meter tops out, raise the alarm
    // (so nearby guards can be alerted) and commit to the chase.
    function tryDetect(world) {
        if (suspicion < 1.0) return false;
        world.emit(this, "alert", { position = lastKnownPlayerPosition });
        setState(world, STATE_CHASE);
        return true;
    }

    // A guard told about a disturbance goes to investigate it (unless already engaged).
    function alertTo(world, alertPosition) {
        if (state == STATE_DEAD || state == STATE_CHASE || state == STATE_ATTACK) return;
        lastKnownPlayerPosition = vec2(alertPosition.x, alertPosition.y);
        setState(world, STATE_SEARCH);
    }

    function setState(world, nextState) {
        if (state == nextState) return;
        world.emit(this, "state", { from = state, to = nextState });
        state = nextState;
        if (state == STATE_SEARCH) searchTimer = searchDuration;
        // Reset the meter on any transition out of calm patrolling so a guard
        // that just lost the target has to re-detect rather than snap back.
        if (state == STATE_CHASE || state == STATE_SEARCH || state == STATE_RETURN) suspicion = 0.0;
    }

    function update(deltaTime, world) {
        if (state == STATE_DEAD) return;
        attackTimer = clamp(attackTimer - deltaTime, 0.0, attackCooldown);

        switch (state) {
            case STATE_PATROL: updatePatrol(deltaTime, world); break;
            case STATE_CHASE:  updateChase(deltaTime, world);  break;
            case STATE_ATTACK: updateAttack(deltaTime, world); break;
            case STATE_SEARCH: updateSearch(deltaTime, world); break;
            case STATE_RETURN: updateReturn(deltaTime, world); break;
        }
    }

    function updatePatrol(deltaTime, world) {
        local seen = senseSuspicion(deltaTime, world);
        if (seen) remember(seen);
        if (tryDetect(world)) return;

        local target = patrolPoints[patrolIndex];
        position = step(world, target, walkSpeed * deltaTime);

        if (vecDistance(position, target) <= waypointTolerance) {
            patrolIndex = (patrolIndex + 1) % patrolPoints.len();
            world.emit(this, "waypoint", { index = patrolIndex });
        }
    }

    function updateChase(deltaTime, world) {
        local target = world.target;
        if (perceive(world)) remember(target);

        if (target == null || !target.alive) { setState(world, STATE_RETURN); return; }

        local distance = vecDistance(position, target.position);
        if (distance <= attackRange)      { setState(world, STATE_ATTACK); return; }
        if (distance > loseTargetRange)   { setState(world, STATE_SEARCH); return; }

        position = step(world, lastKnownPlayerPosition, chaseSpeed * deltaTime);
    }

    function updateAttack(deltaTime, world) {
        local target = world.target;
        if (target == null || !target.alive) { setState(world, STATE_RETURN); return; }

        local distance = vecDistance(position, target.position);
        if (distance > attackRange) { setState(world, STATE_CHASE); return; }

        remember(target);
        if (attackTimer <= 0.0) {
            world.emit(this, "attack", { damage = attackDamage });
            target.takeDamage(attackDamage);
            attackTimer = attackCooldown;
        }
    }

    function updateSearch(deltaTime, world) {
        local seen = senseSuspicion(deltaTime, world);
        if (seen) remember(seen);
        if (tryDetect(world)) return;

        position = step(world, lastKnownPlayerPosition, walkSpeed * deltaTime);
        searchTimer -= deltaTime;
        if (searchTimer <= 0.0) setState(world, STATE_RETURN);
    }

    function updateReturn(deltaTime, world) {
        local seen = senseSuspicion(deltaTime, world);
        if (seen) remember(seen);
        if (tryDetect(world)) return;

        local target = patrolPoints[patrolIndex];
        position = step(world, target, walkSpeed * deltaTime);
        if (vecDistance(position, target) <= waypointTolerance) setState(world, STATE_PATROL);
    }

    function takeDamage(world, amount, attackerPosition) {
        if (state == STATE_DEAD) return;
        health = clamp(health - amount, 0, 100);
        lastKnownPlayerPosition = vec2(attackerPosition.x, attackerPosition.y);
        world.emit(this, "damaged", { amount = amount, health = health });

        if (health <= 0) {
            setState(world, STATE_DEAD);
            world.emit(this, "death", {});
        } else {
            setState(world, STATE_CHASE);
        }
    }

    function status() {
        return format("%s %-6s pos=%s hp=%d susp=%.0f%%",
            name, state, positionText(position), health, suspicion * 100.0);
    }
}

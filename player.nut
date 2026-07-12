// Example target entity, shared by the demo hosts. Load after guard.nut (it uses
// vec2/clamp). Your real game supplies its own entity — the guard only needs
// .position {x,y}, .alive (bool), and .takeDamage(amount).

class Player {
    position = null;
    health = 100;
    alive = true;

    constructor(startPosition) { position = vec2(startPosition.x, startPosition.y); }
    function moveTo(newPosition) { position = vec2(newPosition.x, newPosition.y); }

    function takeDamage(amount) {
        if (!alive) return;
        health = clamp(health - amount, 0, 100);
        print(format("  PLAYER takes %d damage; health=%d\n", amount, health));
        if (health <= 0) { alive = false; print("  PLAYER has been defeated.\n"); }
    }
}

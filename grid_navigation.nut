// Deterministic grid navigation adapter for the world.moveToward contract.
// This is an example host-side adapter, not part of guard.nut.
// Coordinates are integer grid cells; blocked cells cannot be entered.

class GridNavigator {
    width = 0;
    height = 0;
    blocked = null;

    constructor(gridWidth, gridHeight, blockedCells) {
        width = gridWidth;
        height = gridHeight;
        blocked = {};
        foreach (cell in blockedCells) blocked[key(cell.x, cell.y)] <- true;
    }

    function key(x, y) { return format("%d,%d", x, y); }

    function inBounds(x, y) {
        return x >= 0 && x < width && y >= 0 && y < height;
    }

    function walkable(x, y) {
        return inBounds(x, y) && !(key(x, y) in blocked);
    }

    function cell(position) {
        return { x = floor(position.x + 0.5).tointeger(),
                 y = floor(position.y + 0.5).tointeger() };
    }

    // Breadth-first search gives a short, repeatable path. Neighbor order is
    // deliberate so equal-length paths always choose the same route.
    function path(from, to) {
        if (!walkable(from.x, from.y) || !walkable(to.x, to.y)) return null;

        local queue = [{ x = from.x, y = from.y }];
        local head = 0;
        local parent = {};
        // false is a retained sentinel; assigning null would remove a Squirrel table key.
        parent[key(from.x, from.y)] <- false;
        local directions = [
            { x = 1, y = 0 }, { x = 0, y = 1 },
            { x = -1, y = 0 }, { x = 0, y = -1 }
        ];

        while (head < queue.len()) {
            local current = queue[head++];
            if (current.x == to.x && current.y == to.y) break;
            foreach (direction in directions) {
                local next = { x = current.x + direction.x,
                               y = current.y + direction.y };
                local nextKey = key(next.x, next.y);
                if (walkable(next.x, next.y) && !(nextKey in parent)) {
                    parent[nextKey] <- current;
                    queue.push(next);
                }
            }
        }

        local destinationKey = key(to.x, to.y);
        if (!(destinationKey in parent)) return null;
        local reversed = [];
        local cursor = to;
        while (cursor != null) {
            reversed.push(cursor);
            local previous = parent[key(cursor.x, cursor.y)];
            cursor = previous == false ? null : previous;
        }
        local result = [];
        for (local i = reversed.len() - 1; i >= 0; i--) result.push(reversed[i]);
        return result;
    }

    // Return the authoritative position after moving no farther than distance.
    // A real adapter would replace path() and this stepping code with its
    // navmesh/pathfinder query and the engine's collision-resolved transform.
    function moveToward(guard, destination, distance) {
        local current = cell(guard.position);
        local target = cell(destination);
        local route = path(current, target);
        if (route == null) return vec2(guard.position.x, guard.position.y);

        local position = vec2(guard.position.x, guard.position.y);
        local remaining = distance;
        for (local i = 1; i < route.len() && remaining > 0.0; i++) {
            local next = vec2(route[i].x, route[i].y);
            local segment = vecDistance(position, next);
            if (segment <= remaining) {
                position = next;
                remaining -= segment;
            } else {
                position = ::moveToward(position, next, remaining);
                remaining = 0.0;
            }
        }
        return position;
    }
}

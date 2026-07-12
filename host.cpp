// Minimal C++ host embedding the Squirrel VM to run guard.nut.
//
// This proves the "engine-independent" claim: the behaviour lives in guard.nut,
// while the ENGINE SIDE — perception (canSee), event reaction (emit), the target
// entity, and the frame loop — is implemented here in native C++. A real game
// swaps the bodies of canSee/emit for raycasts and animation calls; the script
// is untouched.
//
// Build (after `brew install squirrel-lang`, or point -I/-L at your own build):
//   c++ -std=c++11 host.cpp -I/opt/homebrew/include -L/opt/homebrew/lib \
//       -lsquirrel -lsqstdlib -o host && ./host
//
// It loads guard.nut from the working directory, so run it from the repo root.

#include <squirrel.h>
#include <sqstdio.h>
#include <sqstdaux.h>
#include <sqstdmath.h>
#include <sqstdstring.h>
#include <cstdio>
#include <cstdarg>
#include <cmath>

static void printfunc(HSQUIRRELVM, const SQChar *s, ...) {
    va_list vl; va_start(vl, s); vfprintf(stdout, s, vl); va_end(vl);
}

// --- reading fields off a Squirrel object at stack index `idx` ---
static SQFloat getFloat(HSQUIRRELVM v, SQInteger idx, const SQChar *key) {
    sq_pushstring(v, key, -1); sq_get(v, idx < 0 ? idx - 1 : idx);
    SQFloat f = 0; sq_getfloat(v, -1, &f); sq_poptop(v); return f;
}
static SQBool getBool(HSQUIRRELVM v, SQInteger idx, const SQChar *key) {
    sq_pushstring(v, key, -1); sq_get(v, idx < 0 ? idx - 1 : idx);
    SQBool b = SQFalse; sq_getbool(v, -1, &b); sq_poptop(v); return b;
}
// position is a nested table {x,y}; read one component of obj.<key>.<comp>
static SQFloat getVecComp(HSQUIRRELVM v, SQInteger idx, const SQChar *key, const SQChar *comp) {
    sq_pushstring(v, key, -1); sq_get(v, idx < 0 ? idx - 1 : idx);   // push obj[key] (a table)
    SQFloat f = getFloat(v, -1, comp);
    sq_poptop(v);
    return f;
}

// world.canSee(guard, target) -> bool.  ENGINE PERCEPTION lives here.
static SQInteger native_canSee(HSQUIRRELVM v) {
    // stack: 1=this(world) 2=guard 3=target
    SQFloat gx = getVecComp(v, 2, _SC("position"), _SC("x"));
    SQFloat gy = getVecComp(v, 2, _SC("position"), _SC("y"));
    SQFloat sr = getFloat(v, 2, _SC("sightRange"));
    SQBool alive = getBool(v, 3, _SC("alive"));
    SQFloat tx = getVecComp(v, 3, _SC("position"), _SC("x"));
    SQFloat ty = getVecComp(v, 3, _SC("position"), _SC("y"));
    SQFloat d = std::sqrt((gx - tx) * (gx - tx) + (gy - ty) * (gy - ty));
    sq_pushbool(v, alive && d <= sr);
    return 1;
}

// world.emit(guard, event, data).  ENGINE REACTION (animation/sound/UI) lives here.
static SQInteger native_emit(HSQUIRRELVM v) {
    // stack: 1=this 2=guard 3=event(string) 4=data(table)
    const SQChar *name = _SC("?"); sq_pushstring(v, _SC("name"), -1); sq_get(v, 2); sq_getstring(v, -1, &name);
    const SQChar *ev = _SC("?"); sq_getstring(v, 3, &ev);
    printf("  [engine] %s: event '%s'\n", name, ev);
    sq_poptop(v);
    return 0;
}

// target.takeDamage(amount): decrement health, flip alive at zero.
static SQInteger native_takeDamage(HSQUIRRELVM v) {
    SQInteger amount = 0; sq_getinteger(v, 2, &amount);
    SQInteger hp = (SQInteger)getFloat(v, 1, _SC("health")) - amount;
    if (hp < 0) hp = 0;
    sq_pushstring(v, _SC("health"), -1); sq_pushinteger(v, hp); sq_set(v, 1);
    if (hp == 0) { sq_pushstring(v, _SC("alive"), -1); sq_pushbool(v, SQFalse); sq_set(v, 1); }
    printf("  [engine] target hit for %d -> hp=%d\n", (int)amount, (int)hp);
    return 0;
}

// helper: put a {x,y} table on top of the stack
static void pushVec2(HSQUIRRELVM v, float x, float y) {
    sq_newtable(v);
    sq_pushstring(v, _SC("x"), -1); sq_pushfloat(v, x); sq_newslot(v, -3, SQFalse);
    sq_pushstring(v, _SC("y"), -1); sq_pushfloat(v, y); sq_newslot(v, -3, SQFalse);
}
static void addNative(HSQUIRRELVM v, const SQChar *name, SQFUNCTION f) {
    sq_pushstring(v, name, -1); sq_newclosure(v, f, 0); sq_newslot(v, -3, SQFalse);
}
static void addFloat(HSQUIRRELVM v, const SQChar *name, float val) {
    sq_pushstring(v, name, -1); sq_pushfloat(v, val); sq_newslot(v, -3, SQFalse);
}

int main() {
    HSQUIRRELVM v = sq_open(1024);
    sq_setprintfunc(v, printfunc, printfunc);
    sq_pushroottable(v);
    sqstd_register_mathlib(v);
    sqstd_register_stringlib(v);
    sqstd_seterrorhandlers(v);

    // Load guard.nut — this defines GuardNPC, vec2, etc. in the root table.
    if (SQ_FAILED(sqstd_dofile(v, _SC("guard.nut"), SQFalse, SQTrue))) {
        printf("failed to load guard.nut (run from the repo root)\n");
        return 1;
    }

    // --- build the target entity table ---
    HSQOBJECT target;
    sq_newtable(v);
    sq_pushstring(v, _SC("position"), -1); pushVec2(v, 12.0f, 5.0f); sq_newslot(v, -3, SQFalse);
    sq_pushstring(v, _SC("health"), -1); sq_pushinteger(v, 100); sq_newslot(v, -3, SQFalse);
    sq_pushstring(v, _SC("alive"), -1); sq_pushbool(v, SQTrue); sq_newslot(v, -3, SQFalse);
    addNative(v, _SC("takeDamage"), native_takeDamage);
    sq_getstackobj(v, -1, &target); sq_addref(v, &target);
    sq_poptop(v);

    // --- build the world adapter (native canSee/emit + the target) ---
    HSQOBJECT world;
    sq_newtable(v);
    sq_pushstring(v, _SC("target"), -1); sq_pushobject(v, target); sq_newslot(v, -3, SQFalse);
    addNative(v, _SC("canSee"), native_canSee);
    addNative(v, _SC("emit"), native_emit);
    sq_getstackobj(v, -1, &world); sq_addref(v, &world);
    sq_poptop(v);

    // --- construct GuardNPC("Guard", vec2(0,0), [ 4 patrol points ]) ---
    HSQOBJECT guard;
    sq_pushroottable(v);
    sq_pushstring(v, _SC("GuardNPC"), -1);
    sq_get(v, -2);                 // the class
    sq_pushroottable(v);           // 'this' for the constructor call
    sq_pushstring(v, _SC("Guard"), -1);
    pushVec2(v, 0.0f, 0.0f);
    sq_newarray(v, 0);
    float route[4][2] = {{0,0},{6,0},{6,6},{0,6}};
    for (int i = 0; i < 4; i++) { pushVec2(v, route[i][0], route[i][1]); sq_arrayappend(v, -2); }
    if (SQ_FAILED(sq_call(v, 4, SQTrue, SQTrue))) { printf("construct failed\n"); return 1; }
    sq_getstackobj(v, -1, &guard); sq_addref(v, &guard);
    sq_pop(v, 3);                  // instance, class, roottable

    // --- the frame loop, owned by C++ ---
    const float dt = 0.5f;
    printf("=== C++ HOST DRIVING guard.nut ===\n");
    for (int step = 0; step < 32; step++) {
        float t = step * dt;
        // C++ scripts the target: walk it into the guard's patrol area, then away.
        float tx = (t < 5.0f) ? 12.0f : (t < 10.0f) ? 4.0f : 30.0f;
        sq_pushobject(v, target);
        sq_pushstring(v, _SC("position"), -1); pushVec2(v, tx, 3.0f); sq_set(v, -3);
        sq_poptop(v);

        // guard.update(dt, world)
        sq_pushobject(v, guard);
        sq_pushstring(v, _SC("update"), -1); sq_get(v, -2);
        sq_pushobject(v, guard); sq_pushfloat(v, dt); sq_pushobject(v, world);
        sq_call(v, 3, SQFalse, SQTrue);
        sq_pop(v, 2);   // method, guard

        // read guard.state for the log
        sq_pushobject(v, guard);
        sq_pushstring(v, _SC("state"), -1); sq_get(v, -2);
        const SQChar *state = _SC("?"); sq_getstring(v, -1, &state);
        printf("[t=%4.1f] target.x=%4.1f  guard.state=%s\n", t, tx, state);
        sq_pop(v, 2);
    }

    sq_release(v, &guard); sq_release(v, &world); sq_release(v, &target);
    sq_close(v);
    return 0;
}

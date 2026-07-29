// C++11 reference host for embedding guard.nut in a Squirrel VM.
//
// The code below deliberately has two layers:
//   SquirrelVm/helpers: VM setup, script calls, and Squirrel value lifetime.
//   SampleWorld: a tiny world implementation used only by this runnable demo.
//
// A game should retain the VM and guard for the actor's lifetime, replace the
// SampleWorld callbacks with engine queries, and call update once per frame.
// Squirrel objects held in C++ are owned by an sq_addref/sq_release pair; the
// VM must outlive every such reference. Callbacks must resolve engine handles
// at call time and must not retain pointers to destroyed actors.
//
// Build from the repository root (Squirrel 3.x):
//   c++ -std=c++11 host.cpp -I/opt/homebrew/include -L/opt/homebrew/lib \
//       -lsquirrel -lsqstdlib -o host && ./host
// Adjust the include/library paths for another Squirrel installation.

#include <squirrel.h>
#include <sqstdio.h>
#include <sqstdaux.h>
#include <sqstdmath.h>
#include <sqstdstring.h>
#include <cstdarg>
#include <cmath>
#include <cstdio>

static void printfunc(HSQUIRRELVM, const SQChar *s, ...) {
    va_list args; va_start(args, s); vfprintf(stdout, s, args); va_end(args);
}

// These helpers use positive callback argument indexes. Negative indexes are
// adjusted because sq_get pushes the value being read onto the VM stack.
static SQInteger stableIndex(HSQUIRRELVM v, SQInteger index) {
    // The key is pushed immediately before sq_get; account for that push.
    return index < 0 ? sq_gettop(v) + index : index;
}
static bool getField(HSQUIRRELVM v, SQInteger object, const SQChar *key) {
    sq_pushstring(v, key, -1);
    return SQ_SUCCEEDED(sq_get(v, stableIndex(v, object)));
}
static bool getFloat(HSQUIRRELVM v, SQInteger object, const SQChar *key, SQFloat &out) {
    if (!getField(v, object, key)) return false;
    const SQRESULT result = sq_getfloat(v, -1, &out); sq_poptop(v); return SQ_SUCCEEDED(result);
}
static bool getBool(HSQUIRRELVM v, SQInteger object, const SQChar *key, SQBool &out) {
    if (!getField(v, object, key)) return false;
    const SQRESULT result = sq_getbool(v, -1, &out); sq_poptop(v); return SQ_SUCCEEDED(result);
}
static bool getVec2(HSQUIRRELVM v, SQInteger object, const SQChar *key, SQFloat &x, SQFloat &y) {
    if (!getField(v, object, key)) return false;
    const bool ok = getFloat(v, -1, _SC("x"), x) && getFloat(v, -1, _SC("y"), y);
    sq_poptop(v); return ok;
}
static void pushVec2(HSQUIRRELVM v, SQFloat x, SQFloat y) {
    sq_newtable(v);
    sq_pushstring(v, _SC("x"), -1); sq_pushfloat(v, x); sq_newslot(v, -3, SQFalse);
    sq_pushstring(v, _SC("y"), -1); sq_pushfloat(v, y); sq_newslot(v, -3, SQFalse);
}
static void addNative(HSQUIRRELVM v, const SQChar *name, SQFUNCTION function) {
    sq_pushstring(v, name, -1); sq_newclosure(v, function, 0); sq_newslot(v, -3, SQFalse);
}

class SquirrelVm {
public:
    SquirrelVm() : vm_(sq_open(1024)) {
        sq_setprintfunc(vm_, printfunc, printfunc);
        sq_pushroottable(vm_);
        sqstd_register_mathlib(vm_);
        sqstd_register_stringlib(vm_);
        sqstd_seterrorhandlers(vm_);
        // Keep the root table on the stack: sqstd_dofile uses it as `this`.
    }
    ~SquirrelVm() { if (vm_) sq_close(vm_); }
    HSQUIRRELVM get() const { return vm_; }
    bool load(const SQChar *file) {
        return SQ_SUCCEEDED(sqstd_dofile(vm_, file, SQFalse, SQTrue));
    }
private:
    HSQUIRRELVM vm_;
    SquirrelVm(const SquirrelVm &); // C++11: VM ownership is non-copyable.
    SquirrelVm &operator=(const SquirrelVm &);
};

// Sample engine callbacks. Replace the bodies, not guard.nut, with real
// visibility/raycast and presentation/damage systems in an embedding engine.
static SQInteger sampleCanSee(HSQUIRRELVM v) {
    SQFloat gx, gy, range, tx, ty; SQBool alive;
    const bool valid = getVec2(v, 2, _SC("position"), gx, gy) &&
        getFloat(v, 2, _SC("sightRange"), range) && getBool(v, 3, _SC("alive"), alive) &&
        getVec2(v, 3, _SC("position"), tx, ty);
    const SQFloat distance = valid ? std::sqrt((gx-tx)*(gx-tx) + (gy-ty)*(gy-ty)) : 0;
    sq_pushbool(v, valid && alive && distance <= range); return 1;
}
static SQInteger sampleTakeDamage(HSQUIRRELVM v) {
    SQInteger amount = 0; SQFloat health = 0;
    if (SQ_FAILED(sq_getinteger(v, 2, &amount)) || !getFloat(v, 1, _SC("health"), health)) return 0;
    SQInteger hp = static_cast<SQInteger>(health) - amount; if (hp < 0) hp = 0;
    sq_pushstring(v, _SC("health"), -1); sq_pushinteger(v, hp); sq_set(v, 1);
    if (hp == 0) { sq_pushstring(v, _SC("alive"), -1); sq_pushbool(v, SQFalse); sq_set(v, 1); }
    std::printf("  [engine] target hit for %d -> hp=%d\n", (int)amount, (int)hp); return 0;
}
static SQInteger sampleEmit(HSQUIRRELVM v) {
    const SQChar *name = _SC("?"), *event = _SC("?");
    if (getField(v, 2, _SC("name"))) { sq_getstring(v, -1, &name); sq_poptop(v); }
    if (SQ_FAILED(sq_getstring(v, 3, &event))) return 0;
    std::printf("  [engine] %s: event '%s'\n", name, event);
    // Production replacement point: dispatch state/attack/death/alert here.
    return 0;
}

class SampleWorld {
public:
    explicit SampleWorld(HSQUIRRELVM v) : vm_(v), target_(), world_() {
        makeTarget(); makeWorld();
    }
    ~SampleWorld() { sq_release(vm_, &world_); sq_release(vm_, &target_); }
    HSQOBJECT target() const { return target_; }
    HSQOBJECT object() const { return world_; }
    void moveTarget(SQFloat x, SQFloat y) {
        sq_pushobject(vm_, target_); sq_pushstring(vm_, _SC("position"), -1); pushVec2(vm_, x, y); sq_set(vm_, -3); sq_poptop(vm_);
    }
private:
    void makeTarget() {
        sq_newtable(vm_); sq_pushstring(vm_, _SC("position"), -1); pushVec2(vm_, 12, 5); sq_newslot(vm_, -3, SQFalse);
        sq_pushstring(vm_, _SC("health"), -1); sq_pushinteger(vm_, 100); sq_newslot(vm_, -3, SQFalse);
        sq_pushstring(vm_, _SC("alive"), -1); sq_pushbool(vm_, SQTrue); sq_newslot(vm_, -3, SQFalse);
        addNative(vm_, _SC("takeDamage"), sampleTakeDamage); sq_getstackobj(vm_, -1, &target_); sq_addref(vm_, &target_); sq_poptop(vm_);
    }
    void makeWorld() {
        sq_newtable(vm_); sq_pushstring(vm_, _SC("target"), -1); sq_pushobject(vm_, target_); sq_newslot(vm_, -3, SQFalse);
        addNative(vm_, _SC("canSee"), sampleCanSee); addNative(vm_, _SC("emit"), sampleEmit);
        sq_getstackobj(vm_, -1, &world_); sq_addref(vm_, &world_); sq_poptop(vm_);
    }
    HSQUIRRELVM vm_; HSQOBJECT target_, world_;
};

static bool makeGuard(HSQUIRRELVM v, HSQOBJECT &guard) {
    sq_pushroottable(v); sq_pushstring(v, _SC("GuardNPC"), -1); if (SQ_FAILED(sq_get(v, -2))) return false;
    sq_pushroottable(v); sq_pushstring(v, _SC("Guard"), -1); pushVec2(v, 0, 0); sq_newarray(v, 0);
    const SQFloat route[4][2] = {{0,0},{6,0},{6,6},{0,6}};
    for (int i=0; i<4; ++i) { pushVec2(v, route[i][0], route[i][1]); sq_arrayappend(v, -2); }
    if (SQ_FAILED(sq_call(v, 4, SQTrue, SQTrue))) { sq_settop(v, 0); return false; }
    sq_getstackobj(v, -1, &guard); sq_addref(v, &guard); sq_pop(v, 3); return true;
}

int main() {
    SquirrelVm squirrel; HSQUIRRELVM v = squirrel.get();
    if (!squirrel.load(_SC("guard.nut"))) { std::printf("failed to load guard.nut (run from repo root)\n"); return 1; }
    SampleWorld world(v); HSQOBJECT guard;
    if (!makeGuard(v, guard)) { std::printf("failed to construct GuardNPC\n"); return 1; }
    std::printf("=== C++ HOST DRIVING guard.nut ===\n"); const SQFloat dt = 0.5f;
    for (int step=0; step<32; ++step) {
        const SQFloat t = step * dt; const SQFloat tx = t < 5 ? 12 : (t < 10 ? 4 : 30); world.moveTarget(tx, 3);
        sq_pushobject(v, guard); sq_pushstring(v, _SC("update"), -1); sq_get(v, -2);
        sq_pushobject(v, guard); sq_pushfloat(v, dt); sq_pushobject(v, world.object());
        if (SQ_FAILED(sq_call(v, 3, SQFalse, SQTrue))) { std::printf("guard.update failed\n"); break; }
        sq_pop(v, 2); sq_pushobject(v, guard); sq_pushstring(v, _SC("state"), -1); sq_get(v, -2);
        const SQChar *state = _SC("?"); sq_getstring(v, -1, &state); std::printf("[t=%4.1f] target.x=%4.1f  guard.state=%s\n", t, tx, state); sq_pop(v, 2);
    }
    sq_release(v, &guard); return 0;
}

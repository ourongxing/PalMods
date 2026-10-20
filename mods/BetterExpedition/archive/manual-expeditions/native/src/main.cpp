#define NOMINMAX
#include <Windows.h>
#include <intrin.h>
#include <array>
#include <cstring>
#include <memory>
#include <random>
#include <set>
#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/UnrealInitializer.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <LuaType/LuaUObject.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <polyhook2/Detour/x64Detour.hpp>
#include "RewardRules.hpp"
#include "binary_guard.hpp"

namespace {
using namespace RC;
using namespace RC::Unreal;
std::uintptr_t base{};
using Clock = std::int64_t* (*)(std::int64_t*, void*);
using Cancel = void (*)(void*, int);
using Submit = void (*)(void*, void*);
std::uint64_t clock_original{}, cancel_original{}, submit_original{};
std::unique_ptr<PLH::x64Detour> clock_hook, cancel_hook, submit_hook;
bool active{};
struct Settlement { void* model; double ratio{}; bool clock_read{}, submitted{}; int reward_stacks{-1}; };
thread_local Settlement* settlement{};
std::mt19937_64 rng{std::random_device{}()};
double random_unit() { return std::generate_canonical<double, 53>(rng); }
template<class T> T read(void* object, std::size_t offset) {
    T value; std::memcpy(&value, static_cast<std::byte*>(object) + offset, sizeof(T)); return value;
}

// Only the completion comparison receives an adjusted clock. The saved start,
// real world clock, completion estimate and every other caller stay native.
std::int64_t* clock_now(std::int64_t* out, void* context) {
    auto* result = reinterpret_cast<Clock>(clock_original)(out, context);
    if (reinterpret_cast<std::uintptr_t>(_ReturnAddress()) != base + 0x3022d43 || !IsInGameThreadRaw()) return result;
    const auto complete = read<std::int64_t>(context, 640);
    if (settlement && settlement->model == context) {
        settlement->ratio = better_expedition::time_ratio(*out, read<std::int64_t>(context, 632), complete);
        settlement->clock_read = true;
        *out = std::max(*out, complete);
    } else if (complete > 0) {
        *out = std::min(*out, complete - 1);
    }
    return result;
}

void submit(void* container, void* request) {
    if (!settlement || !settlement->clock_read || settlement->submitted
        || reinterpret_cast<std::uintptr_t>(_ReturnAddress()) != base + 0x30095c1)
        return reinterpret_cast<Submit>(submit_original)(container, request);
    settlement->submitted = true;
    // The game's owned FPalItemIdAndNum array: 40-byte item ID + int32 quantity.
    // Compact in place; elements contain no owning pointers. Native code retains
    // responsibility for allocation, copying, notifications and destruction.
    auto* bytes = static_cast<std::byte*>(request);
    auto* items = read<std::byte*>(request, 0x60);
    const auto count = read<int>(request, 0x68);
    const auto capacity = read<int>(request, 0x6c);
    if (count < 0 || count > capacity || count > 100000 || (count && !items)) {
        Output::send(STR("[BetterExpedition] Invalid native reward array; reward submission rejected.\n"));
        return;
    }
    int kept{};
    for (int i = 0; i < count; ++i) {
        auto* item = items + i * 44;
        const auto vanilla = read<int>(item, 40);
        const auto n = better_expedition::quantity(vanilla, settlement->ratio, random_unit());
        Output::send(STR("[BetterExpedition] Reward stack {}: vanilla={} proportional={}\n"), i, vanilla, n);
        if (!n) continue;
        if (kept != i) std::memmove(items + kept * 44, item, 44);
        std::memcpy(items + kept * 44 + 40, &n, sizeof(n));
        ++kept;
    }
    std::memcpy(bytes, &kept, sizeof(kept));
    std::memcpy(bytes + 0x68, &kept, sizeof(kept));
    settlement->reward_stacks = kept;
    if (kept) reinterpret_cast<Submit>(submit_original)(container, request);
}

void finish(void* model, int player_id) {
    if (!IsInGameThreadRaw() || settlement || read<std::uint8_t>(model, 624) != 2) return;
    // Identical requesting-player -> stable player UID -> guild permission
    // checks to the vanilla cancel handler, before any reward or state change.
    std::array<std::byte, 16> uid{};
    reinterpret_cast<void* (*)(void*, void*, int)>(base + 0x32f34f0)(uid.data(), model, player_id);
    if (!reinterpret_cast<bool (*)(void*, void*)>(base + 0x30b9fe0)(model, uid.data())) return;
    Settlement current{model};
    settlement = &current;
    reinterpret_cast<void (*)(void*)>(base + 0x3022c40)(model);
    settlement = nullptr;
    // No item may survive fractional rounding on an immediate recall. Run the
    // same empty-container notification used after Take All, so the station
    // returns to Ready instead of waiting forever for an empty reward chest.
    if (current.reward_stacks == 0 && read<std::uint8_t>(model, 624) == 3) {
        auto* module = reinterpret_cast<void* (*)(void*)>(base + 0x2fff160)(model);
        if (module) reinterpret_cast<void (*)(void*, void*)>(base + 0x3019e10)(model, module);
    }
    Output::send(STR("[BetterExpedition] Manual finish: time ratio={}, state={}, reward stacks={}.\n"),
        current.ratio, read<std::uint8_t>(model, 624), current.reward_stacks);
}

int status(const LuaMadeSimple::Lua& lua) {
    if (!active || !IsInGameThreadRaw() || !lua.is_userdata()) { lua.set_bool(false); return 1; }
    auto* object = lua.get_userdata<LuaType::UObject>().get_remote_cpp_object();
    auto* cls = UObjectGlobals::StaticFindObject<UClass*>(nullptr, nullptr, STR("/Script/Pal.PalMapObjectCharacterTeamMissionModel"));
    if (!object || reinterpret_cast<std::uintptr_t>(object) < 0x10000 || !cls || !object->IsA(cls)) { lua.set_bool(false); return 1; }
    std::int64_t now{};
    reinterpret_cast<Clock>(clock_original)(&now, object);
    const auto start = read<std::int64_t>(object, 632), complete = read<std::int64_t>(object, 640);
    lua.set_bool(read<std::uint8_t>(object, 624) == 2);
    lua.set_number(std::max(0., static_cast<double>(now - start) / 10000000.));
    lua.set_number(better_expedition::time_ratio(now, start, complete));
    return 3;
}
int is_active(const LuaMadeSimple::Lua& lua) { lua.set_bool(active); return 1; }

class Mod final : public CppUserModBase {
public:
    Mod() { ModName = STR("BetterExpedition"); ModVersion = STR("0.1.0"); ModAuthors = STR("ourongxing");
        ModDescription = STR("Manual expeditions with vanilla-calibrated proportional rewards"); }
    void on_lua_start(StringViewType name, LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua& main,
                      LuaMadeSimple::Lua& async, LuaMadeSimple::Lua* hook) override {
        if (name != STR("BetterExpedition")) return;
        std::set<LuaMadeSimple::Lua*> instances{&lua, &main, &async};
        if (hook) instances.insert(hook);
        for (auto* instance : instances) {
            instance->register_function("BetterExpeditionNativeStatus", &status);
            instance->register_function("BetterExpeditionNativeIsActive", &is_active);
        }
    }
    void on_unreal_init() override {
        base = reinterpret_cast<std::uintptr_t>(GetModuleHandleW(nullptr));
        const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
        if (nt->FileHeader.TimeDateStamp != guard::timestamp || nt->OptionalHeader.SizeOfImage != guard::image_size) return;
        for (const auto& region : guard::regions) {
            if (std::memcmp(reinterpret_cast<void*>(base + region.rva), region.bytes, region.size)) {
                Output::send(STR("[BetterExpedition] Unsupported/modified native code; disabled.\n")); return;
            }
        }
        clock_hook = std::make_unique<PLH::x64Detour>(base + 0x32675c0, reinterpret_cast<std::uint64_t>(&clock_now), &clock_original);
        cancel_hook = std::make_unique<PLH::x64Detour>(base + 0x301cea0, reinterpret_cast<std::uint64_t>(&finish), &cancel_original);
        submit_hook = std::make_unique<PLH::x64Detour>(base + 0x3063eb0, reinterpret_cast<std::uint64_t>(&submit), &submit_original);
        // Install suppression last; a partial failure must never leave a
        // mission unable to finish through either native or mod behavior.
        if (!submit_hook->hook() || !cancel_hook->hook() || !clock_hook->hook()) {
            clock_hook->unHook(); cancel_hook->unHook(); submit_hook->unHook();
            Output::send(STR("[BetterExpedition] Hook installation failed; native behavior restored.\n")); return;
        }
        active = true;
        Output::send(STR("[BetterExpedition] ACTIVE: manual finish, native time/strength rewards; game revision 102999.\n"));
    }
};
}
#define EXPORT __declspec(dllexport)
extern "C" { EXPORT RC::CppUserModBase* start_mod() { return new Mod(); } EXPORT void uninstall_mod(RC::CppUserModBase* mod) { delete mod; } }

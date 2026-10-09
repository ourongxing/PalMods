#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/FFrame.hpp>
extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#define NOMINMAX
#include <Windows.h>
#include "binary_guard.hpp"

namespace {
std::atomic_bool installed{false};
std::atomic_bool scope_ready{false};
std::uint8_t* target{};
thread_local unsigned storage_depth{};
thread_local unsigned candidate_depth{};
std::array<RC::Unreal::Hook::GlobalCallbackId, 4> scope_hooks{};
RC::Unreal::FName inventory_name;
RC::Unreal::FName candidate_function_name;
bool inventory_context(RC::Unreal::UObject* context) {
    return scope_ready.load() && context && context->GetClassPrivate()
        && context->GetClassPrivate()->GetFName() == inventory_name
        && context->GetClassPrivate()->GetFullName() == STR("WidgetBlueprintGeneratedClass /Game/Pal/Blueprint/UI/UserInterface/MainMenu/InventoryEquipment/WBP_InventoryEquipment.WBP_InventoryEquipment_C");
}
int storage_scope(lua_State* state) {
    lua_pushboolean(state, installed.load() && scope_ready.load() && storage_depth > 0);
    return 1;
}
bool candidate_function(RC::Unreal::FFrame& frame) {
    return frame.Node()
        && frame.Node()->GetFName() == candidate_function_name;
}
int candidate_scope(lua_State* state) {
    lua_pushboolean(state, installed.load() && scope_ready.load() && candidate_depth > 0);
    return 1;
}
constexpr std::array<std::uint8_t, 6> replacement{0x90,0x90,0x90,0x90,0x90,0x90};

bool write_code(const std::uint8_t* bytes) {
    DWORD previous{};
    if (!VirtualProtect(target, replacement.size(), PAGE_EXECUTE_READWRITE, &previous)) return false;
    std::memcpy(target, bytes, replacement.size());
    FlushInstructionCache(GetCurrentProcess(), target, replacement.size());
    DWORD ignored{};
    VirtualProtect(target, replacement.size(), previous, &ignored);
    return true;
}

int native_ready(lua_State* state) {
    lua_pushboolean(state, installed.load());
    return 1;
}

class BetterBulkStorage final : public RC::CppUserModBase {
public:
    BetterBulkStorage() {
        ModName = STR("BetterBulkStorage");
        ModVersion = STR("0.1.0-experimental");
        ModAuthors = STR("ourongxing");
        ModDescription = STR("Extend native Easy Bulk Storage to empty slots");
    }
    auto on_unreal_init() -> void override {
        auto* base = reinterpret_cast<std::uint8_t*>(GetModuleHandleW(nullptr));
        if (!base) return;
        const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if (dos->e_magic != IMAGE_DOS_SIGNATURE) return;
        const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
        if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.TimeDateStamp != guard::timestamp
            || nt->OptionalHeader.SizeOfImage != guard::image_size
            || std::memcmp(base + guard::function_rva, guard::function.data(), guard::function.size()) != 0
            || std::memcmp(base + guard::call_rva, guard::call.data(), guard::call.size()) != 0
            || std::memcmp(base + guard::permission_rva, guard::permission.data(), guard::permission.size()) != 0
            || std::memcmp(base + guard::filter_rva, guard::filter.data(), guard::filter.size()) != 0) {
            RC::Output::send(STR("[BetterBulkStorage] unsupported or modified binary; enhancement disabled\n"));
            return;
        }
        target = base + guard::patch_rva;
        // Only remove the 'this chest has no matching item' gate. Native slot
        // validation, capacity, transfer transaction and server authority remain.
        if (!write_code(replacement.data())) {
            RC::Output::send(STR("[BetterBulkStorage] patch installation failed\n"));
            target = nullptr;
            return;
        }
        installed.store(true);
        // Track synchronous Blueprint execution, including nested delegate calls.
        // Never pretend that the player is inside a base for unrelated gameplay.
        auto enter = [](auto&, RC::Unreal::UObject* context, RC::Unreal::FFrame& frame, void*) {
            if (!inventory_context(context)) return;
            ++storage_depth;
            if (candidate_function(frame)) ++candidate_depth;
        };
        auto leave = [](auto&, RC::Unreal::UObject* context, RC::Unreal::FFrame& frame, void*) {
            if (!inventory_context(context)) return;
            if (candidate_function(frame) && candidate_depth) --candidate_depth;
            if (storage_depth) --storage_depth;
        };
        using namespace RC::Unreal::Hook;
        inventory_name = RC::Unreal::FName(STR("WBP_InventoryEquipment_C"));
        candidate_function_name = RC::Unreal::FName(STR("Update Inventory Greyout"));
        FCallbackOptions options{false, false, STR("BetterBulkStorage"), STR("StorageScope")};
        scope_hooks = {RegisterProcessInternalPreCallback(enter, options),
            RegisterProcessInternalPostCallback(leave, options),
            RegisterProcessLocalScriptFunctionPreCallback(enter, options),
            RegisterProcessLocalScriptFunctionPostCallback(leave, options)};
        bool complete = true;
        for (auto id : scope_hooks) complete = complete && id != ERROR_ID;
        scope_ready.store(complete);
        if (!complete) {
            for (auto& id : scope_hooks) {
                if (id) UnregisterCallback(id);
                id = ERROR_ID;
            }
        }
        RC::Output::send(complete
            ? STR("[BetterBulkStorage] scoped outside-base storage and egg candidates ready\n")
            : STR("[BetterBulkStorage] script scope unavailable; outside-base storage disabled\n"));
        RC::Output::send(STR("[BetterBulkStorage] native empty-slot enhancement ready (0.1.0 experimental)\n"));
    }
    ~BetterBulkStorage() override {
        installed.store(false);
        scope_ready.store(false);
        for (auto id : scope_hooks) if (id) RC::Unreal::Hook::UnregisterCallback(id);
        if (target && std::memcmp(target, replacement.data(), replacement.size()) == 0)
            write_code(guard::original.data());
    }
};
}

extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new BetterBulkStorage(); }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
// Loaded by the Lua companion from this same DLL. No stale readiness files.
extern "C" __declspec(dllexport) int luaopen_BetterBulkStorage(lua_State* state) {
    lua_pushcfunction(state, native_ready);
    lua_pushcfunction(state, storage_scope);
    lua_pushcfunction(state, candidate_scope);
    return 3;
}

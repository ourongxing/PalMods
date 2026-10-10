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
#include "storage_transfer.hpp"

namespace {
std::atomic_bool installed{false};
std::atomic_bool scope_ready{false};
std::uint8_t* target{};
std::uint8_t* game_base{};
RC::Unreal::UObject* preview_inventory{};
thread_local unsigned storage_depth{};
std::array<RC::Unreal::Hook::GlobalCallbackId, 4> scope_hooks{};
RC::Unreal::FName inventory_name;
RC::Unreal::FName candidate_function_name;
RC::Unreal::FName update_function_name;
RC::Unreal::FName toggle_function_name;
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
std::array<std::uint8_t, 14> replacement{};
void ordered_transfer(void* context, const void* source, const void* item) {
    using Maximum = std::int32_t (*)(void*);
    using Transfer = void (*)(void*, std::int32_t, const void*, const void*, void*);
    storage::transfer(context, source, item,
        storage::read<std::uint64_t>(game_base, guard::none_rva),
        reinterpret_cast<Maximum>(game_base + guard::maximum_rva),
        reinterpret_cast<Transfer>(game_base + guard::transfer_rva));
}

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
    lua_pushboolean(state, installed.load() && scope_ready.load());
    return 1;
}

int preview_state(lua_State* state) {
    preview_inventory = reinterpret_cast<RC::Unreal::UObject*>(luaL_checkinteger(state, 1));
    return 0;
}
int milliseconds(lua_State* state) {
    LARGE_INTEGER counter{}, frequency{};
    QueryPerformanceCounter(&counter);
    QueryPerformanceFrequency(&frequency);
    lua_pushnumber(state, static_cast<double>(counter.QuadPart) * 1000.0 / frequency.QuadPart);
    return 1;
}
int container_allows(lua_State* state) {
    auto* container = reinterpret_cast<std::uint8_t*>(luaL_checkinteger(state, 1));
    auto* data = reinterpret_cast<std::uint8_t*>(luaL_checkinteger(state, 2));
    bool accepted = false;
    if (installed.load() && preview_inventory && game_base && container && data) {
        using Permission = bool (*)(void*, void*);
        using Filter = bool (*)(void*, void*, void*);
        accepted = reinterpret_cast<Permission>(game_base + guard::permission_rva)(data, container + 0x80)
            && reinterpret_cast<Filter>(game_base + guard::filter_rva)(container, data, container + 0xc8);
    }
    lua_pushboolean(state, accepted);
    return 1;
}
int slot_allows(lua_State* state) {
    auto* slot = reinterpret_cast<std::uint8_t*>(luaL_checkinteger(state, 1));
    auto* data = reinterpret_cast<std::uint8_t*>(luaL_checkinteger(state, 2));
    using Permission = bool (*)(void*, void*);
    lua_pushboolean(state, installed.load() && preview_inventory && game_base && slot && data
        && reinterpret_cast<Permission>(game_base + guard::permission_rva)(data, slot + 0x160));
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
            || std::memcmp(base + guard::filter_rva, guard::filter.data(), guard::filter.size()) != 0
            || std::memcmp(base + guard::maximum_rva, guard::maximum.data(), guard::maximum.size()) != 0
            || std::memcmp(base + guard::transfer_rva, guard::transfer.data(), guard::transfer.size()) != 0) {
            RC::Output::send(STR("[BetterBulkStorage] unsupported or modified binary; enhancement disabled\n"));
            return;
        }
        target = base + guard::function_rva;
        game_base = base;
        // Replace only the validated bulk helper. A RIP-indirect absolute jump
        // preserves every argument register; no trampoline or displaced code.
        replacement = {0xff, 0x25, 0, 0, 0, 0};
        const auto destination = reinterpret_cast<std::uintptr_t>(&ordered_transfer);
        std::memcpy(replacement.data() + 6, &destination, sizeof(destination));
        if (!write_code(replacement.data())) {
            RC::Output::send(STR("[BetterBulkStorage] patch installation failed\n"));
            target = nullptr;
            return;
        }
        installed.store(true);
        // Track synchronous Blueprint execution, including nested delegate calls.
        // Never pretend that the player is inside a base for unrelated gameplay.
        auto enter = [](auto& callback, RC::Unreal::UObject* context, RC::Unreal::FFrame& frame, void*) {
            if (!inventory_context(context)) return;
            ++storage_depth;
            // Lua Blueprint hooks are post-only. Arm suppression here before
            // Toggle executes its synchronous per-slot greyout loop.
            if (frame.Node() && frame.Node()->GetFName() == toggle_function_name)
                preview_inventory = context;
            if (context == preview_inventory && frame.Node()) {
                const auto name = frame.Node()->GetFName();
                // Replace only the quick-storage preview. Editing=false remains
                // vanilla, including ordinary inventory sorting/reset colours.
                if (candidate_function(frame)
                    || (name == update_function_name && frame.Locals() && frame.Locals()[0]))
                    callback.PreventOriginalFunctionCall();
            }
        };
        auto leave = [](auto&, RC::Unreal::UObject* context, RC::Unreal::FFrame&, void*) {
            if (!inventory_context(context)) return;
            if (storage_depth) --storage_depth;
        };
        using namespace RC::Unreal::Hook;
        inventory_name = RC::Unreal::FName(STR("WBP_InventoryEquipment_C"));
        candidate_function_name = RC::Unreal::FName(STR("Update Inventory Greyout"));
        update_function_name = RC::Unreal::FName(STR("UpdateQuickStackableInventorySlot"));
        toggle_function_name = RC::Unreal::FName(STR("ToggleQuickStackPanel"));
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
        preview_inventory = nullptr;
        installed.store(false);
        scope_ready.store(false);
        for (auto id : scope_hooks) if (id) RC::Unreal::Hook::UnregisterCallback(id);
        if (target && std::memcmp(target, replacement.data(), replacement.size()) == 0)
            write_code(guard::function.data());
    }
};
}

extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new BetterBulkStorage(); }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
// Loaded by the Lua companion from this same DLL. No stale readiness files.
extern "C" __declspec(dllexport) int luaopen_BetterBulkStorage(lua_State* state) {
    const luaL_Reg bridge[] = {
        {"ready", native_ready},
        {"inStorageScope", storage_scope},
        {"setPreview", preview_state},
        {"containerAllows", container_allows},
        {"slotAllows", slot_allows},
        {"milliseconds", milliseconds},
        {nullptr, nullptr},
    };
    luaL_newlib(state, bridge);
    return 1;
}

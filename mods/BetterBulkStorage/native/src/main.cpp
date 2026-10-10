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
#include "transport_priority.hpp"

namespace {
std::atomic_bool installed{false};
std::atomic_bool scope_ready{false};
std::uint8_t* target{};
std::uint8_t* game_base{};
std::uint8_t* transport_target{};
void* transport_thunk{};
std::array<std::uint8_t, 14> transport_original{}, transport_replacement{};
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
std::array<std::uint8_t, 14> absolute_jump(const void* destination) {
    std::array<std::uint8_t, 14> bytes{0xff, 0x25, 0, 0, 0, 0};
    std::memcpy(bytes.data() + 6, &destination, sizeof(destination));
    return bytes;
}
void ordered_transfer(void* context, const void* source, const void* item) {
    using Maximum = std::int32_t (*)(void*);
    using Transfer = void (*)(void*, std::int32_t, const void*, const void*, void*);
    storage::transfer(context, source, item,
        storage::read<std::uint64_t>(game_base, guard::none_rva),
        reinterpret_cast<Maximum>(game_base + guard::maximum_rva),
        reinterpret_cast<Transfer>(game_base + guard::transfer_rva));
}

bool write_code(std::uint8_t* address, const std::uint8_t* bytes) {
    DWORD previous{};
    if (!VirtualProtect(address, replacement.size(), PAGE_EXECUTE_READWRITE, &previous)) return false;
    std::memcpy(address, bytes, replacement.size());
    FlushInstructionCache(GetCurrentProcess(), address, replacement.size());
    DWORD ignored{};
    VirtualProtect(address, replacement.size(), previous, &ignored);
    return true;
}

bool item_permission(void* data, void* permission) {
    using Permission = bool (*)(void*, void*);
    return reinterpret_cast<Permission>(game_base + guard::permission_rva)(data, permission);
}
bool accepts_container(void* container, void* data) {
    using Filter = bool (*)(void*, void*, void*);
    auto* bytes = static_cast<std::byte*>(container);
    return item_permission(data, bytes + 0x80)
        && reinterpret_cast<Filter>(game_base + guard::filter_rva)(container, data, bytes + 0xc8);
}
bool accepts_slot(void* slot, void* data) {
    return item_permission(data, static_cast<std::byte*>(slot) + 0x160);
}

float ranked_transport(const void* candidate) {
    const auto* status = storage::read<void*>(candidate, 8);
    const auto priority = storage::read<std::uint8_t>(status, 0);
    return storage::transport_priority(priority, [&] {
        auto* model = storage::read<void*>(candidate, 0);
        if (!storage::valid(model)) return false;
        using Getter = void* (*)(void*);
        using Data = void* (*)(void*, std::uint64_t);
        using Maximum = std::int32_t (*)(void*);
        auto* module = reinterpret_cast<Getter>(game_base + guard::module_rva)(model);
        if (!storage::valid(module)) return false;
        auto* container = reinterpret_cast<Getter>(game_base + guard::container_rva)(module);
        if (!storage::valid(container)) return false;
        const auto name = storage::read<std::uint64_t>(candidate, 0x10);
        auto* data = reinterpret_cast<Data>(game_base + guard::static_data_rva)(model, name);
        return storage::valid(data) && accepts_container(container, data)
            && storage::has_transport_stack(container, name,
                storage::read<std::uint64_t>(game_base, guard::none_rva),
                reinterpret_cast<Maximum>(game_base + guard::maximum_rva),
                [&](void* slot) { return accepts_slot(slot, data); });
    });
}

bool install_transport() {
    // Replace only the 14-byte priority load after vanilla builds its eligible
    // candidate list. RBX points at a 32-byte candidate; all live nonvolatile
    // registers (including XMM6/8/9) are preserved by the Win64 callee ABI.
    std::array<std::uint8_t, 41> thunk{
        0x48,0x89,0xd9,                   // mov rcx,rbx
        0x48,0x83,0xec,0x20,             // aligned Win64 shadow space
        0x48,0xb8,0,0,0,0,0,0,0,0,     // mov rax,ranked_transport
        0xff,0xd0,                       // call rax
        0x48,0x83,0xc4,0x20,
        0xf3,0x0f,0x10,0xf8,             // movss xmm7,xmm0
        0xff,0x25,0,0,0,0,              // jmp [rip]
        0,0,0,0,0,0,0,0};
    const auto callback = reinterpret_cast<std::uintptr_t>(&ranked_transport);
    const auto continuation = reinterpret_cast<std::uintptr_t>(game_base + guard::transport_patch_rva + 14);
    std::memcpy(thunk.data() + 9, &callback, 8);
    std::memcpy(thunk.data() + 33, &continuation, 8);
    transport_thunk = VirtualAlloc(nullptr, thunk.size(), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!transport_thunk) return false;
    std::memcpy(transport_thunk, thunk.data(), thunk.size());
    DWORD previous{};
    if (!VirtualProtect(transport_thunk, thunk.size(), PAGE_EXECUTE_READ, &previous)) {
        VirtualFree(transport_thunk, 0, MEM_RELEASE); transport_thunk = nullptr; return false;
    }
    FlushInstructionCache(GetCurrentProcess(), transport_thunk, thunk.size());
    transport_target = game_base + guard::transport_patch_rva;
    std::memcpy(transport_original.data(), transport_target, 14);
    transport_replacement = absolute_jump(transport_thunk);
    const bool success = write_code(transport_target, transport_replacement.data());
    if (!success) {
        transport_target = nullptr;
        VirtualFree(transport_thunk, 0, MEM_RELEASE); transport_thunk = nullptr;
    }
    return success;
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
    lua_pushboolean(state, installed.load() && preview_inventory && game_base && container && data
        && accepts_container(container, data));
    return 1;
}
int slot_allows(lua_State* state) {
    auto* slot = reinterpret_cast<std::uint8_t*>(luaL_checkinteger(state, 1));
    auto* data = reinterpret_cast<std::uint8_t*>(luaL_checkinteger(state, 2));
    lua_pushboolean(state, installed.load() && preview_inventory && game_base && slot && data
        && accepts_slot(slot, data));
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
        replacement = absolute_jump(reinterpret_cast<const void*>(&ordered_transfer));
        if (!write_code(target, replacement.data())) {
            RC::Output::send(STR("[BetterBulkStorage] patch installation failed\n"));
            target = nullptr;
            return;
        }
        installed.store(true);
        const bool transport_supported =
            !std::memcmp(base + guard::transport_rva, guard::transport.data(), guard::transport.size())
            && !std::memcmp(base + guard::module_rva, guard::module.data(), guard::module.size())
            && !std::memcmp(base + guard::container_rva, guard::container.data(), guard::container.size())
            && !std::memcmp(base + guard::static_data_rva, guard::static_data.data(), guard::static_data.size());
        RC::Output::send(transport_supported && install_transport()
            ? STR("[BetterBulkStorage] Pal transport stack preference ready\n")
            : STR("[BetterBulkStorage] Pal transport patch unavailable; vanilla transport retained\n"));
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
            write_code(target, guard::function.data());
        if (transport_target && !std::memcmp(transport_target, transport_replacement.data(), 14)) {
            if (write_code(transport_target, transport_original.data()) && transport_thunk)
                VirtualFree(transport_thunk, 0, MEM_RELEASE);
        }
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

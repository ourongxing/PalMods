#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/FWeakObjectPtr.hpp>
#include <Unreal/FFrame.hpp>
extern "C" {
#include <lua.h>
#include <lauxlib.h>
}
#define NOMINMAX
#include <Windows.h>
#include "binary_guard.hpp"
#include "transport_priority.hpp"
#include "stack_limits.hpp"

namespace {
constexpr std::size_t jump_size = 14;
using Jump = std::array<std::uint8_t, jump_size>;
std::atomic_bool installed{false};
std::atomic_bool scope_ready{false};
std::uint8_t* game_base{};
std::uint8_t* transport_target{};
void* transport_thunk{};
Jump transport_original{}, transport_replacement{};
std::uint8_t* stack_target{};
void* stack_trampoline{};
Jump stack_replacement{};
RC::Unreal::UClass* static_item_class{};
struct SavedStackLimit { RC::Unreal::FWeakObjectPtr object; std::int32_t maximum; };
std::mutex stack_mutex;
std::unordered_map<std::uint64_t, SavedStackLimit> saved_stack_limits;
thread_local unsigned storage_depth{};
std::array<RC::Unreal::Hook::GlobalCallbackId, 4> scope_hooks{};
RC::Unreal::FName inventory_name;
RC::Unreal::FWeakObjectPtr inventory_class;
bool inventory_context(RC::Unreal::UObject* context) {
    if (!scope_ready.load() || !context) return false;
    const auto* cls = context->GetClassPrivate();
    if (!cls || cls->GetFName() != inventory_name) return false;
    if (inventory_class.Get() == cls) return true;
    if (cls->GetFullName() != STR("WidgetBlueprintGeneratedClass /Game/Pal/Blueprint/UI/UserInterface/MainMenu/InventoryEquipment/WBP_InventoryEquipment.WBP_InventoryEquipment_C")) return false;
    inventory_class = RC::Unreal::FWeakObjectPtr(const_cast<RC::Unreal::UClass*>(cls));
    return true;
}
int storage_scope(lua_State* state) {
    lua_pushboolean(state, installed.load() && scope_ready.load() && storage_depth > 0);
    return 1;
}
Jump absolute_jump(const void* destination) {
    Jump bytes{0xff, 0x25, 0, 0, 0, 0};
    std::memcpy(bytes.data() + 6, &destination, sizeof(destination));
    return bytes;
}
bool write_code(std::uint8_t* address, const std::uint8_t* bytes) {
    DWORD previous{};
    if (!VirtualProtect(address, jump_size, PAGE_EXECUTE_READWRITE, &previous)) return false;
    std::memcpy(address, bytes, jump_size);
    FlushInstructionCache(GetCurrentProcess(), address, jump_size);
    DWORD ignored{};
    VirtualProtect(address, jump_size, previous, &ignored);
    return true;
}

template <std::size_t Size>
void* executable_code(const std::array<std::uint8_t, Size>& bytes) {
    auto* memory = VirtualAlloc(nullptr, Size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!memory) return nullptr;
    std::memcpy(memory, bytes.data(), Size);
    DWORD previous{};
    if (!VirtualProtect(memory, Size, PAGE_EXECUTE_READ, &previous)) {
        VirtualFree(memory, 0, MEM_RELEASE);
        return nullptr;
    }
    FlushInstructionCache(GetCurrentProcess(), memory, Size);
    return memory;
}

void* expanded_static_item(void* table, std::uint64_t name) {
    using Lookup = void* (*)(void*, std::uint64_t);
    auto* data = reinterpret_cast<Lookup>(stack_trampoline)(table, name);
    if (!storage::valid(data) || !static_item_class
        || !static_cast<RC::Unreal::UObject*>(data)->IsA(static_item_class)) return data;
    std::lock_guard lock(stack_mutex);
    const auto before = storage::read<std::int32_t>(data, 0x78);
    const auto after = storage::expanded_limit(before, storage::read<void*>(data, 0x80) != nullptr);
    if (before == after) return data;
    // Weak identity prevents teardown from writing to a destroyed/reused row.
    const RC::Unreal::FWeakObjectPtr weak(static_cast<RC::Unreal::UObject*>(data));
    const auto key = static_cast<std::uint64_t>(static_cast<std::uint32_t>(weak.ObjectIndex))
        | (static_cast<std::uint64_t>(static_cast<std::uint32_t>(weak.ObjectSerialNumber)) << 32);
    try {
        saved_stack_limits.try_emplace(key, SavedStackLimit{weak, before});
    } catch (const std::bad_alloc&) { return data; }
    storage::set_item_stack_limit(data, after);
    return data;
}

bool install_stack_limits() {
    if (std::memcmp(game_base + guard::stack_lookup_rva, guard::stack_lookup.data(), guard::stack_lookup.size())) return false;
    static_item_class = RC::Unreal::UObjectGlobals::StaticFindObject<RC::Unreal::UClass*>(
        nullptr, nullptr, STR("/Script/Pal.PalStaticItemDataBase"));
    if (!static_item_class) return false;
    // Guard generation verifies the first 14 bytes are complete instructions
    // with no relative branches or RIP operands. The original row lookup runs
    // first; all vanilla validation then reads the same updated data object.
    std::array<std::uint8_t, jump_size * 2> trampoline{};
    std::memcpy(trampoline.data(), guard::stack_lookup.data(), jump_size);
    const auto continuation = absolute_jump(game_base + guard::stack_lookup_rva + jump_size);
    std::memcpy(trampoline.data() + jump_size, continuation.data(), jump_size);
    stack_trampoline = executable_code(trampoline);
    if (!stack_trampoline) return false;
    stack_target = game_base + guard::stack_lookup_rva;
    stack_replacement = absolute_jump(reinterpret_cast<void*>(&expanded_static_item));
    if (!write_code(stack_target, stack_replacement.data())) {
        stack_target = nullptr;
        VirtualFree(stack_trampoline, 0, MEM_RELEASE); stack_trampoline = nullptr; return false;
    }
    return true;
}

void remove_stack_limits() {
    if (stack_target && !std::memcmp(stack_target, stack_replacement.data(), jump_size)) {
        if (!write_code(stack_target, guard::stack_lookup.data())) return;
        if (stack_trampoline) VirtualFree(stack_trampoline, 0, MEM_RELEASE);
        stack_trampoline = nullptr;
    }
    std::lock_guard lock(stack_mutex);
    for (const auto& [key, saved] : saved_stack_limits) {
        auto* data = saved.object.Get();
        if (storage::valid(data) && storage::read<std::int32_t>(data, 0x78) == storage::expanded_stack_limit)
            storage::set_item_stack_limit(data, saved.maximum);
    }
    saved_stack_limits.clear();
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
    const auto continuation = reinterpret_cast<std::uintptr_t>(game_base + guard::transport_patch_rva + jump_size);
    std::memcpy(thunk.data() + 9, &callback, 8);
    std::memcpy(thunk.data() + 33, &continuation, 8);
    transport_thunk = executable_code(thunk);
    if (!transport_thunk) return false;
    transport_target = game_base + guard::transport_patch_rva;
    std::memcpy(transport_original.data(), transport_target, jump_size);
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

class BetterStorage final : public RC::CppUserModBase {
public:
    BetterStorage() {
        ModName = STR("BetterStorage");
        ModVersion = STR("0.1.0");
        ModAuthors = STR("ourongxing");
        ModDescription = STR("Vanilla quick storage with outside-base destination, stack limits and transport priority");
    }
    auto on_unreal_init() -> void override {
        auto* base = reinterpret_cast<std::uint8_t*>(GetModuleHandleW(nullptr));
        if (!base) return;
        const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if (dos->e_magic != IMAGE_DOS_SIGNATURE) return;
        const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
        if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.TimeDateStamp != guard::timestamp
            || nt->OptionalHeader.SizeOfImage != guard::image_size
            || std::memcmp(base + guard::permission_rva, guard::permission.data(), guard::permission.size()) != 0
            || std::memcmp(base + guard::filter_rva, guard::filter.data(), guard::filter.size()) != 0
            || std::memcmp(base + guard::maximum_rva, guard::maximum.data(), guard::maximum.size()) != 0) {
            RC::Output::send(STR("[BetterStorage] unsupported or modified binary; enhancement disabled\n"));
            return;
        }
        game_base = base;
        installed.store(true);
        RC::Output::send(install_stack_limits()
            ? STR("[BetterStorage] shared stack limit ready: minimum 99999, higher original limits preserved (inventory, chests and production storage)\n")
            : STR("[BetterStorage] stack limit patch unavailable; original limits retained\n"));
        const bool transport_supported =
            !std::memcmp(base + guard::transport_rva, guard::transport.data(), guard::transport.size())
            && !std::memcmp(base + guard::module_rva, guard::module.data(), guard::module.size())
            && !std::memcmp(base + guard::container_rva, guard::container.data(), guard::container.size())
            && !std::memcmp(base + guard::static_data_rva, guard::static_data.data(), guard::static_data.size());
        RC::Output::send(transport_supported && install_transport()
            ? STR("[BetterStorage] Pal transport stack preference ready\n")
            : STR("[BetterStorage] Pal transport patch unavailable; vanilla transport retained\n"));
        // Track synchronous Blueprint execution, including nested delegate calls.
        // Never pretend that the player is inside a base for unrelated gameplay.
        auto enter = [](auto&, RC::Unreal::UObject* context, RC::Unreal::FFrame&, void*) {
            if (!inventory_context(context)) return;
            ++storage_depth;
        };
        auto leave = [](auto&, RC::Unreal::UObject* context, RC::Unreal::FFrame&, void*) {
            if (!inventory_context(context)) return;
            if (storage_depth) --storage_depth;
        };
        using namespace RC::Unreal::Hook;
        inventory_name = RC::Unreal::FName(STR("WBP_InventoryEquipment_C"));
        FCallbackOptions options{false, false, STR("BetterStorage"), STR("StorageScope")};
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
            ? STR("[BetterStorage] scoped outside-base storage ready\n")
            : STR("[BetterStorage] script scope unavailable; outside-base storage disabled\n"));
        RC::Output::send(STR("[BetterStorage] simple edition ready: vanilla candidates/transfers, no empty-slot preview\n"));
    }
    ~BetterStorage() override {
        installed.store(false);
        scope_ready.store(false);
        for (auto id : scope_hooks) if (id) RC::Unreal::Hook::UnregisterCallback(id);
        remove_stack_limits();
        if (transport_target && !std::memcmp(transport_target, transport_replacement.data(), jump_size)) {
            if (write_code(transport_target, transport_original.data()) && transport_thunk)
                VirtualFree(transport_thunk, 0, MEM_RELEASE);
        }
    }
};
}

extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new BetterStorage(); }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
// Loaded by the Lua companion from this same DLL. No stale readiness files.
extern "C" __declspec(dllexport) int luaopen_BetterStorage(lua_State* state) {
    const luaL_Reg bridge[] = {
        {"ready", native_ready},
        {"inStorageScope", storage_scope},
        {nullptr, nullptr},
    };
    luaL_newlib(state, bridge);
    return 1;
}

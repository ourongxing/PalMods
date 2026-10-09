#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
extern "C" {
#include <lua.h>
}
#define NOMINMAX
#include <Windows.h>
#include "binary_guard.hpp"

namespace {
std::atomic_bool installed{false};
std::uint8_t* target{};
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

class EnhancedBulkStorage final : public RC::CppUserModBase {
public:
    EnhancedBulkStorage() {
        ModName = STR("EnhancedBulkStorage");
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
            || std::memcmp(base + guard::call_rva, guard::call.data(), guard::call.size()) != 0) {
            RC::Output::send(STR("[EnhancedBulkStorage] unsupported or modified binary; enhancement disabled\n"));
            return;
        }
        target = base + guard::patch_rva;
        // Only remove the 'this chest has no matching item' gate. Native slot
        // validation, capacity, transfer transaction and server authority remain.
        if (!write_code(replacement.data())) {
            RC::Output::send(STR("[EnhancedBulkStorage] patch installation failed\n"));
            target = nullptr;
            return;
        }
        installed.store(true);
        RC::Output::send(STR("[EnhancedBulkStorage] native empty-slot enhancement ready (0.1.0 experimental)\n"));
    }
    ~EnhancedBulkStorage() override {
        installed.store(false);
        if (target && std::memcmp(target, replacement.data(), replacement.size()) == 0)
            write_code(guard::original.data());
    }
};
}

extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new EnhancedBulkStorage(); }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
// Loaded by the Lua companion from this same DLL. No stale readiness files.
extern "C" __declspec(dllexport) int luaopen_EnhancedBulkStorage(lua_State* state) {
    lua_pushcfunction(state, native_ready);
    return 1;
}

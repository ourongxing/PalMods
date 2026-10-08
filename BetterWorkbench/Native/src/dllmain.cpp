#define NOMINMAX
#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <vector>
#include <cmath>
#include <deque>
#include <map>
#include <mutex>
#include <set>
#include <filesystem>
#include <fstream>
#include <algorithm>
#include <objbase.h>
#include <intrin.h>
#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/NameTypes.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <Unreal/Core/HAL/UnrealMemory.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Windows.h>
#include <polyhook2/Detour/x64Detour.hpp>
#include "recipe_view.hpp"
#include "job_schedule.hpp"
#include "job_journal.hpp"
#include "recipe_scope.hpp"
#include "input_layout.hpp"
#include "consumption_ops.hpp"
#pragma comment(lib, "ole32.lib")

namespace {
using namespace RC;
using namespace RC::Unreal;
// The game passes an eight-byte name in R8, not a pointer to an SDK wrapper.
struct BorrowedArray { const std::byte* data; int32_t count; int32_t capacity; };
static_assert(sizeof(BorrowedArray) == 16);
using DemandFunction = void (*)(void*, void*, uint64_t, BorrowedArray*);
uint64_t trampoline{};
std::unique_ptr<PLH::x64Detour> detour;
uint64_t counts_trampoline{};
std::unique_ptr<PLH::x64Detour> counts_detour;
std::atomic<unsigned> scoped_samples{};
std::atomic<unsigned> ui_samples{}, server_samples{};
std::atomic<bool> copy_disabled{};
thread_local bool copying{};
constexpr uintptr_t demand_rva = 0x2fadaa0;
constexpr uintptr_t call_rva = 0x300611e;
constexpr uintptr_t counts_rva = 0x2fa0020;
constexpr uintptr_t counts_call_rva = 0x30061ec;
// Filled from a verified local PE by the build tool; never guessed from pseudocode.
#include "binary_guard.hpp"

struct Material { std::wstring name; int32_t quantity; };
std::optional<better_workbench::MaterialLayout> recipe_layout() {
    auto* function = UObjectGlobals::StaticFindObject<UFunction*>(nullptr, nullptr,
        STR("/Script/Pal.PalMapObjectConvertItemModel:GetCurrentRecipe"));
    auto* result = function ? function->GetReturnProperty() : nullptr;
    if (!result || !result->IsA<FStructProperty>()) return {};
    auto* type = static_cast<FStructProperty*>(result)->GetStruct().Get();
    if (!type || type->GetSize() != 0x88 || result->GetElementSize() != 0x88) return {};
    better_workbench::MaterialLayout layout{};
    layout.row_size = type->GetSize();
    for (std::size_t index = 0; index < 5; ++index) {
        const auto base = L"Material" + std::to_wstring(index + 1);
        auto* name = type->FindProperty(FName((base + L"_Id").c_str()));
        auto* count = type->FindProperty(FName((base + L"_Count").c_str()));
        if (!name || !count || !name->IsA<FNameProperty>() || !count->IsA<FIntProperty>()
            || name->GetElementSize() != 8 || count->GetElementSize() != 4) return {};
        layout.names[index] = name->GetOffset_ForInternal();
        layout.counts[index] = count->GetOffset_ForInternal();
    }
    try { better_workbench::verify_layout(layout); } catch (const std::invalid_argument&) { return {}; }
    return layout;
}
using CountsFunction = void (*)(void*, BorrowedArray*, BorrowedArray*, BorrowedArray*);
void active_worker(void*, int32_t, uint64_t, int32_t, bool, bool);
#include "request_snapshot.hpp"
#include "active_jobs.hpp"

void scoped_counts(void* world, BorrowedArray* containers, BorrowedArray* names, BorrowedArray* result) {
    const bool worker = reinterpret_cast<uintptr_t>(_ReturnAddress()) ==
        reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)) + counts_call_rva + 5;
    if (worker && pending_job && pending_model == world) {
        auto* total = reinterpret_cast<BorrowedArray*>(
            reinterpret_cast<std::byte*>(_AddressOfReturnAddress()) + 0x60);
        set_material_array(total, pending_job->schedule.total);
    }
    std::vector<std::wstring> requested;
    std::vector<Material> batch_demand;
    bool selected = worker && !copy_disabled.load() && (scoped_samples.load() < 12
        || (snapshot_reads_ready && !snapshot_disabled.load() && snapshot_samples.load() < 24));
    if (selected) {
        try {
            if (!names || names->count < 0 || names->count > 64 || names->capacity < names->count
                || (names->count && !names->data)) selected = false;
            else {
                // Verified worker call-site layout: its total demand is at
                // caller RSP+0x58; this callback's return-address slot is RSP-8.
                // This view is borrowed only during this synchronous callback.
                const auto* total = reinterpret_cast<const BorrowedArray*>(
                    reinterpret_cast<const std::byte*>(_AddressOfReturnAddress()) + 0x60);
                if (total->count < 0 || total->count > 64 || total->capacity < total->count
                    || (total->count && !total->data)) selected = false;
                else for (int32_t index = 0; index < total->count; ++index) {
                    uint64_t id{}; int32_t quantity{};
                    std::memcpy(&id, total->data + index * 12, 8);
                    std::memcpy(&quantity, total->data + index * 12 + 8, 4);
                    if (quantity < 0) { selected = false; break; }
                    batch_demand.push_back({FName(static_cast<int64_t>(id)).ToString(), quantity});
                }
                // This native function consumes its by-value name array and frees
                // its allocation. Copy BEFORE the original; never inspect it after.
                for (int32_t index = 0; index < names->count; ++index) {
                    uint64_t id{}; std::memcpy(&id, names->data + index * 8, 8);
                    requested.push_back(FName(static_cast<int64_t>(id)).ToString());
                }
            }
        } catch (const std::exception&) { selected = false; copy_disabled.store(true); }
    }
    // The additional query has its own consumed name allocation and owned
    // output. The caller's arguments and vanilla output remain unchanged.
    if (selected && !pending_job) capture_request(world, containers, batch_demand);
    reinterpret_cast<CountsFunction>(counts_trampoline)(world, containers, names, result);
    if (!selected || !result || scoped_samples.fetch_add(1) >= 12) return;
    try {
        if (result->count < 0 || result->count > 64 || result->capacity < result->count
            || (result->count && !result->data)) return;
        std::vector<Material> owned;
        for (int32_t index = 0; index < result->count; ++index) {
            uint64_t id{}; int32_t quantity{};
            std::memcpy(&id, result->data + index * 12, 8);
            std::memcpy(&quantity, result->data + index * 12 + 8, 4);
            if (quantity < 0) return;
            owned.push_back({FName(static_cast<int64_t>(id)).ToString(), quantity});
        }
        Output::send(STR("[BetterWorkbenchNative] SERVER_SCOPE requested={} returned={}\n"), requested.size(), owned.size());
        for (const auto& name : requested) Output::send(STR("[BetterWorkbenchNative] SCOPE_REQUEST {}\n"), name);
        for (const auto& item : batch_demand) Output::send(STR("[BetterWorkbenchNative] BATCH_DEMAND {}={}\n"), item.name, item.quantity);
        for (const auto& item : owned) Output::send(STR("[BetterWorkbenchNative] SCOPE_STOCK {}={}\n"), item.name, item.quantity);
    } catch (const std::exception&) {
        copy_disabled.store(true);
        Output::send(STR("[BetterWorkbenchNative] scoped inventory copying disabled after C++ error\n"));
    }
}
void demand(void* world, void* owner, uint64_t recipe, BorrowedArray* result) {
    if (active_ready && is_job_name(recipe)) {
        try { auto job = find_job(recipe); set_material_array(result, job_unit(job, owner)); }
        catch (const std::exception&) { set_material_array(result, {{L"BetterWorkbench_MissingPlan", 1000000000}}); }
        return;
    }
    const bool server = reinterpret_cast<uintptr_t>(_ReturnAddress()) ==
        reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)) + call_rva + 5;
    reinterpret_cast<DemandFunction>(trampoline)(world, owner, recipe, result);
    if (active_ready && reinterpret_cast<uintptr_t>(_ReturnAddress()) == game_base()+0x29817b5+5) {
        // Only the reflected utility caller used by recipe cards; the native
        // server-worker and quantity-setting caller use separate exact paths.
        auto* widget_type=UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,STR("/Script/UMG.UserWidget"));
        auto* model_type=UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,STR("/Script/Pal.PalUIConvertItemModel"));
        auto* object=static_cast<UObject*>(world);
        if (object && ((widget_type && object->IsA(widget_type)) || (model_type && object->IsA(model_type))))
            ui_material_preview(world,owner,recipe,1,result);
    }
    auto& samples = server ? server_samples : ui_samples;
    if (copying || copy_disabled.load() || samples.load() >= 12 || !result) return;
    copying = true;
    struct Reset { ~Reset() { copying = false; } } reset;
    try {
        const auto name = FName(static_cast<int64_t>(recipe)).ToString();
        if (name != L"CarbonFiber" && name != L"CarbonFiber2" && name != L"Bio_Battery") return;
        if (result->count < 0 || result->count > 64 || result->capacity < result->count
            || (result->count && !result->data)) return;
        std::vector<Material> owned;
        owned.reserve(result->count);
        // Native element stride is 12; SDK FName alignment must not change this stride.
        for (int32_t index = 0; index < result->count; ++index) {
            uint64_t id{}; int32_t quantity{};
            std::memcpy(&id, result->data + index * 12, 8);
            std::memcpy(&quantity, result->data + index * 12 + 8, 4);
            if (quantity < 0) return;
            owned.push_back({FName(static_cast<int64_t>(id)).ToString(), quantity});
        }
        if (samples.fetch_add(1) >= 12) return;
        Output::send(STR("[BetterWorkbenchNative] NATIVE_DEMAND source={} recipe={} owner={} materials={}\n"), server ? L"server-worker" : L"other", name, owner != nullptr, owned.size());
        for (const auto& material : owned)
            Output::send(STR("[BetterWorkbenchNative] MATERIAL {}={}\n"), material.name, material.quantity);
    } catch (const std::exception&) {
        copy_disabled.store(true);
        Output::send(STR("[BetterWorkbenchNative] demand copying disabled after C++ error\n"));
    }
}

bool binary_matches(uintptr_t base) {
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (!base || dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 4096) return false;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64
        || nt->FileHeader.TimeDateStamp != expected_timestamp
        || nt->OptionalHeader.SizeOfImage != expected_image_size
        || nt->OptionalHeader.SizeOfImage <= call_rva + 5
        || nt->OptionalHeader.SizeOfImage <= demand_rva + expected_prefix.size()) return false;
    if (std::memcmp(reinterpret_cast<void*>(base + demand_rva), expected_prefix.data(), expected_prefix.size())) return false;
    const auto* call = reinterpret_cast<const uint8_t*>(base + call_rva);
    int32_t relative{}; std::memcpy(&relative, call + 1, 4);
    return *call == 0xe8 && base + call_rva + 5 + relative == base + demand_rva;
}

class Bridge final : public CppUserModBase {
    bool unreal_ready{}, attempted{};
    unsigned wait_polls{};
public:
    Bridge() {
        ModName = STR("better workbench / \u66f4\u597d\u7684\u5de5\u4f5c\u53f0"); ModVersion = STR("0.6.2-native-debits");
        ModDescription = STR("Native same-station crafting with immutable job recipes");
        ModAuthors = STR("BetterWorkbench");
    }
    void on_unreal_init() override { unreal_ready = true; }
    void on_lua_start(StringViewType name, LuaMadeSimple::Lua& lua,
                      LuaMadeSimple::Lua& main, LuaMadeSimple::Lua& async,
                      LuaMadeSimple::Lua* hook) override {
        if (name != STR("BetterWorkbench")) return;
        std::set<LuaMadeSimple::Lua*> instances{&lua, &main, &async};
        if (hook) instances.insert(hook);
        for (auto* instance : instances) {
            instance->register_function("BetterWorkbenchNativeTakeSnapshot", &take_snapshot);
            instance->register_function("BetterWorkbenchNativeIsActive", &active_status);
        }
        Output::send(STR("[BetterWorkbenchNative] owned snapshot API registered; no Lua state retained\n"));
    }
    void on_update() override {
        if (!unreal_ready || attempted) return;
        // The build verifies pinned headers; deployment verifies runtime imports.
#ifndef BETTERWORKBENCH_SDK_ABI_VERIFIED
        constexpr bool sdk_verified = false;
#else
        constexpr bool sdk_verified = true;
#endif
        if (!sdk_verified) {
            attempted = true;
            Output::send(STR("[BetterWorkbenchNative] disabled: native SDK ABI not verified\n"));
            return;
        }
        const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        if (!binary_matches(base)) { attempted = true; Output::send(STR("[BetterWorkbenchNative] disabled: game binary mismatch\n")); return; }
        auto* type = UObjectGlobals::StaticFindObject<UScriptStruct*>(nullptr, nullptr, STR("/Script/Pal.PalStaticItemIdAndNum"));
        if (!type) {
            if (++wait_polls >= 600) { attempted = true; Output::send(STR("[BetterWorkbenchNative] disabled: material struct unavailable\n")); }
            return;
        }
        attempted = true;
        auto* id = type ? type->FindProperty(FName(STR("StaticItemId"))) : nullptr;
        auto* num = type ? type->FindProperty(FName(STR("Num"))) : nullptr;
        if (FName::StaticSize() != 8 || type->GetSize() != 12 || !id || !num || id->GetOffset_ForInternal() != 0
            || num->GetOffset_ForInternal() != 8 || id->GetElementSize() != 8 || num->GetElementSize() != 4) {
            Output::send(STR("[BetterWorkbenchNative] disabled: material layout mismatch\n")); return;
        }
        detour = std::make_unique<PLH::x64Detour>(base + demand_rva, reinterpret_cast<uint64_t>(&demand), &trampoline);
        if (!detour->hook()) { detour.reset(); Output::send(STR("[BetterWorkbenchNative] hook failed\n")); return; }
        Output::send(STR("[BetterWorkbenchNative] read-only demand hook installed\n"));
        const auto* counts_call = reinterpret_cast<const uint8_t*>(base + counts_call_rva);
        int32_t counts_relative{}; std::memcpy(&counts_relative, counts_call + 1, 4);
        if (*counts_call != 0xe8 || base + counts_call_rva + 5 + counts_relative != base + counts_rva
            || std::memcmp(reinterpret_cast<void*>(base + 0x30060ff), expected_batch_window.data(), expected_batch_window.size())
            || std::memcmp(reinterpret_cast<void*>(base + 0x30061db), expected_counts_call_window.data(), expected_counts_call_window.size())
            || std::memcmp(reinterpret_cast<void*>(base + counts_rva), expected_counts_prefix.data(), expected_counts_prefix.size())) {
            Output::send(STR("[BetterWorkbenchNative] scoped inventory hook disabled: binary mismatch\n")); return;
        }
        counts_detour = std::make_unique<PLH::x64Detour>(base + counts_rva, reinterpret_cast<uint64_t>(&scoped_counts), &counts_trampoline);
        if (!counts_detour->hook()) { counts_detour.reset(); Output::send(STR("[BetterWorkbenchNative] scoped inventory hook failed\n")); return; }
        Output::send(STR("[BetterWorkbenchNative] read-only server scope hook installed\n"));
        if (!recipe_layout()) {
            Output::send(STR("[BetterWorkbenchNative] recipe copy layout unavailable; snapshot extension inactive\n")); return;
        }
        if (std::memcmp(reinterpret_cast<void*>(base + 0x3005d80), expected_worker_prefix.data(), expected_worker_prefix.size())
            || std::memcmp(reinterpret_cast<void*>(base + 0x30f0fb0), expected_data_prefix.data(), expected_data_prefix.size())
            || std::memcmp(reinterpret_cast<void*>(base + 0x30ec350), expected_row_prefix.data(), expected_row_prefix.size())) {
            Output::send(STR("[BetterWorkbenchNative] request snapshot disabled: binary mismatch\n")); return;
        }
        worker_detour = std::make_unique<PLH::x64Detour>(base + 0x3005d80, reinterpret_cast<uint64_t>(&worker), &worker_trampoline);
        if (!worker_detour->hook()) { worker_detour.reset(); Output::send(STR("[BetterWorkbenchNative] worker snapshot hook failed\n")); return; }
        snapshot_reads_ready = true;
        Output::send(STR("[BetterWorkbenchNative] owned request snapshot hook installed; writes inactive\n"));
        install_active_jobs(base);
    }
    ~Bridge() override {
        snapshot_reads_ready = false;
        active_ready = false;
        for (auto& hook : active_detours) hook->unHook();
        if (worker_detour) worker_detour->unHook();
        if (counts_detour) counts_detour->unHook(); if (detour) detour->unHook();
    }
};
}
extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new Bridge; }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }

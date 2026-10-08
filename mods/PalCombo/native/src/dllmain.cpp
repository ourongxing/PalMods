#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <filesystem>
#include <memory>
#include <optional>
#include <unordered_map>
#include <intrin.h>

#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <Unreal/NameTypes.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UObjectGlobals.hpp>

#define NOMINMAX
#include <Windows.h>
#include <polyhook2/Detour/x64Detour.hpp>

#include "rotation.hpp"

namespace pal_combo {
using namespace RC;
using namespace RC::Unreal;

static uint64_t selector_trampoline{};
static std::unique_ptr<PLH::x64Detour> selector_detour;
static float early_start_seconds{3.0f};
static int selection_log_count{};
static int bypass_log_count{};
static int reset_log_count{};
struct ComboState {
    UObject* slot{};
    UObject* target{};
    UObject* controller{};
    Phase phase{Phase::ready_for_first};
    bool logged_wait{};
    bool has_selection_log{};
    int last_original{-2};
    int last_selected{-2};
    Phase last_phase_before{Phase::ready_for_first};
    Phase last_phase_after{Phase::ready_for_first};
    Ready last_ready{};
};
static std::unordered_map<UObject*, ComboState> combo_states;

static constexpr uintptr_t selector_rva = 0x2CFABB0;
static constexpr uintptr_t direct_call_rva = 0x2CF7040;
static constexpr std::array<uint8_t, 15> selector_prefix{
    0x48, 0x8B, 0xC4, 0x4C, 0x89, 0x40, 0x18, 0x48,
    0x89, 0x50, 0x10, 0x48, 0x89, 0x48, 0x08,
};

static auto read_early_start_seconds() -> float {
    HMODULE module{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
            | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&read_early_start_seconds), &module)) return 3.0f;
    std::array<wchar_t, 1024> module_path{};
    const auto length = GetModuleFileNameW(module, module_path.data(),
                                          static_cast<DWORD>(module_path.size()));
    if (length == 0 || length >= module_path.size()) return 3.0f;
    const auto config_path = std::filesystem::path(module_path.data())
        .parent_path().parent_path() / L"config.ini";
    std::array<wchar_t, 64> value{};
    GetPrivateProfileStringW(L"Combo", L"EarlyStartSeconds", L"3.0",
                             value.data(), static_cast<DWORD>(value.size()), config_path.c_str());
    wchar_t* end{};
    const float parsed = std::wcstof(value.data(), &end);
    while (*end == L' ' || *end == L'\t') ++end;
    if (end == value.data() || *end != L'\0' || !std::isfinite(parsed)
        || parsed < 0.0f || parsed > 30.0f) {
        Output::send(STR("[PalCombo] invalid EarlyStartSeconds; using 3.0\n"));
        return 3.0f;
    }
    return parsed;
}

static auto object_return(UObject* object, const CharType* name) -> UObject* {
    if (!object) return nullptr;
    auto* function = object->GetFunctionByNameInChain(name);
    auto* result = function ? function->FindProperty(FName(STR("ReturnValue"))) : nullptr;
    if (!result || result->GetOffset_ForInternal() + sizeof(UObject*) > 64) return nullptr;
    std::array<std::byte, 64> params{};
    object->ProcessEvent(function, params.data());
    return *result->ContainerPtrToValuePtr<UObject*>(params.data());
}

static auto object_property(UObject* object, const CharType* name) -> UObject* {
    if (!object || !object->GetClassPrivate()) return nullptr;
    auto* property = object->GetClassPrivate()->FindProperty(FName(name));
    return property ? *property->ContainerPtrToValuePtr<UObject*>(object) : nullptr;
}

static auto bool_return(UObject* object, const CharType* name) -> std::optional<bool> {
    if (!object) return std::nullopt;
    auto* function = object->GetFunctionByNameInChain(name);
    auto* result = function ? function->FindProperty(FName(STR("ReturnValue"))) : nullptr;
    if (!result || result->GetOffset_ForInternal() + sizeof(bool) > 64) return std::nullopt;
    std::array<std::byte, 64> params{};
    object->ProcessEvent(function, params.data());
    return *result->ContainerPtrToValuePtr<bool>(params.data());
}

static auto is_riding(UObject* actor) -> std::optional<bool> {
    if (!actor) return std::nullopt;
    static UClass* marker_class{};
    if (!marker_class)
        marker_class = UObjectGlobals::StaticFindObject<UClass*>(
            nullptr, nullptr, STR("/Script/Pal.PalRideMarkerComponent"));
    if (!marker_class) return std::nullopt;
    auto* function = actor->GetFunctionByNameInChain(STR("GetComponentByClass"));
    auto* input = function ? function->FindProperty(FName(STR("ComponentClass"))) : nullptr;
    auto* result = function ? function->FindProperty(FName(STR("ReturnValue"))) : nullptr;
    if (!input || !result || input->GetOffset_ForInternal() + sizeof(UClass*) > 64
        || result->GetOffset_ForInternal() + sizeof(UObject*) > 64) return std::nullopt;
    std::array<std::byte, 64> params{};
    *input->ContainerPtrToValuePtr<UClass*>(params.data()) = marker_class;
    actor->ProcessEvent(function, params.data());
    auto* marker = *result->ContainerPtrToValuePtr<UObject*>(params.data());
    return marker ? bool_return(marker, STR("IsRiding")) : std::optional<bool>{false};
}

static auto bool_slot(UObject* slot, const CharType* name, int id) -> bool {
    if (!slot) return false;
    auto* function = slot->GetFunctionByNameInChain(name);
    auto* input = function ? function->FindProperty(FName(STR("SlotID"))) : nullptr;
    auto* result = function ? function->FindProperty(FName(STR("ReturnValue"))) : nullptr;
    if (!input || !result || input->GetOffset_ForInternal() + sizeof(int32_t) > 64
        || result->GetOffset_ForInternal() + sizeof(bool) > 64) return false;
    std::array<std::byte, 64> params{};
    *input->ContainerPtrToValuePtr<int32_t>(params.data()) = id;
    slot->ProcessEvent(function, params.data());
    return *result->ContainerPtrToValuePtr<bool>(params.data());
}

static auto float_slot(UObject* slot, const CharType* name, int id) -> std::optional<float> {
    if (!slot) return std::nullopt;
    auto* function = slot->GetFunctionByNameInChain(name);
    auto* input = function ? function->FindProperty(FName(STR("SlotID"))) : nullptr;
    auto* result = function ? function->FindProperty(FName(STR("ReturnValue"))) : nullptr;
    if (!input || !result || result->GetElementSize() != sizeof(float)
        || input->GetOffset_ForInternal() + sizeof(int32_t) > 64
        || result->GetOffset_ForInternal() + sizeof(float) > 64) return std::nullopt;
    std::array<std::byte, 64> params{};
    *input->ContainerPtrToValuePtr<int32_t>(params.data()) = id;
    slot->ProcessEvent(function, params.data());
    const float seconds = *result->ContainerPtrToValuePtr<float>(params.data());
    return std::isfinite(seconds) && seconds >= 0.0f
        ? std::optional<float>{seconds} : std::nullopt;
}

static auto player_pal_controller(UObject* actor) -> UObject* {
    if (!actor || !actor->GetClassPrivate()) return nullptr;
    auto* controller = object_return(actor, STR("GetController"));
    return controller && controller->GetClassPrivate()
        && controller->GetClassPrivate()->GetFullName().find(STR("MonsterAIController_Otomo"))
            != StringType::npos ? controller : nullptr;
}

static auto readiness(UObject* slot) -> Ready {
    const bool second_valid = bool_slot(slot, STR("IsValidSkill"), 1);
    const bool second_ready = second_valid && bool_slot(slot, STR("IsCoolTimeFinish"), 1);
    std::optional<float> second_remaining;
    if (second_valid && !second_ready) {
        const auto elapsed = float_slot(slot, STR("GetCoolTime"), 1);
        const auto rate = float_slot(slot, STR("GetCoolTimeRate"), 1);
        if (elapsed && rate) second_remaining = remaining_seconds(*elapsed, *rate);
    }
    return {
        bool_slot(slot, STR("IsValidSkill"), 0) && bool_slot(slot, STR("IsCoolTimeFinish"), 0),
        second_ready,
        bool_slot(slot, STR("IsValidSkill"), 2) && bool_slot(slot, STR("IsCoolTimeFinish"), 2),
        second_remaining,
    };
}

// UPalAIActionCombatBase::ChangeNextAction calls this C++ selector directly.
// Its signature is (UPalActiveSkillSlot*, AActor*, ignored Waza-ID array).
// The UFunction hook does not run on this direct call, so detour the native
// function, retain its original side effects, and replace only its slot result.
static auto native_find_slot(UObject* slot, UObject* target, void* ignored_ids) -> int32_t {
    const auto caller = reinterpret_cast<uintptr_t>(_ReturnAddress());
    using Selector = int32_t (*)(UObject*, UObject*, void*);
    const int original = reinterpret_cast<Selector>(selector_trampoline)(slot, target, ignored_ids);
    auto* actor = object_property(slot, STR("SelfActor"));
    if (is_riding(actor) == true) {
        if (combo_states.erase(actor) && reset_log_count++ < 30)
            Output::send(STR("[PalCombo] reset combo on mounted Pal actor={}\n"),
                         actor->GetFullName());
        return original;
    }
    auto* controller = player_pal_controller(actor);
    if (!controller) return original;
    if (caller != reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)) + direct_call_rva + 5) {
        if (bypass_log_count++ < 20)
            Output::send(STR("[PalCombo] other player-Pal selector caller={:X} original={} actor={}\n"),
                         caller - reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)),
                         original, actor->GetFullName());
        return original;
    }

    auto& state = combo_states[actor];
    // Riding replaces the Pal's controller and can bypass this selector entirely.
    const bool controller_changed = state.controller && state.controller != controller;
    if (controller_changed && reset_log_count++ < 30)
        Output::send(STR("[PalCombo] reset combo after controller change actor={}\n"),
                     actor->GetFullName());
    if (state.slot != slot || state.controller != controller
        || (target && state.target && target != state.target))
        state = {slot, target, controller};
    else if (target) state.target = target;
    const auto ready = readiness(slot);
    const auto previous_phase = state.phase;
    const auto choice = select(ready, state.phase, early_start_seconds);
    const int selected = choice.value_or(-1);
    const bool changed = !state.has_selection_log || state.last_original != original
        || state.last_selected != selected || state.last_phase_before != previous_phase
        || state.last_phase_after != state.phase
        || state.last_ready.first != ready.first || state.last_ready.second != ready.second
        || state.last_ready.third != ready.third;
    if (changed && selection_log_count++ < 500)
        Output::send(STR("[PalCombo] select actor={} target={:X} original={} selected={} phase={}->{} ready={},{},{} slot2_remaining={}\n"),
                     actor->GetFullName(), reinterpret_cast<uintptr_t>(target),
                     original, selected, static_cast<int>(previous_phase),
                     static_cast<int>(state.phase), ready.first, ready.second, ready.third,
                     ready.second_remaining_seconds.value_or(-1.0f));
    state.has_selection_log = true;
    state.last_original = original;
    state.last_selected = selected;
    state.last_phase_before = previous_phase;
    state.last_phase_after = state.phase;
    state.last_ready = ready;
    if (state.phase == Phase::waiting_for_second && !ready.second && !state.logged_wait) {
        Output::send(STR("[PalCombo] waiting for slot 2; no filler permitted between combo skills\n"));
        state.logged_wait = true;
    }
    if (choice == 0) state.logged_wait = false;
    return choice.value_or(-1);
}

class PalComboNative final : public CppUserModBase {
    bool installed{};
public:
    PalComboNative() {
        ModName = STR("PalCombo");
        ModVersion = STR("1.0.7-dev");
        ModAuthors = STR("Codex");
        ModDescription = STR("Native combat slot selector detour");
        early_start_seconds = read_early_start_seconds();
    }
    auto on_update() -> void override {
        if (installed) return;
        auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        if (!base) return;
        auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if (dos->e_magic != IMAGE_DOS_SIGNATURE) return;
        auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
        if (nt->Signature != IMAGE_NT_SIGNATURE
            || nt->OptionalHeader.SizeOfImage <= selector_rva + selector_prefix.size()) return;
        auto* target = base + selector_rva;
        auto* call = base + direct_call_rva;
        int32_t relative{};
        std::memcpy(&relative, call + 1, sizeof(relative));
        if (std::memcmp(target, selector_prefix.data(), selector_prefix.size()) != 0
            || call[0] != 0xE8 || call + 5 + relative != target) {
            Output::send(STR("[PalCombo] unsupported game binary; hook not installed\n"));
            installed = true;
            return;
        }
        selector_detour = std::make_unique<PLH::x64Detour>(
            reinterpret_cast<uint64_t>(target),
            reinterpret_cast<uint64_t>(&native_find_slot), &selector_trampoline);
        if (!selector_detour->hook()) {
            selector_detour.reset();
            Output::send(STR("[PalCombo] detour installation failed\n"));
            installed = true;
            return;
        }
        installed = true;
        Output::send(STR("[PalCombo] installed native selector detour; EarlyStartSeconds={}\n"),
                     early_start_seconds);
    }
    ~PalComboNative() override {
        if (selector_detour) selector_detour->unHook();
    }
};
} // namespace pal_combo

extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() {
    return new pal_combo::PalComboNative();
}
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) {
    delete mod;
}

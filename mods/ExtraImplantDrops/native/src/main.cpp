#define NOMINMAX
#include <Windows.h>
#include <intrin.h>
#include <atomic>
#include <cstring>
#include <filesystem>
#include <memory>
#include <string_view>
#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/NameTypes.hpp>
#include <Unreal/UnrealInitializer.hpp>
#include <polyhook2/Detour/x64Detour.hpp>
#include "binary_guard.hpp"
#include "drop_plan.hpp"
#include "implant_rules.hpp"
#include "game_loot.hpp"
#include "config_value.hpp"

namespace extra_implant_drops {
using namespace RC;
using namespace RC::Unreal;
using Builder = void (*)(void*, DropArray*, void*, const Location*, void*);
using Processor = void (*)(void*, DropArray*, const DropSource*, const Location*, void*, float, bool);
static std::uint64_t trampoline{};
static std::unique_ptr<PLH::x64Detour> detour;
static std::uint64_t processor_trampoline{};
static std::unique_ptr<PLH::x64Detour> processor_detour;
static std::uintptr_t game_base{};
static Settings settings;
static std::array<bool, implant_rules.size()> rule_enabled;
static bool debug{};
static thread_local bool augmenting{};
struct Harvest { Plan base; DropArray* output; bool applied{}; };
static thread_local Harvest* current_harvest{};
static std::atomic_uint warnings{};

static void warn(const CharType* text) {
    if (warnings.fetch_add(1) < 10) Output::send(STR("[ExtraImplantDrops] {}\n"), text);
}
static std::filesystem::path config_path() {
    HMODULE module{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
        GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&config_path), &module)) return {};
    std::array<wchar_t, 32768> path{};
    const auto length = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) return {};
    return std::filesystem::path(path.data()).parent_path().parent_path() / L"config.ini";
}
static int read_int(const std::filesystem::path& path, const wchar_t* section,
                    const wchar_t* key, int fallback, int minimum, int maximum) {
    const auto value = static_cast<int>(GetPrivateProfileIntW(section, key, fallback, path.c_str()));
    return value >= minimum && value <= maximum ? value : fallback;
}
static void read_config() {
    const auto path = config_path();
    std::array<wchar_t, 128> value{};
    GetPrivateProfileStringW(L"Harvest", L"DropChance", L"0.5", value.data(),
        static_cast<DWORD>(value.size()), path.c_str());
    settings.drop_chance = parse_drop_chance(value.data());
    debug = read_int(path, L"Harvest", L"Debug", 0, 0, 1) != 0;
    for (std::size_t i = 0; i < implant_rules.size(); ++i)
        rule_enabled[i] = read_int(path, L"Implants", implant_rules[i].passive, 1, 0, 1) != 0;
}
static std::optional<std::uint64_t> resolve(std::uint64_t raw) {
    FName passive(static_cast<std::int64_t>(raw));
    const auto text = passive.ToString();
    std::wstring_view id{text};
    constexpr std::wstring_view prefix = L"PassiveSkill_";
    if (id.starts_with(prefix)) id.remove_prefix(prefix.size());
    for (std::size_t i = 0; i < implant_rules.size(); ++i) {
        if (!rule_enabled[i] || id != implant_rules[i].passive) continue;
        const FName item(implant_rules[i].item, FNAME_Find);
        if (item.IsNone()) { warn(STR("implant name unavailable; skipped without creating a name")); return {}; }
        return std::uint64_t(item.GetComparisonIndex().ToUnstableInt())
            | (std::uint64_t(item.GetNumber()) << 32);
    }
    return {};
}

// Scope contains copied names/items only and lives on this native stack. Nested
// native deaths get independent scopes; nothing survives the original call.
static void build_drops(void* manager, DropArray* output, void* individual,
                        const Location* location, void* trainer) {
    Harvest harvest{{}, output};
    if (allowed(IsInGameThreadRaw(), augmenting) && output && individual && location && valid(*output)) {
        std::uint32_t flags{};
        std::memcpy(&flags, static_cast<const std::byte*>(individual) + 8, sizeof(flags));
        NameArray passives{};
        if (!(flags & 0x60000000)) {
            std::memcpy(&passives, static_cast<const std::byte*>(individual) + guard::passive_offset, sizeof(passives));
            if (valid(passives)) {
                std::array<std::uint64_t, 4> copied{};
                const auto count = std::min<std::size_t>(passives.count, copied.size());
                if (count) std::memcpy(copied.data(), passives.data, count * sizeof(copied[0]));
                ScopedValue scope(augmenting, true);
                try { harvest.base = plan(std::span{copied.data(), count}, *location, settings, resolve); }
                catch (const std::exception&) { warn(STR("implant resolution failed; original drops preserved")); }
            }
        }
    }
    ScopedValue scope(current_harvest, &harvest);
    reinterpret_cast<Builder>(trampoline)(manager, output, individual, location, trainer);
}

// Reuse the exact quantity constructor used for ordinary Pal loot. The source
// drop builder has already calculated the attacker's partner bonus. The target
// passive bonus and world setting are calculated here using the same natives.
static void process_drops(void* manager, DropArray* output, const DropSource* source,
                          const Location* location, void* killer, float partner_bonus, bool item_bonus) {
    const auto caller = reinterpret_cast<std::uintptr_t>(_ReturnAddress());
    reinterpret_cast<Processor>(processor_trampoline)(manager, output, source, location, killer, partner_bonus, item_bonus);
    auto* harvest = current_harvest;
    if (caller != game_base + guard::processor_call_rva + 5 || !harvest || harvest->applied
        || harvest->output != output || !harvest->base.count || !allowed(IsInGameThreadRaw(), augmenting)
        || !source || !valid(source->passives) || !valid(*output)) return;
    harvest->applied = true;
    ScopedValue scope(augmenting, true);
    try {
        const GameLoot game(game_base);
        const auto world = game.world_rate(manager);
        if (!world || !std::isfinite(partner_bonus)) return;
        const float bonus = game.drop_bonus(manager, source->passives, partner_bonus);
        const auto additions = native_counts(harvest->base, [&](Drop& entry) {
            game.roll(manager, entry, settings.native_drop_rate(), bonus, *world, killer, item_bonus);
        });
        const bool appended = append(*output, additions, [&](DropArray& array, std::int32_t previous) {
            game.grow(array, previous);
        });
        if (!appended) warn(STR("invalid drop array; skipped augmentation"));
        else if (debug && additions.count)
            Output::send(STR("[ExtraImplantDrops] extra drops appended={} total={} chance={} world_rate={} bonus={}\n"),
                additions.count, output->count, settings.drop_chance, *world, bonus);
    } catch (const std::exception&) {
        warn(STR("augmentation failed; no alternate inventory call or retry"));
    }
}

static bool compatible(std::uint8_t* base) {
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return false;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.TimeDateStamp != guard::timestamp
        || nt->OptionalHeader.SizeOfImage != guard::image_size || FName::StaticSize() != 8) return false;
    for (const auto& region : guard::regions) {
        if (region.rva > nt->OptionalHeader.SizeOfImage - region.size
            || std::memcmp(base + region.rva, region.bytes, region.size)) return false;
    }
    return true;
}

class ExtraImplantDropsNative final : public CppUserModBase {
public:
    ExtraImplantDropsNative() {
        ModName = STR("ExtraImplantDrops"); ModVersion = STR("1.0.0");
        ModAuthors = STR("ourongxing");
        ModDescription = STR("Implants in native Pal death drops with game quantity modifiers");
        read_config();
    }
    void on_unreal_init() override {
        auto* base = reinterpret_cast<std::uint8_t*>(GetModuleHandleW(nullptr));
        if (!base || !compatible(base)) {
            Output::send(STR("[ExtraImplantDrops] incompatible game or hook conflict; no hook installed\n")); return;
        }
        game_base = reinterpret_cast<std::uintptr_t>(base);
        processor_detour = std::make_unique<PLH::x64Detour>(game_base + guard::processor_rva,
            reinterpret_cast<std::uint64_t>(&process_drops), &processor_trampoline);
        if (!processor_detour->hook()) {
            processor_detour.reset(); Output::send(STR("[ExtraImplantDrops] processor hook failed\n")); return;
        }
        detour = std::make_unique<PLH::x64Detour>(game_base + guard::builder_rva,
            reinterpret_cast<std::uint64_t>(&build_drops), &trampoline);
        if (!detour->hook()) {
            processor_detour->unHook(); processor_detour.reset();
            detour.reset(); Output::send(STR("[ExtraImplantDrops] hook installation failed\n")); return;
        }
        Output::send(STR("[ExtraImplantDrops] installed native death-drop hooks; extra chance={} base_count=1; game rates; rules={}\n"),
            settings.drop_chance, implant_rules.size());
    }
    ~ExtraImplantDropsNative() override {
        if (detour) { detour->unHook(); detour.reset(); }
        if (processor_detour) { processor_detour->unHook(); processor_detour.reset(); }
    }
};
} // namespace extra_implant_drops

extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() {
    return new extra_implant_drops::ExtraImplantDropsNative();
}
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }

#define NOMINMAX
#include <Windows.h>
#include <intrin.h>
#include <array>
#include <atomic>
#include <cstring>
#include <memory>
#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/NameTypes.hpp>
#include <polyhook2/Detour/x64Detour.hpp>
#include "balance.hpp"
#include "binary_guard.hpp"

namespace {
using namespace RC;
using namespace RC::Unreal;
using Getter = int(*)(void*, const void*);
using RowGetter = const std::byte*(*)(void*, std::uint64_t);
std::array<std::uint64_t, 10> trampolines{};
std::array<std::unique_ptr<PLH::x64Detour>, 10> detours{};
std::uintptr_t game_base{};
struct CallContext {
    std::uint64_t id{};
    std::uintptr_t caller{};
    bool enabled{}, modified{};
    alignas(16) std::array<std::byte,0x80> scalar_row{};
};
thread_local CallContext* active{};
std::atomic<unsigned> observed{};
#ifdef AWAKENINGTRUST_VALIDATION
void validation_probe(void* database, const std::byte* save);
#endif

template<class T> T scalar(const void* value, std::size_t offset) {
    T result{};
    std::memcpy(&result, static_cast<const std::byte*>(value) + offset, sizeof(T));
    return result;
}

// Only inspect the current Pal row. Awakening is checked by the getter context.
bool eligible_row(const std::byte* row) {
    return row && scalar<std::uint8_t>(row,0x28)!=0 && scalar<std::uint8_t>(row,0x190)==0;
}

// These contexts never modify the shared row or individual/save parameter.
// SaveParameter starts at 0x3d0 in the guarded client IndividualParameter.
template<int I> int get_stat(void* database, const void* parameter) {
    constexpr int stat = I % 3;
    const auto original = reinterpret_cast<Getter>(trampolines[I]);
    if (!parameter) return original(database, parameter);
    const auto* save = static_cast<const std::byte*>(parameter) + (I < 3 ? 0x3d0 : 0);
    CallContext context;
    context.id=scalar<std::uint64_t>(save,0);
    context.enabled=scalar<std::uint8_t>(save,0x51)!=0;
    context.caller=game_base+guard::row_calls[I];
    struct Scope {
        CallContext* previous;
        Scope(CallContext* value) : previous(active) { active = value; }
        ~Scope() { active = previous; }
    } scope(&context);
    const int result = original(database, parameter);
    if (context.modified && observed.load(std::memory_order_relaxed)<9 && observed.fetch_add(1) < 9)
        Output::send(STR("[AwakeningTrust] awakened calculation stat={} result={}\n"), stat,result);
#ifdef AWAKENINGTRUST_VALIDATION
    if constexpr (I < 3) {
        validation_probe(database,save);
    }
#endif
    return result;
}

#ifdef AWAKENINGTRUST_VALIDATION
// Diagnostic build only. Native save getters take const references and only read
// these scalar fields / referenced passive arrays. The copy is not an owning
// struct: no constructor/destructor runs, no pointers are altered or retained.
// Original save memory, awakening flags and inventory remain untouched.
void validation_probe(void* database, const std::byte* save) {
    static std::atomic<bool> once{};
    if (once.exchange(true)) return;
    unsigned passed=0,total=0;
    const std::array<Getter,3> gated{&get_stat<3>,&get_stat<4>,&get_stat<5>};
    for (const auto* name : {L"SheepBall",L"IceHorse_Dark"}) {
        const auto id=FName(name).ToUnstableInt();
        for (int rank : {0,7,10}) for (int awaken : {0,1}) {
            alignas(16) std::array<std::byte,0x370> copy;
            std::memcpy(copy.data(),save,copy.size());
            std::memcpy(copy.data(),&id,8);
            copy[0x51]=std::byte(awaken);
            const int points=rank==0?0:(rank==7?80000:200000);
            std::memcpy(copy.data()+0x2ec,&points,4);
            for (int s=0;s<3;++s) {
                // Clear any outer calculation context for the vanilla comparison.
                auto* outer=active;active=nullptr;
                const int vanilla=reinterpret_cast<Getter>(trampolines[3+s])(database,copy.data());
                const int adjusted=gated[s](database,copy.data());
                active=outer;
                const bool expected_boost=name==std::wstring_view(L"SheepBall") && rank>0 && awaken;
                const bool ok=expected_boost?adjusted>vanilla:adjusted==vanilla;
                ++total;if(ok)++passed;
                Output::send(STR("[AwakeningTrust.Validation] {} trust={} awake={} stat={} vanilla={} gated={} pass={}\n"),
                    name,rank,awaken,s,vanilla,adjusted,ok);
            }
        }
    }
    Output::send(STR("[AwakeningTrust.Validation] completed {}/{}; local copies only\n"),passed,total);
}
#endif

const std::byte* get_row(void* database, std::uint64_t id) {
    const auto caller=reinterpret_cast<std::uintptr_t>(_ReturnAddress());
    const auto* original=reinterpret_cast<RowGetter>(trampolines[6])(database,id);
    auto* context=active;
    if(!original || !context || !context->enabled || caller!=context->caller || id!=context->id) return original;
    if(!eligible_row(original)) return original;
    const std::array<int,3> base{scalar<int>(original,0x58),scalar<int>(original,0x60),scalar<int>(original,0x64)};
    const std::array<float,3> growth{scalar<float>(original,0x70),scalar<float>(original,0x74),scalar<float>(original,0x78)};
    const auto delta=bond::growth_delta(base,growth,0);
    if(!(delta>0))return original;
    // Only the verified scalar prefix is copied. No owning arrays, locks or
    // FString/FText objects are copied, constructed or destroyed. These six
    // guarded callers read only base stats and friendship fields in this prefix.
    std::memcpy(context->scalar_row.data(),original,context->scalar_row.size());
    for(int stat=0;stat<3;++stat) {
        const float value=bond::gated_growth(base,growth,stat,true);
        std::memcpy(context->scalar_row.data()+0x70+4*stat,&value,4);
    }
    context->modified=true;
    return context->scalar_row.data();
}

// Native UI breakdown calculators accept exclusion flags. Pass them through
// unchanged so vanilla subtraction/rounding derives the boosted friendship term.
template<int S> int get_detail(void* database, const void* parameter, const void* flags) {
    using Detail = int(*)(void*, const void*, const void*);
    const auto original = reinterpret_cast<Detail>(trampolines[7+S]);
    if (!parameter) return original(database,parameter,flags);
    const auto* save=static_cast<const std::byte*>(parameter)+0x3d0;
    CallContext context;
    context.id=scalar<std::uint64_t>(save,0);
    context.enabled=scalar<std::uint8_t>(save,0x51)!=0;
    context.caller=game_base+guard::detail_row_calls[S];
    struct Scope {
        CallContext* previous;
        Scope(CallContext* value):previous(active){active=value;}
        ~Scope(){active=previous;}
    } scope(&context);
    return original(database,parameter,flags);
}

bool compatible(const std::uint8_t* base) {
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return false;
    const auto* pe = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.TimeDateStamp != guard::timestamp ||
        pe->OptionalHeader.SizeOfImage != guard::image_size || FName::StaticSize() != 8) return false;
    for (const auto& region : guard::regions)
        if (region.rva > guard::image_size-region.size || std::memcmp(base+region.rva,region.bytes,region.size)) return false;
    return true;
}

class AwakeningTrust final : public CppUserModBase {
public:
    AwakeningTrust() {
        ModName=STR("Awakening Trust / 信赖觉醒");ModVersion=STR("0.3.0");ModAuthors=STR("ourongxing");
        ModDescription=STR("Awakening unlocks stronger Trust growth: proportionally raise vanilla Trust Lv.10 stat totals below 450 to 450; preserve totals at or above 450 and the original Awakening bonus.");
    }
    void on_unreal_init() override {
        const auto* base = reinterpret_cast<const std::uint8_t*>(GetModuleHandleW(nullptr));
        if (!base || !compatible(base)) {
            Output::send(STR("[AwakeningTrust] unsupported binary or hook conflict; vanilla unchanged\n"));return;
        }
        game_base = reinterpret_cast<std::uintptr_t>(base);
        const std::array<std::uint64_t,10> callbacks{
            reinterpret_cast<std::uint64_t>(&get_stat<0>),reinterpret_cast<std::uint64_t>(&get_stat<1>),reinterpret_cast<std::uint64_t>(&get_stat<2>),
            reinterpret_cast<std::uint64_t>(&get_stat<3>),reinterpret_cast<std::uint64_t>(&get_stat<4>),reinterpret_cast<std::uint64_t>(&get_stat<5>),
            reinterpret_cast<std::uint64_t>(&get_row),
            reinterpret_cast<std::uint64_t>(&get_detail<0>),reinterpret_cast<std::uint64_t>(&get_detail<1>),reinterpret_cast<std::uint64_t>(&get_detail<2>)};
        for (int i=0;i<10;++i) {
            detours[i]=std::make_unique<PLH::x64Detour>(game_base+guard::hook_rvas[i],callbacks[i],&trampolines[i]);
            if (!detours[i]->hook()) {
                for (int j=i;j>=0;--j) {if(detours[j]) {if(j<i)detours[j]->unHook();detours[j].reset();}}
                Output::send(STR("[AwakeningTrust] hook installation failed at index={} rva={:x}; rolled back to vanilla\n"),i,guard::hook_rvas[i]);return;
            }
        }
        Output::send(STR("[AwakeningTrust] installed awakening gate; target=450, dynamic eligibility, dedicated_server={}, no shared-table/save edits\n"),guard::dedicated_server);
    }
    ~AwakeningTrust() override {for(int i=9;i>=0;--i)if(detours[i]){detours[i]->unHook();detours[i].reset();}}
};
}
extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod(){return new AwakeningTrust();}
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod){delete mod;}

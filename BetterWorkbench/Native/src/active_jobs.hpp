#pragma once
// Native callbacks execute synchronously. No Lua state or borrowed allocation
// crosses callbacks. Definitions are immutable; progress stays in the native save.
using better_workbench::Amounts;
struct ActiveJob : better_workbench::Journal {
    std::byte* row{}; // A deep native recipe copy, never stored in the journal.
};
using better_workbench::alias_text;
std::atomic<bool> active_ready{};
int active_status(const LuaMadeSimple::Lua& lua) { lua.set_bool(active_ready.load()); return 1; }
std::recursive_mutex jobs_mutex;
std::map<std::wstring,std::shared_ptr<ActiveJob>> jobs;
std::vector<std::unique_ptr<PLH::x64Detour>> active_detours;
uint64_t row_trampoline{}, map_trampoline{}, complete_trampoline{}, deficit_trampoline{}, max_trampoline{};
uint64_t preview_trampoline{};
std::atomic<unsigned> preview_logs{};
std::atomic<unsigned> computer_logs{},computer_errors{},computer_stock_logs{};
thread_local std::shared_ptr<ActiveJob> pending_job;
thread_local void* pending_model{};
uintptr_t game_base() { return reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)); }
using RowFunction = const std::byte* (*)(void*, uint64_t);
using MapFunction = void (*)(void*,void*,uint64_t,void*);
using CompleteFunction = void (*)(void*,uint64_t);
using DeficitFunction = void (*)(void*,BorrowedArray*);
template<class T> T field(void* object, std::size_t offset) {
    T result{}; std::memcpy(&result, static_cast<std::byte*>(object)+offset,sizeof(T)); return result;
}
#include "storage_probe.hpp"
bool recipe_candidate(const std::wstring& id) { return !id.empty() && id!=L"None" && !alias_text(id); }
bool is_job_name(uint64_t id) {
    return alias_text(FName(static_cast<int64_t>(id)).ToString());
}
Amounts amounts(const std::vector<Material>& materials) {
    Amounts result;
    for (const auto& item : materials) if (item.quantity) result[item.name]+=item.quantity;
    return result;
}
void set_material_array(BorrowedArray* out, const Amounts& values) {
    if (!out || values.size()>64) throw std::runtime_error("material array limit");
    validate_array(*out,64);
    auto* allocation = values.empty() ? nullptr : static_cast<std::byte*>(FMemory::Malloc(values.size()*12,8));
    if (!allocation && !values.empty()) throw std::bad_alloc();
    std::size_t index{};
    try {
        for (const auto& [name,count] : values) {
            if (count<1 || count>1000000000) throw std::runtime_error("material amount limit");
            const auto id=name_bits(name.c_str());
            std::memcpy(allocation+index*12,&id,8); std::memcpy(allocation+index*12+8,&count,4); ++index;
        }
    } catch (...) { if (allocation) FMemory::Free(allocation); throw; }
    if (out->data) FMemory::Free(const_cast<std::byte*>(out->data));
    *out={allocation,static_cast<int32_t>(values.size()),static_cast<int32_t>(values.size())};
}
std::filesystem::path jobs_directory() {
    HMODULE module{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&jobs_directory),&module)) throw std::runtime_error("module path unavailable");
    wchar_t path[32768]{};
    const auto size=GetModuleFileNameW(module,path,32768);
    if (!size || size>=32768) throw std::runtime_error("module path unavailable");
    return std::filesystem::path(path).parent_path().parent_path()/L"Jobs";
}
void persist_job(const ActiveJob& job) {
    const auto bytes=better_workbench::encode_journal(job,std::wstring(expected_game_hash,expected_game_hash+64));
    better_workbench::decode_journal(bytes,job.alias,std::wstring(expected_game_hash,expected_game_hash+64));
    auto directory=jobs_directory(); std::filesystem::create_directories(directory);
    auto temporary=directory/(job.alias+L".tmp"), destination=directory/(job.alias+L".bwj");
    HANDLE file=CreateFileW(temporary.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(file==INVALID_HANDLE_VALUE) throw std::runtime_error("job journal creation failed");
    DWORD written{}; const bool saved=WriteFile(file,bytes.data(),static_cast<DWORD>(bytes.size()),&written,nullptr)
        && written==bytes.size() && FlushFileBuffers(file);
    CloseHandle(file);
    if(!saved || !MoveFileExW(temporary.c_str(),destination.c_str(),MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temporary.c_str()); throw std::runtime_error("job journal commit failed");
    }
}
std::shared_ptr<ActiveJob> find_job(uint64_t id) {
    std::lock_guard lock(jobs_mutex);
    auto name=FName(static_cast<int64_t>(id)).ToString();
    if(!alias_text(name)) throw std::runtime_error("invalid job identity");
    if(auto existing=jobs.find(name);existing!=jobs.end()) return existing->second;
    if(jobs.size()>=4096) throw std::runtime_error("job cache limit");
    const auto path=jobs_directory()/(name+(name.starts_with(L"SRJ_") ? L".srj" : L".bwj"));
    std::ifstream input(path,std::ios::binary|std::ios::ate);
    if(!input) throw std::runtime_error("job journal unavailable");
    const auto size=input.tellg(); if(size<100 || size>262144) throw std::runtime_error("job journal size mismatch");
    std::vector<uint8_t> bytes(static_cast<std::size_t>(size)); input.seekg(0);
    if(!input.read(reinterpret_cast<char*>(bytes.data()),size)) throw std::runtime_error("job journal read failed");
    auto job=std::make_shared<ActiveJob>();
    static_cast<better_workbench::Journal&>(*job)=better_workbench::decode_journal(std::move(bytes),name,std::wstring(expected_game_hash,expected_game_hash+64));
    jobs[name]=job; return job;
}
std::size_t job_index(const std::shared_ptr<ActiveJob>& job,void* model) {
    if(!job || !model || field<std::array<uint8_t,16>>(model,0xb0)!=job->station) throw std::runtime_error("job station mismatch");
    if(pending_job==job && pending_model==model) return 0;
    const auto requested=field<int32_t>(model,0x298), remaining=field<int32_t>(model,0x29c);
    if(requested!=job->schedule.units.size() || remaining<0 || remaining>requested
        || field<uint64_t>(model,0x290)!=name_bits(job->alias.c_str())) throw std::runtime_error("native job state mismatch");
    return static_cast<std::size_t>(requested-remaining);
}
const Amounts& job_unit(const std::shared_ptr<ActiveJob>& job,void* model) {
    const auto index=job_index(job,model);
    if(index>=job->schedule.units.size()) throw std::runtime_error("job already complete");
    return job->schedule.units[index];
}
const std::byte* virtual_row(void* table,uint64_t id) {
    if(!active_ready || !is_job_name(id)) return reinterpret_cast<RowFunction>(row_trampoline)(table,id);
    try {
        auto job=find_job(id); std::lock_guard lock(jobs_mutex);
        if(!job->row) {
            auto* source=reinterpret_cast<RowFunction>(row_trampoline)(table,name_bits(job->root.c_str()));
            auto* function=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,STR("/Script/Pal.PalMapObjectConvertItemModel:GetCurrentRecipe"));
            auto* type=static_cast<FStructProperty*>(function->GetReturnProperty())->GetStruct().Get();
            if(!source || !type || type->GetSize()!=0x88) throw std::runtime_error("alias recipe source missing");
            auto* row=static_cast<std::byte*>(FMemory::Malloc(type->GetSize(),type->GetMinAlignment()));
            if(!row) throw std::bad_alloc();
            type->InitializeStruct(row); type->CopyScriptStruct(row,source);
            std::vector<uint64_t> identities;
            if(job->schedule.total.size()>5) identities.push_back(name_bits(job->alias.c_str()));
            else for(const auto& [name,count]:job->schedule.total) identities.push_back(name_bits(name.c_str()));
            better_workbench::apply_to_recipe_copy({row,0x88},better_workbench::slot_identities(identities,name_bits(L"None")),*recipe_layout());
            job->row=row;
        }
        return job->row;
    } catch(const std::exception&) { return nullptr; }
}
#include "dynamic_inputs.hpp"
#include "native_consumption.hpp"
void job_cost_map(void* world,void* owner,uint64_t id,void* out) {
    if(!active_ready || !is_job_name(id)) { reinterpret_cast<MapFunction>(map_trampoline)(world,owner,id,out); return; }
    // Let the original initialize/empty its exact native map representation.
    // Then use the same game insertion/hash functions as the original method.
    reinterpret_cast<MapFunction>(map_trampoline)(world,owner,name_bits(L"None"),out);
    try {
        const auto& costs=job_unit(find_job(id),owner);
        using HashFunction=int32_t (*)(uint32_t);
        using InsertFunction=int32_t* (*)(void*,uint32_t,const void*);
        for(const auto& [name,count]:costs) {
            std::array<std::byte,12> pair{}; const auto bits=name_bits(name.c_str()); std::memcpy(pair.data(),&bits,8);
            auto hash=static_cast<uint32_t>(reinterpret_cast<HashFunction>(game_base()+0x34ee990)(static_cast<uint32_t>(bits)))+static_cast<uint32_t>(bits>>32);
            auto* value=reinterpret_cast<InsertFunction>(game_base()+0x2d67dc0)(out,hash,pair.data());
            if(!value) throw std::runtime_error("native map insertion failed"); *value=count;
        }
    } catch(const std::exception&) { Output::send(STR("[BetterWorkbenchNative] blocked invalid job cost map\n")); }
}
void job_complete(void* model,uint64_t argument) {
    const auto id=field<uint64_t>(model,0x290);
    if(active_ready && is_job_name(id)) {
        CompletionContext context; context.model=model;
        try { context.job=find_job(id); prepare_completion(context); }
        catch(const std::exception& error) {
            if(debit_errors.fetch_add(1)<12) {
                const std::string reason(error.what());
                Output::send(STR("[BetterWorkbenchNative] blocked completion before output: {}\n"),std::wstring(reason.begin(),reason.end()));
            }
            return;
        }
        auto* prior=completing_job; completing_job=&context;
        struct Restore { CompletionContext* prior; ~Restore(){completing_job=prior;} } restore{prior};
        reinterpret_cast<CompleteFunction>(complete_trampoline)(model,argument);
        audit_completion(context); return;
    }
    reinterpret_cast<CompleteFunction>(complete_trampoline)(model,argument);
}
void job_deficit(void* model,BorrowedArray* out) {
    const auto id=field<uint64_t>(model,0x290);
    if(!active_ready || !is_job_name(id)) { reinterpret_cast<DeficitFunction>(deficit_trampoline)(model,out); return; }
    try {
        auto job=find_job(id); auto required=better_workbench::suffix(job->schedule,job_index(job,model));
        OwnedNativeArray inputs;
        using InputsFunction=BorrowedArray* (*)(void*,BorrowedArray*);
        reinterpret_cast<InputsFunction>(game_base()+0x300d010)(model,&inputs.value); validate_array(inputs.value,64);
        for(int32_t i=0;i<inputs.value.count;++i) {
            auto* slot=field<void*>(const_cast<std::byte*>(inputs.value.data),i*8); if(!slot) continue;
            auto* object=static_cast<UObject*>(slot); auto* cls=object->GetClassPrivate();
            auto* item_id=cls->FindProperty(FName(STR("ItemId"))); auto* num=cls->FindProperty(FName(STR("StackCount")));
            auto* item_type=item_id && item_id->IsA<FStructProperty>() ? static_cast<FStructProperty*>(item_id)->GetStruct().Get() : nullptr;
            auto* name=item_type ? item_type->FindProperty(FName(STR("StaticId"))) : nullptr;
            if(!name || !num || !name->IsA<FNameProperty>() || !num->IsA<FIntProperty>()
                || item_id->GetOffset_ForInternal()+name->GetOffset_ForInternal()!=0x12c
                || name->GetElementSize()!=8 || num->GetOffset_ForInternal()!=0x154 || num->GetElementSize()!=4)
                throw std::runtime_error("input slot layout mismatch");
            auto item=FName(static_cast<int64_t>(field<uint64_t>(slot,0x12c))).ToString();
            const auto count=field<int32_t>(slot,0x154); if(count<0) throw std::runtime_error("negative native slot");
            if(auto entry=required.find(item);entry!=required.end()) entry->second=std::max(0,entry->second-count);
        }
        std::erase_if(required,[](const auto& pair){return pair.second==0;}); set_material_array(out,required);
    } catch(const std::exception&) { set_material_array(out,{{L"BetterWorkbench_MissingPlan",1000000000}}); }
}
better_workbench::NativePlanner planner_request(void* model,int32_t player,uint64_t root) {
    using UidFunction=void* (*)(void*,void*,int32_t);
    using ContainersFunction=void (*)(void*,void*,BorrowedArray*,uint8_t);
    using TechnologyFunction=void* (*)(void*,void*);
    using PolicyFunction=bool (*)(void*,const uint64_t*);
    std::array<uint8_t,16> uid{};
    reinterpret_cast<UidFunction>(game_base()+0x32f34f0)(uid.data(),model,player);
    if(std::all_of(uid.begin(),uid.end(),[](auto b){return b==0;})) throw std::runtime_error("player unavailable");
    auto* technology=reinterpret_cast<TechnologyFunction>(game_base()+0x32f7e50)(model,uid.data());
    if(!technology) throw std::runtime_error("technology data unavailable");
    std::set<std::wstring> station,allowed;
    for(auto& id:station_recipes(model)) station.insert(std::move(id));
    const auto root_name=FName(static_cast<int64_t>(root)).ToString();
    if(!station.contains(root_name)) throw std::runtime_error("root outside current workbench");
    if(root_name==L"Computer") storage_probe(model);
    std::vector<better_workbench::NativeRecipe> catalog,rows; std::set<std::wstring> names;
    for(const auto& id:station) {
        if(!recipe_candidate(id)) continue;
        const auto bits=name_bits(id.c_str());
        if(reinterpret_cast<PolicyFunction>(game_base()+0x31cc070)(technology,&bits)
            || !reinterpret_cast<PolicyFunction>(game_base()+0x326aa30)(technology,&bits)) continue;
        try {
            const auto row=read_recipe_metadata(model,id.c_str());
            if(row.raw.empty()) continue; // Free recipes stay with vanilla.
            allowed.insert(id); catalog.push_back({row.id,row.output,row.output_amount,amounts(row.raw)});
        } catch(const std::exception&) { if(id==root_name) throw; }
    }
    const auto selected=better_workbench::dependency_recipes(catalog,allowed,root_name);
    if(selected.size()==1) throw std::runtime_error("no same-station intermediate recipe");
    rows.reserve(selected.size());
    for(auto& row:catalog) {
        if(!selected.contains(row.id)) continue;
        auto costs=amounts(read_effective_costs(model,row.id.c_str()));
        if(costs.empty()) { allowed.erase(row.id); continue; }
        for(const auto& [name,count]:costs) names.insert(name);
        row.costs=std::move(costs);
        rows.push_back(std::move(row));
    }
    OwnedNativeArray containers;
    reinterpret_cast<ContainersFunction>(game_base()+0x2fa0d00)(model,uid.data(),&containers.value,2);
    Amounts inventory; const std::vector<std::wstring> items{names.begin(),names.end()};
    for(std::size_t start=0;start<items.size();start+=64) {
        const auto end=std::min(items.size(),start+64);
        const auto part=amounts(read_scoped_stock(model,&containers.value,{items.begin()+start,items.begin()+end}));
        inventory.insert(part.begin(),part.end());
    }
    if(root_name==L"Computer" && computer_stock_logs.fetch_add(1)<4) {
        for(const auto& row:rows) for(const auto& [item,count]:row.costs)
            Output::send(STR("[BetterWorkbenchNative] COMPUTER_COST recipe={} item={} required={} stock={}\n"),row.id,item,count,inventory[item]);
    }
    const auto capacity=dynamic_container_supported(model)?64u:5u;
    return better_workbench::NativePlanner(std::move(rows),std::move(allowed),std::move(inventory),capacity);
}
void active_worker(void* model,int32_t player,uint64_t recipe,int32_t batches,bool option,bool cancel) {
    const auto original=reinterpret_cast<WorkerFunction>(worker_trampoline);
    const auto root=FName(static_cast<int64_t>(recipe)).ToString();
    if(!active_ready || cancel || !recipe_candidate(root) || batches<1 || batches>256 || option
        || field<uint64_t>(model,0x290)!=name_bits(L"None")) { original(model,player,recipe,batches,option,cancel); return; }
    std::shared_ptr<ActiveJob> job;
    try {
        using AuthorityFunction=bool (*)(void*);
        if(!reinterpret_cast<AuthorityFunction>(game_base()+0x3306f40)(model)) { original(model,player,recipe,batches,option,cancel); return; }
        auto schedule=planner_request(model,player,recipe).resolve(root,batches);
        auto vanilla=amounts(read_recipe(model,root.c_str()).effective);
        for(auto& [name,count]:vanilla) count*=batches;
        if(schedule.total==vanilla) { original(model,player,recipe,batches,option,cancel); return; }
        GUID guid{}; if(FAILED(CoCreateGuid(&guid))) throw std::runtime_error("job identity unavailable");
        job=std::make_shared<ActiveJob>(); job->root=root; job->alias=L"BWJ_";
        constexpr wchar_t hex[]=L"0123456789abcdef";
        for(auto b:std::span(reinterpret_cast<const uint8_t*>(&guid),16)) { job->alias+=hex[b>>4]; job->alias+=hex[b&15]; }
        job->station=field<std::array<uint8_t,16>>(model,0xb0); job->schedule=std::move(schedule);
        if(std::all_of(job->station.begin(),job->station.end(),[](auto b){return b==0;})) throw std::runtime_error("station identity unavailable");
        { std::lock_guard lock(jobs_mutex); if(jobs.size()>=4096) throw std::runtime_error("job cache limit"); }
        persist_job(*job); // Durable definition precedes any native material mutation.
        if(job->schedule.total.size()>5) ensure_dynamic_capacity(model,job->schedule.total.size());
        { std::lock_guard lock(jobs_mutex); jobs[job->alias]=job; }
    } catch(const std::exception& error) {
        const std::string message(error.what()); Output::send(STR("[BetterWorkbenchNative] PLAN_REJECTED {}: {}\n"),root,std::wstring(message.begin(),message.end()));
        original(model,player,recipe,batches,option,cancel); return;
    }
    const auto prior=pending_job; auto* previous_model=pending_model;
    pending_job=job; pending_model=model;
    struct Restore { std::shared_ptr<ActiveJob> previous; void* model; ~Restore(){pending_job=previous;pending_model=model;} } restore{prior,previous_model};
    original(model,player,name_bits(job->alias.c_str()),batches,option,cancel);
    Output::send(STR("[BetterWorkbenchNative] ACTIVE_REQUEST root={} batches={} accepted={} inputs={}\n"),root,batches,
        field<uint64_t>(model,0x290)==name_bits(job->alias.c_str()),job->schedule.total.size());
    for(const auto& [id,count]:job->schedule.total) Output::send(STR("[BetterWorkbenchNative] ACTUAL_INPUT {}={}\n"),id,count);
}
int32_t local_player_id(void* world) {
    using ControllerFunction=void* (*)(void*,int32_t);
    auto* controller=static_cast<UObject*>(reinterpret_cast<ControllerFunction>(game_base()+0x528e0b0)(world,0));
    if(!controller) throw std::runtime_error("local controller unavailable");
    auto* state_property=controller->GetClassPrivate()->FindProperty(FName(STR("PlayerState")));
    if(!state_property || !state_property->IsA<FObjectProperty>()
        || state_property->GetOffset_ForInternal()!=0x298 || state_property->GetElementSize()!=8)
        throw std::runtime_error("local player-state property mismatch");
    auto* state=field<UObject*>(controller,0x298); if(!state) throw std::runtime_error("local player state unavailable");
    auto* id_property=state->GetClassPrivate()->FindProperty(FName(STR("PlayerId")));
    if(!id_property || !id_property->IsA<FIntProperty>() || id_property->GetOffset_ForInternal()!=0x294
        || id_property->GetElementSize()!=4) throw std::runtime_error("local network-player ID property mismatch");
    return field<int32_t>(state,0x294);
}
void preview_error(uint64_t recipe,const std::exception& error) {
    const auto id=FName(static_cast<int64_t>(recipe)).ToString();
    if(id==L"Computer") { if(computer_errors.fetch_add(1)>=8) return; }
    else if(preview_logs.fetch_add(1)>=24) return;
    const std::string message(error.what());
    Output::send(STR("[BetterWorkbenchNative] UI_PREVIEW_REJECTED recipe={} reason={}\n"),id,std::wstring(message.begin(),message.end()));
}
bool ui_material_preview(void* world,void* model,uint64_t recipe,int32_t batches,BorrowedArray* out) {
    if(!active_ready || !model || !recipe_candidate(FName(static_cast<int64_t>(recipe)).ToString()) || batches<1 || batches>256) return false;
    try {
        const auto preview=planner_request(model,local_player_id(world),recipe).preview(FName(static_cast<int64_t>(recipe)).ToString(),batches);
        const auto& total=preview.total;
        set_material_array(out,total);
        const auto id=FName(static_cast<int64_t>(recipe)).ToString();
        const bool log=id==L"Computer" ? computer_logs.fetch_add(1)<8 : preview_logs.fetch_add(1)<24;
        if(log) {
            Output::send(STR("[BetterWorkbenchNative] UI_RESOLVED recipe={} batches={} slots={}\n"),FName(static_cast<int64_t>(recipe)).ToString(),batches,total.size());
            for(const auto& [id,count]:total) Output::send(STR("[BetterWorkbenchNative] UI_REQUIRED {}={}\n"),id,count);
        }
        return true;
    } catch(const std::exception& error) { preview_error(recipe,error); return false; }
}
void setting_materials(void* setting,BorrowedArray* out,bool single) {
    using PreviewFunction=void (*)(void*,BorrowedArray*,bool);
    const auto original=reinterpret_cast<PreviewFunction>(preview_trampoline);
    original(setting,out,single);
    if(!active_ready) return;
    uint64_t id{};
    try {
        using SelectionFunction=void* (*)(void*,uint64_t*);
        using WeakValidFunction=bool (*)(void*);
        using WeakGetFunction=void* (*)(void*);
        reinterpret_cast<SelectionFunction>(game_base()+0x32f4600)(setting,&id);
        if(!recipe_candidate(FName(static_cast<int64_t>(id)).ToString())) return;
        auto* weak=static_cast<std::byte*>(setting)+0x84;
        if(!reinterpret_cast<WeakValidFunction>(game_base()+0x36971b0)(weak)) return;
        auto* model=reinterpret_cast<WeakGetFunction>(game_base()+0x36954b0)(weak);
        // Original native method multiplies its per-unit result by +0x80 only
        // when single=false. Replace AFTER that multiplication with exact totals.
        if(ui_material_preview(setting,model,id,single?1:field<int32_t>(setting,0x80),out)) return;
    } catch(const std::exception& error) { preview_error(id,error); }
}
int32_t job_max(void* setting) {
    const auto original=reinterpret_cast<int32_t (*)(void*)>(max_trampoline);
    const auto native=original(setting);
    if(!active_ready) return native;
    try {
        using SelectionFunction=void* (*)(void*,uint64_t*);
        using WeakValidFunction=bool (*)(void*);
        using WeakGetFunction=void* (*)(void*);
        uint64_t id{}; reinterpret_cast<SelectionFunction>(game_base()+0x32f4600)(setting,&id);
        if(!recipe_candidate(FName(static_cast<int64_t>(id)).ToString())) return native;
        auto* weak=static_cast<std::byte*>(setting)+0x84;
        if(!reinterpret_cast<WeakValidFunction>(game_base()+0x36971b0)(weak)) return native;
        auto* model=reinterpret_cast<WeakGetFunction>(game_base()+0x36954b0)(weak); if(!model) return native;
        // The worker receives APlayerState::PlayerId (observed as 259), not
        // local-player index zero. Resolve the local controller with the game's
        // getter, then read only reflected, verified scalar identity fields.
        const auto planner=planner_request(model,local_player_id(setting),id);
        const auto root=FName(static_cast<int64_t>(id)).ToString();
        // Preserve the existing ceiling; increase it only for validated expansion.
        int32_t low=std::min(native,256),high=256;
        while(low<high) {
            const auto middle=low+(high-low+1)/2;
            if(planner.can_resolve(root,middle)) low=middle;
            else high=middle-1;
        }
        return std::max(native,low);
    } catch(const std::exception&) { return native; }
}
void install_active_jobs(uintptr_t base) {
    struct Hook { uintptr_t rva; uint64_t callback; uint64_t* original; };
    const std::array hooks{
        Hook{0x30ec350,reinterpret_cast<uint64_t>(&virtual_row),&row_trampoline},
        Hook{0x2fad860,reinterpret_cast<uint64_t>(&job_cost_map),&map_trampoline},
        Hook{0x3012d70,reinterpret_cast<uint64_t>(&job_complete),&complete_trampoline},
        Hook{0x300df10,reinterpret_cast<uint64_t>(&job_deficit),&deficit_trampoline},
        Hook{0x32f5ee0,reinterpret_cast<uint64_t>(&setting_materials),&preview_trampoline},
        Hook{0x300ced0,reinterpret_cast<uint64_t>(&dynamic_material_ids),&identities_trampoline},
        Hook{0x300d010,reinterpret_cast<uint64_t>(&dynamic_input_slots),&slots_trampoline},
        Hook{0x300e280,reinterpret_cast<uint64_t>(&dynamic_input_indices),&indices_trampoline},
        Hook{0x2fbc2f0,reinterpret_cast<uint64_t>(&job_transaction),&transaction_trampoline},
        Hook{0x32c6e10,reinterpret_cast<uint64_t>(&job_max),&max_trampoline}};
    for(const auto& guard:active_guards)
        if(std::memcmp(reinterpret_cast<void*>(base+guard.rva),guard.bytes.data(),guard.bytes.size())) {
            Output::send(STR("[BetterWorkbenchNative] active crafting disabled: native binary guard mismatch\n")); return;
        }
    auto* type=UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,STR("/Script/Pal.PalMapObjectConvertItemModel"));
    for(const auto& [name,offset]:std::array<std::pair<const wchar_t*,int>,4>{{{L"CurrentRecipeId",0x290},{L"RequestedProductNum",0x298},{L"RemainProductNum",0x29c},{L"ModelInstanceId",0xb0}}}) {
        auto* property=type?type->FindProperty(FName(name)):nullptr;
        if(!property || property->GetOffset_ForInternal()!=offset) { Output::send(STR("[BetterWorkbenchNative] active crafting disabled: model property mismatch\n")); return; }
    }
    for(const auto& hook:hooks) {
        auto detour=std::make_unique<PLH::x64Detour>(base+hook.rva,hook.callback,hook.original);
        if(!detour->hook()) {
            for(auto& prior:active_detours) prior->unHook(); active_detours.clear();
            Output::send(STR("[BetterWorkbenchNative] active crafting hook installation failed\n")); return;
        }
        active_detours.push_back(std::move(detour));
    }
    active_ready=true;
    Output::send(STR("[BetterWorkbenchNative] ACTIVE_CRAFTING enabled: same station, native costs/transfers/consumption/refunds, durable job definitions\n"));
    Output::send(STR("[BetterWorkbenchNative] UI_PREVIEW enabled: single-recipe cards and exact selected-quantity material arrays\n"));
    Output::send(STR("[BetterWorkbenchNative] RECIPE_SCOPE all native current-workbench recipes; no focused whitelist; uncached planner\n"));
    Output::send(STR("[BetterWorkbenchNative] DYNAMIC_INPUTS enabled for verified native containers: max=64 output_slot=5 stock_first=true\n"));
}

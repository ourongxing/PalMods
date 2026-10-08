#pragma once
// Included after find_job/virtual_row. All mutations use the audited native
// extension method on the worker thread. Output slot five is never an input.
uint64_t identities_trampoline{},slots_trampoline{},indices_trampoline{};
using IdentityFunction=void (*)(void*,BorrowedArray*);
using SlotArrayFunction=BorrowedArray* (*)(void*,BorrowedArray*);
void* dynamic_container(void* model) {
    using Module=void* (*)(void*); using Container=bool (*)(void*,void**);
    auto* module=reinterpret_cast<Module>(game_base()+0x2fff160)(model);
    void* result{};
    if(!module || !reinterpret_cast<Container>(game_base()+0x3083060)(module,&result) || !result)
        throw std::runtime_error("dynamic input container missing");
    auto* type=static_cast<UObject*>(result)->GetClassPrivate();
    if(!type || type->GetFullName()!=STR("Class /Script/Pal.PalItemContainer"))
        throw std::runtime_error("dynamic input container type mismatch");
    const auto vtable=field<uintptr_t>(result,0);
    if(field<uintptr_t>(reinterpret_cast<void*>(vtable),0x2b0)!=game_base()+0xdbe790
        || field<uintptr_t>(reinterpret_cast<void*>(vtable),0x2d8)!=game_base()+0x2fa6c00)
        throw std::runtime_error("dynamic input container implementation mismatch");
    const auto count=field<int32_t>(result,0x78);
    if(count<6 || count>65 || !field<void*>(result,0x70))
        throw std::runtime_error("dynamic input container shape mismatch");
    return result;
}
bool dynamic_container_supported(void* model) {
    try { dynamic_container(model); return true; } catch(const std::exception&) { return false; }
}
void* ensure_dynamic_capacity(void* model,std::size_t inputs) {
    auto* container=dynamic_container(model);
    const auto indices=better_workbench::input_indices(inputs);
    const auto required=std::max(6,indices.back()+1);
    const auto previous=field<int32_t>(container,0x78);
    if(previous<required) {
        using Authority=bool (*)(void*); using Extend=void (*)(void*,int32_t);
        if(!reinterpret_cast<Authority>(game_base()+0x3306f40)(model))
            throw std::runtime_error("dynamic input extension requires native authority");
        std::vector<void*> preserved;
        for(int32_t index=0;index<previous;++index)
            preserved.push_back(field<void*>(field<void*>(container,0x70),index*8));
        reinterpret_cast<Extend>(game_base()+0x2e8d210)(container,required);
        if(field<int32_t>(container,0x78)!=required) throw std::runtime_error("native input extension failed");
        for(int32_t index=0;index<previous;++index)
            if(preserved[index]!=field<void*>(field<void*>(container,0x70),index*8))
                throw std::runtime_error("native input extension changed existing slots");
        Output::send(STR("[BetterWorkbenchNative] INPUT_CAPACITY native_extension {} -> {} output_slot=5\n"),previous,required);
    }
    return container;
}
std::shared_ptr<ActiveJob> dynamic_model_job(void* model) {
    const auto id=pending_model==model && pending_job?name_bits(pending_job->alias.c_str()):field<uint64_t>(model,0x290);
    if(!is_job_name(id)) return {};
    auto job=find_job(id); job_index(job,model);
    return job->schedule.total.size()>5?job:nullptr;
}
template<class T> void append_native_array(BorrowedArray* out,const std::vector<T>& values) {
    if(!out || values.size()>65) throw std::runtime_error("dynamic array limit");
    validate_array(*out,4096);
    const auto count=out->count+static_cast<int32_t>(values.size());
    if(count>4096) throw std::runtime_error("dynamic array append limit");
    auto* memory=static_cast<std::byte*>(FMemory::Malloc(static_cast<std::size_t>(count)*sizeof(T),alignof(T)));
    if(!memory) throw std::bad_alloc();
    if(out->count) std::memcpy(memory,out->data,out->count*sizeof(T));
    std::memcpy(memory+out->count*sizeof(T),values.data(),values.size()*sizeof(T));
    if(out->data) FMemory::Free(const_cast<std::byte*>(out->data));
    *out={memory,count,count};
}
void dynamic_material_ids(void* row,BorrowedArray* out) {
    const auto marker=field<uint64_t>(row,0x24);
    if(!active_ready || !is_job_name(marker)) { reinterpret_cast<IdentityFunction>(identities_trampoline)(row,out); return; }
    try {
        auto job=find_job(marker); std::vector<uint64_t> ids;
        for(const auto& [name,count]:job->schedule.total) ids.push_back(name_bits(name.c_str()));
        const auto caller=reinterpret_cast<uintptr_t>(_ReturnAddress())-game_base();
        // Both audited callers interpret identity position as a physical slot.
        // Refunds and validation instead need the compact identity/input arrays.
        if(caller==0x3008fb3 || caller==0x300e349)
            ids=better_workbench::physical_identities(std::move(ids),name_bits(L"None"));
        append_native_array(out,ids);
    } catch(const std::exception&) {
        Output::send(STR("[BetterWorkbenchNative] dynamic material identities unavailable\n"));
    }
}
BorrowedArray* dynamic_input_slots(void* model,BorrowedArray* out) {
    if(!active_ready) return reinterpret_cast<SlotArrayFunction>(slots_trampoline)(model,out);
    // This native function CONSTRUCTS its return array. Its callers pass
    // uninitialized stack storage (e.g. 0x3023f4d), not an existing TArray.
    // Match the original zeroing before reading or freeing any output fields.
    *out={};
    try {
        auto job=dynamic_model_job(model);
        if(!job) return reinterpret_cast<SlotArrayFunction>(slots_trampoline)(model,out);
        auto* container=ensure_dynamic_capacity(model,job->schedule.total.size());
        using GetSlot=void* (*)(void*,int32_t);
        std::vector<void*> slots;
        for(auto index:better_workbench::input_indices(job->schedule.total.size())) {
            auto* slot=reinterpret_cast<GetSlot>(game_base()+0x2fa9650)(container,index);
            if(!slot) throw std::runtime_error("dynamic input slot missing");
            slots.push_back(slot);
        }
        append_native_array(out,slots); return out;
    } catch(const std::exception& error) {
        const std::string reason(error.what());
        Output::send(STR("[BetterWorkbenchNative] dynamic input slots unavailable: {}\n"),std::wstring(reason.begin(),reason.end())); return out;
    }
}
BorrowedArray* dynamic_input_indices(void* model,BorrowedArray* out) {
    if(!active_ready) return reinterpret_cast<SlotArrayFunction>(indices_trampoline)(model,out);
    // Same constructor ABI as the native input-slot return function.
    *out={};
    try {
        auto job=dynamic_model_job(model);
        if(!job) return reinterpret_cast<SlotArrayFunction>(indices_trampoline)(model,out);
        append_native_array(out,better_workbench::input_indices(job->schedule.total.size())); return out;
    } catch(const std::exception&) {
        Output::send(STR("[BetterWorkbenchNative] dynamic input indices unavailable\n")); return out;
    }
}

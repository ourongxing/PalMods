#pragma once
// Included inside the bridge namespace, after field() and game_base().
// Synchronous, bounded observation of the workbench actually opened by the
// player. No capacity writes and no UObject or Lua state retained.
std::atomic<bool> storage_probe_complete{};
std::atomic<unsigned> storage_probe_failures{};
void storage_probe(void* model) {
    if(storage_probe_complete.load() || storage_probe_failures.load()>=4) return;
    try {
        using ModuleFunction=void* (*)(void*);
        using ContainerFunction=bool (*)(void*,void**);
        auto* module=static_cast<UObject*>(reinterpret_cast<ModuleFunction>(game_base()+0x2fff160)(model));
        if(!module) throw std::runtime_error("workbench item-container module unavailable");
        void* pointer{};
        if(!reinterpret_cast<ContainerFunction>(game_base()+0x3083060)(module,&pointer) || !pointer)
            throw std::runtime_error("native input-container getter unavailable");
        auto* container=static_cast<UObject*>(pointer);
        auto* type=container->GetClassPrivate();
        if(!type) throw std::runtime_error("container class unavailable");
        const auto vtable=field<uintptr_t>(container,0);
        const auto count_function=field<uintptr_t>(reinterpret_cast<void*>(vtable),0x2b0);
        const auto extend_function=field<uintptr_t>(reinterpret_cast<void*>(vtable),0x2d8);
        const auto slot_count=field<int32_t>(container,0x78);
        if(slot_count<5 || slot_count>4096) throw std::runtime_error("input container slot-count mismatch");
        OwnedNativeArray input_slots;
        using InputFunction=BorrowedArray* (*)(void*,BorrowedArray*);
        reinterpret_cast<InputFunction>(game_base()+0x300d010)(model,&input_slots.value);
        validate_array(input_slots.value,5);
        if(input_slots.value.count!=5) throw std::runtime_error("native input enumeration mismatch");
        const auto slot_array=field<void*>(container,0x70);
        if(!slot_array) throw std::runtime_error("container slot storage unavailable");
        for(int32_t index=0;index<5;++index) {
            const auto actual=field<void*>(const_cast<std::byte*>(input_slots.value.data),index*8);
            if(actual!=field<void*>(slot_array,index*8)) throw std::runtime_error("input slot mapping mismatch");
        }
        Output::send(STR("[BetterWorkbenchNative] STORAGE_PROBE class={} slots={} input_slots={} writes=false\n"),
            type->GetFullName(),slot_count,input_slots.value.count);
        const auto count_rva=count_function>=game_base() && count_function<game_base()+expected_image_size ? count_function-game_base():0;
        const auto extend_rva=extend_function>=game_base() && extend_function<game_base()+expected_image_size ? extend_function-game_base():0;
        Output::send(STR("[BetterWorkbenchNative] STORAGE_VTABLE count_rva={} extend_rva={} input_mapping=0,1,2,3,4\n"),count_rva,extend_rva);
        // Log reflected field shapes, not field values or save/account identity.
        for(auto* object:{module,container}) {
            unsigned visited=0;
            for(TFieldIterator<FProperty> it(object->GetClassPrivate());it && visited<64;++it,++visited) {
                auto* property=*it;
                Output::send(STR("[BetterWorkbenchNative] STORAGE_PROPERTY owner={} name={} offset={} size={}\n"),
                    object->GetClassPrivate()->GetFullName(),property->GetFName().ToString(),
                    property->GetOffset_ForInternal(),property->GetElementSize());
            }
        }
        storage_probe_complete.store(true);
    } catch(const std::exception& error) {
        storage_probe_failures.fetch_add(1);
        const std::string message(error.what());
        Output::send(STR("[BetterWorkbenchNative] STORAGE_PROBE_REJECTED {} writes=false\n"),std::wstring(message.begin(),message.end()));
    }
}

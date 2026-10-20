#pragma once
#include "job_wire.hpp"
std::string guid_text(const std::byte* data) {
    std::string result; constexpr char hex[]="0123456789abcdef";
    for (int word=0;word<4;++word) {
        uint32_t value{}; std::memcpy(&value,data+word*4,4);
        for (int shift=28;shift>=0;shift-=4) result+=hex[(value>>shift)&15];
    }
    return result;
}

int poll_job(const LuaMadeSimple::Lua& lua) {
    std::lock_guard lock(jobs_mutex);
    if (network_jobs.empty()) { lua.set_nil(); return 1; }
    const auto alias=network_jobs.front(); network_jobs.pop_front();
    lua.set_string(utf8(alias)); return 1;
}
int export_job(const LuaMadeSimple::Lua& lua) {
    try {
        if (!active_ready || !IsInGameThreadRaw()) throw std::runtime_error("native scope unavailable");
        const auto input=lua.get_string(1);
        if (input.size()>128) throw std::runtime_error("alias size limit");
        const std::wstring alias(input.begin(),input.end());
        const auto job=find_job(name_bits(alias.c_str()));
        const auto bytes=better_workbench::encode_wire(*job);
        lua.set_string(bytes.data(),bytes.size());
        lua.set_string(guid_text(reinterpret_cast<const std::byte*>(job->station.data())));
        lua.set_string(utf8(job->root)); return 3;
    } catch (const std::exception& error) { lua.set_nil(); lua.set_string(error.what()); return 2; }
}
int import_job(const LuaMadeSimple::Lua& lua) {
    try {
        if (!active_ready || !IsInGameThreadRaw()) throw std::runtime_error("native scope unavailable");
        const auto alias=lua.get_string(1), bytes=lua.get_string(2);
        if (alias.size()>128 || bytes.size()>262144) throw std::runtime_error("job size limit");
        auto job=std::make_shared<ActiveJob>();
        static_cast<better_workbench::Journal&>(*job)=better_workbench::decode_wire({bytes.begin(),bytes.end()},{alias.begin(),alias.end()});
        std::lock_guard lock(jobs_mutex);
        if (auto existing=jobs.find(job->alias);existing!=jobs.end()) {
            if (better_workbench::encode_wire(*existing->second)!=better_workbench::encode_wire(*job))
                throw std::runtime_error("immutable job mismatch");
        } else {
            if (jobs.size()>=4096) throw std::runtime_error("job cache limit");
            jobs[job->alias]=job;
        }
        lua.set_bool(true); return 1;
    } catch (const std::exception& error) { lua.set_bool(false); lua.set_string(error.what()); return 2; }
}
int player_scope(const LuaMadeSimple::Lua& lua) {
    try {
        if (!active_ready || !IsInGameThreadRaw()) throw std::runtime_error("native scope unavailable");
        auto* model=lua.get_userdata<LuaType::UObject>().get_remote_cpp_object();
        auto* controller=lua.get_userdata<LuaType::UObject>().get_remote_cpp_object();
        const auto recipe=lua.get_string(1);
        auto* model_type=UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,STR("/Script/Pal.PalMapObjectConvertItemModel"));
        auto* player_type=UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,STR("/Script/Pal.PalPlayerController"));
        if (!model || !controller || !model_type || !player_type || !model->IsA(model_type) || !controller->IsA(player_type))
            throw std::runtime_error("invalid workbench or controller");
        auto* state_property=controller->GetClassPrivate()->FindProperty(FName(STR("PlayerState")));
        if (!state_property || !state_property->IsA<FObjectProperty>() || state_property->GetOffset_ForInternal()!=0x298)
            throw std::runtime_error("player-state layout mismatch");
        auto* state=field<UObject*>(controller,0x298);
        auto* id_property=state ? state->GetClassPrivate()->FindProperty(FName(STR("PlayerId"))) : nullptr;
        if (!id_property || !id_property->IsA<FIntProperty>() || id_property->GetOffset_ForInternal()!=0x294)
            throw std::runtime_error("player ID unavailable");
        const std::wstring root(recipe.begin(),recipe.end());
        const auto ids=station_recipes(model);
        if (!recipe_candidate(root) || std::find(ids.begin(),ids.end(),root)==ids.end())
            throw std::runtime_error("recipe outside workbench");
        std::array<uint8_t,16> uid{};
        using Uid=void* (*)(void*,void*,int32_t);
        reinterpret_cast<Uid>(game_base()+0x32f34f0)(uid.data(),model,field<int32_t>(state,0x294));
        if (std::all_of(uid.begin(),uid.end(),[](auto b){return b==0;})) throw std::runtime_error("player unavailable");
        using Technology=void* (*)(void*,void*);
        auto* technology=reinterpret_cast<Technology>(game_base()+0x32f7e50)(model,uid.data());
        const auto bits=name_bits(root.c_str());
        using Policy=bool (*)(void*,const uint64_t*);
        if (!technology || reinterpret_cast<Policy>(game_base()+0x31cc070)(technology,&bits)
            || !reinterpret_cast<Policy>(game_base()+0x326aa30)(technology,&bits)) throw std::runtime_error("recipe locked");
        OwnedNativeArray scope;
        using Collect=void (*)(void*,void*,BorrowedArray*,uint8_t);
        reinterpret_cast<Collect>(game_base()+0x2fa0d00)(model,uid.data(),&scope.value,2);
        validate_array(scope.value,4096);
        // The audited count function walks GUIDs at stride 16, not UObjects.
        std::string result; constexpr char hex[]="0123456789abcdef";
        for (int32_t i=0;i<scope.value.count;++i) {
            for (int32_t word=0;word<4;++word) {
                uint32_t value{}; std::memcpy(&value,scope.value.data+i*16+word*4,4);
                for (int shift=28;shift>=0;shift-=4) result+=hex[(value>>shift)&15];
            }
            result+=';';
        }
        const auto row=read_recipe_metadata(model,root.c_str());
        const auto stock=read_scoped_stock(model,&scope.value,{row.output});
        int64_t available{};
        for (const auto& material:stock) if (material.name==row.output) available+=material.quantity;
        lua.set_string(result); lua.set_integer(available); return 2;
    } catch (const std::exception& error) { lua.set_nil(); lua.set_string(error.what()); return 2; }
}

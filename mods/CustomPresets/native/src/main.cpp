#include <algorithm>
#include <cstdint>
#include <set>
#include <vector>
#include <cstring>
#include "PreviewImage.hpp"
#include "PreviewArguments.hpp"
#include "PreviewPixels.hpp"
#include <stdexcept>
#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/Output.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <LuaType/LuaUObject.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <Unreal/Core/HAL/UnrealMemory.hpp>

using namespace RC;
using namespace RC::Unreal;
namespace {
int refresh(const LuaMadeSimple::Lua& lua) {
    try {
        auto* object = lua.get_userdata<LuaType::UObject>().get_remote_cpp_object();
        auto* expected = UObjectGlobals::StaticFindObject<UClass*>(nullptr, nullptr,
            STR("/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSettings.WBP_Title_WorldSettings_C"));
        if (!object || !expected || !object->IsA(expected)) throw std::runtime_error("Invalid world settings editor");
        auto* function = object->GetFunctionByNameInChain(STR("ApplyWorldSettingToUI"));
        auto* source = CastField<FStructProperty>(expected->FindProperty(FName(STR("EditedWorldSetting"))));
        auto* parameter = function ? CastField<FStructProperty>(function->FindProperty(FName(STR("WorldSetting")))) : nullptr;
        if (!source || !parameter || function->GetNumParms() != 1 || source->GetStruct() != parameter->GetStruct()
            || !parameter->HasAnyPropertyFlags(CPF_Parm) || parameter->HasAnyPropertyFlags(CPF_OutParm | CPF_ReturnParm)
            || parameter->GetArrayDim() != 1 || source->GetArrayDim() != 1
            || source->GetElementSize() != parameter->GetElementSize())
            throw std::runtime_error("World settings function signature changed");
        const auto size = static_cast<std::size_t>(function->GetParmsSize());
        const auto offset = static_cast<std::size_t>(parameter->GetOffset_Internal());
        const auto field_size = static_cast<std::size_t>(parameter->GetElementSize());
        if (size == 0 || size > 1024 * 1024 || offset > size || field_size > size - offset)
            throw std::runtime_error("Invalid world settings parameter bounds");
        const auto alignment = std::max<std::uint32_t>(16, parameter->GetMinAlignment());
        void* memory = FMemory::Malloc(size, alignment);
        if (!memory) throw std::runtime_error("World settings allocation failed");
        struct Allocation { void* data; ~Allocation() { FMemory::Free(data); } } allocation{memory};
        auto* destination = static_cast<std::uint8_t*>(memory) + offset;
        parameter->InitializeValue(destination);
        struct Value { FProperty* property; void* data; ~Value() { property->DestroyValue(data); } } value{parameter, destination};
        // Deep-copy FString/array members using their reflected property. Never
        // route this 536-byte argument through UE4SS Lua's fixed 512-byte buffer.
        parameter->CopyCompleteValue(destination, source->ContainerPtrToValuePtr<void>(object));
        Output::send(STR("[CustomPresetsNative] refresh parameter_bytes={} allocated_bytes={}\n"), field_size, size);
        object->ProcessEvent(function, memory);
        lua.set_bool(true);
        return 1;
    } catch (const std::exception& error) {
        lua.throw_error(error.what());
        return 0;
    }
}

// Allocate reflected parameter blocks for character functions too: current
// appearance structures are larger than UE4SS Lua's fixed call buffer.
struct Parameters {
    UFunction* function;
    void* memory;
    std::vector<FProperty*> initialized;
    explicit Parameters(UFunction* fn) : function(fn), memory(nullptr) {
        if (!fn || fn->GetParmsSize() == 0 || fn->GetParmsSize() > 1024 * 1024)
            throw std::runtime_error("Invalid character parameter block");
        memory = FMemory::Malloc(fn->GetParmsSize(), 16);
        if (!memory) throw std::runtime_error("Character allocation failed");
        std::memset(memory, 0, fn->GetParmsSize());
    }
    Parameters(const Parameters&) = delete;
    ~Parameters() {
        for (auto* field : initialized) field->DestroyValue(field->ContainerPtrToValuePtr<void>(memory));
        FMemory::Free(memory);
    }
    template<class T> T* field(const wchar_t* name) {
        auto* property = CastField<T>(function->FindProperty(FName(name)));
        const auto size = static_cast<std::size_t>(function->GetParmsSize());
        const auto offset = property ? static_cast<std::size_t>(property->GetOffset_Internal()) : size;
        if (!property || !property->HasAnyPropertyFlags(CPF_Parm) || property->GetArrayDim() != 1
            || offset > size || static_cast<std::size_t>(property->GetElementSize()) > size - offset)
            throw std::runtime_error("Character function signature changed");
        property->InitializeValue(property->ContainerPtrToValuePtr<void>(memory));
        initialized.push_back(property);
        return property;
    }
};
UObject* object_field(UObject* object, UClass* owner, const wchar_t* name) {
    auto* property = CastField<FObjectProperty>(owner->FindProperty(FName(name)));
    auto* value = property ? property->GetObjectPropertyValue(property->ContainerPtrToValuePtr<void>(object)) : nullptr;
    if (!value) throw std::runtime_error("Character editor child unavailable");
    return value;
}
int refresh_character(const LuaMadeSimple::Lua& lua) {
    try {
        auto* editor = lua.get_userdata<LuaType::UObject>().get_remote_cpp_object();
        auto* expected = UObjectGlobals::StaticFindObject<UClass*>(nullptr, nullptr,
            STR("/Game/Pal/Blueprint/UI/CharacterMake/WBP_CharacterMake.WBP_CharacterMake_C"));
        if (!editor || !expected || !editor->IsA(expected)) throw std::runtime_error("Invalid character editor");
        auto* source = CastField<FStructProperty>(expected->FindProperty(FName(STR("MakeInfo"))));
        auto* limit = CastField<FDoubleProperty>(expected->FindProperty(FName(STR("SVMax"))));
        if (!source || !limit) throw std::runtime_error("Character appearance fields changed");
        auto* data = object_field(editor, expected, STR("CharacterMakeData"));
        auto* controls = object_field(editor, expected, STR("WBP_CharaCre"));
        auto* conversion = data->GetFunctionByNameInChain(STR("ConvertMakeInfo_HSVToRGB"));
        if (!conversion || conversion->GetNumParms() != 3) throw std::runtime_error("Character color converter changed");
        Parameters rgb(conversion);
        auto* input = rgb.field<FStructProperty>(STR("MakeInfo"));
        auto* output = rgb.field<FStructProperty>(STR("ConvertedMakeInfo"));
        auto* sv = rgb.field<FDoubleProperty>(STR("SVLimit"));
        if (input->GetStruct() != source->GetStruct() || output->GetStruct() != source->GetStruct()
            || input->HasAnyPropertyFlags(CPF_OutParm | CPF_ReturnParm) || !output->HasAnyPropertyFlags(CPF_OutParm))
            throw std::runtime_error("Character appearance types changed");
        input->CopyCompleteValue(input->ContainerPtrToValuePtr<void>(rgb.memory), source->ContainerPtrToValuePtr<void>(editor));
        sv->CopyCompleteValue(sv->ContainerPtrToValuePtr<void>(rgb.memory), limit->ContainerPtrToValuePtr<void>(editor));
        data->ProcessEvent(conversion, rgb.memory);
        auto* apply = controls->GetFunctionByNameInChain(STR("ApplyMakeInfo"));
        if (!apply || apply->GetNumParms() != 1) throw std::runtime_error("Character controls signature changed");
        Parameters arguments(apply);
        auto* value = arguments.field<FStructProperty>(STR("MakeInfo"));
        if (value->GetStruct() != source->GetStruct() || value->HasAnyPropertyFlags(CPF_OutParm | CPF_ReturnParm))
            throw std::runtime_error("Character controls type changed");
        value->CopyCompleteValue(value->ContainerPtrToValuePtr<void>(arguments.memory), output->ContainerPtrToValuePtr<void>(rgb.memory));
        controls->ProcessEvent(apply, arguments.memory);
        lua.set_bool(true);
        return 1;
    } catch (const std::exception& error) {
        lua.throw_error(error.what());
        return 0;
    }
}

int capture_preview(const LuaMadeSimple::Lua& lua) {
    try {
        UObject* editor{};
        const auto path = CustomPresetsPreview::read_arguments(lua, [&] {
            editor = lua.get_userdata<LuaType::UObject>(1).get_remote_cpp_object();
        });
        const auto filename = CustomPresetsPreview::wide_path(path);
        auto* expected = UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,
            STR("/Game/Pal/Blueprint/UI/CharacterMake/WBP_CharacterMake.WBP_CharacterMake_C"));
        auto* rendererClass = UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,
            STR("/Game/Pal/Blueprint/UI/SceneCaptureWidget/WBP_PalPlayerInframeRender.WBP_PalPlayerInframeRender_C"));
        auto* textureClass = UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,STR("/Script/Engine.TextureRenderTarget2D"));
        if (!editor || !expected || !editor->IsA(expected) || !rendererClass || !textureClass)
            throw std::runtime_error("Character preview unavailable");
        auto* renderer = object_field(editor,expected,STR("WBP_PalPlayerInframeRender"));
        if (!renderer->IsA(rendererClass)) throw std::runtime_error("Character preview class changed");
        auto* target = object_field(renderer,rendererClass,STR("RenderTarget"));
        if (!target->IsA(textureClass)) throw std::runtime_error("Character preview texture changed");
        auto* sizeX = CastField<FIntProperty>(textureClass->FindProperty(FName(STR("SizeX"))));
        auto* sizeY = CastField<FIntProperty>(textureClass->FindProperty(FName(STR("SizeY"))));
        if (!sizeX || !sizeY) throw std::runtime_error("Preview size fields unavailable");
        const auto width = sizeX->GetPropertyValueInContainer(target);
        const auto height = sizeY->GetPropertyValueInContainer(target);
        if (width <= 0 || height <= 0 || width > 4096 || height > 4096) throw std::runtime_error("Invalid preview dimensions");
        auto* rendering = UObjectGlobals::StaticFindObject<UObject*>(nullptr,nullptr,STR("/Script/Engine.Default__KismetRenderingLibrary"));
        auto* function = rendering ? rendering->GetFunctionByNameInChain(STR("ReadRenderTargetRaw")) : nullptr;
        if (!function || function->GetNumParms()!=5) throw std::runtime_error("Preview readback signature changed");
        Parameters arguments(function);
        auto* context = arguments.field<FObjectProperty>(STR("WorldContextObject"));
        auto* texture = arguments.field<FObjectProperty>(STR("TextureRenderTarget"));
        auto* output = arguments.field<FArrayProperty>(STR("OutLinearSamples"));
        auto* normalize = arguments.field<FBoolProperty>(STR("bNormalize"));
        auto* result = arguments.field<FBoolProperty>(STR("ReturnValue"));
        if (!output->HasAnyPropertyFlags(CPF_OutParm) || output->GetInner()->GetElementSize()!=16)
            throw std::runtime_error("Preview pixel format changed");
        context->SetObjectPropertyValue(context->ContainerPtrToValuePtr<void>(arguments.memory),editor);
        texture->SetObjectPropertyValue(texture->ContainerPtrToValuePtr<void>(arguments.memory),target);
        normalize->SetPropertyValue(normalize->ContainerPtrToValuePtr<void>(arguments.memory),false);
        rendering->ProcessEvent(function,arguments.memory);
        if (!result->GetPropertyValue(result->ContainerPtrToValuePtr<void>(arguments.memory)))
            throw std::runtime_error("Preview readback failed");
        FScriptArrayHelper samples(output,output->ContainerPtrToValuePtr<void>(arguments.memory));
        if (samples.Num()!=width*height) throw std::runtime_error("Incomplete preview pixels");
        auto* formatProperty=CastField<FByteProperty>(textureClass->FindProperty(FName(STR("RenderTargetFormat"))));
        if (!formatProperty) throw std::runtime_error("Preview render format unavailable");
        const auto format=formatProperty->GetPropertyValueInContainer(target);
        if (format!=2 && format!=3 && format!=6) throw std::runtime_error("Unsupported portrait render format");
        auto portrait=CustomPresetsPreview::compose_portrait(width,height,samples.GetRawPtr(0),format==2||format==3,format==3);
        CustomPresetsPreview::write_preview(filename,CustomPresetsPreview::portrait_width,CustomPresetsPreview::portrait_height,reinterpret_cast<BYTE*>(portrait.data()));
        lua.set_bool(true);
        return 1;
    } catch (const std::exception& error) { lua.throw_error(error.what()); return 0; }
}
class Bridge final : public CppUserModBase {
public:
    Bridge() {
        ModName = STR("Custom Presets 自定义预设"); ModVersion = STR("0.4.6");
        ModAuthors = STR("ourongxing");
        ModDescription = STR("Sized world and character preset refresh bridge");
    }
    void on_lua_start(StringViewType name, LuaMadeSimple::Lua& lua,
                      LuaMadeSimple::Lua& main, LuaMadeSimple::Lua& async,
                      LuaMadeSimple::Lua* hook) override {
        if (name != STR("CustomPresets")) return;
        std::set<LuaMadeSimple::Lua*> instances{&lua, &main, &async};
        if (hook) instances.insert(hook);
        for (auto* instance : instances) {
            instance->register_function("CustomPresetsNativeRefresh", &refresh);
            instance->register_function("CustomPresetsNativeCharacterRefresh", &refresh_character);
            instance->register_function("CustomPresetsNativeCapturePreview", &capture_preview);
        }
        Output::send(STR("[CustomPresetsNative] sized refresh API registered\n"));
    }
};
}
extern "C" __declspec(dllexport) CppUserModBase* start_mod() { return new Bridge(); }
extern "C" __declspec(dllexport) void uninstall_mod(CppUserModBase* mod) { delete mod; }

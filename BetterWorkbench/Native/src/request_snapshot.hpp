#pragma once
#include <deque>
#include <map>
#include <mutex>
#include <set>
#include <Unreal/Core/HAL/UnrealMemory.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>

// Included inside dllmain.cpp's anonymous namespace. All Unreal allocations
// stay inside the synchronous game callback. Only owned strings/numbers reach
// Lua; neither a UObject nor a borrowed array is kept by the queue.
struct RecipeSnapshot {
    std::wstring id, output;
    int32_t output_amount{};
    float work{};
    std::vector<Material> raw, effective;
};
struct RequestSnapshot {
    std::wstring recipe;
    int32_t batches{};
    std::vector<std::wstring> station;
    std::vector<RecipeSnapshot> recipes;
    std::vector<Material> stock, batch;
};
std::mutex snapshot_mutex;
std::deque<RequestSnapshot> snapshot_queue;
std::atomic<unsigned> snapshot_samples{};
std::atomic<bool> snapshot_disabled{};
std::atomic<bool> snapshot_reads_ready{};
struct RequestContext { void* model; uint64_t recipe; int32_t batches; };
thread_local const RequestContext* request_context{};
uint64_t worker_trampoline{};
std::unique_ptr<PLH::x64Detour> worker_detour;
using WorkerFunction = void (*)(void*, int32_t, uint64_t, int32_t, bool, bool);

std::string utf8(const std::wstring& input) {
    if (input.empty()) return {};
    const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input.data(),
        static_cast<int>(input.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0) throw std::runtime_error("invalid native name encoding");
    std::string output(size, '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, input.data(),
        static_cast<int>(input.size()), output.data(), size, nullptr, nullptr);
    return output;
}
uint64_t name_bits(const wchar_t* text) {
    static_assert(sizeof(FName) == 8);
    const FName name(text);
    uint64_t bits{}; std::memcpy(&bits, &name, 8); return bits;
}
void validate_array(const BorrowedArray& array, int32_t limit) {
    if (array.count < 0 || array.count > limit || array.capacity < array.count
        || array.capacity > 1000000 || (array.count && !array.data))
        throw std::runtime_error("native array shape mismatch");
}
std::vector<Material> copy_materials(const BorrowedArray& array) {
    validate_array(array, 64);
    std::vector<Material> result;
    std::set<std::wstring> seen;
    for (int32_t index = 0; index < array.count; ++index) {
        uint64_t bits{}; int32_t count{};
        std::memcpy(&bits, array.data + index * 12, 8);
        std::memcpy(&count, array.data + index * 12 + 8, 4);
        auto name = FName(static_cast<int64_t>(bits)).ToString();
        if (name.empty() || name == L"None" || count < 0 || count > 1000000000
            || !seen.insert(name).second) throw std::runtime_error("invalid native material");
        result.push_back({std::move(name), count});
    }
    return result;
}
// Own a newly created result, never an array supplied by the game's caller.
struct OwnedNativeArray {
    BorrowedArray value{};
    ~OwnedNativeArray() { if (value.data) FMemory::Free(const_cast<std::byte*>(value.data)); }
};
std::vector<std::wstring> station_recipes(void* model) {
    auto* object = static_cast<UObject*>(model);
    auto* function = object->GetFunctionByNameInChain(STR("GetRecipes"));
    auto* result = function ? function->GetReturnProperty() : nullptr;
    if (!result || !result->IsA<FArrayProperty>() || result->GetOffset_ForInternal() != 0
        || result->GetElementSize() != 16 || function->GetPropertiesSize() != 16)
        throw std::runtime_error("station recipe return layout mismatch");
    auto* inner = static_cast<FArrayProperty*>(result)->GetInner();
    if (!inner || !inner->IsA<FNameProperty>() || inner->GetElementSize() != 8)
        throw std::runtime_error("station recipe element layout mismatch");
    OwnedNativeArray returned;
    object->ProcessEvent(function, &returned.value);
    validate_array(returned.value, 4096);
    std::vector<std::wstring> ids;
    std::set<std::wstring> seen;
    for (int32_t index = 0; index < returned.value.count; ++index) {
        uint64_t bits{}; std::memcpy(&bits, returned.value.data + index * 8, 8);
        auto name = FName(static_cast<int64_t>(bits)).ToString();
        if (name.empty() || name == L"None" || !seen.insert(name).second)
            throw std::runtime_error("invalid station recipe identity");
        ids.push_back(std::move(name));
    }
    return ids;
}
RecipeSnapshot read_recipe_metadata(void* model, const wchar_t* id) {
    const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    using DataFunction = void* (*)(void*);
    using RowFunction = const std::byte* (*)(void*, uint64_t);
    auto* table = reinterpret_cast<DataFunction>(base + 0x30f0fb0)(model);
    auto* row = table ? reinterpret_cast<RowFunction>(base + 0x30ec350)(table, name_bits(id)) : nullptr;
    if (!row) throw std::runtime_error("recipe row unavailable");
    RecipeSnapshot result; result.id = id;
    uint64_t product{}; std::memcpy(&product, row + 8, 8);
    result.output = FName(static_cast<int64_t>(product)).ToString();
    std::memcpy(&result.output_amount, row + 0x10, 4);
    std::memcpy(&result.work, row + 0x14, 4);
    if (result.output.empty() || result.output == L"None" || result.output_amount <= 0
        || result.output_amount > 1000000000 || !std::isfinite(result.work) || result.work < 0)
        throw std::runtime_error("invalid native recipe metadata");
    for (std::size_t slot = 0; slot < 5; ++slot) {
        uint64_t item{}; int32_t count{};
        std::memcpy(&item, row + better_workbench::observed_layout.names[slot], 8);
        std::memcpy(&count, row + better_workbench::observed_layout.counts[slot], 4);
        if (count < 0 || count > 1000000000) throw std::runtime_error("invalid raw recipe amount");
        auto name = FName(static_cast<int64_t>(item)).ToString();
        if (count > 0 && name != L"None") result.raw.push_back({std::move(name), count});
    }
    return result;
}
std::vector<Material> read_effective_costs(void* model, const wchar_t* id) {
    OwnedNativeArray costs;
    // Same world AND owner used by the verified server-worker call site.
    reinterpret_cast<DemandFunction>(trampoline)(model, model, name_bits(id), &costs.value);
    return copy_materials(costs.value);
}
RecipeSnapshot read_recipe(void* model, const wchar_t* id) {
    auto result = read_recipe_metadata(model,id);
    result.effective = read_effective_costs(model,id);
    return result;
}
std::vector<Material> read_scoped_stock(void* model, BorrowedArray* containers,
                                      const std::vector<std::wstring>& items) {
    if (!containers || items.empty() || items.size() > 64) throw std::runtime_error("invalid stock query");
    validate_array(*containers, 4096);
    // The original consumes this allocation; release ownership BEFORE entering
    // it. Never allow it to free a vector, CRT allocation, or the caller's names.
    BorrowedArray consumed{};
    auto* allocation = static_cast<std::byte*>(FMemory::Malloc(items.size() * 8, 8));
    if (!allocation) throw std::bad_alloc();
    try {
        for (std::size_t index = 0; index < items.size(); ++index) {
            const auto bits = name_bits(items[index].c_str());
            std::memcpy(allocation + index * 8, &bits, 8);
        }
    } catch (...) { FMemory::Free(allocation); throw; }
    consumed = {allocation, static_cast<int32_t>(items.size()), static_cast<int32_t>(items.size())};
    OwnedNativeArray counts;
    reinterpret_cast<CountsFunction>(counts_trampoline)(model, containers, &consumed, &counts.value);
    auto result = copy_materials(counts.value);
    // Audited native implementation (0x2fa0020) inserts a result row only
    // after finding a nonempty matching slot in the complete supplied scope.
    // Therefore an absent REQUESTED name is exactly zero for THIS query,
    // unlike missing rows from a partial player/base diagnostic sample.
    std::set<std::wstring> returned;
    const std::set<std::wstring> requested(items.begin(), items.end());
    for (const auto& value : result) {
        if (!requested.contains(value.name)) throw std::runtime_error("unexpected stock query item");
        returned.insert(value.name);
    }
    for (const auto& item : items)
        if (!returned.contains(item)) result.push_back({item, 0});
    return result;
}
void capture_request(void* model, BorrowedArray* containers, const std::vector<Material>& batch) {
    if (!snapshot_reads_ready || snapshot_disabled.load() || snapshot_samples.load() >= 24
        || !request_context || request_context->model != model || request_context->batches < 1
        || request_context->batches > 256) return;
    const auto root = FName(static_cast<int64_t>(request_context->recipe)).ToString();
    if (root != L"Bio_Battery" && root != L"CarbonFiber" && root != L"CarbonFiber2") return;
    try {
        RequestSnapshot packet; packet.recipe = root; packet.batches = request_context->batches;
        packet.batch = batch; packet.station = station_recipes(model);
        const std::set<std::wstring> allowed(packet.station.begin(), packet.station.end());
        std::set<std::wstring> items;
        for (const auto* id : {L"Bio_Battery", L"CarbonFiber", L"CarbonFiber2", L"Charcoal"}) {
            // Charcoal's row documents the forbidden furnace expansion. It is
            // metadata, never permission to use a recipe outside this station.
            if (!allowed.contains(id) && std::wstring_view(id) != L"Charcoal") continue;
            auto recipe = read_recipe(model, id);
            for (const auto& item : recipe.effective) items.insert(item.name);
            packet.recipes.push_back(std::move(recipe));
        }
        packet.stock = read_scoped_stock(model, containers, {items.begin(), items.end()});
        std::lock_guard lock(snapshot_mutex);
        if (snapshot_queue.size() == 8) snapshot_queue.pop_front();
        snapshot_queue.push_back(std::move(packet));
        ++snapshot_samples;
        Output::send(STR("[BetterWorkbenchNative] OWNED_REQUEST recipe={} batches={} native-costs/native-scope captured; writes inactive\n"),
            root, request_context->batches);
    } catch (const std::exception& error) {
        snapshot_disabled.store(true);
        const std::string message(error.what());
        Output::send(STR("[BetterWorkbenchNative] request snapshot disabled: {}\n"),
            std::wstring(message.begin(), message.end()));
    }
}
void worker(void* model, int32_t player, uint64_t recipe, int32_t batches, bool option, bool cancel) {
    const RequestContext context{model, recipe, batches};
    const auto* prior = request_context;
    request_context = &context;
    struct Reset { const RequestContext* prior; ~Reset() { request_context = prior; } } reset{prior};
    active_worker(model, player, recipe, batches, option, cancel);
}
void push_materials(const LuaMadeSimple::Lua& lua, const std::vector<Material>& values) {
    auto table = lua.prepare_new_table(0, static_cast<int32_t>(values.size()));
    std::map<std::string, int64_t> merged;
    for (const auto& value : values) merged[utf8(value.name)] += value.quantity;
    for (const auto& [name, amount] : merged) table.add_pair(name.c_str(), static_cast<long long>(amount));
    table.make_local();
}
int take_snapshot(const LuaMadeSimple::Lua& lua) {
    std::optional<RequestSnapshot> packet;
    { std::lock_guard lock(snapshot_mutex);
      if (!snapshot_queue.empty()) { packet.emplace(std::move(snapshot_queue.front())); snapshot_queue.pop_front(); } }
    if (!packet) { lua.set_nil(); return 1; }
    auto result = lua.prepare_new_table(0, 9);
    result.add_pair("Schema", 1);
    result.add_pair("RecipeId", utf8(packet->recipe).c_str());
    result.add_pair("Batches", packet->batches);
    result.add_pair("ReadOnly", true);
    result.add_pair("NativeCosts", true);
    result.add_pair("ScopeComplete", true);
    result.add_pair("EligibilityVerified", false);
    result.add_key("StationRecipes");
    auto station = lua.prepare_new_table(0, static_cast<int32_t>(packet->station.size()));
    for (const auto& name : packet->station) station.add_pair(utf8(name).c_str(), true);
    station.make_local(); result.fuse_pair();
    result.add_key("Inventory"); push_materials(lua, packet->stock); result.fuse_pair();
    result.add_key("BatchDemand"); push_materials(lua, packet->batch); result.fuse_pair();
    result.add_key("Recipes"); auto recipes = lua.prepare_new_table(0, 4);
    for (const auto& recipe : packet->recipes) {
        recipes.add_key(utf8(recipe.id).c_str()); auto row = lua.prepare_new_table(0, 5);
        row.add_pair("OutputItem", utf8(recipe.output).c_str());
        row.add_pair("OutputAmount", recipe.output_amount);
        row.add_pair("WorkAmount", recipe.work);
        row.add_key("Materials"); push_materials(lua, recipe.raw); row.fuse_pair();
        row.add_key("EffectiveMaterials"); push_materials(lua, recipe.effective); row.fuse_pair();
        row.make_local(); recipes.fuse_pair();
    }
    recipes.make_local(); result.fuse_pair(); result.make_local(); return 1;
}

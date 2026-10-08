#pragma once
#include <algorithm>
#include <cstdint>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace better_workbench {
using Amounts = std::map<std::wstring, int32_t>;
struct NativeRecipe { std::wstring id, output; int32_t output_amount; Amounts costs; };
struct Schedule { std::vector<Amounts> units; Amounts total; };
struct NativeSlotLimit : std::runtime_error {
    explicit NativeSlotLimit(std::size_t count, std::size_t limit=5)
        : std::runtime_error("native input slot limit: " + std::to_string(count) + " > " + std::to_string(limit)) {}
};
// Costs are supplied by the game's research-adjusted method. This class only
// reserves stock and expands missing intermediates; it never calculates discounts.
class NativePlanner {
    // Immutable request-local catalog. Retry planners only copy inventory state;
    // indices remain valid when the planner is copied or returned by value.
    struct Catalog {
        std::vector<NativeRecipe> recipes;
        std::set<std::wstring> allowed;
        std::map<std::wstring, std::size_t> by_id;
        std::map<std::wstring, std::vector<std::size_t>> producers;
    };
    std::shared_ptr<const Catalog> catalog;
    Amounts stock, surplus, consumed;
    unsigned nodes{};
    bool allow_missing{};
    std::size_t input_limit{5};
    static void add(Amounts& values, const std::wstring& id, int64_t count) {
        const auto sum = int64_t(values[id]) + count;
        if (sum < 0 || sum > 1000000000) throw std::runtime_error("quantity limit");
        values[id] = static_cast<int32_t>(sum);
    }
    void need(const std::wstring& item, int32_t count, std::set<std::wstring>& path) {
        if (++nodes > 10000 || path.size() > 32 || count < 1) throw std::runtime_error("expansion limit");
        auto use = std::min(count, stock[item]);
        stock[item] -= use; count -= use; if (use) add(consumed, item, use);
        use = std::min(count, surplus[item]); surplus[item] -= use; count -= use;
        if (!count) return;
        if (!path.insert(item).second) throw std::runtime_error("recipe cycle");
        struct RestorePath {
            std::set<std::wstring>& path;
            const std::wstring& item;
            ~RestorePath() { path.erase(item); }
        } restore_path{path, item};
        const auto producers = catalog->producers.find(item);
        if (producers != catalog->producers.end()) for (const auto index : producers->second) {
            const auto& recipe = catalog->recipes[index];
            auto saved_stock = stock, saved_surplus = surplus, saved_consumed = consumed;
            try {
                const int64_t batches = (int64_t(count) + recipe.output_amount - 1) / recipe.output_amount;
                for (const auto& [id, quantity] : recipe.costs) {
                    const auto total = batches * quantity;
                    if (total < 1 || total > 1000000000) throw std::runtime_error("quantity limit");
                    need(id, static_cast<int32_t>(total), path);
                }
                add(surplus, item, batches * recipe.output_amount - count);
                return;
            } catch (const std::runtime_error&) {
                stock = std::move(saved_stock); surplus = std::move(saved_surplus); consumed = std::move(saved_consumed);
            }
        }
        if (allow_missing) { add(consumed,item,count); return; }
        throw std::runtime_error("insufficient same-station materials");
    }
public:
    NativePlanner(std::vector<NativeRecipe> rows, std::set<std::wstring> permitted, Amounts inventory, std::size_t limit=5)
        : stock(std::move(inventory)), input_limit(limit) {
        if(limit<5 || limit>64) throw std::runtime_error("unsupported input capacity");
        auto indexed = std::make_shared<Catalog>();
        indexed->recipes = std::move(rows); indexed->allowed = std::move(permitted);
        for (std::size_t index = 0; index < indexed->recipes.size(); ++index) {
            const auto& row = indexed->recipes[index];
            if (row.output_amount < 1 || row.costs.empty()) throw std::runtime_error("invalid native recipe");
            for (const auto& [id, count] : row.costs) if (count < 1) throw std::runtime_error("invalid native cost");
            indexed->by_id.emplace(row.id, index);
            if (indexed->allowed.contains(row.id)) indexed->producers[row.output].push_back(index);
        }
        catalog = std::move(indexed);
        for (const auto& [id, count] : stock) if (count < 0) throw std::runtime_error("invalid stock");
    }
private:
    Schedule resolve_attempt(const std::wstring& root, int32_t batches, bool record_units) {
        if (batches < 1 || batches > 256 || !catalog->allowed.contains(root)) throw std::runtime_error("unsupported request");
        const auto found = catalog->by_id.find(root);
        if (found == catalog->by_id.end()) throw std::runtime_error("root unavailable");
        const auto& row = catalog->recipes[found->second];
        Schedule result;
        if (record_units) result.units.reserve(batches);
        std::set<std::wstring> path{row.output};
        for (int32_t index = 0; index < batches; ++index) {
            Amounts before;
            if (record_units) before = consumed;
            for (const auto& [id, count] : row.costs) need(id, count, path);
            if (!record_units) continue;
            Amounts delta;
            for (const auto& [id, total] : consumed) {
                const auto old = before.find(id);
                const auto amount = total - (old == before.end() ? 0 : old->second);
                if (amount) delta[id] = amount;
            }
            result.units.push_back(std::move(delta));
        }
        result.total = consumed;
        if (result.total.size() > input_limit) throw NativeSlotLimit(result.total.size(),input_limit);
        return result;
    }
    Schedule resolve_plan(const std::wstring& root, int32_t batches, bool record_units) const {
        auto exact=*this;
        try { return exact.resolve_attempt(root,batches,record_units); }
        catch (const NativeSlotLimit&) {
            if(input_limit>5) throw; // Expanded containers always preserve inventory-first planning.
            // Preserve inventory-first behavior whenever it fits. If combining
            // stored and newly produced intermediates would require a sixth
            // slot, try leaving those stored intermediates untouched. Only
            // unlocked same-station producers may replace them with raw inputs.
            std::set<std::wstring> candidates;
            for (const auto& recipe:catalog->recipes) {
                const auto found=stock.find(recipe.output);
                if(catalog->allowed.contains(recipe.id) && found!=stock.end() && found->second>0)
                    candidates.insert(recipe.output);
            }
            unsigned attempts=0;
            for(const auto& item:candidates) {
                if(++attempts>64) break;
                auto alternative=*this; alternative.stock[item]=0;
                try { return alternative.resolve_attempt(root,batches,record_units); }
                catch(const std::runtime_error&) {}
            }
            for(auto first=candidates.begin();first!=candidates.end() && attempts<64;++first) {
                for(auto second=std::next(first);second!=candidates.end() && attempts<64;++second) {
                    ++attempts; auto alternative=*this;
                    alternative.stock[*first]=0; alternative.stock[*second]=0;
                    try { return alternative.resolve_attempt(root,batches,record_units); }
                    catch(const std::runtime_error&) {}
                }
            }
            throw;
        }
    }
public:
    Schedule resolve(const std::wstring& root, int32_t batches) const {
        return resolve_plan(root,batches,true);
    }
    // Uses exactly the same expansion, overflow and slot-limit fallback rules,
    // but maximum-quantity probes do not need per-unit debit schedules.
    bool can_resolve(const std::wstring& root, int32_t batches) const {
        try { resolve_plan(root,batches,false); return true; }
        catch (const std::runtime_error&) { return false; }
    }
    Schedule preview(const std::wstring& root,int32_t batches) const {
        try { return resolve(root,batches); }
        catch (const std::runtime_error&) {
            auto required=*this; required.allow_missing=true;
            return required.resolve(root,batches);
        }
    }
};
inline Amounts suffix(const Schedule& plan, std::size_t index) {
    if (index > plan.units.size()) throw std::runtime_error("invalid native progress");
    Amounts result;
    for (; index < plan.units.size(); ++index)
        for (const auto& [id, count] : plan.units[index]) result[id] += count;
    return result;
}
}

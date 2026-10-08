#pragma once
#include "job_schedule.hpp"

namespace better_workbench {
// The catalog comes exclusively from the native current-workbench GetRecipes.
// Select the root and its producer dependencies; unrelated recipes never cause
// inventory reads or research-cost queries for this request.
inline std::set<std::wstring> dependency_recipes(const std::vector<NativeRecipe>& catalog,
    const std::set<std::wstring>& permitted, const std::wstring& root) {
    std::map<std::wstring,const NativeRecipe*> by_id;
    std::multimap<std::wstring,const NativeRecipe*> producers;
    for (const auto& row : catalog) {
        if (!permitted.contains(row.id) || row.output_amount < 1 || row.costs.empty()) continue;
        by_id.emplace(row.id,&row); producers.emplace(row.output,&row);
    }
    if (!by_id.contains(root)) throw std::runtime_error("root unavailable at current workbench");
    std::vector<std::wstring> pending{root};
    std::set<std::wstring> selected;
    while (!pending.empty()) {
        auto id=std::move(pending.back()); pending.pop_back();
        if (!selected.insert(id).second) continue;
        if (selected.size()>4096) throw std::runtime_error("station recipe limit");
        for (const auto& [item,count] : by_id.at(id)->costs) {
            if (count<=0) continue;
            const auto [first,last]=producers.equal_range(item);
            for (auto it=first;it!=last;++it) if (!selected.contains(it->second->id)) pending.push_back(it->second->id);
        }
    }
    return selected;
}
}

#pragma once
#include "job_schedule.hpp"
#include "input_layout.hpp"
namespace better_workbench {
struct InputDebit { std::wstring item; int32_t slot,quantity; };
inline std::vector<InputDebit> input_debits(const Amounts& identities,const Amounts& unit) {
    const auto indices=input_indices(identities.size());
    for(const auto& [item,count]:unit)
        if(count<1 || !identities.contains(item) || count>identities.at(item))
            throw std::runtime_error("invalid unit debit");
    std::vector<InputDebit> result;
    std::size_t index=0;
    for(const auto& [item,total]:identities) {
        if(total<1) throw std::runtime_error("invalid total debit");
        if(auto found=unit.find(item);found!=unit.end()) result.push_back({item,indices[index],found->second});
        ++index;
    }
    return result;
}
}

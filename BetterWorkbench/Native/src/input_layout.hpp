#pragma once
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>
namespace better_workbench {
inline std::vector<int32_t> input_indices(std::size_t count) {
    if(!count || count>64) throw std::runtime_error("invalid dynamic input count");
    std::vector<int32_t> indices;
    for(std::size_t index=0;index<count;++index)
        indices.push_back(static_cast<int32_t>(index<5?index:index+1));
    return indices; // Native output remains at physical slot five.
}
template<class T> std::vector<T> physical_identities(std::vector<T> values,T none) {
    if(values.empty() || values.size()>64) throw std::runtime_error("invalid dynamic identities");
    if(values.size()>5) values.insert(values.begin()+5,none);
    return values; // Used only by callers indexing the physical container directly.
}
}

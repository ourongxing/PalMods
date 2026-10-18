#pragma once
#include <stdexcept>
#include <string>

namespace CustomPresetsPreview {
template<class Lua, class ConsumeEditor>
std::string read_arguments(const Lua& lua, ConsumeEditor consume_editor) {
    if (lua.get_stack_size()!=2 || !lua.is_userdata(1) || !lua.is_string(2))
        throw std::runtime_error("Preview capture requires an editor and a filename");
    // LuaMadeSimple getters REMOVE their argument. After consuming the editor,
    // the filename is at index 1, not index 2. get_string on a missing value
    // constructs string_view(nullptr) and crashes before C++ can throw.
    consume_editor();
    if (!lua.is_string(1)) throw std::runtime_error("Preview filename unavailable");
    return std::string(lua.get_string(1));
}
}

#include "PreviewArguments.hpp"
#include <iostream>
#include <variant>
#include <vector>
struct Lua {
    mutable std::vector<std::variant<int,std::string>> values;
    mutable int string_reads{};
    int get_stack_size() const { return static_cast<int>(values.size()); }
    bool is_userdata(int i) const { return i>0 && i<=get_stack_size() && std::holds_alternative<int>(values[i-1]); }
    bool is_string(int i) const { return i>0 && i<=get_stack_size() && std::holds_alternative<std::string>(values[i-1]); }
    std::string get_string(int i) const {
        ++string_reads;
        if (!is_string(i)) throw std::runtime_error("Read a missing filename");
        auto result=std::get<std::string>(values[i-1]); values.erase(values.begin()+i-1); return result;
    }
};
void require(bool value) { if (!value) throw std::runtime_error("Preview argument regression"); }
int main() {
    try {
        Lua lua{{1,std::string("C:/预览/造型.png")}};
        int consumed=0;
        const auto path=CustomPresetsPreview::read_arguments(lua,[&] {++consumed; lua.values.erase(lua.values.begin());});
        require(path=="C:/预览/造型.png" && consumed==1 && lua.string_reads==1 && lua.values.empty());
        for (Lua bad : {Lua{{}}, Lua{{1}}, Lua{{std::string("wrong"),1}}, Lua{{1,2}}, Lua{{1,std::string("x"),3}}}) {
            bool rejected=false; int consumedBad=0;
            try { CustomPresetsPreview::read_arguments(bad,[&] {++consumedBad;}); }
            catch (const std::runtime_error&) { rejected=true; }
            require(rejected && consumedBad==0 && bad.string_reads==0);
        }
        Lua vanished{{1,std::string("x")}};
        bool rejected=false;
        try {CustomPresetsPreview::read_arguments(vanished,[&] {vanished.values.clear();});}
        catch (const std::runtime_error&) {rejected=true;}
        require(rejected && vanished.string_reads==0);
        std::cout << "PASS: consuming userdata shifts filename to slot 1; invalid arguments never reach get_string.\n";
        return 0;
    } catch (const std::exception& error) {std::cerr << error.what(); return 1;}
}

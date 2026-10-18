#include "StorageDirectory.hpp"
#include <cassert>
#include <fstream>
#include <iostream>
int main() {
    wchar_t temporary[MAX_PATH];
    assert(GetTempPathW(MAX_PATH,temporary));
    const auto root=std::filesystem::path(temporary) / (L"CustomPresets-storage-test-"+std::to_wstring(GetCurrentProcessId()));
    const auto logical=root/L"Pal"/L"Saved"/L"CustomPresets"/L"presets";
    const auto first=CustomPresetsStorage::prepare_directory(root);
    assert(std::filesystem::is_directory(logical));
    assert(std::filesystem::is_directory(logical.parent_path()/L"backups"));
    assert(first.back()=='/');
    std::ofstream(first+"user-test.preset") << "saved preset";
    const auto second=CustomPresetsStorage::prepare_directory(root);
    assert(first==second);
    std::ifstream saved(second+"user-test.preset");
    std::string content;std::getline(saved,content);
    assert(content=="saved preset");saved.close();
    std::filesystem::remove_all(root);
    std::cout<<"PASS: persistent data directory creation and repeated initialization preserve presets\n";
}

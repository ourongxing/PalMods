#pragma once
#include "PreviewImage.hpp"
#include <filesystem>

namespace CustomPresetsStorage {
inline std::string prepare_directory(const std::filesystem::path& localAppData) {
    const auto directory=localAppData / L"Pal" / L"Saved" / L"CustomPresets" / L"presets";
    std::filesystem::create_directories(directory);
    std::filesystem::create_directories(directory.parent_path() / L"backups");
    // Lua's Windows file API uses narrow paths. Prefer the Windows short path
    // so non-ASCII account names remain usable when 8.3 aliases are available.
    std::filesystem::path usable=directory;
    const auto required=GetShortPathNameW(directory.c_str(),nullptr,0);
    if (required) {
        std::wstring shortPath(required,L'\0');
        const auto length=GetShortPathNameW(directory.c_str(),shortPath.data(),required);
        if (length && length<required) {shortPath.resize(length);usable=shortPath;}
    }
    const auto utf8=usable.generic_u8string();
    return std::string(reinterpret_cast<const char*>(utf8.data()),utf8.size()) + "/";
}
}

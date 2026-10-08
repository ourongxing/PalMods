cmake_minimum_required(VERSION 3.22)

project(PalCombo LANGUAGES CXX)
set(CMAKE_CONFIGURATION_TYPES Game__Shipping__Win64 CACHE STRING "SDK-compatible configuration" FORCE)
set(CMAKE_CXX_FLAGS_GAME__SHIPPING__WIN64 "${CMAKE_CXX_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_GAME__SHIPPING__WIN64 "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")

set(PalModsSDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../.build/UE4SS" CACHE PATH "Shared PalMods SDK package")
find_package(PalModsSDK CONFIG REQUIRED)
add_library(PalComboFillerNative SHARED src/dllmain.cpp)
target_compile_features(PalComboFillerNative PRIVATE cxx_std_23)
target_include_directories(PalComboFillerNative PRIVATE src)
target_link_libraries(PalComboFillerNative PRIVATE PalMods::UE4SS)
set_property(TARGET PalComboFillerNative PROPERTY MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
target_compile_options(PalComboFillerNative PRIVATE /EHsc /Zc:__cplusplus /utf-8)
set_target_properties(PalComboFillerNative PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>/bin")

cmake_minimum_required(VERSION 3.22)

project(PalCombo LANGUAGES CXX)

# requirements
set(UE4SS_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../../../.tools/RE-UE4SS" CACHE PATH "Pinned UE4SS checkout")
if(NOT EXISTS "${UE4SS_SOURCE}/CMakeLists.txt")
    message(FATAL_ERROR "Run tools/setup_ue4ss.ps1 from the repository root first")
endif()
add_subdirectory("${UE4SS_SOURCE}" RE-UE4SS)
add_library(PalComboFillerNative SHARED src/dllmain.cpp)
target_compile_features(PalComboFillerNative PRIVATE cxx_std_20)
target_include_directories(PalComboFillerNative PRIVATE src)
target_link_libraries(PalComboFillerNative PRIVATE UE4SS)

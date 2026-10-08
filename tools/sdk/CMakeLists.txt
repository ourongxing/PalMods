cmake_minimum_required(VERSION 3.22)
project(PalModsSDK LANGUAGES CXX)
set(UE4SS_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../../.tools/RE-UE4SS" CACHE PATH "UE4SS source")
if(NOT EXISTS "${UE4SS_SOURCE}/CMakeLists.txt")
    message(FATAL_ERROR "Run tools/setup_ue4ss.ps1 before building the shared SDK")
endif()
add_subdirectory("${UE4SS_SOURCE}" RE-UE4SS)
# A neutral consumer lets MSBuild resolve transitive usage requirements without
# depending on any mod's project, include directories, or export definitions.
add_library(PalModsSDKProbe SHARED probe.cpp)
target_link_libraries(PalModsSDKProbe PRIVATE UE4SS)

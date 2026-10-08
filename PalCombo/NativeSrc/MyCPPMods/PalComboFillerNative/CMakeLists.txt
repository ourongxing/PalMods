cmake_minimum_required(VERSION 3.22)

add_library(PalComboFillerNative SHARED src/dllmain.cpp)
target_compile_features(PalComboFillerNative PRIVATE cxx_std_20)
target_include_directories(PalComboFillerNative PRIVATE .)
target_link_libraries(PalComboFillerNative PRIVATE UE4SS)

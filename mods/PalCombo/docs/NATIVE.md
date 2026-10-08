# PalCombo 原生工程

`native/CMakeLists.txt` 构建 `PalComboFillerNative`，配置为 `Game__Shipping__Win64`，链接共享 `PalMods::UE4SS`。
源码位于 `native/src/`，连招回归位于 `tests/native/rotation_test.cpp`。

构建入口与环境见 [根 README](../../../README.md)。已有 SDK 包时，可用
`mods/PalCombo/tools/configure_native.bat -A x64 -T version=14.44.35207` 单独生成工程。

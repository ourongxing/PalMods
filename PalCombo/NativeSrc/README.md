# PalCombo native source

Run `./setup_dependency.ps1` before the first build, then run
`./build_mods_shipping.bat` from this directory. The pinned UE4SS source is
downloaded into the repository's `.tools/RE-UE4SS/`; build output goes to `build/`. Both are ignored by
the root Git repository. See [DEVELOPMENT.md](DEVELOPMENT.md) for implementation
details.

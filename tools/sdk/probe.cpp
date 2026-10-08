// Build-time SDK consumer only; never installed into the game.
extern "C" __declspec(dllexport) int palmods_sdk_probe() { return 0; }

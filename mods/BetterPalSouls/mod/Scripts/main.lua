local loaded, config = pcall(require, "config")
if not loaded or type(config) ~= "table" then config = { Enabled = true, Language = "auto", RefreshIntervalMs = 750 } end
require("BetterPalSouls.UI").start(config)

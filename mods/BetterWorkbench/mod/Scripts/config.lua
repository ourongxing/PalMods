return {
    Enabled = true,
    MaxDepth = 32,
    MaxNodes = 10000,
    MaxCount = 1000000000,
    -- Multiple recipes may yield the same item. Select an exact recipe ID here.
    PreferredRecipes = {},
    MaterialScroll = { Enabled = true, VisibleRows = 5, RowHeight = 38 },
    -- auto follows the game language; overrides: zh-Hans, zh-Hant, ja, en.
    Disassembly = { Enabled = true, Language = "auto" },
    Diagnostics = {
        Enabled = false,
        MaxHitsPerHook = 12,
        MaxTotalHits = 150,
        FocusRecipes = { CarbonFiber = true, CarbonFiber2 = true, Bio_Battery = true },
        FocusItems = { "Coal", "Charcoal", "FireOrgan", "ElectricOrgan", "IronIngot", "CarbonFiber", "Bio_Battery" },
        MaxSetupVisits = 600,
        MaxInventorySamples = 24,
        -- Quarantined after the 2026-10-06 crash; not connected to diagnostics.
        MaterialAudit = false,
    },
}

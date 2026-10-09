------------------------------------------------
-- PalBoxPageSkipConfig
-- Version: 1.2.5
-- Date: 2026-09-16
-- Author: ikusamaou
------------------------------------------------
------------------------------------------------
-- 1. Changelog
------------------------------------------------
-- Version 1.2.5 - 2026-09-16
-- - Updated Page Skip hold documentation to match the native page-repeat implementation.
--
-- Version 1.2.4 - 2026-09-10
-- - Updated the Pal selling-screen Trigger warning to match the final guide-suppression behavior.
--
-- Version 1.2.3 - 2026-09-09
-- - Updated Trigger Page Skip guide documentation for the source-row conflict-suppression implementation.
--
-- Version 1.2.2 - 2026-09-08
-- - Updated Page Skip operation-guide documentation to match the current CommonUI implementation.
--
-- Version 1.2.1 - 2026-09-07
-- - Updated controller documentation after disabling MOD operation-guide registration.
--
-- Version 1.2.0 - 2026-09-06
-- - Added DarnMenu integration metadata for supported in-game configuration options.
-- - Added configurable Gamepad controls for Page Skip.
-- - Added Right Stick Left/Right and Left/Right Trigger as supported Gamepad inputs.
-- - Documented the Pal selling screen limitation for Trigger Page Skip.
--
-- Version 1.1.0 - 2026-09-04
-- - Added automatic config migration with backup to preserve user settings when updating the MOD.
------------------------------------------------
-- ----------------------------------------------
-- Require
-- ----------------------------------------------

-- Key.lua is used to convert key names such as F8 into
-- the key codes used by UE4SS.
--
-- To assign a different key, use a key name defined in Key.lua.
local Key = require("Key")

local Config = {

    -- ------------------------------------------------
    -- Page Skip
    -- ------------------------------------------------
    -- This is a convenient feature independent of the overlay display.
    --
    -- On supported PalBox screens, multiple pages can be skipped at once.
    -- Holding a Page Skip input repeats the operation automatically through
    -- Palworld's native page-repeat timing. Each repeat immediately moves the
    -- actual PalBox by PageOffset pages and refreshes the displayed page.
    -- Releasing the input stops the native repeat.
    -- The Global PalBox is excluded because using this feature there causes the game to freeze.
    --
    -- The available settings are described below.
    -- Changes are loaded automatically while the game is running,
    -- including PageOffset, keyboard hotkey, and Gamepad button changes.
    --
    -- PageOffset:
    -- The number of pages to skip with each key press.
    -- Specify a positive value.
    --
    -- SkipForwardKey:
    -- The keyboard key used to skip forward by the number of pages specified by PageOffset.
    --
    -- SkipBackwardKey:
    -- The keyboard key used to skip backward by the number of pages specified by PageOffset.
    --
    -- GamepadSkipForwardButton:
    -- The Gamepad input used to skip forward.
    --
    -- GamepadSkipBackwardButton:
    -- The Gamepad input used to skip backward.
    --
    -- The Gamepad settings can be changed while the game is running.
    --
    -- Supported Gamepad inputs:
    --   Right Stick Left / Right
    --   Left Trigger / Right Trigger
    --
    -- The MOD adds Page Skip operation guides to supported PalBox screens
    -- through the game's CommonUI Action Bar. Keyboard and Gamepad inputs for
    -- each direction share the same guide row.
    --
    -- When a Trigger is assigned to Page Skip, the conflicting vanilla
    -- Cursor Move Trigger key is suppressed from the Action Bar guide source
    -- while the native input binding itself remains available.
    --
    -- WARNING:
    -- Trigger Page Skip does not work on the Pal selling screen because the
    -- vanilla Trigger page-movement action takes priority there. The conflicting
    -- PageSkip Trigger guide is hidden on that screen.
    --
    -- Example:
    -- PageOffset = 5
    -- SkipForwardKey = Key.D
    -- SkipBackwardKey = Key.A
    -- GamepadSkipForwardButton = "Right Stick Right"
    -- GamepadSkipBackwardButton = "Right Stick Left"
    --
    -- With these settings:
    -- D key / Right Stick Right → Skip forward by 5 pages.
    -- A key / Right Stick Left → Skip backward by 5 pages.
    -- ------------------------------------------------
    PageSkip = {

        PageOffset = 5, -- @darn min=1; max=100; step=1

        SkipForwardKey = Key.D, -- @darn kind=hotkey
        SkipBackwardKey = Key.A, -- @darn kind=hotkey

        -- Select Right Stick Left/Right or Left/Right Trigger.
        -- WARNING: Trigger Page Skip does not work on the Pal selling screen; its conflicting PageSkip Trigger guide is hidden there.
        GamepadSkipForwardButton = "Right Stick Right", -- @darn label="Gamepad Skip Forward Button"; values={"Right Stick Right","Right Stick Left","Right Trigger","Left Trigger"}

        -- Select Right Stick Left/Right or Left/Right Trigger.
        -- WARNING: Trigger Page Skip does not work on the Pal selling screen; its conflicting PageSkip Trigger guide is hidden there.
        GamepadSkipBackwardButton = "Right Stick Left", -- @darn label="Gamepad Skip Backward Button"; values={"Right Stick Left","Right Stick Right","Left Trigger","Right Trigger"}

    },

}

return Config

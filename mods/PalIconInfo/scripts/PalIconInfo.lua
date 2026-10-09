------------------------------------------------
-- PalIconInfo
-- Version: 1.4.0-beta2
-- Date: 2026-09-21
-- Author: ikusamaou
------------------------------------------------
------------------------------------------------
-- Changelog
------------------------------------------------
-- Version 1.4.0-beta2 - 2026-09-21
-- - Improved pooled Overlay lifecycle stability during condensation, page navigation, sorting, Preset transitions, and repeated PalBox rebuilds.
-- - Prevented pooled Overlays from attaching before a valid lifecycle owner is established, avoiding ownerless Entries that could outlive their source Widget tree.
-- - Fixed an occasional missing Overlay on a PalBox slot by replaying the initial Overlay update after the ScrollList owner becomes available.
-- - Improved condensation Party slot lifecycle handling so delayed Slot updates after Widget teardown cannot reacquire pooled Overlays.
--
-- Version 1.4.0-beta1 - 2026-09-21
-- - Added prewarmed reusable Overlay Pools for normal PalBox, Preset, and Party slots, including condensation Party slots, reducing repeated Widget creation.
-- - Unified pooled Overlay lifecycle handling across normal PalBox, Preset, and condensation Party slots; screen-specific logic only determines lifecycle boundaries.
-- - Pooled PalBox / Preset / Party targets no longer fall back to direct Overlay creation when Pool acquisition fails.
-- - Reduced first PalBox-open processing overhead by preloading and anchoring required UI textures before PalBox use.
-- - Fixed Passive Skill bar/background texture handling by using Engine WhiteSquareTexture.
-- - Reworked PalBox Page Skip hold behavior to use Palworld's native repeat timing and direct page movement.
-- - Improved MOD restart stability by redesigning Hook dispatch, Hook tracking, and runtime cleanup so previous executions do not retain old Overlay Pool or UObject state.
-- - Refactored and optimized internal Overlay Pool, resource-loading, Page Skip, and Hook management code.
--
-- Version 1.3.2 - 2026-09-14
-- - Added Pal Preset reordering with Middle Mouse Button or Gamepad Square / X.
-- - Added a CommonUI Action Bar guide for Pal Preset reordering.
-- - Preserved custom Preset names when reordering entries.
-- - Improved More Pal Slots compatibility by preventing a crash when Preset data contains more entries than the Preset UI can display.
--
-- Version 1.3.1 - 2026-09-10
-- - Replaced WBP_PalStatus Action Bar guide proxies with the existing CommonUI bridge bindings, preventing Pal preview rendering side effects.
-- - Added compatibility for custom Passive Skills that use OverrideNameTextID or do not provide the standard PASSIVE_<SkillID> text Row.
-- - Fixed Page Skip Trigger guide display on the Pal selling screen so unavailable L2/R2 Page Skip actions are no longer advertised there.
--
-- Version 1.3.1-beta4 - 2026-09-09
-- - Updated Pal Preset Overlay data to use each registered Pal's current data instead of the snapshot stored when the preset was created.
-- - Isolated unavailable or invalid Preset entries so one missing Pal does not interrupt Overlay updates for later entries.
-- - Added direct visible Overlay refresh after Config reload without rebuilding the current PalBox page.
-- - Added direct visible Overlay refresh after condensation through the native operation-result callback.
-- - Reworked Trigger Page Skip guide conflict handling to avoid Action Bar update-Hook processing and guide flicker.
--
-- Version 1.3.1-beta3 - 2026-09-08
-- - Added an option to enable or disable Overlay display on the multi-hatch result screen.
-- - Added event-driven just-in-time Hook registration for the lazily loaded multi-hatch result UI.
-- - Replaced indefinite one-second Blueprint Hook retry polling with a one-time game-thread preload fallback for other unloaded Blueprint targets.
-- - Reduced duplicate Outer-hierarchy traversal in the high-frequency normal SlotUpdate path.
-- - Made Hook, hotkey, and Config Watch runtime state restart-safe to avoid callback buildup after UE4SS MOD restarts.
-- - Removed persistent CommonUI guide proxies during MOD restart so hidden Widget instances do not accumulate across restarts.
-- - Cleaned up internal logging, unused code, and outdated comments.
--
-- Version 1.3.1-beta2 - 2026-09-07
-- - Removed the RegisterActionBinding observer used for MOD operation guides to avoid a potential UI-related crash.
-- - Preserved CommonUI-based DisplayMode input without the observer.
-- - Added DisplayMode support for the Pal Preset screen and incubator all-open result screen.
-- - Restored DisplayMode and Page Skip state correctly when returning from the Pal Preset screen.
-- - Improved hidden bridge cleanup and retained local R3 conflict-guide suppression for the Global PalBox and Dimensional Pal Storage.
--
-- Version 1.3.1-beta1 - 2026-09-06
-- - Added configurable Gamepad input for DisplayMode through CommonUI.
-- - Added DisplayMode config migration support for the new Gamepad assignment.
-- - Added context-specific handling for vanilla R3 conflicts in the Global PalBox and Dimensional Pal Storage.
--
-- Version 1.3.0-beta1 - 2026-09-04
-- - Added automatic config migration with backup to preserve user settings when updating the MOD.
--
-- Version 1.2.1 - 2026-09-02
-- - Added an option to enable or disable Party Pal Slot display.
-- - Added an option to disable the PalBox refresh Hook after condensation.
--
-- Version 1.2.0 - 2026-09-02
-- - Added overlay display support for Party Pal Slots.
-- - Added Party-specific Overlay target configuration and Canvas handling.
-- - Added hooks for Party Pal Slot initialization and Handle updates.
-- - Unified Normal PalBox Slot and Party Pal Slot Overlay processing through UpdateSlotOverlay().
--
-- Version 1.1.2 - 2026-09-01
-- - Added a safe Outer-class lookup utility.
-- - Optimized excluded Widget detection: replaced GetFullName()-based string matching with direct class name checks through the Widget's Outer hierarchy, reducing processing overhead.
-- - Changed the processing order within SetupText().
--
-- Version 1.1.1 - 2026-08-29
-- - Improved Overlay processing performance by caching frequently accessed
--   DataTable data in Lua hash tables.
-- - Fixed an issue where PalCraftInfo was excluded from displaying Pal information beyond the intended scope.
--
-- Version 1.1.0 - 2026-08-25
-- - Added optional Ability Glasses requirement for Talent display.
-- - Added equipment change detection for Talent display updates.
--
-- Version 1.0.3 - 2026-08-24
-- - Changed method for retrieving the configuration path

-- Version 1.0.2 - 2026-08-23
-- - Added configurable Talent display options.
-- - Added configurable Talent color thresholds.
-- - Added optional symbols for hidden and maximum Talent values.
-- - Added optional automatic horizontal text scaling.
--
-- Version 1.0.1 - 2026-08-23
-- - Improved PalBox visibility handling.
-- - Prevented DisplayMode switching when the PalBox is not open.
-- - Improved DisplayMode switching performance by updating
--   only visible PalCharacter slots.
--
-- Version 1.0.0 - 2026-08-21
-- - Initial release.
------------------------------------------------

------------------------------------------------
-- Dependencies
------------------------------------------------

-- Shared configuration manager.
--
-- The bundled default config is kept under Scripts\DefaultConfig_DO_NOT_EDIT,
-- while the user-editable config is stored in the shared PalIconInfo config folder.
-- On a config version change, matching user values are migrated
-- onto the new default source before the config is loaded.
local ConfigManager = require("ConfigManager")

-- Shared CommonUI input utilities.
-- PalIconInfo owns its DisplayMode bridge and behavior; ControllerInput
-- provides shared DT_UIInputAction row management and keyboard FKey conversion.
local ControllerInput = require("ControllerInput")

------------------------------------------------
-- Logging
------------------------------------------------

-- Enables or disables detailed debug logging.
-- Normally false. Set to true only when investigating a problem.
local DEBUG = false

local function Log(...)
    print("[PalIconInfo]", ...)
end

-- Detailed investigation log.
-- Normally keep this disabled and enable it only when investigating a problem.
local function DebugLog(...)
    if DEBUG then
        print("[PalIconInfo][Debug]", ...)
    end
end

------------------------------------------------
-- Restart-safe Runtime
------------------------------------------------
--
-- UE4SS MOD restart can leave RegisterHook / RegisterKeyBind callbacks and
-- delayed loops from the previous Lua execution alive. Keep only lightweight
-- IDs, key registration state, and dispatch pointers in _G so a new execution
-- can invalidate or unregister the previous one without retaining live game
-- UObjects.
local PAL_ICON_RUNTIME_KEY =
    "__PalIconInfo_PalIconInfo_Runtime"

local PalIconRuntime =
    rawget(
        _G,
        PAL_ICON_RUNTIME_KEY
    )

if type(PalIconRuntime) ~= "table" then

    PalIconRuntime = {
        Hooks = {},
        RegisteredDisplayModeKeys = {},
        PresetSwapMouseKeyRegistered = false,
        Generation = 0,
    }

    rawset(
        _G,
        PAL_ICON_RUNTIME_KEY,
        PalIconRuntime
    )

end

if type(PalIconRuntime.Hooks) ~= "table" then
    PalIconRuntime.Hooks = {}
end

if type(PalIconRuntime.HookHistory) ~= "table" then
    PalIconRuntime.HookHistory = {}
end

if type(PalIconRuntime.Dispatchers) ~= "table" then
    PalIconRuntime.Dispatchers = {}
end

if type(PalIconRuntime.RegisteredDisplayModeKeys) ~= "table" then
    PalIconRuntime.RegisteredDisplayModeKeys = {}
end

if type(PalIconRuntime.PresetSwapMouseKeyRegistered) ~= "boolean" then
    PalIconRuntime.PresetSwapMouseKeyRegistered = false
end

do

    local previousCleanup =
        PalIconRuntime.Cleanup

    -- Invalidate callbacks from the previous Lua execution before calling any
    -- previous-execution cleanup code. This is deliberately done by the new
    -- execution so restart safety does not depend on the old Cleanup function
    -- having the latest implementation.
    PalIconRuntime.Generation =
        (tonumber(PalIconRuntime.Generation) or 0) + 1

    PalIconRuntime.DisplayModeKeyHandler = nil
    PalIconRuntime.PresetSwapMouseHandler = nil

    -- Drop execution-local callbacks before touching old Widgets. Registered
    -- UE4SS wrappers resolve callbacks through this persistent table and keep
    -- only scalar generation/key data, so clearing it also releases references
    -- to the previous Overlay Pools even if a native Hook survives unregister.
    PalIconRuntime.Dispatchers = {}

    -- Unregister every Hook ID still known to the runtime. HookHistory is kept
    -- separately from the target->latest map so an accidental re-registration
    -- can never make an older Hook ID unreachable during a later MOD restart.
    local previousHooks =
        PalIconRuntime.HookHistory

    -- Migration from builds that tracked only target->Hook in Hooks. Without
    -- this fallback, the first upgrade to HookHistory would lose the IDs that
    -- are most important to unregister.
    if type(previousHooks) ~= "table"
        or #previousHooks == 0 then

        previousHooks = {}

        for _, hook in pairs(PalIconRuntime.Hooks) do
            previousHooks[#previousHooks + 1] = hook
        end

    end

    if type(previousHooks) == "table" then

        for _, hook in ipairs(previousHooks) do

            if type(hook) == "table"
                and hook.Active ~= false
                and type(hook.Target) == "string"
                and type(hook.PreId) == "number"
                and type(hook.PostId) == "number" then

                pcall(function()
                    UnregisterHook(
                        hook.Target,
                        hook.PreId,
                        hook.PostId
                    )
                end)

                hook.Active = false

            end

        end

    end

    PalIconRuntime.Hooks = {}
    PalIconRuntime.HookHistory = {}

    if type(previousCleanup) == "function" then
        pcall(previousCleanup)
    end

    PalIconRuntime.Cleanup = nil
end

-- previousCleanup() may itself advance Generation. Advance once more and bind
-- this execution to the final value only after all previous state is retired.
PalIconRuntime.Generation =
    (tonumber(PalIconRuntime.Generation) or 0) + 1

local RuntimeGeneration =
    PalIconRuntime.Generation

local function IsCurrentRuntimeGeneration()

    return
        PalIconRuntime.Generation
        == RuntimeGeneration

end

local scriptPath = debug.getinfo(1, "S").source

if scriptPath:sub(1, 1) == "@" then
    scriptPath = scriptPath:sub(2)
end

local SCRIPT_DIR =
    scriptPath:match("^(.*[/\\])") or ""

local CONFIG_PATH =
    SCRIPT_DIR .. "..\\..\\shared\\PalIconInfo\\PalIconInfoConfig.lua"

local DEFAULT_CONFIG_PATH =
    SCRIPT_DIR .. "DefaultConfig_DO_NOT_EDIT\\PalIconInfoConfig.lua"

------------------------------------------------
-- DisplayMode Config Migration
------------------------------------------------

local DEFAULT_DISPLAY_MODE_GAMEPAD_BUTTON =
    "Right Stick Press"


-- DisplayMode is a ReplaceTables entry, so ConfigManager preserves the
-- existing user's complete DisplayMode source during version migration.
--
-- Older configs have no GamepadButton member. During migration only,
-- inject the default Gamepad assignment into the first active DisplayMode
-- hotkey table in source order before that preserved table replaces the new
-- default DisplayMode table.
--
-- This is intentionally a migration-time source upgrade. Runtime controller
-- logic never depends on source order or parses the config file.
local function UpgradeDisplayModeSourceForGamepad(
    rawSource
)

    if type(rawSource) ~= "string" then
        return nil,
            "DisplayMode source is not a string."
    end

    ------------------------------------------------
    -- Already upgraded.
    ------------------------------------------------

    for line in (rawSource .. "\n"):gmatch(
        "(.-)\r?\n"
    ) do

        if not line:match("^%s*%-%-")
            and line:match(
                "%f[%a]GamepadButton%f[^%w_]%s*="
            ) then

            return rawSource
        end

    end

    ------------------------------------------------
    -- Find the first active source line that opens a
    -- DisplayMode hotkey table:
    --
    --     [Key.F1] = {
    ------------------------------------------------

    local searchPos = 1

    while searchPos <= #rawSource do

        local newline =
            rawSource:find(
                "\n",
                searchPos,
                true
            )

        local lineEnd =
            newline and newline - 1
            or #rawSource

        local line =
            rawSource:sub(
                searchPos,
                lineEnd
            )

        if not line:match("^%s*%-%-") then

            local openStart,
                openEnd =
                line:find(
                    "%[%s*[%a_][%w_]*%.[%a_][%w_]*%s*%]%s*=%s*{"
                )

            if openStart then

                local indent =
                    line:match("^(%s*)")
                    or ""

                local memberIndent =
                    indent .. "    "

                local absoluteOpenEnd =
                    searchPos
                    + openEnd
                    - 1

                local insertion =
                    "\n\n"
                    .. memberIndent
                    .. "GamepadButton = "
                    .. string.format(
                        "%q",
                        DEFAULT_DISPLAY_MODE_GAMEPAD_BUTTON
                    )
                    .. ","

                return rawSource:sub(
                    1,
                    absoluteOpenEnd
                )
                .. insertion
                .. rawSource:sub(
                    absoluteOpenEnd + 1
                )

            end

        end

        if not newline then
            break
        end

        searchPos = newline + 1

    end

    return nil,
        "No active DisplayMode hotkey table was found for Gamepad migration."

end


local ConfigManagerInstance =
    ConfigManager.Create({

        ConfigPath = CONFIG_PATH,

        DefaultConfigPath = DEFAULT_CONFIG_PATH,

        -- DisplayMode is preserved as a complete user table.
        -- It is not recursively merged with the new default.
        ReplaceTables = {
            DisplayMode = true,
        },

        -- Existing DisplayMode is preserved as source. Upgrade older user
        -- tables once during version migration by adding GamepadButton to
        -- the first DisplayMode hotkey table when the field is absent.
        ReplaceTableSourceTransforms = {
            DisplayMode =
                UpgradeDisplayModeSourceForGamepad,
        },

        -- Pass the MOD logger so important config operations such as
        -- creation, migration, merge, backup, and replacement are
        -- written with the normal [PalIconInfo] log prefix.
        Log = Log,

    })

local Config, ConfigLoadError =
    ConfigManagerInstance:Load()

if not Config then
    error(
        "[PalIconInfo] "
        .. tostring(ConfigLoadError)
    )
end

------------------------------------------------
-- MOD Processing Overview
------------------------------------------------

-- PalIconInfo mainly processes data in the following order.
--
-- 1. Load display settings from PalIconInfoConfig.lua.
-- 2. Obtain Palworld's standard Textures / DataTables / Widget Classes.
-- 3. Create MOD Overlay Widgets on existing Canvases inside Pal Slots.
-- 4. Hook the relevant PalBox, Preset, Party, Hatch, equipment, and optional
--    condensation events that can change Overlay state.
-- 5. Obtain SaveParameter through the route appropriate to each Overlay target.
-- 6. Pass valid Pal data to the shared UpdateSlotOverlay() processing.
-- 7. Update each display item in UpdateOverlayData() and apply DisplayMode
--    visibility through UpdateOverlayVisibility().
--
-- SaveParameter retrieval differs by target type, but Normal, Preset, Party, and
-- Hatch entries share the same Overlay update path after retrieval.

------------------------------------------------
-- Code Structure
------------------------------------------------

-- The code is organized in the following order according to the role of each process.
--
--   Dependencies / Logging
--     ↓
--   Restart-safe Runtime / Config Migration
--     ↓
--   Global State / Constants / Hook Targets / Asset Paths
--     ↓
--   Configuration Watch / Resource Loading / Utility
--     ↓
--   Display Mode / Widget Functions / Overlay Pools
--     ↓
--   Data Functions / Overlay UI Data Update
--     ↓
--   Slot Management / Feature-specific Hooks
--     ↓
--   Restart-safe Hook Registration
--     ↓
--   Initialization / Cleanup / Configuration Watch
--
-- In general, higher-level processes use lower-level functions.
--
-- In particular, SaveParameter retrieval and Overlay update processing are separated.
-- This allows the SaveParameter retrieval method to be changed without modifying the UI update side.

------------------------------------------------
-- Public Customization Points
------------------------------------------------

-- The main parts normally modified by users of the public version are as follows.
--
--   PalIconInfoConfig.lua
--     Settings such as display items, position, size, color, and hotkeys.
--     This is the file that normal users edit first.
--
--   OverlayLayout
--     The structure and creation order of Widgets generated as the Overlay.
--     When adding, removing, or reordering Widgets, also check their
--     correspondence with the settings in Config.UI.
--
--   AssetPath
--     Paths to Palworld's standard assets used by the MOD.
--     Modify these when a game update changes an asset's location or name.
--
--   ExcludedWidgetNames
--     Add Pal Slot-related Widgets here when their Overlay should be excluded.
--
--   HookTarget
--     Functions targeted by Hooks on the Palworld side.
--     Modify these when a game update changes Blueprint or Function names.
--
-- All other processing is basically internal MOD implementation.
-- When adding a new display item, follow the existing division of responsibilities
-- between Data Functions / Overlay UI Data Update / OverlayLayout / Config.UI.
--
-- In particular, UE4SS Unreal property access may require different access methods
-- depending on the type of the target property, so do not unnecessarily unify
-- existing retrieval methods.
-- TextBlock and Image color processing also use dedicated functions because
-- their ColorAndOpacity structures differ.

------------------------------------------------
-- Maintenance Notes
------------------------------------------------

-- The configuration and internal implementation have the following relationship.
--
--   PalIconInfoConfig.lua
--       ↓
--   Config.DisplayMode / DisplayOption / UI
--       ↓
--   OverlayLayout
--       ↓
--   CreateOverlayWidgets()
--       ↓
--   UpdateOverlayData() / UpdateOverlayVisibility()
--
-- If only PalIconInfoConfig.lua is edited, PalIconInfo.lua does not need to be changed
-- when only existing display item settings are modified.
--
-- When adding or removing Overlay Widgets, check at least the following:
--
--   1. OverlayLayout
--      Widget creation order and paths in the Overlay Table.
--
--   2. CreateOverlayWidgets()
--      Creation of the Widget Classes corresponding to OverlayLayout.
--
--   3. Config.UI
--      Settings such as position, size, font, and color for the added Widgets.
--
--   4. UpdateOverlayData()
--      Processing that applies game data to the Widget.
--
--   5. UpdateOverlayVisibility()
--      Processing that makes the Widget a display target in DisplayMode.
--
-- Changing only one of these can cause the Widget not to be created,
-- not to be displayed, or Config settings not to be applied.
--
-- When modifying processing related to Hooks or UE4SS Property Access,
-- unlike normal Config editing, dependencies on the game's Widget structure
-- and data structure must be checked.

------------------------------------------------
-- Global State
------------------------------------------------

-- Stores the current state index for each hotkey.
-- Config.DisplayMode key codes are used as keys.
local DisplayModeState = {}

-- Records key codes for which RegisterKeyBind() has already been executed.
--
-- When PalIconInfoConfig.lua is hot-reloaded, registering an already registered key
-- again may result in multiple callbacks being registered for the same key.
-- Therefore, registered keys are tracked here, and only newly added keys
-- are registered by RegisterDisplayModeHotKeys().
local RegisteredDisplayModeKeys =
    PalIconRuntime.RegisteredDisplayModeKeys

-- Resources
-- ResourceReady indicates whether initialization of the required UE assets is complete.
-- UObjectCache stores UE objects obtained through StaticFindObject(),
-- while Res stores them in a form that can be referenced by the names defined in ResourcePaths.
local ResourceReady = false
local UObjectCache = {}
local Res = {}

-- Set only when a normal SlotUpdate had to return because the required
-- resources were not ready. InitializeExistingSlots() is a rescue path for
-- precisely that case and is unnecessary when the first initialization
-- succeeds before any normal Slot was missed.
PalIconRuntime.NormalSlotsMissedBeforeResourceReady = false

-- Caches data retrieved from Palworld's standard DataTables.
-- These caches are built once when the MOD is initialized so that
-- Palpedia, Passive Skill, and Friendship Rank information can be
-- retrieved from Lua tables during Slot updates without repeatedly
-- searching the corresponding DataTables.
local PalpediaCache = {}
local PassiveSkillCache = {}
local FriendshipRankCache = {}
------------------------------------------------
-- Constants
------------------------------------------------

-- Defines the creation order of Overlay Widgets and the Lua Table paths
-- used to reference the generated Widgets.
--
-- Each entry in this list is written as a dot-separated path such as:
--
--     "PassiveSkill.Bar.Image_Background"
--
-- CreateOverlayWidgets() creates Widgets in this order and uses SetPath()
-- to store them in a hierarchy such as overlay.PassiveSkill.Bar.Image_Background.
--
-- GetOverlayWidgets() also retrieves MOD Widgets on the Canvas in this order,
-- and ClearOverlayWidgets() performs the appropriate clearing operation
-- for each Widget type in this order.
-- The display order, meaning the stacking order, also follows this order.
-- Reorder the list if the display order needs to be changed.
--
-- Entries whose names begin with Text_ are created as TextBlocks,
-- while entries whose names begin with Image_ are created as Images.
local OverlayLayout = {

    "Number.Text_No",
    "Number.Text_NumberValue",
    "Number.Text_SuffixValue",
    "Number.Text_0",

    "Level.Text_Lv",
    "Level.Text_LevelValue",

    "Gender.Male.Image_MaleIconBG",
    "Gender.Female.Image_FemaleIconBG",
    "Gender.Male.Image_MaleIcon",
    "Gender.Female.Image_FemaleIcon",

    "Rank.Image_RankIcon.1",
    "Rank.Image_RankIcon.2",
    "Rank.Image_RankIcon.3",
    "Rank.Image_RankIcon.4",

    "Soul.Image_SoulIcon",
    "Soul.Text_SoulValue",

    "Friendship.Image_FriendshipIcon",
    "Friendship.Text_FriendshipValue",

    "PassiveSkill.Bar.Image_Background",
    "PassiveSkill.Bar.Image_PassiveSkillIcon.1",
    "PassiveSkill.Bar.Image_PassiveSkillIcon.2",
    "PassiveSkill.Bar.Image_PassiveSkillIcon.3",
    "PassiveSkill.Bar.Image_PassiveSkillIcon.4",

    "Talent.Text_TalentHPValue",
    "Talent.Text_TalentATKValue",
    "Talent.Text_TalentDEFValue",

    "PassiveSkill.Name.Image_Background.1",
    "PassiveSkill.Name.Image_Background.2",
    "PassiveSkill.Name.Image_Background.3",
    "PassiveSkill.Name.Image_Background.4",
    "PassiveSkill.Name.Text_PassiveSkillName.1",
    "PassiveSkill.Name.Text_PassiveSkillName.2",
    "PassiveSkill.Name.Text_PassiveSkillName.3",
    "PassiveSkill.Name.Text_PassiveSkillName.4",

}

------------------------------------------------
-- Base Child Widget Count
------------------------------------------------

-- Number of native Canvas child Widgets that exist before MOD overlay Widgets.
--
-- The value differs depending on the type of slot:
--   Normal: PalBox slots
--   Party:  Party Pal slots
--   Hatch:  Incubator hatch-result entries
--
-- Overlay Widgets are added after these native Widgets.
-- These values are fixed according to the current Palworld UI structure
-- and cannot be determined automatically from OverlayLayout.
--
-- If a game update changes the native Widget structure,
-- these values must be reviewed because they are used to distinguish
-- Palworld's native Widgets from MOD-added overlay Widgets.
local BASE_CHILD_COUNT_NORMAL = 16
local BASE_CHILD_COUNT_PARTY = 2
local BASE_CHILD_COUNT_HATCH = 3

------------------------------------------------
-- Overlay Target Configuration
------------------------------------------------

local OverlayTargetConfig = {

    Normal = {

        BaseChildCount =
            BASE_CHILD_COUNT_NORMAL,

        FindWidgets = function()

            return FindAllOf(
                "WBP_PalCharacterSlotBase_C"
            )

        end,

    },

    Party = {

        BaseChildCount =
            BASE_CHILD_COUNT_PARTY,

        FindWidgets = function()

            return FindAllOf(
                "WBP_IngameMenu_PalBox_PalList_C"
            )

        end,

    },

    Hatch = {

        BaseChildCount =
            BASE_CHILD_COUNT_HATCH,

        -- Canvas_Pal represents the entire 450x80 hatch-result row,
        -- while the Pal icon occupies the 80x80 area at its left edge.
        -- Use the left edge of the Canvas as the horizontal coordinate origin
        -- so the existing 80x80 Overlay layout maps directly onto the icon.
        AnchorX = 0.0,
        AnchorY = 0.5,
        OriginX = 0.0,
        OriginY = 0.5,

        -- Small fixed alignment correction for the hatch-result Pal icon.
        OffsetX = 3,
        OffsetY = -3,

        FindWidgets = function()

            return FindAllOf(
                "WBP_Ingame_Incubator_AllOpen_List_C"
            )

        end,

    },

}

-- Return whether an Overlay target type is enabled for runtime updates.
-- Normal PalBox / Preset targets are always enabled. Party and Hatch targets
-- follow their screen-specific DisplayOption settings.
local function IsOverlayTargetEnabled(targetType)

    if targetType == "Party" then
        return Config.DisplayOption.EnablePartyDisplay == true
    end

    if targetType == "Hatch" then
        return Config.DisplayOption.EnableHatchDisplay == true
    end

    return true

end

-- Number of Widgets added by this MOD.
-- Automatically follows changes to OverlayLayout.
local ADDED_CHILD_COUNT = #OverlayLayout

-- Widgets for which no Overlay should be added or updated.
--
-- PalBox and other HUDs or special UI elements may also contain Slots
-- derived from WBP_PalCharacterSlotBase_C, so the Slot type alone
-- cannot distinguish PalBox Slots.
-- Therefore, the Widget's Outer hierarchy is inspected and matching parent
-- class names registered here are excluded from Overlay creation and updates.
--
-- Add a Widget class name here when its Overlay should not be displayed in a new UI.
-- Conversely, adding a normal PalBox Slot here will prevent its Overlay from being displayed.
local ExcludedWidgetNames = {

    ["WBP_Ingame_PalHPGauge_C"] = true,         -- Summoned Pal icon outside the main screen
    ["WBP_IngameMenu_Task_SimpleList_C"] = true, -- Pal icon at the upper-right of the base HUD
    ["WBP_PalCraftInfo_Pal_C"] = true,          -- Pal icon currently working at a base facility
    ["WBP_PalLoupe_C"] = true,                  -- Selected summoned Pal icon at the lower-left of the HUD
    ["WBP_PalLvExp_C"] = true,                  -- Pal icon receiving experience at the upper-left of the HUD
    ["WBP_IngameProgress_C"] = true,            -- Pal icon for construction progress

}

-- Display colors used according to Passive Skill Rank.
--
-- Only R / G / B are defined; Alpha is not defined.
-- SetImageColor() / SetTextColor() use the value currently held by the Widget
-- for components that are not specified in Color.
-- Therefore, leaving Alpha undefined here preserves the existing transparency
-- configured in Config.UI.
local PassiveSkillColor = {

    Red = {
        R = 1.0,
        G = 0.049707,
        B = 0.049707,
    },

    White = {
        R = 0.783538,
        G = 0.964686,
        B = 1.0,
    },

    Yellow = {
        R = 1.0,
        G = 0.751014,
        B = 0.05,
    },

    Green = {
        R = 0.138432,
        G = 1.0,
        B = 0.684092,
    }

}

-- Text colors used according to the value range of individual values (Talent).
local TalentColor = {

    Blue = {
        R = 0.38132602,
        G = 0.8713671,
        B = 1.0,
    },

    Yellow = {
        R = 1.0,
        G = 0.7539063,
        B = 0.015625,
    },

    Green = {
        R = 0.012983024,
        G = 1.0,
        B = 0.27618778,
    }

}

------------------------------------------------
-- Hook Targets
------------------------------------------------

-- Palworld Blueprint / native Functions targeted by Hooks.
--
-- These Hooks are used to detect various PalBox, Party Pal,
-- Pal Condense, and equipment-related events.
--
-- If a game update changes any of the Function names or Blueprint paths,
-- the corresponding entries must be reviewed.
local HookTarget = {

    -- Called when a PalBox slot is updated with a Pal.
    SlotUpdate =
    "/Game/Pal/Blueprint/UI/Thumbnails/Character/WBP_PalCommonCharacterSlot.WBP_PalCommonCharacterSlot_C:On Update Slot Binded",

    -- Called when a PalBox slot becomes empty.
    SlotEmpty =
    "/Game/Pal/Blueprint/UI/Thumbnails/Character/WBP_PalCommonCharacterSlot.WBP_PalCommonCharacterSlot_C:On Set Empty Binded",

    -- Called when a Pal preset is set up.
    SetupPreset =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_PresetList.WBP_IngameMenu_PalBox_PresetList_C:SetupPreset",

    -- Native result callback for the Pal condensation / rank-up model.
    -- Unlike the PalCondense UI Blueprint, this /Script/ UFunction is available
    -- without waiting for the condensation screen to be loaded.
    CondensationOperationResult =
    "/Script/Pal.PalMapObjectRankUpCharacterModel:ReceiveOperationResult",

    -- Called when the equipped slot changes.
    -- Used to detect whether Ability Glasses are equipped
    -- and update the Ability Glasses state accordingly.
    OnEquipSlotChanged =
    "/Script/Pal.PalPlayerInventoryData:OnEquipSlotChanged",

    -- Called when the Party Pal list is set up.
    -- Used to initialize or update overlays on Party Pal slots.
    SetupPartyPal =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_PalList.WBP_IngameMenu_PalBox_PalList_C:Setup",

    -- Called when a Party Pal list slot is updated.
    -- Used to update the overlay for the affected Party Pal slot.
    OnUpdateHandleSlot =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_PalList.WBP_IngameMenu_PalBox_PalList_C:OnUpdateHandleSlot",

    -- Deterministic lifetime boundary for Party Pal rows in the normal PalBox.
    -- WBP_IngameMenu_PalBox_PalList_C has no Blueprint Destruct event of its
    -- own, while the containing PalStorageMenu does. Reclaim all Party Pool
    -- Entries when that screen is destroyed.
    PartyPoolHostDestruct =
    "/Game/Pal/Blueprint/UI/PalStorage/WBP_PalStorageMenu.WBP_PalStorageMenu_C:Destruct",

    -- Native client notification fired when multi-hatching completes.
    -- Used only as a just-in-time registration point for the lazily loaded
    -- hatch-result Blueprint hooks.
    NotifyMultiHatchComplete =
    "/Script/Pal.PalPlayerState:NotifyMultiHatchComplete_ToClient",

    -- Called when one entry on the multi-hatch result screen is populated.
    -- IndividualParam directly identifies the newly hatched Pal.
    SetupHatchResult =
    "/Game/Pal/Blueprint/UI/UserInterface/InGame/Incubator/WBP_Ingame_Incubator_AllOpen_List.WBP_Ingame_Incubator_AllOpen_List_C:Setup",

    -- Called when the multi-hatch result screen is closed.
    -- Used to release the temporary DisplayMode CommonUI bridge.
    HatchResultClose =
    "/Game/Pal/Blueprint/UI/UserInterface/InGame/Incubator/WBP_Ingame_Incubator_AllOpen.WBP_Ingame_Incubator_AllOpen_C:OnClose",

    -- BindButtonEvents runs after a SlotButton has been created but before
    -- that Button's Setup(targetSlot) call. This is the earliest narrow
    -- Blueprint point where the owning ScrollList and MyCharacterSlotWidget
    -- are both available, so persistent-Pool eligibility can be recorded
    -- before SlotUpdate fires from Setup().
    PalCharacterScrollListBindButtonEvents =
    "/Game/Pal/Blueprint/UI/CommonWidget/CommonScrollList/WBP_PalCharacterScrollList.WBP_PalCharacterScrollList_C:BindButtonEvents",

    PalCharacterScrollListAddSlotButton =
    "/Game/Pal/Blueprint/UI/CommonWidget/CommonScrollList/WBP_PalCharacterScrollList.WBP_PalCharacterScrollList_C:AddSlotButtonToScrollList",

    PalCharacterScrollListClearInnerChildren =
    "/Game/Pal/Blueprint/UI/CommonWidget/CommonScrollList/WBP_PalCharacterScrollList.WBP_PalCharacterScrollList_C:ClearInnnerChildren",

    -- Common SlotButton lifetime end. Used to park any Entry owned by the
    -- exact Button and to prevent late inner SlotUpdate from reacquiring it.
    CommonCharacterSlotButtonDestruct =
    "/Game/Pal/Blueprint/UI/Thumbnails/Character/WBP_PalCommonCharacterSlotButton.WBP_PalCommonCharacterSlotButton_C:Destruct",

    -- Common live-start points. These pre-Hooks run before the Button forwards
    -- Setup* to its inner CharacterSlot Widget, so the exact Button/Widget
    -- identity is available before any resulting SlotUpdate can fire.
    CharacterSlotButtonBaseSetup =
    "/Game/Pal/Blueprint/UI/Thumbnails/Character/Base/WBP_PalCharacterSlotButtonBase.WBP_PalCharacterSlotButtonBase_C:Setup",

    CharacterSlotButtonBaseSetupByCharacterID =
    "/Game/Pal/Blueprint/UI/Thumbnails/Character/Base/WBP_PalCharacterSlotButtonBase.WBP_PalCharacterSlotButtonBase_C:SetupByCharacterID",

    CharacterSlotButtonBaseSetupByIndividualId =
    "/Game/Pal/Blueprint/UI/Thumbnails/Character/Base/WBP_PalCharacterSlotButtonBase.WBP_PalCharacterSlotButtonBase_C:SetupByIndividualId",

    CharacterSlotButtonBaseSetupBySaveParameter =
    "/Game/Pal/Blueprint/UI/Thumbnails/Character/Base/WBP_PalCharacterSlotButtonBase.WBP_PalCharacterSlotButtonBase_C:SetupBySaveParameter",

}

------------------------------------------------
-- Asset Paths
------------------------------------------------

-- Paths to the Palworld standard assets used by the MOD.
--
-- This MOD does not create its own Textures or DataTables;
-- it loads and uses existing assets included in Palworld.
--
-- The paths listed here are affected if a game update changes
-- the location or name of an asset.
--
-- To use a new asset, first add its path to this table,
-- then load it through ResourcePaths.
local AssetPath = {

    Class = {

        Text = "/Game/Pal/Blueprint/UI/PalTextBlock/BP_PalTextBlock.BP_PalTextBlock_C",

        Image = "/Script/UMG.Image",

        Canvas = "/Script/UMG.CanvasPanel",

    },

    Texture = {

        MaleGender = "/Game/Pal/Texture/UI/Main_Menu/T_Icon_PanGender_Male.T_Icon_PanGender_Male",

        FemaleGender = "/Game/Pal/Texture/UI/Main_Menu/T_Icon_PanGender_Female.T_Icon_PanGender_Female",

        Rank = "/Game/Pal/Texture/UI/InGame/T_icon_enemy_rarity_01.T_icon_enemy_rarity_01",

        Soul = "/Game/Pal/Texture/UI/IngameMenu/T_icon_buildup.T_icon_buildup",

        BaseBand = "/Game/Pal/Material/UI/Texture/T_UI_BaseBand.T_UI_BaseBand",

        -- Explicit flat white texture used by Passive Skill bars/backgrounds.
        -- Previous builds accidentally relied on the white placeholder shown
        -- when T_UI_BaseBand failed to load; use the intended solid resource instead.
        SolidWhite = "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture",

        Friendship = "/Game/Pal/Texture/UI/Main_Menu/T_Icon_PalFriendship_Color.T_Icon_PalFriendship_Color",

    },

    DataTable = {

        palMonsterParameter = "/Game/Pal/DataTable/Character/DT_PalMonsterParameter.DT_PalMonsterParameter",

        PassiveSkill = "/Game/Pal/DataTable/PassiveSkill/DT_PassiveSkill_Main.DT_PassiveSkill_Main",

        SkillName = "/Game/Pal/DataTable/Text/DT_SkillNameText.DT_SkillNameText",

        FriendshipRank = "/Game/Pal/DataTable/Friendship/DT_FriendshipRankTable.DT_FriendshipRankTable",

    },

}

------------------------------------------------
-- Native Objects
------------------------------------------------

-- PalUtility is used to obtain the local player inventory from a Widget.

local PAL_UTILITY = "/Script/Pal.Default__PalUtility"

------------------------------------------------
-- Shared Normal / Preset Overlay Pool
------------------------------------------------
--
-- Prewarm complete Normal-layout Overlay entries shared by the
-- Normal PalBox and Preset screen. Every Entry always contains all 34 Widgets
-- defined by OverlayLayout. No display-mode-based lazy Widget creation is used.
--
-- 80 is the startup target because runtime testing showed 30 normal PalBox
-- Entries remaining active while 50 Preset slots are displayed. It is not a
-- hard maximum; the shared Pool grows only when more than 80 Normal-layout
-- slots are simultaneously required and retains that high-water capacity.
local SHARED_OVERLAY_POOL_ENABLED = true
local SHARED_OVERLAY_POOL_TARGET_COUNT = 80

-- Party Pal rows use a separate persistent Pool because their layout differs
-- from Normal PalBox Slots. Vanilla uses five Party rows; compatibility MODs
-- may create more, so five is only the prewarm target and synchronous growth
-- remains available when required.

local PAL_TEXT_BLOCK_ASSET =
    "/Game/Pal/Blueprint/UI/PalTextBlock/BP_PalTextBlock"

------------------------------------------------
-- Controller DisplayMode Input
------------------------------------------------
--
-- A DisplayMode entry with GamepadButton uses the same CommonUI Action for
-- both its configured keyboard key and Gamepad input. Keyboard-only DisplayMode
-- entries continue to use RegisterKeyBind().
--
-- Two CharacterCreation Action rows are borrowed only while the PalBox
-- CommonUI bridge exists. They are not used by the normal PalBox UI.
--
-- CharacterCreation_Randomize:
--     Actual DisplayMode CommonUI Action.
--
-- CharacterCreation_ToggleEquip:
--     Normally the disabled second PageControlAction parameter. On the Preset
--     screen only, its Keyboard/Mouse key is Middle Mouse Button and its
--     Gamepad key is Square / X for Preset reorder.
------------------------------------------------

local DISPLAY_MODE_CONTROLLER_OWNER =
    "PalIconInfo.DisplayMode"

local DISPLAY_MODE_ACTION =
    "CharacterCreation_Randomize"

local DISPLAY_MODE_UNUSED_ACTION =
    "CharacterCreation_ToggleEquip"

-- On the Pal Preset screen the normally unused Prev Page Action is borrowed
-- for the Swap Preset Action Bar guide and for the Square / X gamepad input.
--
-- Middle Mouse is written to the Action row so CommonUI can render its mouse
-- glyph. Actual Middle Mouse input uses RegisterKeyBind because the
-- WBP_BoxPalListBase PageControlAction path does not dispatch that mouse button
-- to its Pressed callback. Outside the Preset screen this row remains disabled.
local PRESET_SWAP_MOUSE_KEY =
    "MiddleMouseButton"

local PRESET_SWAP_GAMEPAD_KEY =
    "Gamepad_FaceButton_Left"

local PRESET_SWAP_GUIDE_DISPLAY_NAME =
    "Swap Preset"

-- Windows VK_MBUTTON. Used only for actual Middle Mouse input; CommonUI above
-- supplies the mouse glyph in the Action Bar.
local PRESET_SWAP_MOUSE_KEY_CODE = 0x04

local PRESET_SWAP_SELECTED_OPACITY = 0.55

-- Display name kept on the borrowed CommonUI Action row.
local DISPLAY_MODE_GUIDE_DISPLAY_NAME =
    "Display Mode"

-- User-facing controller button names mapped to Unreal FKey names.
--
-- The friendly names are also used by DarnMenu.
local DISPLAY_MODE_GAMEPAD_BUTTON_ALIASES = {

    ["Right Stick Press"] = "Gamepad_RightThumbstick",
    ["Right Stick Up"]    = "Gamepad_RightStick_Up",
    ["Right Stick Down"]  = "Gamepad_RightStick_Down",
    ["Right Stick Left"]  = "Gamepad_RightStick_Left",
    ["Right Stick Right"] = "Gamepad_RightStick_Right",

}

local PAL_BOX_LIST_BASE_ASSET =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase"

local PAL_BOX_LIST_BASE_CLASS =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C"

local WIDGET_BLUEPRINT_LIBRARY =
    "/Script/UMG.Default__WidgetBlueprintLibrary"

local PRESET_SWAP_LIST_ASSET =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_PresetList"

local DISPLAY_MODE_HOOK_SET_MAX_PAGE =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C:SetMaxPageNum"

local DISPLAY_MODE_HOOK_DESTRUCT =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C:Destruct"

-- Preset screen lifetime hooks.
-- The DisplayMode bridge is created after the Preset screen finishes OnSetup
-- and released when that exact screen is destroyed.
local DISPLAY_MODE_HOOK_PRESET_SETUP =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_Preset.WBP_IngameMenu_PalBox_Preset_C:OnSetup"

local DISPLAY_MODE_HOOK_PRESET_DESTRUCT =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_Preset.WBP_IngameMenu_PalBox_Preset_C:Destruct"

local DISPLAY_MODE_HOOK_PRESSED =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C:OnPressedNextPageInputInternal"

local PRESET_SWAP_HOOK_PRESSED =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C:OnPressedPrevPageInputInternal"

local PRESET_SWAP_HOOK_DELETE =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_Preset.WBP_IngameMenu_PalBox_Preset_C:DeletePreset"

local DisplayModeControllerBridge = nil
local DisplayModeControllerBridgeName = nil

-- Transient identity string of the real WBP_BoxPalListBase that owns this
-- bridge. No live real PalBox UObject is retained.
local DisplayModeControllerOwnerName = nil

-- Transient path of the real PalBox list that was active immediately before
-- entering the Preset screen. Only the path string is retained; the live
-- PalBox UObject is reacquired with StaticFindObject() when returning.
local DisplayModePresetReturnPalBoxPath = nil

-- Identifies which screen currently owns the temporary CommonUI bridge.
-- Values: "PalBox", "Preset", "Hatch".
local DisplayModeControllerOwnerKind = nil

local DisplayModeControllerCreating = false
local DisplayModeControllerDestroying = false
local DisplayModeControllerReady = false

-- Preset reorder selection is intentionally stored as scalar state only.
-- No Preset screen or row UObject is retained across input events.
local PresetSwapSelectedIndex = nil
local PresetSwapSelectedOriginalOpacity = nil

local DisplayModeBoxPalListBaseClass = nil
local DisplayModeWidgetBlueprintLibrary = nil
------------------------------------------------
-- Forward Declarations
------------------------------------------------

local GetPalSlotCanvas
local GetOverlayWidgets
local SharedOverlayPool
local UpdateOverlayVisibility
local UpdateOverlayData
local UpdateSlotOverlay
local AbilityGlassesEquipped = false
local AbilityGlassesStateInitialized = false
local UpdateAbilityGlassesState

local ApplyDisplayMode
local AdvanceDisplayModeState
local RegisterDisplayModeHotKeys
local ConfigWatchLoop
local SafeRegisterHook
local RefreshDisplayModeControllerBinding
local RefreshVanillaR3GuideVisibility
local HasVisibleStandaloneDisplayModeTarget
local RefreshVisiblePalBoxOverlays

------------------------------------------------
-- Configuration Watch & Reload
------------------------------------------------

-- Apply a newly loaded PalIconInfoConfig table to the running MOD.
--
-- File reading, syntax validation, and change detection are handled
-- by ConfigManager. This function only updates the runtime
-- state that belongs specifically to PalIconInfo.
local function ReloadConfig(newConfig)

    if type(newConfig) ~= "table" then
        return false,
            "Reloaded config is not a table."
    end

    ------------------------------------------------
    -- Ensure ActiveDisplay exists first
    --
    -- Immediately after replacing Config with the new table,
    -- ActiveDisplay may not exist.
    --
    -- If the SlotUpdate Hook fires during reload,
    --
    -- Config.ActiveDisplay.Number
    --
    -- may be nil at this point, so the ActiveDisplay from before
    -- the replacement is retained.
    ------------------------------------------------

    if newConfig.ActiveDisplay == nil then

        if Config and Config.ActiveDisplay then

            newConfig.ActiveDisplay =
                Config.ActiveDisplay

        end

    end

    ------------------------------------------------
    -- Replace Config
    ------------------------------------------------

    Config = newConfig

    Log("Config Reloaded")

    ------------------------------------------------
    -- Adjust when the number of states is reduced by a Config change
    ------------------------------------------------

    for keyCode, stateIndex in pairs(DisplayModeState) do

        local states =
            Config.DisplayMode
            and Config.DisplayMode[keyCode]

        if states then

            local count = #states

            if count <= 0 then

                DisplayModeState[keyCode] = nil

            elseif stateIndex > count then

                DisplayModeState[keyCode] = 1

            end

        else

            ------------------------------------------------
            -- When the key itself is removed from Config
            ------------------------------------------------

            DisplayModeState[keyCode] = nil

        end

    end

    ------------------------------------------------
    -- Register newly added hotkeys
    ------------------------------------------------

    RegisterDisplayModeHotKeys()

    ------------------------------------------------
    -- Rebuild ActiveDisplay from the new Config
    ------------------------------------------------

    ApplyDisplayMode()

    ------------------------------------------------
    -- Apply Controller DisplayMode input changes
    ------------------------------------------------
    --
    -- If the PalBox bridge currently exists, update the borrowed UI Action row
    -- and re-register its CommonUI binding without rebuilding the bridge.
    ------------------------------------------------

    if RefreshDisplayModeControllerBinding then

        local refreshed, refreshError =
            RefreshDisplayModeControllerBinding()

        if refreshed == false then

            Log(
                "Controller DisplayMode Config Reload Failed:",
                refreshError
            )

        end

    end

    ------------------------------------------------
    -- Update vanilla guides that conflict with R3
    ------------------------------------------------

    if RefreshVanillaR3GuideVisibility then

        RefreshVanillaR3GuideVisibility()

    end

    ------------------------------------------------
    -- Refresh persistent Pool static UI settings
    ------------------------------------------------
    -- Pool Entries normally apply layout/font/static color only once.
    -- A Config reload can change those values, so reapply them once here
    -- before refreshing visible Pal data.

    if SharedOverlayPool
        and SharedOverlayPool.RefreshStaticLayoutAllEntries then

        SharedOverlayPool.RefreshStaticLayoutAllEntries(
            "Config reload"
        )

    end

    if PartyOverlayPool
        and PartyOverlayPool.RefreshStaticLayoutAllEntries then

        PartyOverlayPool.RefreshStaticLayoutAllEntries(
            "Config reload"
        )

    end

    ------------------------------------------------
    -- Refresh visible PalBox-related Overlays
    ------------------------------------------------
    -- Re-evaluate the MOD Overlay on visible Box / Base / Party Pal Slots
    -- directly from their currently bound Slots. This applies layout,
    -- visibility, and display-option changes without rebuilding Palworld's
    -- current PalBox page or disturbing controller focus.
    ------------------------------------------------

    if RefreshVisiblePalBoxOverlays then
        RefreshVisiblePalBoxOverlays("Config reload")
    end

    return true

end


-- Check whether PalIconInfoConfig.lua has changed since the previous
-- manager check. The manager loads and validates the changed file,
-- then passes the resulting table to ReloadConfig().
local function CheckConfigChanged()

    local _, errorMessage =
        ConfigManagerInstance:CheckChanged(
            ReloadConfig
        )

    if errorMessage then

        Log(
            "Config Reload Failed:",
            errorMessage
        )

    end

end


------------------------------------------------
-- Resources Loader
------------------------------------------------

-- List of assets defined in AssetPath
-- to be loaded by LoadRequiredObjects().
--
-- AssetPath manages "asset paths inside the game",
-- while ResourcePaths manages the mapping between
-- "names used within this MOD" and
-- "corresponding asset paths".
--
-- For example,
--
--     texSoul = AssetPath.Texture.Soul
--
-- allows subsequent processing to use Res.texSoul
-- instead of directly specifying the long asset path.
local ResourcePaths = {

    textClass = AssetPath.Class.Text,

    imageClass = AssetPath.Class.Image,

    canvasClass = AssetPath.Class.Canvas,

    texMale = AssetPath.Texture.MaleGender,

    texFemale = AssetPath.Texture.FemaleGender,

    texRankStar = AssetPath.Texture.Rank,

    texSoul = AssetPath.Texture.Soul,

    texSolidWhite = AssetPath.Texture.SolidWhite,

    texFriendship = AssetPath.Texture.Friendship,

    palMonsterParameter = AssetPath.DataTable.palMonsterParameter,

    passiveSkillTable = AssetPath.DataTable.PassiveSkill,

    skillNameTable = AssetPath.DataTable.SkillName,

    friendshipRankTable = AssetPath.DataTable.FriendshipRank,

}

-- Obtain the required UE objects and store them in Res.
--
-- StaticFindObject() may fail to obtain an asset immediately after game startup
-- if the target asset has not been loaded yet.
--
-- Therefore, when this function returns false,
-- the caller does not immediately stop the entire MOD,
-- but attempts to load the assets again
-- when a later Hook is triggered.
--
-- Objects that have already been obtained are stored in UObjectCache
-- so that subsequent searches can be skipped.
--
-- Returns false if even one required object cannot be obtained.
-- The caller does not set ResourceReady to true at that point,
-- and calls this function again when a later Hook is triggered.
local function LoadRequiredObjects()

    for name, path in pairs(ResourcePaths) do

        local obj = UObjectCache[name]

        ------------------------------------------------
        -- Reuse a Texture only after it has been successfully anchored in a
        -- hidden persistent UImage Brush. If preload/anchor failed, fall back
        -- to the normal StaticFindObject() path.
        if not obj then

            local isTexture =
                name == "texMale"
                or name == "texFemale"
                or name == "texRankStar"
                or name == "texSoul"
                or name == "texSolidWhite"
                or name == "texFriendship"

            if isTexture then

                local preloadState =
                    PalIconRuntime.PrePalBoxResourcePreload

                if preloadState
                    and preloadState.Complete == true
                    and preloadState.Verified
                    and preloadState.Verified[name] == true
                    and preloadState.AnchorSuccess
                    and preloadState.AnchorSuccess[name] == true
                    and preloadState.TextureKeepAlive then

                    obj =
                        preloadState.TextureKeepAlive[name]

                    if obj then
                        UObjectCache[name] = obj
                    end

                end

            end

        end

        if not obj then

            obj = StaticFindObject(path)

            if obj then
                UObjectCache[name] = obj
            end

        end

        if not obj then
            return false
        end

        Res[name] = obj

    end

    return true
end


------------------------------------------------
-- Required UObject Reference Warm-up
------------------------------------------------
-- Reduce the first PalBox-open cost without changing resource readiness or
-- Image-brush timing. This warm-up only asks StaticFindObject() for already
-- loaded Widget Classes and DataTables, and stores successful results in the
-- same UObjectCache used by LoadRequiredObjects().
--
-- Texture resources are deliberately excluded. StaticFindObject() can expose a
-- Texture UObject before the PalBox-side resource load has completed; caching
-- that early reference caused SetBrushFromTexture() to display a white
-- placeholder. Texture objects therefore remain on the normal first-use path.
--
-- Important safety properties:
--   - never calls LoadAsset();
--   - never sets ResourceReady;
--   - never writes Res;
--   - never caches Texture resources;
--   - never applies Texture brushes;
--   - missing assets remain on the normal synchronous first-use path.
PalIconRuntime.ResourceReferenceWarmup = {
    Started = false,
    Complete = false,
    Pending = {},
    Index = 1,
    RetryPass = 0,
    MaxRetryPasses = 4,
}

function PalIconRuntime.ResourceReferenceWarmupBuildPending()

    local state = PalIconRuntime.ResourceReferenceWarmup

    state.Pending = {}
    state.Index = 1

    for name, path in pairs(ResourcePaths) do

        -- Texture UObjects must be resolved at normal first use. Caching them
        -- here can preserve an object reference obtained before the texture's
        -- PalBox-side load has completed, resulting in a white placeholder.
        local isTexture =
            name == "texMale"
            or name == "texFemale"
            or name == "texRankStar"
            or name == "texSoul"
            or name == "texSolidWhite"
            or name == "texFriendship"

        if not isTexture
            and not UObjectCache[name] then

            state.Pending[#state.Pending + 1] = {
                Name = name,
                Path = path,
            }

        end

    end

    return #state.Pending

end

function PalIconRuntime.ResourceReferenceWarmupStep()

    if not IsCurrentRuntimeGeneration()
        or ResourceReady then
        return
    end

    local state = PalIconRuntime.ResourceReferenceWarmup

    if state.Complete then
        return
    end

    local item = state.Pending[state.Index]

    if item then

        local okFind, obj =
            pcall(
                StaticFindObject,
                item.Path
            )

        if okFind and obj then
            UObjectCache[item.Name] = obj
        end

        state.Index = state.Index + 1

        ExecuteWithDelay(
            16,
            PalIconRuntime.ResourceReferenceWarmupStep
        )

        return
    end

    state.RetryPass = state.RetryPass + 1

    local missing =
        PalIconRuntime.ResourceReferenceWarmupBuildPending()

    if missing == 0 then

        state.Complete = true

        DebugLog(
            "[ResourceRefWarmup] Complete"
        )

        return
    end

    if state.RetryPass >= state.MaxRetryPasses then

        state.Complete = true

        DebugLog(
            "[ResourceRefWarmup] Stopped with",
            missing,
            "objects still unavailable"
        )

        return
    end

    ExecuteWithDelay(
        250,
        PalIconRuntime.ResourceReferenceWarmupStep
    )

end

function PalIconRuntime.StartResourceReferenceWarmup()

    local state = PalIconRuntime.ResourceReferenceWarmup

    if state.Started
        or state.Complete
        or ResourceReady then
        return
    end

    state.Started = true

    if PalIconRuntime.ResourceReferenceWarmupBuildPending() == 0 then
        state.Complete = true
        return
    end

    ExecuteWithDelay(
        100,
        PalIconRuntime.ResourceReferenceWarmupStep
    )

end

------------------------------------------------
-- Pre-PalBox Texture Preload
------------------------------------------------
-- Load the six Texture assets on the first known game-thread callback, before
-- PalBox use. LoadAsset() is given the full object path and its actual return
-- contract is validated: loaded UObject, was_asset_found, did_asset_load.
--
-- The early UObject wrapper is intentionally not reused later. Once the hidden
-- persistent ParkingRoot exists, each Texture is reacquired with LoadAsset()
-- and immediately anchored in a UE-owned UImage Brush. This avoids retaining a
-- transient Lua RemoteObject wrapper across startup / map-transition timing.
PalIconRuntime.PrePalBoxResourcePreload = {
    Started = false,
    Complete = false,
    TextureKeepAlive = {},
    AnchorWidgets = {},
    LoadMs = {},
    Verified = {},
    AnchorReadback = {},
    AnchorSuccess = {},
    NonTextureMs = 0,
    Anchored = false,
    AnchorCount = 0,
    AnchorReadbackCount = 0,
    AnchorMs = 0,
    Items = {
        { Name = "texSolidWhite", Path = AssetPath.Texture.SolidWhite },
        { Name = "texFemale", Path = AssetPath.Texture.FemaleGender },
        { Name = "texFriendship", Path = AssetPath.Texture.Friendship },
        { Name = "texMale", Path = AssetPath.Texture.MaleGender },
        { Name = "texSoul", Path = AssetPath.Texture.Soul },
        { Name = "texRankStar", Path = AssetPath.Texture.Rank },
    },
}

function PalIconRuntime.StartPrePalBoxResourcePreload()

    local state = PalIconRuntime.PrePalBoxResourcePreload

    if state.Started
        or state.Complete
        or ResourceReady then
        return
    end

    state.Started = true

    -- Opportunistically cache non-Texture resources while already on the game
    -- thread. Missing objects remain on the normal LoadRequiredObjects() path.
    local nonTextureStart = os.clock()

    for name, path in pairs(ResourcePaths) do

        local isTexture =
            name == "texMale"
            or name == "texFemale"
            or name == "texRankStar"
            or name == "texSoul"
            or name == "texSolidWhite"
            or name == "texFriendship"

        if not isTexture
            and not UObjectCache[name] then

            local okFind, obj =
                pcall(
                    StaticFindObject,
                    path
                )

            if okFind and obj then
                UObjectCache[name] = obj
            end

        end

    end

    state.NonTextureMs =
        (os.clock() - nonTextureStart) * 1000

    local verifiedCount = 0
    local preloadStart = os.clock()

    for _, item in ipairs(state.Items) do

        local loadStart = os.clock()
        local okCall, loadedObject, wasFound, didLoad =
            pcall(
                LoadAsset,
                item.Path
            )

        state.LoadMs[item.Name] =
            (os.clock() - loadStart) * 1000

        local loadValid = false

        if okCall and loadedObject then
            pcall(function()
                loadValid = loadedObject:IsValid()
            end)
        end

        local verified =
            okCall
            and wasFound == true
            and didLoad == true
            and loadValid

        state.Verified[item.Name] = verified

        if verified then
            verifiedCount = verifiedCount + 1
        else
            Log(
                "[TexturePreload] Failed:",
                item.Name,
                "callOk=" .. tostring(okCall),
                "wasFound=" .. tostring(wasFound),
                "didLoad=" .. tostring(didLoad),
                "valid=" .. tostring(loadValid),
                "path=" .. tostring(item.Path)
            )
        end

    end

    state.TextureLoadComplete = true

    DebugLog(
        "[TexturePreload] Complete:",
        verifiedCount,
        "/",
        #state.Items,
        "Textures /",
        string.format("%.3fms", (os.clock() - preloadStart) * 1000)
    )

end

------------------------------------------------
-- Utility
------------------------------------------------

-- Interprets a dot-separated path as a hierarchy of Lua Tables
-- and assigns a value at the specified location.
--
-- OverlayLayout manages Widgets using strings such as
--
--     "PassiveSkill.Bar.Image_Background"
--
-- This function converts the string path into
--
--     overlay.PassiveSkill.Bar.Image_Background
--
-- as a Lua Table hierarchy.
--
-- Elements consisting only of numbers are treated as array indices.
--
-- For example,
--
--     "Image_PassiveSkillIcon.1"
--
-- is stored as
--
--     overlay.Image_PassiveSkillIcon[1]
--
-- This is a generic helper function that avoids the need
-- to manually reconstruct the Overlay Table when OverlayLayout is modified.
local function SetPath(tbl, path, value)

    local current = tbl

    local parts = {}
    for part in path:gmatch("[^.]+") do
        parts[#parts+1]=part
    end

    for i = 1, #parts - 1 do

        local key = tonumber(parts[i]) or parts[i]

        if current[key] == nil then
            current[key] = {}
        end

        current = current[key]

    end

    local key = tonumber(parts[#parts]) or parts[#parts]

    current[key] = value

end



-- Get the class name of the UObject at the specified Outer level.
-- level = 0: the object itself
-- level = 1: the object's Outer
-- level = 2: the Outer's Outer
-- Returns nil if the requested Outer level cannot be accessed.
local function GetOuterClassName(obj, level)

    if not obj then
        return nil
    end

    level = level or 0

    if level < 0 then
        return nil
    end

    local ok, result =
        pcall(function()

            local target = obj

            -- level 0 = the object itself
            if level == 0 then
                local class = target:GetClass()

                if not class then
                    return nil
                end

                local fname = class:GetFName()

                if not fname then
                    return nil
                end

                return fname:ToString()
            end

            for i = 1, level do

                target = target:GetOuter()

                if not target then
                    return nil
                end

                local class = target:GetClass()

                if not class then
                    return nil
                end

                local fname = class:GetFName()

                if not fname then
                    return nil
                end

                local className = fname:ToString()

                -- Stop traversing once Package is reached.
                if className == "Package" then
                    if i == level then
                        return className
                    end

                    return nil
                end

                if i == level then
                    return className
                end

            end

            return nil

        end)

    if not ok then
        return nil
    end

    return result

end
------------------------------------------------
-- Display Mode
------------------------------------------------

-- Combines the current state of each hotkey configured in Config.DisplayMode
-- using OR logic to determine which Overlay items should actually be displayed.
--
-- Multiple display states can be configured for a single hotkey.
-- Multiple hotkeys can also be registered.
--
-- If the same item is true for multiple hotkeys,
-- it is displayed using OR logic.
--
-- For example,
--
--     F1 → Number = true
--     F2 → Level  = true
--
-- in this case,
--
--     Number = true
--     Level  = true
--
-- is the result.
--
-- The display state created here is stored in Config.ActiveDisplay
-- and is used by UpdateOverlayVisibility()
-- to update the visibility of each Overlay Widget.
--
-- Only items set to true in each DisplayMode are treated as display targets.
-- False or unspecified items are not added to the display targets.
-- If the same item is true for multiple keys, the final result remains true.
ApplyDisplayMode = function()

    ------------------------------------------------
    -- Initialize all items as hidden
    ------------------------------------------------

    local display = {

        Number = false,
        Level = false,
        Gender = false,
        Rank = false,
        Soul = false,
        Friendship = false,

        PassiveSkill = {
            Bar  = false,
            Name = false,
        },

        Talent = false,

    }

    ------------------------------------------------
    -- Combine the current state of each hotkey
    ------------------------------------------------

    for keyCode, stateIndex in pairs(DisplayModeState) do

        local states = Config.DisplayMode[keyCode]

        if states then

            local state = states[stateIndex]

            if state then

                ------------------------------------------------
                -- Number
                ------------------------------------------------

                if state.Number == true then
                    display.Number = true
                end

                ------------------------------------------------
                -- Level
                ------------------------------------------------

                if state.Level == true then
                    display.Level = true
                end

                ------------------------------------------------
                -- Gender
                ------------------------------------------------

                if state.Gender == true then
                    display.Gender = true
                end

                ------------------------------------------------
                -- Rank
                ------------------------------------------------

                if state.Rank == true then
                    display.Rank = true
                end

                ------------------------------------------------
                -- Soul
                ------------------------------------------------

                if state.Soul == true then
                    display.Soul = true
                end

                ------------------------------------------------
                -- Friendship
                ------------------------------------------------

                if state.Friendship == true then
                    display.Friendship = true
                end

                ------------------------------------------------
                -- PassiveSkill
                ------------------------------------------------

                if state.PassiveSkill then

                    if state.PassiveSkill.Bar == true then
                        display.PassiveSkill.Bar = true
                    end

                    if state.PassiveSkill.Name == true then
                        display.PassiveSkill.Name = true
                    end

                end

                ------------------------------------------------
                -- Talent
                ------------------------------------------------

                if state.Talent == true then
                    display.Talent = true
                end

            end

        end

    end

    ------------------------------------------------
    -- Update the actual display settings
    ------------------------------------------------

    Config.ActiveDisplay = display

    DebugLog(
        "ActiveDisplay:",
        "Number =", display.Number,
        "Level =", display.Level,
        "Gender =", display.Gender,
        "Rank =", display.Rank,
        "Soul =", display.Soul,
        "Friendship =", display.Friendship,
        "PassiveBar =", display.PassiveSkill.Bar,
        "PassiveName =", display.PassiveSkill.Name,
        "Talent =", display.Talent
    )

end

-- Advance one configured DisplayMode key to its next state and immediately
-- reapply Overlay visibility to currently visible target Slots.
--
-- requireVisibleTarget:
--   true  = keyboard-only RegisterKeyBind path. Do nothing when no supported
--           PalIconInfo Overlay screen is visible.
--   false = CommonUI bridge path. The bridge itself is created only for a
--           supported screen, so no additional visibility guard is required.
AdvanceDisplayModeState =
    function(
        keyCode,
        requireVisibleTarget
    )

        if not Config.DisplayMode then
            return
        end

        local states =
            Config.DisplayMode[
                keyCode
            ]

        if type(states) ~= "table"
            or #states <= 0 then
            return
        end

        ------------------------------------------------
        -- Keyboard-only Overlay target visibility guard
        ------------------------------------------------

        if requireVisibleTarget then

            local okFindBox, boxes =
                pcall(function()

                    return FindAllOf(
                        "WBP_BoxPalListBase_C"
                    )

                end)

            if not okFindBox
                or not boxes then
                return
            end

            local hasVisibleBox = false

            for _, box
                in ipairs(boxes) do

                local okVisible, isVisible =
                    pcall(function()

                        return box:IsVisible()

                    end)

                if okVisible
                    and isVisible then

                    hasVisibleBox = true
                    break

                end

            end

            if not hasVisibleBox
                and not HasVisibleStandaloneDisplayModeTarget() then
                return
            end

        end

        ------------------------------------------------
        -- Advance state
        ------------------------------------------------

        local currentState =
            DisplayModeState[
                keyCode
            ] or 1

        currentState =
            currentState + 1

        if currentState > #states then
            currentState = 1
        end

        DisplayModeState[
            keyCode
        ] = currentState

        ApplyDisplayMode()

        ------------------------------------------------
        -- Reapply visibility to visible Overlay targets
        ------------------------------------------------

        for targetType, targetConfig
            in pairs(OverlayTargetConfig) do

            if not IsOverlayTargetEnabled(
                targetType
            ) then
                goto continueTarget
            end

            local okSlots, slots =
                pcall(function()

                    return
                        targetConfig.FindWidgets()

                end)

            if okSlots
                and slots then

                for _, slot
                    in ipairs(slots) do

                    local okVisible, isVisible =
                        pcall(function()

                            return slot:IsVisible()

                        end)

                    if okVisible
                        and isVisible then

                        local overlay = nil
                        local pooledEntry = nil

                        if targetType == "Normal" then

                            -- Normal PalBox and Preset slots share the same
                            -- Normal-layout persistent Pool.
                            pooledEntry =
                                SharedOverlayPool.GetEntryForWidget(
                                    slot
                                )

                        elseif targetType == "Party"
                            and PartyOverlayPool then

                            pooledEntry =
                                PartyOverlayPool.GetEntryForWidget(
                                    slot
                                )

                        end

                        if pooledEntry then

                            overlay =
                                pooledEntry.Overlay

                        else

                            -- Direct-child targets still need their Canvas.
                            local okCanvas, canvas =
                                pcall(function()

                                    return GetPalSlotCanvas(
                                        slot,
                                        targetType
                                    )

                                end)

                            if okCanvas
                                and canvas then

                                overlay =
                                    GetOverlayWidgets(
                                        canvas,
                                        targetConfig.BaseChildCount
                                    )

                            end

                        end

                        if overlay then

                            UpdateOverlayVisibility(
                                overlay,
                                slot,
                                nil,
                                pooledEntry
                                    and pooledEntry.DynamicCache
                                    or nil
                            )

                        end

                    end

                end

            end

            ::continueTarget::

        end

    end


-- Return true while a non-PalBox screen that displays PalIconInfo Overlay
-- information is visible.
--
-- The configured Keyboard/Gamepad DisplayMode pair normally uses CommonUI.
-- RegisterKeyBind is kept only as a keyboard fallback for these standalone
-- screens when no temporary CommonUI bridge is currently active.
HasVisibleStandaloneDisplayModeTarget = function()

    local targetClasses = {
        "WBP_IngameMenu_PalBox_PresetList_C",
    }

    if Config.DisplayOption.EnableHatchDisplay then

        table.insert(
            targetClasses,
            "WBP_Ingame_Incubator_AllOpen_List_C"
        )

    end

    for _, className in ipairs(targetClasses) do

        local okFind, widgets =
            pcall(function()

                return FindAllOf(
                    className
                )

            end)

        if okFind
            and widgets then

            for _, widget in ipairs(widgets) do

                local okVisible, isVisible =
                    pcall(function()

                        return widget:IsVisible()

                    end)

                if okVisible
                    and isVisible then
                    return true
                end

            end

        end

    end

    return false

end


-- Register DisplayMode keyboard hotkeys.
--
-- A DisplayMode table that defines GamepadButton normally uses one shared
-- CommonUI Action. Its RegisterKeyBind callback is retained only as a keyboard
-- fallback for standalone Overlay screens when no CommonUI bridge is active,
-- avoiding duplicate handling while CommonUI owns the same keyboard key.
--
-- Additional DisplayMode tables without GamepadButton remain keyboard-only
-- and continue to use RegisterKeyBind so the existing multi-hotkey feature
-- is preserved.
--
-- RegisterKeyBind callbacks themselves cannot be unregistered. They therefore
-- call this persistent runtime dispatcher, which is replaced on each MOD
-- execution. Old callbacks become harmless because they resolve the same
-- current dispatcher instead of retaining an old module closure.
PalIconRuntime.DisplayModeKeyHandler =
    function(keyCode)

        if not IsCurrentRuntimeGeneration() then
            return
        end

        local currentStates =
            Config.DisplayMode
            and Config.DisplayMode[
                keyCode
            ]

        if type(currentStates)
            ~= "table" then
            return
        end

        local currentUsesCommonUI =
            type(
                currentStates.GamepadButton
            ) == "string"
            and currentStates.GamepadButton
                ~= ""

        if currentUsesCommonUI then

            -- When a CommonUI bridge exists, both Keyboard and
            -- Gamepad are already handled by that Action.
            if DisplayModeControllerBridge then
                return
            end

            -- Fallback only for standalone Overlay screens if
            -- bridge creation is not available at that moment.
            if not HasVisibleStandaloneDisplayModeTarget() then
                return
            end

            AdvanceDisplayModeState(
                keyCode,
                false
            )

            return

        end

        AdvanceDisplayModeState(
            keyCode,
            true
        )

    end

RegisterDisplayModeHotKeys = function()

    if not Config.DisplayMode then
        return
    end

    for keyCode, states
        in pairs(Config.DisplayMode) do

        if type(states) == "table"
            and #states > 0 then

            if DisplayModeState[
                keyCode
            ] == nil then

                DisplayModeState[
                    keyCode
                ] = 1

            end

            if not RegisteredDisplayModeKeys[
                keyCode
            ] then

                local registeredKeyCode =
                    keyCode

                RegisterKeyBind(
                    registeredKeyCode,
                    function()

                        local handler =
                            PalIconRuntime.DisplayModeKeyHandler

                        if type(handler) == "function" then
                            handler(registeredKeyCode)
                        end

                    end
                )

                RegisteredDisplayModeKeys[
                    keyCode
                ] = true

            end

        end

    end

end

------------------------------------------------
-- Widget Functions
------------------------------------------------

-- Obtain the CanvasPanel used for adding the MOD Overlay Widgets.
--
-- The CanvasPanel is obtained differently depending on the overlay target:
--   Normal: Traverse upward from Text_ReviveTimer through the Widget hierarchy.
--   Party:  Use the CanvasPanel_119 member directly.
--   Hatch:  Resolve Canvas_Pal through Image_PalIcon.Slot.Parent.
--
-- The method for each target depends on Palworld's current Widget structure.
-- No dynamic type checking such as GetClass() is performed.
--
-- If Palworld's Widget structure changes, the corresponding
-- CanvasPanel retrieval method must be reviewed.
GetPalSlotCanvas = function(widget, targetType)

    if not widget then
        return nil
    end

    if targetType == "Party" then

        return widget.CanvasPanel_119

    end

    if targetType == "Hatch" then

        -- Canvas_Pal is not exposed as a UObject member on
        -- WBP_Ingame_Incubator_AllOpen_List_C. Accessing widget.Canvas_Pal
        -- directly therefore produces a TrivialObject in UE4SS.
        --
        -- Image_PalIcon is an exposed UObject member and its CanvasPanelSlot
        -- belongs directly to Canvas_Pal, so obtain the actual CanvasPanel
        -- through the same Slot.Parent route used by the Normal target.
        local image =
            widget.Image_PalIcon

        if not image then
            return nil
        end

        local slot =
            image.Slot

        if not slot then
            return nil
        end

        return slot.Parent

    end

    ------------------------------------------------
    -- Normal PalBox
    ------------------------------------------------

    local text =
        widget.Text_ReviveTimer

    if not text then
        return nil
    end

    local parent =
        text.Slot.Parent

    parent =
        parent.Slot.Parent

    parent =
        parent.Slot.Parent

    return parent

end

-- Inspect the parent classes relevant to Normal-slot processing in one pass.
--
-- WBP_PalCharacterSlotBase_C is also used by UI elements other than the PalBox,
-- so the Slot class alone cannot identify the target. Levels 2-4 of the Outer
-- hierarchy are enough for the known excluded Widgets and the Preset list.
-- Traversal stops at Package so no invalid parent access is attempted beyond it.
--
-- Returns:
--   excludedFromNormalOverlay = parent matches ExcludedWidgetNames
--   belongsToPreset           = parent belongs to the Preset list
local function InspectNormalSlotParents(widget)

    if not widget then
        return false, false, false
    end

    local target = widget
    local belongsToPreset = false
    local excludedFromNormalPool = false

    for level = 1, 4 do

        target = target:GetOuter()

        if not target then
            return false, belongsToPreset, excludedFromNormalPool
        end

        local class = target:GetClass()

        if not class then
            return false, belongsToPreset, excludedFromNormalPool
        end

        local fname = class:GetFName()

        if not fname then
            return false, belongsToPreset, excludedFromNormalPool
        end

        local className = fname:ToString()

        local objectName = nil
        local objectFName = target:GetFName()

        if objectFName then
            objectName = objectFName:ToString()
        end

        if level >= 2 then

            if className == "WBP_IngameMenu_PalBox_PresetList_C" then
                belongsToPreset = true
            end

            -- Persistent Pool Entries are intended for the paged PalBox lists
            -- that are reclaimed through WBP_BoxPalListBase / ClearInnnerChildren.
            --
            -- PalLiftItem, BaseCampPalList, and DisplayCharacterScrollList are
            -- not owned by the paged ScrollList lifecycle. Keep those auxiliary
            -- targets on the existing direct-child route.
            --
            -- WBP_BoxPalList_Party_C is intentionally no longer
            -- excluded here. Its static CommonCharacterSlotButtons now have an
            -- exact Common lifecycle/owner and can use the Shared Pool safely.
            if className == "WBP_PalLiftItem_C"
                or (objectName and objectName:find(
                    "WBP_BaseCampPalList", 1, true
                ) == 1)
                or (objectName and objectName:find(
                    "WBP_DisplayCharacterScrollList", 1, true
                ) == 1) then
                excludedFromNormalPool = true
            end

            if ExcludedWidgetNames[className] then
                DebugLog("EXCLUDED : " .. className .. " (level " .. level .. ")")
                return true, belongsToPreset, excludedFromNormalPool
            end

        end

        if className == "Package" then
            return false, belongsToPreset, excludedFromNormalPool
        end

    end

    return false, belongsToPreset, excludedFromNormalPool

end


-- Determine whether the specified Widget must be excluded from normal Overlay
-- processing. Preset membership is intentionally not treated as a general
-- exclusion because SetupPreset displays Overlay information on those same slots
-- through its own SaveParameter route.
local function IsExcludedWidget(widget)

    local excluded =
        InspectNormalSlotParents(widget)

    return excluded == true

end
-- Change the visibility state of an Overlay Widget.
--
-- This MOD reuses Overlay Widgets after they are created.
-- Therefore, when hiding a Widget, it is not removed;
-- its visibility is changed to Collapsed.
--
-- In UE4/UMG:
--   0 = Visible
--   2 = Collapsed
--
-- Collapsed also removes the Widget from the layout.
--
-- Visibility changes may fail on the UE4SS side,
-- so SetVisibility() is protected with pcall().
local function SetWidgetVisible(widget, visible)

    if not widget then
        return
    end

    pcall(function()

        widget:SetVisibility(
            visible and 0 or 2
        )

    end)

end

-- Create a Widget from the specified UE Widget Class
-- and add it to the Canvas.
--
-- Visibility is disabled immediately after creation.
-- Whether the Widget is actually displayed is determined later by
-- UpdateOverlayVisibility() according to Config.ActiveDisplay.
--
-- Therefore, Overlay Widgets are created in advance,
-- and only the required Widgets are changed to Visible.
local function CreateWidget(class, canvas)

    if not class or not canvas then
        return nil
    end

    local okConstruct, widget =
        pcall(
            StaticConstructObject,
            class,
            canvas
        )

    if not okConstruct or not widget then
        return nil
    end

    -- StaticConstructObject can rarely return a Lua-side value that
    -- cannot be marshalled as a UObject argument by UPanelWidget:AddChild.
    -- Validate the constructed object before crossing that native boundary so
    -- one bad construction attempt cannot abort the entire Pool prewarm.
    local okValid, widgetValid =
        pcall(function()
            return widget:IsValid()
        end)

    if not okValid or widgetValid ~= true then
        Log(
            "[OverlayPoolCreateDiag] Constructed child is not a valid UObject",
            "/ luaType =", type(widget)
        )
        return nil
    end

    local childSlot = nil
    local okAdd, addResult =
        pcall(function()
            return canvas:AddChild(widget)
        end)

    if okAdd then
        childSlot = addResult
    end

    if not okAdd or not childSlot then
        Log(
            "[OverlayPoolCreateDiag] AddChild failed",
            "/ luaType =", type(widget),
            "/ error =", okAdd and "<nil slot>" or tostring(addResult)
        )
        return nil
    end

    SetWidgetVisible(widget, false)

    return widget

end

-- Calculate the position and size of one Overlay Widget.
--
-- The layout is calculated from the Widget's Left / Top / Width / Height,
-- with PitchX / PitchY applied based on the Widget's index.
--
-- Target-specific OffsetX / OffsetY from Config.UI[targetType]
-- are then applied to account for differences between overlay targets,
-- such as Normal PalBox slots and Party Pal slots.
--
-- Finally, the position is adjusted relative to Config.UI.BaseSize,
-- and VAlign / VOffset are applied as Text position adjustments.
--
-- Returns the Left / Top / Width / Height values
-- to be assigned to the UCanvasPanelSlot.
local function CalculateSlotLayout(
    config,
    targetType,
    index
)

    index = index or 1

    local left   = config.Left or 0
    local top    = config.Top or 0
    local width  = config.Width or 16
    local height = config.Height or 16

    ------------------------------------------------
    -- Pitch
    ------------------------------------------------

    left =
        left
        + (index - 1) * (config.PitchX or 0)

    top =
        top
        + (index - 1) * (config.PitchY or 0)

    ------------------------------------------------
    -- Target-specific Offset
    ------------------------------------------------

    local targetUI =
        Config.UI[targetType]

    if targetUI then

        left =
            left
            + (targetUI.OffsetX or 0)

        top =
            top
            + (targetUI.OffsetY or 0)

    end

    local targetConfig =
        OverlayTargetConfig[targetType]

    if targetConfig then

        left =
            left
            + (targetConfig.OffsetX or 0)

        top =
            top
            + (targetConfig.OffsetY or 0)

    end

    ------------------------------------------------
    -- Coordinate Origin Adjustment
    ------------------------------------------------
    -- Normal / Party overlays use the center of their Canvas as the
    -- 80x80 coordinate origin. Hatch-result rows use the left edge of
    -- their 450x80 Canvas because the Pal icon occupies the leftmost
    -- 80x80 area. OverlayTargetConfig defines these target-specific
    -- origin ratios without changing the shared UI element coordinates.

    local originX =
        targetConfig
        and targetConfig.OriginX
        or 0.5

    local originY =
        targetConfig
        and targetConfig.OriginY
        or 0.5

    left =
        left
        - Config.UI.BaseSize * originX

    top =
        top
        - Config.UI.BaseSize * originY

    ------------------------------------------------
    -- Vertical Alignment
    ------------------------------------------------

    if config.VAlign and config.FontSize then

        local textHeight =
            config.FontSize
            * Config.UI.FontHeightScale

        local offsetY = 0

        if config.VAlign == "Center" then

            offsetY =
                (height - textHeight) * 0.5

        elseif config.VAlign == "Bottom" then

            offsetY =
                height - textHeight

        end

        top =
            top
            + offsetY
            + (config.VOffset or 0)

    end

    return left, top, width, height

end

-- Apply the layout, rendering scale, and optional text fitting
-- specified in Config to the Widget.
--
-- CalculateSlotLayout() calculates the final position and size,
-- including the target-specific OffsetX / OffsetY.
-- This function applies those calculated values to the Widget's
-- CanvasPanelSlot.
--
-- Because the Anchor is based on the center of the Pal icon,
-- fixed values of 0.5 to 0.5 are used for both X and Y.
--
-- ScaleX / ScaleY control the horizontal and vertical rendering scale
-- of the Widget.
--
-- TextFit controls how text is handled when it exceeds the Widget width.
-- "Clip" clips text that exceeds the configured Width.
-- "AutoScale" automatically shrinks the text horizontally
-- to fit within the configured Width.
-- If TextFit is not specified, no text fitting is applied.
--
-- Modify CalculateSlotLayout() when changing the positioning algorithm.
-- Modify this function when changing how the calculated layout values,
-- rendering scale, or text fitting are applied to the Widget.
local function SetupSlot(
    widget,
    config,
    targetType,
    index
)

    if not widget then
        return
    end

    local left, top, width, height =
        CalculateSlotLayout(
            config,
            targetType,
            index
        )

    local slot =
        widget.Slot

    if slot then

        local targetConfig =
            OverlayTargetConfig[targetType]

        local anchorX =
            targetConfig
            and targetConfig.AnchorX
            or 0.5

        local anchorY =
            targetConfig
            and targetConfig.AnchorY
            or 0.5

        slot:SetAnchors({

            Minimum = {
                X = anchorX,
                Y = anchorY
            },

            Maximum = {
                X = anchorX,
                Y = anchorY
            }

        })

        slot:SetPosition({
            X = left,
            Y = top
        })

        slot:SetSize({
            X = width,
            Y = height
        })

    end

    ------------------------------------------------
    -- Render Scale
    ------------------------------------------------
    -- ScaleX / ScaleY control the horizontal and vertical
    -- rendering scale of the Widget.
    --
    -- Values below 1.0 make the Widget smaller.
    -- Values above 1.0 make the Widget larger.
    ------------------------------------------------

    widget:SetRenderScale({

        X = config.ScaleX or 1.0,
        Y = config.ScaleY or 1.0

    })

    ------------------------------------------------
    -- Render Transform Pivot
    ------------------------------------------------
    -- Adjust the horizontal pivot according to HAlign
    -- so that horizontal scaling keeps the aligned edge
    -- in the same position.
    --
    -- Left   = left edge remains fixed.
    -- Right  = right edge remains fixed.
    -- Center = center remains fixed.
    ------------------------------------------------

    local pivotX = 0.5

    if config.HAlign == "Left" then

        pivotX = 0.0

    elseif config.HAlign == "Center" then

        pivotX = 0.5

    elseif config.HAlign == "Right" then

        pivotX = 1.0

    end

    widget:SetRenderTransformPivot({

        X = pivotX,
        Y = 0.5

    })

    ------------------------------------------------
    -- Text Fit
    ------------------------------------------------
    -- TextFit is optional.
    --
    -- "Clip":
    --   Clip text that exceeds the configured Width.
    --
    -- "AutoScale":
    --   Automatically shrink the text horizontally
    --   to fit within the configured Width.
    --
    -- If TextFit is not specified, no text fitting is applied.
    ------------------------------------------------

    if config.TextFit == "AutoScale" then

        pcall(function()

            widget.IsAutoAdjustScale = true
            widget.MaxWidth = width

        end)

    elseif config.TextFit == "Clip" then

        pcall(function()

            widget.IsAutoAdjustScale = false
            widget:SetClipping(1)

        end)

    end

end

---------------------------------------------------
-- Color
---------------------------------------------------

-- The type of ColorAndOpacity exposed by UE4SS differs
-- between TextBlock and Image.
-- Therefore, color-setting logic is separated by Widget type.
--
-- Do not attempt to unify this by guessing and reading
-- the current ColorAndOpacity structure.
-- Only known structures for each Widget are used to avoid exceptions
-- caused by invalid property access to SlateColor.

-- TextBlock-specific color setting.
-- TextBlock's ColorAndOpacity is a SlateColor,
-- so it is processed separately from Image.
--
-- Components not specified in Config.Color retain
-- the values currently held by the Widget.
-- For example, if only R and G are specified,
-- the existing B and A values are preserved.
-- If the existing Widget value cannot be obtained,
-- 1.0 is used for that component.
--
-- Because the property structures of TextBlock's SlateColor
-- and Image's LinearColor exposed by UE4SS differ,
-- color processing is separated into SetTextColor() and SetImageColor().
local function SetTextColor(text, color)

    if not text or not color then
        return
    end

    local current =
        text.ColorAndOpacity

    local currentColor =
        current.SpecifiedColor

    text:SetColorAndOpacity({

        SpecifiedColor = {

            R = color.R ~= nil
                and color.R
                or currentColor.R
                or 1,

            G = color.G ~= nil
                and color.G
                or currentColor.G
                or 1,

            B = color.B ~= nil
                and color.B
                or currentColor.B
                or 1,

            A = color.A ~= nil
                and color.A
                or currentColor.A
                or 1,

        },

        ColorUseRule =
            color.ColorUseRule ~= nil
            and color.ColorUseRule
            or current.ColorUseRule
            or 0,

    })

end

-- Image-specific color setting.
--
-- Components not specified in Config.Color retain
-- the values currently held by the Widget.
-- For example, if only R and G are specified,
-- the existing B and A values are preserved.
-- If the existing Widget value cannot be obtained,
-- 1.0 is used for that component.
--
-- Image's ColorAndOpacity has a different structure
-- from TextBlock's SlateColor, so this function is separate
-- from SetTextColor() for TextBlocks.
local function SetImageColor(img, color)

    if not img or not color then
        return
    end

    local current =
        img.ColorAndOpacity

    img:SetColorAndOpacity({

        R = color.R ~= nil
            and color.R
            or current.R
            or 1,

        G = color.G ~= nil
            and color.G
            or current.G
            or 1,

        B = color.B ~= nil
            and color.B
            or current.B
            or 1,

        A = color.A ~= nil
            and color.A
            or current.A
            or 1,

    })

end

-- Create the per-Entry cache used only by persistent pooled Overlays.
-- Direct-child Overlays pass no cache and therefore keep the legacy behavior.
local function CreatePoolDynamicCache()

    return {
        Text = {},
        ImageAlpha = {},
        ImageColor = {},
        TextColor = {},
        Visibility = {},
        PassiveSkillScratch = {},
        SoulValue = nil,
        FriendshipValue = nil,
    }

end

local function SetTextColorCached(text, color, dynamicCache)

    if not text or not color then
        return
    end

    if dynamicCache
        and dynamicCache.TextColor[text] == color then
        return
    end

    SetTextColor(text, color)

    if dynamicCache then
        dynamicCache.TextColor[text] = color
    end

end

local function SetImageColorCached(img, color, dynamicCache)

    if not img or not color then
        return
    end

    if dynamicCache
        and dynamicCache.ImageColor[img] == color then
        return
    end

    SetImageColor(img, color)

    if dynamicCache then
        dynamicCache.ImageColor[img] = color
    end

end

local function SetImageAlphaCached(img, alpha, dynamicCache)

    if not img then
        return
    end

    if dynamicCache
        and dynamicCache.ImageAlpha[img] == alpha then
        return
    end

    local color = img.ColorAndOpacity

    img:SetColorAndOpacity({
        R = color.R,
        G = color.G,
        B = color.B,
        A = alpha,
    })

    if dynamicCache then
        dynamicCache.ImageAlpha[img] = alpha
    end

end

-- Configure TextBlock settings that do not depend on the current Pal.
--
-- For direct-child Overlays this is still applied by SetupText() on every
-- update, preserving the legacy behavior. Persistent Pool Entries apply this
-- once while parked and later data updates pass skipStaticSetup=true, avoiding
-- repeated layout / font / alignment / Config-color work.
local function ApplyTextStaticSetup(
    text,
    config,
    targetType,
    index
)

    if not text then
        return
    end

    SetupSlot(
        text,
        config,
        targetType,
        index
    )

    ---------------------------------------------------
    -- Font
    ---------------------------------------------------

    local font =
        text.Font

    if font then

        if config.FontSize then
            font.Size = config.FontSize
        end

        if config.Bold then
            font.TypefaceFontName =
                FName("Bold")
        end

        if config.Outline then

            font.OutlineSettings.OutlineSize = 1
            font.OutlineSettings.OutlineBlur = 0
            font.OutlineSettings.OutlineColor = {
                R = 0,
                G = 0,
                B = 0,
                A = 1
            }

        end

        text:SetFont(font)

    end

    ---------------------------------------------------
    -- Alignment
    ---------------------------------------------------

    if config.HAlign then

        if config.HAlign == "Left" then

            text:SetJustification(0)

        elseif config.HAlign == "Center" then

            text:SetJustification(1)

        elseif config.HAlign == "Right" then

            text:SetJustification(2)

        end

    else

        text:SetJustification(0)

    end

    ---------------------------------------------------
    -- Config Color
    ---------------------------------------------------

    SetTextColor(
        text,
        config.Color
    )

end

-- Configure Image settings that do not depend on the current Pal, excluding
-- the texture itself. Textures are initialized separately after Resource Ready
-- because startup Pool prewarm can finish before PalIconInfo texture assets are
-- available.
local function ApplyImageStaticLayout(
    img,
    config,
    targetType,
    index
)

    if not img then
        return
    end

    SetupSlot(
        img,
        config,
        targetType,
        index
    )

    SetImageColor(
        img,
        config.Color
    )

end

-- Apply an Image texture without touching layout or color.
local function ApplyImageStaticTexture(
    img,
    texture
)

    if not img or not texture then
        return false
    end

    img:SetBrushFromTexture(
        texture,
        true
    )

    return true

end

-- Configure a TextBlock using the settings specified in Config.
--
-- Direct-child Overlays keep the previous behavior and reapply all settings.
-- Persistent Pool Widgets have their static settings initialized once when the
-- Entry is created, so repeated Slot updates only change the displayed text.
local function SetupText(
    text,
    value,
    config,
    targetType,
    index,
    skipStaticSetup,
    dynamicCache
)

    if not text then
        return false
    end

    -- UE4SS can retain a truthy wrapper after the underlying UWidget has already
    -- entered destruction. Validate immediately before any TextBlock native call
    -- so a partially destroyed pooled Entry cannot throw on SetText().
    local okValid, isValid =
        pcall(function()
            return text:IsValid()
        end)

    if not okValid or isValid ~= true then
        return false
    end

    if not skipStaticSetup then

        ApplyTextStaticSetup(
            text,
            config,
            targetType,
            index
        )

    end

    ---------------------------------------------------
    -- Dynamic Text
    ---------------------------------------------------

    local cacheValue = tostring(value)

    if dynamicCache
        and dynamicCache.Text[text] == cacheValue then
        return
    end

    local okSet =
        pcall(function()
            text:SetText(FText(value))
        end)

    if not okSet then
        return false
    end

    if dynamicCache then
        dynamicCache.Text[text] = cacheValue
    end

    return true

end

-- Configure an Image Widget using the settings specified in Config.
--
-- Direct-child Overlays keep the previous behavior. Persistent Pool Widgets
-- pass skipStaticSetup=true after their layout/color and texture have already
-- been initialized on the parked Entry.
local function SetupImage(
    img,
    texture,
    config,
    targetType,
    index,
    skipStaticSetup
)

    if not img then
        return
    end

    if not skipStaticSetup then

        if texture then

            ApplyImageStaticTexture(
                img,
                texture
            )

        end

        ApplyImageStaticLayout(
            img,
            config,
            targetType,
            index
        )

    end

end

-- Change only the Alpha of an Image to show or hide it.
-- RGB is not changed, so the currently configured color is preserved.
-- When transparent=false, Alpha is restored to 1.0,
-- making the Image fully opaque when shown again.
-- RGB configured through Config.Color and other settings remains unchanged.
local function SetImageTransparent(
    img,
    transparent,
    dynamicCache
)

    SetImageAlphaCached(
        img,
        transparent and 0 or 1,
        dynamicCache
    )

end

-- Restore only the configured Alpha for an Image while preserving its current
-- RGB value. Pooled Passive Skill Widgets can be made fully transparent when a
-- previous Pal has fewer skills. Because pooled SetupImage() skips the static
-- Config-color reset on later updates, their configured Alpha must be restored
-- explicitly when a skill becomes present again.
local function RestoreImageConfiguredAlpha(
    img,
    config,
    dynamicCache
)

    if not img
        or not config
        or not config.Color
        or config.Color.A == nil then
        return
    end

    SetImageAlphaCached(
        img,
        config.Color.A,
        dynamicCache
    )

end

------------------------------------------------
-- Overlay UI Functions
------------------------------------------------

-- Generate a Lua Table for the Overlay based on the definition of OverlayLayout.
--
-- OverlayLayout only defines the Widget paths; the actual Widgets are not created here.
-- SetPath() is used to create an empty Table with the same hierarchy as OverlayLayout.
--
-- This structure is shared by CreateOverlayWidgets(), GetOverlayWidgets(),
-- and ClearOverlayWidgets(), so changing OverlayLayout does not require
-- rebuilding the Widget reference Table separately.
local function CreateOverlayTable()

    local overlay = {}

    for _, path in ipairs(OverlayLayout) do
        SetPath(overlay, path, nil)
    end

    return overlay

end

-- Obtain Overlay Widgets that have already been added to the Canvas.
--
-- MOD Overlay Widgets are expected to be added after Palworld's native
-- child Widgets, starting at the specified baseChildCount.
-- The Overlay Widgets are retrieved in the same order as OverlayLayout.
--
-- Therefore, the order of OverlayLayout must remain consistent with
-- the order in which Overlay Widgets are created.
-- When adding, removing, or reordering Widgets, make sure that
-- OverlayLayout and the Widget creation order remain consistent.
GetOverlayWidgets = function(canvas, baseChildCount)

    if not canvas then
        return nil
    end

    local overlay =
        CreateOverlayTable()

    for index, path in ipairs(OverlayLayout) do

        local ok, child =
            pcall(function()

                return canvas:GetChildAt(
                    baseChildCount + index - 1
                )

            end)

        if ok and child then

            SetPath(
                overlay,
                path,
                child
            )

        end

    end

    return overlay

end

-- Initialize the display contents remaining in Overlay Widgets.
--
-- Retrieve each Widget using the order of OverlayLayout,
-- and identify Text / Image from the prefix of the path name
-- to perform the appropriate clearing operation.
--
-- Items whose Widget name starts with Text_ use SetText(),
-- while items starting with Image_ have their Brush cleared and are made transparent.
--
-- Instead of using GetClass() or attempting Property Access to determine the Widget type,
-- the OverlayLayout definition, which is also used during Widget creation,
-- is used as the type information.
--
-- This prevents Image-specific processing from being applied to TextBlocks,
-- or Text-specific processing from being applied to Images, during clearing.
local function GetOverlayValue(tbl, path)

    local current = tbl

    for part in path:gmatch("[^.]+") do

        local key = tonumber(part) or part

        if type(current) ~= "table" then
            return nil
        end

        current = current[key]

        if current == nil then
            return nil
        end

    end

    return current

end

local function ClearOverlayWidgets(overlay)

    if not overlay then
        return
    end

    for _, path in ipairs(OverlayLayout) do

        local obj =
            GetOverlayValue(
                overlay,
                path
            )

        if obj then

            if path:find("Text_", 1, true) then

                pcall(function()
                    obj:SetText(FText(""))
                end)

            elseif path:find("Image_", 1, true) then

                pcall(function()
                    obj:SetBrushFromTexture(nil, true)
                    obj:SetSize({X = 0, Y = 0})

                end)

                SetImageTransparent(
                    obj,
                    true
                )

            end

            SetWidgetVisible(
                obj,
                false
            )

        end

    end

end


-- Clear the contents of Overlays that were created during the previous execution
-- and remain when the MOD is restarted.
local function ClearSlotOverlay(
    widget,
    targetType,
    poolKind
)

    if not widget then
        return
    end

    targetType =
        targetType or "Normal"

    local targetConfig =
        OverlayTargetConfig[
            targetType
        ]

    if not targetConfig then
        return
    end

    if targetType == "Normal"
        and IsExcludedWidget(widget) then
        return
    end

    ------------------------------------------------
    -- Persistent Pool
    ------------------------------------------------
    -- A pooled Entry already owns the Overlay references, so there is no need
    -- to traverse the Slot Widget hierarchy just to resolve its Canvas.
    local pooledEntry = nil

    if targetType == "Normal" then

        -- Normal PalBox and Preset slots share one Normal-layout Pool.
        pooledEntry =
            SharedOverlayPool.GetEntryForWidget(
                widget
            )

    elseif targetType == "Party"
        and PartyOverlayPool then

        pooledEntry =
            PartyOverlayPool.GetEntryForWidget(
                widget
            )

    end

    if pooledEntry then

        -- Persistent pooled Widgets keep their one-time static layout and
        -- texture state. An empty Slot only needs to hide the root; clearing
        -- child Brushes/Sizes would destroy the static initialization.
        if pooledEntry.RootVisible then

            SetWidgetVisible(
                pooledEntry.Root,
                false
            )

            pooledEntry.RootVisible = false

        end

        return

    end

    ------------------------------------------------
    -- Direct-child Overlay fallback
    ------------------------------------------------

    local canvas =
        GetPalSlotCanvas(
            widget,
            targetType
        )

    if not canvas then
        return
    end

    local okCount, count =
        pcall(function()

            return canvas:GetChildrenCount()

        end)

    if not okCount
        or type(count) ~= "number"
        or count <
            targetConfig.BaseChildCount
            + ADDED_CHILD_COUNT then
        return
    end

    local overlay =
        GetOverlayWidgets(
            canvas,
            targetConfig.BaseChildCount
        )

    if overlay then
        ClearOverlayWidgets(overlay)
    end

end

-- Clear Overlay contents left by a previous execution.
-- No Widgets are created here; only already existing MOD Overlay children are
-- retrieved according to each target's native child count and cleared.
local function ClearAllOverlayWidgets()

    for targetType, targetConfig
        in pairs(OverlayTargetConfig) do

        local okFind, widgets =
            pcall(function()

                return targetConfig.FindWidgets()

            end)

        if okFind
            and widgets then

            for _, widget
                in ipairs(widgets) do

                local okClear, clearError =
                    pcall(function()

                        ClearSlotOverlay(
                            widget,
                            targetType
                        )

                    end)

                if not okClear then

                    DebugLog(
                        "Overlay cleanup failed:",
                        targetType,
                        clearError
                    )

                end

            end

        end

    end

end


-- Recursively traverse the Overlay Table and change the visibility
-- of all contained Widgets.
--
-- Because the Table hierarchy can be passed directly,
-- visibility can be changed for entire groups such as Number or PassiveSkill.Bar.
--
-- By matching the hierarchy of OverlayLayout with that of Config.ActiveDisplay,
-- the same function can process all display items without writing separate
-- visibility logic for each item.
local function SetOverlayWidgetsVisible(obj, visible)

    if not obj then
        return
    end

    if type(obj) == "table" then

        for _, v in pairs(obj) do
            SetOverlayWidgetsVisible(v, visible)
        end

    else
        SetWidgetVisible(obj, visible)
    end

end

-- Persistent Pool entries retain child visibility between uses. Cache the
-- visibility of each Overlay group so page changes do not repeat identical
-- SetVisibility() calls across all 34 child Widgets.
local function SetOverlayWidgetsVisibleCached(
    obj,
    visible,
    dynamicCache
)

    if dynamicCache
        and dynamicCache.Visibility[obj] == visible then
        return
    end

    SetOverlayWidgetsVisible(
        obj,
        visible
    )

    if dynamicCache then
        dynamicCache.Visibility[obj] = visible
    end

end


-- Obtain the string currently set in a TextBlock as a Lua string.
--
-- Used by UpdateOverlayVisibility() to determine HideZero for Soul / Friendship.
-- UMG Text is returned as FText, so ToString() is used to convert it to a Lua string.
-- Returns nil if the value cannot be obtained through UE4SS GetText() / ToString().
local function GetOverlayText(widget)

    if not widget then
        return nil
    end

    local text = nil

    local ok = pcall(function()
        text = widget:GetText()
    end)

    if not ok or not text then
        return nil
    end

    local result = nil

    pcall(function()
        result = text:ToString()
    end)

    return result

end


-- Determine whether Talent values may be displayed according to the current
-- Talent display option and the cached Ability Glasses state.
--
-- The equipment hook updates AbilityGlassesEquipped only.
-- UI processing is intentionally not performed there because the PalBox is
-- normally closed while the equipment screen is open.
local function CanDisplayTalent(widget)

    if not Config.DisplayOption
    or not Config.DisplayOption.Talent
    or not Config.DisplayOption.Talent.RequireAbilityGlasses then
        return true
    end

    if not AbilityGlassesStateInitialized and widget then

        local palUtility =
            Res.palUtility

        if not palUtility then

            local okUtility, resultUtility =
                pcall(function()
                    return StaticFindObject(PAL_UTILITY)
                end)

            if okUtility and resultUtility then
                palUtility = resultUtility
                Res.palUtility = resultUtility
            end

        end

        if palUtility then

            local okInventory, inventory =
                pcall(function()
                    return palUtility:GetLocalInventoryData(widget)
                end)

            if okInventory and inventory then
                UpdateAbilityGlassesState(inventory)
            end

        end

    end

    return AbilityGlassesEquipped == true

end


-- Update the cached Ability Glasses state from Palworld's inventory data.
-- This is called when the state actually needs to be determined, such as
-- when the PalBox is displayed. Equipment changes only update this flag.
UpdateAbilityGlassesState = function(inventory)

    if not Config.DisplayOption
    or not Config.DisplayOption.Talent
    or not Config.DisplayOption.Talent.RequireAbilityGlasses then
        AbilityGlassesEquipped = true
        AbilityGlassesStateInitialized = true
        return
    end

    if not inventory then
        AbilityGlassesEquipped = false
        AbilityGlassesStateInitialized = true
        return
    end

    local okCheck, allowed =
        pcall(function()
            return inventory:CanCheckPalTalentsByInventoryItem()
        end)

    AbilityGlassesEquipped = okCheck and allowed == true
    AbilityGlassesStateInitialized = true

end


-- Update the Overlay visibility according to Config.ActiveDisplay and DisplayOption.
--
-- Because this is separated from data updating (UpdateOverlayData),
-- visibility is changed according to the current DisplayMode after
-- the values inside the Widgets have been updated.
--
-- Soul / Friendship have individual options to hide them when their value is 0,
-- so only these items also check their current Text contents before being displayed.
UpdateOverlayVisibility = function(
    overlay,
    widget,
    talentAllowed,
    dynamicCache
)

    if not overlay then
        return
    end

    ------------------------------------------------
    -- Palpedia Number
    ------------------------------------------------

    SetOverlayWidgetsVisibleCached(
        overlay.Number,
        Config.ActiveDisplay.Number,
        dynamicCache
    )

    ------------------------------------------------
    -- Level
    ------------------------------------------------

    SetOverlayWidgetsVisibleCached(
        overlay.Level,
        Config.ActiveDisplay.Level,
        dynamicCache
    )


    ------------------------------------------------
    -- Gender
    ------------------------------------------------

    SetOverlayWidgetsVisibleCached(
        overlay.Gender,
        Config.ActiveDisplay.Gender,
        dynamicCache
    )


    ------------------------------------------------
    -- Rank
    ------------------------------------------------

    SetOverlayWidgetsVisibleCached(
        overlay.Rank,
        Config.ActiveDisplay.Rank,
        dynamicCache
    )


    ------------------------------------------------
    -- Soul
    ------------------------------------------------

    local showSoul = Config.ActiveDisplay.Soul

    if showSoul
    and Config.DisplayOption.Soul.HideZero then

        if dynamicCache
            and dynamicCache.SoulValue ~= nil then

            if dynamicCache.SoulValue == 0 then
                showSoul = false
            end

        else

            local soulText = GetOverlayText(
                overlay.Soul.Text_SoulValue
            )

            if soulText == "0" then
                showSoul = false
            end

        end

    end

    SetOverlayWidgetsVisibleCached(
        overlay.Soul,
        showSoul,
        dynamicCache
    )


    ------------------------------------------------
    -- Friendship
    ------------------------------------------------

    local showFriendship = Config.ActiveDisplay.Friendship

    if showFriendship
    and Config.DisplayOption.Friendship.HideZero then

        if dynamicCache
            and dynamicCache.FriendshipValue ~= nil then

            if dynamicCache.FriendshipValue == 0 then
                showFriendship = false
            end

        else

            local friendshipText = GetOverlayText(
                overlay.Friendship.Text_FriendshipValue
            )

            if friendshipText == "0" then
                showFriendship = false
            end

        end

    end

    SetOverlayWidgetsVisibleCached(
        overlay.Friendship,
        showFriendship,
        dynamicCache
    )


    ------------------------------------------------
    -- PassiveSkill
    ------------------------------------------------

    SetOverlayWidgetsVisibleCached(
        overlay.PassiveSkill.Bar,
        Config.ActiveDisplay.PassiveSkill.Bar,
        dynamicCache
    )

    SetOverlayWidgetsVisibleCached(
        overlay.PassiveSkill.Name,
        Config.ActiveDisplay.PassiveSkill.Name,
        dynamicCache
    )


    ------------------------------------------------
    -- Talent
    ------------------------------------------------

    local showTalent = Config.ActiveDisplay.Talent

    if showTalent
    and Config.DisplayOption.Talent.RequireAbilityGlasses then

        if talentAllowed == nil then
            talentAllowed = CanDisplayTalent(widget)
        end

        showTalent = talentAllowed == true

    end

    SetOverlayWidgetsVisibleCached(
        overlay.Talent,
        showTalent,
        dynamicCache
    )

end

-- Create Overlay Widgets on the Canvas according to OverlayLayout.
--
-- Items whose Widget name starts with Text_ create BP_PalTextBlock Widgets,
-- while items starting with Image_ create UMG Image Widgets.
-- The creation order must exactly match the order of OverlayLayout.
-- GetOverlayWidgets() uses the same order to obtain existing Widgets from the Canvas,
-- so OverlayLayout is the common definition for both creation and retrieval.
local function CreateOverlayWidgets(canvas)

    local overlay = CreateOverlayTable()

    for _, path in ipairs(OverlayLayout) do

        local obj

        if path:find("Text_",1,true) then

            obj = CreateWidget(Res.textClass,canvas)

        elseif path:find("Image_",1,true) then

            obj = CreateWidget(Res.imageClass,canvas)

        end

        SetPath(
            overlay,
            path,
            obj
        )

    end

    return overlay

end

------------------------------------------------
-- Shared Normal / Preset Overlay Pool
------------------------------------------------
--
-- Scope:
--   * Normal PalBox + Preset shared Normal-layout Pool
--   * startup prewarm target: 80 pooled Entries
--   * every Entry owns one OverlayRoot containing all 34 Overlay Widgets
--   * pool capacity grows automatically when more Entries are required
--
-- Party uses a separate persistent Pool. Preset shares this Normal-layout Pool. Hatch continues to use the existing direct-child path.
SharedOverlayPool = {
    OverallLayout = nil,
    ParkingRoot = nil,
    Entries = {},
    EntryByWidgetAddress = {},
    WidgetPoolModeByAddress = {},
    WidgetScrollListAddressByWidgetAddress = {},
    -- Diagnostic identity: remember the SlotButton UObject address that
    -- owns each pooled/preset Slot. A recycled CharacterSlot address must not
    -- inherit the retiring state of a different SlotButton instance.
    WidgetSlotButtonAddressByWidgetAddress = {},
    -- bounded registry for currently live WBP_PalCharacterScrollList
    -- SlotButtons. Records are created before SlotButton:Setup() -> SlotUpdate
    -- and removed on SlotButton Destruct or owner cleanup. Dead Slot addresses
    -- are never retained as tombstones in this registry.
    LiveScrollSlotByButtonAddress = {},
    LiveScrollSlotButtonAddressByWidgetAddress = {},
    -- generation-scoped owner state. A ScrollList generation is active
    -- only while its current set of SlotButtons is allowed to drive Pool
    -- acquisition. Cleanup invalidates the owner generation before parking,
    -- so late SlotUpdate is rejected even while a closing Button still has a
    -- valid Parent. No retired Slot address is retained.
    LiveScrollOwnerStateByAddress = {},
    LiveScrollOwnerNextGeneration = 0,
    DiagnosticLiveScrollOwnerPeak = 0,
    DiagnosticLiveScrollOwnerActivated = 0,
    DiagnosticLiveScrollOwnerDeactivated = 0,
    DiagnosticLiveScrollOwnerReleasedByLastSlot = 0,
    DiagnosticInactiveOwnerSlotUpdateRejected = 0,
    DiagnosticLiveScrollSlotPeak = 0,
    DiagnosticLiveScrollSlotRemovedByCleanup = 0,
    DiagnosticLiveScrollSlotRemovedByDestruct = 0,
    DiagnosticDetachedSlotUpdateRejected = 0,
    DiagnosticUnregisteredParentedSlotUpdate = 0,
    DiagnosticResidualParentValid = 0,
    DiagnosticResidualParentNil = 0,
    DiagnosticResidualButtonNotFound = 0,
    DiagnosticResidualParentError = 0,
    -- screen-independent live identity registry for every common
    -- CharacterSlotButton Setup* path. Pool eligibility is still governed by
    -- the live ScrollList/Common owner registries.
    LiveCommonSlotByButtonAddress = {},
    LiveCommonSlotButtonAddressByWidgetAddress = {},
    DiagnosticLiveCommonSlotPeak = 0,
    DiagnosticLiveCommonSetup = 0,
    DiagnosticLiveCommonSetupByCharacterID = 0,
    DiagnosticLiveCommonSetupByIndividualId = 0,
    DiagnosticLiveCommonSetupBySaveParameter = 0,
    DiagnosticLiveCommonRemovedByDestruct = 0,
    -- classify common ButtonBase Setup* calls that do not belong to
    -- WBP_PalCharacterScrollList. This is diagnostic-only and is used to
    -- verify Party / Preset / condensation / auxiliary Button lifecycles
    -- before extending Pool eligibility beyond paged ScrollLists.
    DiagnosticCommonNonScrollContextSeen = {},
    DiagnosticCommonNonScrollDestructContextSeen = {},
    DiagnosticCommonNonScrollSetup = 0,
    DiagnosticCommonNonScrollRemoved = 0,
    -- Preset teardown is represented on the existing bounded Common
    -- live record itself instead of creating a dead CharacterSlot-address
    -- tombstone. The exact SlotButton identity remains authoritative until
    -- Destruct removes the record. A marker fallback is retained only as a
    -- safety diagnostic if a Preset Slot unexpectedly lacks a Common record.
    DiagnosticCommonRetiringMarked = 0,
    DiagnosticCommonRetiringBlocked = 0,
    DiagnosticCommonRetiringFallbackMarker = 0,
    -- non-ScrollList CommonCharacterSlotButton ownership for shared
    -- Pool Entries. The exact live SlotButton identity owns the Entry until
    -- the Button Destruct pre-hook parks it. This replaces AttachedPendingOwner
    -- for Common slots without introducing a dead-address tombstone.
    DiagnosticCommonOwnedEntryAttached = 0,
    DiagnosticCommonOwnedEntryParkedByDestruct = 0,
    -- non-ScrollList Common records that have reached Button Destruct
    -- but must remain as bounded Retiring records until the next authoritative
    -- Setup* reactivates the same Button identity.
    DiagnosticCommonPostDestructRetained = 0,
    -- diagnostic-only tracing for live non-ScrollList Common Slots.
    -- Debug-only counters for live non-ScrollList Common Slot updates.
    DiagnosticCommonLiveSlotUpdateObserved = 0,
    DiagnosticCommonLiveSlotUpdateAttached = 0,
    DiagnosticCommonLiveSlotUpdateNoEntry = 0,
    -- a retiring marker is needed only until the exact owning
    -- SlotButton actually Destructs. Clear it at that physical lifetime end,
    -- matched by SlotButton identity, so teardown protection remains intact
    -- without retaining dead-address tombstones after destruction.
    DiagnosticRetiringMarkerClearedByButtonDestruct = 0,
    -- Slot addresses parked by a ScrollList/Preset teardown remain
    -- temporarily marked until a newly created live Slot is preclassified.
    -- This blocks late SlotUpdate callbacks from reacquiring a Pool Entry into
    -- a Widget subtree that has already entered destruction.
    WidgetRetiringReasonByAddress = {},
    DiagnosticRetiredSlotUpdateCount = 0,
    DiagnosticRetiredSlotReuseCount = 0,
    -- identify whether a retiring SlotUpdate fires while PalIconInfo's
    -- own cleanup callback is still running or only after that callback has
    -- explicitly reached its end. This does not rely on a Blueprint post hook.
    DiagnosticRetireSequence = 0,
    DiagnosticRetireStateBySequence = {},
    DiagnosticRetiringMarkerPeak = 0,
    DiagnosticAfterCleanupObserved = false,
    -- correlate retiring SlotUpdate and SlotButton::Destruct using the
    -- exact CharacterSlot / SlotButton identity and cleanup sequence.
    DiagnosticSlotButtonDestructByWidgetAddress = {},
    DiagnosticSlotButtonDestructCount = 0,
    DiagnosticSlotUpdateAfterButtonDestructCount = 0,
    DiagnosticSlotButtonDestructCountAtLastCleanup = 0,
    DiagnosticSlotButtonDestructAfterCleanupCount = 0,
    DiagnosticRetiredSlotUpdateBeforeButtonDestructCount = 0,
    DiagnosticRetiredSlotUpdateAfterButtonDestructCount = 0,
    DiagnosticRetiredSlotUpdateUnknownButtonDestructCount = 0,
    DiagnosticScrollListSeen = {},
    DiagnosticBoundaryStacks = {},
    DiagnosticSequence = 0,
    DiagnosticNextEntryId = 0,
    Ready = false,
    PrewarmRequested = false,
    TextAssetLoadAttempted = false,
    TexturesInitialized = false,
    TargetCount = SHARED_OVERLAY_POOL_TARGET_COUNT,
}

function SharedOverlayPool.IsValidObject(obj)

    if not obj then
        return false
    end

    local ok, valid =
        pcall(function()
            return obj:IsValid()
        end)

    return ok and valid == true

end

function SharedOverlayPool.GetAddress(obj)

    if not SharedOverlayPool.IsValidObject(obj) then
        return nil
    end

    local ok, address =
        pcall(function()
            return obj:GetAddress()
        end)

    if not ok then
        return nil
    end

    return address

end


-- Detach a pooled Root only while both the Root and its current parent are
-- still valid. Validity is rechecked immediately before the native call and
-- again after RemoveFromParent(), because pooled Widgets can cross PalBox UI
-- lifetime boundaries during page/menu transitions.
function SharedOverlayPool.DetachRootSafely(root)

    if not SharedOverlayPool.IsValidObject(root) then
        return false, "root invalid before GetParent"
    end

    local parent = nil
    local getParentCalled = false

    local okParent =
        pcall(function()

            if not SharedOverlayPool.IsValidObject(root) then
                return
            end

            getParentCalled = true
            parent = root:GetParent()

        end)

    if not okParent
        or not getParentCalled
        or not SharedOverlayPool.IsValidObject(root) then
        return false, "root invalid around GetParent"
    end

    if not parent then
        return true
    end

    if not SharedOverlayPool.IsValidObject(parent) then
        return false, "parent invalid before RemoveFromParent"
    end

    local removeCalled = false

    local okRemove =
        pcall(function()

            if not SharedOverlayPool.IsValidObject(root)
                or not SharedOverlayPool.IsValidObject(parent) then
                return
            end

            removeCalled = true
            root:RemoveFromParent()

        end)

    if not okRemove or not removeCalled then
        return false, "RemoveFromParent skipped or failed"
    end

    if not SharedOverlayPool.IsValidObject(root) then
        return false, "root invalid after RemoveFromParent"
    end

    return true

end


-- Add a pooled Root only after revalidating both sides immediately before the
-- native AddChild() call. The returned CanvasPanelSlot is also validated before
-- any slot-layout native calls are made.
function SharedOverlayPool.AddRootSafely(parent, root)

    if not SharedOverlayPool.IsValidObject(parent) then
        return nil, "target parent invalid before AddChild"
    end

    if not SharedOverlayPool.IsValidObject(root) then
        return nil, "root invalid before AddChild"
    end

    local childSlot = nil
    local addCalled = false

    local okAdd =
        pcall(function()

            if not SharedOverlayPool.IsValidObject(parent)
                or not SharedOverlayPool.IsValidObject(root) then
                return
            end

            addCalled = true
            childSlot = parent:AddChild(root)

        end)

    if not okAdd
        or not addCalled
        or not childSlot then
        return nil, "AddChild skipped or failed"
    end

    if not SharedOverlayPool.IsValidObject(parent)
        or not SharedOverlayPool.IsValidObject(root)
        or not SharedOverlayPool.IsValidObject(childSlot) then
        return nil, "object invalid after AddChild"
    end

    return childSlot

end

-- Resolve the WBP_PalOverallUILayout_C that actually owns a PalBox Widget.
-- During a map/UI transition an older OverallLayout can remain IsValid() for a
-- short time after the replacement layout has already become active. Pool host
-- validation therefore must use ownership identity, not UObject validity alone.
function SharedOverlayPool.ResolveOwningOverallLayout(widget)

    local target = widget

    for _ = 1, 16 do

        if not SharedOverlayPool.IsValidObject(target) then
            return nil
        end

        local className = nil

        local okClass =
            pcall(function()

                local class = target:GetClass()

                if class then
                    local fname = class:GetFName()

                    if fname then
                        className = fname:ToString()
                    end
                end

            end)

        if not okClass or not className then
            return nil
        end

        if className == "WBP_PalOverallUILayout_C" then
            return target
        end

        if className == "Package" then
            return nil
        end

        local nextTarget = nil
        local okOuter =
            pcall(function()
                nextTarget = target:GetOuter()
            end)

        if not okOuter
            or not nextTarget
            or nextTarget == target then
            return nil
        end

        target = nextTarget

    end

    return nil

end


-- Ensure that the persistent Overlay Pool belongs to the same OverallLayout as
-- the PalBox that is being opened. This specifically handles map/UI transition
-- windows where the previous host is still valid but is no longer the active
-- owner of the new PalBox.
function SharedOverlayPool.EnsureHostForWidget(widget)

    if not SHARED_OVERLAY_POOL_ENABLED then
        return false
    end

    local currentLayout =
        SharedOverlayPool.ResolveOwningOverallLayout(
            widget
        )

    if not SharedOverlayPool.IsValidObject(currentLayout) then
        return false
    end

    local currentAddress =
        SharedOverlayPool.GetAddress(currentLayout)

    local poolAddress =
        SharedOverlayPool.GetAddress(
            SharedOverlayPool.OverallLayout
        )

    local sameHost =
        SharedOverlayPool.Ready
        and currentAddress ~= nil
        and poolAddress ~= nil
        and currentAddress == poolAddress
        and SharedOverlayPool.IsValidObject(
            SharedOverlayPool.ParkingRoot
        )

    if sameHost then
        return true
    end

    if SharedOverlayPool.Ready
        or SharedOverlayPool.OverallLayout ~= nil
        or SharedOverlayPool.ParkingRoot ~= nil then

        DebugLog(
            "[OverlayPool] OverallLayout changed; rebinding Pool host before PalBox setup"
        )

        -- Do not manipulate the old Widget tree here. During travel it can be
        -- in the middle of destruction even while IsValid() is still true.
        -- Dropping Lua-side state lets that old tree destroy its children on
        -- its own, while the new Pool is built under the current layout.
        SharedOverlayPool.Reset()

        if PartyOverlayPool
            and PartyOverlayPool.Reset then
            PartyOverlayPool.Reset()
        end

        -- Texture anchor Images belonged to the previous OverallLayout. Rebuild
        -- those UE-side anchors under the new host before creating new Entries.
        local preloadState =
            PalIconRuntime.PrePalBoxResourcePreload

        if preloadState then
            preloadState.AnchorWidgets = {}
            preloadState.AnchorReadback = {}
            preloadState.AnchorSuccess = {}
            preloadState.Anchored = false
            preloadState.Complete = false
            preloadState.AnchorCount = 0
            preloadState.AnchorReadbackCount = 0
            preloadState.AnchorMs = 0
        end

    end

    return SharedOverlayPool.Prewarm(
        currentLayout
    )

end

function SharedOverlayPool.IsCompleteOverlay(overlay)

    if not overlay then
        return false
    end

    for _, path in ipairs(OverlayLayout) do

        local obj =
            GetOverlayValue(
                overlay,
                path
            )

        if not SharedOverlayPool.IsValidObject(obj) then
            return false, path
        end

    end

    return true, nil

end


-- Validate the complete persistent Entry immediately before reuse/update.
-- A Root can remain valid briefly while one or more child Text/Image Widgets
-- have already become TrivialObject wrappers during UI teardown. Root-only
-- validation therefore cannot protect the hot update path.
function SharedOverlayPool.ValidateEntryTree(entry, reason)

    if not entry
        or entry.Quarantined == true then
        return false
    end

    local overlayComplete, invalidPath =
        SharedOverlayPool.IsCompleteOverlay(
            entry.Overlay
        )

    if not SharedOverlayPool.IsValidObject(entry.Root)
        or not overlayComplete then

        Log(
            "[OverlayPoolSafety] Partial Entry invalid / Entry",
            entry.Index,
            "/ Widget =",
            invalidPath or "<Root>",
            "/",
            reason or "validation",
            "/ Owner =",
            entry.DiagnosticOwnerFullName or "<unknown>",
            "/ BoundWidget =",
            entry.DiagnosticWidgetFullName or "<unknown>",
            "/ BindSeq =",
            entry.DiagnosticBindSequence or 0,
            "/ LastBoundary =",
            entry.DiagnosticLastBoundary or "<none>",
            "/ BoundarySeq =",
            entry.DiagnosticLastBoundarySequence or 0
        )

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Partial Widget tree: " .. tostring(reason or "validation")
        )

        return false
    end

    return true

end

function SharedOverlayPool.ApplyStaticLayoutToOverlay(
    overlay,
    targetType
)

    if not SharedOverlayPool.IsCompleteOverlay(overlay) then
        return false
    end

    targetType = targetType or "Normal"

    local function SetupStaticText(
        widget,
        config,
        index
    )

        ApplyTextStaticSetup(
            widget,
            config,
            targetType,
            index
        )

    end

    local function SetupStaticImage(
        widget,
        config,
        index
    )

        ApplyImageStaticLayout(
            widget,
            config,
            targetType,
            index
        )

    end

    ------------------------------------------------
    -- Text Widgets (15)
    ------------------------------------------------

    SetupStaticText(
        overlay.Number.Text_No,
        Config.UI.Number.Text_No
    )

    overlay.Number.Text_No:SetText(
        FText("No.")
    )

    SetupStaticText(
        overlay.Number.Text_NumberValue,
        Config.UI.Number.Text_NumberValue
    )

    SetupStaticText(
        overlay.Number.Text_SuffixValue,
        Config.UI.Number.Text_SuffixValue
    )

    SetupStaticText(
        overlay.Number.Text_0,
        Config.UI.Number.Text_0
    )

    SetupStaticText(
        overlay.Level.Text_Lv,
        Config.UI.Level.Text_Lv
    )

    overlay.Level.Text_Lv:SetText(
        FText("Lv.")
    )

    SetupStaticText(
        overlay.Level.Text_LevelValue,
        Config.UI.Level.Text_LevelValue
    )

    SetupStaticText(
        overlay.Soul.Text_SoulValue,
        Config.UI.Soul.Text_SoulValue
    )

    SetupStaticText(
        overlay.Friendship.Text_FriendshipValue,
        Config.UI.Friendship.Text_FriendshipValue
    )

    local talent = {
        overlay.Talent.Text_TalentHPValue,
        overlay.Talent.Text_TalentATKValue,
        overlay.Talent.Text_TalentDEFValue,
    }

    for i = 1, 3 do

        SetupStaticText(
            talent[i],
            Config.UI.Talent.Text_TalentValue,
            i
        )

    end

    for i = 1, 4 do

        SetupStaticText(
            overlay.PassiveSkill.Name.Text_PassiveSkillName[i],
            Config.UI.PassiveSkill.Name.Text_PassiveSkillName,
            i
        )

    end

    ------------------------------------------------
    -- Image Widgets (19)
    ------------------------------------------------

    SetupStaticImage(
        overlay.Gender.Male.Image_MaleIconBG,
        Config.UI.Gender.Image_GenderIconBG
    )

    SetupStaticImage(
        overlay.Gender.Female.Image_FemaleIconBG,
        Config.UI.Gender.Image_GenderIconBG
    )

    SetupStaticImage(
        overlay.Gender.Male.Image_MaleIcon,
        Config.UI.Gender.Image_GenderIcon
    )

    SetupStaticImage(
        overlay.Gender.Female.Image_FemaleIcon,
        Config.UI.Gender.Image_GenderIcon
    )

    for i = 1, 4 do

        SetupStaticImage(
            overlay.Rank.Image_RankIcon[i],
            Config.UI.Rank.Image_RankIcon,
            i
        )

    end

    SetupStaticImage(
        overlay.Soul.Image_SoulIcon,
        Config.UI.Soul.Image_SoulIcon
    )

    SetupStaticImage(
        overlay.Friendship.Image_FriendshipIcon,
        Config.UI.Friendship.Image_FriendshipIcon
    )

    SetupStaticImage(
        overlay.PassiveSkill.Bar.Image_Background,
        Config.UI.PassiveSkill.Bar.Image_Background
    )

    for i = 1, 4 do

        SetupStaticImage(
            overlay.PassiveSkill.Bar.Image_PassiveSkillIcon[i],
            Config.UI.PassiveSkill.Bar.Image_PassiveSkillIcon,
            i
        )

        SetupStaticImage(
            overlay.PassiveSkill.Name.Image_Background[i],
            Config.UI.PassiveSkill.Name.Image_Background,
            i
        )

    end

    return true

end

function SharedOverlayPool.ApplyStaticTexturesToOverlay(overlay)

    if not SharedOverlayPool.IsCompleteOverlay(overlay) then
        return false
    end

    local function SetupStaticTexture(
        widget,
        texture
    )

        ApplyImageStaticTexture(
            widget,
            texture
        )

    end

    SetupStaticTexture(
        overlay.Gender.Male.Image_MaleIconBG,
        Res.texMale
    )

    SetupStaticTexture(
        overlay.Gender.Female.Image_FemaleIconBG,
        Res.texFemale
    )

    SetupStaticTexture(
        overlay.Gender.Male.Image_MaleIcon,
        Res.texMale
    )

    SetupStaticTexture(
        overlay.Gender.Female.Image_FemaleIcon,
        Res.texFemale
    )

    for i = 1, 4 do

        SetupStaticTexture(
            overlay.Rank.Image_RankIcon[i],
            Res.texRankStar
        )

    end

    SetupStaticTexture(
        overlay.Soul.Image_SoulIcon,
        Res.texSoul
    )

    SetupStaticTexture(
        overlay.Friendship.Image_FriendshipIcon,
        Res.texFriendship
    )

    SetupStaticTexture(
        overlay.PassiveSkill.Bar.Image_Background,
        Res.texSolidWhite
    )

    for i = 1, 4 do

        SetupStaticTexture(
            overlay.PassiveSkill.Bar.Image_PassiveSkillIcon[i],
            Res.texSolidWhite
        )

        SetupStaticTexture(
            overlay.PassiveSkill.Name.Image_Background[i],
            Res.texSolidWhite
        )

    end

    return true

end

function SharedOverlayPool.RefreshStaticLayoutAllEntries(reason)

    if not SharedOverlayPool.Ready then
        return 0
    end

    local refreshed = 0

    for _, entry
        in ipairs(SharedOverlayPool.Entries) do

        local okRefresh, didRefresh =
            pcall(
                SharedOverlayPool.ApplyStaticLayoutToOverlay,
                entry.Overlay
            )

        if okRefresh and didRefresh then

            if entry.DynamicCache then
                entry.DynamicCache =
                    CreatePoolDynamicCache()
            end

            refreshed = refreshed + 1

        end

    end

    DebugLog(
        "[OverlayPool] Static layout refreshed:",
        refreshed,
        "Entries / reason =",
        reason or "unspecified"
    )

    return refreshed

end

function SharedOverlayPool.InitializeStaticTexturesAllEntries()

    if not SharedOverlayPool.Ready
        or SharedOverlayPool.TexturesInitialized then
        return 0
    end

    local initialized = 0

    for _, entry
        in ipairs(SharedOverlayPool.Entries) do

        local okTexture, didInitialize =
            pcall(
                SharedOverlayPool.ApplyStaticTexturesToOverlay,
                entry.Overlay
            )

        if okTexture and didInitialize then
            initialized = initialized + 1
        end

    end

    SharedOverlayPool.TexturesInitialized = true

    DebugLog(
        "[OverlayPool] Static textures initialized:",
        initialized,
        "Entries"
    )

    return initialized

end

function SharedOverlayPool.EnsureWidgetClasses()

    if not SHARED_OVERLAY_POOL_ENABLED then
        return false
    end

    local canvasClass =
        Res.canvasClass
        or StaticFindObject(
            AssetPath.Class.Canvas
        )

    local textClass =
        Res.textClass
        or StaticFindObject(
            AssetPath.Class.Text
        )

    -- The native Canvas/Image classes are always available, while the cooked
    -- BP_PalTextBlock class may still be unloaded when OverallUILayout first
    -- appears. Try its asset preload only once; later prewarm retries simply
    -- re-check StaticFindObject so a failed package lookup cannot spam logs.
    if not textClass
        and not SharedOverlayPool.TextAssetLoadAttempted then

        SharedOverlayPool.TextAssetLoadAttempted =
            true

        pcall(function()
            LoadAsset(PAL_TEXT_BLOCK_ASSET)
        end)

        textClass =
            StaticFindObject(
                AssetPath.Class.Text
            )

    end

    local imageClass =
        Res.imageClass
        or StaticFindObject(
            AssetPath.Class.Image
        )

    if not canvasClass
        or not textClass
        or not imageClass then
        return false
    end

    Res.canvasClass = canvasClass
    Res.textClass = textClass
    Res.imageClass = imageClass

    UObjectCache.canvasClass = canvasClass
    UObjectCache.textClass = textClass
    UObjectCache.imageClass = imageClass

    return true

end

function SharedOverlayPool.SetupRootSlot(slot)

    if not slot then
        return false
    end

    local ok =
        pcall(function()

            slot:SetAnchors({
                Minimum = {
                    X = 0.0,
                    Y = 0.0,
                },
                Maximum = {
                    X = 1.0,
                    Y = 1.0,
                },
            })

            slot:SetOffsets({
                Left = 0.0,
                Top = 0.0,
                Right = 0.0,
                Bottom = 0.0,
            })

            slot:SetAlignment({
                X = 0.0,
                Y = 0.0,
            })

            slot:SetAutoSize(false)

        end)

    return ok

end

function SharedOverlayPool.SetupParkingSlot(slot)

    if not slot then
        return
    end

    pcall(function()

        slot:SetAnchors({
            Minimum = {
                X = 0.0,
                Y = 0.0,
            },
            Maximum = {
                X = 0.0,
                Y = 0.0,
            },
        })

        slot:SetPosition({
            X = -10000.0,
            Y = -10000.0,
        })

        slot:SetSize({
            X = 1.0,
            Y = 1.0,
        })

    end)

end

function SharedOverlayPool.CreateEntry(
    parkingRoot,
    index
)

    local okConstruct, root =
        pcall(
            StaticConstructObject,
            Res.canvasClass,
            parkingRoot
        )

    if not okConstruct or not root then
        return nil
    end

    local rootSlot =
        parkingRoot:AddChild(root)

    if not rootSlot then
        return nil
    end

    SharedOverlayPool.SetupParkingSlot(rootSlot)
    SetWidgetVisible(root, false)

    local overlay =
        CreateOverlayWidgets(root)

    if not SharedOverlayPool.IsCompleteOverlay(overlay) then

        pcall(function()
            root:RemoveFromParent()
        end)

        return nil

    end

    -- Apply all layout / font / alignment / Config-color settings while the
    -- Entry is still parked. These values do not depend on the current Pal and
    -- therefore do not need to be repeated on every later Slot update.
    local okStaticLayout, staticLayoutReady =
        pcall(
            SharedOverlayPool.ApplyStaticLayoutToOverlay,
            overlay
        )

    if not okStaticLayout
        or staticLayoutReady ~= true then

        pcall(function()
            root:RemoveFromParent()
        end)

        return nil

    end

    -- Entries created after Resource Ready (adaptive growth) can initialize
    -- their texture brushes immediately. Startup-prewarmed Entries receive the
    -- same one-time texture setup from EnsureResourceReady().
    if ResourceReady then

        local okStaticTexture =
            pcall(
                SharedOverlayPool.ApplyStaticTexturesToOverlay,
                overlay
            )

        if not okStaticTexture then

            pcall(function()
                root:RemoveFromParent()
            end)

            return nil

        end

    end

    SharedOverlayPool.DiagnosticNextEntryId =
        (SharedOverlayPool.DiagnosticNextEntryId or 0) + 1

    local diagnosticEntryId =
        SharedOverlayPool.DiagnosticNextEntryId

    return {
        Index = index,
        DiagnosticEntryId = diagnosticEntryId,
        Root = root,
        Overlay = overlay,
        BoundWidgetAddress = nil,
        OwnerScrollListAddress = nil,
        OwnerPresetRowAddress = nil,
        OwnerCommonSlotButtonAddress = nil,
        LastSave = nil,
        DynamicCache = nil,
        RootVisible = false,
        Quarantined = false,

        -- Diagnostic metadata is strings/scalars only. Never retain an extra
        -- UObject solely for diagnostics.
        DiagnosticOwnerFullName = nil,
        DiagnosticWidgetFullName = nil,
        DiagnosticBindSequence = 0,
        DiagnosticLastBoundary = nil,
        DiagnosticLastBoundarySequence = 0,
        DiagnosticState = "Parked",
        DiagnosticLastTransition = "CreateEntry",
        DiagnosticLastParkReason = "prewarm/create",
        DiagnosticLastParentFullName =
            SharedOverlayPool.GetDiagnosticFullName(parkingRoot),
        DiagnosticFailureReason = nil,
        DiagnosticFailureState = nil,
        DiagnosticFailureRootValid = nil,
        DiagnosticFailureTreeValid = nil,
        DiagnosticFailureWidget = nil,
        DiagnosticFailureWasBound = nil,
        DiagnosticFailureHadScrollOwner = nil,
        DiagnosticFailureHadPresetOwner = nil,
        DiagnosticFailureOwnerFullName = nil,
        DiagnosticFailureBoundWidgetFullName = nil,
    }

end

function SharedOverlayPool.Reset()

    SharedOverlayPool.OverallLayout = nil
    SharedOverlayPool.ParkingRoot = nil
    SharedOverlayPool.Entries = {}
    SharedOverlayPool.EntryByWidgetAddress = {}
    SharedOverlayPool.WidgetPoolModeByAddress = {}
    SharedOverlayPool.WidgetScrollListAddressByWidgetAddress = {}
    SharedOverlayPool.WidgetSlotButtonAddressByWidgetAddress = {}
    SharedOverlayPool.LiveScrollSlotByButtonAddress = {}
    SharedOverlayPool.LiveScrollSlotButtonAddressByWidgetAddress = {}
    SharedOverlayPool.LiveScrollOwnerStateByAddress = {}
    SharedOverlayPool.LiveScrollOwnerNextGeneration = 0
    SharedOverlayPool.DiagnosticLiveScrollOwnerPeak = 0
    SharedOverlayPool.DiagnosticLiveScrollOwnerActivated = 0
    SharedOverlayPool.DiagnosticLiveScrollOwnerDeactivated = 0
    SharedOverlayPool.DiagnosticLiveScrollOwnerReleasedByLastSlot = 0
    SharedOverlayPool.DiagnosticInactiveOwnerSlotUpdateRejected = 0
    SharedOverlayPool.DiagnosticLiveScrollSlotPeak = 0
    SharedOverlayPool.DiagnosticLiveScrollSlotRemovedByCleanup = 0
    SharedOverlayPool.DiagnosticLiveScrollSlotRemovedByDestruct = 0
    SharedOverlayPool.DiagnosticDetachedSlotUpdateRejected = 0
    SharedOverlayPool.DiagnosticUnregisteredParentedSlotUpdate = 0
    SharedOverlayPool.DiagnosticResidualParentValid = 0
    SharedOverlayPool.DiagnosticResidualParentNil = 0
    SharedOverlayPool.DiagnosticResidualButtonNotFound = 0
    SharedOverlayPool.DiagnosticResidualParentError = 0
    SharedOverlayPool.LiveCommonSlotByButtonAddress = {}
    SharedOverlayPool.LiveCommonSlotButtonAddressByWidgetAddress = {}
    SharedOverlayPool.DiagnosticLiveCommonSlotPeak = 0
    SharedOverlayPool.DiagnosticLiveCommonSetup = 0
    SharedOverlayPool.DiagnosticLiveCommonSetupByCharacterID = 0
    SharedOverlayPool.DiagnosticLiveCommonSetupByIndividualId = 0
    SharedOverlayPool.DiagnosticLiveCommonSetupBySaveParameter = 0
    SharedOverlayPool.DiagnosticLiveCommonRemovedByDestruct = 0
    SharedOverlayPool.DiagnosticCommonNonScrollContextSeen = {}
    SharedOverlayPool.DiagnosticCommonNonScrollDestructContextSeen = {}
    SharedOverlayPool.DiagnosticCommonNonScrollSetup = 0
    SharedOverlayPool.DiagnosticCommonNonScrollRemoved = 0
    SharedOverlayPool.DiagnosticCommonRetiringMarked = 0
    SharedOverlayPool.DiagnosticCommonRetiringBlocked = 0
    SharedOverlayPool.DiagnosticCommonRetiringFallbackMarker = 0
    SharedOverlayPool.DiagnosticCommonOwnedEntryAttached = 0
    SharedOverlayPool.DiagnosticCommonOwnedEntryParkedByDestruct = 0
    SharedOverlayPool.DiagnosticCommonPostDestructRetained = 0
    SharedOverlayPool.DiagnosticCommonLiveSlotUpdateObserved = 0
    SharedOverlayPool.DiagnosticCommonLiveSlotUpdateAttached = 0
    SharedOverlayPool.DiagnosticCommonLiveSlotUpdateNoEntry = 0
    SharedOverlayPool.DiagnosticPalCondensePartySetupAttachAttempt = 0
    SharedOverlayPool.DiagnosticPalCondensePartySetupAttachSuccess = 0
    SharedOverlayPool.DiagnosticPalCondensePartySetupAttachEmpty = 0
    SharedOverlayPool.DiagnosticPalCondensePartySetupAttachNoSave = 0
    SharedOverlayPool.DiagnosticRetiringMarkerClearedByButtonDestruct = 0
    SharedOverlayPool.WidgetRetiringReasonByAddress = {}
    SharedOverlayPool.DiagnosticRetiredSlotUpdateCount = 0
    SharedOverlayPool.DiagnosticRetiredSlotReuseCount = 0
    SharedOverlayPool.DiagnosticRetireSequence = 0
    SharedOverlayPool.DiagnosticRetireStateBySequence = {}
    SharedOverlayPool.DiagnosticRetiringMarkerPeak = 0
    SharedOverlayPool.DiagnosticAfterCleanupObserved = false
    SharedOverlayPool.DiagnosticSlotButtonDestructByWidgetAddress = {}
    SharedOverlayPool.DiagnosticSlotButtonDestructCount = 0
    SharedOverlayPool.DiagnosticSlotUpdateAfterButtonDestructCount = 0
    SharedOverlayPool.DiagnosticSlotButtonDestructCountAtLastCleanup = 0
    SharedOverlayPool.DiagnosticSlotButtonDestructAfterCleanupCount = 0
    SharedOverlayPool.DiagnosticRetiredSlotUpdateBeforeButtonDestructCount = 0
    SharedOverlayPool.DiagnosticRetiredSlotUpdateAfterButtonDestructCount = 0
    SharedOverlayPool.DiagnosticRetiredSlotUpdateUnknownButtonDestructCount = 0
    SharedOverlayPool.DiagnosticScrollListSeen = {}
    SharedOverlayPool.DiagnosticBoundaryStacks = {}
    SharedOverlayPool.DiagnosticSequence = 0
    SharedOverlayPool.Ready = false
    SharedOverlayPool.TexturesInitialized = false

end

function SharedOverlayPool.AppendEntry(reason)

    if not SharedOverlayPool.Ready
        or not SharedOverlayPool.IsValidObject(
            SharedOverlayPool.ParkingRoot
        ) then
        return nil
    end

    local index =
        #SharedOverlayPool.Entries + 1

    local entry =
        SharedOverlayPool.CreateEntry(
            SharedOverlayPool.ParkingRoot,
            index
        )

    if not entry then
        return nil
    end

    SharedOverlayPool.Entries[
        #SharedOverlayPool.Entries + 1
    ] = entry

    DebugLog("[OverlayPool] Entry created:", index, "/ reason =", reason or "unspecified")

    return entry

end

------------------------------------------------
-- Preloaded Texture UE-side Anchor
------------------------------------------------
-- Reacquire each preloaded Texture with LoadAsset() only after the hidden
-- persistent ParkingRoot exists, then immediately store it in a UImage Brush.
-- No StaticFindObject() lookup is needed here: LoadAsset() already returns the
-- loaded UObject and its found/load status. Keeping the Brush alive provides a
-- persistent UE-side reference for later PalBox resource initialization.
function SharedOverlayPool.LoadAndAnchorTexturesNow()

    local state = PalIconRuntime.PrePalBoxResourcePreload

    if not state
        or state.Complete == true
        or state.Anchored == true then
        return state and state.Anchored == true or false
    end

    local parkingRoot = SharedOverlayPool.ParkingRoot

    if not SharedOverlayPool.IsValidObject(parkingRoot)
        or not Res.imageClass then
        return false
    end

    local startTime = os.clock()
    local anchoredCount = 0
    local readbackCount = 0

    for index, item in ipairs(state.Items) do

        local okConstruct, anchorImage =
            pcall(
                StaticConstructObject,
                Res.imageClass,
                parkingRoot
            )

        if not okConstruct then
            anchorImage = nil
        end

        local childSlot = nil

        if anchorImage then
            childSlot = parkingRoot:AddChild(anchorImage)
        end

        if anchorImage then
            SetWidgetVisible(anchorImage, false)
        end

        local okCall, loadedObject, wasFound, didLoad =
            pcall(
                LoadAsset,
                item.Path
            )

        local loadValid = false

        if okCall and loadedObject then
            pcall(function()
                loadValid = loadedObject:IsValid()
            end)
        end

        local loadSucceeded =
            okCall
            and wasFound == true
            and didLoad == true
            and loadValid

        local okBrush = false
        local brushError = nil

        if loadSucceeded
            and anchorImage
            and childSlot then

            okBrush, brushError =
                pcall(function()
                    anchorImage:SetBrushFromTexture(loadedObject, true)
                end)

        end

        local readbackObject = nil
        local readbackValid = false

        if okBrush then
            pcall(function()
                if anchorImage.Brush then
                    readbackObject = anchorImage.Brush.ResourceObject
                end

                if readbackObject then
                    readbackValid = readbackObject:IsValid()
                end
            end)
        end

        local anchorSuccess =
            loadSucceeded
            and okBrush
            and readbackObject ~= nil
            and readbackValid

        state.AnchorReadback[item.Name] = readbackValid
        state.AnchorSuccess[item.Name] = anchorSuccess

        if anchorSuccess then
            state.TextureKeepAlive[item.Name] = loadedObject
            state.AnchorWidgets[item.Name] = anchorImage

            -- The anchored Texture is now a persistent UE-side resource.
            -- Publish the exact same UObject immediately so startup-prewarmed
            -- Pool Entries can receive their static brushes before PalBox opens.
            Res[item.Name] = loadedObject
            UObjectCache[item.Name] = loadedObject

            anchoredCount = anchoredCount + 1
        else
            Log(
                "[TextureAnchor] Failed:",
                item.Name,
                "callOk=" .. tostring(okCall),
                "wasFound=" .. tostring(wasFound),
                "didLoad=" .. tostring(didLoad),
                "valid=" .. tostring(loadValid),
                "brush=" .. tostring(okBrush),
                "brushError=" .. tostring(brushError),
                "readbackValid=" .. tostring(readbackValid)
            )
        end

        if readbackValid then
            readbackCount = readbackCount + 1
        end

    end

    state.AnchorCount = anchoredCount
    state.AnchorReadbackCount = readbackCount
    state.AnchorMs = (os.clock() - startTime) * 1000
    state.Anchored = anchoredCount == #state.Items
    state.Complete = true

    DebugLog(
        "[TextureAnchor] Complete:",
        anchoredCount,
        "/",
        #state.Items,
        "Textures /",
        string.format("%.3fms", state.AnchorMs)
    )

    return state.Anchored

end

function SharedOverlayPool.Prewarm(overallLayout)

    if not SHARED_OVERLAY_POOL_ENABLED then
        return false
    end

    if SharedOverlayPool.Ready
        and SharedOverlayPool.IsValidObject(
            SharedOverlayPool.ParkingRoot
        ) then
        return true
    end

    SharedOverlayPool.Reset()

    if not SharedOverlayPool.IsValidObject(overallLayout) then
        return false
    end

    if not SharedOverlayPool.EnsureWidgetClasses() then
        return false
    end

    local rootPanel = nil

    local okRoot, resultRoot =
        pcall(function()
            return overallLayout.CanvasPanel_Root
        end)

    if okRoot then
        rootPanel = resultRoot
    end

    if not SharedOverlayPool.IsValidObject(rootPanel) then
        return false
    end

    local okConstruct, parkingRoot =
        pcall(
            StaticConstructObject,
            Res.canvasClass,
            rootPanel
        )

    if not okConstruct or not parkingRoot then
        return false
    end

    local parkingSlot =
        rootPanel:AddChild(
            parkingRoot
        )

    if not parkingSlot then
        return false
    end

    SharedOverlayPool.SetupParkingSlot(parkingSlot)
    SetWidgetVisible(parkingRoot, false)

    SharedOverlayPool.OverallLayout =
        overallLayout

    SharedOverlayPool.ParkingRoot =
        parkingRoot

    SharedOverlayPool.Ready = true

    -- Reacquire and anchor all six preloaded Texture resources now, before any
    -- of the 80 Pool Entries are constructed.
    SharedOverlayPool.LoadAndAnchorTexturesNow()

    -- Build the complete shared startup capacity immediately while the
    -- persistent OverallLayout host is available. The Pool exists specifically
    -- to avoid constructing Overlay Widgets when PalBox / Preset is displayed,
    -- so normal runtime use should not depend on an unfinished delayed prewarm.
    while #SharedOverlayPool.Entries
        < SharedOverlayPool.TargetCount do

        local entry =
            SharedOverlayPool.AppendEntry(
                "prewarm"
            )

        if not entry then

            Log(
                "[OverlayPool] Prewarm Entry creation failed at",
                #SharedOverlayPool.Entries + 1
            )

            break

        end

    end

    local preloadState =
        PalIconRuntime.PrePalBoxResourcePreload

    if preloadState
        and preloadState.Anchored == true then
        SharedOverlayPool.InitializeStaticTexturesAllEntries()
    end

    DebugLog(
        "[OverlayPool] Prewarm complete:",
        #SharedOverlayPool.Entries,
        "Entries / target",
        SharedOverlayPool.TargetCount,
        "/",
        #OverlayLayout,
        "Widgets per Entry"
    )

    return true

end

function SharedOverlayPool.EnsureReadyNow()

    if not SHARED_OVERLAY_POOL_ENABLED then
        return false
    end

    if SharedOverlayPool.Ready
        and SharedOverlayPool.IsValidObject(
            SharedOverlayPool.ParkingRoot
        ) then
        return true
    end

    -- The persistent host may have been recreated by a world/UI transition.
    -- Invalidate the old Lua-side pool state before binding to the new host.
    if SharedOverlayPool.Ready then
        SharedOverlayPool.Reset()
    end

    local overallLayout = nil

    local okFind, resultFind =
        pcall(function()
            return FindFirstOf(
                "WBP_PalOverallUILayout_C"
            )
        end)

    if okFind then
        overallLayout = resultFind
    end

    if not SharedOverlayPool.IsValidObject(
        overallLayout
    ) then
        return false
    end

    return SharedOverlayPool.Prewarm(
        overallLayout
    )

end

-- Remove an Entry from reuse without making any further native calls on its
-- Widget tree. This is used when the Root itself is still valid but its current
-- parent or Canvas lifetime has already become unsafe. Such an Entry must not be
-- returned to the free list, because Root:IsValid() alone does not guarantee
-- that its surrounding UMG hierarchy is still usable.
function SharedOverlayPool.QuarantineEntry(entry, reason)

    if not entry or entry.Quarantined == true then
        return false
    end

    -- Preserve the exact Lua-side state before Quarantine clears the live
    -- UObject references. These scalar/string fields are retained only for
    -- diagnosis; they do not participate in allocation or reuse decisions.
    local rootValid =
        SharedOverlayPool.IsValidObject(entry.Root)

    local treeValid = false
    local invalidWidget = "<Root>"

    if rootValid then
        local complete, invalidPath =
            SharedOverlayPool.IsCompleteOverlay(entry.Overlay)

        treeValid = complete == true
        invalidWidget =
            treeValid and "<none>" or (invalidPath or "<child>")
    end

    entry.DiagnosticFailureReason =
        tostring(reason or "unsafe Widget tree")
    entry.DiagnosticFailureState =
        entry.DiagnosticState or "<unknown>"
    entry.DiagnosticFailureRootValid = rootValid
    entry.DiagnosticFailureTreeValid = treeValid
    entry.DiagnosticFailureWidget = invalidWidget
    entry.DiagnosticFailureWasBound =
        entry.BoundWidgetAddress ~= nil
    entry.DiagnosticFailureHadScrollOwner =
        entry.OwnerScrollListAddress ~= nil
    entry.DiagnosticFailureHadPresetOwner =
        entry.OwnerPresetRowAddress ~= nil
    entry.DiagnosticFailureHadCommonOwner =
        entry.OwnerCommonSlotButtonAddress ~= nil
    entry.DiagnosticFailureOwnerFullName =
        entry.DiagnosticOwnerFullName
    entry.DiagnosticFailureBoundWidgetFullName =
        entry.DiagnosticWidgetFullName

    local widgetAddress =
        entry.BoundWidgetAddress

    -- The Widget->ScrollList classification belongs to the live Slot, not to
    -- this particular Entry. Preserve it so a replacement Entry acquired for
    -- the same existing Slot can recover its owner immediately. The normal
    -- ScrollList clear/destruct lifecycle removes classifications.
    if widgetAddress then

        if SharedOverlayPool.EntryByWidgetAddress[
            widgetAddress
        ] == entry then

            SharedOverlayPool.EntryByWidgetAddress[
                widgetAddress
            ] = nil

        end


    end

    entry.Quarantined = true
    entry.Root = nil
    entry.Overlay = nil
    entry.DynamicCache = nil
    entry.BoundWidgetAddress = nil
    entry.OwnerScrollListAddress = nil
    entry.OwnerPresetRowAddress = nil
    entry.OwnerCommonSlotButtonAddress = nil
    entry.LastSave = nil
    entry.RootVisible = false

    Log(
        "[OverlayPoolSafety] Entry",
        entry.Index,
        "quarantined /",
        reason or "unsafe Widget tree"
    )

    return true

end


function SharedOverlayPool.GetEntryForWidget(
    widget,
    knownAddress
)

    if not SHARED_OVERLAY_POOL_ENABLED
        or not SharedOverlayPool.Ready then
        return nil
    end

    local address =
        knownAddress
        or SharedOverlayPool.GetAddress(widget)

    if not address then
        return nil
    end

    local entry =
        SharedOverlayPool.EntryByWidgetAddress[
            address
        ]

    if not entry then
        return nil
    end

    -- Validate the complete 34-Widget tree immediately before an existing
    -- pooled Entry is updated. A child TextBlock can
    -- become invalid while the Entry Root still reports valid. Quarantine the
    -- whole Entry in that state so no later updater touches a partial tree.
    if not SharedOverlayPool.ValidateEntryTree(
        entry,
        "bound Entry lookup"
    ) then
        return nil
    end

    -- Pool invariant recovery for an in-session upgrade from an older build:
    -- a bound Entry with no lifecycle owner must not remain attached. Park it
    -- before returning so the caller can reacquire it only after resolving an
    -- exact ScrollList / Preset / Common owner. New pooled attachments never
    -- enter this state.
    if entry.BoundWidgetAddress ~= nil
        and entry.OwnerScrollListAddress == nil
        and entry.OwnerPresetRowAddress == nil
        and entry.OwnerCommonSlotButtonAddress == nil then

        Log(
            "[OverlayPoolSafety] Recovering ownerless bound Entry:",
            entry.Index or -1
        )

        SharedOverlayPool.ParkEntry(
            entry,
            "Owner invariant recovery"
        )

        return nil

    end

    return entry

end

function SharedOverlayPool.IsEntryFree(entry)

    -- Entry validity/completeness is established during creation. AttachEntry()
    -- performs the Root validity guard before a free Entry is actually moved.
    -- Keep the free-list scan Lua-only.
    return
        entry
        and entry.Quarantined ~= true
        and entry.BoundWidgetAddress == nil

end


-- Remove Pool records whose Root UObject has already disappeared.
--
-- A Slot Widget can occasionally be destroyed without reaching one of the
-- normal parking lifecycle callbacks. In that case the old Entry remains
-- marked as bound even though its Root is no longer valid. Because a bound
-- Entry is not considered free, repeated menu transitions would otherwise
-- leave dead records in the Pool and force unnecessary Pool growth.
--
-- This maintenance pass intentionally does not touch any still-valid Root or
-- Widget tree. It only drops Lua-side records for UObjects that are already
-- invalid, making it safe to run at low-frequency screen boundaries.
function SharedOverlayPool.CompactInvalidEntries(reason)

    if not SharedOverlayPool.Ready
        or #SharedOverlayPool.Entries == 0 then
        return 0
    end

    local compacted = {}
    local removed = 0

    -- Aggregate invalid Entries by their last known lifecycle state instead of
    -- printing one line per Entry. Large failure bursts can otherwise create
    -- hundreds of diagnostic log lines and obscure the event that preceded
    -- them. This table is diagnostic-only and never affects Pool decisions.
    local diagnosticGroups = {}
    local diagnosticGroupOrder = {}

    local function AddDiagnosticGroup(
        entry,
        rootValid,
        treeValid,
        invalidWidget
    )

        if not entry then
            return
        end

        local state =
            entry.DiagnosticFailureState
            or entry.DiagnosticState
            or "<unknown>"

        local owner =
            entry.DiagnosticFailureOwnerFullName
            or entry.DiagnosticOwnerFullName
            or "<unknown>"

        local boundWidget =
            entry.DiagnosticFailureBoundWidgetFullName
            or entry.DiagnosticWidgetFullName
            or "<unknown>"

        local failureReason =
            entry.DiagnosticFailureReason
            or "<not quarantined before compact>"

        local failureRootValid =
            entry.DiagnosticFailureRootValid

        if failureRootValid == nil then
            failureRootValid = rootValid == true
        end

        local failureTreeValid =
            entry.DiagnosticFailureTreeValid

        if failureTreeValid == nil then
            failureTreeValid = treeValid == true
        end

        local failureWidget =
            entry.DiagnosticFailureWidget
            or invalidWidget
            or "<unknown>"

        local wasBound =
            entry.DiagnosticFailureWasBound

        if wasBound == nil then
            wasBound = entry.BoundWidgetAddress ~= nil
        end

        local hadScrollOwner =
            entry.DiagnosticFailureHadScrollOwner

        if hadScrollOwner == nil then
            hadScrollOwner = entry.OwnerScrollListAddress ~= nil
        end

        local hadPresetOwner =
            entry.DiagnosticFailureHadPresetOwner

        if hadPresetOwner == nil then
            hadPresetOwner = entry.OwnerPresetRowAddress ~= nil
        end

        local lastBoundary =
            entry.DiagnosticLastBoundary or "<none>"

        local lastTransition =
            entry.DiagnosticLastTransition or "<none>"

        local lastParkReason =
            entry.DiagnosticLastParkReason or "<none>"

        local key = table.concat({
            tostring(state),
            tostring(owner),
            tostring(failureRootValid),
            tostring(failureTreeValid),
            tostring(failureWidget),
            tostring(wasBound),
            tostring(hadScrollOwner),
            tostring(hadPresetOwner),
            tostring(lastBoundary),
            tostring(lastTransition),
            tostring(lastParkReason),
            tostring(entry.Quarantined == true),
        }, "\31")

        local group = diagnosticGroups[key]

        if not group then
            group = {
                Count = 0,
                Ids = {},
                State = state,
                Owner = owner,
                BoundWidget = boundWidget,
                RootValid = failureRootValid,
                TreeValid = failureTreeValid,
                BadWidget = failureWidget,
                WasBound = wasBound,
                HadScrollOwner = hadScrollOwner,
                HadPresetOwner = hadPresetOwner,
                LastBoundary = lastBoundary,
                LastTransition = lastTransition,
                LastParkReason = lastParkReason,
                FailureReason = failureReason,
                Quarantined = entry.Quarantined == true,
            }
            diagnosticGroups[key] = group
            diagnosticGroupOrder[#diagnosticGroupOrder + 1] = key
        end

        group.Count = group.Count + 1

        if #group.Ids < 8 then
            group.Ids[#group.Ids + 1] =
                tostring(entry.DiagnosticEntryId or entry.Index or -1)
        end

    end

    for _, entry
        in ipairs(SharedOverlayPool.Entries) do

        local rootValid =
            entry
            and entry.Quarantined ~= true
            and SharedOverlayPool.IsValidObject(entry.Root)
            or false

        local treeValid = false
        local invalidWidget = "<Root>"

        if rootValid then
            local complete, invalidPath =
                SharedOverlayPool.IsCompleteOverlay(entry.Overlay)

            treeValid = complete == true
            invalidWidget =
                treeValid and "<none>" or (invalidPath or "<child>")
        end

        if entry
            and entry.Quarantined ~= true
            and rootValid
            and treeValid then

            entry.Index = #compacted + 1
            compacted[#compacted + 1] = entry

        else

            removed = removed + 1

            if entry then

                AddDiagnosticGroup(
                    entry,
                    rootValid,
                    treeValid,
                    invalidWidget
                )

                local widgetAddress =
                    entry.BoundWidgetAddress

                -- Preserve Slot classification for a replacement Entry.
                -- ClearWidgetModesForScrollList() owns classification cleanup.
                if widgetAddress then

                    if SharedOverlayPool.EntryByWidgetAddress[
                        widgetAddress
                    ] == entry then

                        SharedOverlayPool.EntryByWidgetAddress[
                            widgetAddress
                        ] = nil

                    end


                end

                entry.Root = nil
                entry.Overlay = nil
                entry.DynamicCache = nil
                entry.BoundWidgetAddress = nil
                entry.OwnerScrollListAddress = nil
                entry.OwnerPresetRowAddress = nil
                entry.OwnerCommonSlotButtonAddress = nil
                entry.LastSave = nil

            end

        end

    end

    if removed > 0 then

        SharedOverlayPool.Entries = compacted

        Log(
            "[OverlayPool] Removed",
            removed,
            "invalid Entries:",
            reason or "maintenance",
            "/ Pool size =",
            #SharedOverlayPool.Entries
        )

        -- Usually only one or two groups exist even for a large burst. Keep a
        -- hard cap so diagnostics cannot themselves produce a log storm.
        local maxGroups = 12
        local shown = math.min(#diagnosticGroupOrder, maxGroups)

        for i = 1, shown do

            local group =
                diagnosticGroups[
                    diagnosticGroupOrder[i]
                ]

            Log(
                "[PoolStateDiag] Invalid group",
                i,
                "/ count =", group.Count,
                "/ IDs =", table.concat(group.Ids, ","),
                "/ state =", group.State,
                "/ rootValid =", group.RootValid,
                "/ treeValid =", group.TreeValid,
                "/ badWidget =", group.BadWidget,
                "/ wasBound =", group.WasBound,
                "/ scrollOwner =", group.HadScrollOwner,
                "/ presetOwner =", group.HadPresetOwner,
                "/ quarantined =", group.Quarantined,
                "/ lastTransition =", group.LastTransition,
                "/ lastParkReason =", group.LastParkReason,
                "/ lastBoundary =", group.LastBoundary,
                "/ failureReason =", group.FailureReason,
                "/ owner =", group.Owner,
                "/ boundWidget =", group.BoundWidget
            )

        end

        if #diagnosticGroupOrder > maxGroups then
            Log(
                "[PoolStateDiag] Additional groups omitted =",
                #diagnosticGroupOrder - maxGroups
            )
        end

    end

    return removed

end

-- Diagnostic helpers used only to identify the exact UI lifetime boundary that
-- invalidates persistent Pool Entries. They store strings/scalars only and do
-- not change Pool eligibility, parking, acquisition, or reuse behavior.
function SharedOverlayPool.GetDiagnosticFullName(obj)

    if not DEBUG then
        return nil
    end

    if not SharedOverlayPool.IsValidObject(obj) then
        return "<invalid>"
    end

    local fullName = nil

    pcall(function()
        fullName = obj:GetFullName()
    end)

    if fullName then
        return tostring(fullName)
    end

    local objectName, className =
        GetPoolDiagnosticObjectIdentity(obj)

    return tostring(className) .. " " .. tostring(objectName)

end


function SharedOverlayPool.ResolveBoxPalScrollList(boxPalListBase)

    if not SharedOverlayPool.IsValidObject(boxPalListBase) then
        return nil
    end

    local scrollList = nil

    pcall(function()
        scrollList = boxPalListBase.WBP_BoxPalScrollList
    end)

    if not SharedOverlayPool.IsValidObject(scrollList) then
        return nil
    end

    return scrollList

end


function SharedOverlayPool.GetEntryHealth(entry)

    local health = {
        RootValid = false,
        TreeValid = false,
        InvalidWidget = "<Root>",
        ParentValid = false,
        ParentFullName = "<none>",
    }

    if not entry then
        return health
    end

    if not SharedOverlayPool.IsValidObject(entry.Root) then
        return health
    end

    health.RootValid = true

    local complete, invalidPath =
        SharedOverlayPool.IsCompleteOverlay(entry.Overlay)

    health.TreeValid = complete == true
    health.InvalidWidget = complete and "<none>" or (invalidPath or "<child>")

    local parent = nil
    pcall(function()
        if SharedOverlayPool.IsValidObject(entry.Root) then
            parent = entry.Root:GetParent()
        end
    end)

    if SharedOverlayPool.IsValidObject(parent) then
        health.ParentValid = true
        health.ParentFullName = SharedOverlayPool.GetDiagnosticFullName(parent)
    end

    return health

end


function SharedOverlayPool.LogPhaseDamage(entry, phaseName, beforeHealth)

    if not entry or not beforeHealth then
        return
    end

    local afterHealth =
        SharedOverlayPool.GetEntryHealth(entry)

    local rootBroke =
        beforeHealth.RootValid
        and not afterHealth.RootValid

    local treeBroke =
        beforeHealth.TreeValid
        and afterHealth.RootValid
        and not afterHealth.TreeValid

    if rootBroke or treeBroke then
        Log(
            "[PoolLifetimeDiag] DAMAGE DURING",
            phaseName,
            "/ Entry =", entry.Index or -1,
            "/ rootBroken =", rootBroke,
            "/ treeBroken =", treeBroke,
            "/ badWidget =", afterHealth.InvalidWidget or "<none>",
            "/ parentBefore =", beforeHealth.ParentFullName or "<none>",
            "/ parentAfter =", afterHealth.ParentFullName or "<none>",
            "/ Owner =", entry.DiagnosticOwnerFullName or "<unknown>"
        )
    end

end


function SharedOverlayPool.DiagnosticBoundaryBegin(
    boundaryName,
    scrollList
)

    if not DEBUG then
        return
    end

    if not SharedOverlayPool.Ready
        or not SharedOverlayPool.IsValidObject(scrollList) then
        return
    end

    SharedOverlayPool.DiagnosticSequence =
        (SharedOverlayPool.DiagnosticSequence or 0) + 1

    local sequence = SharedOverlayPool.DiagnosticSequence
    local ownerAddress = SharedOverlayPool.GetAddress(scrollList)

    if not ownerAddress then
        return
    end

    local ownerFullName =
        SharedOverlayPool.GetDiagnosticFullName(scrollList)

    local snapshots = {}
    local badBefore = 0

    for _, entry in ipairs(SharedOverlayPool.Entries) do

        if entry
            and entry.OwnerScrollListAddress == ownerAddress then

            local beforeHealth =
                SharedOverlayPool.GetEntryHealth(entry)

            snapshots[#snapshots + 1] = {
                Entry = entry,
                Index = entry.Index,
                RootValid = beforeHealth.RootValid,
                TreeValid = beforeHealth.TreeValid,
                InvalidWidget = beforeHealth.InvalidWidget,
                ParentValid = beforeHealth.ParentValid,
                ParentFullName = beforeHealth.ParentFullName,
                BoundWidgetAddress = entry.BoundWidgetAddress,
            }

            if not beforeHealth.RootValid
                or not beforeHealth.TreeValid then
                badBefore = badBefore + 1
            end

            entry.DiagnosticLastBoundary = boundaryName .. ":pre"
            entry.DiagnosticLastBoundarySequence = sequence

        end

    end

    local state = {
        Sequence = sequence,
        OwnerAddress = ownerAddress,
        OwnerFullName = ownerFullName,
        Snapshots = snapshots,
    }

    local stacks = SharedOverlayPool.DiagnosticBoundaryStacks
    if type(stacks) ~= "table" then
        stacks = {}
        SharedOverlayPool.DiagnosticBoundaryStacks = stacks
    end

    local stack = stacks[boundaryName]
    if type(stack) ~= "table" then
        stack = {}
        stacks[boundaryName] = stack
    end

    stack[#stack + 1] = state

    if badBefore > 0 then
        Log(
            "[PoolLifetimeDiag] DAMAGE BEFORE",
            boundaryName,
            "/ seq =", sequence,
            "/ owned =", #snapshots,
            "/ bad =", badBefore,
            "/ owner =", ownerFullName
        )
    end

end


function SharedOverlayPool.DiagnosticBoundaryEnd(
    boundaryName,
    scrollList
)

    if not DEBUG then
        return
    end

    if not SharedOverlayPool.Ready then
        return
    end

    local stacks = SharedOverlayPool.DiagnosticBoundaryStacks
    local stack = type(stacks) == "table" and stacks[boundaryName] or nil

    if type(stack) ~= "table" or #stack <= 0 then
        return
    end

    -- Hooks execute on the game thread. Keep a per-boundary LIFO stack so the
    -- post callback can inspect the exact Entries captured by the pre callback
    -- even if the ScrollList UObject itself became invalid during destruction.
    local before = stack[#stack]
    stack[#stack] = nil

    local newlyBroken = 0
    local rootBroken = 0
    local treeBroken = 0
    local examples = {}

    for _, snapshot in ipairs(before.Snapshots or {}) do

        local entry = snapshot.Entry
        local afterHealth =
            SharedOverlayPool.GetEntryHealth(entry)

        local brokeRoot =
            snapshot.RootValid
            and not afterHealth.RootValid

        local brokeTree =
            snapshot.TreeValid
            and afterHealth.RootValid
            and not afterHealth.TreeValid

        if brokeRoot or brokeTree then

            newlyBroken = newlyBroken + 1

            if brokeRoot then
                rootBroken = rootBroken + 1
            else
                treeBroken = treeBroken + 1
            end

            if #examples < 5 then
                examples[#examples + 1] =
                    tostring(snapshot.Index)
                    .. ":"
                    .. tostring(afterHealth.InvalidWidget)
                    .. ":parentBefore="
                    .. tostring(snapshot.ParentFullName)
                    .. ":parentAfter="
                    .. tostring(afterHealth.ParentFullName)
            end

        end

        if entry then
            entry.DiagnosticLastBoundary = boundaryName .. ":post"
            entry.DiagnosticLastBoundarySequence = before.Sequence
        end

    end

    if newlyBroken > 0 then
        Log(
            "[PoolLifetimeDiag] DAMAGE DURING",
            boundaryName,
            "/ seq =", before.Sequence,
            "/ tracked =", #(before.Snapshots or {}),
            "/ newlyBroken =", newlyBroken,
            "/ rootBroken =", rootBroken,
            "/ treeBroken =", treeBroken,
            "/ examples =", table.concat(examples, " | "),
            "/ owner =", before.OwnerFullName or "<unknown>"
        )
    end

end

function SharedOverlayPool.IsPagedBoxScrollList(scrollList)

    if not SharedOverlayPool.IsValidObject(scrollList) then
        return false
    end

    local objectName = nil

    pcall(function()

        local fname = scrollList:GetFName()

        if fname then
            objectName = fname:ToString()
        end

    end)

    if not objectName then
        return false
    end

    return
        objectName:find(
            "WBP_BoxPalScrollList",
            1,
            true
        ) == 1

end

local function GetPoolDiagnosticObjectIdentity(obj)

    if not SharedOverlayPool.IsValidObject(obj) then
        return "<invalid>", "<invalid>"
    end

    local objectName = "<unknown>"
    local className = "<unknown>"

    pcall(function()

        local fname = obj:GetFName()

        if fname then
            objectName = fname:ToString()
        end

    end)

    pcall(function()

        local class = obj:GetClass()

        if not class then
            return
        end

        local fname = class:GetFName()

        if fname then
            className = fname:ToString()
        end

    end)

    return objectName, className

end


function SharedOverlayPool.LogScrollListClassification(
    scrollList,
    characterSlotWidget,
    scrollListAddress,
    usePersistentPool,
    hadPooledEntryBeforeClassification
)

    if not DEBUG then
        return
    end

    if not scrollListAddress
        or SharedOverlayPool.DiagnosticScrollListSeen[
            scrollListAddress
        ] then
        return
    end

    SharedOverlayPool.DiagnosticScrollListSeen[
        scrollListAddress
    ] = true

    local scrollName, scrollClass =
        GetPoolDiagnosticObjectIdentity(
            scrollList
        )

    local slotName, slotClass =
        GetPoolDiagnosticObjectIdentity(
            characterSlotWidget
        )

    local excluded = false
    local belongsToPreset = false
    local excludedFromNormalPool = false

    if SharedOverlayPool.IsValidObject(
        characterSlotWidget
    ) then

        local okInspect,
            resultExcluded,
            resultPreset,
            resultPoolExcluded =
            pcall(
                InspectNormalSlotParents,
                characterSlotWidget
            )

        if okInspect then
            excluded = resultExcluded == true
            belongsToPreset = resultPreset == true
            excludedFromNormalPool =
                resultPoolExcluded == true
        end

    end

    Log(
        "[PoolClassify] ScrollList =",
        scrollName,
        "/ Class =",
        scrollClass,
        "/ Persistent =",
        usePersistentPool == true,
        "/ Slot =",
        slotName,
        "/ SlotClass =",
        slotClass,
        "/ ParentExcluded =",
        excluded,
        "/ Preset =",
        belongsToPreset,
        "/ PoolExcluded =",
        excludedFromNormalPool,
        "/ PrePooled =",
        hadPooledEntryBeforeClassification == true
    )

    -- A non-paged list should already have been excluded from the persistent
    -- Pool by the earlier SlotUpdate parent inspection. If PrePooled is true,
    -- the Slot temporarily entered SharedOverlayPool before this authoritative
    -- ScrollList classification point. This is the condition used
    -- to detect for BaseCamp and other auxiliary lists.
    if not usePersistentPool
        and hadPooledEntryBeforeClassification then

        Log(
            "[PoolClassify] WARNING: auxiliary Slot entered Shared Pool before ScrollList classification:",
            scrollName
        )

    end

end


-- return the active generation for one ScrollList, creating a new
-- globally unique generation when this owner has just been (re)activated.
-- The scalar is intentionally global rather than per-address so UObject address
-- reuse can never make an old Slot record current again.
function SharedOverlayPool.GetOrActivateLiveScrollOwnerGeneration(scrollList)

    local scrollListAddress =
        SharedOverlayPool.GetAddress(scrollList)

    if not scrollListAddress then
        return nil
    end

    local state =
        SharedOverlayPool.LiveScrollOwnerStateByAddress[
            scrollListAddress
        ]

    if type(state) == "table"
        and state.Active == true
        and state.Generation then
        return state.Generation
    end

    SharedOverlayPool.LiveScrollOwnerNextGeneration =
        (SharedOverlayPool.LiveScrollOwnerNextGeneration or 0) + 1

    local generation =
        SharedOverlayPool.LiveScrollOwnerNextGeneration

    SharedOverlayPool.LiveScrollOwnerStateByAddress[
        scrollListAddress
    ] = {
        Generation = generation,
        Active = true,
    }

    if DEBUG then

        SharedOverlayPool.DiagnosticLiveScrollOwnerActivated =
            (SharedOverlayPool.DiagnosticLiveScrollOwnerActivated or 0) + 1

        local ownerCount = 0

        for _, ownerState in pairs(
            SharedOverlayPool.LiveScrollOwnerStateByAddress
        ) do
            if type(ownerState) == "table"
                and ownerState.Active == true then
                ownerCount = ownerCount + 1
            end
        end

        if ownerCount > (SharedOverlayPool.DiagnosticLiveScrollOwnerPeak or 0) then
            SharedOverlayPool.DiagnosticLiveScrollOwnerPeak = ownerCount
        end

    end

    return generation

end

function SharedOverlayPool.DeactivateLiveScrollOwner(scrollList, reason)

    local scrollListAddress =
        SharedOverlayPool.GetAddress(scrollList)

    if not scrollListAddress then
        return nil
    end

    local state =
        SharedOverlayPool.LiveScrollOwnerStateByAddress[
            scrollListAddress
        ]

    if type(state) ~= "table" then
        return nil
    end

    local generation = state.Generation

    -- Missing owner state is treated as inactive by validation. Delete the
    -- state entirely so owner addresses do not accumulate across sessions.
    SharedOverlayPool.LiveScrollOwnerStateByAddress[
        scrollListAddress
    ] = nil

    if DEBUG then
        SharedOverlayPool.DiagnosticLiveScrollOwnerDeactivated =
            (SharedOverlayPool.DiagnosticLiveScrollOwnerDeactivated or 0) + 1
    end

    DebugLog(
        "[PoolOwnerGeneration] Deactivated ScrollList owner / generation =",
        generation or 0,
        "/ reason =",
        reason or "cleanup"
    )

    return generation

end

function SharedOverlayPool.IsLiveScrollRecordOwnerActive(record)

    if type(record) ~= "table"
        or not record.OwnerScrollListAddress
        or not record.OwnerGeneration then
        return false
    end

    local state =
        SharedOverlayPool.LiveScrollOwnerStateByAddress[
            record.OwnerScrollListAddress
        ]

    return type(state) == "table"
        and state.Active == true
        and state.Generation == record.OwnerGeneration

end

function SharedOverlayPool.CountActiveLiveScrollOwners()

    local count = 0

    for _, state in pairs(
        SharedOverlayPool.LiveScrollOwnerStateByAddress
    ) do
        if type(state) == "table"
            and state.Active == true then
            count = count + 1
        end
    end

    return count

end

-- register one currently live ScrollList SlotButton. Records remain
-- only while the Button UObject is alive and are removed on Button Destruct.
-- Owner cleanup invalidates the generation instead of deleting these records,
-- which closes the ParentValid window without tombstones.
function SharedOverlayPool.RegisterLiveScrollSlot(
    scrollList,
    slotButton,
    characterSlotWidget,
    usePersistentPool
)

    local scrollListAddress =
        SharedOverlayPool.GetAddress(scrollList)

    local slotButtonAddress =
        SharedOverlayPool.GetAddress(slotButton)

    local widgetAddress =
        SharedOverlayPool.GetAddress(characterSlotWidget)

    if not scrollListAddress
        or not slotButtonAddress
        or not widgetAddress then
        return false
    end

    local ownerGeneration =
        SharedOverlayPool.GetOrActivateLiveScrollOwnerGeneration(
            scrollList
        )

    if not ownerGeneration then
        return false
    end

    local oldButtonAddress =
        SharedOverlayPool.LiveScrollSlotButtonAddressByWidgetAddress[
            widgetAddress
        ]

    if oldButtonAddress
        and oldButtonAddress ~= slotButtonAddress then

        SharedOverlayPool.LiveScrollSlotByButtonAddress[
            oldButtonAddress
        ] = nil

    end

    SharedOverlayPool.LiveScrollSlotByButtonAddress[
        slotButtonAddress
    ] = {
        WidgetAddress = widgetAddress,
        SlotButtonAddress = slotButtonAddress,
        OwnerScrollListAddress = scrollListAddress,
        OwnerGeneration = ownerGeneration,
        PersistentPool = usePersistentPool == true,
    }

    SharedOverlayPool.LiveScrollSlotButtonAddressByWidgetAddress[
        widgetAddress
    ] = slotButtonAddress

    if DEBUG then

        local liveCount = 0

        for _, _ in pairs(
            SharedOverlayPool.LiveScrollSlotByButtonAddress
        ) do
            liveCount = liveCount + 1
        end

        if liveCount
            > (SharedOverlayPool.DiagnosticLiveScrollSlotPeak or 0) then

            SharedOverlayPool.DiagnosticLiveScrollSlotPeak =
                liveCount

        end

    end

    return true

end

-- release an owner generation when its final live SlotButton has
-- disappeared. This prevents non-persistent / auxiliary ScrollList owner
-- states from surviving after every Slot record is gone. Generation matching
-- is mandatory: a delayed Destruct from an old page must never clear a newer
-- generation that reused the same ScrollList address.
function SharedOverlayPool.ReleaseLiveScrollOwnerIfGenerationUnused(
    record,
    reason
)

    if type(record) ~= "table"
        or not record.OwnerScrollListAddress
        or not record.OwnerGeneration then
        return false
    end

    for _, otherRecord in pairs(
        SharedOverlayPool.LiveScrollSlotByButtonAddress
    ) do
        if type(otherRecord) == "table"
            and otherRecord.OwnerScrollListAddress
                == record.OwnerScrollListAddress
            and otherRecord.OwnerGeneration
                == record.OwnerGeneration then
            return false
        end
    end

    local state =
        SharedOverlayPool.LiveScrollOwnerStateByAddress[
            record.OwnerScrollListAddress
        ]

    if type(state) ~= "table"
        or state.Active ~= true
        or state.Generation ~= record.OwnerGeneration then
        return false
    end

    SharedOverlayPool.LiveScrollOwnerStateByAddress[
        record.OwnerScrollListAddress
    ] = nil

    if DEBUG then
        SharedOverlayPool.DiagnosticLiveScrollOwnerDeactivated =
            (SharedOverlayPool.DiagnosticLiveScrollOwnerDeactivated or 0) + 1

        SharedOverlayPool.DiagnosticLiveScrollOwnerReleasedByLastSlot =
            (SharedOverlayPool.DiagnosticLiveScrollOwnerReleasedByLastSlot or 0) + 1
    end

    DebugLog(
        "[PoolOwnerGeneration] Released owner after final SlotButton / generation =",
        record.OwnerGeneration,
        "/ reason =",
        reason or "last slot removed"
    )

    return true

end


function SharedOverlayPool.RemoveLiveScrollSlotButton(
    slotButton,
    reason
)

    local slotButtonAddress =
        SharedOverlayPool.GetAddress(slotButton)

    if not slotButtonAddress then
        return false
    end

    local record =
        SharedOverlayPool.LiveScrollSlotByButtonAddress[
            slotButtonAddress
        ]

    if type(record) ~= "table" then
        return false
    end

    local widgetAddress = record.WidgetAddress

    SharedOverlayPool.LiveScrollSlotByButtonAddress[
        slotButtonAddress
    ] = nil

    if widgetAddress
        and SharedOverlayPool.LiveScrollSlotButtonAddressByWidgetAddress[
            widgetAddress
        ] == slotButtonAddress then

        SharedOverlayPool.LiveScrollSlotButtonAddressByWidgetAddress[
            widgetAddress
        ] = nil

    end

    if DEBUG and reason == "Destruct" then
        SharedOverlayPool.DiagnosticLiveScrollSlotRemovedByDestruct =
            (SharedOverlayPool.DiagnosticLiveScrollSlotRemovedByDestruct or 0) + 1
    end

    SharedOverlayPool.ReleaseLiveScrollOwnerIfGenerationUnused(
        record,
        reason
    )

    return true

end

-- Debug-only residual lifetime inspector. It is disabled in normal release
-- execution and can be enabled temporarily when diagnosing a lifecycle issue.
function SharedOverlayPool.DiagnoseResidualSlotButtonParent(record)

    if not DEBUG then
        return
    end

    if type(record) ~= "table"
        or record.PersistentPool ~= true
        or not record.SlotButtonAddress then
        return
    end

    local targetAddress = record.SlotButtonAddress
    local slotButton = nil

    local okFind, buttons = pcall(function()
        return FindAllOf("WBP_PalCommonCharacterSlotButton_C")
    end)

    if okFind and buttons then

        for _, button in ipairs(buttons) do

            if SharedOverlayPool.GetAddress(button) == targetAddress then
                slotButton = button
                break
            end

        end

    end

    if not SharedOverlayPool.IsValidObject(slotButton) then

        SharedOverlayPool.DiagnosticResidualButtonNotFound =
            (SharedOverlayPool.DiagnosticResidualButtonNotFound or 0) + 1

        Log(
            "[PoolLiveRegistry] Residual cleanup SlotButton parent / state =",
            "ButtonNotFound",
            "/ slotButtonAddress =",
            targetAddress,
            "/ widgetAddress =",
            record.WidgetAddress or 0
        )

        return

    end

    local parent = nil
    local okParent = pcall(function()
        parent = slotButton:GetParent()
    end)

    if not okParent then

        SharedOverlayPool.DiagnosticResidualParentError =
            (SharedOverlayPool.DiagnosticResidualParentError or 0) + 1

        Log(
            "[PoolLiveRegistry] Residual cleanup SlotButton parent / state =",
            "ParentError",
            "/ slotButtonAddress =",
            targetAddress,
            "/ widgetAddress =",
            record.WidgetAddress or 0
        )

        return

    end

    local parentValid = SharedOverlayPool.IsValidObject(parent)

    if parentValid then
        SharedOverlayPool.DiagnosticResidualParentValid =
            (SharedOverlayPool.DiagnosticResidualParentValid or 0) + 1
    else
        SharedOverlayPool.DiagnosticResidualParentNil =
            (SharedOverlayPool.DiagnosticResidualParentNil or 0) + 1
    end

    Log(
        "[PoolLiveRegistry] Residual cleanup SlotButton parent / state =",
        parentValid and "ParentValid" or "ParentNil",
        "/ slotButtonAddress =",
        targetAddress,
        "/ widgetAddress =",
        record.WidgetAddress or 0
    )

end

function SharedOverlayPool.RemoveLiveScrollSlotsForScrollList(
    scrollList,
    reason
)

    local scrollListAddress =
        SharedOverlayPool.GetAddress(scrollList)

    if not scrollListAddress then
        return 0
    end

    local removed = 0
    local removeButtons = {}

    for slotButtonAddress, record
        in pairs(SharedOverlayPool.LiveScrollSlotByButtonAddress) do

        if type(record) == "table"
            and record.OwnerScrollListAddress == scrollListAddress then

            removeButtons[#removeButtons + 1] = slotButtonAddress

        end

    end

    for _, slotButtonAddress in ipairs(removeButtons) do

        local record =
            SharedOverlayPool.LiveScrollSlotByButtonAddress[
                slotButtonAddress
            ]

        if type(record) == "table" then

            -- inspect only records that survived until owner cleanup.
            -- This is the stale-owner cleanup path for a removed live slot.
            SharedOverlayPool.DiagnoseResidualSlotButtonParent(record)

            local widgetAddress = record.WidgetAddress

            SharedOverlayPool.LiveScrollSlotByButtonAddress[
                slotButtonAddress
            ] = nil

            if widgetAddress
                and SharedOverlayPool.LiveScrollSlotButtonAddressByWidgetAddress[
                    widgetAddress
                ] == slotButtonAddress then

                SharedOverlayPool.LiveScrollSlotButtonAddressByWidgetAddress[
                    widgetAddress
                ] = nil

            end

            removed = removed + 1

        end

    end

    if DEBUG then
        SharedOverlayPool.DiagnosticLiveScrollSlotRemovedByCleanup =
            (SharedOverlayPool.DiagnosticLiveScrollSlotRemovedByCleanup or 0) + removed
    end

    if removed > 0 then
        DebugLog(
            "[PoolLiveRegistry] Removed live ScrollList slots:",
            removed,
            "/ reason =",
            reason or "cleanup"
        )
    end

    return removed

end

function SharedOverlayPool.GetLiveScrollSlotRecord(widgetAddress)

    if not widgetAddress then
        return nil
    end

    local slotButtonAddress =
        SharedOverlayPool.LiveScrollSlotButtonAddressByWidgetAddress[
            widgetAddress
        ]

    if not slotButtonAddress then
        return nil
    end

    local record =
        SharedOverlayPool.LiveScrollSlotByButtonAddress[
            slotButtonAddress
        ]

    if type(record) ~= "table"
        or record.WidgetAddress ~= widgetAddress then
        return nil
    end

    return record

end

-- Fallback for a SlotUpdate that no longer has a live ScrollList record.
-- A freshly created ScrollList Button is registered before Setup(), while a
-- retired Button has already been removed from its Panel by ClearChildren().
-- Therefore an unregistered Common SlotButton with no current parent is a stale
-- dynamic ScrollList Slot and must not reacquire a pooled Entry.
function SharedOverlayPool.IsDetachedUnregisteredSlot(widget)

    if not SharedOverlayPool.IsValidObject(widget) then
        return false
    end

    local slotButton = nil

    local okButton = pcall(function()

        local widgetTree = widget:GetOuter()
        slotButton = widgetTree and widgetTree:GetOuter() or nil

    end)

    if not okButton
        or not SharedOverlayPool.IsValidObject(slotButton) then
        return false
    end

    local parent = nil

    local okParent = pcall(function()
        parent = slotButton:GetParent()
    end)

    if not okParent then
        return false
    end

    return not SharedOverlayPool.IsValidObject(parent)

end

function SharedOverlayPool.CountLiveScrollSlots()

    local count = 0

    for _, _ in pairs(
        SharedOverlayPool.LiveScrollSlotByButtonAddress
    ) do
        count = count + 1
    end

    return count

end

-- Debug helper: identify the stable outer class chain for a
-- common SlotButton without depending on a specific screen Hook. GetFullName
-- is intentionally not used here; only the short UObject/Class FNames of at
-- most eight Outer levels are sampled, and only for non-ScrollList Buttons.
function SharedOverlayPool.GetCommonSlotContextSignature(slotButton)

    if not DEBUG then
        return nil
    end

    if not SharedOverlayPool.IsValidObject(slotButton) then
        return "<invalid>"
    end

    local parts = {}
    local current = slotButton

    for depth = 1, 8 do

        if not SharedOverlayPool.IsValidObject(current) then
            break
        end

        local objectName, className =
            GetPoolDiagnosticObjectIdentity(current)

        parts[#parts + 1] =
            tostring(className) .. ":" .. tostring(objectName)

        if className == "Package" then
            break
        end

        local nextOuter = nil
        local okOuter = pcall(function()
            nextOuter = current:GetOuter()
        end)

        if not okOuter or nextOuter == current then
            break
        end

        current = nextOuter

    end

    if #parts == 0 then
        return "<unknown>"
    end

    return table.concat(parts, " > ")

end

-- register the exact common SlotButton -> inner CharacterSlot identity
-- from WBP_PalCharacterSlotButtonBase::Setup* pre-Hooks. Unlike the existing
-- ScrollList registry, this does not depend on any owner screen and therefore
-- can observe Party / Preset / condensation / auxiliary common SlotButtons.
-- It is used only for debug diagnostics.
function SharedOverlayPool.RegisterLiveCommonSlotButton(slotButton, source)

    if not SharedOverlayPool.IsValidObject(slotButton) then
        return false
    end

    local characterSlotWidget = nil

    local okWidget = pcall(function()
        characterSlotWidget = slotButton.MyCharacterSlotWidget
    end)

    if not okWidget
        or not SharedOverlayPool.IsValidObject(characterSlotWidget) then
        return false
    end

    local slotButtonAddress =
        SharedOverlayPool.GetAddress(slotButton)

    local widgetAddress =
        SharedOverlayPool.GetAddress(characterSlotWidget)

    if not slotButtonAddress or not widgetAddress then
        return false
    end

    local oldButtonAddress =
        SharedOverlayPool.LiveCommonSlotButtonAddressByWidgetAddress[
            widgetAddress
        ]

    if oldButtonAddress
        and oldButtonAddress ~= slotButtonAddress then

        SharedOverlayPool.LiveCommonSlotByButtonAddress[
            oldButtonAddress
        ] = nil

    end

    local scrollRecord =
        SharedOverlayPool.LiveScrollSlotByButtonAddress[
            slotButtonAddress
        ]

    local isScrollList =
        type(scrollRecord) == "table"

    local contextSignature = nil

    if not isScrollList and DEBUG then

        contextSignature =
            SharedOverlayPool.GetCommonSlotContextSignature(
                slotButton
            )

        SharedOverlayPool.DiagnosticCommonNonScrollSetup =
            (SharedOverlayPool.DiagnosticCommonNonScrollSetup or 0) + 1

        local contextKey =
            tostring(source or "Setup")
            .. "|"
            .. tostring(contextSignature)

        if not SharedOverlayPool.DiagnosticCommonNonScrollContextSeen[
            contextKey
        ] then

            SharedOverlayPool.DiagnosticCommonNonScrollContextSeen[
                contextKey
            ] = true

            Log(
                "[CommonButtonLifeDiag] Non-scroll Setup",
                "/ source =",
                source or "Setup",
                "/ widgetAddress =",
                widgetAddress,
                "/ slotButtonAddress =",
                slotButtonAddress,
                "/ context =",
                contextSignature
            )

        end

    end

    SharedOverlayPool.LiveCommonSlotByButtonAddress[
        slotButtonAddress
    ] = {
        WidgetAddress = widgetAddress,
        SlotButtonAddress = slotButtonAddress,
        Source = source or "Setup",
        IsScrollList = isScrollList,
        ContextSignature = contextSignature,
        Retiring = false,
        RetireReason = nil,
        RetireSequence = nil,
    }

    SharedOverlayPool.LiveCommonSlotButtonAddressByWidgetAddress[
        widgetAddress
    ] = slotButtonAddress

    -- Setup* is the authoritative reactivation point for a static
    -- Common Button. A prior Destruct diagnostic for this same CharacterSlot
    -- must not classify the new live generation as post-Destruct traffic.
    SharedOverlayPool.DiagnosticSlotButtonDestructByWidgetAddress[
        widgetAddress
    ] = nil

    if DEBUG then

        if source == "SetupByCharacterID" then
            SharedOverlayPool.DiagnosticLiveCommonSetupByCharacterID =
                (SharedOverlayPool.DiagnosticLiveCommonSetupByCharacterID or 0) + 1
        elseif source == "SetupByIndividualId" then
            SharedOverlayPool.DiagnosticLiveCommonSetupByIndividualId =
                (SharedOverlayPool.DiagnosticLiveCommonSetupByIndividualId or 0) + 1
        elseif source == "SetupBySaveParameter" then
            SharedOverlayPool.DiagnosticLiveCommonSetupBySaveParameter =
                (SharedOverlayPool.DiagnosticLiveCommonSetupBySaveParameter or 0) + 1
        else
            SharedOverlayPool.DiagnosticLiveCommonSetup =
                (SharedOverlayPool.DiagnosticLiveCommonSetup or 0) + 1
        end

        local liveCount = 0

        for _, _ in pairs(SharedOverlayPool.LiveCommonSlotByButtonAddress) do
            liveCount = liveCount + 1
        end

        if liveCount > (SharedOverlayPool.DiagnosticLiveCommonSlotPeak or 0) then
            SharedOverlayPool.DiagnosticLiveCommonSlotPeak = liveCount
        end

    end

    return true

end

function SharedOverlayPool.RemoveLiveCommonSlotButton(slotButton)

    local slotButtonAddress =
        SharedOverlayPool.GetAddress(slotButton)

    if not slotButtonAddress then
        return false
    end

    local record =
        SharedOverlayPool.LiveCommonSlotByButtonAddress[
            slotButtonAddress
        ]

    if type(record) ~= "table" then
        return false
    end

    local widgetAddress = record.WidgetAddress

    -- keep retirement protection until the exact owning Button has
    -- physically reached Destruct, then release only that matching marker.
    -- Do not clear by CharacterSlot address alone: UObject addresses can be
    -- recycled across widget lifetimes.
    if widgetAddress then

        local retireRecord =
            SharedOverlayPool.WidgetRetiringReasonByAddress[
                widgetAddress
            ]

        if type(retireRecord) == "table"
            and retireRecord.SlotButtonAddress == slotButtonAddress then

            SharedOverlayPool.WidgetRetiringReasonByAddress[
                widgetAddress
            ] = nil

            if DEBUG then
                SharedOverlayPool.DiagnosticRetiringMarkerClearedByButtonDestruct =
                    (SharedOverlayPool.DiagnosticRetiringMarkerClearedByButtonDestruct or 0) + 1
            end

        end

    end

    SharedOverlayPool.LiveCommonSlotByButtonAddress[
        slotButtonAddress
    ] = nil

    if widgetAddress
        and SharedOverlayPool.LiveCommonSlotButtonAddressByWidgetAddress[
            widgetAddress
        ] == slotButtonAddress then

        SharedOverlayPool.LiveCommonSlotButtonAddressByWidgetAddress[
            widgetAddress
        ] = nil

    end

    if record.IsScrollList == false and DEBUG then

        SharedOverlayPool.DiagnosticCommonNonScrollRemoved =
            (SharedOverlayPool.DiagnosticCommonNonScrollRemoved or 0) + 1

        local contextSignature =
            record.ContextSignature or "<unknown>"

        local contextKey =
            tostring(record.Source or "Setup")
            .. "|"
            .. tostring(contextSignature)

        if not SharedOverlayPool.DiagnosticCommonNonScrollDestructContextSeen[
            contextKey
        ] then

            SharedOverlayPool.DiagnosticCommonNonScrollDestructContextSeen[
                contextKey
            ] = true

            Log(
                "[CommonButtonLifeDiag] Non-scroll Destruct",
                "/ source =",
                record.Source or "Setup",
                "/ widgetAddress =",
                widgetAddress,
                "/ slotButtonAddress =",
                slotButtonAddress,
                "/ context =",
                contextSignature
            )

        end

    end

    if DEBUG then
        SharedOverlayPool.DiagnosticLiveCommonRemovedByDestruct =
            (SharedOverlayPool.DiagnosticLiveCommonRemovedByDestruct or 0) + 1
    end

    return true

end

function SharedOverlayPool.CountLiveCommonSlots()

    local count = 0

    for _, _ in pairs(SharedOverlayPool.LiveCommonSlotByButtonAddress) do
        count = count + 1
    end

    return count

end

function SharedOverlayPool.GetLiveCommonSlotRecord(widgetAddress)

    if not widgetAddress then
        return nil
    end

    local slotButtonAddress =
        SharedOverlayPool.LiveCommonSlotButtonAddressByWidgetAddress[
            widgetAddress
        ]

    if not slotButtonAddress then
        return nil
    end

    local record =
        SharedOverlayPool.LiveCommonSlotByButtonAddress[
            slotButtonAddress
        ]

    if type(record) ~= "table"
        or record.WidgetAddress ~= widgetAddress
        or record.SlotButtonAddress ~= slotButtonAddress then
        return nil
    end

    return record

end

function SharedOverlayPool.MarkLiveCommonSlotRetiring(
    widgetAddress,
    reason,
    retireSequence
)

    local record =
        SharedOverlayPool.GetLiveCommonSlotRecord(
            widgetAddress
        )

    if type(record) ~= "table" then
        return false
    end

    record.Retiring = true
    record.RetireReason = reason or "Preset Destruct"
    record.RetireSequence = retireSequence

    if DEBUG then
        SharedOverlayPool.DiagnosticCommonRetiringMarked =
            (SharedOverlayPool.DiagnosticCommonRetiringMarked or 0) + 1
    end

    return true

end

function SharedOverlayPool.CountRetiringLiveCommonSlots()

    local count = 0

    for _, record
        in pairs(SharedOverlayPool.LiveCommonSlotByButtonAddress) do

        if type(record) == "table"
            and record.Retiring == true then
            count = count + 1
        end

    end

    return count

end

function SharedOverlayPool.GetWidgetPoolMode(widget)

    local address =
        SharedOverlayPool.GetAddress(widget)

    if not address then
        return nil
    end

    return
        SharedOverlayPool.WidgetPoolModeByAddress[
            address
        ],
        address

end

function SharedOverlayPool.BeginRetireLifetime(reason)

    if not DEBUG then
        return nil
    end

    SharedOverlayPool.DiagnosticRetireSequence =
        (SharedOverlayPool.DiagnosticRetireSequence or 0) + 1

    local sequence =
        SharedOverlayPool.DiagnosticRetireSequence

    SharedOverlayPool.DiagnosticRetireStateBySequence[
        sequence
    ] = {
        Sequence = sequence,
        Reason = reason or "cleanup",
        Returned = false,
        BlockedDuringCleanup = 0,
        BlockedAfterCleanup = 0,
        ReusedDuringCleanup = 0,
        ReusedAfterCleanup = 0,
        ButtonDestructDuringCleanup = 0,
        ButtonDestructAfterCleanup = 0,
        BlockedBeforeButtonDestruct = 0,
        BlockedAfterButtonDestruct = 0,
        BlockedUnknownButtonDestruct = 0,
    }

    return sequence

end

function SharedOverlayPool.CountRetiringMarkers()

    local count = 0

    for _, _ in pairs(
        SharedOverlayPool.WidgetRetiringReasonByAddress
    ) do
        count = count + 1
    end

    return count

end


function SharedOverlayPool.MarkRetireCleanupReturned(sequence)

    local state =
        sequence
        and SharedOverlayPool.DiagnosticRetireStateBySequence[
            sequence
        ]
        or nil

    if type(state) ~= "table" then
        return false
    end

    state.Returned = true

    -- Debug-only: quantify how many retiring address tombstones
    -- remain after cleanup without changing their lifetime or behavior.
    local retainedMarkers =
        SharedOverlayPool.CountRetiringMarkers()

    if retainedMarkers
        > (SharedOverlayPool.DiagnosticRetiringMarkerPeak or 0) then

        SharedOverlayPool.DiagnosticRetiringMarkerPeak =
            retainedMarkers

    end

    Log(
        "[PoolRetireLifetime] Cleanup callback returned / seq =",
        sequence,
        "/ reason =",
        state.Reason or "cleanup",
        "/ blockedDuring =",
        state.BlockedDuringCleanup or 0,
        "/ reusedDuring =",
        state.ReusedDuringCleanup or 0,
        "/ buttonDestructDuring =",
        state.ButtonDestructDuringCleanup or 0,
        "/ commonRetiringNow =",
        SharedOverlayPool.CountRetiringLiveCommonSlots(),
        "/ commonRetiringMarked =",
        SharedOverlayPool.DiagnosticCommonRetiringMarked or 0,
        "/ commonRetiringBlocked =",
        SharedOverlayPool.DiagnosticCommonRetiringBlocked or 0,
        "/ commonRetiringFallback =",
        SharedOverlayPool.DiagnosticCommonRetiringFallbackMarker or 0,
        "/ retainedMarkers =",
        retainedMarkers,
        "/ peakMarkers =",
        SharedOverlayPool.DiagnosticRetiringMarkerPeak or 0
    )

    return true

end


function SharedOverlayPool.ClearWidgetModesForScrollList(
    scrollList,
    retireReason,
    retireSequence
)

    local scrollListAddress =
        SharedOverlayPool.GetAddress(scrollList)

    if not scrollListAddress then
        return 0
    end

    local cleared = 0

    for widgetAddress, ownerAddress
        in pairs(
            SharedOverlayPool.WidgetScrollListAddressByWidgetAddress
        ) do

        if ownerAddress == scrollListAddress then

            -- normal ScrollList retirement no longer leaves an
            -- address tombstone. Live eligibility is represented only by the
            -- bounded LiveScrollSlot registry and is removed separately before
            -- pooled Entries are parked.
            SharedOverlayPool.WidgetRetiringReasonByAddress[
                widgetAddress
            ] = nil

            SharedOverlayPool.WidgetScrollListAddressByWidgetAddress[
                widgetAddress
            ] = nil

            SharedOverlayPool.WidgetPoolModeByAddress[
                widgetAddress
            ] = nil

            SharedOverlayPool.WidgetSlotButtonAddressByWidgetAddress[
                widgetAddress
            ] = nil

            cleared = cleared + 1

        end

    end

    return cleared

end

function SharedOverlayPool.ResolveAttachOwner(
    widgetAddress,
    ownerHint
)

    if not widgetAddress then
        return nil, nil
    end

    -- Preset binding is explicit and synchronous. The caller must provide
    -- the exact Preset row address so an Entry is never attached without
    -- lifecycle ownership.
    if type(ownerHint) == "table"
        and ownerHint.Kind == "Preset"
        and ownerHint.RowAddress ~= nil then

        return "Preset", ownerHint.RowAddress

    end

    -- Dynamic paged PalBox Slots are registered from BindButtonEvents before
    -- Button::Setup() -> SlotUpdate. Only the current active owner generation
    -- is eligible to acquire a Shared Pool Entry.
    local liveScrollRecord =
        SharedOverlayPool.GetLiveScrollSlotRecord(
            widgetAddress
        )

    if type(liveScrollRecord) == "table"
        and liveScrollRecord.PersistentPool == true
        and SharedOverlayPool.IsLiveScrollRecordOwnerActive(
            liveScrollRecord
        )
        and liveScrollRecord.OwnerScrollListAddress ~= nil then

        return
            "ScrollList",
            liveScrollRecord.OwnerScrollListAddress

    end

    -- Static non-ScrollList Common Buttons (for example condensation Party
    -- Slots) are eligible only after their exact Button identity is known.
    -- A retiring Common record is never allowed to reacquire an Entry.
    local liveCommonRecord =
        SharedOverlayPool.GetLiveCommonSlotRecord(
            widgetAddress
        )

    if type(liveCommonRecord) == "table"
        and liveCommonRecord.IsScrollList == false
        and liveCommonRecord.Retiring ~= true
        and liveCommonRecord.SlotButtonAddress ~= nil then

        return
            "Common",
            liveCommonRecord.SlotButtonAddress

    end

    return nil, nil

end

function SharedOverlayPool.AttachEntry(
    entry,
    widget,
    canvas,
    knownAddress,
    ownerHint,
    resolvedOwnerKind,
    resolvedOwnerAddress
)

    if not entry
        or not SharedOverlayPool.IsValidObject(canvas) then
        return false
    end

    if not SharedOverlayPool.ValidateEntryTree(
        entry,
        "Attach preflight"
    ) then
        return false
    end

    local widgetAddress =
        knownAddress
        or SharedOverlayPool.GetAddress(widget)

    if not widgetAddress then
        return false
    end

    -- Pool invariant: an Entry must never be attached to a live Widget tree
    -- without an exact lifecycle owner. This removes AttachedPendingOwner as
    -- a normal runtime state and prevents an unowned Entry from dying with an
    -- unrelated transient Widget tree.
    if resolvedOwnerKind == nil
        or resolvedOwnerAddress == nil then

        return false

    end

    if not entry.DynamicCache then
        entry.DynamicCache =
            CreatePoolDynamicCache()
    end

    if entry.RootVisible then

        if not SharedOverlayPool.IsValidObject(entry.Root) then
            return false
        end

        SetWidgetVisible(
            entry.Root,
            false
        )

        entry.RootVisible = false

    end

    local attachBeforeDetach =
        SharedOverlayPool.GetEntryHealth(entry)

    local detached, detachReason =
        SharedOverlayPool.DetachRootSafely(
            entry.Root
        )

    SharedOverlayPool.LogPhaseDamage(
        entry,
        "Attach RemoveFromParent",
        attachBeforeDetach
    )

    if not detached then

        Log(
            "[OverlayPoolSafety] Attach aborted / Entry",
            entry.Index,
            "/",
            detachReason or "detach failed"
        )

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Attach: " .. tostring(detachReason or "detach failed")
        )

        return false

    end

    if not SharedOverlayPool.IsValidObject(canvas)
        or not SharedOverlayPool.IsValidObject(entry.Root) then

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Attach: target or Root invalid after detach"
        )

        return false
    end

    local attachBeforeAdd =
        SharedOverlayPool.GetEntryHealth(entry)

    local rootSlot, addReason =
        SharedOverlayPool.AddRootSafely(
            canvas,
            entry.Root
        )

    SharedOverlayPool.LogPhaseDamage(
        entry,
        "Attach AddChild",
        attachBeforeAdd
    )

    if not rootSlot then

        Log(
            "[OverlayPoolSafety] Attach AddChild aborted / Entry",
            entry.Index,
            "/",
            addReason or "AddChild failed"
        )

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Attach AddChild: " .. tostring(addReason or "failed")
        )

        return false
    end

    if not SharedOverlayPool.IsValidObject(rootSlot)
        or not SharedOverlayPool.SetupRootSlot(
            rootSlot
        ) then

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Attach: Root slot invalid or setup failed"
        )

        return false
    end

    entry.BoundWidgetAddress = widgetAddress

    -- Ownership was resolved before any Widget-tree mutation. Commit exactly
    -- one owner kind; no pooled Entry may remain ownerless after AttachEntry.
    entry.OwnerScrollListAddress = nil
    entry.OwnerPresetRowAddress = nil
    entry.OwnerCommonSlotButtonAddress = nil

    if resolvedOwnerKind == "ScrollList" then

        entry.OwnerScrollListAddress =
            resolvedOwnerAddress

        entry.DiagnosticState = "AttachedScrollList"
        entry.DiagnosticLastTransition =
            "AttachEntryResolvedScrollOwner"

    elseif resolvedOwnerKind == "Preset" then

        entry.OwnerPresetRowAddress =
            resolvedOwnerAddress

        entry.DiagnosticState = "AttachedPreset"
        entry.DiagnosticLastTransition =
            "AttachEntryResolvedPresetOwner"

    elseif resolvedOwnerKind == "Common" then

        entry.OwnerCommonSlotButtonAddress =
            resolvedOwnerAddress

        entry.DiagnosticState = "AttachedCommonButton"
        entry.DiagnosticLastTransition =
            "AttachEntryResolvedCommonOwner"

        if DEBUG then
            SharedOverlayPool.DiagnosticCommonOwnedEntryAttached =
                (SharedOverlayPool.DiagnosticCommonOwnedEntryAttached or 0) + 1
        end

    else

        return false

    end

    SharedOverlayPool.EntryByWidgetAddress[
        widgetAddress
    ] = entry

    entry.DiagnosticLastParentFullName =
        SharedOverlayPool.GetDiagnosticFullName(canvas)

    return true

end

function SharedOverlayPool.AcquireEntry(
    widget,
    canvas,
    knownAddress,
    ownerHint
)

    local existing =
        SharedOverlayPool.GetEntryForWidget(
            widget,
            knownAddress
        )

    if existing then
        return existing
    end

    local widgetAddress =
        knownAddress
        or SharedOverlayPool.GetAddress(widget)

    local resolvedOwnerKind, resolvedOwnerAddress =
        SharedOverlayPool.ResolveAttachOwner(
            widgetAddress,
            ownerHint
        )

    if resolvedOwnerKind == nil
        or resolvedOwnerAddress == nil then

        -- Setup-time SlotUpdate can legitimately run before a static Common
        -- Button hook has published its exact lifecycle owner. Do not attach
        -- an ownerless Entry; report this as a deferred acquisition so the
        -- caller can wait for the authoritative later boundary instead of
        -- treating it as Pool damage.
        return nil, "OwnerPending"

    end

    if not SharedOverlayPool.EnsureReadyNow() then
        return nil, "PoolUnavailable"
    end

    local function TryAttachFreeEntry()

        for _, entry
            in ipairs(SharedOverlayPool.Entries) do

            if SharedOverlayPool.IsEntryFree(entry) then

                if SharedOverlayPool.AttachEntry(
                    entry,
                    widget,
                    canvas,
                    knownAddress,
                    ownerHint,
                    resolvedOwnerKind,
                    resolvedOwnerAddress
                ) then
                    return entry
                end

                -- If an Entry became invalid unexpectedly, continue looking
                -- for another free Entry before falling back to adaptive growth.

            end

        end

        return nil

    end

    local freeEntry =
        TryAttachFreeEntry()

    if freeEntry then
        return freeEntry
    end

    -- Before growing the Pool, discard records whose Root was already destroyed
    -- by an earlier menu transition. This prevents missed lifecycle cleanup from
    -- turning into permanent Pool growth over a long play session.
    if SharedOverlayPool.CompactInvalidEntries(
        "Acquire exhausted"
    ) > 0 then

        freeEntry =
            TryAttachFreeEntry()

        if freeEntry then
            return freeEntry
        end

    end

    -- No free Entry remains. Grow the high-water capacity by one complete
    -- 34-Widget Entry. The startup target is prewarmed synchronously, so this
    -- path is normally reached only by layouts that need more than 80 shared
    -- Normal/Preset Entries at the same time.
    local entry =
        SharedOverlayPool.AppendEntry(
            "sync"
        )

    if not entry then
        return nil
    end

    if SharedOverlayPool.AttachEntry(
        entry,
        widget,
        canvas,
        knownAddress,
        ownerHint,
        resolvedOwnerKind,
        resolvedOwnerAddress
    ) then
        return entry
    end

    return nil

end

function SharedOverlayPool.ParkEntry(
    entry,
    reason
)

    if not entry then
        return false
    end

    local oldWidgetAddress =
        entry.BoundWidgetAddress

    if oldWidgetAddress then

        SharedOverlayPool.EntryByWidgetAddress[
            oldWidgetAddress
        ] = nil

    end

    if not SharedOverlayPool.IsValidObject(entry.Root) then

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Park: Root invalid"
        )

        return false
    end

    if entry.RootVisible then

        SetWidgetVisible(
            entry.Root,
            false
        )

        entry.RootVisible = false

    end

    local parkBeforeDetach =
        SharedOverlayPool.GetEntryHealth(entry)

    local detached, detachReason =
        SharedOverlayPool.DetachRootSafely(
            entry.Root
        )

    SharedOverlayPool.LogPhaseDamage(
        entry,
        "Park RemoveFromParent",
        parkBeforeDetach
    )

    if not detached then

        Log(
            "[OverlayPoolSafety] Park aborted / Entry",
            entry.Index,
            "/",
            detachReason or "detach failed"
        )

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Park: " .. tostring(detachReason or "detach failed")
        )

        return false
    end

    local parkingRoot =
        SharedOverlayPool.ParkingRoot

    if not SharedOverlayPool.IsValidObject(parkingRoot)
        or not SharedOverlayPool.IsValidObject(entry.Root) then

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Park: ParkingRoot or Root invalid after detach"
        )

        return false
    end

    local parkBeforeAdd =
        SharedOverlayPool.GetEntryHealth(entry)

    local parkingSlot, addReason =
        SharedOverlayPool.AddRootSafely(
            parkingRoot,
            entry.Root
        )

    SharedOverlayPool.LogPhaseDamage(
        entry,
        "Park AddChild",
        parkBeforeAdd
    )

    if not parkingSlot then

        Log(
            "[OverlayPoolSafety] Park AddChild aborted / Entry",
            entry.Index,
            "/",
            addReason or "AddChild failed"
        )

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Park AddChild: " .. tostring(addReason or "failed")
        )

        return false
    end

    if not SharedOverlayPool.IsValidObject(parkingSlot) then

        SharedOverlayPool.QuarantineEntry(
            entry,
            "Park: Parking slot invalid after AddChild"
        )

        return false
    end

    SharedOverlayPool.SetupParkingSlot(parkingSlot)

    entry.BoundWidgetAddress = nil
    entry.OwnerScrollListAddress = nil
    entry.OwnerPresetRowAddress = nil
    entry.OwnerCommonSlotButtonAddress = nil
    entry.LastSave = nil

    entry.DiagnosticState = "Parked"
    entry.DiagnosticLastTransition = "ParkEntry"
    entry.DiagnosticLastParkReason = reason or "unspecified"
    entry.DiagnosticLastParentFullName =
        SharedOverlayPool.GetDiagnosticFullName(parkingRoot)

    DebugLog(
        "[OverlayPool] Entry",
        entry.Index,
        "parked:",
        reason or "unspecified"
    )

    return true

end

-- reclaim a Shared Pool Entry at the exact physical lifetime end
-- of a non-ScrollList CommonCharacterSlotButton. The Common live record was
-- registered before Setup* -> SlotUpdate, so the Button address is a bounded
-- positive identity rather than a retired-address tombstone.
function SharedOverlayPool.ParkEntryForCommonSlotButton(
    slotButton,
    reason
)

    local slotButtonAddress =
        SharedOverlayPool.GetAddress(
            slotButton
        )

    if not slotButtonAddress then
        return false
    end

    local commonRecord =
        SharedOverlayPool.LiveCommonSlotByButtonAddress[
            slotButtonAddress
        ]

    if type(commonRecord) ~= "table"
        or commonRecord.SlotButtonAddress ~= slotButtonAddress then
        return false
    end

    local widgetAddress =
        commonRecord.WidgetAddress

    if not widgetAddress then
        return false
    end

    local entry =
        SharedOverlayPool.EntryByWidgetAddress[
            widgetAddress
        ]

    if not entry
        or entry.OwnerCommonSlotButtonAddress ~= slotButtonAddress then
        return false
    end

    local parked =
        SharedOverlayPool.ParkEntry(
            entry,
            reason or "Common SlotButton Destruct"
        )

    if not parked then
        return false
    end

    if DEBUG then

        SharedOverlayPool.DiagnosticCommonOwnedEntryParkedByDestruct =
            (SharedOverlayPool.DiagnosticCommonOwnedEntryParkedByDestruct or 0) + 1

        local parkedCount =
            SharedOverlayPool.DiagnosticCommonOwnedEntryParkedByDestruct

        if parkedCount <= 20
            or parkedCount % 100 == 0 then

            Log(
                "[PoolCommonOwner] Parked Entry on SlotButton Destruct / count =",
                parkedCount,
                "/ widgetAddress =",
                widgetAddress,
                "/ slotButtonAddress =",
                slotButtonAddress,
                "/ source =",
                commonRecord.Source or "Setup",
                "/ context =",
                commonRecord.ContextSignature or "<unknown>"
            )

        end

    end

    return true

end

function SharedOverlayPool.ParkEntriesForScrollList(
    scrollList,
    reason
)

    local scrollListAddress =
        SharedOverlayPool.GetAddress(
            scrollList
        )

    if not scrollListAddress then
        return 0
    end

    local parkedCount = 0

    for _, entry
        in ipairs(SharedOverlayPool.Entries) do

        if entry.OwnerScrollListAddress
            == scrollListAddress then

            if SharedOverlayPool.ParkEntry(
                entry,
                reason
            ) then
                parkedCount = parkedCount + 1
            end

        end

    end

    if parkedCount > 0 then

        DebugLog(
            "[OverlayPool] Parked",
            parkedCount,
            "Entries:",
            reason or "unspecified",
            "/ Pool size =",
            #SharedOverlayPool.Entries
        )

    end

    return parkedCount

end

-- Debug-only diagnostic.
-- Record the exact CommonCharacterSlotButton identity when its Destruct event
-- fires. If the CharacterSlot is retiring, also bind that Destruct to the exact
-- cleanup sequence so Destruct-before/after-cleanup can be measured directly.
-- This does not change Pool ownership, retirement, or SlotUpdate flow.
function SharedOverlayPool.RecordSlotButtonDestruct(slotButton)

    if not DEBUG then
        return false
    end

    if not SharedOverlayPool.IsValidObject(slotButton) then
        return false
    end

    local characterSlotWidget = nil

    pcall(function()
        characterSlotWidget = slotButton.MyCharacterSlotWidget
    end)

    if not SharedOverlayPool.IsValidObject(characterSlotWidget) then
        return false
    end

    local widgetAddress =
        SharedOverlayPool.GetAddress(characterSlotWidget)

    local slotButtonAddress =
        SharedOverlayPool.GetAddress(slotButton)

    if not widgetAddress or not slotButtonAddress then
        return false
    end

    SharedOverlayPool.DiagnosticSlotButtonDestructCount =
        (SharedOverlayPool.DiagnosticSlotButtonDestructCount or 0) + 1

    SharedOverlayPool.DiagnosticSlotButtonDestructByWidgetAddress[
        widgetAddress
    ] = {
        SlotButtonAddress = slotButtonAddress,
        Sequence = SharedOverlayPool.DiagnosticSlotButtonDestructCount,
    }

    local retireRecord =
        SharedOverlayPool.WidgetRetiringReasonByAddress[
            widgetAddress
        ]

    if type(retireRecord) == "table" then

        local cleanupSequence = retireRecord.CleanupSequence
        local retireState =
            cleanupSequence
            and SharedOverlayPool.DiagnosticRetireStateBySequence[
                cleanupSequence
            ]
            or nil

        if type(retireState) == "table" then

            if retireState.Returned == true then

                retireState.ButtonDestructAfterCleanup =
                    (retireState.ButtonDestructAfterCleanup or 0) + 1

                SharedOverlayPool.DiagnosticSlotButtonDestructAfterCleanupCount =
                    (SharedOverlayPool.DiagnosticSlotButtonDestructAfterCleanupCount or 0) + 1

                Log(
                    "[PoolButtonLifeDiag] SlotButton Destruct AFTER cleanup / count =",
                    SharedOverlayPool.DiagnosticSlotButtonDestructAfterCleanupCount,
                    "/ cleanupSeq =",
                    cleanupSequence or 0,
                    "/ reason =",
                    retireRecord.Reason or "<unknown>",
                    "/ widgetAddress =",
                    widgetAddress,
                    "/ slotButtonAddress =",
                    slotButtonAddress
                )

            else

                retireState.ButtonDestructDuringCleanup =
                    (retireState.ButtonDestructDuringCleanup or 0) + 1

            end

        end

    end

    return true

end

-- Debug-only diagnostic.
-- Return true when this SlotUpdate belongs to the same SlotButton identity that
-- has already emitted Destruct. A different SlotButton address means the
-- CharacterSlot address was reused by a newly created live Button.
function SharedOverlayPool.ObserveSlotUpdateAfterButtonDestruct(
    widget,
    widgetAddress
)

    if not DEBUG then
        return false
    end

    if not widgetAddress then
        return false
    end

    local record =
        SharedOverlayPool.DiagnosticSlotButtonDestructByWidgetAddress[
            widgetAddress
        ]

    if type(record) ~= "table" then
        return false
    end

    local currentSlotButtonAddress = nil

    pcall(function()

        local widgetTree = widget:GetOuter()
        local slotButton =
            widgetTree
            and widgetTree:GetOuter()
            or nil

        currentSlotButtonAddress =
            SharedOverlayPool.GetAddress(slotButton)

    end)

    if currentSlotButtonAddress
        and record.SlotButtonAddress
        and currentSlotButtonAddress
            ~= record.SlotButtonAddress then

        SharedOverlayPool.DiagnosticSlotButtonDestructByWidgetAddress[
            widgetAddress
        ] = nil

        return false
    end

    if currentSlotButtonAddress
        and currentSlotButtonAddress
            == record.SlotButtonAddress then

        SharedOverlayPool.DiagnosticSlotUpdateAfterButtonDestructCount =
            (SharedOverlayPool.DiagnosticSlotUpdateAfterButtonDestructCount or 0) + 1

        Log(
            "[PoolButtonLifeDiag] SlotUpdate AFTER SlotButton Destruct / count =",
            SharedOverlayPool.DiagnosticSlotUpdateAfterButtonDestructCount,
            "/ destructSeq =",
            record.Sequence or 0,
            "/ widgetAddress =",
            widgetAddress,
            "/ slotButtonAddress =",
            currentSlotButtonAddress
        )

        return true
    end

    return false

end

function SharedOverlayPool.LogSlotButtonDestructCleanupBoundary(reason)

    if not DEBUG then
        return
    end

    local total =
        SharedOverlayPool.DiagnosticSlotButtonDestructCount or 0

    local previous =
        SharedOverlayPool.DiagnosticSlotButtonDestructCountAtLastCleanup or 0

    local delta = total - previous

    SharedOverlayPool.DiagnosticSlotButtonDestructCountAtLastCleanup =
        total

    Log(
        "[PoolButtonLifeDiag] Cleanup boundary / reason =",
        reason or "cleanup",
        "/ destructSincePreviousCleanup =",
        delta,
        "/ destructTotal =",
        total,
        "/ slotUpdateAfterDestructTotal =",
        SharedOverlayPool.DiagnosticSlotUpdateAfterButtonDestructCount or 0
    )

end

-- Record the owning ScrollList before SlotButton:Setup(targetSlot) fires.
--
-- WBP_PalCharacterScrollList::CreateSlotWidget executes in this order:
--   Create SlotButton
--   BindButtonEvents(SlotButton)
--   SlotButton:Setup(targetSlot)  -> SlotUpdate
--
-- Blueprint RegisterHook callbacks run after the hooked Blueprint function,
-- so BindButtonEvents is the earliest narrow hook point that still executes
-- before Setup()/SlotUpdate. This prevents auxiliary lists such as
-- WBP_BaseCampPalList from temporarily claiming a Shared Pool Entry.
function SharedOverlayPool.PreclassifySlotButton(
    scrollList,
    slotButton
)

    if not SharedOverlayPool.IsValidObject(scrollList)
        or not SharedOverlayPool.IsValidObject(slotButton) then
        return false
    end

    local characterSlotWidget = nil

    local okWidget, resultWidget =
        pcall(function()
            return slotButton.MyCharacterSlotWidget
        end)

    if okWidget then
        characterSlotWidget = resultWidget
    end

    if not SharedOverlayPool.IsValidObject(
        characterSlotWidget
    ) then
        return false
    end

    local widgetAddress =
        SharedOverlayPool.GetAddress(
            characterSlotWidget
        )

    local scrollListAddress =
        SharedOverlayPool.GetAddress(
            scrollList
        )

    if not widgetAddress
        or not scrollListAddress then
        return false
    end

    local slotButtonAddress =
        SharedOverlayPool.GetAddress(
            slotButton
        )

    -- Debug state only: this pre-Setup Button is authoritative and
    -- supersedes any Destruct record left by an older recycled address.
    SharedOverlayPool.DiagnosticSlotButtonDestructByWidgetAddress[
        widgetAddress
    ] = nil

    -- A fresh authoritative SlotButton identity supersedes any retiring
    -- record left by an older UObject that previously occupied this address.
    SharedOverlayPool.WidgetSlotButtonAddressByWidgetAddress[
        widgetAddress
    ] = slotButtonAddress

    local usePersistentPool =
        SharedOverlayPool.IsPagedBoxScrollList(
            scrollList
        )

    SharedOverlayPool.RegisterLiveScrollSlot(
        scrollList,
        slotButton,
        characterSlotWidget,
        usePersistentPool
    )

    -- This is an authoritative live-Slot point and runs before
    -- SlotButton:Setup() -> SlotUpdate. If the UObject address was reused from
    -- a retiring Slot, reactivate it before SlotUpdate can fire.
    SharedOverlayPool.WidgetRetiringReasonByAddress[
        widgetAddress
    ] = nil

    SharedOverlayPool.WidgetPoolModeByAddress[
        widgetAddress
    ] = usePersistentPool

    SharedOverlayPool.WidgetScrollListAddressByWidgetAddress[
        widgetAddress
    ] = scrollListAddress

    return true

end


function SharedOverlayPool.BindEntryToScrollList(
    scrollList,
    slotButton
)

    if not SharedOverlayPool.IsValidObject(scrollList)
        or not SharedOverlayPool.IsValidObject(slotButton) then
        return
    end

    local characterSlotWidget = nil

    local okWidget, resultWidget =
        pcall(function()
            return slotButton.MyCharacterSlotWidget
        end)

    if okWidget then
        characterSlotWidget = resultWidget
    end

    if not SharedOverlayPool.IsValidObject(
        characterSlotWidget
    ) then
        return
    end

    local widgetAddress =
        SharedOverlayPool.GetAddress(
            characterSlotWidget
        )

    local scrollListAddress =
        SharedOverlayPool.GetAddress(
            scrollList
        )

    if not widgetAddress
        or not scrollListAddress then
        return
    end

    SharedOverlayPool.WidgetSlotButtonAddressByWidgetAddress[
        widgetAddress
    ] =
        SharedOverlayPool.GetAddress(
            slotButton
        )

    local usePersistentPool =
        SharedOverlayPool.IsPagedBoxScrollList(
            scrollList
        )

    SharedOverlayPool.RegisterLiveScrollSlot(
        scrollList,
        slotButton,
        characterSlotWidget,
        usePersistentPool
    )

    local hadPooledEntryBeforeClassification =
        SharedOverlayPool.EntryByWidgetAddress[
            widgetAddress
        ] ~= nil

    SharedOverlayPool.LogScrollListClassification(
        scrollList,
        characterSlotWidget,
        scrollListAddress,
        usePersistentPool,
        hadPooledEntryBeforeClassification
    )

    -- This post-Hook is the authoritative owner classification point.
    -- SlotUpdate runs earlier while the SlotButton is still being set up.
    SharedOverlayPool.WidgetRetiringReasonByAddress[
        widgetAddress
    ] = nil

    SharedOverlayPool.WidgetPoolModeByAddress[
        widgetAddress
    ] = usePersistentPool

    SharedOverlayPool.WidgetScrollListAddressByWidgetAddress[
        widgetAddress
    ] = scrollListAddress

    local entry =
        SharedOverlayPool.GetEntryForWidget(
            characterSlotWidget,
            widgetAddress
        )

    if not entry and usePersistentPool then

        -- If the first SlotUpdate arrived before owner publication,
        -- Pool acquisition is deferred. This post-AddSlot boundary is
        -- authoritative: the ScrollList owner is now registered
        -- and WBP_PalCharacterSlotBase::Setup has already stored targetSlot.
        -- Replay the missed initial Overlay update exactly once instead of
        -- leaving this Slot blank until the next page transition.
        local targetSlot = nil

        pcall(function()
            targetSlot = characterSlotWidget.targetSlot
        end)

        if SharedOverlayPool.IsValidObject(targetSlot) then

            local okEmpty, isEmpty =
                pcall(function()
                    return targetSlot:IsEmpty()
                end)

            if okEmpty and not isEmpty then

                local resourceReady = true

                if PalIconRuntime.EnsureResourceReady then
                    resourceReady =
                        PalIconRuntime.EnsureResourceReady()
                end

                if resourceReady then

                    local save = nil

                    pcall(function()
                        local handle = targetSlot:GetHandle()
                        if not handle then
                            return
                        end

                        local parameter =
                            handle:TryGetIndividualParameter()

                        if parameter then
                            save = parameter.SaveParameter
                        end
                    end)

                    if save and UpdateSlotOverlay then

                        UpdateSlotOverlay(
                            characterSlotWidget,
                            save,
                            "Normal",
                            true,
                            true,
                            nil,
                            widgetAddress
                        )

                        entry =
                            SharedOverlayPool.GetEntryForWidget(
                                characterSlotWidget,
                                widgetAddress
                            )

                        if entry then
                            DebugLog(
                                "[OverlayPoolReplay] Recovered missed initial Slot overlay / widgetAddress =",
                                widgetAddress
                            )
                        else
                            Log(
                                "[OverlayPoolReplay] Replay did not acquire Entry / widgetAddress =",
                                widgetAddress
                            )
                        end

                    else
                        Log(
                            "[OverlayPoolReplay] Replay SaveParameter unavailable / widgetAddress =",
                            widgetAddress
                        )
                    end

                end

            end

        end

    end

    if not entry then
        return
    end

    if not usePersistentPool then

        -- Auxiliary lists such as BaseCampPalList and
        -- DisplayCharacterScrollList do not share the paged BoxPalListBase
        -- lifecycle. Convert them immediately after their AddSlot call rather
        -- than retaining a persistent Entry until a later menu instance.
        local save = entry.LastSave

        SharedOverlayPool.ParkEntry(
            entry,
            "Non-paged PalCharacterScrollList"
        )

        if save and UpdateSlotOverlay then

            UpdateSlotOverlay(
                characterSlotWidget,
                save,
                "Normal",
                true,
                false
            )

        end

        DebugLog(
            "[OverlayPool] Auxiliary ScrollList converted to direct Overlay."
        )

        return
    end

    entry.OwnerScrollListAddress =
        scrollListAddress

    entry.OwnerPresetRowAddress = nil
    entry.OwnerCommonSlotButtonAddress = nil

    entry.DiagnosticOwnerFullName =
        SharedOverlayPool.GetDiagnosticFullName(scrollList)

    entry.DiagnosticWidgetFullName =
        SharedOverlayPool.GetDiagnosticFullName(characterSlotWidget)

    SharedOverlayPool.DiagnosticSequence =
        (SharedOverlayPool.DiagnosticSequence or 0) + 1

    entry.DiagnosticBindSequence =
        SharedOverlayPool.DiagnosticSequence

    entry.DiagnosticState = "AttachedScrollList"
    entry.DiagnosticLastTransition = "BindEntryToScrollList"
    entry.DiagnosticLastParentFullName =
        entry.DiagnosticOwnerFullName

    entry.LastSave = nil

    DebugLog(
        "[OverlayPool] Entry",
        entry.Index,
        "owner BoxPalScrollList mapped."
    )

end

function SharedOverlayPool.Destroy()

    if not SHARED_OVERLAY_POOL_ENABLED then
        return
    end

    for _, entry
        in ipairs(SharedOverlayPool.Entries) do

        if SharedOverlayPool.IsValidObject(entry.Root) then

            SetWidgetVisible(
                entry.Root,
                false
            )

            pcall(function()
                entry.Root:RemoveFromParent()
            end)

        end

    end

    local parkingRoot =
        SharedOverlayPool.ParkingRoot

    if SharedOverlayPool.IsValidObject(parkingRoot) then

        SetWidgetVisible(
            parkingRoot,
            false
        )

        pcall(function()
            parkingRoot:RemoveFromParent()
        end)

    end

    SharedOverlayPool.Reset()

end

function SharedOverlayPool.Initialize()

    if not SHARED_OVERLAY_POOL_ENABLED
        or SharedOverlayPool.Ready
        or SharedOverlayPool.PrewarmRequested then
        return
    end

    SharedOverlayPool.PrewarmRequested =
        true

    -- Do not hook WBP_PalOverallUILayout:OnInitialized.
    -- Some Palworld builds do not expose that Blueprint UFunction to
    -- RegisterHook even after a package-path LoadAsset attempt. The Pool only
    -- requires the persistent OverallUILayout instance before PalBox opens, so
    -- retry a cheap instance lookup until it exists.
    local function TryPrewarm()

        if not IsCurrentRuntimeGeneration()
            or SharedOverlayPool.Ready then
            return
        end

        ExecuteInGameThread(
            function()

                if not IsCurrentRuntimeGeneration() then
                    return
                end

                ------------------------------------------------
                -- Pre-PalBox resource preload
                ------------------------------------------------
                -- Texture loading does not depend on the OverallLayout or on
                -- successful persistent Pool construction. Start it as soon as
                -- this first known game-thread callback is reached so a delayed or
                -- missing OverallLayout does not also delay resource preload.
                if PalIconRuntime.StartPrePalBoxResourcePreload then
                    PalIconRuntime.StartPrePalBoxResourcePreload()
                end

                if SharedOverlayPool.Ready then
                    return
                end

                if SharedOverlayPool.EnsureReadyNow() then
                    return
                end

                ExecuteWithDelay(
                    500,
                    TryPrewarm
                )

            end
        )

    end

    TryPrewarm()

end


------------------------------------------------
-- Party Overlay Persistent Pool
------------------------------------------------
--
-- Party rows use WBP_IngameMenu_PalBox_PalList_C and have a layout that
-- differs from Normal PalBox slots, so they use their own persistent Pool.
--
-- Vanilla creates five Party rows. The Pool starts with five complete Entries
-- before PalBox opens and grows only when compatibility MODs create additional
-- Party rows. Every Entry always contains all 34 Overlay Widgets.
--
-- WBP_IngameMenu_PalBox_PalList_C itself does not implement a Blueprint
-- Destruct event. The containing WBP_PalStorageMenu_C does, so that screen's
-- Destruct Hook is the deterministic reclaim point for all Party Entries.
------------------------------------------------

PartyOverlayPool = {
    OverallLayout = nil,
    ParkingRoot = nil,
    Entries = {},
    EntryByWidgetAddress = {},
    Ready = false,
    PrewarmRequested = false,
    TexturesInitialized = false,
    Enabled = true,
    TargetCount = 5,
}

function PartyOverlayPool.Reset()

    PartyOverlayPool.OverallLayout = nil
    PartyOverlayPool.ParkingRoot = nil
    PartyOverlayPool.Entries = {}
    PartyOverlayPool.EntryByWidgetAddress = {}
    PartyOverlayPool.Ready = false
    PartyOverlayPool.TexturesInitialized = false

end

function PartyOverlayPool.GetEntryForWidget(widget)

    if not PartyOverlayPool.Enabled
        or not PartyOverlayPool.Ready then
        return nil
    end

    local address =
        SharedOverlayPool.GetAddress(widget)

    if not address then
        return nil
    end

    local entry =
        PartyOverlayPool.EntryByWidgetAddress[
            address
        ]

    if not entry then
        return nil
    end

    -- Child completeness is guaranteed at Entry creation. Only the persistent
    -- Root lifetime needs validation on the hot lookup path.
    if not SharedOverlayPool.IsValidObject(entry.Root) then

        PartyOverlayPool.EntryByWidgetAddress[
            address
        ] = nil

        return nil
    end

    return entry

end

function PartyOverlayPool.CreateEntry(
    parkingRoot,
    index
)

    local okConstruct, root =
        pcall(
            StaticConstructObject,
            Res.canvasClass,
            parkingRoot
        )

    if not okConstruct or not root then
        return nil
    end

    local rootSlot =
        parkingRoot:AddChild(root)

    if not rootSlot then
        return nil
    end

    SharedOverlayPool.SetupParkingSlot(rootSlot)
    SetWidgetVisible(root, false)

    local overlay =
        CreateOverlayWidgets(root)

    if not SharedOverlayPool.IsCompleteOverlay(overlay) then

        pcall(function()
            root:RemoveFromParent()
        end)

        return nil
    end

    local okStaticLayout, staticLayoutReady =
        pcall(
            SharedOverlayPool.ApplyStaticLayoutToOverlay,
            overlay,
            "Party"
        )

    if not okStaticLayout
        or staticLayoutReady ~= true then

        pcall(function()
            root:RemoveFromParent()
        end)

        return nil
    end

    if ResourceReady then

        local okStaticTexture, staticTextureReady =
            pcall(
                SharedOverlayPool.ApplyStaticTexturesToOverlay,
                overlay
            )

        if not okStaticTexture
            or staticTextureReady ~= true then

            pcall(function()
                root:RemoveFromParent()
            end)

            return nil
        end

    end

    return {
        Index = index,
        Root = root,
        Overlay = overlay,
        BoundWidgetAddress = nil,
        LastSave = nil,
        DynamicCache = nil,
        RootVisible = false,
    }

end

function PartyOverlayPool.AppendEntry(reason)

    if not PartyOverlayPool.Ready
        or not SharedOverlayPool.IsValidObject(
            PartyOverlayPool.ParkingRoot
        ) then
        return nil
    end

    local index =
        #PartyOverlayPool.Entries + 1

    local entry =
        PartyOverlayPool.CreateEntry(
            PartyOverlayPool.ParkingRoot,
            index
        )

    if not entry then
        return nil
    end

    PartyOverlayPool.Entries[
        #PartyOverlayPool.Entries + 1
    ] = entry

    if reason == "growth" then
        DebugLog(
            "[PartyOverlayPool] Pool size:",
            #PartyOverlayPool.Entries,
            "Entries"
        )
    end

    return entry

end

function PartyOverlayPool.Prewarm(overallLayout)

    if not PartyOverlayPool.Enabled
        or Config.DisplayOption.EnablePartyDisplay ~= true then
        return false
    end

    if PartyOverlayPool.Ready
        and SharedOverlayPool.IsValidObject(
            PartyOverlayPool.ParkingRoot
        ) then
        return true
    end

    PartyOverlayPool.Reset()

    if not SharedOverlayPool.IsValidObject(overallLayout)
        or not SharedOverlayPool.EnsureWidgetClasses() then
        return false
    end

    local rootPanel = nil

    local okRoot, resultRoot =
        pcall(function()
            return overallLayout.CanvasPanel_Root
        end)

    if okRoot then
        rootPanel = resultRoot
    end

    if not SharedOverlayPool.IsValidObject(rootPanel) then
        return false
    end

    local okConstruct, parkingRoot =
        pcall(
            StaticConstructObject,
            Res.canvasClass,
            rootPanel
        )

    if not okConstruct or not parkingRoot then
        return false
    end

    local parkingSlot =
        rootPanel:AddChild(parkingRoot)

    if not parkingSlot then
        return false
    end

    SharedOverlayPool.SetupParkingSlot(parkingSlot)
    SetWidgetVisible(parkingRoot, false)

    PartyOverlayPool.OverallLayout = overallLayout
    PartyOverlayPool.ParkingRoot = parkingRoot
    PartyOverlayPool.Ready = true

    for _ = 1, PartyOverlayPool.TargetCount do

        if not PartyOverlayPool.AppendEntry("prewarm") then
            break
        end

    end

    local preloadState =
        PalIconRuntime.PrePalBoxResourcePreload

    if preloadState
        and preloadState.Anchored == true then
        PartyOverlayPool.InitializeStaticTexturesAllEntries()
    end

    DebugLog(
        "[PartyOverlayPool] Prewarm complete:",
        #PartyOverlayPool.Entries,
        "Entries /",
        ADDED_CHILD_COUNT,
        "Widgets per Entry"
    )

    return #PartyOverlayPool.Entries > 0

end

function PartyOverlayPool.EnsureReadyNow()

    if not PartyOverlayPool.Enabled
        or Config.DisplayOption.EnablePartyDisplay ~= true then
        return false
    end

    if PartyOverlayPool.Ready
        and SharedOverlayPool.IsValidObject(
            PartyOverlayPool.ParkingRoot
        ) then
        return true
    end

    if PartyOverlayPool.Ready then
        PartyOverlayPool.Reset()
    end

    -- Reuse the OverallLayout already resolved by the Normal Pool whenever
    -- possible. All three pools share the same persistent host, so repeating
    -- FindFirstOf() for Party/Preset is unnecessary after Normal prewarm.
    local overallLayout =
        SharedOverlayPool.OverallLayout

    if not SharedOverlayPool.IsValidObject(
        overallLayout
    ) then

        overallLayout = nil

        local okFind, resultFind =
            pcall(function()
                return FindFirstOf(
                    "WBP_PalOverallUILayout_C"
                )
            end)

        if okFind then
            overallLayout = resultFind
        end

    end

    if not SharedOverlayPool.IsValidObject(
        overallLayout
    ) then
        return false
    end

    return PartyOverlayPool.Prewarm(
        overallLayout
    )

end

function PartyOverlayPool.Initialize()

    if not PartyOverlayPool.Enabled
        or Config.DisplayOption.EnablePartyDisplay ~= true
        or PartyOverlayPool.Ready
        or PartyOverlayPool.PrewarmRequested then
        return
    end

    PartyOverlayPool.PrewarmRequested = true

    local function TryPrewarm()

        if not IsCurrentRuntimeGeneration()
            or PartyOverlayPool.Ready then
            return
        end

        ExecuteInGameThread(
            function()

                if not IsCurrentRuntimeGeneration()
                    or PartyOverlayPool.Ready then
                    return
                end

                if PartyOverlayPool.EnsureReadyNow() then
                    return
                end

                ExecuteWithDelay(
                    500,
                    TryPrewarm
                )

            end
        )

    end

    TryPrewarm()

end

function PartyOverlayPool.AttachEntry(
    entry,
    widget,
    canvas
)

    if not entry
        or not widget
        or not canvas
        or entry.BoundWidgetAddress ~= nil
        or not SharedOverlayPool.IsValidObject(entry.Root) then
        return false
    end

    local widgetAddress =
        SharedOverlayPool.GetAddress(widget)

    if not widgetAddress then
        return false
    end

    if not entry.DynamicCache then
        entry.DynamicCache =
            CreatePoolDynamicCache()
    end

    pcall(function()
        entry.Root:RemoveFromParent()
    end)

    local rootSlot =
        canvas:AddChild(entry.Root)

    if not rootSlot
        or not SharedOverlayPool.SetupRootSlot(rootSlot) then
        return false
    end

    entry.BoundWidgetAddress = widgetAddress


    PartyOverlayPool.EntryByWidgetAddress[
        widgetAddress
    ] = entry

    if entry.RootVisible then
        SetWidgetVisible(entry.Root, false)
        entry.RootVisible = false
    end

    return true

end

function PartyOverlayPool.AcquireEntry(
    widget,
    canvas
)

    local existing =
        PartyOverlayPool.GetEntryForWidget(
            widget
        )

    if existing then
        return existing
    end

    if not PartyOverlayPool.EnsureReadyNow() then
        return nil
    end

    for _, entry
        in ipairs(PartyOverlayPool.Entries) do

        if entry.BoundWidgetAddress == nil then

            if PartyOverlayPool.AttachEntry(
                entry,
                widget,
                canvas
            ) then
                return entry
            end

        end

    end

    local entry =
        PartyOverlayPool.AppendEntry(
            "growth"
        )

    if not entry then
        return nil
    end

    if PartyOverlayPool.AttachEntry(
        entry,
        widget,
        canvas
    ) then
        return entry
    end

    return nil

end

function PartyOverlayPool.ParkEntry(entry)

    if not entry then
        return false
    end

    local widgetAddress =
        entry.BoundWidgetAddress

    if widgetAddress then
        PartyOverlayPool.EntryByWidgetAddress[
            widgetAddress
        ] = nil
    end

    if not SharedOverlayPool.IsValidObject(entry.Root) then

        entry.BoundWidgetAddress = nil
        entry.LastSave = nil
        entry.RootVisible = false

        return false
    end

    SetWidgetVisible(entry.Root, false)
    entry.RootVisible = false

    pcall(function()
        entry.Root:RemoveFromParent()
    end)

    local parkingRoot =
        PartyOverlayPool.ParkingRoot

    if not SharedOverlayPool.IsValidObject(parkingRoot) then
        return false
    end

    local parkingSlot =
        parkingRoot:AddChild(entry.Root)

    if not parkingSlot then
        return false
    end

    SharedOverlayPool.SetupParkingSlot(parkingSlot)

    entry.BoundWidgetAddress = nil
    entry.LastSave = nil

    return true

end

function PartyOverlayPool.ParkAll(reason)

    if not PartyOverlayPool.Ready then
        return 0
    end

    local parked = 0

    for _, entry
        in ipairs(PartyOverlayPool.Entries) do

        if entry.BoundWidgetAddress ~= nil
            and PartyOverlayPool.ParkEntry(entry) then
            parked = parked + 1
        end

    end

    if parked > 0 then

        DebugLog(
            "[PartyOverlayPool] Parked",
            parked,
            "Entries:",
            reason or "unspecified",
            "/ Pool size =",
            #PartyOverlayPool.Entries
        )

    end

    return parked

end

function PartyOverlayPool.RefreshStaticLayoutAllEntries(reason)

    if not PartyOverlayPool.Ready then
        return 0
    end

    local updated = 0

    for _, entry
        in ipairs(PartyOverlayPool.Entries) do

        local ok, result =
            pcall(
                SharedOverlayPool.ApplyStaticLayoutToOverlay,
                entry.Overlay,
                "Party"
            )

        if ok and result == true then

            if entry.DynamicCache then
                entry.DynamicCache =
                    CreatePoolDynamicCache()
            end

            updated = updated + 1

        end

    end

    DebugLog(
        "[PartyOverlayPool] Static layout refreshed:",
        updated,
        "/ reason =",
        reason or "unspecified"
    )

    return updated

end

function PartyOverlayPool.InitializeStaticTexturesAllEntries()

    if not PartyOverlayPool.Ready
        or PartyOverlayPool.TexturesInitialized then
        return 0
    end

    local updated = 0

    for _, entry
        in ipairs(PartyOverlayPool.Entries) do

        local ok, result =
            pcall(
                SharedOverlayPool.ApplyStaticTexturesToOverlay,
                entry.Overlay
            )

        if ok and result == true then
            updated = updated + 1
        end

    end

    PartyOverlayPool.TexturesInitialized = true

    DebugLog(
        "[PartyOverlayPool] Static textures initialized:",
        updated,
        "Entries"
    )

    return updated

end

function PartyOverlayPool.Destroy()

    if not PartyOverlayPool.Enabled then
        return
    end

    for _, entry
        in ipairs(PartyOverlayPool.Entries) do

        if SharedOverlayPool.IsValidObject(entry.Root) then

            SetWidgetVisible(entry.Root, false)

            pcall(function()
                entry.Root:RemoveFromParent()
            end)

        end

    end

    local parkingRoot =
        PartyOverlayPool.ParkingRoot

    if SharedOverlayPool.IsValidObject(parkingRoot) then

        SetWidgetVisible(parkingRoot, false)

        pcall(function()
            parkingRoot:RemoveFromParent()
        end)

    end

    PartyOverlayPool.Reset()

end

------------------------------------------------
-- Shared Preset Overlay Pool Adapter
------------------------------------------------
--
-- Preset slots use the same Normal-layout Overlay as ordinary PalBox slots,
-- so they share SharedOverlayPool instead of retaining a second 50-Entry
-- Widget Pool. No Preset Pal-data cache is kept here. SetupPreset still resolves
-- each registered Pal's current SaveParameter exactly as before.
--
-- Ownership is kept separate inside each shared Entry:
--   OwnerScrollListAddress  = normal paged PalBox ownership
--   OwnerPresetRowAddress  = Preset-row ownership
--
-- This lets BoxPalList lifecycle events reclaim only normal Entries while the
-- Preset screen Destruct event reclaims only Preset-owned Entries.
------------------------------------------------

PresetOverlayBinding = {
    Enabled = true,
    SlotsPerPreset = 5,
}

function PresetOverlayBinding.BindPresetRowSlots(
    rowWidget,
    characterSlots
)

    if not rowWidget
        or not characterSlots then
        return nil, 0, 0
    end

    -- Preset rows can be created during a UI transition. Validate the Pool
    -- against the OverallLayout that owns this exact row instead of relying only
    -- on ParkingRoot:IsValid(), which cannot distinguish an old still-valid HUD.
    local hostReady =
        SharedOverlayPool.EnsureHostForWidget(
            rowWidget
        )

    if not hostReady then
        hostReady =
            SharedOverlayPool.EnsureReadyNow()
    end

    if not hostReady then
        return nil, 0, 0
    end

    local rowAddress =
        SharedOverlayPool.GetAddress(rowWidget)

    if not rowAddress then
        return nil, 0, 0
    end

    local slotCount = nil
    local okCount =
        pcall(function()
            slotCount = #characterSlots
        end)

    if not okCount
        or type(slotCount) ~= "number" then
        return nil, 0, 0
    end

    -- Resolve each WBP_PalCommonCharacterSlot only once. SetupPreset reuses
    -- this indexed list for the subsequent data update instead of reading the
    -- same CharacterSlots array and nested Widget property a second time.
    local slotWidgets = {}
    local currentAddresses = {}
    local bound = 0

    for i = 1, slotCount do

        local slotWidget = nil
        local slotButton = nil

        local okSlot =
            pcall(function()

                slotButton =
                    characterSlots[i]

                if slotButton then
                    slotWidget =
                        slotButton.WBP_PalCommonCharacterSlot
                end

            end)

        if okSlot and slotWidget then

            slotWidgets[i] = slotWidget

            local widgetAddress =
                SharedOverlayPool.GetAddress(
                    slotWidget
                )

            if widgetAddress then

                currentAddresses[widgetAddress] = true

                SharedOverlayPool.WidgetSlotButtonAddressByWidgetAddress[
                    widgetAddress
                ] =
                    SharedOverlayPool.GetAddress(
                        slotButton
                    )

                -- SetupPreset is the authoritative live-Preset binding point.
                -- Clear a stale retiring marker only for this exact current
                -- Slot before acquiring/binding its shared Entry.
                SharedOverlayPool.WidgetRetiringReasonByAddress[
                    widgetAddress
                ] = nil

                local entry =
                    SharedOverlayPool.GetEntryForWidget(
                        slotWidget,
                        widgetAddress
                    )

                if not entry then

                    local canvas =
                        GetPalSlotCanvas(
                            slotWidget,
                            "Normal"
                        )

                    if canvas then

                        entry =
                            SharedOverlayPool.AcquireEntry(
                                slotWidget,
                                canvas,
                                widgetAddress,
                                {
                                    Kind = "Preset",
                                    RowAddress = rowAddress,
                                }
                            )

                    end

                end

                if entry then

                    entry.OwnerScrollListAddress = nil
                    entry.OwnerPresetRowAddress = rowAddress
                    entry.OwnerCommonSlotButtonAddress = nil
                    entry.DiagnosticState = "AttachedPreset"
                    entry.DiagnosticLastTransition = "BindPresetRowSlots"
                    entry.DiagnosticOwnerFullName =
                        SharedOverlayPool.GetDiagnosticFullName(rowWidget)
                    entry.DiagnosticWidgetFullName =
                        SharedOverlayPool.GetDiagnosticFullName(slotWidget)
                    entry.DiagnosticLastParentFullName =
                        entry.DiagnosticOwnerFullName
                    entry.LastSave = nil

                    -- Do not hide every reused Preset Entry here. Valid Slots
                    -- are updated immediately by SetupPreset, while empty or
                    -- invalid Slots are explicitly cleared there. This avoids
                    -- a redundant hide -> show visibility pair for every valid
                    -- Preset Pal whenever the list is rebuilt.
                    bound = bound + 1

                end

            end

        end

    end

    -- A Preset row can be rebuilt with different Slot Widget instances.
    -- Reclaim only stale Entries owned by this row; normal PalBox Entries and
    -- other Preset rows remain untouched.
    for _, entry
        in ipairs(SharedOverlayPool.Entries) do

        if entry.OwnerPresetRowAddress == rowAddress
            and entry.BoundWidgetAddress ~= nil
            and currentAddresses[
                entry.BoundWidgetAddress
            ] ~= true then

            SharedOverlayPool.ParkEntry(
                entry,
                "Preset row rebuild"
            )

        end

    end

    return slotWidgets, slotCount, bound

end

function PresetOverlayBinding.ParkAll(reason, retireSequence)

    if not SharedOverlayPool.Ready then
        return 0
    end

    local parked = 0

    for _, entry
        in ipairs(SharedOverlayPool.Entries) do

        if entry.OwnerPresetRowAddress ~= nil
            and entry.BoundWidgetAddress ~= nil then

            local widgetAddress =
                entry.BoundWidgetAddress

            -- Preset slots already have an exact Common SlotButton
            -- identity from SlotButtonBase::SetupBySaveParameter. Mark that
            -- bounded live record retiring instead of retaining a dead
            -- CharacterSlot address tombstone. If coverage is unexpectedly
            -- missing, keep the old marker for that Slot only and count it.
            local commonRetiringMarked =
                SharedOverlayPool.MarkLiveCommonSlotRetiring(
                    widgetAddress,
                    reason or "Preset Destruct",
                    retireSequence
                )

            if not commonRetiringMarked then

                SharedOverlayPool.DiagnosticCommonRetiringFallbackMarker =
                    (SharedOverlayPool.DiagnosticCommonRetiringFallbackMarker or 0) + 1

                SharedOverlayPool.WidgetRetiringReasonByAddress[
                    widgetAddress
                ] = {
                    Reason = reason or "Preset Destruct",
                    CleanupSequence = retireSequence,
                    SlotButtonAddress =
                        SharedOverlayPool.WidgetSlotButtonAddressByWidgetAddress[
                            widgetAddress
                        ],
                }

            end

            if SharedOverlayPool.ParkEntry(
                entry,
                reason or "Preset Destruct"
            ) then

                parked = parked + 1

            end

        end

    end

    if parked > 0 then

        DebugLog(
            "[OverlayPool] Parked",
            parked,
            "Preset Entries:",
            reason or "unspecified",
            "/ Pool size =",
            #SharedOverlayPool.Entries
        )

    end

    return parked

end

------------------------------------------------
-- Data Functions
------------------------------------------------
-- Retrieve and calculate the game data required for Overlay display from SaveParameter.
--
-- This section does not directly manipulate UI Widgets.
-- It is responsible only for retrieving and calculating
-- "what should be displayed".
--
-- The retrieved values are applied to Widgets later in Overlay UI Data Update.
--
-- When adding a new display item, first add the required game-data
-- retrieval/calculation here, and then call it from the corresponding Update function.
-- Processing that references Palworld's standard DataTables should also be
-- consolidated in this section whenever possible.
-- This keeps game-data retrieval separate from Widget manipulation.

-- Retrieves the Palpedia number and suffix from the prebuilt PalpediaCache.
-- CharacterID is normalized to the same key format used when the cache is built,
-- allowing this frequently called function to use a direct Lua table lookup.
------------------------------------------------
-- Data Cache Construction
------------------------------------------------

-- Builds a Lua hash table containing the Palpedia number and suffix for each
-- Pal species. The required values are extracted once after the required
-- resources are ready, so Pal icon updates can use direct Lua table lookups
-- instead of querying the PalMonsterParameter DataTable each time.
local function BuildPalpediaCache()

    PalpediaCache = {}

    local rowNames =
        Res.palMonsterParameter:GetRowNames()

    if not rowNames then
        return
    end

    for _, rowName in ipairs(rowNames) do

        local palRow =
            Res.palMonsterParameter:FindRow(
                rowName,
                "PalMonsterParameter"
            )

        if palRow then

            local zukanIndex =
                palRow.ZukanIndex

            if zukanIndex and zukanIndex ~= -1 then

                local numberString =
                    string.format(
                        "%03d",
                        tonumber(zukanIndex)
                    )

                local suffixString = ""

                local suffix =
                    palRow.ZukanIndexSuffix

                if suffix then

                    suffixString =
                        suffix:ToString()

                    if suffixString == "None" then
                        suffixString = ""
                    end

                end

                PalpediaCache[rowName] = {
                    Number = numberString,
                    Suffix = suffixString,
                    Padding = numberString:match("^0*"),
                }

            end

        end

    end

end

------------------------------------------------
-- Passive Skill Cache
------------------------------------------------

-- Builds a Lua hash table containing each passive skill's display name and
-- rank. The passive-skill and skill-name DataTables are resolved once during
-- initialization so subsequent Pal icon updates can retrieve this information
-- directly from the cache.
local function BuildPassiveSkillCache()

    PassiveSkillCache = {}

    local rowNames =
        Res.passiveSkillTable:GetRowNames()

    if not rowNames then
        return
    end

    for _, rowName in ipairs(rowNames) do

        local passiveRow =
            Res.passiveSkillTable:FindRow(
                rowName,
                "Passive"
            )

        if passiveRow then

            local skillID =
                rowName

            local skillRank =
                passiveRow.Rank

            ------------------------------------------------
            -- Passive Skill Name
            ------------------------------------------------
            --
            -- Vanilla Passive Skills normally use a SkillName DataTable Row
            -- named "PASSIVE_" .. SkillID and leave OverrideNameTextID as None.
            --
            -- Custom Passive Skill MODs may instead set OverrideNameTextID
            -- without adding a corresponding Row to DT_SkillNameText.
            -- In that case, use OverrideNameTextID itself as the fallback
            -- display name so the Passive Skill is still cached and can be
            -- displayed by both the Bar and Name Overlay.

            local overrideNameTextIDString = nil

            local overrideNameTextID =
                passiveRow.OverrideNameTextID

            if overrideNameTextID then

                if type(overrideNameTextID) == "string" then
                    overrideNameTextIDString = overrideNameTextID
                else
                    overrideNameTextIDString =
                        overrideNameTextID:ToString()
                end

                if overrideNameTextIDString == "None"
                    or overrideNameTextIDString == ""
                then
                    overrideNameTextIDString = nil
                end

            end

            local defaultNameTextID =
                "PASSIVE_" .. skillID

            local nameTextID =
                overrideNameTextIDString
                or defaultNameTextID

            local nameRow =
                Res.skillNameTable:FindRow(
                    nameTextID,
                    "SkillName"
                )

            -- Some custom Passive Skills may provide OverrideNameTextID
            -- while still using the standard PASSIVE_<SkillID> Text Row.
            -- Try the vanilla convention as a secondary lookup before
            -- falling back to a raw display string.
            if not nameRow
                and nameTextID ~= defaultNameTextID
            then

                nameRow =
                    Res.skillNameTable:FindRow(
                        defaultNameTextID,
                        "SkillName"
                    )

            end

            local skillName = nil

            if nameRow then

                skillName =
                    nameRow.TextData:ToString()

            elseif overrideNameTextIDString then

                skillName =
                    overrideNameTextIDString

            else

                -- Keep the Passive Skill available even when no display-name
                -- Row exists. This prevents the Bar display from dropping
                -- otherwise valid custom Passive Skills.
                skillName =
                    skillID

            end

            PassiveSkillCache[skillID] = {
                SkillID   = skillID,
                SkillName = skillName,
                SkillRank = skillRank,
            }

        end

    end

end

------------------------------------------------
-- Friendship Rank Cache
------------------------------------------------

-- Builds a Lua table containing the friendship thresholds and ranks used by
-- CalculateFriendshipRank(). Friendship rank data is resolved once during
-- initialization so each Pal icon update does not need to traverse the
-- friendship DataTable.
local function BuildFriendshipRankCache()

    FriendshipRankCache = {}

    Res.friendshipRankTable:ForEachRow(
        function(rowName, row)

            if not row then
                return
            end

            local requiredPoint =
                row.RequiredPoint

            local friendshipRank =
                row.FriendshipRank

            if requiredPoint == nil
                or friendshipRank == nil
            then
                return
            end

            table.insert(
                FriendshipRankCache,
                {
                    RequiredPoint = requiredPoint,
                    FriendshipRank = friendshipRank,
                }
            )

        end
    )

end

local function GetPalpediaNumber(save)

    if not save then
        return "---", "", ""
    end

    local characterID =
        save.CharacterID

    if not characterID then
        return "---", "", ""
    end

    local characterIDString =
        characterID:ToString()

    if not characterIDString then
        return "---", "", ""
    end

    ------------------------------------------------
    -- Normalize CharacterID
    ------------------------------------------------

    characterIDString =
        characterIDString:gsub("^[Bb][Oo][Ss][Ss]_", "")

    characterIDString =
        characterIDString:gsub("^GYM_", "")

    characterIDString =
        characterIDString:gsub("_[Oo]tomo$", "")

    ------------------------------------------------
    -- Palpedia Cache
    ------------------------------------------------

    local data =
        PalpediaCache[characterIDString]

    if not data then
        return "---", "", ""
    end

    return data.Number, data.Suffix, data.Padding

end

-- Retrieves each passive skill from SaveParameter and resolves its display
-- information through the prebuilt PassiveSkillCache. The cache replaces the
-- repeated passive-skill and skill-name DataTable lookups used during updates.
local function GetPassiveSkillData(
    save,
    scratch
)

    local list =
        scratch or {}

    -- Persistent Pool Entries reuse one fixed scratch array so repeated Slot
    -- updates do not allocate a new result table. Direct-child Overlays still
    -- receive a temporary table, preserving their independent update path.
    for i = #list, 1, -1 do
        list[i] = nil
    end

    if not save then
        return list
    end

    local passiveSkillList =
        save.PassiveSkillList

    if not passiveSkillList then
        return list
    end

    passiveSkillList:ForEach(
        function(index, value)

            if not value then
                return
            end

            local fname =
                value:get()

            if not fname then
                return
            end

            local skillID =
                fname:ToString()

            local data =
                PassiveSkillCache[skillID]

            if not data then
                return
            end

            -- Cache entries already contain the immutable SkillID / display
            -- name / rank values. Reuse those tables instead of allocating one
            -- new Lua table per Passive Skill on every Slot update.
            list[#list + 1] = data

        end
    )

    return list

end

-- Fixed comparator reused by every pooled Slot update. Defining it once avoids
-- allocating a new closure for each table.sort() call.
local function ComparePassiveSkillRank(a, b)

    if a.SkillRank ~= b.SkillRank then

        if a.SkillRank == nil then
            return false
        end

        if b.SkillRank == nil then
            return true
        end

        return a.SkillRank > b.SkillRank

    end

    return a.SkillID < b.SkillID

end

-- Sum the four Soul Rank values stored in SaveParameter
-- and convert them into the single Soul Rank displayed by the Overlay.
--
-- This function does not manipulate Widgets;
-- it calculates only the numeric value required for display.
-- Actual icon and number updates are handled by UpdateSoul().
--
-- Palworld stores the following four individual values:
--
--     Rank_HP
--     Rank_Attack
--     Rank_Defence
--     Rank_CraftSpeed
--
-- This MOD displays their sum as the Soul Rank.
--
-- If SaveParameter does not exist or an individual value is nil,
-- it is treated as 0.
local function CalculateSoulRank(save)

    if not save then
        return 0
    end

    return
        (save.Rank_HP or 0)
        + (save.Rank_Attack or 0)
        + (save.Rank_Defence or 0)
        + (save.Rank_CraftSpeed or 0)

end

-- Calculates the friendship rank from FriendshipPoint using the prebuilt
-- FriendshipRankCache. The cache contains the DataTable values needed for the
-- calculation, avoiding a DataTable traversal for each Pal icon update.
local function CalculateFriendshipRank(save)

    if not save then
        return 0
    end

    local point =
        save.FriendshipPoint or 0

    local resultRank = 0

    for _, data in ipairs(FriendshipRankCache) do

        if point < data.RequiredPoint then
            break
        end

        resultRank =
            data.FriendshipRank

    end

    return resultRank

end

------------------------------------------------
-- Overlay UI Data Update
------------------------------------------------

-- Apply the values retrieved and calculated by Data Functions
-- to the corresponding Overlay Widgets.
--
-- Each display item is updated by a dedicated function,
-- keeping data retrieval/calculation separate from Widget manipulation.
--
-- targetType identifies the type of Overlay target being processed:
--
--   "Normal" - Normal PalBox / Preset slot
--   "Party"  - Party Pal slot
--   "Hatch"  - Incubator hatch-result entry
--
-- It is passed through the UI update chain so that target-specific
-- layout settings can be applied by SetupSlot().
--
-- SetupText() / SetupImage() receive targetType, optional index, and
-- skipStaticSetup. Persistent Pool updates pass skipStaticSetup=true because
-- their layout/font/color/texture have already been initialized.

-- Display the Palpedia number divided into "No.", "Number",
-- "Suffix", and leading zeros.
--
-- GetPalpediaNumber() returns the number and suffix separately,
-- allowing each component to be configured independently in Config.
--
-- The numeric portion is displayed as a three-digit string,
-- while the suffix is displayed separately.
-- For example, Palpedia number 12 with suffix B is displayed as "012" and "B".
local function UpdateNumber(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    local number, suffix, padding =
        GetPalpediaNumber(save)

    if not skipStaticSetup then

        SetupText(
            overlay.Number.Text_No,
            "No.",
            Config.UI.Number.Text_No,
            targetType,
            nil,
            false
        )

    end

    SetupText(
        overlay.Number.Text_NumberValue,
        tostring(number),
        Config.UI.Number.Text_NumberValue,
        targetType,
        nil,
        skipStaticSetup,
        dynamicCache
    )

    SetupText(
        overlay.Number.Text_SuffixValue,
        tostring(suffix),
        Config.UI.Number.Text_SuffixValue,
        targetType,
        nil,
        skipStaticSetup,
        dynamicCache
    )

    SetupText(
        overlay.Number.Text_0,
        padding,
        Config.UI.Number.Text_0,
        targetType,
        nil,
        skipStaticSetup,
        dynamicCache
    )

end

-- Display the Pal's Level from SaveParameter.Level.
--
-- "Lv." and the numeric value use separate Widgets,
-- allowing their positions, sizes, and colors to be configured
-- independently through Config.UI.Level.
--
-- No calculation or adjustment is performed here.
-- The value stored in SaveParameter is displayed directly.
local function UpdateLevel(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    local level =
        save.Level

    if not skipStaticSetup then

        SetupText(
            overlay.Level.Text_Lv,
            "Lv.",
            Config.UI.Level.Text_Lv,
            targetType,
            nil,
            false
        )

    end

    SetupText(
        overlay.Level.Text_LevelValue,
        tostring(level),
        Config.UI.Level.Text_LevelValue,
        targetType,
        nil,
        skipStaticSetup,
        dynamicCache
    )

end

-- Update the Gender icon and its background according to SaveParameter.Gender.
--
-- Separate Male and Female Widgets are used for both the icon and background.
-- All four Widgets are first made transparent to clear the previous state,
-- then only the Widgets corresponding to the current Gender are made visible.
--
-- This prevents the previous Pal's Gender display from remaining
-- when the contents of a slot are changed.
local function UpdateGender(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    local gender =
        save.Gender

    if not skipStaticSetup then

        SetupImage(
            overlay.Gender.Male.Image_MaleIconBG,
            Res.texMale,
            Config.UI.Gender.Image_GenderIconBG,
            targetType,
            nil,
            false
        )

        SetupImage(
            overlay.Gender.Female.Image_FemaleIconBG,
            Res.texFemale,
            Config.UI.Gender.Image_GenderIconBG,
            targetType,
            nil,
            false
        )

        SetupImage(
            overlay.Gender.Male.Image_MaleIcon,
            Res.texMale,
            Config.UI.Gender.Image_GenderIcon,
            targetType,
            nil,
            false
        )

        SetupImage(
            overlay.Gender.Female.Image_FemaleIcon,
            Res.texFemale,
            Config.UI.Gender.Image_GenderIcon,
            targetType,
            nil,
            false
        )

    end

    SetImageTransparent(
        overlay.Gender.Male.Image_MaleIconBG,
        gender ~= 1,
        dynamicCache
    )

    SetImageTransparent(
        overlay.Gender.Male.Image_MaleIcon,
        gender ~= 1,
        dynamicCache
    )

    SetImageTransparent(
        overlay.Gender.Female.Image_FemaleIconBG,
        gender ~= 2,
        dynamicCache
    )

    SetImageTransparent(
        overlay.Gender.Female.Image_FemaleIcon,
        gender ~= 2,
        dynamicCache
    )

end

-- Update the four Rank icons according to SaveParameter.Rank.
--
-- The four Rank Widgets are created once and reused.
-- Only the icons representing the current Rank are displayed;
-- the remaining icons are made transparent.
--
-- For example, when Rank = 2, the first two icons are displayed
-- and the third and fourth icons are made transparent.
--
-- This function does not create or remove Widgets.
-- SetupImage() updates the existing Widgets, while SetImageTransparent()
-- controls their visibility according to the current Rank.
local function UpdateRank(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    local rank = save.Rank
    local starCount = math.max(0, math.min(4, rank - 1))
    local rankConfig = Config.UI.Rank.Image_RankIcon
    local centeredConfig = {}
    for key, value in pairs(rankConfig) do
        centeredConfig[key] = value
    end

    -- Center visible stars when a pooled slot changes Pal or rank.
    local rowWidth = (rankConfig.Width or 16)
        + math.max(0, starCount - 1) * (rankConfig.PitchX or 0)
    centeredConfig.Left = (Config.UI.BaseSize - rowWidth) / 2
    local updateLayout = not skipStaticSetup
        or overlay.CenteredRankCount ~= starCount

    for i = 1, 4 do

        if not skipStaticSetup then

            SetupImage(
                overlay.Rank.Image_RankIcon[i],
                Res.texRankStar,
                centeredConfig,
                targetType,
                i,
                false
            )

        elseif updateLayout then
            SetupSlot(
                overlay.Rank.Image_RankIcon[i],
                centeredConfig,
                targetType,
                i
            )
        end

        SetImageTransparent(
            overlay.Rank.Image_RankIcon[i],
            i >= rank,
            dynamicCache
        )

    end

    overlay.CenteredRankCount = starCount
end

-- Calculate the Soul Rank and update its icon and numeric value.
--
-- Whether the Soul Rank display is hidden when the value is 0
-- is handled by UpdateOverlayVisibility() according to
-- DisplayOption.Soul.HideZero.
local function UpdateSoul(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    local soul =
        CalculateSoulRank(save)

    if not skipStaticSetup then

        SetupImage(
            overlay.Soul.Image_SoulIcon,
            Res.texSoul,
            Config.UI.Soul.Image_SoulIcon,
            targetType,
            nil,
            false
        )

    end

    SetupText(
        overlay.Soul.Text_SoulValue,
        tostring(soul),
        Config.UI.Soul.Text_SoulValue,
        targetType,
        nil,
        skipStaticSetup,
        dynamicCache
    )

    SetImageTransparent(
        overlay.Soul.Image_SoulIcon,
        false,
        dynamicCache
    )

    if dynamicCache then
        dynamicCache.SoulValue = soul
    end

end

-- Calculate the Friendship Rank from FriendshipPoint
-- and update its icon and numeric value.
--
-- Whether the Friendship Rank display is hidden when the value is 0
-- is handled by UpdateOverlayVisibility().
local function UpdateFriendship(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    local friendship =
        CalculateFriendshipRank(save)

    if not skipStaticSetup then

        SetupImage(
            overlay.Friendship.Image_FriendshipIcon,
            Res.texFriendship,
            Config.UI.Friendship.Image_FriendshipIcon,
            targetType,
            nil,
            false
        )

    end

    SetupText(
        overlay.Friendship.Text_FriendshipValue,
        tostring(friendship),
        Config.UI.Friendship.Text_FriendshipValue,
        targetType,
        nil,
        skipStaticSetup,
        dynamicCache
    )

    SetImageTransparent(
        overlay.Friendship.Image_FriendshipIcon,
        false,
        dynamicCache
    )

    if dynamicCache then
        dynamicCache.FriendshipValue = friendship
    end

end

-- Determine the Image and Text colors for a Passive Skill
-- according to its Skill Rank.
--
-- The color definitions are centralized in PassiveSkillColor.
-- This function only selects the appropriate color definitions;
-- applying them to the Widgets is handled separately by
-- SetImageColor() and SetTextColor().
--
-- Image and Text colors are returned separately because they are
-- applied to different Widget types.
--
-- Return values are ordered as Image color, then Text color.
local function GetPassiveSkillColor(rank)

    if rank <= -1 then

        return
            PassiveSkillColor.Red,
            PassiveSkillColor.White

    elseif rank == 1 then

        return
            PassiveSkillColor.White,
            PassiveSkillColor.White

    elseif rank <= 3 then

        return
            PassiveSkillColor.Yellow,
            PassiveSkillColor.Yellow

    else

        return
            PassiveSkillColor.Green,
            PassiveSkillColor.Green

    end

end

-- Update the icons, name backgrounds, and names for four Passive Skill slots.
--
-- When Config.DisplayOption.PassiveSkill.SortBySkillRank is enabled,
-- skills are sorted by descending SkillRank, with SkillID used
-- as the secondary sort key.
--
-- If fewer than four skills are available, the unused Widgets
-- are made transparent and their text is cleared.
--
-- For existing skills, the Image and Text colors are selected
-- according to SkillRank.
-- SetImageColor() and SetTextColor() preserve the existing Alpha,
-- allowing Config.UI transparency settings to remain unchanged.
local function UpdatePassiveSkill(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    local passiveSkillList =
        GetPassiveSkillData(
            save,
            dynamicCache
                and dynamicCache.PassiveSkillScratch
                or nil
        )

    ------------------------------------------------
    -- Sort by SkillRank
    ------------------------------------------------

    if Config.DisplayOption.PassiveSkill.SortBySkillRank then

        table.sort(
            passiveSkillList,
            ComparePassiveSkillRank
        )

    end

    ------------------------------------------------
    -- Passive Skill Bar Background
    ------------------------------------------------

    if not skipStaticSetup then

        SetupImage(
            overlay.PassiveSkill.Bar.Image_Background,
            Res.texSolidWhite,
            Config.UI.PassiveSkill.Bar.Image_Background,
            targetType,
            nil,
            false
        )

    end

    ------------------------------------------------
    -- Passive Skill
    ------------------------------------------------

    for i = 1, 4 do

        local imgIcon =
            overlay.PassiveSkill.Bar.Image_PassiveSkillIcon[i]

        local txtName =
            overlay.PassiveSkill.Name.Text_PassiveSkillName[i]

        local imgNameBG =
            overlay.PassiveSkill.Name.Image_Background[i]

        local skill =
            passiveSkillList[i]

        if skill then

            local colorImage, colorText =
                GetPassiveSkillColor(
                    skill.SkillRank
                )

            ------------------------------------------------
            -- Icon
            ------------------------------------------------

            if not skipStaticSetup then

                SetupImage(
                    imgIcon,
                    Res.texSolidWhite,
                    Config.UI.PassiveSkill.Bar.Image_PassiveSkillIcon,
                    targetType,
                    i,
                    false
                )

            else

                RestoreImageConfiguredAlpha(
                    imgIcon,
                    Config.UI.PassiveSkill.Bar.Image_PassiveSkillIcon,
                    dynamicCache
                )

            end

            SetImageColorCached(
                imgIcon,
                colorImage,
                dynamicCache
            )

            ------------------------------------------------
            -- Name Background
            ------------------------------------------------

            if not skipStaticSetup then

                SetupImage(
                    imgNameBG,
                    Res.texSolidWhite,
                    Config.UI.PassiveSkill.Name.Image_Background,
                    targetType,
                    i,
                    false
                )

            else

                RestoreImageConfiguredAlpha(
                    imgNameBG,
                    Config.UI.PassiveSkill.Name.Image_Background,
                    dynamicCache
                )

            end

            SetImageColorCached(
                imgNameBG,
                colorImage,
                dynamicCache
            )

            ------------------------------------------------
            -- Name
            ------------------------------------------------

            SetupText(
                txtName,
                tostring(skill.SkillName),
                Config.UI.PassiveSkill.Name.Text_PassiveSkillName,
                targetType,
                i,
                skipStaticSetup,
                dynamicCache
            )

            SetTextColorCached(
                txtName,
                colorText,
                dynamicCache
            )

        else

            ------------------------------------------------
            -- No skill
            ------------------------------------------------

            SetImageTransparent(
                imgIcon,
                true,
                dynamicCache
            )

            SetImageTransparent(
                imgNameBG,
                true,
                dynamicCache
            )

            SetupText(
                txtName,
                "",
                Config.UI.PassiveSkill.Name.Text_PassiveSkillName,
                targetType,
                i,
                skipStaticSetup,
                dynamicCache
            )

        end

    end

end

-- Display the HP, ATK, and DEF Talent values and determine
-- their display colors and text according to the configured thresholds.
--
-- SaveParameter stores the three values as:
--
--     Talent_HP
--     Talent_Shot
--     Talent_Defense
--
-- Talent_Shot is displayed as ATK by this MOD.
--
-- The three values share Config.UI.Talent.Text_TalentValue.
-- Their positions are differentiated by the index using PitchX / PitchY.
--
-- Values below HideValueBelow are replaced with HideValueSymbol.
-- If HideValueSymbol is empty, nothing is displayed for those values.
--
-- Values at or above MaxThreshold can be replaced with MaxValueSymbol.
-- If MaxValueSymbol is empty, the numeric value is displayed instead.
--
-- Colors are selected according to GreenThreshold and MaxThreshold:
--
--   Below GreenThreshold
--       Blue
--
--   GreenThreshold to below MaxThreshold
--       Green
--
--   MaxThreshold and above
--       Yellow
--
-- The selected color is applied by SetTextColor().
-- SetTextColor() preserves the existing TextBlock Alpha.
local function UpdateTalent(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    local talentConfig =
        Config.DisplayOption.Talent

    local hideValueBelow =
        talentConfig.HideValueBelow

    local greenThreshold =
        talentConfig.GreenThreshold

    local maxThreshold =
        talentConfig.MaxThreshold

    -- Avoid allocating two three-element Lua arrays for every Pal update.
    -- The three fixed Talent fields are selected directly by index.
    for i = 1, 3 do

        local talentWidget
        local currentValue

        if i == 1 then

            talentWidget =
                overlay.Talent.Text_TalentHPValue

            currentValue =
                save.Talent_HP

        elseif i == 2 then

            talentWidget =
                overlay.Talent.Text_TalentATKValue

            currentValue =
                save.Talent_Shot

        else

            talentWidget =
                overlay.Talent.Text_TalentDEFValue

            currentValue =
                save.Talent_Defense

        end

        local color
        local text

        ------------------------------------------------
        -- Determine the color
        ------------------------------------------------

        if currentValue < greenThreshold then

            color = TalentColor.Blue

        elseif currentValue < maxThreshold then

            color = TalentColor.Green

        else

            color = TalentColor.Yellow

        end

        ------------------------------------------------
        -- Determine the displayed text
        ------------------------------------------------

        if currentValue < hideValueBelow then

            text =
                talentConfig.HideValueSymbol

        elseif currentValue >= maxThreshold then

            if talentConfig.MaxValueSymbol ~= "" then
                text = talentConfig.MaxValueSymbol
            else
                text = tostring(currentValue)
            end

        else

            text = tostring(currentValue)

        end

        SetupText(
            talentWidget,
            text,
            Config.UI.Talent.Text_TalentValue,
            targetType,
            i,
            skipStaticSetup,
            dynamicCache
        )

        SetTextColorCached(
            talentWidget,
            color,
            dynamicCache
        )

    end

end
-- Update all display items for one Pal Slot from SaveParameter.
--
-- This function controls the order in which each display item is updated.
-- Data retrieval and calculation are handled by the corresponding
-- Data Functions, while Widget manipulation is handled by the individual
-- Update functions above.
--
-- targetType identifies the Overlay target:
--
--   "Normal"
--       Normal PalBox slot
--
--   "Party"
--       Party Pal slot
--
-- targetType is passed through the UI update chain so that
-- target-specific layout settings can be applied by SetupSlot().
-- SaveParameter retrieval remains the responsibility of the caller.
local function UpdateOverlayData(
    overlay,
    save,
    targetType,
    skipStaticSetup,
    dynamicCache
)

    if not overlay or not save then
        return
    end

    UpdateNumber(
        overlay,
        save,
        targetType,
        skipStaticSetup,
        dynamicCache
    )

    UpdateLevel(
        overlay,
        save,
        targetType,
        skipStaticSetup,
        dynamicCache
    )

    UpdateGender(
        overlay,
        save,
        targetType,
        skipStaticSetup,
        dynamicCache
    )

    UpdateRank(
        overlay,
        save,
        targetType,
        skipStaticSetup,
        dynamicCache
    )

    UpdateSoul(
        overlay,
        save,
        targetType,
        skipStaticSetup,
        dynamicCache
    )

    UpdateFriendship(
        overlay,
        save,
        targetType,
        skipStaticSetup,
        dynamicCache
    )

    UpdatePassiveSkill(
        overlay,
        save,
        targetType,
        skipStaticSetup,
        dynamicCache
    )

    UpdateTalent(
        overlay,
        save,
        targetType,
        skipStaticSetup,
        dynamicCache
    )

end

------------------------------------------------
-- Slot Management
------------------------------------------------

-- Manage Overlay creation and retrieval for Pal Slots,
-- and apply SaveParameter data to the corresponding Overlays.
--
-- This section handles the Overlay Widget lifecycle separately
-- from display-content updates:
--
--   1. Create Overlays for Slots that already exist.
--   2. Retrieve existing Overlays or create them when necessary.
--   3. Apply SaveParameter data to the existing Overlays.
--
-- Each Overlay is created on the Canvas of its corresponding Slot.
-- Once created, the Overlay Widgets are reused instead of being
-- deleted and recreated whenever the Slot contents change.
--
-- Events such as SlotUpdate update the contents of existing Overlays
-- and create them only when they do not yet exist.
-- This keeps Widget creation and display-content updates separate.

-- Create Overlays for Normal PalBox Slots that already exist
-- when resource loading is complete.
--
-- This initialization targets Slots that existed before ResourceReady
-- became true. Slots created afterward are handled by the appropriate
-- Slot Hooks and create their Overlays as necessary.
--
-- This function is therefore intended to run only once for the
-- existing Normal PalBox Slots and does not need to be called repeatedly.
local function InitializeExistingSlots()

    local slots = FindAllOf("WBP_PalCharacterSlotBase_C")

    if not slots then
        return
    end

    for _, widget in ipairs(slots) do

        local ok, err = pcall(function()

            local excluded, belongsToPreset, excludedFromNormalPool =
                InspectNormalSlotParents(
                    widget
                )

            -- Inspect the Outer hierarchy once. Preset continues to use its
            -- dedicated route and excluded Widgets remain untouched.
            if excluded or belongsToPreset then
                return
            end

            local canvas = GetPalSlotCanvas(widget)

            if not canvas then
                return
            end

            ------------------------------------------------
            -- Check for an Existing Overlay
            ------------------------------------------------

            local okCount, count = pcall(function()

                return canvas:GetChildrenCount()

            end)


            if not okCount then

                DebugLog("GetChildrenCount Failed")

                return

            end

            if count < BASE_CHILD_COUNT_NORMAL then
                return
            end

            if count >= BASE_CHILD_COUNT_NORMAL + ADDED_CHILD_COUNT then
                return
            end

            -- Normal PalBox Slots now use the persistent Pool. This includes
            -- Slots that already exist when ResourceReady first becomes true.
            -- AcquireEntry() grows the pool synchronously if startup prewarm
            -- has not yet produced enough complete Entries.
            local poolMode, widgetAddress =
                SharedOverlayPool.GetWidgetPoolMode(
                    widget
                )

            if widgetAddress
                and SharedOverlayPool.WidgetRetiringReasonByAddress[
                    widgetAddress
                ] then
                return
            end

            if not excludedFromNormalPool
                and poolMode ~= false then

                if not SharedOverlayPool.EnsureReadyNow() then
                    Log(
                        "[OverlayPoolSafety] Required Normal Pool is unavailable."
                    )
                    return
                end

                local entry =
                    SharedOverlayPool.AcquireEntry(
                        widget,
                        canvas
                    )

                if entry then
                    return
                end

                Log(
                    "[OverlayPoolSafety] Required Normal Pool Entry acquisition failed."
                )
                return

            end

            -- Explicit direct targets only. Persistent PalBox/Preset/Condense
            -- targets never fall back from Pool ownership to direct creation.
            CreateOverlayWidgets(canvas)


        end)


        if not ok then

            Log(
                "Initialize Slot Error:",
                err
            )

        end

    end

end

-- Create or retrieve the Overlay for the specified Pal Slot
-- and apply the provided SaveParameter.
--
-- This function is the common entry point for Overlay processing
-- after the caller has obtained SaveParameter.
--
-- The caller is responsible for retrieving the appropriate
-- SaveParameter and passing it to this function.
-- SaveParameter retrieval is therefore not performed here.
--
-- targetType identifies the type of Overlay target being processed:
--
--   "Normal" - Normal PalBox / Preset slot
--   "Party"  - Party Pal slot
--   "Hatch"  - Incubator hatch-result entry
--
-- normalParentsChecked is used only by the high-frequency normal SlotUpdate
-- route after it has already classified the same parent hierarchy. This avoids
-- traversing the same Outer chain twice for that event.
--
-- The target configuration determines how the corresponding Slot
-- is located, where its Canvas is obtained, and how existing
-- Overlay Widgets are identified.
--
-- The processing order here is:
--
--     Obtain target configuration
--         ↓
--     Check exclusion (Normal only)
--         ↓
--     Obtain Canvas
--         ↓
--     Obtain existing Overlay / Create if necessary
--         ↓
--     UpdateOverlayData()
--         ↓
--     UpdateOverlayVisibility()
--
-- UpdateOverlayData() updates the contents of the Overlay Widgets.
-- UpdateOverlayVisibility() controls which display items are visible
-- according to the current DisplayMode and other display conditions.
--
-- These processes are kept separate so that Overlay contents can be
-- updated independently of their current visibility state.
UpdateSlotOverlay = function(
    widget,
    save,
    targetType,
    normalParentsChecked,
    allowNormalPoolAcquire,
    poolKind,
    knownWidgetAddress
)

    if not widget or not save then
        return
    end

    targetType =
        targetType or "Normal"

    local targetConfig =
        OverlayTargetConfig[targetType]

    if not targetConfig then
        return
    end

    ------------------------------------------------
    -- Exclusion
    ------------------------------------------------

    if targetType == "Normal"
        and not normalParentsChecked
        and IsExcludedWidget(widget) then

        return

    end

    ------------------------------------------------
    -- Existing pooled Entry
    ------------------------------------------------
    -- Look up the already-bound Entry before resolving the Slot Canvas.
    -- Once an Entry is attached, Overlay updates need only the Entry's cached
    -- Widget references; walking Text_ReviveTimer -> Slot.Parent three levels
    -- on every update is redundant.
    local pooledEntry = nil

    if poolKind == "Preset" then

        pooledEntry =
            SharedOverlayPool.GetEntryForWidget(
                widget,
                knownWidgetAddress
            )

    elseif targetType == "Normal" then

        pooledEntry =
            SharedOverlayPool.GetEntryForWidget(
                widget,
                knownWidgetAddress
            )

    elseif targetType == "Party"
        and PartyOverlayPool.Enabled
        and Config.DisplayOption.EnablePartyDisplay == true then

        pooledEntry =
            PartyOverlayPool.GetEntryForWidget(
                widget
            )

    end

    local overlay =
        pooledEntry
        and pooledEntry.Overlay
        or nil

    ------------------------------------------------
    -- Canvas / Pool acquisition / explicit direct route
    ------------------------------------------------

    if not overlay then

        local canvas =
            GetPalSlotCanvas(
                widget,
                targetType
            )

        if not canvas then
            return
        end

        if poolKind == "Preset" then

            -- Preset Entries are acquired only by BindPresetRowSlots(), where
            -- the exact row owner is known. Never create a temporarily
            -- ownerless Preset Entry from the data-update path.
            return

        elseif targetType == "Normal" then

            -- Only the ordinary Normal SlotUpdate route may claim a free
            -- Normal Pool Entry. Other refresh paths update an Entry only when
            -- it is already bound.
            if allowNormalPoolAcquire then

                local acquireReason = nil

                pooledEntry, acquireReason =
                    SharedOverlayPool.AcquireEntry(
                        widget,
                        canvas,
                        knownWidgetAddress
                    )

                -- A static Common Button can emit SlotUpdate from inside its
                -- Blueprint Setup before the post-hook publishes the exact
                -- Button owner. This is an expected deferred state (not a
                -- Pool failure). Condense Party is attached later at its
                -- authoritative setup-count boundary.
                if not pooledEntry
                    and acquireReason == "OwnerPending" then
                    return
                end

            end

        elseif targetType == "Party"
            and PartyOverlayPool.Enabled
            and Config.DisplayOption.EnablePartyDisplay == true then

            pooledEntry =
                PartyOverlayPool.AcquireEntry(
                    widget,
                    canvas
                )

        end

        if pooledEntry then
            overlay = pooledEntry.Overlay
        end

        if not overlay then

            local okCount, count =
                pcall(function()

                    return canvas:GetChildrenCount()

                end)

            if not okCount or not count then
                return
            end

            -- Existing direct Overlays may still be updated for explicitly
            -- direct auxiliary targets (and during an in-session upgrade from
            -- an older version), but pooled targets never create a new direct
            -- Overlay when Pool acquisition fails.
            if count >=
               targetConfig.BaseChildCount
               + ADDED_CHILD_COUNT
            then

                overlay =
                    GetOverlayWidgets(
                        canvas,
                        targetConfig.BaseChildCount
                    )

            else

                local allowDirectCreate =
                    targetType == "Hatch"
                    or (
                        targetType == "Normal"
                        and poolKind == nil
                        and allowNormalPoolAcquire == false
                    )

                if allowDirectCreate then

                    overlay =
                        CreateOverlayWidgets(canvas)

                else

                    local requiresPool =
                        poolKind == "Preset"
                        or poolKind == "CondenseParty"
                        or targetType == "Party"
                        or (
                            targetType == "Normal"
                            and allowNormalPoolAcquire == true
                        )

                    if requiresPool then
                        Log(
                            "[OverlayPoolSafety] Required pooled Overlay unavailable:",
                            targetType,
                            poolKind or "Normal"
                        )
                    end

                    return

                end

            end

        end

    end

    if not overlay then
        return
    end

    ------------------------------------------------
    -- Update Display Data
    ------------------------------------------------

    UpdateOverlayData(
        overlay,
        save,
        targetType,
        pooledEntry ~= nil,
        pooledEntry and pooledEntry.DynamicCache or nil
    )

    -- LastSave exists only for the short interval between the Normal
    -- SlotUpdate and AddSlotButtonToScrollList owner classification. It is
    -- needed to convert an auxiliary non-paged list back to the direct-child
    -- path. Do not retain SaveParameter on Party/Preset Entries or on Normal
    -- Entries whose paged owner is already known.
    if pooledEntry
        and targetType == "Normal"
        and poolKind == nil
        and pooledEntry.OwnerScrollListAddress == nil then

        pooledEntry.LastSave = save

    end

    ------------------------------------------------
    -- Update Visibility
    ------------------------------------------------

    UpdateOverlayVisibility(
        overlay,
        widget,
        nil,
        pooledEntry and pooledEntry.DynamicCache or nil
    )

    if pooledEntry
        and not pooledEntry.RootVisible then

        SetWidgetVisible(
            pooledEntry.Root,
            true
        )

        pooledEntry.RootVisible = true

    end

end

------------------------------------------------
-- Controller DisplayMode Bridge
------------------------------------------------
--
-- PalIconInfo-specific controller implementation.
--
-- ControllerInput is intentionally not responsible for:
--   * creating this Widget
--   * deciding which DisplayMode state changes
--   * PalBox lifecycle
--   * callback Hook targets
--
-- The direct WBP_BoxPalListBase bridge is used as a lightweight CommonUI
-- callback receiver without retaining a live PalBox UObject.
------------------------------------------------

local function GetDisplayModeWidgetBlueprintLibrary()

    if DisplayModeWidgetBlueprintLibrary then
        return DisplayModeWidgetBlueprintLibrary
    end

    local ok, result =
        pcall(function()

            return StaticFindObject(
                WIDGET_BLUEPRINT_LIBRARY
            )

        end)

    if not ok
        or not result then
        return nil
    end

    DisplayModeWidgetBlueprintLibrary =
        result

    return DisplayModeWidgetBlueprintLibrary

end


local function GetDisplayModeBoxPalListBaseClass()

    if DisplayModeBoxPalListBaseClass then
        return DisplayModeBoxPalListBaseClass
    end

    local ok, result =
        pcall(function()

            return StaticFindObject(
                PAL_BOX_LIST_BASE_CLASS
            )

        end)

    if not ok
        or not result then
        return nil
    end

    DisplayModeBoxPalListBaseClass =
        result

    return DisplayModeBoxPalListBaseClass

end


local function GetDisplayModeObjectFullName(
    object
)

    if not object then
        return nil
    end

    local ok, result =
        pcall(function()

            return object:GetFullName()

        end)

    if not ok
        or type(result) ~= "string"
        or result == "" then
        return nil
    end

    return result

end


-- Return only the transient object path accepted by StaticFindObject().
-- No live PalBox UObject is retained between events.
local function GetDisplayModeObjectPath(
    object
)

    local fullName =
        GetDisplayModeObjectFullName(
            object
        )

    if not fullName then
        return nil
    end

    return fullName:match(
        "^%S+%s+(.+)$"
    )

end


local function ResolveDisplayModeGamepadButton(
    button
)

    if type(button) ~= "string"
        or button == "" then
        return nil
    end

    local mapped =
        DISPLAY_MODE_GAMEPAD_BUTTON_ALIASES[
            button
        ]

    if mapped then
        return mapped
    end

    -- Allow a raw Unreal FKey name when editing the Lua config manually.
    -- DarnMenu exposes only the supported Right Stick choices above.
    if button:match("^Gamepad_") then
        return button
    end

    return nil

end


local function FindGamepadDisplayMode(
    sourceConfig
)

    local displayMode =
        sourceConfig
        and sourceConfig.DisplayMode

    if type(displayMode) ~= "table" then
        return nil, nil, nil,
            "Config.DisplayMode is unavailable."
    end

    local selectedKey = nil
    local selectedStates = nil
    local selectedButton = nil

    for keyCode, states
        in pairs(displayMode) do

        if type(states) == "table"
            and #states > 0
            and type(states.GamepadButton)
                == "string"
            and states.GamepadButton ~= "" then

            if selectedKey ~= nil then

                return nil, nil, nil,
                    "Multiple DisplayMode entries define GamepadButton."

            end

            selectedKey = keyCode
            selectedStates = states
            selectedButton =
                states.GamepadButton

        end

    end

    if selectedKey == nil then

        return nil, nil, nil,
            "No DisplayMode entry defines GamepadButton."

    end

    return selectedKey,
        selectedStates,
        selectedButton

end


local function GetDisplayModeInputConfig(
    sourceConfig
)

    local sourceKey,
        states,
        button,
        targetError =
        FindGamepadDisplayMode(
            sourceConfig
        )

    if sourceKey == nil
        or type(states) ~= "table" then

        return nil,
            targetError
    end

    local gamepadKey =
        ResolveDisplayModeGamepadButton(
            button
        )

    if not gamepadKey then
        return nil,
            "Unsupported DisplayMode GamepadButton: "
            .. tostring(button)
    end

    local keyboardKey,
        keyboardError =
        ControllerInput.ResolveKeyboardKeyName(
            sourceKey
        )

    if not keyboardKey then
        return nil,
            "Unsupported DisplayMode keyboard key: "
            .. tostring(keyboardError)
    end

    return {
        Button = button,
        KeyboardKey = keyboardKey,
        GamepadKey = gamepadKey,
        SourceKey = sourceKey,
        States = states,
    }

end


------------------------------------------------
-- Vanilla R3 Guide Suppression
------------------------------------------------
--
-- These two vanilla R3 guides are not part of the normal CommonUI
-- Action Bar. Each screen owns a dedicated guide Widget:
--
-- Global PalBox:
--   Action  = GlobalPalStorage_StartRemoveData
--   Owner   = WBP_IngameMenu_PalBoxGlobal_C
--   Guide   = Canvas_RemoveGuide
--
-- Dimensional Pal Storage:
--   Action  = DimensionLocker_SendAll
--   Owner   = WBP_IngameMenu_PalBoxLocker_C
--   Guide   = Canvas_DropGuide
--
-- The Blueprint JSON confirms that the corresponding
-- WBP_PalKeyGuideIcon is a child of each Canvas and is bound directly
-- to the Action above.
--
-- The owner screen is recovered from the already observed
-- WBP_BoxPalListBase:SetMaxPageNum event. No RegisterActionBinding observer
-- and no screen-specific Setup Hook is required.
--
-- Only the row that belongs to the conflicting R3 action is collapsed.
-- Other guide rows in the same Canvas remain untouched.
--
-- No real PalBox UObject is retained. Only the transient owner path and
-- the original guide Visibility are stored.
------------------------------------------------

local VANILLA_R3_GUIDE_COLLAPSED_VISIBILITY = 1


local function GetDirectChildrenByName(
    panel,
    names
)

    if not panel
        or type(names) ~= "table" then
        return {}
    end

    local wanted = {}

    for _, name
        in ipairs(names) do

        if type(name) == "string"
            and name ~= "" then
            wanted[name] = true
        end

    end

    local found = {}

    local okCount, count =
        pcall(function()

            return panel:GetChildrenCount()

        end)

    if not okCount
        or type(count) ~= "number" then
        return found
    end

    for index = 0, count - 1 do

        local child = nil

        local okChild =
            pcall(function()

                child =
                    panel:GetChildAt(
                        index
                    )

            end)

        if okChild
            and child then

            local childName = nil

            pcall(function()

                local fname =
                    child:GetFName()

                if fname then
                    childName =
                        fname:ToString()
                end

            end)

            if childName
                and wanted[
                    childName
                ] then

                found[
                    childName
                ] = child

            end

        end

    end

    local result = {}

    for _, name
        in ipairs(names) do

        local child =
            found[
                name
            ]

        if child then
            table.insert(
                result,
                child
            )
        end

    end

    return result

end


local VanillaR3GuideTargets = {

    ["GlobalPalStorage_StartRemoveData"] = {

        OwnerClass =
            "WBP_IngameMenu_PalBoxGlobal_C",

        GetWidgets =
            function(owner)

                local widgets =
                    GetDirectChildrenByName(
                        owner.Canvas_RemoveGuide,
                        {
                            -- R3 icon for "Delete Selection".
                            "WBP_PalKeyGuideIcon",

                            -- Text row for "Delete Selection".
                            "HorizontalBox_0",
                        }
                    )

                -- The same R3 Action is also used by the icon embedded in the
                -- remove-confirm button. Suppress only that icon as well.
                local confirmIcon =
                    owner.WBP_PalKeyGuideIcon_1

                if confirmIcon then
                    table.insert(
                        widgets,
                        confirmIcon
                    )
                end

                return widgets

            end,

        OwnerPath = nil,
        OriginalVisibility = {},

    },

    ["DimensionLocker_SendAll"] = {

        OwnerClass =
            "WBP_IngameMenu_PalBoxLocker_C",

        GetWidgets =
            function(owner)

                return
                    GetDirectChildrenByName(
                        owner.Canvas_DropGuide,
                        {
                            -- R3 icon for "Send All Pals".
                            "WBP_PalKeyGuideIcon",

                            -- Text for "Send All Pals".
                            "BP_PalTextBlock_C",
                        }
                    )

            end,

        OwnerPath = nil,
        OriginalVisibility = {},

    },

}


local function IsDisplayModeUsingR3()

    local controllerConfig =
        GetDisplayModeInputConfig(
            Config
        )

    return controllerConfig ~= nil
        and controllerConfig.GamepadKey
            == "Gamepad_RightThumbstick"

end


local function ResolveVanillaR3GuideOwner(
    ownerPath
)

    if type(ownerPath) ~= "string"
        or ownerPath == "" then
        return nil
    end

    local owner = nil

    local ok =
        pcall(function()

            owner =
                StaticFindObject(
                    ownerPath
                )

        end)

    if not ok then
        return nil
    end

    return owner

end


local function GetVanillaR3GuideWidgets(
    target,
    owner
)

    if type(target) ~= "table"
        or not owner then
        return {}
    end

    local widgets = nil

    local ok =
        pcall(function()

            widgets =
                target.GetWidgets(
                    owner
                )

        end)

    if not ok
        or type(widgets) ~= "table" then
        return {}
    end

    return widgets

end


local function ApplyVanillaR3GuideTarget(
    target,
    suppress
)

    if type(target) ~= "table"
        or not target.OwnerPath then
        return
    end

    local owner =
        ResolveVanillaR3GuideOwner(
            target.OwnerPath
        )

    if not owner then
        return
    end

    local widgets =
        GetVanillaR3GuideWidgets(
            target,
            owner
        )

    for index, widget
        in ipairs(widgets) do

        if widget then

            if suppress then

                pcall(function()

                    widget:SetVisibility(
                        VANILLA_R3_GUIDE_COLLAPSED_VISIBILITY
                    )

                end)

            else

                local originalVisibility =
                    target.OriginalVisibility[
                        index
                    ]

                if originalVisibility
                    ~= nil then

                    pcall(function()

                        widget:SetVisibility(
                            originalVisibility
                        )

                    end)

                end

            end

        end

    end

end


local function CaptureVanillaR3GuideOwnerObject(
    owner,
    actionName
)

    local target =
        VanillaR3GuideTargets[
            actionName
        ]

    if not target
        or not owner then
        return nil
    end

    if GetOuterClassName(
        owner,
        0
    ) ~= target.OwnerClass then

        return nil
    end

    local ownerPath =
        GetDisplayModeObjectPath(
            owner
        )

    if not ownerPath then
        return nil
    end

    if target.OwnerPath
        ~= ownerPath then

        target.OwnerPath =
            ownerPath

        target.OriginalVisibility =
            {}

        local widgets =
            GetVanillaR3GuideWidgets(
                target,
                owner
            )

        for index, widget
            in ipairs(widgets) do

            if widget then

                pcall(function()

                    target.OriginalVisibility[
                        index
                    ] =
                        widget:GetVisibility()

                end)

            end

        end

        DebugLog(
            "Vanilla R3 guide owner captured:",
            actionName,
            target.OwnerClass
        )

    end

    return target

end


-- WBP_BoxPalListBase:SetMaxPageNum is already used as the normal PalBox
-- lifetime event for DisplayMode. At that point the complete owning screen is
-- loaded, so walk only the UObject Outer chain and capture the two exact
-- screens that own conflicting R3 guides. This avoids both a global
-- RegisterActionBinding Hook and screen-specific Setup Hook timing problems.
local function CaptureVanillaR3GuideFromPalBoxBase(
    baseWidget
)

    local current =
        baseWidget

    for _ = 1, 8 do

        if not current then
            break
        end

        local className =
            GetOuterClassName(
                current,
                0
            )

        for actionName, target
            in pairs(
                VanillaR3GuideTargets
            ) do

            if className
                == target.OwnerClass then

                local captured =
                    CaptureVanillaR3GuideOwnerObject(
                        current,
                        actionName
                    )

                if captured then

                    ApplyVanillaR3GuideTarget(
                        captured,
                        IsDisplayModeUsingR3()
                    )

                end

                return
            end

        end

        local outer = nil

        local okOuter =
            pcall(function()

                outer =
                    current:GetOuter()

            end)

        if not okOuter
            or not outer then
            break
        end

        if GetOuterClassName(
            outer,
            0
        ) == "Package" then

            break
        end

        current = outer

    end

end



RefreshVanillaR3GuideVisibility =
    function()

        local suppress =
            IsDisplayModeUsingR3()

        for _, target
            in pairs(
                VanillaR3GuideTargets
            ) do

            ApplyVanillaR3GuideTarget(
                target,
                suppress
            )

        end

    end



local function EnsureDisplayModeControllerRows(
    worldContextObject,
    ownerKind
)

    local controllerConfig =
        GetDisplayModeInputConfig(
            Config
        )

    -- The Preset screen also uses this bridge for the Swap Preset Action.
    -- Therefore the bridge may exist there even when no DisplayMode Gamepad input
    -- is configured. In that case the DisplayMode side of the bridge is disabled.
    local displayModeKeyboard = "None"
    local displayModeGamepad = "None"
    local displayModeDisplayName = ""
    local displayModeHoldDisplayName = ""

    if controllerConfig then

        displayModeKeyboard =
            controllerConfig.KeyboardKey

        displayModeGamepad =
            controllerConfig.GamepadKey

        displayModeDisplayName =
            DISPLAY_MODE_GUIDE_DISPLAY_NAME

        displayModeHoldDisplayName =
            DISPLAY_MODE_GUIDE_DISPLAY_NAME

    elseif ownerKind ~= "Preset" then

        return false,
            "CommonUI DisplayMode configuration is disabled or invalid."

    end

    local borrowedAction,
        actionError =
        ControllerInput.BorrowActionRow(
            DISPLAY_MODE_CONTROLLER_OWNER,
            worldContextObject,
            DISPLAY_MODE_ACTION,
            {
                Keyboard =
                    displayModeKeyboard,
                Gamepad =
                    displayModeGamepad,
                DisplayName =
                    displayModeDisplayName,
                HoldDisplayName =
                    displayModeHoldDisplayName,
                NavBarPriority = 40,
            }
        )

    if not borrowedAction then
        return false, actionError
    end

    local presetSwapEnabled =
        ownerKind == "Preset"

    local borrowedUnused,
        unusedError =
        ControllerInput.BorrowActionRow(
            DISPLAY_MODE_CONTROLLER_OWNER,
            worldContextObject,
            DISPLAY_MODE_UNUSED_ACTION,
            {
                Keyboard =
                    presetSwapEnabled
                    and PRESET_SWAP_MOUSE_KEY
                    or "None",
                Gamepad =
                    presetSwapEnabled
                    and PRESET_SWAP_GAMEPAD_KEY
                    or "None",
                DisplayName =
                    presetSwapEnabled
                    and PRESET_SWAP_GUIDE_DISPLAY_NAME
                    or "",
                HoldDisplayName =
                    presetSwapEnabled
                    and PRESET_SWAP_GUIDE_DISPLAY_NAME
                    or "",
                NavBarPriority = 39,
            }
        )

    if not borrowedUnused then

        ControllerInput.RestoreBorrowedActionRows(
            DISPLAY_MODE_CONTROLLER_OWNER
        )

        return false, unusedError
    end

    return true

end


RefreshDisplayModeControllerBinding =
    function()

        local controllerConfig =
            GetDisplayModeInputConfig(
                Config
            )

        local ownerKind =
            DisplayModeControllerOwnerKind

        -- Without a live bridge there is nothing to rebind. The next screen
        -- bridge creation will use the current Config and Preset reorder state.
        if not DisplayModeControllerBridge then

            if controllerConfig
                or ownerKind == "Preset" then
                return true
            end

            return false,
                "DisplayMode CommonUI input configuration is invalid."
        end

        -- A Preset bridge remains valid even when DisplayMode Gamepad input is
        -- disabled because its unused Prev side carries the Swap Preset Action.
        if not controllerConfig
            and ownerKind ~= "Preset" then
            return false,
                "DisplayMode CommonUI input configuration is invalid."
        end

        local displayModeKeyboard = "None"
        local displayModeGamepad = "None"
        local displayModeDisplayName = ""
        local displayModeHoldDisplayName = ""

        if controllerConfig then

            displayModeKeyboard =
                controllerConfig.KeyboardKey

            displayModeGamepad =
                controllerConfig.GamepadKey

            displayModeDisplayName =
                DISPLAY_MODE_GUIDE_DISPLAY_NAME

            displayModeHoldDisplayName =
                DISPLAY_MODE_GUIDE_DISPLAY_NAME

        end

        local updated, updateError =
            ControllerInput.UpdateBorrowedActionRow(
                DISPLAY_MODE_CONTROLLER_OWNER,
                DISPLAY_MODE_ACTION,
                {
                    Keyboard =
                        displayModeKeyboard,
                    Gamepad =
                        displayModeGamepad,
                    DisplayName =
                        displayModeDisplayName,
                    HoldDisplayName =
                        displayModeHoldDisplayName,
                    NavBarPriority = 40,
                }
            )

        if not updated then
            return false, updateError
        end

        local presetSwapEnabled =
            ownerKind == "Preset"

        local updatedUnused, unusedError =
            ControllerInput.UpdateBorrowedActionRow(
                DISPLAY_MODE_CONTROLLER_OWNER,
                DISPLAY_MODE_UNUSED_ACTION,
                {
                    Keyboard =
                        presetSwapEnabled
                        and PRESET_SWAP_MOUSE_KEY
                        or "None",
                    Gamepad =
                        presetSwapEnabled
                        and PRESET_SWAP_GAMEPAD_KEY
                        or "None",
                    DisplayName =
                        presetSwapEnabled
                        and PRESET_SWAP_GUIDE_DISPLAY_NAME
                        or "",
                    HoldDisplayName =
                        presetSwapEnabled
                        and PRESET_SWAP_GUIDE_DISPLAY_NAME
                        or "",
                    NavBarPriority = 39,
                }
            )

        if not updatedUnused then
            return false, unusedError
        end

        local okRebind, rebindError =
            pcall(function()

                DisplayModeControllerBridge:
                    RemovePageControlAction()

                -- Let CommonUI expose the Blueprint-native bindings through the
                -- normal Action Bar while SetPageControlAction() registers them.
                DisplayModeControllerBridge.bDisplayInActionBar = true

                DisplayModeControllerBridge:
                    SetPageControlAction(
                        {
                            Key =
                                FName(
                                    DISPLAY_MODE_ACTION
                                ),
                        },
                        {
                            Key =
                                FName(
                                    DISPLAY_MODE_UNUSED_ACTION
                                ),
                        }
                    )

                DisplayModeControllerBridge.bDisplayInActionBar = false

                DisplayModeControllerBridge:
                    SetVisibility(1)

            end)

        if not okRebind then
            return false,
                tostring(rebindError)
        end

        DebugLog(
            "CommonUI DisplayMode binding updated:",
            "Keyboard =",
            displayModeKeyboard,
            "Gamepad =",
            displayModeGamepad,
            "PresetSwap =",
            presetSwapEnabled,
            "PresetSwapMouse =",
            presetSwapEnabled and PRESET_SWAP_MOUSE_KEY or "None"
        )

        return true

    end


local function FindDisplayModeBridgeAttachPanel(
    worldContextObject
)

    if not worldContextObject then
        return nil
    end

    -- Use the same direct bridge attachment path as PageSkip.
    --
    -- GetParent() is attempted only as a one-time bridge-creation lookup.
    -- If the current object itself is not directly under a PanelWidget,
    -- follow the UObject Outer hierarchy and retry. Stop before Package.
    local current =
        worldContextObject

    for _ = 1, 6 do

        if not current then
            break
        end

        local parentPanel = nil

        local okParent =
            pcall(function()

                parentPanel =
                    current:GetParent()

            end)

        if okParent
            and parentPanel then

            local okPanel =
                pcall(function()

                    parentPanel:GetChildrenCount()

                end)

            if okPanel then
                return parentPanel
            end

        end

        local outer = nil

        local okOuter =
            pcall(function()

                outer =
                    current:GetOuter()

            end)

        if not okOuter
            or not outer then
            break
        end

        local className =
            GetOuterClassName(
                outer,
                0
            )

        if className == "Package" then
            break
        end

        current = outer

    end

    return nil

end


local function ReleaseDisplayModeBridgeWidget(
    bridge
)

    if not bridge
        or not SharedOverlayPool.IsValidObject(bridge) then
        return
    end

    DisplayModeControllerDestroying = true

    pcall(function()
        bridge:RemovePageControlAction()
    end)

    pcall(function()
        bridge:DeactivateWidget()
    end)

    -- Deactivation removes the CommonUI bindings, but the Widget itself
    -- otherwise remains a child of the Panel. Remove it as well so repeated
    -- PalBox <-> Preset transitions do not accumulate inactive bridges.
    pcall(function()
        bridge:RemoveFromParent()
    end)

    DisplayModeControllerDestroying = false

end


local function DestroyDisplayModeControllerBridge()

    local bridge =
        DisplayModeControllerBridge

    if not bridge then

        ControllerInput.RestoreBorrowedActionRows(
            DISPLAY_MODE_CONTROLLER_OWNER
        )

        DisplayModeControllerBridgeName = nil
        DisplayModeControllerOwnerName = nil
        DisplayModeControllerOwnerKind = nil
        return

    end

    ReleaseDisplayModeBridgeWidget(
        bridge
    )

    DisplayModeControllerBridge = nil
    DisplayModeControllerBridgeName = nil
    DisplayModeControllerOwnerName = nil
    DisplayModeControllerOwnerKind = nil

    ControllerInput.RestoreBorrowedActionRows(
        DISPLAY_MODE_CONTROLLER_OWNER
    )

    return true

end


local function CreateDisplayModeControllerBridge(
    worldContextObject,
    ownerKind,
    attachPanelOverride
)

    if DisplayModeControllerBridge
        or DisplayModeControllerCreating then

        return DisplayModeControllerBridge
    end

    local controllerConfig =
        GetDisplayModeInputConfig(
            Config
        )

    if not controllerConfig
        and ownerKind ~= "Preset" then

        return nil,
            "Controller DisplayMode configuration is unavailable."
    end

    local ownerName =
        GetDisplayModeObjectFullName(
            worldContextObject
        )

    if not ownerName then
        return nil,
            "DisplayMode bridge owner identity is unavailable."
    end

    local bridgeClass =
        GetDisplayModeBoxPalListBaseClass()

    if not bridgeClass then
        return nil,
            "WBP_BoxPalListBase_C bridge class is unavailable."
    end

    local widgetLibrary =
        GetDisplayModeWidgetBlueprintLibrary()

    if not widgetLibrary then
        return nil,
            "WidgetBlueprintLibrary is unavailable."
    end

    local rowsReady, rowError =
        EnsureDisplayModeControllerRows(
            worldContextObject,
            ownerKind
        )

    if not rowsReady then

        Log(
            "DisplayMode Action row setup failed:",
            rowError
        )

        return nil
    end

    local owningPlayer = nil

    local okOwner =
        pcall(function()

            owningPlayer =
                worldContextObject:GetOwningPlayer()

        end)

    if not okOwner
        or not owningPlayer then

        ControllerInput.RestoreBorrowedActionRows(
            DISPLAY_MODE_CONTROLLER_OWNER
        )

        return nil,
            "Owning Player is unavailable."
    end

    local attachPanel =
        attachPanelOverride

    if attachPanel then

        local okPanel =
            pcall(function()

                attachPanel:GetChildrenCount()

            end)

        if not okPanel then
            attachPanel = nil
        end

    else

        attachPanel =
            FindDisplayModeBridgeAttachPanel(
                worldContextObject
            )

    end

    if not attachPanel then

        ControllerInput.RestoreBorrowedActionRows(
            DISPLAY_MODE_CONTROLLER_OWNER
        )

        return nil,
            "Live parent PanelWidget for DisplayMode bridge is unavailable."
    end

    local bridge = nil

    DisplayModeControllerCreating = true

    local okCreate =
        pcall(function()

            bridge =
                widgetLibrary:Create(
                    worldContextObject,
                    bridgeClass,
                    owningPlayer
                )

        end)

    if not okCreate
        or not bridge then

        DisplayModeControllerCreating = false

        ControllerInput.RestoreBorrowedActionRows(
            DISPLAY_MODE_CONTROLLER_OWNER
        )

        return nil,
            "WBP_BoxPalListBase DisplayMode bridge creation failed."
    end

    local okSetup =
        pcall(function()

            -- Keep the hidden base's own native Next/Prev callback work inside
            -- a harmless single-page range. No SetMaxPageNum() call is made.
            bridge.MaxPageNum = 1
            bridge.LastSelectedPageNum = 0

            attachPanel:AddChild(
                bridge
            )

            bridge:SetVisibility(1)

            if bridge:IsActivated() ~= true then
                bridge:ActivateWidget()
            end

            bridge:SetVisibility(1)

        end)

    DisplayModeControllerCreating = false

    if not okSetup then

        ReleaseDisplayModeBridgeWidget(
            bridge
        )

        ControllerInput.RestoreBorrowedActionRows(
            DISPLAY_MODE_CONTROLLER_OWNER
        )

        return nil,
            "DisplayMode bridge setup / attach / activation failed."
    end

    local bridgeName =
        GetDisplayModeObjectFullName(
            bridge
        )

    if not bridgeName then

        ReleaseDisplayModeBridgeWidget(
            bridge
        )

        ControllerInput.RestoreBorrowedActionRows(
            DISPLAY_MODE_CONTROLLER_OWNER
        )

        return nil,
            "DisplayMode bridge identity is unavailable."
    end

    DisplayModeControllerBridge =
        bridge

    DisplayModeControllerBridgeName =
        bridgeName

    DisplayModeControllerOwnerName =
        ownerName

    DisplayModeControllerOwnerKind =
        ownerKind or "PalBox"

    local okBinding, bindingError =
        pcall(function()

            -- Next Action = shared Keyboard/Gamepad DisplayMode input when configured.
            -- Prev Action = Middle Mouse / Square / X Preset reorder input only on the Preset screen;
            -- otherwise it remains a disabled dummy row.
            -- SetPageControlAction() creates the native CommonUI bindings itself.
            -- Expose those Blueprint-native bindings through CommonUI's normal Action Bar path.
            bridge.bDisplayInActionBar = true

            bridge:SetPageControlAction(
                {
                    Key =
                        FName(
                            DISPLAY_MODE_ACTION
                        ),
                },
                {
                    Key =
                        FName(
                            DISPLAY_MODE_UNUSED_ACTION
                        ),
                }
            )

            bridge.bDisplayInActionBar = false

            bridge:SetVisibility(1)

        end)


    if not okBinding then

        DestroyDisplayModeControllerBridge()

        return nil,
            "SetPageControlAction failed for the DisplayMode bridge: "
            .. tostring(
                bindingError
            )
    end

    DebugLog(
        "DisplayMode CommonUI bridge:",
        bridgeName
    )

    return bridge

end


-- Ensure that DisplayMode has the same CommonUI Keyboard/Gamepad Action on
-- standalone PalIconInfo screens that do not own a normal PalBox list.
-- Only one DisplayMode bridge exists at a time.
local function EnsureStandaloneDisplayModeControllerBridge(
    worldContextObject,
    ownerKind,
    attachPanelOverride
)

    if not DisplayModeControllerReady
        or not worldContextObject then
        return nil
    end

    if ownerKind ~= "Preset"
        and not GetDisplayModeInputConfig(
            Config
        ) then
        return nil
    end

    if DisplayModeControllerBridge then
        return DisplayModeControllerBridge
    end

    local bridge, bridgeError =
        CreateDisplayModeControllerBridge(
            worldContextObject,
            ownerKind,
            attachPanelOverride
        )

    if not bridge then

        DebugLog(
            "Standalone DisplayMode CommonUI bridge creation failed:",
            ownerKind or "<unknown>",
            bridgeError or "<unknown>"
        )

    end

    return bridge

end


------------------------------------------------
-- Pal Preset Reorder
------------------------------------------------
--
-- The Preset screen already owns the displayed CurrentLoadoutData copy, while
-- the persistent order is stored in UPalPlayerLocalRecordData.
--
-- Selection inputs:
--   * Middle Mouse Button on a Preset row.
--   * Gamepad Square / X through the unused Prev side of the existing hidden
--     WBP_BoxPalListBase CommonUI bridge.
--
-- The first selected row is dimmed until the second Preset is selected. The
-- same Preset selected twice cancels the pending swap.
------------------------------------------------

local function GetPresetSwapRow(
    presetScreen,
    index
)

    if not presetScreen
        or type(index) ~= "number"
        or index < 0 then
        return nil
    end

    local row = nil

    local ok =
        pcall(function()

            local scrollBox =
                presetScreen.ScrollBox_0

            if not scrollBox then
                return
            end

            row =
                scrollBox:GetChildAt(
                    index
                )

        end)

    if not ok
        or not row then
        return nil
    end

    local isPreset = false

    local okPreset =
        pcall(function()
            isPreset = row.IsPreset == true
        end)

    if not okPreset
        or not isPreset then
        return nil
    end

    return row

end


local function ResetPresetSwapSelection(
    presetScreen
)

    local selectedIndex =
        PresetSwapSelectedIndex

    local originalOpacity =
        PresetSwapSelectedOriginalOpacity

    PresetSwapSelectedIndex = nil
    PresetSwapSelectedOriginalOpacity = nil

    if not presetScreen
        or selectedIndex == nil then
        return
    end

    local row =
        GetPresetSwapRow(
            presetScreen,
            selectedIndex
        )

    if not row then
        return
    end

    pcall(function()
        row:SetRenderOpacity(
            originalOpacity or 1.0
        )
    end)

end


local function MarkPresetSwapSelection(
    presetScreen,
    index
)

    local row =
        GetPresetSwapRow(
            presetScreen,
            index
        )

    if not row then
        return false
    end

    local originalOpacity = 1.0

    pcall(function()
        originalOpacity =
            row:GetRenderOpacity()
    end)

    PresetSwapSelectedIndex = index
    PresetSwapSelectedOriginalOpacity =
        originalOpacity

    local ok =
        pcall(function()
            row:SetRenderOpacity(
                PRESET_SWAP_SELECTED_OPACITY
            )
        end)

    if not ok then

        PresetSwapSelectedIndex = nil
        PresetSwapSelectedOriginalOpacity = nil
        return false
    end

    DebugLog(
        "Preset reorder first selection:",
        index
    )

    return true

end


local function ResolvePresetSwapLocalRecordData(
    presetScreen
)

    if not presetScreen then
        return nil,
            "Preset screen is unavailable."
    end

    local palUtility = nil

    local okUtility, utilityResult =
        pcall(function()
            return StaticFindObject(
                PAL_UTILITY
            )
        end)

    if okUtility then
        palUtility = utilityResult
    end

    if not palUtility then
        return nil,
            "PalUtility is unavailable."
    end

    local playerState = nil

    local okPlayerState, playerStateResult =
        pcall(function()
            return palUtility:GetLocalPlayerState(
                presetScreen
            )
        end)

    if okPlayerState then
        playerState = playerStateResult
    end

    if not playerState then
        return nil,
            "Local PlayerState is unavailable."
    end

    local localRecordData = nil

    local okRecord, recordResult =
        pcall(function()
            return playerState:GetLocalRecordData()
        end)

    if okRecord then
        localRecordData = recordResult
    end

    if not localRecordData then
        return nil,
            "LocalRecordData is unavailable."
    end

    return localRecordData

end


local function SwapPresetOrder(
    presetScreen,
    indexA,
    indexB
)

    if not presetScreen
        or type(indexA) ~= "number"
        or type(indexB) ~= "number"
        or indexA < 0
        or indexB < 0
        or indexA == indexB then
        return false,
            "Invalid Preset indices."
    end

    local currentData = nil

    local okCurrent =
        pcall(function()
            currentData =
                presetScreen.CurrentLoadoutData
        end)

    if not okCurrent
        or not currentData then
        return false,
            "CurrentLoadoutData is unavailable."
    end

    local localRecordData, recordError =
        ResolvePresetSwapLocalRecordData(
            presetScreen
        )

    if not localRecordData then
        return false, recordError
    end

    local saveData = nil

    local okSaveData =
        pcall(function()
            saveData =
                localRecordData.Local_OtomoLoadoutSaveData
        end)

    if not okSaveData
        or not saveData then
        return false,
            "Local_OtomoLoadoutSaveData is unavailable."
    end

    local currentCount = nil
    local saveCount = nil

    local okCounts =
        pcall(function()
            currentCount = #currentData
            saveCount = #saveData
        end)

    if not okCounts
        or not currentCount
        or not saveCount then
        return false,
            "Preset array size is unavailable."
    end

    -- Blueprint preset indices are zero-based. UE4SS TArray indexing from Lua
    -- is one-based, matching the existing PalIconInfo Preset iteration code.
    local luaIndexA = indexA + 1
    local luaIndexB = indexB + 1

    if luaIndexA > currentCount
        or luaIndexB > currentCount
        or luaIndexA > saveCount
        or luaIndexB > saveCount then
        return false,
            "Preset index is outside the available data range."
    end

    ------------------------------------------------
    -- Preserve custom Preset names before the struct swap
    ------------------------------------------------
    --
    -- TArray<struct> assignment successfully swaps the registered Pal data on
    -- the current UE4SS build, but the FString PresetName may be lost. Read the
    -- two names before either array is modified, then reapply them after the
    -- data swap through the same native function used by the vanilla name edit
    -- screen.
    ------------------------------------------------

    local presetNameA = nil
    local presetNameB = nil

    local okNames, namesError =
        pcall(function()

            local dataA =
                currentData[luaIndexA]

            local dataB =
                currentData[luaIndexB]

            local okGetA, resolvedA =
                pcall(function()
                    return dataA:get()
                end)

            if okGetA
                and resolvedA then
                dataA = resolvedA
            end

            local okGetB, resolvedB =
                pcall(function()
                    return dataB:get()
                end)

            if okGetB
                and resolvedB then
                dataB = resolvedB
            end

            local rawNameA =
                dataA.PresetName

            local rawNameB =
                dataB.PresetName

            if rawNameA == nil then
                presetNameA = ""
            elseif type(rawNameA) == "string" then
                presetNameA = rawNameA
            else
                presetNameA = rawNameA:ToString()
            end

            if rawNameB == nil then
                presetNameB = ""
            elseif type(rawNameB) == "string" then
                presetNameB = rawNameB
            else
                presetNameB = rawNameB:ToString()
            end

        end)

    if not okNames then
        return false,
            "Preset name backup failed: "
            .. tostring(namesError)
    end

    ------------------------------------------------
    -- Commit the persistent pair first
    ------------------------------------------------
    --
    -- CurrentLoadoutData is still untouched here, so it provides the original
    -- A/B values for both writes and for rollback if the second write fails.
    ------------------------------------------------

    local okSaveA, saveAError =
        pcall(function()
            saveData[luaIndexA] =
                currentData[luaIndexB]
        end)

    if not okSaveA then
        return false,
            "LocalRecordData first write failed: "
            .. tostring(saveAError)
    end

    local okSaveB, saveBError =
        pcall(function()
            saveData[luaIndexB] =
                currentData[luaIndexA]
        end)

    if not okSaveB then

        local rollbackOk, rollbackError =
            pcall(function()
                saveData[luaIndexA] =
                    currentData[luaIndexA]
            end)

        if not rollbackOk then
            return false,
                "LocalRecordData second write failed and rollback failed: "
                .. tostring(saveBError)
                .. " / rollback: "
                .. tostring(rollbackError)
        end

        return false,
            "LocalRecordData second write failed: "
            .. tostring(saveBError)
    end

    ------------------------------------------------
    -- Synchronize the screen copy
    ------------------------------------------------
    --
    -- saveData now contains the complete swapped pair. If either screen write
    -- fails, restore both arrays to the original order using the still-available
    -- original value on the untouched side of CurrentLoadoutData.
    ------------------------------------------------

    local okCurrentA, currentAError =
        pcall(function()
            currentData[luaIndexA] =
                saveData[luaIndexA]
        end)

    if not okCurrentA then

        local rollbackOk, rollbackError =
            pcall(function()
                saveData[luaIndexA] =
                    currentData[luaIndexA]
                saveData[luaIndexB] =
                    currentData[luaIndexB]
            end)

        if not rollbackOk then
            return false,
                "CurrentLoadoutData first write failed and save rollback failed: "
                .. tostring(currentAError)
                .. " / rollback: "
                .. tostring(rollbackError)
        end

        return false,
            "CurrentLoadoutData first write failed: "
            .. tostring(currentAError)
    end

    local okCurrentB, currentBError =
        pcall(function()
            currentData[luaIndexB] =
                saveData[luaIndexB]
        end)

    if not okCurrentB then

        -- Current A is already swapped, while Current B still contains the
        -- original B value. saveData[B] contains the original A value.
        local rollbackOk, rollbackError =
            pcall(function()

                currentData[luaIndexA] =
                    saveData[luaIndexB]

                saveData[luaIndexA] =
                    currentData[luaIndexA]

                saveData[luaIndexB] =
                    currentData[luaIndexB]

            end)

        if not rollbackOk then
            return false,
                "CurrentLoadoutData second write failed and rollback failed: "
                .. tostring(currentBError)
                .. " / rollback: "
                .. tostring(rollbackError)
        end

        return false,
            "CurrentLoadoutData second write failed: "
            .. tostring(currentBError)
    end

    ------------------------------------------------
    -- Move the custom names with the swapped Preset data
    ------------------------------------------------

    local okNameA, nameAError =
        pcall(function()
            presetScreen:ChangeLoadoutPresetName(
                presetNameB,
                indexA
            )
        end)

    if not okNameA then
        return false,
            "Preset A name restore failed: "
            .. tostring(nameAError)
    end

    local okNameB, nameBError =
        pcall(function()
            presetScreen:ChangeLoadoutPresetName(
                presetNameA,
                indexB
            )
        end)

    if not okNameB then

        -- Restore A's original name before reporting the failure.
        pcall(function()
            presetScreen:ChangeLoadoutPresetName(
                presetNameA,
                indexA
            )
        end)

        return false,
            "Preset B name restore failed: "
            .. tostring(nameBError)
    end

    ------------------------------------------------
    -- Refresh only the two affected existing row Widgets
    ------------------------------------------------

    local rowA =
        GetPresetSwapRow(
            presetScreen,
            indexA
        )

    local rowB =
        GetPresetSwapRow(
            presetScreen,
            indexB
        )

    local okRefresh, refreshError =
        pcall(function()

            if rowA then
                presetScreen:SetupListWidget(
                    rowA,
                    true,
                    indexA
                )
            end

            if rowB then
                presetScreen:SetupListWidget(
                    rowB,
                    true,
                    indexB
                )
            end

        end)

    if not okRefresh then

        -- Data has already been committed successfully. Keep it and report only
        -- the visual refresh failure; reopening the Preset screen will rebuild
        -- the rows from the swapped data.
        Log(
            "Preset reorder row refresh failed:",
            tostring(refreshError)
        )

    end

    DebugLog(
        "Preset order swapped:",
        indexA,
        "<->",
        indexB
    )

    return true

end


local function HandlePresetSwapSelection(
    presetScreen,
    index
)

    if not presetScreen
        or type(index) ~= "number"
        or index < 0 then
        return
    end

    if not GetPresetSwapRow(
        presetScreen,
        index
    ) then
        return
    end

    local selectedIndex =
        PresetSwapSelectedIndex

    if selectedIndex == nil then

        MarkPresetSwapSelection(
            presetScreen,
            index
        )

        return
    end

    if selectedIndex == index then

        ResetPresetSwapSelection(
            presetScreen
        )

        DebugLog(
            "Preset reorder selection cancelled:",
            index
        )

        return
    end

    -- Remove the temporary selection visual before SetupListWidget refreshes
    -- either row.
    ResetPresetSwapSelection(
        presetScreen
    )

    local swapped, swapError =
        SwapPresetOrder(
            presetScreen,
            selectedIndex,
            index
        )

    if not swapped then

        Log(
            "Preset reorder failed:",
            swapError or "unknown error"
        )

    end

end

local function ResolveActivePresetSwapScreen()

    if DisplayModeControllerOwnerKind ~= "Preset"
        or not DisplayModeControllerOwnerName then
        return nil
    end

    local objectPath =
        DisplayModeControllerOwnerName:match(
            "^%S+%s+(.+)$"
        )

    if not objectPath then
        return nil
    end

    local presetScreen = nil

    local ok =
        pcall(function()
            presetScreen =
                StaticFindObject(
                    objectPath
                )
        end)

    if not ok
        or not presetScreen then
        return nil
    end

    if GetOuterClassName(
        presetScreen,
        0
    ) ~= "WBP_IngameMenu_PalBox_Preset_C" then
        return nil
    end

    return presetScreen

end



local function HandlePresetSwapMousePressed()

    local presetScreen =
        ResolveActivePresetSwapScreen()

    if not presetScreen then
        return
    end

    local index = nil

    local okIndex =
        pcall(function()
            index = tonumber(
                presetScreen.LastHoveredIndex
            )
        end)

    if not okIndex
        or index == nil
        or not GetPresetSwapRow(
            presetScreen,
            index
        ) then
        return
    end

    DebugLog(
        "Preset reorder Middle Mouse input:",
        index
    )

    HandlePresetSwapSelection(
        presetScreen,
        index
    )

end


local function RegisterPresetSwapMouseKey()

    -- Keep one persistent UE4SS key registration across MOD restarts. The
    -- callback resolves the current execution's handler through PalIconRuntime,
    -- matching the existing restart-safe DisplayMode hotkey pattern.
    PalIconRuntime.PresetSwapMouseHandler =
        HandlePresetSwapMousePressed

    if PalIconRuntime.PresetSwapMouseKeyRegistered then
        return
    end

    RegisterKeyBind(
        PRESET_SWAP_MOUSE_KEY_CODE,
        function()

            local handler =
                PalIconRuntime.PresetSwapMouseHandler

            if type(handler) == "function" then
                handler()
            end

        end
    )

    PalIconRuntime.PresetSwapMouseKeyRegistered = true

end


local function HandlePresetSwapCommonUIPressed(
    Context
)

    if DisplayModeControllerOwnerKind ~= "Preset"
        or not DisplayModeControllerBridgeName then
        return
    end

    local widget = nil

    local okContext =
        pcall(function()
            widget = Context:get()
        end)

    if not okContext
        or not widget then
        return
    end

    local fullName =
        GetDisplayModeObjectFullName(
            widget
        )

    if fullName ~=
        DisplayModeControllerBridgeName then
        return
    end

    local presetScreen =
        ResolveActivePresetSwapScreen()

    if not presetScreen then
        return
    end

    local index = nil

    local okIndex =
        pcall(function()
            index = tonumber(
                presetScreen.LastHoveredIndex
            )
        end)

    if not okIndex
        or index == nil then
        return
    end

    HandlePresetSwapSelection(
        presetScreen,
        index
    )

end


local function OnPresetSwapDelete(
    Context
)

    -- DeletePreset() is entered only after the vanilla confirmation flow has
    -- committed to deletion. Clear any pending first selection before the list
    -- indices are compacted by the native delete implementation.
    local presetScreen = nil

    local okContext =
        pcall(function()
            presetScreen = Context:get()
        end)

    if not okContext
        or not presetScreen then
        return
    end

    ResetPresetSwapSelection(
        presetScreen
    )

end


local function HandleDisplayModeControllerPressed(
    Context
)

    if not DisplayModeControllerBridgeName then
        return
    end

    local widget = nil

    local okContext =
        pcall(function()

            widget =
                Context:get()

        end)

    if not okContext
        or not widget then
        return
    end

    local fullName =
        GetDisplayModeObjectFullName(
            widget
        )

    if fullName
        ~= DisplayModeControllerBridgeName then

        -- The real PalBox and PalBoxPageSkip bridge use the same Blueprint
        -- callback. Only PalIconInfo's own hidden bridge is accepted.
        return
    end

    local controllerConfig =
        GetDisplayModeInputConfig(
            Config
        )

    if not controllerConfig then
        return
    end

    AdvanceDisplayModeState(
        controllerConfig.SourceKey,
        false
    )

end


local function OnDisplayModePalBoxSetMaxPageNum(
    Context,
    MaxPage
)

    local widget = nil

    local okContext =
        pcall(function()

            widget =
                Context:get()

        end)

    if not okContext
        or not widget then
        return
    end

    ------------------------------------------------
    -- Pool Host Validation
    ------------------------------------------------
    -- A previous OverallLayout can remain IsValid() briefly during fast-travel
    -- / UI reconstruction. Bind the Pool to the OverallLayout that actually
    -- owns this PalBox before its SlotUpdate sequence starts.
    if SHARED_OVERLAY_POOL_ENABLED
        and SharedOverlayPool.EnsureHostForWidget then

        SharedOverlayPool.EnsureHostForWidget(
            widget
        )

        SharedOverlayPool.CompactInvalidEntries(
            "PalBox setup"
        )

    end

    ------------------------------------------------
    -- Pre-Slot Resource Initialization
    ------------------------------------------------
    -- The normal PalBox open path reaches SetMaxPageNum while the paged list
    -- is being prepared, before its CharacterSlots begin their normal Setup /
    -- SlotUpdate sequence. Resolve all required resources here so the first
    -- SlotUpdate does not also pay the one-time ResourceReady cost.
    --
    -- Texture assets are preloaded and anchored before PalBox use whenever
    -- possible. This call completes the remaining DataTable/cache initialization
    -- before the normal SlotUpdate sequence begins.
    if not ResourceReady
        and PalIconRuntime.EnsureResourceReady then

        PalIconRuntime.EnsureResourceReady()

    end

    if not DisplayModeControllerReady then
        return
    end

    -- The real list belongs either to a normal PalBox or to one of the two
    -- standalone storage screens with an R3 conflict guide. Capture and update
    -- that guide before any bridge-lifetime early return below.
    CaptureVanillaR3GuideFromPalBoxBase(
        widget
    )

    if not GetDisplayModeInputConfig(
        Config
    ) then
        return
    end

    if DisplayModeControllerCreating
        or DisplayModeControllerDestroying
        or DisplayModeControllerBridge then
        return
    end

    local bridge, bridgeError =
        CreateDisplayModeControllerBridge(
            widget,
            "PalBox"
        )

    if not bridge then

        Log(
            "DisplayMode CommonUI bridge creation failed:",
            bridgeError or "<unknown>"
        )

    end

end


local function OnDisplayModePalBoxDestruct(
    Context
)

    local widget = nil

    local okContext =
        pcall(function()

            widget =
                Context:get()

        end)

    if not okContext
        or not widget then
        return
    end

    -- Pool cleanup must not depend on whether a CommonUI controller bridge
    -- exists. Reclaim any Entry owned by this BoxPalList before the Widget
    -- hierarchy disappears.
    if SHARED_OVERLAY_POOL_ENABLED
        and SharedOverlayPool.Ready then

        local scrollList = nil

        local okScroll, resultScroll =
            pcall(function()
                return widget.WBP_BoxPalScrollList
            end)

        if okScroll then
            scrollList = resultScroll
        end

        if scrollList then

            SharedOverlayPool.DiagnosticBoundaryBegin(
                "WBP_BoxPalListBase Destruct",
                scrollList
            )

            SharedOverlayPool.DeactivateLiveScrollOwner(
                scrollList,
                "WBP_BoxPalListBase Destruct"
            )

            SharedOverlayPool.ParkEntriesForScrollList(
                scrollList,
                "WBP_BoxPalListBase Destruct"
            )

            SharedOverlayPool.ClearWidgetModesForScrollList(
                scrollList,
                "WBP_BoxPalListBase Destruct",
                nil
            )

            SharedOverlayPool.DiagnosticBoundaryEnd(
                "WBP_BoxPalListBase Destruct",
                scrollList
            )

        end

    end

    if DisplayModeControllerDestroying
        or not DisplayModeControllerBridge then
        return
    end

    local fullName =
        GetDisplayModeObjectFullName(
            widget
        )

    if not fullName then
        return
    end

    -- Ignore our own hidden bridge and every unrelated WBP_BoxPalListBase.
    -- Only the real Base that created this bridge owns its lifetime.
    if fullName
        ~= DisplayModeControllerOwnerName then
        return
    end

    DestroyDisplayModeControllerBridge()

end


-- Create the Preset DisplayMode bridge only after the top-level Preset screen
-- has completed OnSetup. SetupPreset is a data-population event and can run
-- before the screen becomes the active CommonUI owner, so it is intentionally
-- not used as the bridge lifetime event.
local function OnDisplayModePresetSetup(
    Context
)

    if not DisplayModeControllerReady then
        return
    end

    local widget = nil

    local okContext =
        pcall(function()

            widget =
                Context:get()

        end)

    if not okContext
        or not widget then
        return
    end

    DebugLog(
        "[PresetSafety] Preset OnSetup begin"
    )

    -- Preset is a separate UI subtree and can be created while the previous
    -- PalBox tree is still being torn down. Revalidate the persistent Pool host
    -- here as well as in each SetupPreset row, then drop any already-invalid
    -- Entry records accumulated during earlier menu transitions.
    if SHARED_OVERLAY_POOL_ENABLED
        and SharedOverlayPool.EnsureHostForWidget then

        SharedOverlayPool.EnsureHostForWidget(
            widget
        )

        SharedOverlayPool.CompactInvalidEntries(
            "Preset setup"
        )

        DebugLog(
            "[PresetSafety] Pool checked / entries =",
            #SharedOverlayPool.Entries
        )

    end

    ResetPresetSwapSelection(
        widget
    )

    local ownerName =
        GetDisplayModeObjectFullName(
            widget
        )

    if DisplayModeControllerBridge then

        if DisplayModeControllerOwnerKind == "Preset"
            and DisplayModeControllerOwnerName == ownerName then
            return
        end

        -- Preserve only the transient path of the real PalBox list before
        -- replacing its bridge with the Preset-screen bridge. SetMaxPageNum()
        -- is not called again merely by returning from Preset, so this path is
        -- used to rebuild the PalBox bridge after Preset Destruct.
        if DisplayModeControllerOwnerKind == "PalBox"
            and DisplayModeControllerOwnerName then

            DisplayModePresetReturnPalBoxPath =
                DisplayModeControllerOwnerName:match(
                    "^%S+%s+(.+)$"
                )

            DebugLog(
                "Saved PalBox path for Preset return:",
                DisplayModePresetReturnPalBoxPath or "<unavailable>"
            )

        end

        DebugLog(
            "[PresetSafety] Releasing previous DisplayMode bridge"
        )

        DestroyDisplayModeControllerBridge()

        DebugLog(
            "[PresetSafety] Previous DisplayMode bridge released"
        )

    end

    local attachPanel = nil

    local okPanel =
        pcall(function()

            attachPanel =
                widget.Canvas_MenuGuide

            -- Verify that UE4SS resolved the Blueprint property as a real
            -- PanelWidget before using it as the bridge attachment point.
            attachPanel:GetChildrenCount()

        end)

    if not okPanel
        or not attachPanel then

        Log(
            "Preset DisplayMode attach panel is unavailable."
        )

        return
    end

    local bridge, bridgeError =
        CreateDisplayModeControllerBridge(
            widget,
            "Preset",
            attachPanel
        )

    if bridge then

        DebugLog(
            "[PresetSafety] Preset DisplayMode bridge created"
        )

        DebugLog(
            "Preset DisplayMode CommonUI bridge created"
        )

    else

        Log(
            "Preset DisplayMode CommonUI bridge creation failed:",
            bridgeError or "<unknown>"
        )

    end

end


-- The top-level Preset screen has an explicit Destruct event, so use it as
-- the deterministic cleanup point. No global UserWidget:Destruct Hook is used.
local function OnDisplayModePresetDestruct(
    Context
)

    if PresetOverlayBinding
        and PresetOverlayBinding.Enabled then

        local retireSequence =
            SharedOverlayPool.BeginRetireLifetime(
                "WBP_IngameMenu_PalBox_Preset Destruct"
            )

        PresetOverlayBinding.ParkAll(
            "WBP_IngameMenu_PalBox_Preset Destruct",
            retireSequence
        )

        SharedOverlayPool.MarkRetireCleanupReturned(
            retireSequence
        )

    end

    if DisplayModeControllerOwnerKind ~= "Preset"
        or not DisplayModeControllerOwnerName then
        return
    end

    local widget = nil

    local okContext =
        pcall(function()

            widget =
                Context:get()

        end)

    if not okContext
        or not widget then
        return
    end

    local fullName =
        GetDisplayModeObjectFullName(
            widget
        )

    if fullName
        ~= DisplayModeControllerOwnerName then
        return
    end

    ResetPresetSwapSelection(
        widget
    )

    DestroyDisplayModeControllerBridge()

    DebugLog(
        "Preset DisplayMode CommonUI bridge destroyed"
    )

    local returnPalBoxPath =
        DisplayModePresetReturnPalBoxPath

    DisplayModePresetReturnPalBoxPath = nil

    if not returnPalBoxPath then
        return
    end

    -- The Preset screen is destroyed just before control is returned to the
    -- underlying PalBox. Wait briefly so its visibility has been restored,
    -- then reacquire the exact previous PalBox list from its transient path.
    -- No live real PalBox UObject is retained across the screen transition.
    ExecuteWithDelay(
        100,
        function()

            if not IsCurrentRuntimeGeneration() then
                return
            end

            ExecuteInGameThread(
                function()

                    if not IsCurrentRuntimeGeneration() then
                        return
                    end

                    if not DisplayModeControllerReady
                        or DisplayModeControllerBridge then
                        return
                    end

                    if not GetDisplayModeInputConfig(
                        Config
                    ) then
                        return
                    end

                    local palBoxList = nil

                    local okResolve =
                        pcall(function()

                            palBoxList =
                                StaticFindObject(
                                    returnPalBoxPath
                                )

                        end)

                    if not okResolve
                        or not palBoxList then

                        DebugLog(
                            "PalBox DisplayMode bridge restore skipped: previous PalBox unavailable"
                        )

                        return
                    end

                    local visible = false

                    local okVisible =
                        pcall(function()

                            visible =
                                palBoxList:IsVisible()

                        end)

                    if not okVisible
                        or visible ~= true then

                        DebugLog(
                            "PalBox DisplayMode bridge restore skipped: previous PalBox not visible"
                        )

                        return
                    end

                    local bridge, bridgeError =
                        CreateDisplayModeControllerBridge(
                            palBoxList,
                            "PalBox"
                        )

                    if bridge then

                        DebugLog(
                            "PalBox DisplayMode CommonUI bridge restored after Preset"
                        )

                    else

                        Log(
                            "PalBox DisplayMode bridge restore after Preset failed:",
                            bridgeError or "<unknown>"
                        )

                    end

                end
            )

        end
    )

end


-- The hatch-result parent provides an explicit OnClose event, so use it as a
-- deterministic cleanup point rather than relying only on child destruction.
local function OnDisplayModeHatchResultClose()

    if DisplayModeControllerOwnerKind
        ~= "Hatch" then
        return
    end

    DestroyDisplayModeControllerBridge()

end



local function InitializeDisplayModeController()

    local controllerConfig =
        GetDisplayModeInputConfig(
            Config
        )

    -- Initialize the native bridge infrastructure even without a configured
    -- DisplayMode Gamepad input because the Preset reorder feature uses the
    -- same safe Blueprint-native CommonUI path for Square / X.
    ExecuteInGameThread(
        function()

            if not IsCurrentRuntimeGeneration() then
                return
            end

            local okLoad, loadError =
                pcall(function()

                    LoadAsset(
                        PAL_BOX_LIST_BASE_ASSET
                    )

                    LoadAsset(
                        PRESET_SWAP_LIST_ASSET
                    )

                end)

            if not okLoad then

                Log(
                    "DisplayMode controller asset preload failed:",
                    loadError
                )

                return
            end

            if not GetDisplayModeBoxPalListBaseClass() then

                Log(
                    "DisplayMode controller class unavailable"
                )

                return
            end

            -- Destruct also owns Normal Overlay Pool cleanup, so register
            -- it before optional CommonUI controller initialization.
            SafeRegisterHook(
                DISPLAY_MODE_HOOK_DESTRUCT,
                OnDisplayModePalBoxDestruct
            )

            SafeRegisterHook(
                DISPLAY_MODE_HOOK_PRESET_DESTRUCT,
                OnDisplayModePresetDestruct
            )

            local controllerReady,
                controllerError =
                ControllerInput.Initialize()

            if not controllerReady then

                Log(
                    "ControllerInput initialization failed:",
                    controllerError
                )

                return
            end

            -- WBP_BoxPalListBase is loaded above so the bridge input UFunctions
            -- are available before the controller hooks are registered.
            SafeRegisterHook(
                DISPLAY_MODE_HOOK_PRESSED,
                HandleDisplayModeControllerPressed
            )

            SafeRegisterHook(
                PRESET_SWAP_HOOK_PRESSED,
                HandlePresetSwapCommonUIPressed
            )

            SafeRegisterHook(
                PRESET_SWAP_HOOK_DELETE,
                OnPresetSwapDelete
            )

            SafeRegisterHook(
                DISPLAY_MODE_HOOK_SET_MAX_PAGE,
                OnDisplayModePalBoxSetMaxPageNum
            )

            SafeRegisterHook(
                DISPLAY_MODE_HOOK_PRESET_SETUP,
                OnDisplayModePresetSetup
            )

            DisplayModeControllerReady = true

            DebugLog(
                "CommonUI controller bridge infrastructure initialized:",
                "DisplayMode =",
                controllerConfig ~= nil,
                "Button =",
                controllerConfig and controllerConfig.Button or "<disabled>",
                "FKey =",
                controllerConfig and controllerConfig.GamepadKey or "None"
            )

        end
    )

end


------------------------------------------------
-- Hook Registration
------------------------------------------------
-- Monitor game-side events and connect Slot state changes
-- to Overlay updates.
--
-- Overlay-data Hooks obtain SaveParameter using the route specific to each
-- target. Other Hooks in this section handle visibility, cleanup, equipment
-- state, or optional refresh behavior. UpdateSlotOverlay() remains the shared
-- data-to-UI path for targets that provide Pal data.
--
-- The primary Overlay-data lifecycle events are summarized below. Additional
-- screen-specific and state hooks are documented next to their registrations.
--
-- SlotUpdate
--   Fired when a normal Pal icon is updated.
--   Detects Pal replacement and display-content updates,
--   then updates the Overlay contents from SaveParameter.
--
-- SetupPreset
--   Fired when PalBox preset contents are configured.
--   The SaveParameter obtained here is not for the Pal
--   currently in a normal Pal Slot.
--   It is the SaveParameter of the "Pal registered in the preset."
--   Because Preset Slots have a different data structure from normal Slots,
--   SaveParameter for each preset entry is obtained from LoadoutData
--   and the Overlay is displayed on the corresponding CharacterSlot.
--
-- SlotEmpty
--   Fired when a Pal Slot becomes empty.
--   Clears the Overlay Widget contents so that a previously displayed
--   Overlay does not remain visible.
------------------------------------------------


------------------------------------------------
-- Resource Initialization
------------------------------------------------
-- Ensure all assets and caches required by Overlay processing are ready.
--
-- SlotUpdate used to own this initialization directly. Hatch-result entries
-- can be displayed before a normal PalBox SlotUpdate occurs, so initialization
-- is shared by every Hook that can be the first Overlay entry point.
local function EnsureResourceReady()

    if ResourceReady then
        return true
    end

    if not LoadRequiredObjects() then
        return false
    end

    ResourceReady = true

    Log("Resource Ready")

    BuildPalpediaCache()
    BuildPassiveSkillCache()
    BuildFriendshipRankCache()

    -- Startup-prewarmed Pool Entries already have static layout/font/color.
    -- When pre-open initialization succeeded, their Image brushes are already
    -- initialized; these calls are idempotent fallbacks for partial preload.
    if SharedOverlayPool
        and SharedOverlayPool.InitializeStaticTexturesAllEntries then

        SharedOverlayPool.InitializeStaticTexturesAllEntries()

    end

    if PartyOverlayPool
        and PartyOverlayPool.InitializeStaticTexturesAllEntries then

        PartyOverlayPool.InitializeStaticTexturesAllEntries()

    end

    -- Rescue only normal Slots whose earlier SlotUpdate returned while
    -- resources were unavailable.
    if PalIconRuntime.NormalSlotsMissedBeforeResourceReady then

        InitializeExistingSlots()

        PalIconRuntime.NormalSlotsMissedBeforeResourceReady = false

    end

    ApplyDisplayMode()

    ConfigWatchLoop()

    return true

end

-- OnDisplayModePalBoxSetMaxPageNum() is defined earlier because it also owns
-- the CommonUI bridge lifecycle. Publish the completed initializer through the
-- restart-scoped runtime table so that callback can invoke it without a main-
-- chunk local forward declaration.
PalIconRuntime.EnsureResourceReady =
    EnsureResourceReady


------------------------------------------------
-- SafeRegisterHook
------------------------------------------------
--
-- RegisterHook() requires the target UFunction to already exist in memory.
-- Blueprint UFunctions may still be unloaded when this script starts.
--
-- First try to register normally. If a /Game/ Blueprint target is missing,
-- derive its asset path from the UFunction path and schedule one game-thread
-- fallback that loads the Blueprint and retries registration once.
--
-- This avoids the previous one-second retry loop, which could otherwise keep
-- running indefinitely for optional screens that were never opened.
------------------------------------------------

SafeRegisterHook = function(target, func, postFunc)

    ------------------------------------------------
    -- Persistent dispatcher
    ------------------------------------------------
    --
    -- The native Hook wrapper must NOT capture func/postFunc directly.
    -- UE4SS may retain a Hook callback after MOD restart even when
    -- UnregisterHook() was requested. Capturing the execution-local callback
    -- here would keep its Overlay Pool / Widget UObject upvalues alive.
    --
    -- Instead, the wrapper captures only the target string and generation.
    -- The real callbacks live in the restart-safe Runtime dispatcher table,
    -- which is cleared before old cleanup begins.
    ------------------------------------------------

    local hookGeneration =
        RuntimeGeneration

    local existingHook =
        PalIconRuntime.Hooks[target]

    if type(existingHook) == "table"
        and existingHook.Active ~= false
        and type(existingHook.PreId) == "number"
        and type(existingHook.PostId) == "number" then

        PalIconRuntime.Dispatchers[target] = {
            Generation = hookGeneration,
            Pre = func,
            Post = postFunc,
        }

        return true
    end

    PalIconRuntime.Dispatchers[
        target
    ] = {
        Generation = hookGeneration,
        Pre = func,
        Post = postFunc,
    }

    local guardedFunc = function(...)

        if PalIconRuntime.Generation
            ~= hookGeneration then
            return
        end

        local dispatchers =
            PalIconRuntime.Dispatchers

        local dispatcher =
            type(dispatchers) == "table"
            and dispatchers[target]
            or nil

        if type(dispatcher) ~= "table"
            or dispatcher.Generation ~= hookGeneration then
            return
        end

        local callback =
            dispatcher.Pre

        if type(callback) == "function" then
            return callback(...)
        end

    end

    local guardedPostFunc = nil

    if postFunc then

        guardedPostFunc = function(...)

            if PalIconRuntime.Generation
                ~= hookGeneration then
                return
            end

            local dispatchers =
                PalIconRuntime.Dispatchers

            local dispatcher =
                type(dispatchers) == "table"
                and dispatchers[target]
                or nil

            if type(dispatcher) ~= "table"
                or dispatcher.Generation ~= hookGeneration then
                return
            end

            local callback =
                dispatcher.Post

            if type(callback) == "function" then
                return callback(...)
            end

        end

    end

    local function StoreHook(
        preId,
        postId
    )

        if type(preId) ~= "number"
            or type(postId) ~= "number" then
            return false,
                "RegisterHook returned invalid hook IDs."
        end

        local hookRecord = {
            Target = target,
            PreId = preId,
            PostId = postId,
            Active = true,
        }

        PalIconRuntime.Hooks[
            target
        ] = hookRecord

        table.insert(
            PalIconRuntime.HookHistory,
            hookRecord
        )

        return true

    end

    local function TryRegister()

        local ok, preId, postId =
            pcall(function()

                if postFunc then

                    return RegisterHook(
                        target,
                        guardedFunc,
                        guardedPostFunc
                    )

                end

                return RegisterHook(
                    target,
                    guardedFunc
                )

            end)

        if not ok then
            return false, preId
        end

        return StoreHook(
            preId,
            postId
        )

    end

    local ok, result =
        TryRegister()

    if ok then
        return true
    end

    ------------------------------------------------
    -- One-time Blueprint preload fallback
    ------------------------------------------------

    local assetPath =
        type(target) == "string"
        and target:match(
            "^(/Game/.+)%.[^:]+:"
        )
        or nil

    if not assetPath then

        PalIconRuntime.Dispatchers[
            target
        ] = nil

        Log(
            "Hook Registration Failed:",
            target,
            result
        )

        return false, result
    end

    ExecuteInGameThread(
        function()

            if not IsCurrentRuntimeGeneration() then
                return
            end

            local okLoad, loadError =
                pcall(function()
                    LoadAsset(assetPath)
                end)

            if not okLoad then

                PalIconRuntime.Dispatchers[
                    target
                ] = nil

                Log(
                    "Hook target Blueprint preload failed:",
                    assetPath,
                    loadError
                )

                return
            end

            local retryOk, retryError =
                TryRegister()

            if not retryOk then

                PalIconRuntime.Dispatchers[
                    target
                ] = nil

                Log(
                    "Hook Registration Failed after Blueprint preload:",
                    target,
                    retryError
                )

            end

        end
    )

    return true

end


------------------------------------------------
-- Normal Overlay Persistent Pool Hooks
------------------------------------------------
--
-- /Game/ Blueprint RegisterHook callbacks run after the Blueprint function.
--
-- AddSlotButtonToScrollList:
--   SlotUpdate may already have attached the pooled Entry while the Button was
--   being set up. Once Palworld adds that Button to the ScrollList, associate
--   the Entry with the owning ScrollList for the next rebuild.
--
-- ClearInnnerChildren:
--   Runs after the current WrapBox children were removed, but before
--   SetCharacterSlots continues to AddCharacterSlots(). Park Entries owned by
--   that ScrollList so they can be reused by the newly generated Slots.
--
-- WBP_BoxPalListBase:Destruct is already part of the existing DisplayMode
-- lifecycle. Pool parking is folded into that callback to avoid registering
-- the same Blueprint UFunction twice in PalIconInfo's restart-safe Hook table.
if SHARED_OVERLAY_POOL_ENABLED then

    -- Condensation Party lifecycle verified from Blueprint JSON.
    --
    -- WBP_IngameMenu_PalCondense::Setup:
    --   PartyPalSlots[i]
    --     -> PalOtomoHolderComponentBase:GetSlots()[i]
    --     -> WBP_PalCommonCharacterSlotButton::Setup(targetSlot)
    --   ... repeated for the static PartyPalSlots ...
    --   -> Update Simulation      (loop-completed path)
    --
    -- Normal PalBox Party slots are a different UI type
    -- (WBP_IngameMenu_PalBox_PalList_C) and continue to use targetType=Party
    -- plus PartyOverlayPool. Condensation Party slots use
    -- WBP_PalCommonCharacterSlotButton_C -> WBP_PalCommonCharacterSlot_C, so
    -- they use the shared Normal-layout Pool but a distinct poolKind
    -- "CondenseParty". Do not conflate the two because both are called Party.

    local PendingCondensePartyAttachByHostAddress = {}

    -- Return the exact WBP_IngameMenu_PalCondense owner only for the fixed
    -- Outer chain proven by the Blueprint:
    --   CommonCharacterSlotButton
    --     -> WidgetTree
    --     -> WBP_BoxPalList_Party
    --     -> WidgetTree
    --     -> WBP_IngameMenu_PalCondense
    --
    -- No GetFullName() scan is used for eligibility.
    local function GetPalCondenseHostForPartySlotButton(slotButton)

        if not SharedOverlayPool.IsValidObject(slotButton) then
            return nil
        end

        local condenseHost = nil

        pcall(function()

            local buttonTree = slotButton:GetOuter()
            if not SharedOverlayPool.IsValidObject(buttonTree) then
                return
            end

            local partyHost = buttonTree:GetOuter()
            if not SharedOverlayPool.IsValidObject(partyHost) then
                return
            end

            local partyClass = partyHost:GetClass()
            local partyClassName =
                partyClass
                and partyClass:GetFName()
                and partyClass:GetFName():ToString()
                or nil

            if partyClassName ~= "WBP_BoxPalList_Party_C" then
                return
            end

            local partyTree = partyHost:GetOuter()
            if not SharedOverlayPool.IsValidObject(partyTree) then
                return
            end

            local candidate = partyTree:GetOuter()
            if not SharedOverlayPool.IsValidObject(candidate) then
                return
            end

            local condenseClass = candidate:GetClass()
            local condenseClassName =
                condenseClass
                and condenseClass:GetFName()
                and condenseClass:GetFName():ToString()
                or nil

            if condenseClassName == "WBP_IngameMenu_PalCondense_C" then
                condenseHost = candidate
            end

        end)

        return condenseHost

    end

    local function IsPalCondensePartySlotButton(slotButton)
        return GetPalCondenseHostForPartySlotButton(slotButton) ~= nil
    end

    local function AttachPalCondensePartyAfterSetup(slotButton, source)

        if source ~= "Setup"
            or not IsPalCondensePartySlotButton(slotButton) then
            return
        end

        SharedOverlayPool.DiagnosticPalCondensePartySetupAttachAttempt =
            (SharedOverlayPool.DiagnosticPalCondensePartySetupAttachAttempt or 0) + 1

        local slotButtonAddress = SharedOverlayPool.GetAddress(slotButton)
        local commonRecord =
            slotButtonAddress
            and SharedOverlayPool.LiveCommonSlotByButtonAddress[slotButtonAddress]
            or nil

        if type(commonRecord) ~= "table"
            or commonRecord.Retiring == true then
            return
        end

        local characterSlotWidget = nil
        local targetSlot = nil

        pcall(function()
            characterSlotWidget = slotButton.MyCharacterSlotWidget
        end)

        -- GetTargetSlot exposes targetSlot as an OutParm. The verified
        -- WBP_PalCharacterSlotBase::Setup Blueprint stores newTargetSlot in
        -- MyCharacterSlotWidget.targetSlot before BindEvents, so read the
        -- stored property directly at this verified Setup boundary.
        if SharedOverlayPool.IsValidObject(characterSlotWidget) then
            pcall(function()
                targetSlot = characterSlotWidget.targetSlot
            end)
        end

        if not SharedOverlayPool.IsValidObject(characterSlotWidget)
            or not SharedOverlayPool.IsValidObject(targetSlot) then
            return
        end

        local okEmpty, isEmpty = pcall(function()
            return targetSlot:IsEmpty()
        end)

        if not okEmpty then
            return
        end

        if isEmpty then
            SharedOverlayPool.DiagnosticPalCondensePartySetupAttachEmpty =
                (SharedOverlayPool.DiagnosticPalCondensePartySetupAttachEmpty or 0) + 1

            ClearSlotOverlay(characterSlotWidget, "Normal", "CondenseParty")
            return
        end

        if not EnsureResourceReady() then
            return
        end

        local handle = nil
        local parameter = nil
        local save = nil

        pcall(function()
            handle = targetSlot:GetHandle()
        end)

        if handle then
            pcall(function()
                parameter = handle:TryGetIndividualParameter()
            end)
        end

        if parameter then
            pcall(function()
                save = parameter.SaveParameter
            end)
        end

        if not save then
            SharedOverlayPool.DiagnosticPalCondensePartySetupAttachNoSave =
                (SharedOverlayPool.DiagnosticPalCondensePartySetupAttachNoSave or 0) + 1
            return
        end

        UpdateSlotOverlay(
            characterSlotWidget,
            save,
            "Normal",          -- UI layout: WBP_PalCommonCharacterSlot_C
            true,
            true,
            "CondenseParty",   -- lifecycle/source kind, NOT normal PalBox Party
            commonRecord.WidgetAddress
        )

        local entry = SharedOverlayPool.GetEntryForWidget(
            characterSlotWidget,
            commonRecord.WidgetAddress
        )

        -- An Entry may already be bound before the Condense Setup boundary.
        -- In that case AcquireEntry() returns the existing Entry without
        -- re-running AttachEntry(), so adopt the exact positive Common Button
        -- identity here. Never overwrite a stronger owner.
        if entry
            and type(commonRecord) == "table"
            and commonRecord.IsScrollList == false
            and commonRecord.Retiring ~= true
            and commonRecord.SlotButtonAddress ~= nil
            and entry.OwnerCommonSlotButtonAddress == nil
            and entry.OwnerScrollListAddress == nil
            and entry.OwnerPresetRowAddress == nil then

            entry.OwnerCommonSlotButtonAddress =
                commonRecord.SlotButtonAddress

            entry.DiagnosticState = "AttachedCommonButton"
            entry.DiagnosticLastTransition =
                "CondensePartyBoundaryAdoptCommonOwner"

            SharedOverlayPool.DiagnosticCommonOwnedEntryAttached =
                (SharedOverlayPool.DiagnosticCommonOwnedEntryAttached or 0) + 1

        end

        if entry
            and entry.OwnerCommonSlotButtonAddress == commonRecord.SlotButtonAddress then

            entry.TargetKind = "CondenseParty"

            SharedOverlayPool.DiagnosticPalCondensePartySetupAttachSuccess =
                (SharedOverlayPool.DiagnosticPalCondensePartySetupAttachSuccess or 0) + 1
        end

    end

    local commonSetupHooks = {
        { HookTarget.CharacterSlotButtonBaseSetup, "Setup" },
        { HookTarget.CharacterSlotButtonBaseSetupByCharacterID, "SetupByCharacterID" },
        { HookTarget.CharacterSlotButtonBaseSetupByIndividualId, "SetupByIndividualId" },
        { HookTarget.CharacterSlotButtonBaseSetupBySaveParameter, "SetupBySaveParameter" },
    }

    for _, setupHook in ipairs(commonSetupHooks) do

        SafeRegisterHook(
            setupHook[1],
            function(Context)

                local slotButton = nil
                pcall(function()
                    slotButton = Context:get()
                end)

                SharedOverlayPool.RegisterLiveCommonSlotButton(
                    slotButton,
                    setupHook[2]
                )

                -- WBP_IngameMenu_PalCondense::Setup loops PartyPalSlots and
                -- calls Button::Setup(targetSlot) once for each element. The
                -- existing Common Setup hook therefore provides the completion
                -- boundary without a separate PalCondense-specific hook.
                if setupHook[2] == "Setup" then

                    local condenseHost =
                        GetPalCondenseHostForPartySlotButton(slotButton)

                    local hostAddress =
                        condenseHost
                        and SharedOverlayPool.GetAddress(condenseHost)
                        or nil

                    if hostAddress then

                        local pending =
                            PendingCondensePartyAttachByHostAddress[hostAddress]

                        if type(pending) ~= "table" then
                            pending = {
                                Host = condenseHost,
                                SetupCount = 0,
                            }
                            PendingCondensePartyAttachByHostAddress[hostAddress] = pending
                        end

                        pending.Host = condenseHost
                        pending.SetupCount = (pending.SetupCount or 0) + 1

                        local partySlots = nil
                        local slotCount = 0

                        pcall(function()
                            partySlots = condenseHost.PartyPalSlots
                        end)

                        if partySlots then
                            pcall(function()
                                slotCount = #partySlots
                            end)
                        end

                        if slotCount > 0
                            and pending.SetupCount >= slotCount then

                            PendingCondensePartyAttachByHostAddress[hostAddress] = nil

                            if DEBUG then
                                Log(
                                    "[PoolCondenseParty] Setup-count boundary / slots =",
                                    slotCount,
                                    "/ setupCount =",
                                    pending.SetupCount or 0
                                )
                            end

                            for i = 1, slotCount do

                                local partySlotButton = nil
                                pcall(function()
                                    partySlotButton = partySlots[i]
                                end)

                                AttachPalCondensePartyAfterSetup(
                                    partySlotButton,
                                    "Setup"
                                )

                            end

                        end

                    end

                end

            end
        )

    end

    -- use Common SlotButton Destruct to remove live ScrollList records;
    -- retain ordering diagnostics when DEBUG is enabled.
    -- without changing Pool ownership or retirement behavior.
    SafeRegisterHook(
        HookTarget.CommonCharacterSlotButtonDestruct,
        function(Context)

            local slotButton = nil

            pcall(function()
                slotButton = Context:get()
            end)

            SharedOverlayPool.RemoveLiveScrollSlotButton(
                slotButton,
                "Destruct"
            )

            -- reclaim a Shared Entry owned by this exact Common
            -- Button. RegisterHook observes the Blueprint Destruct callback
            -- after the Blueprint event itself, so a late inner SlotUpdate can
            -- still occur afterward. Do not discard a non-ScrollList Common
            -- record at this point unless it was already retiring through a
            -- stronger owner lifecycle (Preset). Instead retain the exact
            -- Button identity as Retiring until the next Setup* reactivates it.
            SharedOverlayPool.ParkEntryForCommonSlotButton(
                slotButton,
                "Common SlotButton Destruct"
            )

            local slotButtonAddress =
                SharedOverlayPool.GetAddress(slotButton)

            local commonRecord =
                slotButtonAddress
                and SharedOverlayPool.LiveCommonSlotByButtonAddress[
                    slotButtonAddress
                ]
                or nil

            if type(commonRecord) == "table"
                and commonRecord.IsScrollList == false
                and commonRecord.Retiring ~= true
                and commonRecord.WidgetAddress ~= nil then

                if SharedOverlayPool.MarkLiveCommonSlotRetiring(
                    commonRecord.WidgetAddress,
                    "Common SlotButton Destruct",
                    nil
                ) then

                    if DEBUG then
                        SharedOverlayPool.DiagnosticCommonPostDestructRetained =
                            (SharedOverlayPool.DiagnosticCommonPostDestructRetained or 0) + 1
                    end

                end

            else

                SharedOverlayPool.RemoveLiveCommonSlotButton(
                    slotButton
                )

            end

            SharedOverlayPool.RecordSlotButtonDestruct(
                slotButton
            )

        end
    )

    -- Preclassify each Slot Widget before SlotButton:Setup() triggers
    -- SlotUpdate. In particular, BaseCamp and other auxiliary ScrollLists are
    -- marked non-persistent before the Normal SlotUpdate path can AcquireEntry().
    SafeRegisterHook(
        HookTarget.PalCharacterScrollListBindButtonEvents,
        function(Context, createdSlotButton)

            local scrollList = nil
            local slotButton = nil

            local okContext, resultContext =
                pcall(function()
                    return Context:get()
                end)

            if okContext then
                scrollList = resultContext
            end

            local okButton, resultButton =
                pcall(function()
                    return createdSlotButton:get()
                end)

            if okButton then
                slotButton = resultButton
            end

            SharedOverlayPool.PreclassifySlotButton(
                scrollList,
                slotButton
            )

        end
    )

    SafeRegisterHook(
        HookTarget.PalCharacterScrollListAddSlotButton,
        function(Context, createdSlotButton)

            local scrollList = nil
            local slotButton = nil

            local okContext, resultContext =
                pcall(function()
                    return Context:get()
                end)

            if okContext then
                scrollList = resultContext
            end

            local okButton, resultButton =
                pcall(function()
                    return createdSlotButton:get()
                end)

            if okButton then
                slotButton = resultButton
            end

            SharedOverlayPool.BindEntryToScrollList(
                scrollList,
                slotButton
            )

        end
    )

    SafeRegisterHook(
        HookTarget.PalCharacterScrollListClearInnerChildren,
        function(Context)

            local scrollList = nil

            local okContext, resultContext =
                pcall(function()
                    return Context:get()
                end)

            if okContext then
                scrollList = resultContext
            end

            if scrollList then

                SharedOverlayPool.DiagnosticBoundaryBegin(
                    "ClearInnnerChildren",
                    scrollList
                )

                -- invalidate the current owner generation first.
                -- Records for still-alive Buttons remain until their Destruct,
                -- but they immediately become ineligible for Pool acquisition
                -- even if the Button still has a valid Parent.
                SharedOverlayPool.DeactivateLiveScrollOwner(
                    scrollList,
                    "ClearInnnerChildren"
                )

                SharedOverlayPool.ParkEntriesForScrollList(
                    scrollList,
                    "ClearInnnerChildren"
                )

                SharedOverlayPool.ClearWidgetModesForScrollList(
                    scrollList,
                    "ClearInnnerChildren",
                    nil
                )

                SharedOverlayPool.DiagnosticBoundaryEnd(
                    "ClearInnnerChildren",
                    scrollList
                )


            end

        end
    )

    -- Start a short-lived lookup retry. It stops permanently as soon as the
    -- persistent OverallUILayout instance has been found and the persistent
    -- Pool host has been created. The complete 80-Entry shared Normal/Preset
    -- startup target is then generated immediately. No OverallUILayout Blueprint
    -- Hook is used.
    SharedOverlayPool.Initialize()
    PartyOverlayPool.Initialize()

end


------------------------------------------------
-- Slot Update Hook
------------------------------------------------
--
-- Fired when a normal Pal Slot is updated.
--
-- SaveParameter retrieval is separated from Overlay processing so the data
-- access route can be changed independently of the subsequent UI update path.
--
-- Two SaveParameter retrieval routes are currently available:
--
-- Route 1:
--   Slot
--     ↓ ReplicateIndividualParameter
--   SaveParameter
--
-- Route 2:
--   Slot
--     ↓ GetHandle()
--     ↓ TryGetIndividualParameter()
--   SaveParameter
--
-- SlotUpdate currently uses the Handle Route.
--
-- SlotUpdate can also be triggered by Widgets on the Preset screen.
-- Preset Slots use a different data structure and cannot obtain
-- SaveParameter through these normal Slot retrieval routes.
-- Therefore, Preset screen calls are excluded here and handled
-- separately by the SetupPreset Hook.

------------------------------------------------
-- SaveParameter Retrieval: Replicate Route
------------------------------------------------

-- Obtain SaveParameter from ReplicateIndividualParameter
-- of a normal Pal Slot.
--
-- The retrieval route is:
--
--   Slot
--     ↓ ReplicateIndividualParameter
--   SaveParameter
--
-- This function is responsible only for retrieving SaveParameter.
-- It does not perform any Overlay processing.
--
-- Normal SlotUpdate currently uses GetSaveParameter_Handle(), while
-- Party Pal Slot updates use this Replicate route.
local function GetSaveParameter_Replicate(slot)

    if not slot then
        return nil
    end

    local replicateParam =
        slot.ReplicateIndividualParameter

    if not replicateParam then
        return nil
    end

    local save =
        replicateParam.SaveParameter

    if not save then
        return nil
    end

    return save

end


------------------------------------------------
-- SaveParameter Retrieval: Handle Route
------------------------------------------------

-- Obtain SaveParameter from the IndividualParameter returned
-- by Slot.GetHandle().
--
-- The retrieval route is:
--
--   Slot
--     ↓ GetHandle()
--   IndividualParameter
--     ↓ SaveParameter
--
-- This is the retrieval method currently used by SlotUpdate.
--
-- This function is responsible only for retrieving SaveParameter.
-- Overlay processing remains in UpdateSlotOverlay().
local function GetSaveParameter_Handle(slot)

    if not slot then
        return nil
    end

    local handle = slot:GetHandle()

    if not handle then
        return nil
    end

    local param =
        handle:TryGetIndividualParameter()

    if not param then
        return nil
    end

    local save =
        param.SaveParameter

    if not save then
        return nil
    end

    return save

end


------------------------------------------------
-- SaveParameter Retrieval: Current Preset Pal Route
------------------------------------------------

-- Obtain the current SaveParameter for a Pal registered in a preset.
--
-- Preset LoadoutData stores both the SaveParameter captured when the preset
-- was registered and the PalInstanceID of that individual Pal. The stored
-- SaveParameter can therefore become stale after level, rank, passive skill,
-- Talent, Friendship, or other Pal data changes.
--
-- Use PalInstanceID only as the stable lookup key and resolve the current
-- UPalIndividualCharacterParameter through PalUtility, matching Palworld's
-- own SetupByIndividualId retrieval path:
--
--   Preset element
--     ↓ PalInstanceID
--   PalUtility:GetIndividualCharacterParameterByIstanceID()
--     ↓
--   UPalIndividualCharacterParameter
--     ↓ SaveParameter
--   Current SaveParameter
--
-- No fallback to the SaveParameter stored in the preset is performed. Mixing
-- current and historical values on the same preset screen would make the
-- Overlay state ambiguous.
local function GetSaveParameter_PresetCurrent(
    widget,
    element
)

    if not widget or not element then
        return nil
    end

    local instanceId = nil

    local okId, resultId =
        pcall(function()
            return element.PalInstanceID
        end)

    if okId then
        instanceId = resultId
    end

    if not okId or not instanceId then
        return nil
    end

    local palUtility =
        Res.palUtility

    if not palUtility then

        local okUtility, resultUtility =
            pcall(function()
                return StaticFindObject(PAL_UTILITY)
            end)

        if okUtility and resultUtility then
            palUtility = resultUtility
            Res.palUtility = resultUtility
        end

    end

    if not palUtility then
        return nil
    end

    local parameter = nil

    local okParameter, resultParameter =
        pcall(function()
            return palUtility:GetIndividualCharacterParameterByIstanceID(
                widget,
                instanceId
            )
        end)

    if okParameter then
        parameter = resultParameter
    end

    if not okParameter or not parameter then
        return nil
    end

    -- UE4SS may return a truthy UObject wrapper whose native UObject pointer
    -- is nullptr when the Pal referenced by the preset no longer exists.
    -- A simple nil check therefore is not sufficient. Validate the UObject
    -- before reading SaveParameter from it.
    local okParameterValid, isParameterValid =
        pcall(function()
            return parameter:IsValid()
        end)

    if not okParameterValid or not isParameterValid then
        return nil
    end

    local save = nil

    local okSave, resultSave =
        pcall(function()
            return parameter.SaveParameter
        end)

    if okSave then
        save = resultSave
    end

    if not okSave or not save then
        return nil
    end

    return save

end

SafeRegisterHook(
    HookTarget.SlotUpdate,
    function(Context, targetSlot)

        local widget = Context:get()

        if not widget then
            return
        end

        ------------------------------------------------
        -- Normal-slot parent classification
        ------------------------------------------------
        --
        -- Once AddSlotButtonToScrollList has classified this Widget as a real
        -- paged WBP_BoxPalScrollList child, that ownership result is stronger
        -- than repeating the same four-level Outer traversal on every later
        -- SlotUpdate. Unknown / auxiliary Widgets still use the full hierarchy
        -- check so Preset and exclusion behavior remains unchanged.
        local poolMode, widgetAddress =
            SharedOverlayPool.GetWidgetPoolMode(
                widget
            )

        local liveScrollRecord =
            SharedOverlayPool.GetLiveScrollSlotRecord(
                widgetAddress
            )

        if type(liveScrollRecord) == "table" then

            if not SharedOverlayPool.IsLiveScrollRecordOwnerActive(
                liveScrollRecord
            ) then

                if DEBUG then

                    SharedOverlayPool.DiagnosticInactiveOwnerSlotUpdateRejected =
                        (SharedOverlayPool.DiagnosticInactiveOwnerSlotUpdateRejected or 0) + 1

                    local rejectedCount =
                        SharedOverlayPool.DiagnosticInactiveOwnerSlotUpdateRejected

                    if rejectedCount <= 20
                        or rejectedCount % 100 == 0 then

                        Log(
                            "[PoolOwnerGeneration] Rejected inactive-owner SlotUpdate / count =",
                            rejectedCount,
                            "/ widgetAddress =",
                            widgetAddress or 0,
                            "/ ownerGeneration =",
                            liveScrollRecord.OwnerGeneration or 0
                        )

                    end

                end

                return

            end

            -- Preclassification is authoritative only for the currently active
            -- ScrollList generation.
            poolMode = liveScrollRecord.PersistentPool == true

        elseif SharedOverlayPool.IsDetachedUnregisteredSlot(
            widget
        ) then

            -- this SlotButton is no longer registered as live and is
            -- no longer parented in the UI. It is a retired dynamic ScrollList
            -- Slot; do not let a late update reacquire a pooled Entry.
            if DEBUG then

                SharedOverlayPool.DiagnosticDetachedSlotUpdateRejected =
                    (SharedOverlayPool.DiagnosticDetachedSlotUpdateRejected or 0) + 1

                local rejectedCount =
                    SharedOverlayPool.DiagnosticDetachedSlotUpdateRejected

                if rejectedCount <= 20
                    or rejectedCount % 100 == 0 then

                    Log(
                        "[PoolLiveRegistry] Rejected detached unregistered SlotUpdate / count =",
                        rejectedCount,
                        "/ widgetAddress =",
                        widgetAddress or 0,
                        "/ liveNow =",
                        SharedOverlayPool.CountLiveScrollSlots()
                    )

                end

            end

            return

        end

        -- Preset retirement is stored on the exact live Common
        -- SlotButton record. This remains bounded by current Button lifetime
        -- and rejects a late update before any Pool reacquisition can occur.
        local liveCommonRecord =
            SharedOverlayPool.GetLiveCommonSlotRecord(
                widgetAddress
            )

        if type(liveCommonRecord) == "table"
            and liveCommonRecord.Retiring == true then

            if DEBUG then

                SharedOverlayPool.DiagnosticCommonRetiringBlocked =
                    (SharedOverlayPool.DiagnosticCommonRetiringBlocked or 0) + 1

                local blockedCount =
                    SharedOverlayPool.DiagnosticCommonRetiringBlocked

                if blockedCount <= 20
                    or blockedCount % 100 == 0 then

                    Log(
                        "[PoolCommonLifecycle] Rejected retiring Common SlotUpdate / count =",
                        blockedCount,
                        "/ widgetAddress =",
                        widgetAddress or 0,
                        "/ slotButtonAddress =",
                        liveCommonRecord.SlotButtonAddress or 0,
                        "/ reason =",
                        liveCommonRecord.RetireReason or "<unknown>"
                    )

                end

            end

            return

        end

        -- Debug-only: if this record is live and non-ScrollList,
        -- record the SlotUpdate before parent classification / resource / save
        -- retrieval. Absence of this log proves no live SlotUpdate occurred.
        local diagnosticLiveCommonUpdate =
            DEBUG
            and type(liveCommonRecord) == "table"
            and liveCommonRecord.IsScrollList == false
            and liveCommonRecord.Retiring ~= true

        if diagnosticLiveCommonUpdate then

            SharedOverlayPool.DiagnosticCommonLiveSlotUpdateObserved =
                (SharedOverlayPool.DiagnosticCommonLiveSlotUpdateObserved or 0) + 1

            local observedCount =
                SharedOverlayPool.DiagnosticCommonLiveSlotUpdateObserved

            if observedCount <= 30 or observedCount % 100 == 0 then
                Log(
                    "[PoolCommonPathDiag] Live non-scroll SlotUpdate / count =",
                    observedCount,
                    "/ widgetAddress =",
                    widgetAddress or 0,
                    "/ slotButtonAddress =",
                    liveCommonRecord.SlotButtonAddress or 0,
                    "/ source =",
                    liveCommonRecord.Source or "Setup",
                    "/ poolModeBeforeClassify =",
                    tostring(poolMode),
                    "/ context =",
                    liveCommonRecord.ContextSignature or "<unknown>"
                )
            end

        end

        -- Debug-only diagnostic. Do not alter the existing retirement guard;
        -- merely record whether this update arrived after the exact owning
        -- CommonCharacterSlotButton already emitted Destruct.
        SharedOverlayPool.ObserveSlotUpdateAfterButtonDestruct(
            widget,
            widgetAddress
        )

        local retireRecord =
            widgetAddress
            and SharedOverlayPool.WidgetRetiringReasonByAddress[
                widgetAddress
            ]
            or nil

        if retireRecord then

            local retireReason =
                type(retireRecord) == "table"
                and retireRecord.Reason
                or retireRecord

            local retiredSlotButtonAddress =
                type(retireRecord) == "table"
                and retireRecord.SlotButtonAddress
                or nil

            local retireSequence =
                type(retireRecord) == "table"
                and retireRecord.CleanupSequence
                or nil

            local retireState =
                retireSequence
                and SharedOverlayPool.DiagnosticRetireStateBySequence[
                    retireSequence
                ]
                or nil

            local retirePhase =
                type(retireState) == "table"
                and retireState.Returned == true
                and "AfterCleanup"
                or "DuringCleanup"

            local currentSlotButtonAddress = nil

            -- Diagnostic identity check only runs when an address already has
            -- a retiring marker. It is not part of the normal SlotUpdate hot
            -- path. CharacterSlot -> WidgetTree -> SlotButton is stable for
            -- the normal slot widgets involved here.
            pcall(function()

                local widgetTree =
                    widget:GetOuter()

                local slotButton =
                    widgetTree
                    and widgetTree:GetOuter()
                    or nil

                currentSlotButtonAddress =
                    SharedOverlayPool.GetAddress(
                        slotButton
                    )

            end)

            if retiredSlotButtonAddress
                and currentSlotButtonAddress
                and currentSlotButtonAddress
                    ~= retiredSlotButtonAddress then

                -- The CharacterSlot address has been recycled for a different
                -- SlotButton instance. The old retiring marker must not block
                -- this new live SlotUpdate.
                SharedOverlayPool.WidgetRetiringReasonByAddress[
                    widgetAddress
                ] = nil

                SharedOverlayPool.WidgetSlotButtonAddressByWidgetAddress[
                    widgetAddress
                ] = currentSlotButtonAddress

                SharedOverlayPool.DiagnosticRetiredSlotReuseCount =
                    (SharedOverlayPool.DiagnosticRetiredSlotReuseCount or 0) + 1

                if type(retireState) == "table" then
                    if retirePhase == "AfterCleanup" then
                        retireState.ReusedAfterCleanup =
                            (retireState.ReusedAfterCleanup or 0) + 1
                    else
                        retireState.ReusedDuringCleanup =
                            (retireState.ReusedDuringCleanup or 0) + 1
                    end
                end

                Log(
                    "[PoolRetireDiag] Reused Slot address reactivated / count =",
                    SharedOverlayPool.DiagnosticRetiredSlotReuseCount,
                    "/ phase =",
                    retirePhase,
                    "/ cleanupSeq =",
                    retireSequence or 0,
                    "/ reason =",
                    retireReason or "<unknown>",
                    "/ widget =",
                    SharedOverlayPool.GetDiagnosticFullName(
                        widget
                    ) or "<unavailable>"
                )

            else

                SharedOverlayPool.DiagnosticRetiredSlotUpdateCount =
                    (SharedOverlayPool.DiagnosticRetiredSlotUpdateCount or 0) + 1

                if type(retireState) == "table" then
                    if retirePhase == "AfterCleanup" then
                        retireState.BlockedAfterCleanup =
                            (retireState.BlockedAfterCleanup or 0) + 1
                    else
                        retireState.BlockedDuringCleanup =
                            (retireState.BlockedDuringCleanup or 0) + 1
                    end
                end

                local buttonDestructRecord =
                    SharedOverlayPool.DiagnosticSlotButtonDestructByWidgetAddress[
                        widgetAddress
                    ]

                local buttonPhase = "Unknown"

                if retiredSlotButtonAddress
                    and currentSlotButtonAddress
                    and currentSlotButtonAddress == retiredSlotButtonAddress then

                    if type(buttonDestructRecord) == "table"
                        and buttonDestructRecord.SlotButtonAddress
                            == retiredSlotButtonAddress then

                        buttonPhase = "AfterDestruct"

                        SharedOverlayPool.DiagnosticRetiredSlotUpdateAfterButtonDestructCount =
                            (SharedOverlayPool.DiagnosticRetiredSlotUpdateAfterButtonDestructCount or 0) + 1

                        if type(retireState) == "table" then
                            retireState.BlockedAfterButtonDestruct =
                                (retireState.BlockedAfterButtonDestruct or 0) + 1
                        end

                    else

                        buttonPhase = "BeforeDestruct"

                        SharedOverlayPool.DiagnosticRetiredSlotUpdateBeforeButtonDestructCount =
                            (SharedOverlayPool.DiagnosticRetiredSlotUpdateBeforeButtonDestructCount or 0) + 1

                        if type(retireState) == "table" then
                            retireState.BlockedBeforeButtonDestruct =
                                (retireState.BlockedBeforeButtonDestruct or 0) + 1
                        end

                    end

                else

                    SharedOverlayPool.DiagnosticRetiredSlotUpdateUnknownButtonDestructCount =
                        (SharedOverlayPool.DiagnosticRetiredSlotUpdateUnknownButtonDestructCount or 0) + 1

                    if type(retireState) == "table" then
                        retireState.BlockedUnknownButtonDestruct =
                            (retireState.BlockedUnknownButtonDestruct or 0) + 1
                    end

                end

                if retirePhase == "AfterCleanup"
                    and not SharedOverlayPool.DiagnosticAfterCleanupObserved then

                    SharedOverlayPool.DiagnosticAfterCleanupObserved = true

                    Log(
                        "[PoolRetireLifetime] AFTER CLEANUP late SlotUpdate confirmed / cleanupSeq =",
                        retireSequence or 0,
                        "/ reason =",
                        retireReason or "<unknown>"
                    )

                end

                Log(
                    "[PoolRetireDiag] Blocked late SlotUpdate / count =",
                    SharedOverlayPool.DiagnosticRetiredSlotUpdateCount,
                    "/ phase =",
                    retirePhase,
                    "/ cleanupSeq =",
                    retireSequence or 0,
                    "/ reason =",
                    retireReason or "<unknown>",
                    "/ buttonPhase =",
                    buttonPhase,
                    "/ beforeDestructTotal =",
                    SharedOverlayPool.DiagnosticRetiredSlotUpdateBeforeButtonDestructCount or 0,
                    "/ afterDestructTotal =",
                    SharedOverlayPool.DiagnosticRetiredSlotUpdateAfterButtonDestructCount or 0,
                    "/ unknownDestructTotal =",
                    SharedOverlayPool.DiagnosticRetiredSlotUpdateUnknownButtonDestructCount or 0
                )

                return

            end

        end

        local excluded = false
        local belongsToPreset = false
        local excludedFromNormalPool = false

        if poolMode ~= true then

            excluded,
            belongsToPreset,
            excludedFromNormalPool =
                InspectNormalSlotParents(
                    widget
                )

        end

        if diagnosticLiveCommonUpdate then
            Log(
                "[PoolCommonPathDiag] Classification",
                "/ widgetAddress =",
                widgetAddress or 0,
                "/ excluded =",
                tostring(excluded),
                "/ preset =",
                tostring(belongsToPreset),
                "/ poolExcluded =",
                tostring(excludedFromNormalPool),
                "/ poolMode =",
                tostring(poolMode)
            )
        end

        if excluded or belongsToPreset then
            return
        end

        ------------------------------------------------
        -- Obtain the Slot to Update
        ------------------------------------------------

        local slot = targetSlot:get()

        if not slot then
            return
        end

        ------------------------------------------------
        -- Wait for Resource Loading
        --
        -- Immediately after game startup, the required Textures
        -- and DataTables may not have been loaded yet,
        -- so initialization is performed here.
        ------------------------------------------------

        local allowPersistentPool =
            not excludedFromNormalPool
            and poolMode ~= false

        if diagnosticLiveCommonUpdate then
            Log(
                "[PoolCommonPathDiag] Pool gate",
                "/ widgetAddress =",
                widgetAddress or 0,
                "/ allowPersistentPool =",
                tostring(allowPersistentPool)
            )
        end

        if not EnsureResourceReady() then

            if diagnosticLiveCommonUpdate then
                Log(
                    "[PoolCommonPathDiag] ResourceReady failed",
                    "/ widgetAddress =",
                    widgetAddress or 0
                )
            end

            PalIconRuntime.NormalSlotsMissedBeforeResourceReady = true

            return
        end

        ------------------------------------------------
        -- Obtain SaveParameter
        ------------------------------------------------

        -- Retrieve SaveParameter using the Handle Route.
        -- The retrieval method is isolated in GetSaveParameter_Handle()
        -- so that the alternative Replicate Route can be used without
        -- changing the Overlay processing below.
        local save =
            GetSaveParameter_Handle(slot)

        if not save then
            if diagnosticLiveCommonUpdate then
                Log(
                    "[PoolCommonPathDiag] SaveParameter missing",
                    "/ widgetAddress =",
                    widgetAddress or 0
                )
            end
            return
        end

        ------------------------------------------------
        -- Update Overlay
        ------------------------------------------------

        UpdateSlotOverlay(
            widget,
            save,
            "Normal",
            true,
            allowPersistentPool,
            nil,
            widgetAddress
        )

        if diagnosticLiveCommonUpdate then

            local diagnosticEntry =
                SharedOverlayPool.GetEntryForWidget(
                    widget,
                    widgetAddress
                )

            if diagnosticEntry then
                SharedOverlayPool.DiagnosticCommonLiveSlotUpdateAttached =
                    (SharedOverlayPool.DiagnosticCommonLiveSlotUpdateAttached or 0) + 1
            else
                SharedOverlayPool.DiagnosticCommonLiveSlotUpdateNoEntry =
                    (SharedOverlayPool.DiagnosticCommonLiveSlotUpdateNoEntry or 0) + 1
            end

            Log(
                "[PoolCommonPathDiag] Update result",
                "/ widgetAddress =",
                widgetAddress or 0,
                "/ entry =",
                diagnosticEntry and "yes" or "no",
                "/ state =",
                diagnosticEntry and (diagnosticEntry.DiagnosticState or "<none>") or "<none>",
                "/ commonOwner =",
                diagnosticEntry and (diagnosticEntry.OwnerCommonSlotButtonAddress or 0) or 0,
                "/ observedTotal =",
                SharedOverlayPool.DiagnosticCommonLiveSlotUpdateObserved or 0,
                "/ attachedTotal =",
                SharedOverlayPool.DiagnosticCommonLiveSlotUpdateAttached or 0,
                "/ noEntryTotal =",
                SharedOverlayPool.DiagnosticCommonLiveSlotUpdateNoEntry or 0
            )

        end

    end
)


------------------------------------------------
-- Hatch Result Setup Hooks
------------------------------------------------
--
-- The hatch-result Widgets are loaded lazily by Palworld. RegisterHook() can
-- hook their Blueprint Functions only after those UFunctions exist in memory.
--
-- A startup-only LoadAsset attempt is not sufficient for this screen, while
-- polling every second would reintroduce the old optional-Hook retry overhead.
-- Instead, the native NotifyMultiHatchComplete_ToClient callback is used as a
-- just-in-time registration point. Because /Script/ RegisterHook callbacks run
-- before the native Function, the two hatch-result Blueprints can be loaded and
-- their Setup / OnClose Hooks registered before Palworld creates the result UI.
------------------------------------------------

local function IsManagedHookRegistered(target)

    local hook =
        PalIconRuntime.Hooks[target]

    return
        type(hook) == "table"
        and hook.Active ~= false
        and type(hook.PreId) == "number"
        and type(hook.PostId) == "number"

end


-- Register an already-loaded UFunction immediately without scheduling the
-- generic Blueprint preload fallback. Used by the hatch just-in-time path,
-- which already runs in the game thread and explicitly loads its Blueprints.
local function RegisterLoadedHookNow(
    target,
    callback
)

    if IsManagedHookRegistered(target) then
        return true
    end

    local hookGeneration =
        RuntimeGeneration

    PalIconRuntime.Dispatchers[
        target
    ] = {
        Generation = hookGeneration,
        Pre = callback,
        Post = nil,
    }

    -- Keep the native wrapper lightweight across MOD restart. It resolves the
    -- real execution-local callback from PalIconRuntime only while its own
    -- generation is current, so a stale UE4SS Hook cannot retain Hatch/Pool
    -- state from the previous Lua execution.
    local guardedCallback = function(...)

        if PalIconRuntime.Generation
            ~= hookGeneration then
            return
        end

        local dispatchers =
            PalIconRuntime.Dispatchers

        local dispatcher =
            type(dispatchers) == "table"
            and dispatchers[target]
            or nil

        if type(dispatcher) ~= "table"
            or dispatcher.Generation ~= hookGeneration then
            return
        end

        local currentCallback =
            dispatcher.Pre

        if type(currentCallback) == "function" then
            return currentCallback(...)
        end

    end

    local ok, preId, postId =
        pcall(function()

            return RegisterHook(
                target,
                guardedCallback
            )

        end)

    if not ok then

        PalIconRuntime.Dispatchers[
            target
        ] = nil

        return false, tostring(preId)
    end

    if type(preId) ~= "number"
        or type(postId) ~= "number" then

        PalIconRuntime.Dispatchers[
            target
        ] = nil

        return false,
            "RegisterHook returned invalid hook IDs."

    end

    local hookRecord = {
        Target = target,
        PreId = preId,
        PostId = postId,
        Active = true,
    }

    PalIconRuntime.Hooks[target] =
        hookRecord

    table.insert(
        PalIconRuntime.HookHistory,
        hookRecord
    )

    return true

end


local function GetBlueprintAssetPathFromHookTarget(target)

    if type(target) ~= "string" then
        return nil
    end

    return target:match(
        "^(/Game/.+)%.[^:]+:"
    )

end


local function LoadHookTargetBlueprint(target)

    local assetPath =
        GetBlueprintAssetPathFromHookTarget(
            target
        )

    if not assetPath then
        return false,
            "Unable to derive Blueprint asset path."
    end

    local ok, result =
        pcall(function()

            return LoadAsset(
                assetPath
            )

        end)

    if not ok then
        return false, tostring(result)
    end

    return true

end


local function OnHatchResultSetup(
    Context,
    IndividualParam
)

    if not IsCurrentRuntimeGeneration()
        or not IsOverlayTargetEnabled("Hatch") then
        return
    end

    local widget = nil

    local okWidget, resultWidget =
        pcall(function()
            return Context:get()
        end)

    if okWidget then
        widget = resultWidget
    end

    if not widget then
        return
    end

    local param = nil

    local okParam, resultParam =
        pcall(function()
            return IndividualParam:get()
        end)

    if okParam then
        param = resultParam
    end

    if not param then
        return
    end

    if not EnsureResourceReady() then
        return
    end

    local save = nil

    local okSave, resultSave =
        pcall(function()
            return param.SaveParameter
        end)

    if okSave then
        save = resultSave
    end

    if not save then
        return
    end

    UpdateSlotOverlay(
        widget,
        save,
        "Hatch"
    )

    EnsureStandaloneDisplayModeControllerBridge(
        widget,
        "Hatch"
    )

end


local function EnsureHatchResultHooksRegistered()

    if not IsCurrentRuntimeGeneration()
        or not IsOverlayTargetEnabled("Hatch") then
        return true
    end

    if not IsManagedHookRegistered(
        HookTarget.SetupHatchResult
    ) then

        local loaded, loadError =
            LoadHookTargetBlueprint(
                HookTarget.SetupHatchResult
            )

        if not loaded then
            return false,
                "Hatch result list Blueprint load failed: "
                .. tostring(loadError)
        end

        local registered, registerError =
            RegisterLoadedHookNow(
                HookTarget.SetupHatchResult,
                OnHatchResultSetup
            )

        if not registered then
            return false,
                "Hatch result Setup Hook registration failed: "
                .. tostring(registerError)
        end

    end

    if not IsManagedHookRegistered(
        HookTarget.HatchResultClose
    ) then

        local loaded, loadError =
            LoadHookTargetBlueprint(
                HookTarget.HatchResultClose
            )

        if not loaded then
            return false,
                "Hatch result screen Blueprint load failed: "
                .. tostring(loadError)
        end

        local registered, registerError =
            RegisterLoadedHookNow(
                HookTarget.HatchResultClose,
                OnDisplayModeHatchResultClose
            )

        if not registered then
            return false,
                "Hatch result OnClose Hook registration failed: "
                .. tostring(registerError)
        end

    end

    return true

end


if Config.DisplayOption.EnableHatchDisplay then

    ------------------------------------------------
    -- If the hatch-result Blueprints happen to be loaded already, register
    -- immediately. Failure here is expected when they have not been opened yet;
    -- the native multi-hatch notification below performs the reliable JIT path.
    ------------------------------------------------

    RegisterLoadedHookNow(
        HookTarget.SetupHatchResult,
        OnHatchResultSetup
    )

    RegisterLoadedHookNow(
        HookTarget.HatchResultClose,
        OnDisplayModeHatchResultClose
    )

    ------------------------------------------------
    -- Reliable lazy-load registration point. This native /Script/ Hook runs
    -- before Palworld handles the multi-hatch completion and creates the UI.
    ------------------------------------------------

    SafeRegisterHook(
        HookTarget.NotifyMultiHatchComplete,
        function()

            if not IsCurrentRuntimeGeneration()
                or not IsOverlayTargetEnabled("Hatch") then
                return
            end

            local registered, errorMessage =
                EnsureHatchResultHooksRegistered()

            if not registered then

                Log(
                    "Hatch Result Hook Registration Failed:",
                    errorMessage
                )

            end

        end
    )

end


------------------------------------------------
-- SetupPreset Hook
------------------------------------------------
--
-- Fired when a preset entry is set up.
--
-- LoadoutData stores the Pals registered in the preset as LoadoutPals.
-- Each element contains both:
--
--   PalInstanceID  = stable identity of the registered Pal
--   SaveParameter  = Pal data captured when the preset was registered
--
-- The stored SaveParameter can become stale. This Hook therefore uses only
-- PalInstanceID from the preset and resolves the current SaveParameter through
-- PalUtility before updating the Overlay.
--
--   LoadoutPals[i]
--       ↓ ValidState
--   PalInstanceID
--       ↓ PalUtility:GetIndividualCharacterParameterByIstanceID()
--   current UPalIndividualCharacterParameter
--       ↓ SaveParameter
--   CharacterSlots[i]
--       ↓ WBP_PalCommonCharacterSlot
--   UpdateSlotOverlay()
--
-- If the current parameter cannot be resolved, the corresponding Overlay is
-- cleared rather than falling back to the historical preset SaveParameter.
--
-- The CharacterSlot inside the preset uses the same Overlay structure as a
-- normal PalBox Slot, so UpdateSlotOverlay() uses targetType = "Normal".
------------------------------------------------

SafeRegisterHook(
    HookTarget.SetupPreset,
    function(Context, LoadoutData, Index)

        -- Index is not used. SetupPreset provides the entire LoadoutData for
        -- one preset, so all LoadoutPals entries are processed in this call.

        ------------------------------------------------
        -- Obtain the Widget executing SetupPreset
        ------------------------------------------------

        local widget = nil

        local okContext, resultContext =
            pcall(function()
                return Context:get()
            end)

        if okContext then
            widget = resultContext
        end

        if not okContext or not widget then
            return
        end

        ------------------------------------------------
        -- Obtain LoadoutData
        ------------------------------------------------

        local loadoutData = nil

        local okLoadout, resultLoadout =
            pcall(function()
                return LoadoutData:get()
            end)

        if okLoadout then
            loadoutData = resultLoadout
        end

        if not okLoadout or not loadoutData then
            return
        end

        local loadoutPals = nil

        local okPals, resultPals =
            pcall(function()
                return loadoutData.LoadoutPals
            end)

        if okPals then
            loadoutPals = resultPals
        end

        if not okPals or not loadoutPals then
            return
        end

        local palsCount = nil

        local okCount, resultCount =
            pcall(function()
                return #loadoutPals
            end)

        if okCount then
            palsCount = resultCount
        end

        if not okCount or not palsCount then
            return
        end

        ------------------------------------------------
        -- Obtain the CharacterSlots actually provided by the Preset Widget
        ------------------------------------------------
        --
        -- Palworld's own SetupPreset logic uses CharacterSlots as the display
        -- boundary and checks whether the matching LoadoutPals index exists.
        -- Keep the MOD on the same boundary so a modded preset can contain
        -- more Pal entries than this Widget can display without causing an
        -- out-of-range CharacterSlots access.
        local characterSlots = nil

        local okSlots, resultSlots =
            pcall(function()
                return widget.CharacterSlots
            end)

        if okSlots then
            characterSlots = resultSlots
        end

        if not okSlots or not characterSlots then
            return
        end

        DebugLog(
            "[PresetSafety] SetupPreset row begin"
        )

        local slotWidgets, slotCount =
            PresetOverlayBinding.BindPresetRowSlots(
                widget,
                characterSlots
            )

        DebugLog(
            "[PresetSafety] SetupPreset row bound / slots =",
            slotCount or -1
        )

        if not slotWidgets
            or type(slotCount) ~= "number" then
            return
        end

        DebugLog(
            "Preset entry / CharacterSlot count:",
            palsCount,
            "/",
            slotCount
        )

        local validCount = 0
        local resolvedCount = 0

        ------------------------------------------------
        -- Process every display Slot
        ------------------------------------------------
        --
        -- BindPresetRowSlots() has already resolved the nested Slot Widgets.
        -- Reuse them here instead of traversing CharacterSlots a second time.
        -- Slots without a corresponding valid LoadoutPal are explicitly hidden,
        -- which also removes the previous need to hide every Preset Entry first.

        for i = 1, slotCount do

            local characterSlotWidget =
                slotWidgets[i]

            if not characterSlotWidget then
                goto continue
            end

            if i > palsCount then

                ClearSlotOverlay(
                    characterSlotWidget,
                    "Normal",
                    "Preset"
                )

                goto continue
            end

            local element = nil

            local okElement, resultElement =
                pcall(function()
                    return loadoutPals[i]
                end)

            if okElement then
                element = resultElement
            end

            if not okElement or not element then

                ClearSlotOverlay(
                    characterSlotWidget,
                    "Normal",
                    "Preset"
                )

                goto continue
            end

            local validState = nil

            local okValid, resultValid =
                pcall(function()
                    return element.ValidState
                end)

            if okValid then
                validState = resultValid
            end

            if not okValid or not validState then

                ClearSlotOverlay(
                    characterSlotWidget,
                    "Normal",
                    "Preset"
                )

                goto continue
            end

            validCount = validCount + 1

            ------------------------------------------------
            -- Resolve current SaveParameter by PalInstanceID
            ------------------------------------------------

            local save =
                GetSaveParameter_PresetCurrent(
                    widget,
                    element
                )

            if not save then

                ClearSlotOverlay(
                    characterSlotWidget,
                    "Normal",
                    "Preset"
                )

                goto continue
            end

            ------------------------------------------------
            -- Update Overlay from current Pal data
            ------------------------------------------------
            --
            -- Keep each preset slot isolated. Even if one Pal contains an
            -- invalid value or becomes unavailable between lookup and display,
            -- that failure must not abort processing of the remaining slots.
            local okUpdate, updateError =
                pcall(function()
                    UpdateSlotOverlay(
                        characterSlotWidget,
                        save,
                        "Normal",
                        true,
                        false,
                        "Preset"
                    )
                end)

            if not okUpdate then

                pcall(function()
                    ClearSlotOverlay(
                        characterSlotWidget,
                        "Normal",
                        "Preset"
                    )
                end)

                DebugLog(
                    "Preset current data update failed: slot =",
                    i,
                    "error =",
                    tostring(updateError)
                )

                goto continue
            end

            resolvedCount = resolvedCount + 1

            ::continue::

        end

        DebugLog(
            "Preset current data resolved:",
            resolvedCount,
            "/",
            validCount
        )

    end
)


------------------------------------------------
-- Visible PalBox Overlay Refresh
------------------------------------------------
-- Re-evaluate PalIconInfo Overlay data on currently visible PalBox-related
-- Slots without rebuilding the PalBox page.
--
-- Normal WBP_PalCharacterSlotBase_C instances cover the visible Box Pal and
-- Base Pal Slots. Preset Slots and unrelated HUD Widgets are excluded through
-- InspectNormalSlotParents(). Party Pal Slots use the separate
-- WBP_IngameMenu_PalBox_PalList_C Widget and are refreshed through TargetSlot.
--
-- Resolving each Slot at call time gives access to the latest
-- IndividualParameter / SaveParameter without retaining live Widget or Slot
-- references. Unlike SetCurrentPage(), this updates only PalIconInfo's own
-- Overlay Widgets, so the selected page and controller focus are unchanged.
--
-- This function is used only for low-frequency events such as Config reload
-- and completed condensation operations.
------------------------------------------------
RefreshVisiblePalBoxOverlays = function(reason)

    if not EnsureResourceReady() then
        return
    end

    local normalUpdated = 0
    local partyUpdated = 0

    ------------------------------------------------
    -- Box Pal / Base Pal Slots
    ------------------------------------------------

    local okNormalFind, normalWidgets =
        pcall(function()
            return FindAllOf("WBP_PalCharacterSlotBase_C")
        end)

    if okNormalFind and normalWidgets then

        for _, widget in ipairs(normalWidgets) do

            local okProcess, updated =
                pcall(function()

                    if not widget:IsVisible() then
                        return false
                    end

                    local excluded, belongsToPreset =
                        InspectNormalSlotParents(widget)

                    if excluded or belongsToPreset then
                        return false
                    end

                    local slot = widget.targetSlot

                    if not slot then
                        return false
                    end

                    local okEmpty, isEmpty =
                        pcall(function()
                            return slot:IsEmpty()
                        end)

                    if not okEmpty then
                        return false
                    end

                    if isEmpty then
                        ClearSlotOverlay(widget, "Normal")
                        return false
                    end

                    local save =
                        GetSaveParameter_Handle(slot)

                    if not save then
                        return false
                    end

                    UpdateSlotOverlay(
                        widget,
                        save,
                        "Normal",
                        true
                    )

                    return true

                end)

            if okProcess and updated then
                normalUpdated = normalUpdated + 1
            end

        end

    end

    ------------------------------------------------
    -- Party Pal Slots
    ------------------------------------------------

    if Config.DisplayOption.EnablePartyDisplay == true then

        local okPartyFind, partyWidgets =
            pcall(function()
                return FindAllOf("WBP_IngameMenu_PalBox_PalList_C")
            end)

        if okPartyFind and partyWidgets then

            for _, widget in ipairs(partyWidgets) do

                local okProcess, updated =
                    pcall(function()

                        if not widget:IsVisible() then
                            return false
                        end

                        -- WBP_IngameMenu_PalBox_PalList_C stores the Slot
                        -- supplied to Setup() in its TargetSlot property.
                        local slot = widget.TargetSlot

                        if not slot then
                            return false
                        end

                        local okEmpty, isEmpty =
                            pcall(function()
                                return slot:IsEmpty()
                            end)

                        if not okEmpty then
                            return false
                        end

                        if isEmpty then
                            ClearSlotOverlay(widget, "Party")
                            return false
                        end

                        local save =
                            GetSaveParameter_Replicate(slot)

                        if not save then
                            return false
                        end

                        UpdateSlotOverlay(
                            widget,
                            save,
                            "Party"
                        )

                        return true

                    end)

                if okProcess and updated then
                    partyUpdated = partyUpdated + 1
                end

            end

        end

    end

    DebugLog(
        "Visible PalBox-related Overlays refreshed:",
        reason or "unspecified",
        "Normal/Base =",
        normalUpdated,
        "Party =",
        partyUpdated
    )

end


------------------------------------------------
-- Equipment Change Hook
------------------------------------------------
-- OnEquipSlotChanged is fired when the player's equipment slot changes.
-- Re-evaluate Talent visibility so the Talent display follows the game's
-- Ability Glasses requirement without polling.
------------------------------------------------
SafeRegisterHook(
    HookTarget.OnEquipSlotChanged,
    function(Context)

        ------------------------------------------------
        -- Update only the cached Ability Glasses state.
        --
        -- The equipment screen is normally open while this hook fires,
        -- so there is no reason to perform PalBox UI processing here.
        ------------------------------------------------
        local inventory = nil

        local okContext, resultContext =
            pcall(function()
                return Context:get()
            end)

        if okContext then
            inventory = resultContext
        end

        UpdateAbilityGlassesState(inventory)

    end
)

------------------------------------------------
-- Overlay Refresh After Condensation
------------------------------------------------
-- PalMapObjectRankUpCharacterModel:ReceiveOperationResult is the native result
-- callback for the condensation / rank-up operation. Using this /Script/ Hook
-- avoids depending on the lazily loaded WBP_IngameMenu_PalCondense Blueprint
-- and therefore avoids the old Hook-registration retry problem in worlds where
-- no condenser UI has been loaded.
--
-- The refresh runs from the Post Hook, after Palworld has processed the result.
-- Visible Box / Base / Party Pal Overlays are re-evaluated directly from their
-- currently bound Slots; the PalBox page itself is not rebuilt. This lets the
-- changed condensation data appear while the result popup is still open and
-- avoids the controller-focus loss previously caused by SetCurrentPage().
------------------------------------------------

SafeRegisterHook(
    HookTarget.CondensationOperationResult,
    function()
        -- Use the Post Hook so SaveParameter reflects Palworld's completed
        -- condensation result before Overlay data is read.
    end,
    function()

        RefreshVisiblePalBoxOverlays("Condensation")

    end
)


------------------------------------------------
-- Slot Empty Hook
------------------------------------------------
--
-- Fired when a Pal Slot becomes empty.
--
-- SlotUpdate only updates Pals for which SaveParameter exists,
-- so when a Slot becomes empty, a previously displayed Overlay
-- may remain.
--
-- Therefore, when generated Overlay Widgets exist on the target Canvas,
-- this Hook clears the contents of those Overlay Widgets.
------------------------------------------------

SafeRegisterHook(
    HookTarget.SlotEmpty,
    function(Context)

        local widget = Context:get()

        if not widget then
            return
        end

        ClearSlotOverlay(
            widget,
            "Normal"
        )

    end
)

------------------------------------------------
-- Party Pal Slot Update
------------------------------------------------

-- Update the Overlay for a Party Pal Slot.
--
-- This function is shared by the Party Pal Slot Hooks:
--
--   SetupPartyPal
--       ↓
--   UpdatePartyPalSlot()
--
--   OnUpdateHandleSlot
--       ↓
--   UpdatePartyPalSlot()
--
-- Both Hooks provide the Party Slot through targetSlot.
-- The Widget executing the Hook is obtained from Context.
--
-- The Slot's empty state is checked first:
--
--   Slot
--       ↓ IsEmpty()
--   Empty Slot
--       ↓
--   Clear existing Overlay widgets
--
-- If the Slot is not empty, SaveParameter is retrieved
-- through the Replicate Route:
--
--   Slot
--       ↓ ReplicateIndividualParameter
--   SaveParameter
--
-- After SaveParameter is obtained, the common Overlay processing
-- is performed by UpdateSlotOverlay() with targetType = "Party".
--
-- This function does not contain Party-specific Overlay processing.
-- Target-specific Canvas handling and Overlay configuration are
-- handled by UpdateSlotOverlay() and the functions it calls.
local function UpdatePartyPalSlot(
    context,
    targetSlot
)

    local widget = nil

    local okWidget, resultWidget =
        pcall(function()
            return context:get()
        end)

    if okWidget then
        widget = resultWidget
    end

    if not okWidget or not widget then
        return
    end

    ------------------------------------------------
    -- Obtain Slot
    ------------------------------------------------

    local slot = nil

    local okSlot, resultSlot =
        pcall(function()
            return targetSlot:get()
        end)

    if okSlot then
        slot = resultSlot
    end

    if not okSlot or not slot then
        return
    end

    ------------------------------------------------
    -- Check Empty State
    ------------------------------------------------

    local okEmpty, isEmpty =
        pcall(function()
            return slot:IsEmpty()
        end)

    if not okEmpty then
        return
    end

    if isEmpty then

        ------------------------------------------------
        -- Clear Overlay
        ------------------------------------------------

        ClearSlotOverlay(
            widget,
            "Party"
        )

        return
    end

    ------------------------------------------------
    -- Ensure resources / Party Pool are ready
    ------------------------------------------------

    if not EnsureResourceReady() then
        return
    end

    ------------------------------------------------
    -- Obtain SaveParameter
    ------------------------------------------------

    local save =
        GetSaveParameter_Replicate(slot)

    if not save then
        return
    end

    ------------------------------------------------
    -- Update Party Pal Overlay
    ------------------------------------------------

    UpdateSlotOverlay(
        widget,
        save,
        "Party"
    )

end

------------------------------------------------
-- Setup Party Pal Hook
------------------------------------------------

-- Fired when a Party Pal Slot is initially set up.
--
-- The Slot is passed to UpdatePartyPalSlot(), which retrieves
-- SaveParameter and applies the common Overlay processing
-- for the Party target.
if Config.DisplayOption.EnablePartyDisplay then

    SafeRegisterHook(
        HookTarget.SetupPartyPal,
        function(Context, TargetSlot)

            UpdatePartyPalSlot(
                Context,
                TargetSlot
            )

        end
    )

end

------------------------------------------------
-- Party Pal Slot Update Hook
------------------------------------------------

-- Fired when the Handle assigned to a Party Pal Slot is updated.
--
-- The updated Slot is passed to UpdatePartyPalSlot() so that
-- the Overlay contents can be refreshed using the current
-- SaveParameter.
if Config.DisplayOption.EnablePartyDisplay then

    SafeRegisterHook(
        HookTarget.OnUpdateHandleSlot,
        function(Context, Slot)

            UpdatePartyPalSlot(
                Context,
                Slot
            )

        end
    )

end


------------------------------------------------
-- Party Pool Host Destruct
------------------------------------------------
--
-- Party rows are owned by WBP_IngameMenu_PalBox_C, which is itself retained by
-- WBP_PalStorageMenu_C. The row Blueprint has no Destruct event, so reclaim the
-- complete Party Pool when the PalStorageMenu screen finishes Destruct.
------------------------------------------------

if Config.DisplayOption.EnablePartyDisplay
    and PartyOverlayPool.Enabled then

    SafeRegisterHook(
        HookTarget.PartyPoolHostDestruct,
        function()

            PartyOverlayPool.ParkAll(
                "WBP_PalStorageMenu Destruct"
            )

        end
    )

end

------------------------------------------------
-- Restart Cleanup
------------------------------------------------

local function CleanupCurrentExecution()

    -- Invalidate delayed callbacks and the Config Watch loop first.
    PalIconRuntime.Generation =
        (tonumber(PalIconRuntime.Generation) or 0) + 1

    PalIconRuntime.DisplayModeKeyHandler = nil
    PalIconRuntime.PresetSwapMouseHandler = nil

    -- Release execution-local callback upvalues before any old Widget cleanup.
    -- Native Hook wrappers only keep scalar generation/key data and become inert
    -- as soon as this dispatcher table is cleared.
    PalIconRuntime.Dispatchers = {}

    -- Unregister every Hook ID that this execution recorded. HookHistory keeps
    -- older IDs reachable even if the same target was accidentally registered
    -- more than once before cleanup.
    local hooks =
        PalIconRuntime.HookHistory

    if type(hooks) == "table" then

        for _, hook in ipairs(hooks) do

            if type(hook) == "table"
                and hook.Active ~= false
                and type(hook.Target) == "string"
                and type(hook.PreId) == "number"
                and type(hook.PostId) == "number" then

                pcall(function()
                    UnregisterHook(
                        hook.Target,
                        hook.PreId,
                        hook.PostId
                    )
                end)

                hook.Active = false

            end

        end

    end


    PalIconRuntime.Hooks = {}
    PalIconRuntime.HookHistory = {}

    pcall(function()
        SharedOverlayPool.Destroy()
    end)

    pcall(function()
        PartyOverlayPool.Destroy()
    end)

    pcall(function()
        DestroyDisplayModeControllerBridge()
    end)

end

PalIconRuntime.Cleanup =
    CleanupCurrentExecution


------------------------------------------------
-- Initial Cleanup
------------------------------------------------

-- This cleanup runs once per PalIconInfo Lua execution. It is not repeated by
-- normal Hook callbacks. When the MOD is restarted, Widgets created by the
-- previous execution may still exist, so their contents are cleared here before
-- the current execution begins normal updates.

ClearAllOverlayWidgets()


---------------------------------------------------
-- Display Mode HotKey
---------------------------------------------------

-- Register the keys defined in Config.DisplayMode
-- and initialize the current display state in Config.ActiveDisplay.
--
-- After a reload through ConfigWatch,
-- RegisterDisplayModeHotKeys() adds only keys
-- that have not already been registered.
RegisterDisplayModeHotKeys()
ApplyDisplayMode()

-- Register Middle Mouse once. The callback is inert outside the Pal Preset
-- screen and uses the vanilla LastHoveredIndex maintained by OnButtonHovered.
-- The CommonUI Action row separately provides the Middle Mouse guide glyph.
RegisterPresetSwapMouseKey()

-- Register the shared Keyboard/Gamepad CommonUI DisplayMode Action for the
-- DisplayMode table that defines GamepadButton. The bridge is created
-- lazily when a supported PalBox / standalone Overlay screen opens.
InitializeDisplayModeController()


------------------------------------------------
-- Config Watch
------------------------------------------------

-- Check the contents of PalIconInfoConfig.lua every second.
-- When the file contents change, execute ReloadConfig()
-- to apply DisplayMode and UI settings without restarting the game.
--
-- This loop starts when EnsureResourceReady() succeeds for the first Overlay
-- entry point (normal Slot, Preset, Party, or Hatch). It therefore does not run
-- before the assets required for Overlay processing have been initialized.
ConfigWatchLoop = function()

    if not IsCurrentRuntimeGeneration() then
        return
    end

    CheckConfigChanged()

    ExecuteWithDelay(
        1000,
        function()

            if not IsCurrentRuntimeGeneration() then
                return
            end

            ConfigWatchLoop()

        end
    )

end

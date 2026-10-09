------------------------------------------------
-- PalBoxPageSkip
-- Version: 1.4.0-beta1
-- Date: 2026-09-16
-- Author: ikusamaou
------------------------------------------------
------------------------------------------------
-- Changelog
------------------------------------------------
-- Version 1.4.0-beta1 - 2026-09-16
-- - Reworked hold handling to use WBP_BoxPalListBase's native Pressed / hold-timer page-step path.
-- - Removed the previous Lua hold-preview, release-commit, Slider/Text synchronization, and repeat state.
-- - Cached the last active PalBox transient path so native repeat normally resolves only one real PalBox target.
-- - Redesigned restart-safe Hook dispatch and Hook ID tracking to prevent previous MOD executions from retaining callbacks or UObject state.
-- - Improved restart cleanup ordering and CommonUI bridge reconstruction.
-- - Simplified path, bridge, and class-name handling for lower overhead and easier maintenance.
--
-- Version 1.2.0 - 2026-09-10
-- - Replaced the WBP_PalStatus Action Bar guide proxy with native Action Bar exposure from the existing CommonUI Page Skip bridge.
-- - Hid conflicting L2/R2 Page Skip guides on the Pal selling screen while preserving the vanilla Trigger page-movement actions.
--
-- Version 1.2.0-beta4 - 2026-09-09
-- - Replaced Action Bar update-Hook based Trigger guide suppression with a narrow PalStorageMenu source-row update.
-- - Preserved the native L2/R2 cursor-move bindings while suppressing only their conflicting Action Bar guide keys.
-- - Eliminated L2/R2 Cursor Move guide flicker without scanning or modifying pooled Action Bar entries.
--
-- Version 1.2.0-beta3 - 2026-09-08
-- - Added Blueprint-native CommonUI Action Bar guides for Page Skip without using a RegisterActionBinding observer.
-- - Added explicit Action Bar ordering for Page Skip guides.
-- - Hid conflicting vanilla Trigger guide rows while Trigger Page Skip is active.
-- - Reduced normal logging for Trigger guide maintenance.
-- - Updated Trigger guide replacement synchronously to prevent the vanilla Cursor Move guide from flashing before PageSkip.
-- - Removed the persistent PageSkip guide proxy during MOD restart so hidden Widget instances do not accumulate across restarts.
--
-- Version 1.2.0-beta2 - 2026-09-07
-- - Removed the RegisterActionBinding observer used for MOD operation guides to avoid a potential UI-related crash.
-- - Preserved CommonUI-based keyboard and Gamepad Page Skip input without the observer.
-- - Improved Preset-screen transition handling and hidden bridge cleanup.
--
-- Version 1.2.0-beta1 - 2026-09-06
-- - Added configurable Gamepad controls for Page Skip through CommonUI.
-- - Integrated keyboard and Gamepad Page Skip input into the same CommonUI actions.
--
-- Version 1.1.0 - 2026-09-04
-- - Added automatic config migration with backup to preserve user settings when updating the MOD.
-- - Added automatic config reload, including PageOffset and hotkey changes.
--
-- Version 1.0.1 - 2026-08-30
-- - Changed to prevent page skipping while the Pal details screen is open.
-- ----------------------------------------------

-- ----------------------------------------------
-- Dependencies
-- ----------------------------------------------

-- Shared configuration manager.
--
-- The bundled default config is kept under Scripts\DefaultConfig_DO_NOT_EDIT,
-- while the user-editable config is stored in the shared PalIconInfo config folder.
-- On a config version change, matching user values are migrated
-- onto the new default source before the config is loaded.
local ConfigManager = require("ConfigManager")
local ControllerInput = require("ControllerInput")

-- ----------------------------------------------
-- Logging
-- ----------------------------------------------

-- Enables or disables detailed debug logging.
-- Normally false. Set to true only when investigating a problem.
local DEBUG = false

local function Log(...)
    print("[PalBoxPageSkip]", ...)
end

-- Detailed debug logging.
-- Keep this false normally and set it to true only when investigating a problem.
local function DebugLog(...)
    if DEBUG then
        print("[PalBoxPageSkip][Debug]", ...)
    end
end

------------------------------------------------
-- Implementation Overview
------------------------------------------------
--
-- 1. Real PalBox lists are tracked only by transient object-path strings.
-- 2. A hidden WBP_BoxPalListBase bridge owns the native CommonUI bindings.
-- 3. Palworld calls bridge ToNextPage()/ToPrevPage() immediately on Pressed
--    and again from its native 0.25 s / 0.1 s hold timer.
-- 4. Those two page-step hooks move the currently focused real PalBox directly
--    through SetCurrentPage(). There is no Lua repeat timer or Slider preview.
-- 5. Focus hooks enable the bridge only while a supported PalBox list is active.
--
-- Keeping input timing in Palworld and page state in SetCurrentPage() avoids a
-- second Lua-side state machine and keeps Slider/list state authoritative.

------------------------------------------------
-- Restart-safe Runtime
------------------------------------------------
--
-- UE4SS MOD restart can leave callbacks from the previous Lua execution
-- registered. Module-local guards therefore do not prevent callback buildup
-- across restarts.
--
-- Keep only hook IDs, registered key codes and a small dispatcher in _G.
-- No real PalBox UObject is stored in this restart-safe table.
local PAGE_SKIP_RUNTIME_KEY =
    "__PalIconInfo_PalBoxPageSkip_Runtime"

local PageSkipRuntime =
    rawget(
        _G,
        PAGE_SKIP_RUNTIME_KEY
    )

if type(PageSkipRuntime) ~= "table" then

    PageSkipRuntime = {
        Hooks = {},
        Generation = 0,
    }

    rawset(
        _G,
        PAGE_SKIP_RUNTIME_KEY,
        PageSkipRuntime
    )

end

if type(PageSkipRuntime.Hooks) ~= "table" then
    PageSkipRuntime.Hooks = {}
end

if type(PageSkipRuntime.HookHistory) ~= "table" then
    PageSkipRuntime.HookHistory = {}
end

if type(PageSkipRuntime.Dispatchers) ~= "table" then
    PageSkipRuntime.Dispatchers = {}
end

-- Retire the previous execution from the new execution side first. This makes
-- restart safety independent of how old the previous Cleanup implementation is.
local previousCleanup =
    PageSkipRuntime.Cleanup

PageSkipRuntime.Generation =
    (tonumber(PageSkipRuntime.Generation) or 0) + 1

-- Earlier builds registered PageSkip keyboard callbacks through
-- RegisterKeyBind(). Those callbacks cannot be unregistered by UE4SS, but they
-- dispatch through this persistent function pointer. Clear it before any old
-- cleanup work so a leftover key callback is already inert.
PageSkipRuntime.PageSkipKeyHandler = nil

-- Drop execution-local callbacks first. Native Hook wrappers resolve the real
-- callback through this table and do not retain bridge/widget state directly.
PageSkipRuntime.Dispatchers = {}

local previousHooks =
    PageSkipRuntime.HookHistory

-- Migration from builds that tracked only hookKey->Hook in Hooks. Preserve
-- those IDs during the first upgrade to HookHistory.
if type(previousHooks) ~= "table"
    or #previousHooks == 0 then

    previousHooks = {}

    for _, hook in pairs(PageSkipRuntime.Hooks) do
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

PageSkipRuntime.Hooks = {}
PageSkipRuntime.HookHistory = {}

if type(previousCleanup) == "function" then
    pcall(previousCleanup)
end

PageSkipRuntime.Cleanup = nil

PageSkipRuntime.Generation =
    (tonumber(PageSkipRuntime.Generation) or 0) + 1

local RuntimeGeneration =
    PageSkipRuntime.Generation

local function IsCurrentRuntimeGeneration()

    return
        PageSkipRuntime.Generation
        == RuntimeGeneration

end

-- ----------------------------------------------
-- Configuration
-- ----------------------------------------------

local scriptPath = debug.getinfo(1, "S").source

if scriptPath:sub(1, 1) == "@" then
    scriptPath = scriptPath:sub(2)
end

local SCRIPT_DIR =
    scriptPath:match("^(.*[/\\])") or ""

local CONFIG_PATH =
    SCRIPT_DIR .. "..\\..\\shared\\PalIconInfo\\PalBoxPageSkipConfig.lua"

local DEFAULT_CONFIG_PATH =
    SCRIPT_DIR .. "DefaultConfig_DO_NOT_EDIT\\PalBoxPageSkipConfig.lua"

local ConfigManagerInstance =
    ConfigManager.Create({

        ConfigPath = CONFIG_PATH,

        DefaultConfigPath = DEFAULT_CONFIG_PATH,

        -- Pass the MOD logger so important config operations such as
        -- creation, migration, merge, backup, and replacement are
        -- written with the normal [PalBoxPageSkip] log prefix.
        Log = Log,

    })

local Config, ConfigLoadError =
    ConfigManagerInstance:Load()

if not Config then
    error(
        "[PalBoxPageSkip] "
        .. tostring(ConfigLoadError)
    )
end


local DEFAULT_GAMEPAD_SKIP_FORWARD_BUTTON =
    "Right Stick Right"

local DEFAULT_GAMEPAD_SKIP_BACKWARD_BUTTON =
    "Right Stick Left"

------------------------------------------------
-- PageSkip-specific Gamepad Inputs
------------------------------------------------
--
-- ControllerInput intentionally does not know which Gamepad keys PageSkip
-- supports. The PageSkip feature owns its own aliases, restrictions, defaults,
-- and Trigger conflict behavior.
local GAMEPAD_BUTTON_ALIASES = {

    ["Right Stick Left"]  = "Gamepad_RightStick_Left",
    ["Right Stick Right"] = "Gamepad_RightStick_Right",

    -- L2/R2 on PlayStation-style controllers, LT/RT on Xbox-style controllers.
    ["Left Trigger"]  = "Gamepad_LeftTrigger",
    ["Right Trigger"] = "Gamepad_RightTrigger",

}

local SUPPORTED_GAMEPAD_PAGE_SKIP_KEYS = {

    ["Gamepad_RightStick_Left"] = true,
    ["Gamepad_RightStick_Right"] = true,
    ["Gamepad_LeftTrigger"] = true,
    ["Gamepad_RightTrigger"] = true,

}


local function ResolveGamepadButtonName(
    buttonName
)

    if type(buttonName) ~= "string"
        or buttonName == "" then
        return nil
    end

    local resolved =
        GAMEPAD_BUTTON_ALIASES[
            buttonName
        ]
        or buttonName

    if not SUPPORTED_GAMEPAD_PAGE_SKIP_KEYS[
        resolved
    ] then
        return nil
    end

    return resolved

end


local function GetGamepadPageSkipButtons(
    pageSkip
)

    if type(pageSkip) ~= "table" then
        return nil, nil
    end

    local forwardButton =
        pageSkip.GamepadSkipForwardButton

    local backwardButton =
        pageSkip.GamepadSkipBackwardButton

    if type(forwardButton) ~= "string"
        or forwardButton == "" then

        forwardButton =
            DEFAULT_GAMEPAD_SKIP_FORWARD_BUTTON

    end

    if type(backwardButton) ~= "string"
        or backwardButton == "" then

        backwardButton =
            DEFAULT_GAMEPAD_SKIP_BACKWARD_BUTTON

    end

    return forwardButton,
        backwardButton

end


local initialGamepadForwardButton,
    initialGamepadBackwardButton =
    GetGamepadPageSkipButtons(
        Config.PageSkip
    )

local GamepadSkipForwardButton =
    ResolveGamepadButtonName(
        initialGamepadForwardButton
    )

local GamepadSkipBackwardButton =
    ResolveGamepadButtonName(
        initialGamepadBackwardButton
    )

if not GamepadSkipForwardButton then

    error(
        "[PalBoxPageSkip] GamepadSkipForwardButton must be Right Stick Left/Right or Left/Right Trigger."
    )

end

if not GamepadSkipBackwardButton then

    error(
        "[PalBoxPageSkip] GamepadSkipBackwardButton must be Right Stick Left/Right or Left/Right Trigger."
    )

end


local KeyboardSkipForwardKey,
    keyboardForwardError =
    ControllerInput.ResolveKeyboardKeyName(
        Config.PageSkip
        and Config.PageSkip.SkipForwardKey
    )

if not KeyboardSkipForwardKey then

    error(
        "[PalBoxPageSkip] Invalid SkipForwardKey for CommonUI: "
        .. tostring(keyboardForwardError)
    )

end

local KeyboardSkipBackwardKey,
    keyboardBackwardError =
    ControllerInput.ResolveKeyboardKeyName(
        Config.PageSkip
        and Config.PageSkip.SkipBackwardKey
    )

if not KeyboardSkipBackwardKey then

    error(
        "[PalBoxPageSkip] Invalid SkipBackwardKey for CommonUI: "
        .. tostring(keyboardBackwardError)
    )

end

-- ----------------------------------------------
-- Hook Targets
-- ----------------------------------------------

-- Blueprint Functions in Palworld used as hook targets.
--
-- PalBoxSetMaxPageNum:
-- Called when the maximum page count of a PalBoxList is set.
-- Records the currently opened PalBoxList here.
--
-- PalBoxDestruct:
-- Called when a PalBoxList is destroyed.
-- Clears the recorded PalBoxList.

local PAL_BOX_LIST_BASE_ASSET =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase"

local PAL_CHARACTER_SCROLL_LIST_ASSET =
    "/Game/Pal/Blueprint/UI/CommonWidget/CommonScrollList/WBP_PalCharacterScrollList"

local PAL_BOX_PRESET_ASSET =
    "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_Preset"

-- Loaded up front so the narrow RegisterStaticActionInput Hook can be
-- installed before PalStorageMenu creates its native cursor-shortcut bindings.
local PAL_STORAGE_MENU_ASSET =
    "/Game/Pal/Blueprint/UI/PalStorage/WBP_PalStorageMenu"

local WIDGET_BLUEPRINT_LIBRARY =
    "/Script/UMG.Default__WidgetBlueprintLibrary"

local BOX_PAL_LIST_BASE_CLASS =
    "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C"


local HookTarget = {

    -- Called when various PalBox screens are opened. No suitable Setup event was found.
    PalBoxSetMaxPageNum =
        "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C:SetMaxPageNum",

    -- Called when various PalBox screens are closed.
    PalBoxDestruct =
        "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C:Destruct",

    -- The hidden bridge calls ToNextPage()/ToPrevPage() once immediately on
    -- Pressed and again from Palworld's native hold timer.  Hook these page
    -- steps directly so initial press and hold repeat share one code path.
    PageStepNext =
        "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C:ToNextPage",

    PageStepPrevious =
        "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_BoxPalListBase.WBP_BoxPalListBase_C:ToPrevPage",

    -- List-level focus callbacks. These allow PageSkip to distinguish the
    -- normal PalBox list from the Base Camp list in O(1) from Context.
    ScrollFocused =
        "/Game/Pal/Blueprint/UI/CommonWidget/CommonScrollList/WBP_PalCharacterScrollList.WBP_PalCharacterScrollList_C:OnFocused_Internal",

    ScrollUnfocused =
        "/Game/Pal/Blueprint/UI/CommonWidget/CommonScrollList/WBP_PalCharacterScrollList.WBP_PalCharacterScrollList_C:OnUnfocused_Internal",

    -- Preset screen lifecycle. The normal PalBox list is destructed while
    -- the Preset screen is open, but the same transient object is reused
    -- when returning to the PalBox. Restore PageSkip state on that return.
    PresetOnSetup =
        "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_Preset.WBP_IngameMenu_PalBox_Preset_C:OnSetup",

    PresetDestruct =
        "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/PalBox/WBP_IngameMenu_PalBox_Preset.WBP_IngameMenu_PalBox_Preset_C:Destruct",

    -- PalStorageMenu registers the vanilla L2/R2 cursor-move bindings here.
    -- A narrow Blueprint post-execution Hook removes only the conflicting
    -- Trigger key from the Action Row after the native binding has cached it.
    PalStorageRegisterStaticActionInput =
        "/Game/Pal/Blueprint/UI/PalStorage/WBP_PalStorageMenu.WBP_PalStorageMenu_C:RegisterStaticActionInput",

    PalStorageDestruct =
        "/Game/Pal/Blueprint/UI/PalStorage/WBP_PalStorageMenu.WBP_PalStorageMenu_C:Destruct",

}

------------------------------------------------
-- Restart-safe Hook Management
------------------------------------------------

local function UnregisterManagedHook(
    hookKey
)

    local hook =
        PageSkipRuntime.Hooks[
            hookKey
        ]

    PageSkipRuntime.Hooks[
        hookKey
    ] = nil

    PageSkipRuntime.Dispatchers[
        hookKey
    ] = nil

    if type(hook) ~= "table" then
        return
    end

    hook.Active = false

    if type(hook.Target) ~= "string"
        or type(hook.PreId) ~= "number"
        or type(hook.PostId) ~= "number" then
        return
    end

    local ok, errorMessage =
        pcall(function()

            UnregisterHook(
                hook.Target,
                hook.PreId,
                hook.PostId
            )

        end)

    if not ok then

        DebugLog(
            "Previous hook cleanup failed:",
            hookKey,
            errorMessage
        )

    end

end


local function RegisterManagedHook(
    hookKey,
    target,
    callback
)

    UnregisterManagedHook(
        hookKey
    )

    local hookGeneration =
        RuntimeGeneration

    PageSkipRuntime.Dispatchers[
        hookKey
    ] = {
        Generation = hookGeneration,
        Callback = callback,
    }

    -- Do not capture the execution-local callback in the native Hook wrapper.
    -- If UE4SS keeps this wrapper alive after MOD restart, it retains only the
    -- persistent runtime table plus scalar key/generation data, not the old
    -- CommonUI bridge or other module-local UObject state.
    local guardedCallback = function(...)

        if PageSkipRuntime.Generation
            ~= hookGeneration then
            return
        end

        local dispatchers =
            PageSkipRuntime.Dispatchers

        local dispatcher =
            type(dispatchers) == "table"
            and dispatchers[hookKey]
            or nil

        if type(dispatcher) ~= "table"
            or dispatcher.Generation ~= hookGeneration then
            return
        end

        local currentCallback =
            dispatcher.Callback

        if type(currentCallback) == "function" then
            return currentCallback(...)
        end

    end

    local ok,
        preId,
        postId =
        pcall(function()

            return RegisterHook(
                target,
                guardedCallback
            )

        end)

    if not ok then

        PageSkipRuntime.Dispatchers[
            hookKey
        ] = nil

        return false,
            tostring(preId)
    end

    if type(preId) ~= "number"
        or type(postId) ~= "number" then

        PageSkipRuntime.Dispatchers[
            hookKey
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

    PageSkipRuntime.Hooks[
        hookKey
    ] = hookRecord

    table.insert(
        PageSkipRuntime.HookHistory,
        hookRecord
    )

    return true

end


local function UnregisterAllManagedHooks()

    local hookKeys = {}

    for hookKey, _
        in pairs(PageSkipRuntime.Hooks) do

        table.insert(
            hookKeys,
            hookKey
        )

    end

    for _, hookKey
        in ipairs(hookKeys) do

        UnregisterManagedHook(
            hookKey
        )

    end

end

------------------------------------------------
-- PageSkip Controller Bridge Constants
------------------------------------------------

local PAGE_SKIP_ACTION_OWNER =
    "PalBoxPageSkip"

-- Separate owner for the two vanilla cursor-shortcut rows. These rows are
-- modified only after PalStorageMenu has registered its native L2/R2 bindings.
-- The binding keeps the Trigger cached, while the DataTable row no longer
-- advertises that Trigger to the Action Bar.
local PAGE_SKIP_CURSOR_GUIDE_OWNER =
    "PalBoxPageSkip_CursorGuide"

local ACTION_CURSOR_SHORTCUT_PREVIOUS =
    "PalBoxCursorShortcutPrev"

local ACTION_CURSOR_SHORTCUT_NEXT =
    "PalBoxCursorShortcutNext"

-- Existing DT_UIInputAction rows borrowed only while the PageSkip bridge exists.
local ACTION_PREVIOUS =
    "CharacterCreation_ZoomIn_Mouse"

local ACTION_NEXT =
    "CharacterCreation_ZoomOut_Mouse"

-- Display name retained in the borrowed CommonUI Action rows.
-- Both directions use the same label in the native Action Bar.
local GUIDE_DISPLAY_NAME =
    "PageSkip"

-- Explicit order: skill info 10, send 20, detail 30, Display Mode 40,
-- PageSkip Previous 50 / Next 51, favorite 60.
local PAGE_SKIP_PREVIOUS_GUIDE_PRIORITY = 50
local PAGE_SKIP_NEXT_GUIDE_PRIORITY = 51

------------------------------------------------
-- PageSkip Controller Native State
------------------------------------------------

local WidgetBlueprintLibrary = nil
local BoxPalListBaseClass = nil

-- Only the MOD-created hidden bridge UObject is retained. Real PalBox UObjects
-- are represented only by transient path strings. BridgeFullNameSet is a
-- membership set used when a hook callback supplies a different Lua wrapper
-- for the same hidden UObject.
local BridgeFullNameSet = {}
local BridgeFullNameByObject = {}

local ControllerBridgeEnabled = false
local ControllerFocusOnPageSkipList = false
local ControllerFocusOnPalShop = false

local ControllerFocusEventGeneration = 0
local FOCUS_UNFOCUSED_FALLBACK_MS = 10

local FocusTrackingEnabled = false
local ControllerIntegrationReady = false
local ControllerBridgeAttaching = false
local ControllerBridgeDestroying = false

------------------------------------------------
-- PageSkip Controller Native Object Access
------------------------------------------------

local function GetWidgetBlueprintLibrary()

    if WidgetBlueprintLibrary then
        return WidgetBlueprintLibrary
    end

    local ok, result =
        pcall(function()

            return StaticFindObject(
                WIDGET_BLUEPRINT_LIBRARY
            )

        end)

    if not ok
        or not result then

        return nil,
            "WidgetBlueprintLibrary is unavailable."

    end

    WidgetBlueprintLibrary = result

    return WidgetBlueprintLibrary

end


local function GetBoxPalListBaseClass()

    if BoxPalListBaseClass then
        return BoxPalListBaseClass
    end

    local ok, result =
        pcall(function()

            return StaticFindObject(
                BOX_PAL_LIST_BASE_CLASS
            )

        end)

    if not ok
        or not result then

        return nil,
            "WBP_BoxPalListBase_C is unavailable."

    end

    BoxPalListBaseClass = result

    return BoxPalListBaseClass

end


-- Return the UObject class name used by the narrow context checks below.
-- Outer traversal is owned by each caller so the traversal order remains
-- visible at the call site instead of being hidden inside a generic helper.
local function GetClassName(
    object
)

    if not object then
        return nil
    end

    local ok, className =
        pcall(function()

            local class =
                object:GetClass()

            if not class then
                return nil
            end

            local fname =
                class:GetFName()

            if not fname then
                return nil
            end

            return fname:ToString()

        end)

    if not ok then
        return nil
    end

    return className

end

-- Widgets excluded from page-skip operations.
--
-- The Global PalBox is currently excluded.
-- Performing page-skip processing on the Global PalBox
-- causes the game to freeze, so it is excluded here.

local ExcludedWidgetNames = {

    ["WBP_IngameMenu_PalBoxGlobal"] = true,            --Global PalBox

}

-- Determines whether a widget is excluded from page-skip operations.
local function IsExcludedWidgetFullName(fullName)

    if type(fullName) ~= "string" then
        return false
    end

    for name
        in string.gmatch(
            fullName,
            "WBP_[^%.:/]+"
        ) do

        if ExcludedWidgetNames[name] then

            DebugLog(
                "EXCLUDED:",
                name
            )

            return true
        end

    end

    return false

end

-- ----------------------------------------------
-- PalBox Page Movement
-- ----------------------------------------------
-- Moves the real PalBox by the configured number of pages.
--
-- PageOffset:
-- Positive: move forward by the specified number of pages.
-- Negative: move backward by the specified number of pages.
-- Zero is rejected by MovePalBoxPage().
--
-- Page movement never goes outside the range from page 1 to MaxPageNum.
--
-- Movement wraps around when the current page is at an edge.
--
-- Move backward from page 1
-- → wrap around to MaxPageNum.
--
-- Move forward from MaxPageNum
-- → wrap around to page 1.
--
-- If the requested movement cannot be completed from a non-edge page,
-- movement stops at the page at that edge.
-- ----------------------------------------------

-- Stores only transient UObject path strings, never live UObject references.
--
-- GetFullName() is used here to obtain the transient object path required by
-- StaticFindObject(). The same returned string is reused for the one-time
-- excluded-widget check so no second GetFullName() call is performed.
--
-- StaticFindObject(string) expects the full object name without the type
-- prefix, so only the part beginning with /Engine/Transient is retained.
local function GetObjectPath(
    object
)

    if not object then
        return nil
    end

    local fullName = nil

    local ok =
        pcall(function()
            fullName =
                object:GetFullName()
        end)

    if not ok
        or type(fullName) ~= "string" then
        return nil
    end

    local objectPath =
        fullName:match(
            "^%S+%s+(.+)$"
        )

    return objectPath, fullName

end


local function ResolvePalBoxList(
    objectPath
)

    if type(objectPath) ~= "string"
        or objectPath == "" then
        return nil
    end

    local widget = nil

    local ok =
        pcall(function()

            widget =
                StaticFindObject(
                    objectPath
                )

        end)

    if not ok then
        return nil
    end

    return widget

end


local CurrentPalBoxPaths = {}

-- Membership set for CurrentPalBoxPaths.
-- Both containers store transient path strings, never live real-PalBox UObjects.
-- The set prevents duplicate registration without scanning the array.
local CurrentPalBoxPathSet = {}

-- Native CommonUI PageSkip bridge.
-- The bridge exists only while a supported PalBox screen is open and is never
-- used as the actual page-movement target.
local ControllerBridge = nil

-- Prevent bridge creation re-entry while the hidden direct-base Widget is
-- created and attached.
local ControllerBridgeCreating = false

-- Saved PageSkip state used while temporarily leaving the normal PalBox for
-- the Preset screen. OnSetup and PalBox Destruct can occur in either order,
-- so one transition snapshot is updated by whichever event still has access
-- to the live PalBox state. Only transient object paths are retained.
local PresetTransitionState = nil
local PresetScreenActive = false

------------------------------------------------
-- Native Page Movement
------------------------------------------------
--
-- The hidden WBP_BoxPalListBase bridge owns the input timing. Its native
-- OnPressed* path calls ToNextPage()/ToPrevPage() once immediately and then
-- repeats those same calls through Palworld's 0.25 s / 0.1 s hold timer.
--
-- Lua does not keep a second hold state, preview page, Slider value, or
-- release-time commit. Each bridge page-step moves the real PalBox directly
-- through SetCurrentPage().
------------------------------------------------

-- Last real PalBox path that successfully handled PageSkip. Only a transient
-- path string is cached; no real PalBox UObject is retained across callbacks.
local LastActivePalBoxPath = nil

local function CalculatePageSkipTarget(
    currentPage,
    maxPage,
    pageOffset
)

    if type(currentPage) ~= "number"
        or type(maxPage) ~= "number"
        or type(pageOffset) ~= "number"
        or maxPage <= 0 then
        return nil
    end

    local targetPage =
        currentPage + pageOffset

    if pageOffset < 0 then

        if currentPage == 0 then
            targetPage = maxPage - 1
        elseif targetPage < 0 then
            targetPage = 0
        end

    elseif pageOffset > 0 then

        if currentPage == maxPage - 1 then
            targetPage = 0
        elseif targetPage >= maxPage then
            targetPage = maxPage - 1
        end

    end

    return targetPage

end


local function TryMovePalBoxPage(
    objectPath,
    pageOffset
)

    local widget =
        ResolvePalBoxList(
            objectPath
        )

    if not widget then
        return nil
    end

    -- Only the real PalBox list that currently owns hover/focus may receive
    -- the page step.
    local hovered = false

    local okHovered =
        pcall(function()
            hovered = widget:IsHovered()
        end)

    if not okHovered
        or hovered ~= true then
        return nil
    end

    local okPage,
        currentPage,
        maxPage =
        pcall(function()

            return
                widget.LastSelectedPageNum,
                widget.MaxPageNum

        end)

    if not okPage
        or type(currentPage) ~= "number"
        or type(maxPage) ~= "number"
        or maxPage <= 0 then
        return nil
    end

    local targetPage =
        CalculatePageSkipTarget(
            currentPage,
            maxPage,
            pageOffset
        )

    if targetPage == nil then
        return nil
    end

    -- SetCurrentPage() already calls SetCurrentPageNum_WithoutEvent() and
    -- then broadcasts OnUpdatedPage(). Keep page state, Slider, and list
    -- contents on Palworld's normal authoritative path.
    local okMove =
        pcall(function()
            widget:SetCurrentPage(
                targetPage
            )
        end)

    if not okMove then
        return nil
    end

    return objectPath, targetPage

end


local function MovePalBoxPage(
    pageOffset
)

    if type(pageOffset) ~= "number"
        or pageOffset == 0
        or #CurrentPalBoxPaths == 0 then
        return nil
    end

    -- Native hold repeat normally keeps targeting the same real PalBox. Try
    -- that transient path first so the 100 ms repeat path does not rescan all
    -- registered PalBox lists on every tick.
    local cachedPath =
        LastActivePalBoxPath

    if cachedPath
        and CurrentPalBoxPathSet[cachedPath] then

        local objectPath, targetPage =
            TryMovePalBoxPage(
                cachedPath,
                pageOffset
            )

        if objectPath then
            return objectPath, targetPage
        end

        LastActivePalBoxPath = nil

    end

    -- Fallback handles initial focus, Preset return, or a focus change between
    -- supported PalBox lists without retaining any live UObject.
    for _, objectPath
        in ipairs(CurrentPalBoxPaths) do

        if objectPath ~= cachedPath then

            local movedPath, targetPage =
                TryMovePalBoxPage(
                    objectPath,
                    pageOffset
                )

            if movedPath then

                LastActivePalBoxPath =
                    movedPath

                return movedPath, targetPage

            end

        end

    end

    return nil

end


local SetControllerBridgeFocusState = nil

------------------------------------------------
-- Live CommonUI PageSkip Mapping
------------------------------------------------

local function ApplyBorrowedPageSkipRows()

    -- WBP_Shop_Pal_00_C registers its own PalBoxCursorShortcutPrev / Next
    -- Trigger bindings for page movement. When PageSkip is configured to L2/R2,
    -- keep the PageSkip Action Row's Gamepad key at None only while the focused
    -- PageSkip list belongs to that selling screen.
    --
    -- This suppresses only the conflicting PageSkip Trigger guide/input.
    -- Keyboard and Right Stick PageSkip mappings remain available.
    local backwardGamepad =
        GamepadSkipBackwardButton

    local forwardGamepad =
        GamepadSkipForwardButton

    if ControllerFocusOnPalShop then

        if backwardGamepad == "Gamepad_LeftTrigger"
            or backwardGamepad == "Gamepad_RightTrigger" then
            backwardGamepad = "None"
        end

        if forwardGamepad == "Gamepad_LeftTrigger"
            or forwardGamepad == "Gamepad_RightTrigger" then
            forwardGamepad = "None"
        end

    end

    local updatedBackward,
        backwardError =
        ControllerInput.UpdateBorrowedActionRow(
            PAGE_SKIP_ACTION_OWNER,
            ACTION_PREVIOUS,
            {
                Keyboard =
                    KeyboardSkipBackwardKey,
                Gamepad =
                    backwardGamepad,
                NavBarPriority =
                    PAGE_SKIP_PREVIOUS_GUIDE_PRIORITY,
                DisplayName =
                    GUIDE_DISPLAY_NAME,
                HoldDisplayName =
                    GUIDE_DISPLAY_NAME,
            }
        )

    if not updatedBackward then
        return false, backwardError
    end

    local updatedForward,
        forwardError =
        ControllerInput.UpdateBorrowedActionRow(
            PAGE_SKIP_ACTION_OWNER,
            ACTION_NEXT,
            {
                Keyboard =
                    KeyboardSkipForwardKey,
                Gamepad =
                    forwardGamepad,
                NavBarPriority =
                    PAGE_SKIP_NEXT_GUIDE_PRIORITY,
                DisplayName =
                    GUIDE_DISPLAY_NAME,
                HoldDisplayName =
                    GUIDE_DISPLAY_NAME,
            }
        )

    if not updatedForward then
        return false, forwardError
    end

    return true

end


local function SetPageSkipInputKeys(
    forwardButton,
    backwardButton,
    forwardKeyCode,
    backwardKeyCode
)

    local resolvedForward =
        ResolveGamepadButtonName(
            forwardButton
        )

    local resolvedBackward =
        ResolveGamepadButtonName(
            backwardButton
        )

    local resolvedKeyboardForward,
        keyboardForwardError =
        ControllerInput.ResolveKeyboardKeyName(
            forwardKeyCode
        )

    local resolvedKeyboardBackward,
        keyboardBackwardError =
        ControllerInput.ResolveKeyboardKeyName(
            backwardKeyCode
        )

    if not resolvedKeyboardForward then
        return false,
            "Invalid SkipForwardKey for CommonUI: "
            .. tostring(keyboardForwardError)
    end

    if not resolvedKeyboardBackward then
        return false,
            "Invalid SkipBackwardKey for CommonUI: "
            .. tostring(keyboardBackwardError)
    end

    if not resolvedForward then

        return false,
            "GamepadSkipForwardButton must be Right Stick Left/Right or Left/Right Trigger."

    end

    if not resolvedBackward then

        return false,
            "GamepadSkipBackwardButton must be Right Stick Left/Right or Left/Right Trigger."

    end

    if resolvedForward == GamepadSkipForwardButton
        and resolvedBackward == GamepadSkipBackwardButton
        and resolvedKeyboardForward == KeyboardSkipForwardKey
        and resolvedKeyboardBackward == KeyboardSkipBackwardKey then

        return true

    end

    local previousForward =
        GamepadSkipForwardButton

    local previousBackward =
        GamepadSkipBackwardButton

    local previousKeyboardForward =
        KeyboardSkipForwardKey

    local previousKeyboardBackward =
        KeyboardSkipBackwardKey

    local wasEnabled =
        ControllerBridge ~= nil
        and ControllerBridgeEnabled == true

    local wasPalShop =
        ControllerFocusOnPalShop == true

    if wasEnabled then

        local disabled =
            SetControllerBridgeFocusState(
                false
            )

        if not disabled then
            return false,
                "Failed to disable the active CommonUI PageSkip binding."
        end

    end

    GamepadSkipForwardButton =
        resolvedForward

    GamepadSkipBackwardButton =
        resolvedBackward

    KeyboardSkipForwardKey =
        resolvedKeyboardForward

    KeyboardSkipBackwardKey =
        resolvedKeyboardBackward

    if ControllerBridge then

        local updated, updateError =
            ApplyBorrowedPageSkipRows()

        if not updated then

            GamepadSkipForwardButton =
                previousForward

            GamepadSkipBackwardButton =
                previousBackward

            KeyboardSkipForwardKey =
                previousKeyboardForward

            KeyboardSkipBackwardKey =
                previousKeyboardBackward

            -- Restore the previous MOD mapping.
            ApplyBorrowedPageSkipRows()

            if wasEnabled then

                SetControllerBridgeFocusState(
                    true,
                    wasPalShop
                )

            end

            return false,
                updateError
                or "Failed to update CommonUI PageSkip inputs."

        end

    end

    if wasEnabled then

        local reenabled =
            SetControllerBridgeFocusState(
                true,
                wasPalShop
            )

        if not reenabled
            or not ControllerBridgeEnabled then

            GamepadSkipForwardButton =
                previousForward

            GamepadSkipBackwardButton =
                previousBackward

            KeyboardSkipForwardKey =
                previousKeyboardForward

            KeyboardSkipBackwardKey =
                previousKeyboardBackward

            if ControllerBridge then
                ApplyBorrowedPageSkipRows()
            end

            SetControllerBridgeFocusState(
                true,
                wasPalShop
            )

            return false,
                "Failed to re-enable the CommonUI PageSkip binding."

        end

    end

    DebugLog(
        "CommonUI PageSkip inputs updated:",
        "KeyboardBackward =",
        KeyboardSkipBackwardKey,
        "KeyboardForward =",
        KeyboardSkipForwardKey,
        "GamepadBackward =",
        GamepadSkipBackwardButton,
        "GamepadForward =",
        GamepadSkipForwardButton
    )

    return true

end


-- Replaces the active Config after ConfigManager has loaded and validated
-- the changed file, then applies keyboard and Gamepad input changes live.
local function ReloadConfig(newConfig)

    if type(newConfig) ~= "table"
        or type(newConfig.PageSkip) ~= "table" then

        return false,
            "Reloaded Config.PageSkip is missing or invalid."

    end

    local newForwardButton,
        newBackwardButton =
        GetGamepadPageSkipButtons(
            newConfig.PageSkip
        )

    ------------------------------------------------
    -- Update the shared CommonUI keyboard / Gamepad Action rows.
    ------------------------------------------------
    local inputUpdated,
        inputUpdateError =
        SetPageSkipInputKeys(
            newForwardButton,
            newBackwardButton,
            newConfig.PageSkip.SkipForwardKey,
            newConfig.PageSkip.SkipBackwardKey
        )

    if not inputUpdated then
        return false, inputUpdateError
    end

    Config = newConfig

    Log("Config Reloaded")

    return true

end


-- Checks whether PalBoxPageSkipConfig.lua has changed since the previous
-- manager check. ConfigManager loads and validates the changed file before
-- passing the resulting table to ReloadConfig().
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
-- Vanilla Trigger Guide Source Rows
------------------------------------------------
--
-- WBP_PalStorageMenu:RegisterStaticActionInput() registers
-- PalBoxCursorShortcutPrev / Next with IsDisplayActionBar = true.
-- Their vanilla Gamepad keys are L2 / R2.
--
-- The native CommonUI binding caches its input key at registration time.
-- Therefore PalStorageMenu first registers the vanilla binding with L2/R2,
-- then the narrow post-execution Hook calls this function to set only the
-- conflicting Action Row Gamepad key to None. The native operation
-- remains bound, while the Action Bar no longer has a Trigger key to display.
------------------------------------------------

local function RestoreCursorShortcutGuideRows()

    return
        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_CURSOR_GUIDE_OWNER
        )

end


local function SuppressCursorShortcutTriggerGuideRows(
    worldContextObject
)

    local restored, restoreError =
        RestoreCursorShortcutGuideRows()

    if not restored then
        return false, restoreError
    end

    local suppressLeftTrigger =
        GamepadSkipForwardButton == "Gamepad_LeftTrigger"
        or GamepadSkipBackwardButton == "Gamepad_LeftTrigger"

    local suppressRightTrigger =
        GamepadSkipForwardButton == "Gamepad_RightTrigger"
        or GamepadSkipBackwardButton == "Gamepad_RightTrigger"

    if not suppressLeftTrigger
        and not suppressRightTrigger then
        return true
    end

    if not worldContextObject then
        return false,
            "WorldContextObject is unavailable for Trigger guide row suppression."
    end

    if suppressLeftTrigger then

        local borrowed, borrowError =
            ControllerInput.BorrowActionRow(
                PAGE_SKIP_CURSOR_GUIDE_OWNER,
                worldContextObject,
                ACTION_CURSOR_SHORTCUT_PREVIOUS,
                { Gamepad = "None" }
            )

        if not borrowed then
            RestoreCursorShortcutGuideRows()
            return false, borrowError
        end

    end

    if suppressRightTrigger then

        local borrowed, borrowError =
            ControllerInput.BorrowActionRow(
                PAGE_SKIP_CURSOR_GUIDE_OWNER,
                worldContextObject,
                ACTION_CURSOR_SHORTCUT_NEXT,
                { Gamepad = "None" }
            )

        if not borrowed then
            RestoreCursorShortcutGuideRows()
            return false, borrowError
        end

    end

    DebugLog(
        "Vanilla Trigger guide source rows updated after native binding registration:",
        "LeftTrigger =",
        suppressLeftTrigger and "None" or "unchanged",
        "RightTrigger =",
        suppressRightTrigger and "None" or "unchanged"
    )

    return true

end


local function OnPalStorageRegisterStaticActionInputAfter(
    Context
)

    -- RegisterHook callbacks for Blueprint functions run after the original
    -- function. At this point PalStorageMenu has already cached the vanilla
    -- L2/R2 key in its native CommonUI binding. Only now remove the
    -- conflicting Trigger key from the DataTable row used by the guide.
    local widget = nil

    local okGet, getError =
        pcall(function()
            widget = Context:get()
        end)

    if not okGet
        or not widget then

        Log(
            "Could not resolve PalStorageMenu after RegisterStaticActionInput:",
            getError
        )

        return
    end

    local applied, applyError =
        SuppressCursorShortcutTriggerGuideRows(
            widget
        )

    if not applied then

        Log(
            "Trigger guide row suppression failed:",
            applyError
        )

        return
    end

    if GamepadSkipForwardButton == "Gamepad_LeftTrigger"
        or GamepadSkipForwardButton == "Gamepad_RightTrigger"
        or GamepadSkipBackwardButton == "Gamepad_LeftTrigger"
        or GamepadSkipBackwardButton == "Gamepad_RightTrigger" then

        DebugLog(
            "Trigger guide source-row suppression applied:",
            "Backward =",
            GamepadSkipBackwardButton,
            "Forward =",
            GamepadSkipForwardButton
        )

    end

end

local function OnPalStorageDestruct(
    Context
)

    local restored, restoreError =
        RestoreCursorShortcutGuideRows()

    if not restored then
        DebugLog(
            "Cursor-shortcut row restore on PalStorageMenu Destruct failed:",
            restoreError
        )
    end

end



------------------------------------------------
-- Borrowed PageSkip Action Rows
------------------------------------------------

local function EnsurePageSkipActionRows(
    worldContextObject,
    isPalShop
)

    -- Change only ordering on the four identified vanilla rows. The shared
    -- borrowing layer saves the original priority and restores it on release.
    local vanillaOrder = {
        { "TogglePalDetailSkillInfo", 10 },
        { "PalBoxSendSlot", 20 },
        { "PalBoxDetailStatus", 30 },
        { "PalStorageFavoriteShortcut", 60 },
    }
    for _, item in ipairs(vanillaOrder) do
        local ok, err = ControllerInput.BorrowActionRow(
            PAGE_SKIP_ACTION_OWNER,
            worldContextObject,
            item[1],
            { NavBarPriority = item[2] }
        )
        if not ok then
            ControllerInput.RestoreBorrowedActionRows(PAGE_SKIP_ACTION_OWNER)
            return false, err
        end
    end

    local previousGamepad =
        GamepadSkipBackwardButton

    local nextGamepad =
        GamepadSkipForwardButton

    -- The Pal selling screen registers PalBoxCursorShortcutPrev / Next directly
    -- for L2/R2. Mask only PageSkip's conflicting Trigger keys before the
    -- borrowed rows are first installed. This must not depend on a prior
    -- focus callback because that callback can occur before the hidden bridge
    -- exists.
    if isPalShop == true then

        if previousGamepad == "Gamepad_LeftTrigger"
            or previousGamepad == "Gamepad_RightTrigger" then
            previousGamepad = "None"
        end

        if nextGamepad == "Gamepad_LeftTrigger"
            or nextGamepad == "Gamepad_RightTrigger" then
            nextGamepad = "None"
        end

    end

    local borrowedPrevious,
        previousError =
        ControllerInput.BorrowActionRow(
            PAGE_SKIP_ACTION_OWNER,
            worldContextObject,
            ACTION_PREVIOUS,
            {
                Keyboard =
                    KeyboardSkipBackwardKey,
                Gamepad =
                    previousGamepad,
                NavBarPriority =
                    PAGE_SKIP_PREVIOUS_GUIDE_PRIORITY,
                DisplayName =
                    GUIDE_DISPLAY_NAME,
                HoldDisplayName =
                    GUIDE_DISPLAY_NAME,
            }
        )

    if not borrowedPrevious then
        ControllerInput.RestoreBorrowedActionRows(PAGE_SKIP_ACTION_OWNER)
        return false, previousError
    end

    local borrowedNext,
        nextError =
        ControllerInput.BorrowActionRow(
            PAGE_SKIP_ACTION_OWNER,
            worldContextObject,
            ACTION_NEXT,
            {
                Keyboard =
                    KeyboardSkipForwardKey,
                Gamepad =
                    nextGamepad,
                NavBarPriority =
                    PAGE_SKIP_NEXT_GUIDE_PRIORITY,
                DisplayName =
                    GUIDE_DISPLAY_NAME,
                HoldDisplayName =
                    GUIDE_DISPLAY_NAME,
            }
        )

    if not borrowedNext then

        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

        return false, nextError
    end

    return true

end

------------------------------------------------
-- Hidden Bridge Native Page Step
------------------------------------------------
--
-- WBP_BoxPalListBase's native input path calls ToNextPage()/ToPrevPage() once
-- on Pressed, then calls the same functions from its native hold timer.  The
-- hidden bridge itself has MaxPageNum=1, so its own page remains inert.  We use
-- each native page-step call only as the event that moves the REAL PalBox page
-- by Config.PageSkip.PageOffset.
--
-- Intentional bridge mapping:
--   bridge ToPrevPage() -> PageSkip Next
--   bridge ToNextPage() -> PageSkip Previous
--
-- There is no Lua repeat timer, preview page, Slider->page conversion, or
-- Released-time commit in this path.
------------------------------------------------

local function HandleBridgeNativePageStep(
    Context,
    direction
)

    if not IsCurrentRuntimeGeneration()
        or ControllerFocusOnPageSkipList ~= true then
        return
    end

    local baseWidget = nil

    local okContext =
        pcall(function()
            baseWidget = Context:get()
        end)

    if not okContext
        or not baseWidget then
        return
    end

    -- Fast path normally succeeds because the bridge UObject is retained by
    -- this module. Fall back to FullName matching in case UE4SS supplies a
    -- different Lua wrapper for the same UObject in a hook callback.
    local isBridge =
        BridgeFullNameByObject[baseWidget] ~= nil

    if not isBridge then

        local _, bridgeFullName =
            GetObjectPath(
                baseWidget
            )

        isBridge =
            bridgeFullName ~= nil
            and BridgeFullNameSet[bridgeFullName] ~= nil

    end

    if not isBridge then
        return
    end

    local pageSkip =
        Config
        and Config.PageSkip

    local pageOffset =
        pageSkip
        and pageSkip.PageOffset

    if type(pageOffset) ~= "number"
        or pageOffset <= 0 then
        return
    end

    local signedOffset = nil

    if direction == "Previous" then
        signedOffset = -pageOffset
    elseif direction == "Next" then
        signedOffset = pageOffset
    else
        return
    end

    local objectPath, targetPage =
        MovePalBoxPage(
            signedOffset
        )

    if objectPath then

        DebugLog(
            "[PageSkip]",
            "direction=" .. tostring(direction),
            "offset=" .. tostring(signedOffset),
            "page=" .. tostring(targetPage)
        )

    end

end

------------------------------------------------
-- PalBox Scroll-list Focus
------------------------------------------------

-- Inspect the owning UObject Outer chain once for PageSkip context.
-- Returns whether the list is excluded and whether it belongs to the supported
-- Pal selling screen. Keeping both checks in one traversal avoids repeatedly
-- walking the same Outer chain when slot focus changes.
local function InspectPageSkipBaseContext(
    baseWidget
)

    if not baseWidget then
        return false, false
    end

    local current =
        baseWidget

    local isPalShop = false

    for _ = 1, 12 do

        if not current then
            break
        end

        local className =
            GetClassName(
                current
            )

        if not className then
            break
        end

        if className ==
            "WBP_IngameMenu_PalBoxGlobal_C" then

            return true, isPalShop

        end

        if className ==
            "WBP_Shop_Pal_00_C" then

            isPalShop = true

        end

        if className == "Package" then
            break
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

        current = outer

    end

    return false, isPalShop

end


local function IsPageSkipScrollList(
    scrollList
)

    if not scrollList then
        return false, nil, false
    end

    local widgetTree = nil
    local ownerWidget = nil

    local okOuter =
        pcall(function()

            widgetTree =
                scrollList:GetOuter()

            if widgetTree then

                ownerWidget =
                    widgetTree:GetOuter()

            end

        end)

    if not okOuter
        or not ownerWidget then
        return false, nil, false
    end

    -- Normal PalBox:
    -- WBP_BoxPalListBase_C -> WidgetTree -> WBP_BoxPalScrollList
    --
    -- Base Camp:
    -- WBP_IngameMenu_PalBox_C -> WidgetTree -> WBP_BaseCampPalList
    if GetClassName(
        ownerWidget
    ) ~= "WBP_BoxPalListBase_C" then

        return false, nil, false

    end

    local isExcluded, isPalShop =
        InspectPageSkipBaseContext(
            ownerWidget
        )

    if isExcluded then
        return false, nil, false
    end

    return true, ownerWidget, isPalShop

end


local function HandlePalScrollListFocus(
    Context,
    eventName
)

    if not FocusTrackingEnabled then
        return
    end

    local scrollList = nil

    local okContext =
        pcall(function()

            scrollList =
                Context:get()

        end)

    if not okContext
        or not scrollList then
        return
    end

    ControllerFocusEventGeneration =
        ControllerFocusEventGeneration + 1

    local generation =
        ControllerFocusEventGeneration

    local isPageSkipList,
        ownerWidget,
        isPalShop =
        IsPageSkipScrollList(
            scrollList
        )

    if eventName == "Focused" then

        if isPageSkipList
            and ownerWidget then

            LastActivePalBoxPath =
                GetObjectPath(
                    ownerWidget
                )

        else
            LastActivePalBoxPath = nil
        end

        SetControllerBridgeFocusState(
            isPageSkipList,
            isPageSkipList
                and isPalShop
        )

        return
    end

    if eventName ~= "Unfocused" then
        return
    end

    if not isPageSkipList
        or not ControllerFocusOnPageSkipList then
        return
    end

    ExecuteWithDelay(
        FOCUS_UNFOCUSED_FALLBACK_MS,
        function()

            if not IsCurrentRuntimeGeneration() then
                return
            end

            ExecuteInGameThread(
                function()

                    if not IsCurrentRuntimeGeneration() then
                        return
                    end

                    if generation
                        ~= ControllerFocusEventGeneration then
                        return
                    end

                    SetControllerBridgeFocusState(
                        false,
                        false
                    )

                end
            )

        end
    )

end

------------------------------------------------
-- Hidden WBP_BoxPalListBase Bridge
------------------------------------------------

local function FindAttachPanel(
    worldContextObject
)

    if not worldContextObject then
        return nil
    end

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
            GetClassName(
                outer
            )

        if className == "Package" then
            break
        end

        current = outer

    end

    return nil

end


local function SetPageControlBridgeEnabled(
    bridge,
    enabled
)

    if not bridge then
        return false
    end

    local shouldEnable =
        enabled == true

    if shouldEnable then

        local okEnable, enableError =
            pcall(function()

                -- Expose the bridge's Blueprint-native CommonUI bindings in
                -- the Action Bar. Pal selling-screen Trigger conflicts are handled
                -- per Action Row by ApplyBorrowedPageSkipRows(), which keeps only
                -- the conflicting L2/R2 Gamepad key at None while the Pal selling screen is active.
                --
                -- SetPageControlAction() still creates all native delegates and
                -- registrations inside the original Blueprint. Lua does not pass
                -- or construct any Delegate value.
                bridge.bDisplayInActionBar = true

                -- Preserve the established Left -> Right callback order:
                --   Next callback slot     <- ACTION_PREVIOUS (Left)
                --   Previous callback slot <- ACTION_NEXT     (Right)
                bridge:SetPageControlAction(
                    {
                        Key =
                            FName(
                                ACTION_PREVIOUS
                            ),
                    },
                    {
                        Key =
                            FName(
                                ACTION_NEXT
                            ),
                    }
                )

                bridge.bDisplayInActionBar = false

                bridge:SetVisibility(1)

            end)

        if not okEnable then

            DebugLog(
                "PageSkip CommonUI binding failed:",
                enableError
            )

        end

        return okEnable
    end

    return
        pcall(function()

            bridge:RemovePageControlAction()
            bridge:SetVisibility(1)

        end)

end


SetControllerBridgeFocusState =
    function(
        enabled,
        isPalShop
    )

        local shouldEnable =
            enabled == true

        local shouldTreatAsPalShop =
            shouldEnable
            and isPalShop == true

        if not shouldEnable then
            LastActivePalBoxPath = nil
        end

        local contextChanged =
            ControllerFocusOnPalShop
            ~= shouldTreatAsPalShop

        ControllerFocusOnPageSkipList =
            shouldEnable

        ControllerFocusOnPalShop =
            shouldTreatAsPalShop

        -- Keep the borrowed PageSkip Action Rows synchronized with the current
        -- screen before any native binding is created or rebuilt. On the Pal selling
        -- screen this masks only configured Trigger directions to Gamepad=None.
        if ControllerBridge
            and contextChanged then

            local rowsUpdated, rowsError =
                ApplyBorrowedPageSkipRows()

            if not rowsUpdated then

                DebugLog(
                    "PageSkip Pal selling-screen guide row update failed:",
                    rowsError
                )

                return false
            end

        end

        if not ControllerBridge then

            ControllerBridgeEnabled = false
            return true

        end

        if ControllerBridgeEnabled
            == shouldEnable
            and not contextChanged then
            return true
        end

        -- If PageSkip remains focused but the owning screen changed between a
        -- normal PalBox and the Pal selling screen, rebuild the native bindings so
        -- CommonUI resolves the updated Action Row inputs for the new context.
        if ControllerBridgeEnabled
            and shouldEnable
            and contextChanged then

            local disabled =
                SetPageControlBridgeEnabled(
                    ControllerBridge,
                    false
                )

            if not disabled then
                return false
            end

            ControllerBridgeEnabled = false

        end

        local updated =
            SetPageControlBridgeEnabled(
                ControllerBridge,
                shouldEnable
            )

        if not updated then
            return false
        end

        ControllerBridgeEnabled =
            shouldEnable

        DebugLog(
            "CommonUI PageSkip bridge:",
            shouldEnable
                and "Enabled"
                or "Disabled",
            "PalShop =",
            ControllerFocusOnPalShop
        )

        return true

    end


local function ReleasePageControlBridgeWidget(
    bridge
)

    if not bridge then
        return
    end

    local okValid, isValid =
        pcall(function()
            return bridge:IsValid()
        end)

    if not okValid
        or isValid ~= true then
        return
    end

    ControllerBridgeDestroying = true

    -- Trigger guide visibility is handled through the source Action Rows.
    -- No pooled Action Bar entries need to be modified while releasing the bridge.

    pcall(function()
        bridge:RemovePageControlAction()
    end)

    pcall(function()
        bridge:DeactivateWidget()
    end)

    -- Deactivation releases CommonUI input, but does not remove the hidden
    -- Widget from its parent Panel. Remove it explicitly so repeated screen
    -- transitions do not accumulate inactive bridge children.
    pcall(function()
        bridge:RemoveFromParent()
    end)

    ControllerBridgeDestroying = false

end


local function CreatePageControlBridge(
    worldContextObject
)

    if not worldContextObject then

        return nil,
            "WorldContextObject is unavailable."

    end

    local boxPalListBaseClass, classError =
        GetBoxPalListBaseClass()

    if not boxPalListBaseClass then
        return nil, classError
    end

    -- Determine the screen directly from the real WBP_BoxPalListBase_C used
    -- to create this bridge. This removes any dependency on whether the
    -- slot-focus callback happened before or after bridge construction.
    local _, bridgeIsPalShop =
        InspectPageSkipBaseContext(
            worldContextObject
        )

    local rowsReady, rowError =
        EnsurePageSkipActionRows(
            worldContextObject,
            bridgeIsPalShop
        )

    if not rowsReady then
        return nil, rowError
    end

    local widgetLibrary, libraryError =
        GetWidgetBlueprintLibrary()

    if not widgetLibrary then

        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

        return nil, libraryError
    end

    local owningPlayer = nil

    local okOwner, ownerError =
        pcall(function()

            owningPlayer =
                worldContextObject:GetOwningPlayer()

        end)

    if not okOwner
        or not owningPlayer then

        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

        return nil,
            "Owning Player unavailable: "
            .. tostring(ownerError)
    end

    local bridge = nil

    ControllerBridgeCreating = true

    local okCreate, createError =
        pcall(function()

            bridge =
                widgetLibrary:Create(
                    worldContextObject,
                    boxPalListBaseClass,
                    owningPlayer
                )

        end)

    ControllerBridgeCreating = false

    if not okCreate
        or not bridge then

        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

        return nil,
            "WBP_BoxPalListBase bridge creation failed: "
            .. tostring(createError)
    end

    local okInitializeState,
        initializeStateError =
        pcall(function()

            bridge.MaxPageNum = 1
            bridge.LastSelectedPageNum = 0
            bridge.PageMoveCount_Timer = 0
            bridge.bSkipPage = false

        end)

    if not okInitializeState then

        ReleasePageControlBridgeWidget(
            bridge
        )

        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

        return nil,
            "Bridge page state initialization failed: "
            .. tostring(initializeStateError)
    end

    local attachPanel =
        FindAttachPanel(
            worldContextObject
        )

    if not attachPanel then

        ReleasePageControlBridgeWidget(
            bridge
        )

        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

        return nil,
            "Live parent panel for CommonUI bridge is unavailable."
    end

    ControllerBridgeAttaching = true

    local okAttach, attachError =
        pcall(function()

            attachPanel:AddChild(
                bridge
            )

        end)

    ControllerBridgeAttaching = false

    if not okAttach then

        ReleasePageControlBridgeWidget(
            bridge
        )

        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

        return nil,
            "Failed to attach WBP_BoxPalListBase bridge: "
            .. tostring(attachError)
    end

    pcall(function()

        bridge:SetVisibility(1)

    end)

    local wasActivated = nil

    pcall(function()

        wasActivated =
            bridge:IsActivated()

    end)

    if wasActivated ~= true then

        local okActivate, activateError =
            pcall(function()

                bridge:ActivateWidget()

            end)

        if not okActivate then

            ReleasePageControlBridgeWidget(
                bridge
            )

            ControllerInput.RestoreBorrowedActionRows(
                PAGE_SKIP_ACTION_OWNER
            )

            return nil,
                "ActivateWidget failed: "
                .. tostring(activateError)
        end

    end

    pcall(function()

        bridge:SetVisibility(1)

    end)

    local _, bridgeFullName =
        GetObjectPath(
            bridge
        )

    if not bridgeFullName then

        ReleasePageControlBridgeWidget(
            bridge
        )

        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

        return nil,
            "Hidden WBP_BoxPalListBase name is unavailable."
    end

    BridgeFullNameSet[
        bridgeFullName
    ] = true

    BridgeFullNameByObject[
        bridge
    ] = bridgeFullName

    DebugLog(
        "BoxPalListBase CommonUI bridge created:",
        bridgeFullName
    )

    return bridge

end


local function DestroyPageControlBridge(
    bridge
)

    if not bridge then
        return
    end

    local bridgeFullName =
        BridgeFullNameByObject[
            bridge
        ]

    ReleasePageControlBridgeWidget(
        bridge
    )

    if bridgeFullName then

        BridgeFullNameSet[
            bridgeFullName
        ] = nil

    end

    BridgeFullNameByObject[
        bridge
    ] = nil

    ControllerInput.RestoreBorrowedActionRows(
        PAGE_SKIP_ACTION_OWNER
    )

    DebugLog(
        "BoxPalListBase CommonUI bridge destroyed:",
        bridgeFullName or "<unknown>"
    )

end

------------------------------------------------
-- PageSkip Controller Hook Registration
------------------------------------------------

local function RegisterControllerHooks()

    local registered = {}

    local function Register(name, target, callback)

        local ok, err =
            RegisterManagedHook(
                name,
                target,
                callback
            )

        if ok then
            registered[#registered + 1] = name
            return true
        end

        for i = #registered, 1, -1 do
            UnregisterManagedHook(
                registered[i]
            )
        end

        return false, err

    end

    local ok, err =
        Register(
            "ControllerPageStepNextNative",
            HookTarget.PageStepNext,
            function(Context)

                -- Intentional bridge inversion:
                -- native ToNextPage belongs to the MOD Previous action.
                HandleBridgeNativePageStep(
                    Context,
                    "Previous"
                )

            end
        )

    if not ok then
        return false, err
    end

    ok, err =
        Register(
            "ControllerPageStepPreviousNative",
            HookTarget.PageStepPrevious,
            function(Context)

                -- Native ToPrevPage belongs to the MOD Next action.
                HandleBridgeNativePageStep(
                    Context,
                    "Next"
                )

            end
        )

    if not ok then
        return false, err
    end

    ok, err =
        Register(
            "ControllerScrollFocused",
            HookTarget.ScrollFocused,
            function(Context)

                HandlePalScrollListFocus(
                    Context,
                    "Focused"
                )

            end
        )

    if not ok then
        return false, err
    end

    ok, err =
        Register(
            "ControllerScrollUnfocused",
            HookTarget.ScrollUnfocused,
            function(Context)

                HandlePalScrollListFocus(
                    Context,
                    "Unfocused"
                )

            end
        )

    if not ok then
        return false, err
    end

    return true

end

------------------------------------------------
-- Preset Return State
------------------------------------------------

local function SnapshotPageSkipState()

    if #CurrentPalBoxPaths == 0 then
        return nil
    end

    local paths = {}

    for i, path
        in ipairs(CurrentPalBoxPaths) do

        paths[i] = path

    end

    return {
        Paths = paths,
    }

end


local function RestorePageSkipState(
    savedState
)

    if type(savedState) ~= "table"
        or type(savedState.Paths) ~= "table" then
        return false
    end

    local restoredPaths = {}
    local restoredPathSet = {}
    local bridgeWorldContext = nil

    for _, objectPath
        in ipairs(savedState.Paths) do

        local widget =
            ResolvePalBoxList(
                objectPath
            )

        if widget then

            local visible = false

            local okVisible =
                pcall(function()

                    visible =
                        widget:IsVisible()

                end)

            if okVisible
                and visible == true then

                restoredPathSet[
                    objectPath
                ] = true

                table.insert(
                    restoredPaths,
                    objectPath
                )

                if not bridgeWorldContext then
                    bridgeWorldContext = widget
                end

            end

        end

    end

    if #restoredPaths == 0
        or not bridgeWorldContext then
        return false
    end

    CurrentPalBoxPaths = restoredPaths
    CurrentPalBoxPathSet = restoredPathSet
    LastActivePalBoxPath = nil
    FocusTrackingEnabled = true

    if ControllerBridge then

        DestroyPageControlBridge(
            ControllerBridge
        )

        ControllerBridge = nil
        ControllerBridgeEnabled = false

    end

    if ControllerIntegrationReady
        and not ControllerBridgeCreating then

        local okBridge,
            bridge,
            bridgeError =
            pcall(function()

                return
                    CreatePageControlBridge(
                        bridgeWorldContext
                    )

            end)

        if not okBridge
            or not bridge then

            local errorMessage = nil

            if okBridge then
                errorMessage = bridgeError
            else
                errorMessage = bridge
            end

            Log(
                "Preset return PageSkip bridge restoration failed:",
                errorMessage
            )

            return false
        end

        ControllerBridge = bridge
        ControllerBridgeEnabled = false

        -- Returning from Preset always returns control to the PalBox list.
        -- Do not wait for another OnFocused_Internal callback: that callback
        -- is not guaranteed to fire because the existing PalBox Widget is
        -- reused rather than reconstructed.
        SetControllerBridgeFocusState(
            true,
            false
        )

    end

    DebugLog(
        "PageSkip restored after Preset return"
    )

    return true

end


local function OnPresetPageSkipSetup(
    Context
)

    PresetScreenActive = true

    local currentState =
        SnapshotPageSkipState()

    -- OnSetup and the underlying PalBox Destruct can occur in either order.
    -- Keep whichever valid snapshot is available in one transition state.
    if currentState then
        PresetTransitionState = currentState
    end

end


local function OnPresetPageSkipDestruct(
    Context
)

    PresetScreenActive = false

    local savedState =
        PresetTransitionState

    PresetTransitionState = nil

    if not savedState then
        return
    end

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

                    local restored =
                        RestorePageSkipState(
                            savedState
                        )

                    if restored then

                        DebugLog(
                            "PageSkip restored after Preset return"
                        )

                    else

                        DebugLog(
                            "PageSkip Preset return target unavailable"
                        )

                    end

                end
            )

        end
    )

end


-- ----------------------------------------------
-- PalBoxList Registration
-- ----------------------------------------------
--
-- Registers the WBP_BoxPalListBase_C that triggered SetMaxPageNum as a
-- transient object path string in CurrentPalBoxPaths.
--
-- No live real-PalBox UObject reference is retained. Native repeat resolves
-- only transient object paths with StaticFindObject().
-- ----------------------------------------------
local function OnPalBoxSetMaxPageNum(
    Context,
    MaxPage
)

        -- A hidden WBP_BoxPalList used only for CommonUI input executes
        -- SetMaxPageNum() during Construct -> Setup(). It must never become
        -- a page-movement candidate for the normal PageSkip movement path.
        if ControllerBridgeCreating
            or ControllerBridgeAttaching then
            return
        end

        local okGet, widget =
            pcall(function()
                return Context:get()
            end)

        if not okGet or not widget then
            return
        end

        local objectPath,
            fullName =
            GetObjectPath(
                widget
            )

        if not objectPath then
            return
        end

        -- A newly initialized real PalBox supersedes any stale return snapshot.
        if not PresetScreenActive then
            PresetTransitionState = nil
        end

        local alreadyRegistered =
            CurrentPalBoxPathSet[
                objectPath
            ] == true

        ------------------------------------------------
        -- Exclusion is evaluated only when a real PalBoxList is first seen.
        ------------------------------------------------
        --
        -- Excluded lists are not stored as movement candidates and do not
        -- create the CommonUI bridge.
        ------------------------------------------------

        if not alreadyRegistered then

            if IsExcludedWidgetFullName(
                fullName
            ) then
                return
            end

            CurrentPalBoxPathSet[
                objectPath
            ] = true

            table.insert(
                CurrentPalBoxPaths,
                objectPath
            )

        end

        -- PageSkip focus hooks can now do useful work.
        FocusTrackingEnabled = true

        ------------------------------------------------
        -- CommonUI input bridge
        ------------------------------------------------
        --
        -- Create one native CommonUI input bridge from the first supported
        -- real WBP_BoxPalListBase_C that opens. The borrowed Actions contain
        -- both the configured keyboard and Gamepad inputs.
        --
        -- This attempt is intentionally outside the first-registration block:
        -- if bridge creation ever fails, a later SetMaxPageNum call for the
        -- same real list can retry without duplicating the stored path.
        ------------------------------------------------

        if ControllerIntegrationReady
            and not ControllerBridge
            and not ControllerBridgeCreating then

            local okBridge,
                bridge,
                bridgeError =
                pcall(function()

                    return
                        CreatePageControlBridge(
                            widget
                        )

                end)

            if okBridge and bridge then

                ControllerBridge = bridge
                ControllerBridgeEnabled = false

                -- A list-level focus callback may already have fired while
                -- the PalBox was constructing. Apply that remembered state
                -- without scanning Widget descendants.
                SetControllerBridgeFocusState(
                    ControllerFocusOnPageSkipList,
                    ControllerFocusOnPalShop
                )

                DebugLog(
                    "CommonUI PageSkip Ready"
                )

            else

                local errorMessage = nil

                if okBridge then
                    errorMessage = bridgeError
                else
                    errorMessage = bridge
                end

                Log(
                    "CommonUI bridge creation failed:",
                    errorMessage
                )

            end

        end

end

-- ----------------------------------------------
-- Reset the list when the PalBox is destroyed.
-- ----------------------------------------------
local function OnPalBoxDestruct(
    Context
)

        if ControllerBridgeDestroying then
            return
        end

        -- Ignore Destruct from the MOD-created hidden bridge itself.
        local okContext, widget =
            pcall(function()

                return Context:get()

            end)

        if okContext
            and widget then

            local _, fullName =
                GetObjectPath(
                    widget
                )

            if fullName
                and BridgeFullNameSet[
                    fullName
                ] then

                return

            end

        end

        if #CurrentPalBoxPaths == 0
            and not ControllerBridge then
            return
        end

        local returnState =
            SnapshotPageSkipState()

        if returnState then
            PresetTransitionState = returnState
        end

        CurrentPalBoxPaths = {}
        CurrentPalBoxPathSet = {}
        LastActivePalBoxPath = nil

        FocusTrackingEnabled = false
        ControllerFocusOnPageSkipList = false
        ControllerFocusOnPalShop = false

        if ControllerBridge then

            DestroyPageControlBridge(
                ControllerBridge
            )

            ControllerBridge = nil
            ControllerBridgeEnabled = false

        end

        ControllerFocusEventGeneration =
            ControllerFocusEventGeneration + 1

end

------------------------------------------------
-- PalBox Hook Registration
------------------------------------------------
--
-- WBP_BoxPalListBase is not normally loaded until a PalBox-related screen
-- opens. Retrying RegisterHook() every second until that happens can produce
-- periodic work on the game thread.
--
-- Load the Blueprint once, then register only the SetMaxPageNum / Destruct
-- lifecycle hooks once. No per-slot OnCreatedSlot hook or retry loop is used.
------------------------------------------------

local function RegisterPalBoxHooksOnce()

    ExecuteInGameThread(
        function()

            if not IsCurrentRuntimeGeneration() then
                return
            end

            ------------------------------------------------
            -- One-time PageSkip Blueprint preload
            ------------------------------------------------
            --
            -- Keep these feature-specific assets here rather than in
            -- ControllerInput. The direct hidden WBP_BoxPalListBase class is
            -- loaded before PalBox opening.
            local okLoad, loadError =
                pcall(function()

                    LoadAsset(
                        PAL_BOX_LIST_BASE_ASSET
                    )

                    LoadAsset(
                        PAL_CHARACTER_SCROLL_LIST_ASSET
                    )

                    LoadAsset(
                        PAL_BOX_PRESET_ASSET
                    )

                    LoadAsset(
                        PAL_STORAGE_MENU_ASSET
                    )

                end)

            if not okLoad then

                Log(
                    "Failed to preload PageSkip CommonUI assets:",
                    loadError
                )

                return
            end

            local bridgeClass, classError =
                GetBoxPalListBaseClass()

            if not bridgeClass then

                Log(
                    "Failed to resolve WBP_BoxPalListBase_C:",
                    classError
                )

                return
            end

            ------------------------------------------------
            -- Shared ControllerInput utility
            ------------------------------------------------

            local controllerReady,
                controllerError =
                ControllerInput.Initialize()

            if not controllerReady then

                Log(
                    "ControllerInput initialization failed:",
                    controllerError
                )

            else

                local controllerHooksReady,
                    controllerHooksError =
                    RegisterControllerHooks()

                if not controllerHooksReady then

                    Log(
                        "PageSkip CommonUI hook registration failed:",
                        controllerHooksError
                    )

                else

                    ControllerIntegrationReady = true

                end

            end

            ------------------------------------------------
            -- PalStorageMenu cursor-shortcut guide source rows
            ------------------------------------------------
            --
            -- This Hook is limited to one Blueprint function. Blueprint
            -- RegisterHook callbacks run after the original function, so the
            -- vanilla L2/R2 binding is already cached before the callback
            -- removes only the conflicting Trigger key from the guide row.
            ------------------------------------------------

            local okStaticInput, staticInputError =
                RegisterManagedHook(
                    "PalStorageRegisterStaticActionInput",
                    HookTarget.PalStorageRegisterStaticActionInput,
                    OnPalStorageRegisterStaticActionInputAfter
                )

            if not okStaticInput then

                Log(
                    "PalStorage RegisterStaticActionInput hook registration failed:",
                    staticInputError
                )

            end

            local okStorageDestruct, storageDestructError =
                RegisterManagedHook(
                    "PalStorageDestruct",
                    HookTarget.PalStorageDestruct,
                    OnPalStorageDestruct
                )

            if not okStorageDestruct then

                Log(
                    "PalStorage Destruct hook registration failed:",
                    storageDestructError
                )

            end

            ------------------------------------------------
            -- Real PalBox lifecycle
            ------------------------------------------------

            local okSetMax, setMaxError =
                RegisterManagedHook(
                    "PalBoxSetMaxPageNum",
                    HookTarget.PalBoxSetMaxPageNum,
                    OnPalBoxSetMaxPageNum
                )

            if not okSetMax then

                Log(
                    "SetMaxPageNum hook registration failed:",
                    setMaxError
                )

                return
            end

            local okDestruct, destructError =
                RegisterManagedHook(
                    "PalBoxDestruct",
                    HookTarget.PalBoxDestruct,
                    OnPalBoxDestruct
                )

            if not okDestruct then

                UnregisterManagedHook(
                    "PalBoxSetMaxPageNum"
                )

                Log(
                    "Destruct hook registration failed:",
                    destructError
                )

                return
            end

            local okPresetSetup, presetSetupError =
                RegisterManagedHook(
                    "PresetPageSkipSetup",
                    HookTarget.PresetOnSetup,
                    OnPresetPageSkipSetup
                )

            if not okPresetSetup then

                Log(
                    "Preset OnSetup hook registration failed:",
                    presetSetupError
                )

            end

            local okPresetDestruct, presetDestructError =
                RegisterManagedHook(
                    "PresetPageSkipDestruct",
                    HookTarget.PresetDestruct,
                    OnPresetPageSkipDestruct
                )

            if not okPresetDestruct then

                Log(
                    "Preset Destruct hook registration failed:",
                    presetDestructError
                )

            end

            DebugLog(
                "PalBox lifecycle, Preset return, and CommonUI PageSkip hooks registered."
            )

        end
    )

end

------------------------------------------------
-- Restart Cleanup
------------------------------------------------

local function CleanupPreviousExecution()

    PageSkipRuntime.Generation =
        (tonumber(PageSkipRuntime.Generation) or 0) + 1

    PageSkipRuntime.PageSkipKeyHandler = nil

    -- Release execution-local callback upvalues before touching the bridge.
    -- Native Hook wrappers are generation/key trampolines only.
    PageSkipRuntime.Dispatchers = {}

    ControllerFocusEventGeneration =
        ControllerFocusEventGeneration + 1

    ControllerFocusOnPageSkipList = false
    ControllerFocusOnPalShop = false
    FocusTrackingEnabled = false
    ControllerIntegrationReady = false
    ControllerBridgeAttaching = false
    ControllerBridgeCreating = false
    ControllerBridgeDestroying = false
    PresetTransitionState = nil
    PresetScreenActive = false
    LastActivePalBoxPath = nil

    -- Detach all managed callbacks before releasing the bridge. Generation is
    -- already invalid, so callbacks that survive UnregisterHook() are inert.
    UnregisterAllManagedHooks()
    PageSkipRuntime.HookHistory = {}

    if ControllerBridge then

        pcall(function()

            DestroyPageControlBridge(
                ControllerBridge
            )

        end)

        ControllerBridge = nil
        ControllerBridgeEnabled = false

    else

        -- Fallback in case bridge creation failed after borrowing rows.
        ControllerInput.RestoreBorrowedActionRows(
            PAGE_SKIP_ACTION_OWNER
        )

    end

    BridgeFullNameSet = {}
    BridgeFullNameByObject = {}

    -- Restore any PalStorageMenu cursor-shortcut rows modified by this
    -- execution. Action Bar pooled entries are never modified here.
    pcall(function()
        RestoreCursorShortcutGuideRows()
    end)

end


PageSkipRuntime.Cleanup =
    CleanupPreviousExecution


RegisterPalBoxHooksOnce()


-- ----------------------------------------------
-- Config Watch
-- ----------------------------------------------
-- Check PalBoxPageSkipConfig.lua every second.
-- PageOffset and keyboard / Gamepad input changes are applied directly to
-- the CommonUI Action rows without restarting the game or the MOD.
local function ConfigWatchLoop()

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

ConfigWatchLoop()

------------------------------------------------
-- ControllerInput
-- Shared Controller Input Utilities
-- Version: 1.0.1
-- Date: 2026-09-08
-- Author: ikusamaou
------------------------------------------------
--
-- Shared infrastructure for MOD features that integrate with Palworld's
-- CommonUI input system.
--
-- This module intentionally does NOT contain feature-specific behavior.
-- PalBox PageSkip, PalIconInfo DisplayMode switching, and any future feature
-- own their Widget bridges, focus rules, callback hooks, supported keys, and
-- conflict handling.
--
-- Shared responsibilities:
--
--   * temporary borrowing / updating / restoration of DT_UIInputAction rows
--   * UE4SS keyboard key-code to Unreal FKey name conversion
-- No PalBox Widget class, PageSkip direction, Trigger rule, or focus policy is
-- defined here.
------------------------------------------------
------------------------------------------------
-- Changelog
------------------------------------------------
-- Version 1.0.1 - 2026-09-08
-- - Corrected UI Action row write order so DisplayName updates do not clear the Keyboard input assignment.
-- - Added optional NavBarPriority updates for deterministic CommonUI Action Bar ordering.
--
-- Version 1.0.0 - 2026-09-06
-- - Added shared CommonUI input infrastructure for keyboard/Gamepad action binding.
-- - Added temporary DT_UIInputAction row borrowing, updating, and restoration.
-- - Added keyboard FKey conversion.
------------------------------------------------

local ControllerInput = {}

------------------------------------------------
-- Restart-safe Runtime
------------------------------------------------

local CONTROLLER_RUNTIME_KEY =
    "__PalIconInfo_ControllerInput_Runtime"

local ControllerRuntime =
    rawget(
        _G,
        CONTROLLER_RUNTIME_KEY
    )

if type(ControllerRuntime) ~= "table" then

    ControllerRuntime = {}

    rawset(
        _G,
        CONTROLLER_RUNTIME_KEY,
        ControllerRuntime
    )

end


-- A new module execution replaces the previous one cleanly.
local previousCleanup =
    ControllerRuntime.Cleanup

if type(previousCleanup) == "function" then
    pcall(previousCleanup)
end

ControllerRuntime.Cleanup = nil

------------------------------------------------
-- Logging
------------------------------------------------

local DEBUG = false

local function DebugLog(...)
    if DEBUG then
        print("[ControllerInput][Debug]", ...)
    end
end

function ControllerInput.SetDebug(enabled)
    DEBUG = enabled == true
end

------------------------------------------------
-- Native Paths
------------------------------------------------

local PAL_UTILITY =
    "/Script/Pal.Default__PalUtility"

------------------------------------------------
-- State
------------------------------------------------

local PalUtility = nil
local UIInputActionDataTable = nil

-- One action row may be borrowed by only one feature at a time.
--
-- No row UObject is retained. Only the original scalar/string values and the
-- owner key are stored; the row is reacquired from the DataTable when needed.
local BorrowedRows = {}

-- ownerKey -> { [actionName] = true }
local BorrowedActionsByOwner = {}

local Initialized = false

------------------------------------------------
-- Native Object Access
------------------------------------------------

local function GetPalUtility()

    if PalUtility then
        return PalUtility
    end

    local ok, result =
        pcall(function()

            return StaticFindObject(
                PAL_UTILITY
            )

        end)

    if not ok
        or not result then

        return nil,
            "PalUtility is unavailable."

    end

    PalUtility = result

    return PalUtility

end


local function GetUIInputActionDataTable(
    worldContextObject
)

    if UIInputActionDataTable then
        return UIInputActionDataTable
    end

    if not worldContextObject then
        return nil,
            "WorldContextObject is unavailable."
    end

    local palUtility, utilityError =
        GetPalUtility()

    if not palUtility then
        return nil, utilityError
    end

    local okMaster, masterDataTables =
        pcall(function()

            return palUtility:GetMasterDataTables(
                worldContextObject
            )

        end)

    if not okMaster
        or not masterDataTables then

        return nil,
            "PalMasterDataTables is unavailable."

    end

    local okTable, dataTable =
        pcall(function()

            return masterDataTables.UIInputActionDataTable

        end)

    if not okTable
        or not dataTable then

        return nil,
            "UIInputActionDataTable is unavailable."

    end

    UIInputActionDataTable = dataTable

    return UIInputActionDataTable

end

------------------------------------------------
-- Utility
------------------------------------------------

-- Convert the Windows virtual-key codes defined in Key.lua into Unreal FKey
-- names used by DT_UIInputAction. The same numeric values are also compatible
-- with UE4SS RegisterKeyBind when a keyboard-only binding is required.
--
-- Alphanumeric and function keys are resolved algorithmically. Other common
-- keyboard / mouse keys use the fixed Unreal FKey names below.
local KEYBOARD_FKEY_BY_KEY_CODE = {

    [0x01] = "LeftMouseButton",
    [0x02] = "RightMouseButton",
    [0x04] = "MiddleMouseButton",
    [0x05] = "ThumbMouseButton",
    [0x06] = "ThumbMouseButton2",

    [0x08] = "BackSpace",
    [0x09] = "Tab",
    [0x0D] = "Enter",
    [0x10] = "LeftShift",
    [0x11] = "LeftControl",
    [0x12] = "LeftAlt",
    [0x13] = "Pause",
    [0x14] = "CapsLock",
    [0x1B] = "Escape",
    [0x20] = "SpaceBar",
    [0x21] = "PageUp",
    [0x22] = "PageDown",
    [0x23] = "End",
    [0x24] = "Home",
    [0x25] = "Left",
    [0x26] = "Up",
    [0x27] = "Right",
    [0x28] = "Down",
    [0x2C] = "PrintScreen",
    [0x2D] = "Insert",
    [0x2E] = "Delete",

    [0x60] = "NumPadZero",
    [0x61] = "NumPadOne",
    [0x62] = "NumPadTwo",
    [0x63] = "NumPadThree",
    [0x64] = "NumPadFour",
    [0x65] = "NumPadFive",
    [0x66] = "NumPadSix",
    [0x67] = "NumPadSeven",
    [0x68] = "NumPadEight",
    [0x69] = "NumPadNine",
    [0x6A] = "Multiply",
    [0x6B] = "Add",
    [0x6D] = "Subtract",
    [0x6E] = "Decimal",
    [0x6F] = "Divide",

    [0x90] = "NumLock",
    [0x91] = "ScrollLock",

    [0xA0] = "LeftShift",
    [0xA1] = "RightShift",
    [0xA2] = "LeftControl",
    [0xA3] = "RightControl",
    [0xA4] = "LeftAlt",
    [0xA5] = "RightAlt",

    [0xBA] = "Semicolon",
    [0xBB] = "Equals",
    [0xBC] = "Comma",
    [0xBD] = "Hyphen",
    [0xBE] = "Period",
    [0xBF] = "Slash",
    [0xC0] = "Tilde",
    [0xDB] = "LeftBracket",
    [0xDC] = "Backslash",
    [0xDD] = "RightBracket",
    [0xDE] = "Apostrophe",

}

local NUMBER_ROW_FKEY_NAMES = {
    "Zero",
    "One",
    "Two",
    "Three",
    "Four",
    "Five",
    "Six",
    "Seven",
    "Eight",
    "Nine",
}


function ControllerInput.ResolveKeyboardKeyName(
    keyCode
)

    if type(keyCode) ~= "number" then
        return nil,
            "Keyboard key code must be a number."
    end

    keyCode =
        math.floor(
            keyCode
        )

    if keyCode >= 0x41
        and keyCode <= 0x5A then

        return string.char(
            keyCode
        )

    end

    if keyCode >= 0x30
        and keyCode <= 0x39 then

        return NUMBER_ROW_FKEY_NAMES[
            keyCode - 0x30 + 1
        ]

    end

    if keyCode >= 0x70
        and keyCode <= 0x87 then

        return "F"
            .. tostring(
                keyCode - 0x70 + 1
            )

    end

    local keyName =
        KEYBOARD_FKEY_BY_KEY_CODE[
            keyCode
        ]

    if keyName then
        return keyName
    end

    return nil,
        "Unsupported keyboard key code: "
        .. tostring(keyCode)

end


local function MakeFKey(
    keyName
)

    if type(keyName) ~= "string"
        or keyName == "" then
        return nil
    end

    local ok, result =
        pcall(function()

            return {
                KeyName = FName(
                    keyName
                ),
            }

        end)

    if not ok
        or not result then
        return nil
    end

    return result

end


local function GetFKeyName(
    key
)

    if not key
        or not key.KeyName then
        return nil
    end

    local ok, result =
        pcall(function()

            return key.KeyName:ToString()

        end)

    if not ok then
        return nil
    end

    return result

end


local function GetFTextString(
    text
)

    if not text then
        return ""
    end

    local ok, result =
        pcall(function()

            return text:ToString()

        end)

    if not ok
        or result == nil then
        return ""
    end

    return result

end


------------------------------------------------
-- UI Action Row Borrowing
------------------------------------------------

local function FindActionRow(
    actionName
)

    if not UIInputActionDataTable then
        return nil
    end

    local okFind, row =
        pcall(function()

            return UIInputActionDataTable:FindRow(
                actionName
            )

        end)

    if not okFind then
        return nil
    end

    return row

end


local function ApplyActionRow(
    actionName,
    definition
)

    local row =
        FindActionRow(
            actionName
        )

    if not row then
        return false,
            "UI Action row unavailable: "
            .. tostring(actionName)
    end

    definition =
        type(definition) == "table"
        and definition
        or {}

    local keyboardKeyName =
        definition.Keyboard

    local gamepadKeyName =
        definition.Gamepad

    local keyboardKey = nil
    local gamepadKey = nil

    if keyboardKeyName ~= nil then

        keyboardKey =
            MakeFKey(
                keyboardKeyName
            )

        if not keyboardKey then
            return false,
                "Failed to create Keyboard FKey for "
                .. tostring(actionName)
        end

    end

    if gamepadKeyName ~= nil then

        gamepadKey =
            MakeFKey(
                gamepadKeyName
            )

        if not gamepadKey then
            return false,
                "Failed to create Gamepad FKey for "
                .. tostring(actionName)
        end

    end

    local okApply, applyError =
        pcall(function()

            ------------------------------------------------
            -- Text fields first
            ------------------------------------------------
            --
            -- UE4SS / FCommonInputActionDataBase behavior confirmed in-game:
            -- assigning HoldDisplayName after KeyboardInputTypeInfo.Key resets
            -- the Keyboard key to None.
            --
            -- Therefore DisplayName / HoldDisplayName must be written before
            -- the input keys, and Keyboard / Gamepad are always written last.
            ------------------------------------------------

            if definition.DisplayName ~= nil then

                row.DisplayName =
                    FText(
                        tostring(
                            definition.DisplayName
                        )
                    )

            end

            if definition.HoldDisplayName ~= nil then

                row.HoldDisplayName =
                    FText(
                        tostring(
                            definition.HoldDisplayName
                        )
                    )

            end

            -- Optional explicit Action Bar ordering. Keep all metadata
            -- writes ahead of Keyboard/Gamepad keys.
            if definition.NavBarPriority ~= nil then
                row.NavBarPriority = definition.NavBarPriority
            end

            ------------------------------------------------
            -- Input keys last
            ------------------------------------------------

            if keyboardKey then

                row.KeyboardInputTypeInfo.Key =
                    keyboardKey

            end

            if gamepadKey then

                row.DefaultGamepadInputTypeInfo.Key =
                    gamepadKey

            end

        end)

    if not okApply then
        return false,
            tostring(applyError)
    end

    return true

end


local function RestoreBorrowedAction(
    actionName
)

    local borrowed =
        BorrowedRows[
            actionName
        ]

    if type(borrowed) ~= "table" then
        return true
    end

    local original =
        borrowed.Original

    if type(original) ~= "table" then

        BorrowedRows[
            actionName
        ] = nil

        return true

    end

    local restored, restoreError =
        ApplyActionRow(
            actionName,
            {
                Keyboard =
                    original.Keyboard,

                Gamepad =
                    original.Gamepad,

                DisplayName =
                    original.DisplayName,

                HoldDisplayName =
                    original.HoldDisplayName,

                NavBarPriority =
                    original.NavBarPriority,
            }
        )

    if not restored then
        return false, restoreError
    end

    local ownerKey =
        borrowed.Owner

    BorrowedRows[
        actionName
    ] = nil

    local ownerActions =
        BorrowedActionsByOwner[
            ownerKey
        ]

    if type(ownerActions) == "table" then

        ownerActions[
            actionName
        ] = nil

        if next(ownerActions) == nil then

            BorrowedActionsByOwner[
                ownerKey
            ] = nil

        end

    end

    DebugLog(
        "UI Action row restored:",
        actionName
    )

    return true

end


function ControllerInput.BorrowActionRow(
    ownerKey,
    worldContextObject,
    actionName,
    definition
)

    if type(ownerKey) ~= "string"
        or ownerKey == "" then

        return false,
            "ownerKey must be a non-empty string."

    end

    if type(actionName) ~= "string"
        or actionName == "" then

        return false,
            "actionName must be a non-empty string."

    end

    local initialized, initializationError =
        ControllerInput.Initialize()

    if not initialized then
        return false, initializationError
    end

    local dataTable, tableError =
        GetUIInputActionDataTable(
            worldContextObject
        )

    if not dataTable then
        return false, tableError
    end

    local existing =
        BorrowedRows[
            actionName
        ]

    if existing then

        if existing.Owner ~= ownerKey then

            return false,
                "UI Action row is already borrowed by another owner: "
                .. tostring(actionName)

        end

        -- Same owner: treat another BorrowActionRow call as an update.
        return
            ApplyActionRow(
                actionName,
                definition
            )

    end

    local row =
        FindActionRow(
            actionName
        )

    if not row then
        return false,
            "UI Action row unavailable: "
            .. tostring(actionName)
    end

    local originalKeyboard =
        GetFKeyName(
            row.KeyboardInputTypeInfo.Key
        )

    local originalGamepad =
        GetFKeyName(
            row.DefaultGamepadInputTypeInfo.Key
        )

    if not originalKeyboard
        or not originalGamepad then

        return false,
            "Failed to read original keys for "
            .. tostring(actionName)

    end

    local original = {
        Keyboard =
            originalKeyboard,

        Gamepad =
            originalGamepad,

        DisplayName =
            GetFTextString(
                row.DisplayName
            ),

        HoldDisplayName =
            GetFTextString(
                row.HoldDisplayName
            ),

        NavBarPriority =
            row.NavBarPriority,
    }

    BorrowedRows[
        actionName
    ] = {
        Owner = ownerKey,
        Original = original,
    }

    local ownerActions =
        BorrowedActionsByOwner[
            ownerKey
        ]

    if type(ownerActions) ~= "table" then

        ownerActions = {}

        BorrowedActionsByOwner[
            ownerKey
        ] = ownerActions

    end

    ownerActions[
        actionName
    ] = true

    local applied, applyError =
        ApplyActionRow(
            actionName,
            definition
        )

    if not applied then

        -- The original row is still present in memory because this first
        -- configuration failed before a successful lease was established.
        BorrowedRows[
            actionName
        ] = nil

        ownerActions[
            actionName
        ] = nil

        if next(ownerActions) == nil then

            BorrowedActionsByOwner[
                ownerKey
            ] = nil

        end

        return false, applyError
    end

    DebugLog(
        "UI Action row borrowed:",
        actionName,
        "Owner =",
        ownerKey
    )

    return true

end


function ControllerInput.UpdateBorrowedActionRow(
    ownerKey,
    actionName,
    definition
)

    local borrowed =
        BorrowedRows[
            actionName
        ]

    if type(borrowed) ~= "table"
        or borrowed.Owner ~= ownerKey then

        return false,
            "UI Action row is not borrowed by this owner: "
            .. tostring(actionName)

    end

    return
        ApplyActionRow(
            actionName,
            definition
        )

end


function ControllerInput.RestoreBorrowedActionRows(
    ownerKey
)

    if ownerKey == nil then

        local actions = {}

        for actionName, _
            in pairs(BorrowedRows) do

            table.insert(
                actions,
                actionName
            )

        end

        local allRestored = true
        local firstError = nil

        for _, actionName
            in ipairs(actions) do

            local restored, restoreError =
                RestoreBorrowedAction(
                    actionName
                )

            if not restored then

                allRestored = false

                if not firstError then
                    firstError = restoreError
                end

            end

        end

        return allRestored, firstError
    end

    local ownerActions =
        BorrowedActionsByOwner[
            ownerKey
        ]

    if type(ownerActions) ~= "table" then
        return true
    end

    local actions = {}

    for actionName, _
        in pairs(ownerActions) do

        table.insert(
            actions,
            actionName
        )

    end

    local allRestored = true
    local firstError = nil

    for _, actionName
        in ipairs(actions) do

        local restored, restoreError =
            RestoreBorrowedAction(
                actionName
            )

        if not restored then

            allRestored = false

            if not firstError then
                firstError = restoreError
            end

        end

    end

    return allRestored, firstError

end

------------------------------------------------
-- Initialization
------------------------------------------------

function ControllerInput.Initialize()

    if Initialized then
        return true
    end

    Initialized = true

    return true

end

------------------------------------------------
-- Shutdown
------------------------------------------------

function ControllerInput.Shutdown()

    ControllerInput.RestoreBorrowedActionRows()

    Initialized = false

end


ControllerRuntime.Cleanup =
    function()
        ControllerInput.Shutdown()
    end

return ControllerInput

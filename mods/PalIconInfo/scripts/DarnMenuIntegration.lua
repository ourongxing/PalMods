------------------------------------------------
-- DarnMenuIntegration
-- Version: 1.0.1
-- Date: 2026-09-08
-- Author: ikusamaou
--
-- Optional DarnMenu integration support for PalIconInfo.
--
-- This module intentionally contains no ConfigManager or MOD runtime
-- responsibilities. It provides:
--   - @darn annotation parsing from bundled config sources
--   - DisplayMode model extraction
--   - Source-preserving DisplayMode edits
--   - DarnMenu schema generation/registration without a hard dependency
--   - Synchronization between DarnMenu staging values and real config files
--
-- DarnMenu schema rendering/registration is kept separate from the
-- parser/editor layer so PalIconInfo never requires DarnMenu to run.
-- ConfigManager only notifies this module after a successful config load;
-- this module never requires ConfigManager and receives manager instances
-- through RegisterConfigManager().
------------------------------------------------
------------------------------------------------
-- Changelog
------------------------------------------------
-- Version 1.0.1 - 2026-09-08
-- - Made DarnMenu polling restart-safe so delayed watch loops from a previous MOD execution stop automatically.
-- - Removed an unused internal string helper.
--
-- Version 1.0.0 - 2026-09-06
-- - Added optional DarnMenu integration for PalIconInfo and PalBoxPageSkip configuration.
-- - Added schema generation from config annotations and source-preserving synchronization with user config files.
-- - Added DisplayMode keyboard/Gamepad editing while preserving the paired Gamepad assignment.
------------------------------------------------

local DarnMenuIntegration = {}

------------------------------------------------
-- Restart-safe Runtime
------------------------------------------------

local DARN_MENU_RUNTIME_KEY =
    "__PalIconInfo_DarnMenuIntegration_Runtime"

local DarnMenuRuntime =
    rawget(
        _G,
        DARN_MENU_RUNTIME_KEY
    )

if type(DarnMenuRuntime) ~= "table" then

    DarnMenuRuntime = {
        Generation = 0,
    }

    rawset(
        _G,
        DARN_MENU_RUNTIME_KEY,
        DarnMenuRuntime
    )

end

DarnMenuRuntime.Generation =
    (tonumber(DarnMenuRuntime.Generation) or 0) + 1

local RuntimeGeneration =
    DarnMenuRuntime.Generation

local function IsCurrentRuntimeGeneration()

    return
        DarnMenuRuntime.Generation
        == RuntimeGeneration

end

------------------------------------------------
-- Logging
------------------------------------------------

local function Log(options, ...)

    if options
        and type(options.Log) == "function" then

        local ok =
            pcall(
                options.Log,
                ...
            )

        if ok then
            return
        end

    end

    print("[DarnMenuIntegration]", ...)

end


------------------------------------------------
-- Basic String Utilities
------------------------------------------------

local function Trim(value)

    if type(value) ~= "string" then
        return value
    end

    return value:match("^%s*(.-)%s*$")

end


local function HumanizeIdentifier(value)

    if type(value) ~= "string" then
        return ""
    end

    local result =
        value:gsub("_", " ")

    result =
        result:gsub(
            "([a-z0-9])([A-Z])",
            "%1 %2"
        )

    result =
        result:gsub(
            "([A-Z])([A-Z][a-z])",
            "%1 %2"
        )

    return result

end


local function IsSimpleMemberExpression(value)

    if type(value) ~= "string" then
        return false
    end

    local partCount = 0

    for part in value:gmatch("[^.]+") do

        if not part:match(
            "^[%a_][%w_]*$"
        ) then

            return false
        end

        partCount =
            partCount + 1

    end

    return partCount >= 2
        and not value:find("..", 1, true)
        and value:sub(1, 1) ~= "."
        and value:sub(-1) ~= "."

end


local function StripTrailingComment(line)

    local quote = nil
    local escaped = false
    local pos = 1

    while pos <= #line do

        local c =
            line:sub(
                pos,
                pos
            )

        local two =
            line:sub(
                pos,
                pos + 1
            )

        if quote then

            if escaped then
                escaped = false

            elseif c == "\\" then
                escaped = true

            elseif c == quote then
                quote = nil
            end

            pos = pos + 1

        else

            if c == "\""
                or c == "'" then

                quote = c
                pos = pos + 1

            elseif two == "--" then

                return line:sub(
                    1,
                    pos - 1
                )

            else
                pos = pos + 1
            end

        end

    end

    return line

end


-- Split an inline annotation such as:
--
--   Left = 10, -- @darn min=-500; max=500; step=0.5
--
-- Returns the code portion and annotation metadata text. A normal
-- trailing comment is ignored and returns nil for the annotation.
local function SplitInlineDarnAnnotation(line)

    local quote = nil
    local escaped = false
    local pos = 1

    while pos <= #line do

        local c = line:sub(pos, pos)
        local two = line:sub(pos, pos + 1)

        if quote then

            if escaped then
                escaped = false

            elseif c == "\\" then
                escaped = true

            elseif c == quote then
                quote = nil
            end

            pos = pos + 1

        else

            if c == "\"" or c == "'" then

                quote = c
                pos = pos + 1

            elseif two == "--" then

                local comment = Trim(line:sub(pos + 2))
                local annotation = comment:match("^@darn%s*(.-)%s*$")

                if annotation ~= nil then

                    local codePart = line:sub(1, pos - 1)

                    -- A line containing only "-- @darn" is the legacy
                    -- standalone form, not an inline annotation.
                    if Trim(codePart) == "" then
                        return nil, nil
                    end

                    return codePart, annotation
                end

                return nil, nil

            else
                pos = pos + 1
            end

        end

    end

    return nil, nil

end


------------------------------------------------
-- @darn Metadata
------------------------------------------------

-- Split a semicolon-separated metadata string while respecting
-- quoted values such as:
--
--   label="Party Offset X"; min=-500; max=500
local function SplitMetadataFields(text)

    local fields = {}
    local startPos = 1
    local quote = nil
    local escaped = false

    for pos = 1, #text do

        local c =
            text:sub(
                pos,
                pos
            )

        if quote then

            if escaped then
                escaped = false

            elseif c == "\\" then
                escaped = true

            elseif c == quote then
                quote = nil
            end

        else

            if c == "\""
                or c == "'" then

                quote = c

            elseif c == ";" then

                fields[#fields + 1] =
                    Trim(
                        text:sub(
                            startPos,
                            pos - 1
                        )
                    )

                startPos =
                    pos + 1

            end

        end

    end

    local tail =
        Trim(
            text:sub(
                startPos
            )
        )

    if tail ~= "" then
        fields[#fields + 1] = tail
    end

    return fields

end


local function SplitMetadataList(text)

    local values = {}
    local startPos = 1
    local quote = nil
    local escaped = false

    for pos = 1, #text do

        local c = text:sub(pos, pos)

        if quote then

            if escaped then
                escaped = false
            elseif c == "\\" then
                escaped = true
            elseif c == quote then
                quote = nil
            end

        else

            if c == "\"" or c == "'" then
                quote = c
            elseif c == "," then
                local field = Trim(text:sub(startPos, pos - 1))
                if field ~= "" then values[#values + 1] = field end
                startPos = pos + 1
            end

        end

    end

    local tail = Trim(text:sub(startPos))
    if tail ~= "" then values[#values + 1] = tail end

    return values

end


local function ParseMetadataScalar(raw)

    raw = Trim(raw)

    if raw == "true" then return true end
    if raw == "false" then return false end

    local numberValue = tonumber(raw)
    if numberValue ~= nil then return numberValue end

    if #raw >= 2 then
        local first = raw:sub(1, 1)
        local last = raw:sub(-1)
        if (first == "\"" and last == "\"")
            or (first == "'" and last == "'") then
            return raw:sub(2, -2)
        end
    end

    return raw

end


local function ParseMetadataValue(raw)

    raw = Trim(raw)

    if #raw >= 2
        and raw:sub(1, 1) == "{"
        and raw:sub(-1) == "}" then

        local list = {}
        local body = raw:sub(2, -2)

        for _, field in ipairs(SplitMetadataList(body)) do
            list[#list + 1] = ParseMetadataScalar(field)
        end

        return list
    end

    return ParseMetadataScalar(raw)

end


function DarnMenuIntegration.ParseMetadata(annotationText)

    local metadata = {}

    annotationText =
        Trim(
            annotationText or ""
        )

    if annotationText == "" then
        return metadata
    end

    for _, field in ipairs(
        SplitMetadataFields(
            annotationText
        )
    ) do

        if field ~= "" then

            local key, rawValue =
                field:match(
                    "^([%w_]+)%s*=%s*(.+)$"
                )

            if key then

                metadata[key] =
                    ParseMetadataValue(
                        rawValue
                    )

            else

                ------------------------------------------------
                -- A bare metadata word is treated as a true flag.
                ------------------------------------------------

                metadata[field] = true

            end

        end

    end

    return metadata

end


------------------------------------------------
-- Annotated Config Parser
------------------------------------------------

local function GetValueType(rawValue)

    rawValue =
        Trim(
            rawValue or ""
        )

    if rawValue == "true"
        or rawValue == "false" then

        return "boolean"
    end

    if tonumber(rawValue) ~= nil then
        return "number"
    end

    local first =
        rawValue:sub(1, 1)

    local last =
        rawValue:sub(-1)

    if (first == "\""
        and last == "\"")
        or
       (first == "'"
        and last == "'") then

        return "string"
    end

    if IsSimpleMemberExpression(
        rawValue
    ) then

        return "expression"
    end

    return "unknown"

end


local function CollectDescription(lines, annotationLineIndex)

    local collected = {}

    for index = annotationLineIndex - 1, 1, -1 do

        local line =
            lines[index]

        local comment =
            line:match(
                "^%s*%-%-%s?(.*)$"
            )

        if comment == nil then
            break
        end

        comment =
            Trim(
                comment
            )

        ------------------------------------------------
        -- Stop at decorative separators. They belong to the
        -- config layout rather than the individual setting.
        ------------------------------------------------

        if comment == ""
            or comment:match("^%-+$") then

            break
        end

        table.insert(
            collected,
            1,
            comment
        )

    end

    return table.concat(
        collected,
        " "
    )

end


-- Track named Lua tables by indentation. @darn scalar annotations
-- are only used in named-table config sections, so anonymous array
-- tables such as DisplayMode States do not affect normal scalar paths.
local function BuildNamedTableContext(lines)

    local contexts = {}
    local stack = {}

    for index, line in ipairs(lines) do

        local codeLine =
            StripTrailingComment(line)

        local stripped =
            codeLine:match("^%s*(.-)%s*$")

        local indentText =
            codeLine:match("^(%s*)")
            or ""

        local indent =
            #indentText

        local isCodeLine =
            stripped ~= ""
            and not stripped:match("^%-%-")

        local tableKey =
            isCodeLine
            and codeLine:match(
                "^%s*([%a_][%w_]*)%s*=%s*{%s*,?%s*$"
            )
            or nil

        local scalarKey =
            isCodeLine
            and codeLine:match(
                "^%s*([%a_][%w_]*)%s*="
            )
            or nil

        local isClosing =
            isCodeLine
            and stripped:match("^}")
            ~= nil

        ------------------------------------------------
        -- Move back to the correct parent before processing
        -- a sibling scalar/table or a closing brace.
        ------------------------------------------------

        if scalarKey
            or tableKey
            or isClosing then

            while #stack > 0
                and stack[#stack].indent >= indent do

                table.remove(stack)

            end

        end

        if tableKey then

            stack[#stack + 1] = {
                indent = indent,
                key = tableKey,
            }

        end

        local snapshot = {}

        for stackIndex, entry in ipairs(stack) do
            snapshot[stackIndex] = entry.key
        end

        contexts[index] = snapshot

    end

    return contexts

end


function DarnMenuIntegration.ParseAnnotatedConfig(sourceText)

    if type(sourceText) ~= "string" then
        return nil,
            "Config source must be a string."
    end

    local lines = {}

    for line in (sourceText .. "\n"):gmatch("(.-)\r?\n") do
        lines[#lines + 1] = line
    end

    local contexts = BuildNamedTableContext(lines)
    local items = {}

    for index, line in ipairs(lines) do

        local inlineCode, inlineAnnotation =
            SplitInlineDarnAnnotation(line)

        local annotation = inlineAnnotation
        local targetIndex = index
        local targetLine = line
        local codeLine = inlineCode
        local annotationLine = index

        ------------------------------------------------
        -- Backward-compatible standalone form:
        --
        --   -- @darn ...
        --   Value = ...
        ------------------------------------------------

        if annotation == nil then

            annotation =
                line:match(
                    "^%s*%-%-%s*@darn%s*(.-)%s*$"
                )

            if annotation ~= nil then

                targetIndex = index + 1

                while targetIndex <= #lines do

                    local candidate = lines[targetIndex]

                    if candidate:match("^%s*$")
                        or candidate:match("^%s*%-%-") then
                        targetIndex = targetIndex + 1
                    else
                        break
                    end

                end

                targetLine = lines[targetIndex]

                if not targetLine then
                    return nil,
                        "@darn annotation has no following config entry at line "
                        .. tostring(index)
                end

                codeLine = StripTrailingComment(targetLine)
            end

        end

        if annotation ~= nil then

            local metadata =
                DarnMenuIntegration.ParseMetadata(annotation)

            codeLine = codeLine or StripTrailingComment(targetLine)

            local indentText, key, rawValue =
                codeLine:match(
                    "^(%s*)([%a_][%w_]*)%s*=%s*(.-)%s*$"
                )

            local isTable = false

            if key then

                local trimmedValue = Trim(rawValue)

                if trimmedValue == "{" then
                    isTable = true
                    rawValue = "{"
                else
                    rawValue = Trim(rawValue)
                    if rawValue:sub(-1) == "," then
                        rawValue = Trim(rawValue:sub(1, -2))
                    end
                end

            end

            if not key then
                return nil,
                    "Unsupported @darn target at line "
                    .. tostring(targetIndex)
                    .. ": "
                    .. tostring(targetLine)
            end

            local context = contexts[targetIndex - 1] or {}
            local pathParts = {}

            for _, tableKey in ipairs(context) do
                pathParts[#pathParts + 1] = tableKey
            end

            pathParts[#pathParts + 1] = key

            if pathParts[1] == "Config" then
                table.remove(pathParts, 1)
            end

            local path = table.concat(pathParts, ".")
            local kind = metadata.kind

            if not kind then
                if isTable then
                    kind = "table"
                elseif metadata.values ~= nil
                    or metadata.choices ~= nil then
                    kind = "enum"
                else
                    kind = "scalar"
                end
            end

            items[#items + 1] = {
                path = path,
                key = key,
                kind = kind,
                metadata = metadata,
                description = CollectDescription(lines, annotationLine),
                label = metadata.label or HumanizeIdentifier(key),
                rawValue = rawValue,
                valueType = isTable and "table" or GetValueType(rawValue),
                annotationLine = annotationLine,
                targetLine = targetIndex,
            }

        end

    end

    return items

end


------------------------------------------------
-- Source Scanner for DisplayMode
------------------------------------------------

local function SkipQuotedString(
    text,
    pos
)

    local quote =
        text:sub(
            pos,
            pos
        )

    pos = pos + 1

    while pos <= #text do

        local c =
            text:sub(
                pos,
                pos
            )

        if c == "\\" then
            pos = pos + 2

        elseif c == quote then
            return pos + 1

        else
            pos = pos + 1
        end

    end

    return pos

end


local function SkipLineComment(
    text,
    pos
)

    local newline =
        text:find(
            "\n",
            pos,
            true
        )

    if newline then
        return newline + 1
    end

    return #text + 1

end


local function FindMatchingBrace(
    text,
    openPos
)

    if text:sub(
        openPos,
        openPos
    ) ~= "{" then

        return nil
    end

    local depth = 0
    local pos = openPos

    while pos <= #text do

        local two =
            text:sub(
                pos,
                pos + 1
            )

        local c =
            text:sub(
                pos,
                pos
            )

        if two == "--" then

            pos =
                SkipLineComment(
                    text,
                    pos
                )

        elseif c == "\""
            or c == "'" then

            pos =
                SkipQuotedString(
                    text,
                    pos
                )

        elseif c == "{" then

            depth = depth + 1
            pos = pos + 1

        elseif c == "}" then

            depth = depth - 1

            if depth == 0 then
                return pos
            end

            pos = pos + 1

        else
            pos = pos + 1
        end

    end

    return nil

end


local function FindDisplayModeTable(
    sourceText
)

    local searchPos = 1

    while true do

        local startPos, endPos =
            sourceText:find(
                "DisplayMode%s*=%s*{",
                searchPos
            )

        if not startPos then
            return nil,
                "DisplayMode table was not found."
        end

        ------------------------------------------------
        -- Reject a match that occurs inside a line comment.
        ------------------------------------------------

        local lineStart =
            sourceText:sub(
                1,
                startPos
            ):match(".*()\n")
            or 1

        local prefix =
            sourceText:sub(
                lineStart,
                startPos - 1
            )

        if not prefix:find(
            "%-%-"
        ) then

            local openPos =
                sourceText:find(
                    "{",
                    startPos,
                    true
                )

            local closePos =
                FindMatchingBrace(
                    sourceText,
                    openPos
                )

            if not closePos then
                return nil,
                    "DisplayMode table is not properly closed."
            end

            return {
                openPos = openPos,
                closePos = closePos,
            }

        end

        searchPos =
            endPos + 1

    end

end


local function GetTopLevelHotkeyBlocks(
    sourceText,
    displayRange
)

    local blocks = {}
    local pos =
        displayRange.openPos + 1

    while pos < displayRange.closePos do

        local two =
            sourceText:sub(
                pos,
                pos + 1
            )

        local c =
            sourceText:sub(
                pos,
                pos
            )

        if two == "--" then

            pos =
                SkipLineComment(
                    sourceText,
                    pos
                )

        elseif c == "\""
            or c == "'" then

            pos =
                SkipQuotedString(
                    sourceText,
                    pos
                )

        elseif c == "[" then

            local bracketEnd =
                sourceText:find(
                    "]",
                    pos + 1,
                    true
                )

            if bracketEnd then

                local expression =
                    Trim(
                        sourceText:sub(
                            pos + 1,
                            bracketEnd - 1
                        )
                    )

                local equalsPos =
                    sourceText:find(
                        "=",
                        bracketEnd + 1,
                        true
                    )

                if equalsPos then

                    local openPos =
                        sourceText:find(
                            "{",
                            equalsPos + 1,
                            true
                        )

                    if openPos
                        and openPos < displayRange.closePos then

                        local closePos =
                            FindMatchingBrace(
                                sourceText,
                                openPos
                            )

                        if not closePos then

                            return nil,
                                "DisplayMode hotkey table is not properly closed: "
                                .. tostring(expression)
                        end

                        blocks[#blocks + 1] = {
                            expression = expression,
                            expressionStart = pos + 1,
                            expressionEnd = bracketEnd - 1,
                            openPos = openPos,
                            closePos = closePos,
                        }

                        pos =
                            closePos + 1

                    else
                        pos = bracketEnd + 1
                    end

                else
                    pos = bracketEnd + 1
                end

            else
                pos = pos + 1
            end

        else
            pos = pos + 1
        end

    end

    return blocks

end


local function GetStateRanges(
    sourceText,
    hotkeyBlock
)

    local states = {}
    local pos =
        hotkeyBlock.openPos + 1

    while pos < hotkeyBlock.closePos do

        local two =
            sourceText:sub(
                pos,
                pos + 1
            )

        local c =
            sourceText:sub(
                pos,
                pos
            )

        if two == "--" then

            pos =
                SkipLineComment(
                    sourceText,
                    pos
                )

        elseif c == "\""
            or c == "'" then

            pos =
                SkipQuotedString(
                    sourceText,
                    pos
                )

        elseif c == "{" then

            local closePos =
                FindMatchingBrace(
                    sourceText,
                    pos
                )

            if not closePos then

                return nil,
                    "DisplayMode State table is not properly closed."
            end

            states[#states + 1] = {
                openPos = pos,
                closePos = closePos,
            }

            pos =
                closePos + 1

        else
            pos = pos + 1
        end

    end

    return states

end


local DISPLAY_MODE_FIELDS = {
    "Number",
    "Level",
    "Gender",
    "Rank",
    "Soul",
    "Friendship",
    "PassiveSkill.Bar",
    "PassiveSkill.Name",
    "Talent",
}


local DISPLAY_MODE_LABELS = {
    Number = "Palpedia Number",
    Level = "Level",
    Gender = "Gender",
    Rank = "Condensation Rank",
    Soul = "Soul Rank",
    Friendship = "Friendship Rank",
    ["PassiveSkill.Bar"] = "Passive Skill Bar",
    ["PassiveSkill.Name"] = "Passive Skill Name",
    Talent = "Talent",
}


local function ReadBooleanAssignment(
    stateText,
    fieldPath
)

    if fieldPath == "PassiveSkill.Bar"
        or fieldPath == "PassiveSkill.Name" then

        local passiveBody =
            stateText:match(
                "PassiveSkill%s*=%s*{(.-)}"
            )

        if not passiveBody then
            return false, false
        end

        local key =
            fieldPath:match(
                "%.([^.]+)$"
            )

        local raw =
            passiveBody:match(
                key
                .. "%s*=%s*([%a]+)"
            )

        if raw == "true"
            or raw == "false" then

            return raw == "true", true
        end

        return false, false

    end

    local raw =
        stateText:match(
            "[%s{,]"
            .. fieldPath
            .. "%s*=%s*([%a]+)"
        )

    if raw == "true"
        or raw == "false" then

        return raw == "true", true
    end

    return false, false

end


local DISPLAY_MODE_GAMEPAD_BUTTON_VALUES = {
    "Right Stick Press",
    "Right Stick Up",
    "Right Stick Down",
    "Right Stick Left",
    "Right Stick Right",
}


local DISPLAY_MODE_GAMEPAD_BUTTON_SET = {}

for _, value in ipairs(
    DISPLAY_MODE_GAMEPAD_BUTTON_VALUES
) do
    DISPLAY_MODE_GAMEPAD_BUTTON_SET[value] = true
end


local function ReadDisplayModeGamepadButton(
    sourceText,
    hotkeyBlock,
    stateRanges
)

    local headerEnd =
        hotkeyBlock.closePos - 1

    if stateRanges[1] then
        headerEnd =
            stateRanges[1].openPos - 1
    end

    local headerText =
        sourceText:sub(
            hotkeyBlock.openPos + 1,
            headerEnd
        )

    local value =
        headerText:match(
            'GamepadButton%s*=%s*"([^"]*)"'
        )

    if value == nil then
        value =
            headerText:match(
                "GamepadButton%s*=%s*'([^']*)'"
            )
    end

    if value == nil then
        return nil, false
    end

    return value, true

end


function DarnMenuIntegration.GetDisplayModeModel(sourceText)

    local displayRange, displayError =
        FindDisplayModeTable(
            sourceText
        )

    if not displayRange then
        return nil, displayError
    end

    local hotkeyBlocks, hotkeyError =
        GetTopLevelHotkeyBlocks(
            sourceText,
            displayRange
        )

    if not hotkeyBlocks then
        return nil, hotkeyError
    end

    local model = {}

    for _, block in ipairs(hotkeyBlocks) do

        local stateRanges, stateError =
            GetStateRanges(
                sourceText,
                block
            )

        if not stateRanges then
            return nil, stateError
        end

        local gamepadButton,
            gamepadExplicit =
            ReadDisplayModeGamepadButton(
                sourceText,
                block,
                stateRanges
            )

        local hotkey = {
            expression = block.expression,
            gamepadButton = {
                value = gamepadButton,
                explicit = gamepadExplicit,
            },
            states = {},
        }

        for stateIndex, stateRange in ipairs(stateRanges) do

            local stateText =
                sourceText:sub(
                    stateRange.openPos,
                    stateRange.closePos
                )

            local state = {}

            for _, fieldPath in ipairs(
                DISPLAY_MODE_FIELDS
            ) do

                local value, explicit =
                    ReadBooleanAssignment(
                        stateText,
                        fieldPath
                    )

                state[fieldPath] = {
                    value = value,
                    explicit = explicit,
                    label =
                        DISPLAY_MODE_LABELS[fieldPath]
                        or HumanizeIdentifier(fieldPath),
                }

            end

            hotkey.states[stateIndex] = state

        end

        model[#model + 1] = hotkey

    end

    return model

end


------------------------------------------------
-- DisplayMode Source Editing
------------------------------------------------

local function ReplaceRange(
    text,
    startPos,
    endPos,
    replacement
)

    return text:sub(
        1,
        startPos - 1
    )
    ..
    replacement
    ..
    text:sub(
        endPos + 1
    )

end


local function FindHotkeyBlock(
    sourceText,
    expression
)

    local displayRange, displayError =
        FindDisplayModeTable(
            sourceText
        )

    if not displayRange then
        return nil, displayError
    end

    local blocks, blockError =
        GetTopLevelHotkeyBlocks(
            sourceText,
            displayRange
        )

    if not blocks then
        return nil, blockError
    end

    for _, block in ipairs(blocks) do

        if block.expression == expression then
            return block, blocks
        end

    end

    return nil,
        "DisplayMode hotkey was not found: "
        .. tostring(expression)

end


function DarnMenuIntegration.UpdateDisplayModeGamepadButtonSource(
    sourceText,
    hotkeyIndex,
    gamepadButton
)

    if type(sourceText) ~= "string" then
        return nil,
            "DisplayMode source must be a string."
    end

    if type(hotkeyIndex) ~= "number"
        or hotkeyIndex < 1
        or hotkeyIndex % 1 ~= 0 then

        return nil,
            "DisplayMode hotkey index must be a positive integer."
    end

    if type(gamepadButton) ~= "string"
        or not DISPLAY_MODE_GAMEPAD_BUTTON_SET[
            gamepadButton
        ] then

        return nil,
            "Unsupported DisplayMode Gamepad button: "
            .. tostring(gamepadButton)
    end

    local displayRange, displayError =
        FindDisplayModeTable(
            sourceText
        )

    if not displayRange then
        return nil, displayError
    end

    local blocks, blockError =
        GetTopLevelHotkeyBlocks(
            sourceText,
            displayRange
        )

    if not blocks then
        return nil, blockError
    end

    local block =
        blocks[hotkeyIndex]

    if not block then
        return nil,
            "DisplayMode hotkey index does not exist: "
            .. tostring(hotkeyIndex)
    end

    local stateRanges, stateError =
        GetStateRanges(
            sourceText,
            block
        )

    if not stateRanges then
        return nil, stateError
    end

    local headerEnd =
        block.closePos - 1

    if stateRanges[1] then
        headerEnd =
            stateRanges[1].openPos - 1
    end

    local headerText =
        sourceText:sub(
            block.openPos + 1,
            headerEnd
        )

    local assignmentStart,
        assignmentEnd =
        headerText:find(
            'GamepadButton%s*=%s*"[^"]*"'
        )

    if not assignmentStart then

        assignmentStart,
            assignmentEnd =
            headerText:find(
                "GamepadButton%s*=%s*'[^']*'"
            )

    end

    if not assignmentStart then
        return nil,
            "GamepadButton is not present in DisplayMode Hotkey "
            .. tostring(hotkeyIndex)
    end

    local absoluteStart =
        block.openPos
        + assignmentStart

    local absoluteEnd =
        block.openPos
        + assignmentEnd

    local oldAssignment =
        sourceText:sub(
            absoluteStart,
            absoluteEnd
        )

    local prefix =
        oldAssignment:match(
            "^(GamepadButton%s*=%s*)"
        )
        or "GamepadButton = "

    local replacement =
        prefix
        .. string.format(
            "%q",
            gamepadButton
        )

    if oldAssignment == replacement then
        return sourceText, false
    end

    return ReplaceRange(
        sourceText,
        absoluteStart,
        absoluteEnd,
        replacement
    ), true

end


function DarnMenuIntegration.SetDisplayModeHotkey(
    manager,
    oldExpression,
    newExpression
)

    if not manager
        or type(manager.ReadSource) ~= "function"
        or type(manager.WriteSource) ~= "function" then

        return false,
            "A ConfigManager instance with ReadSource()/WriteSource() is required."
    end

    oldExpression =
        Trim(
            oldExpression or ""
        )

    newExpression =
        Trim(
            newExpression or ""
        )

    if not IsSimpleMemberExpression(
        oldExpression
    )
        or not IsSimpleMemberExpression(
            newExpression
        ) then

        return false,
            "DisplayMode hotkeys must be simple member expressions such as Key.F1."
    end

    if oldExpression == newExpression then
        return true, false
    end

    local sourceText =
        manager:ReadSource()

    if not sourceText then
        return false,
            "Could not read the user config source."
    end

    local block, blocksOrError =
        FindHotkeyBlock(
            sourceText,
            oldExpression
        )

    if not block then
        return false, blocksOrError
    end

    for _, existingBlock in ipairs(
        blocksOrError
    ) do

        if existingBlock.expression == newExpression then

            return false,
                "The target DisplayMode hotkey already exists: "
                .. tostring(newExpression)
        end

    end

    local newText =
        ReplaceRange(
            sourceText,
            block.expressionStart,
            block.expressionEnd,
            newExpression
        )

    return manager:WriteSource(
        newText,
        "DisplayMode hotkey updated"
    )

end


local function SetSimpleStateBoolean(
    stateText,
    fieldName,
    enabled
)

    local valueStart, valueEnd =
        stateText:find(
            fieldName
            .. "%s*=%s*true"
        )

    if not valueStart then

        valueStart, valueEnd =
            stateText:find(
                fieldName
                .. "%s*=%s*false"
            )

    end

    if valueStart then

        local boolStart, boolEnd =
            stateText:find(
                "true",
                valueStart,
                true
            )

        local falseStart, falseEnd =
            stateText:find(
                "false",
                valueStart,
                true
            )

        if falseStart
            and (
                not boolStart
                or falseStart < boolStart
            ) then

            boolStart = falseStart
            boolEnd = falseEnd

        end

        if boolStart
            and boolStart <= valueEnd then

            return ReplaceRange(
                stateText,
                boolStart,
                boolEnd,
                enabled and "true" or "false"
            ),
            true

        end

    end

    if not enabled then

        ------------------------------------------------
        -- Missing means false in DisplayMode semantics.
        ------------------------------------------------

        return stateText, false

    end

    local baseIndent =
        stateText:match(
            "\n(%s*)[^%s}]"
        )

    if not baseIndent then
        baseIndent = "    "
    end

    local insertPos =
        stateText:find(
            "\n"
        )

    if not insertPos then
        return nil,
            "Could not determine DisplayMode State insertion position."
    end

    local insertion =
        "\n"
        .. baseIndent
        .. fieldName
        .. " = true,"

    return stateText:sub(
        1,
        insertPos - 1
    )
    ..
    insertion
    ..
    stateText:sub(
        insertPos
    ),
    true

end


local function SetPassiveSkillBoolean(
    stateText,
    passiveKey,
    enabled
)

    local passiveStart =
        stateText:find(
            "PassiveSkill%s*=%s*{"
        )

    if passiveStart then

        local openPos =
            stateText:find(
                "{",
                passiveStart,
                true
            )

        local closePos =
            FindMatchingBrace(
                stateText,
                openPos
            )

        if not closePos then
            return nil,
                "PassiveSkill table is not properly closed."
        end

        local passiveText =
            stateText:sub(
                openPos,
                closePos
            )

        local updatedPassive, changedOrError =
            SetSimpleStateBoolean(
                passiveText,
                passiveKey,
                enabled
            )

        if not updatedPassive then
            return nil, changedOrError
        end

        if not changedOrError then
            return stateText, false
        end

        return ReplaceRange(
            stateText,
            openPos,
            closePos,
            updatedPassive
        ),
        true

    end

    if not enabled then
        return stateText, false
    end

    local baseIndent =
        stateText:match(
            "\n(%s*)[^%s}]"
        )
        or "    "

    local insertPos =
        stateText:find(
            "\n"
        )

    if not insertPos then
        return nil,
            "Could not determine PassiveSkill insertion position."
    end

    local insertion =
        "\n"
        .. baseIndent
        .. "PassiveSkill = {\n"
        .. baseIndent
        .. "    "
        .. passiveKey
        .. " = true,\n"
        .. baseIndent
        .. "},"

    return stateText:sub(
        1,
        insertPos - 1
    )
    ..
    insertion
    ..
    stateText:sub(
        insertPos
    ),
    true

end


function DarnMenuIntegration.SetDisplayModeStateValue(
    manager,
    hotkeyExpression,
    stateIndex,
    fieldPath,
    enabled
)

    if not manager
        or type(manager.ReadSource) ~= "function"
        or type(manager.WriteSource) ~= "function" then

        return false,
            "A ConfigManager instance with ReadSource()/WriteSource() is required."
    end

    if type(stateIndex) ~= "number"
        or stateIndex < 1
        or stateIndex % 1 ~= 0 then

        return false,
            "DisplayMode State index must be a positive integer."
    end

    if enabled ~= true
        and enabled ~= false then

        return false,
            "DisplayMode State value must be boolean."
    end

    local supported = false

    for _, candidate in ipairs(
        DISPLAY_MODE_FIELDS
    ) do

        if candidate == fieldPath then
            supported = true
            break
        end

    end

    if not supported then

        return false,
            "Unsupported DisplayMode field: "
            .. tostring(fieldPath)
    end

    local sourceText =
        manager:ReadSource()

    if not sourceText then
        return false,
            "Could not read the user config source."
    end

    local block, blockError =
        FindHotkeyBlock(
            sourceText,
            Trim(
                hotkeyExpression or ""
            )
        )

    if not block then
        return false, blockError
    end

    local states, stateError =
        GetStateRanges(
            sourceText,
            block
        )

    if not states then
        return false, stateError
    end

    local stateRange =
        states[stateIndex]

    if not stateRange then

        return false,
            "DisplayMode State does not exist: "
            .. tostring(stateIndex)
    end

    local stateText =
        sourceText:sub(
            stateRange.openPos,
            stateRange.closePos
        )

    local updatedState
    local changedOrError

    if fieldPath == "PassiveSkill.Bar"
        or fieldPath == "PassiveSkill.Name" then

        updatedState, changedOrError =
            SetPassiveSkillBoolean(
                stateText,
                fieldPath:match("%.([^.]+)$"),
                enabled
            )

    else

        updatedState, changedOrError =
            SetSimpleStateBoolean(
                stateText,
                fieldPath,
                enabled
            )

    end

    if not updatedState then
        return false, changedOrError
    end

    if not changedOrError then
        return true, false
    end

    local newText =
        ReplaceRange(
            sourceText,
            stateRange.openPos,
            stateRange.closePos,
            updatedState
        )

    return manager:WriteSource(
        newText,
        "DisplayMode State updated"
    )

end


------------------------------------------------
-- Pure DisplayMode Source Updates
------------------------------------------------

-- Update one DisplayMode State field in a source string without writing it.
-- Hotkeys are addressed by source order so the schema can keep stable staging
-- paths even when the key expression itself changes.
function DarnMenuIntegration.UpdateDisplayModeStateSource(
    sourceText,
    hotkeyIndex,
    stateIndex,
    fieldPath,
    enabled
)

    if type(sourceText) ~= "string" then
        return nil, "DisplayMode source must be a string."
    end

    if type(hotkeyIndex) ~= "number"
        or hotkeyIndex < 1
        or hotkeyIndex % 1 ~= 0 then

        return nil, "DisplayMode hotkey index must be a positive integer."
    end

    if type(stateIndex) ~= "number"
        or stateIndex < 1
        or stateIndex % 1 ~= 0 then

        return nil, "DisplayMode State index must be a positive integer."
    end

    if enabled ~= true and enabled ~= false then
        return nil, "DisplayMode State value must be boolean."
    end

    local supported = false

    for _, candidate in ipairs(DISPLAY_MODE_FIELDS) do
        if candidate == fieldPath then
            supported = true
            break
        end
    end

    if not supported then
        return nil,
            "Unsupported DisplayMode field: "
            .. tostring(fieldPath)
    end

    local displayRange, displayError =
        FindDisplayModeTable(sourceText)

    if not displayRange then
        return nil, displayError
    end

    local blocks, blockError =
        GetTopLevelHotkeyBlocks(
            sourceText,
            displayRange
        )

    if not blocks then
        return nil, blockError
    end

    local block = blocks[hotkeyIndex]

    if not block then
        return nil,
            "DisplayMode hotkey index does not exist: "
            .. tostring(hotkeyIndex)
    end

    local states, stateError =
        GetStateRanges(
            sourceText,
            block
        )

    if not states then
        return nil, stateError
    end

    local stateRange = states[stateIndex]

    if not stateRange then
        return nil,
            "DisplayMode State does not exist: "
            .. tostring(stateIndex)
    end

    local stateText =
        sourceText:sub(
            stateRange.openPos,
            stateRange.closePos
        )

    local updatedState
    local changedOrError

    if fieldPath == "PassiveSkill.Bar"
        or fieldPath == "PassiveSkill.Name" then

        updatedState, changedOrError =
            SetPassiveSkillBoolean(
                stateText,
                fieldPath:match("%.([^.]+)$"),
                enabled
            )

    else

        updatedState, changedOrError =
            SetSimpleStateBoolean(
                stateText,
                fieldPath,
                enabled
            )

    end

    if not updatedState then
        return nil, changedOrError
    end

    if not changedOrError then
        return sourceText, false
    end

    return ReplaceRange(
        sourceText,
        stateRange.openPos,
        stateRange.closePos,
        updatedState
    ), true

end


-- Replace multiple DisplayMode hotkey expressions simultaneously by source
-- order. Simultaneous replacement permits swaps such as F1 <-> F2 without
-- temporarily installing an invalid/duplicate config.
function DarnMenuIntegration.UpdateDisplayModeHotkeysSource(
    sourceText,
    desiredByIndex
)

    if type(sourceText) ~= "string" then
        return nil, "DisplayMode source must be a string."
    end

    if type(desiredByIndex) ~= "table" then
        return nil, "DisplayMode hotkey replacements must be a table."
    end

    local displayRange, displayError =
        FindDisplayModeTable(sourceText)

    if not displayRange then
        return nil, displayError
    end

    local blocks, blockError =
        GetTopLevelHotkeyBlocks(
            sourceText,
            displayRange
        )

    if not blocks then
        return nil, blockError
    end

    local finalExpressions = {}

    for index, block in ipairs(blocks) do

        local desired = desiredByIndex[index]

        if desired ~= nil then

            desired = Trim(tostring(desired))

            if not IsSimpleMemberExpression(desired) then
                return nil,
                    "DisplayMode hotkeys must be simple member expressions such as Key.F1."
            end

            finalExpressions[index] = desired

        else
            finalExpressions[index] = block.expression
        end

    end

    for index in pairs(desiredByIndex) do
        if type(index) ~= "number"
            or index < 1
            or index % 1 ~= 0
            or not blocks[index] then

            return nil,
                "DisplayMode hotkey index does not exist: "
                .. tostring(index)
        end
    end

    local seen = {}

    for index, expression in ipairs(finalExpressions) do

        if seen[expression] then
            return nil,
                "DisplayMode hotkey would be duplicated: "
                .. tostring(expression)
        end

        seen[expression] = index
    end

    local replacements = {}

    for index, block in ipairs(blocks) do

        local replacement = finalExpressions[index]

        if replacement ~= block.expression then
            replacements[#replacements + 1] = {
                startPos = block.expressionStart,
                endPos = block.expressionEnd,
                value = replacement,
            }
        end

    end

    if #replacements == 0 then
        return sourceText, false
    end

    table.sort(
        replacements,
        function(a, b)
            return a.startPos > b.startPos
        end
    )

    local newText = sourceText

    for _, replacement in ipairs(replacements) do
        newText = ReplaceRange(
            newText,
            replacement.startPos,
            replacement.endPos,
            replacement.value
        )
    end

    return newText, true

end


------------------------------------------------
-- DarnMenu Schema / Staging Integration
------------------------------------------------

local IntegrationGroups = {}


local function ReadFile(path)

    local file = io.open(path, "r")

    if not file then
        return nil
    end

    local text = file:read("*a")
    file:close()

    return text

end


local function WriteFile(path, text)

    local file = io.open(path, "w")

    if not file then
        return false
    end

    local ok = pcall(function()
        file:write(text)
    end)

    file:close()

    return ok

end


local function SplitPath(path)

    local parts = {}

    for part in tostring(path or ""):gmatch("[^.]+") do
        parts[#parts + 1] = part
    end

    return parts

end


local function IsArray(value)

    if type(value) ~= "table" then
        return false, 0
    end

    local count = 0
    local maximum = 0

    for key in pairs(value) do

        if type(key) ~= "number"
            or key < 1
            or key % 1 ~= 0 then

            return false, 0
        end

        count = count + 1

        if key > maximum then
            maximum = key
        end

    end

    return count == maximum, maximum

end


local function SerializeLua(value, indent)

    indent = indent or 0

    local valueType = type(value)

    if valueType == "nil" then
        return "nil"
    end

    if valueType == "boolean"
        or valueType == "number" then

        return tostring(value)
    end

    if valueType == "string" then
        return string.format("%q", value)
    end

    if valueType ~= "table" then
        error("Unsupported schema value type: " .. valueType)
    end

    local isArray, arrayLength = IsArray(value)
    local currentIndent = string.rep("    ", indent)
    local childIndent = string.rep("    ", indent + 1)
    local lines = { "{" }

    if isArray then

        for index = 1, arrayLength do
            lines[#lines + 1] =
                childIndent
                .. SerializeLua(value[index], indent + 1)
                .. ","
        end

    else

        local keys = {}

        for key in pairs(value) do
            keys[#keys + 1] = key
        end

        table.sort(
            keys,
            function(a, b)
                return tostring(a) < tostring(b)
            end
        )

        for _, key in ipairs(keys) do
            lines[#lines + 1] =
                childIndent
                .. "["
                .. SerializeLua(key, 0)
                .. "] = "
                .. SerializeLua(value[key], indent + 1)
                .. ","
        end

    end

    lines[#lines + 1] = currentIndent .. "}"

    return table.concat(lines, "\n")

end


local function DecodeQuotedString(raw)

    local first = raw:sub(1, 1)
    local last = raw:sub(-1)

    if (first ~= "\"" and first ~= "'")
        or last ~= first then

        return nil
    end

    local body = raw:sub(2, -2)

    body = body:gsub("\\n", "\n")
    body = body:gsub("\\r", "\r")
    body = body:gsub("\\t", "\t")
    body = body:gsub("\\\"", "\"")
    body = body:gsub("\\'", "'")
    body = body:gsub("\\\\", "\\")

    return body

end


local function RawValueToLua(rawValue, kind)

    rawValue = Trim(rawValue or "")

    if kind == "hotkey" then

        local keyName =
            rawValue:match("^Key%.([%a_][%w_]*)$")

        return keyName
    end

    if rawValue == "true" then
        return true
    end

    if rawValue == "false" then
        return false
    end

    local numberValue = tonumber(rawValue)

    if numberValue ~= nil then
        return numberValue
    end

    return DecodeQuotedString(rawValue)

end


local function KeyExpressionToName(expression)

    return Trim(expression or ""):match(
        "^Key%.([%a_][%w_]*)$"
    )

end


local function KeyNameToExpression(keyName)

    if type(keyName) ~= "string"
        or not keyName:match("^[%a_][%w_]*$") then

        return nil
    end

    return "Key." .. keyName

end


local function MakeStagingKey(...)

    local parts = { ... }

    for index, value in ipairs(parts) do
        parts[index] =
            tostring(value)
            :gsub("[^%w_]", "_")
    end

    return table.concat(parts, "__")

end


local function DeriveSharedDirectory(configPath)

    if type(configPath) ~= "string" then
        return nil
    end

    return configPath:match(
        "^(.*[/\\]shared[/\\])"
    )

end


local function GetFileName(path)

    if type(path) ~= "string" then
        return nil
    end

    return path:match("([^/\\]+)$")

end


local function GetConfigIdFromPath(configPath)

    local fileName =
        GetFileName(configPath)

    if not fileName then
        return nil
    end

    local stem =
        fileName:gsub("%.lua$", "")

    local configId =
        stem:gsub("Config$", "")

    if configId == "" then
        configId = stem
    end

    return configId

end


local function GetSchemaNameFromPath(configPath, sharedDir)

    if type(configPath) ~= "string"
        or type(sharedDir) ~= "string" then

        return nil
    end

    local relative =
        configPath:sub(#sharedDir + 1)

    local folderName =
        relative:match("^([^/\\]+)[/\\]")

    if folderName and folderName ~= "" then
        return folderName
    end

    return GetConfigIdFromPath(configPath)

end


local function ValuesEqual(a, b)

    return type(a) == type(b)
        and a == b

end


local function GetScalarKind(item)

    if item.kind == "hotkey" then
        return "keycapture"
    end

    if item.kind == "enum"
        or item.metadata.values ~= nil
        or item.metadata.choices ~= nil then
        return "enum"
    end

    if item.valueType == "boolean" then
        return "bool"
    end

    if item.valueType == "number" then
        return "number"
    end

    if item.valueType == "string" then
        return "text"
    end

    return nil

end


local function HumanizePathPart(value)

    local special = {
        Number = "Palpedia Number",
        Rank = "Condensation Rank",
        Soul = "Soul Rank",
        Friendship = "Friendship Rank",
        PassiveSkill = "Passive Skill",
        Text_No = "No.",
        Text_NumberValue = "Number Value",
        Text_SuffixValue = "Suffix Value",
        Text_0 = "Leading Zero",
        Text_Lv = "Lv",
        Text_LevelValue = "Level Value",
        Image_RankIcon = "Rank Icon",
        Image_SoulIcon = "Soul Icon",
        Text_SoulValue = "Soul Value",
        Image_FriendshipIcon = "Friendship Icon",
        Text_FriendshipValue = "Friendship Value",
        Image_PassiveSkillIcon = "Passive Skill Icon",
        Text_PassiveSkillName = "Passive Skill Name",
        Text_TalentValue = "Talent Value",
        Image_GenderIcon = "Gender Icon",
        Image_GenderIconBG = "Gender Icon Background",
        Image_Background = "Background",
    }

    return special[value]
        or HumanizeIdentifier(value)

end


local function GetSectionAndLabel(registration, item)

    if item.metadata.section then
        return tostring(item.metadata.section), item.label
    end

    if registration.SectionTitle then
        return registration.SectionTitle, item.label
    end

    local parts = SplitPath(item.path)

    if parts[1] == "DisplayOption" then

        if #parts >= 3 then
            return "Display Options - "
                .. HumanizePathPart(parts[2]),
                item.label
        end

        return "Display Options", item.label
    end

    if parts[1] == "UI" then

        if parts[2] == "Normal"
            or parts[2] == "Party" then

            return "UI Layout - "
                .. HumanizePathPart(parts[2]),
                item.label
        end

        if parts[2] == "PassiveSkill"
            and parts[3] then

            local section =
                "UI Layout - Passive Skill "
                .. HumanizePathPart(parts[3])

            local label = item.label

            if #parts >= 5 then
                label = HumanizePathPart(parts[#parts - 1])
                    .. " - "
                    .. HumanizePathPart(parts[#parts])
            end

            return section, label
        end

        if #parts == 2 then
            return "UI Layout - General", item.label
        end

        local section =
            "UI Layout - "
            .. HumanizePathPart(parts[2] or "General")

        local label = item.label

        if #parts >= 4 then
            label = HumanizePathPart(parts[#parts - 1])
                .. " - "
                .. HumanizePathPart(parts[#parts])
        end

        return section, label
    end

    if parts[1] == "PageSkip" then
        return "Page Skip", item.label
    end

    return registration.ConfigId, item.label

end


local function AddOptionToSection(
    sectionsByTitle,
    sectionOrder,
    sectionTitle,
    option
)

    local section = sectionsByTitle[sectionTitle]

    if not section then

        section = {
            title = sectionTitle,
            options = {},
        }

        sectionsByTitle[sectionTitle] = section
        sectionOrder[#sectionOrder + 1] = sectionTitle
    end

    section.options[#section.options + 1] = option

end


local function BuildNormalOption(
    registration,
    item,
    stagingKey
)

    local kind = GetScalarKind(item)

    if not kind then
        return nil,
            "Unsupported @darn setting type for "
            .. tostring(item.path)
    end

    local option = {
        path = stagingKey,
        label = item.label,
        kind = kind,
        live = item.metadata.restart ~= true,
    }

    if item.description ~= "" then
        option.help = item.description
    end

    if kind == "number" then

        option.min = item.metadata.min
        option.max = item.metadata.max
        option.step = item.metadata.step

        local defaultNumber = tonumber(item.rawValue)
        local step = tonumber(item.metadata.step)
        local minimum = tonumber(item.metadata.min)
        local maximum = tonumber(item.metadata.max)

        if defaultNumber
            and defaultNumber % 1 == 0
            and (not step or step % 1 == 0)
            and (not minimum or minimum % 1 == 0)
            and (not maximum or maximum % 1 == 0) then

            option.integer = true
        end

    elseif kind == "text" then

        option.maxLen =
            item.metadata.maxLen
            or item.metadata.maxlen

        option.minLen =
            item.metadata.minLen
            or item.metadata.minlen

    elseif kind == "enum" then

        local choices =
            item.metadata.choices
            or item.metadata.values

        if type(choices) == "string" then

            option.values = {}

            for choice in choices:gmatch("[^|]+") do
                option.values[#option.values + 1] = Trim(choice)
            end

        elseif type(choices) == "table" then
            option.values = choices
        end

        if not option.values or #option.values == 0 then
            return nil,
                "Enum @darn setting has no choices: "
                .. tostring(item.path)
        end

    end

    return option

end


local function ReadManagerScalarValues(registration)

    if not registration.Manager
        or type(registration.Manager.ReadSourceValues) ~= "function" then

        return nil,
            "ConfigManager v1.0.6+ is required for DarnMenu integration."
    end

    return registration.Manager:ReadSourceValues()

end


local function BuildGroupModel(group)

    local schemaDefaults = {}
    local currentValues = {}
    local routes = {}
    local sectionsByTitle = {}
    local sectionOrder = {}

    local configIds = {}

    for configId in pairs(group.Configs) do
        configIds[#configIds + 1] = configId
    end

    table.sort(configIds)

    for _, configId in ipairs(configIds) do

        local registration = group.Configs[configId]
        local defaultSource = registration.Manager:ReadDefaultSource()
        local userSource = registration.Manager:ReadSource()

        if not defaultSource or not userSource then
            return nil,
                "Could not read config sources for "
                .. tostring(configId)
        end

        local annotatedItems, annotationError =
            DarnMenuIntegration.ParseAnnotatedConfig(defaultSource)

        if not annotatedItems then
            return nil, annotationError
        end

        local sourceValues, sourceError =
            ReadManagerScalarValues(registration)

        if not sourceValues then
            return nil, sourceError
        end

        local hasDisplayMode = false

        for _, item in ipairs(annotatedItems) do

            if item.kind == "displaymode" then
                hasDisplayMode = true

            else

                local stagingKey =
                    MakeStagingKey(
                        configId,
                        item.path
                    )

                local option, optionError =
                    BuildNormalOption(
                        registration,
                        item,
                        stagingKey
                    )

                if not option then
                    return nil, optionError
                end

                local sectionTitle, label =
                    GetSectionAndLabel(
                        registration,
                        item
                    )

                option.label = label

                local defaultValue =
                    RawValueToLua(
                        item.rawValue,
                        item.kind
                    )

                local currentEntry = sourceValues[item.path]
                local currentValue = defaultValue

                if currentEntry then
                    currentValue =
                        RawValueToLua(
                            currentEntry.rawValue,
                            item.kind
                        )
                end

                if defaultValue == nil
                    and currentValue == nil then

                    return nil,
                        "Could not decode @darn value for "
                        .. tostring(item.path)
                end

                schemaDefaults[stagingKey] = defaultValue
                currentValues[stagingKey] = currentValue

                routes[stagingKey] = {
                    type = "scalar",
                    registration = registration,
                    path = item.path,
                    kind = item.kind,
                }

                AddOptionToSection(
                    sectionsByTitle,
                    sectionOrder,
                    sectionTitle,
                    option
                )

            end

        end

        if hasDisplayMode then

            local userModel, userModelError =
                DarnMenuIntegration.GetDisplayModeModel(userSource)

            if not userModel then
                return nil, userModelError
            end

            local defaultModel =
                DarnMenuIntegration.GetDisplayModeModel(defaultSource)

            if type(defaultModel) ~= "table" then
                defaultModel = {}
            end

            for hotkeyIndex, hotkey in ipairs(userModel) do

                local sectionTitle = "Display Mode"

                if #userModel > 1 then
                    sectionTitle = sectionTitle
                        .. " - Hotkey "
                        .. tostring(hotkeyIndex)
                end

                local hotkeyStagingKey =
                    MakeStagingKey(
                        configId,
                        "DisplayMode",
                        hotkeyIndex,
                        "Hotkey"
                    )

                local currentKeyName =
                    KeyExpressionToName(hotkey.expression)

                local defaultExpression =
                    defaultModel[hotkeyIndex]
                    and defaultModel[hotkeyIndex].expression
                    or hotkey.expression

                local defaultKeyName =
                    KeyExpressionToName(defaultExpression)
                    or currentKeyName

                schemaDefaults[hotkeyStagingKey] = defaultKeyName
                currentValues[hotkeyStagingKey] = currentKeyName

                routes[hotkeyStagingKey] = {
                    type = "displaymode_hotkey",
                    registration = registration,
                    hotkeyIndex = hotkeyIndex,
                }

                AddOptionToSection(
                    sectionsByTitle,
                    sectionOrder,
                    sectionTitle,
                    {
                        path = hotkeyStagingKey,
                        label = "Hotkey",
                        kind = "keycapture",
                        live = true,
                        help = "Changes the key assigned to this DisplayMode. The State structure and Gamepad assignment are preserved.",
                    }
                )

                local section = sectionsByTitle[sectionTitle]

                ------------------------------------------------
                -- Optional Gamepad assignment belonging to this
                -- DisplayMode hotkey table.
                ------------------------------------------------

                if hotkey.gamepadButton
                    and hotkey.gamepadButton.explicit then

                    local gamepadStagingKey =
                        MakeStagingKey(
                            configId,
                            "DisplayMode",
                            hotkeyIndex,
                            "GamepadButton"
                        )

                    local defaultGamepadButton =
                        hotkey.gamepadButton.value

                    if defaultModel[hotkeyIndex]
                        and defaultModel[hotkeyIndex].gamepadButton
                        and defaultModel[hotkeyIndex].gamepadButton.explicit then

                        defaultGamepadButton =
                            defaultModel[hotkeyIndex]
                                .gamepadButton.value
                    end

                    schemaDefaults[gamepadStagingKey] =
                        defaultGamepadButton

                    currentValues[gamepadStagingKey] =
                        hotkey.gamepadButton.value

                    routes[gamepadStagingKey] = {
                        type = "displaymode_gamepad",
                        registration = registration,
                        hotkeyIndex = hotkeyIndex,
                    }

                    section.options[#section.options + 1] = {
                        path = gamepadStagingKey,
                        label = "Gamepad Button",
                        kind = "enum",
                        live = true,
                        values = DISPLAY_MODE_GAMEPAD_BUTTON_VALUES,
                        help = "Select the Right Stick input used to advance this DisplayMode. When Right Stick Press (R3) is selected, PalIconInfo uses R3 on supported PalBox screens. Delete Selection becomes unavailable in the Global PalBox, and Send All Pals becomes unavailable in the Dimensional Pal Storage.",
                    }

                end

                for stateIndex, state in ipairs(hotkey.states) do

                    section.options[#section.options + 1] = {
                        subtitle = "State " .. tostring(stateIndex),
                    }

                    for _, fieldPath in ipairs(DISPLAY_MODE_FIELDS) do

                        local field = state[fieldPath]
                        local fieldLabel =
                            DISPLAY_MODE_LABELS[fieldPath]
                            or HumanizeIdentifier(fieldPath)

                        local stagingKey =
                            MakeStagingKey(
                                configId,
                                "DisplayMode",
                                hotkeyIndex,
                                "State",
                                stateIndex,
                                fieldPath
                            )

                        local defaultValue = field.value

                        if defaultModel[hotkeyIndex]
                            and defaultModel[hotkeyIndex].states[stateIndex]
                            and defaultModel[hotkeyIndex].states[stateIndex][fieldPath] then

                            defaultValue =
                                defaultModel[hotkeyIndex]
                                    .states[stateIndex][fieldPath].value
                        end

                        schemaDefaults[stagingKey] = defaultValue
                        currentValues[stagingKey] = field.value

                        routes[stagingKey] = {
                            type = "displaymode_state",
                            registration = registration,
                            hotkeyIndex = hotkeyIndex,
                            stateIndex = stateIndex,
                            fieldPath = fieldPath,
                        }

                        section.options[#section.options + 1] = {
                            path = stagingKey,
                            -- DarnMenu has no dedicated indentation field.
                            -- Preserve the State subtitle as the parent row and
                            -- visually indent each child option with spaces.
                            label = "    " .. fieldLabel,
                            kind = "bool",
                            live = true,
                        }

                    end

                end

            end

        end

    end

    local function SectionPriority(title)

        if title == "Display Mode" then
            return 10
        end

        local hotkeyIndex =
            title:match("^Display Mode %- Hotkey (%d+)$")

        if hotkeyIndex then
            return 10 + tonumber(hotkeyIndex) / 100
        end

        local displayOptionPriority = {
            ["Display Options"] = 20,
            ["Display Options - Soul Rank"] = 21,
            ["Display Options - Friendship Rank"] = 22,
            ["Display Options - Passive Skill"] = 23,
            ["Display Options - Talent"] = 24,
        }

        if displayOptionPriority[title] then
            return displayOptionPriority[title]
        end

        local uiPriority = {
            ["UI Layout - General"] = 30,
            ["UI Layout - Normal"] = 31,
            ["UI Layout - Party"] = 32,
            ["UI Layout - Palpedia Number"] = 33,
            ["UI Layout - Level"] = 34,
            ["UI Layout - Gender"] = 35,
            ["UI Layout - Condensation Rank"] = 36,
            ["UI Layout - Friendship Rank"] = 37,
            ["UI Layout - Soul Rank"] = 38,
            ["UI Layout - Passive Skill Bar"] = 39,
            ["UI Layout - Passive Skill Name"] = 40,
            ["UI Layout - Talent"] = 41,
        }

        if uiPriority[title] then
            return uiPriority[title]
        end

        if title == "Page Skip" then
            return 50
        end

        return 100

    end

    table.sort(
        sectionOrder,
        function(a, b)
            local pa = SectionPriority(a)
            local pb = SectionPriority(b)
            if pa ~= pb then return pa < pb end
            return a < b
        end
    )

    local sections = {}

    for _, title in ipairs(sectionOrder) do
        sections[#sections + 1] = sectionsByTitle[title]
    end

    return {
        defaults = schemaDefaults,
        current = currentValues,
        routes = routes,
        sections = sections,
    }

end


local SPLIT_SCHEMA_SUFFIXES = {
    "DisplayMode",
    "DisplayOptions",
    "OverlayPosition",
    "PageSkip",
}


local function EscapeLuaPattern(value)

    return tostring(value):gsub("([^%w])", "%%%1")

end


-- DarnMenu treats every schema entry as an independent MOD page. PalIconInfo
-- therefore uses exactly one schema named after the actual MOD and keeps the
-- major setting groups as sections inside that page.
local function WriteSchemaIndex(group)

    local indexPath =
        group.SharedDir
        .. "DarnMenu_schema_index.lua"

    local list = {}
    local existingText = ReadFile(indexPath)

    if existingText then

        local chunk, loadError = loadfile(indexPath)

        if not chunk then
            return false,
                "Existing DarnMenu schema index could not be loaded: "
                .. tostring(loadError)
        end

        local ok, existing = pcall(chunk)

        if not ok or type(existing) ~= "table" then
            return false,
                "Existing DarnMenu schema index is invalid."
        end

        local ownPrefix =
            "^" .. EscapeLuaPattern(group.SchemaName) .. "_"

        for _, name in ipairs(existing) do

            if type(name) == "string"
                and name ~= group.SchemaName
                and not name:match(ownPrefix) then

                list[#list + 1] = name
            end

        end

    end

    list[#list + 1] = group.SchemaName

    local source = "return " .. SerializeLua(list, 0) .. "\n"

    if not WriteFile(indexPath, source) then
        return false,
            "Failed to write DarnMenu schema index: "
            .. tostring(indexPath)
    end

    return true

end


local function WriteSchema(group, model)

    local schema = {
        schemaVersion = group.SchemaVersion,
        tab = group.Tab,
        target = group.Target,
        order = group.Order,
        note = group.Note,
        applyNote = group.ApplyNote,
        defaults = model.defaults,
        sections = model.sections,
    }

    local schemaPath =
        group.SharedDir
        .. "DarnMenu_schema_"
        .. group.SchemaName
        .. ".lua"

    local source = "return " .. SerializeLua(schema, 0) .. "\n"

    if not WriteFile(schemaPath, source) then
        return false,
            "Failed to write DarnMenu schema file: "
            .. tostring(schemaPath)
    end

    return true

end


local function RemoveSplitSchemaFiles(group)

    -- v0.3.2 generated four pseudo-MOD schema names. DarnMenu correctly
    -- identifies those as pages whose MOD folders do not exist, so remove them.
    for _, suffix in ipairs(SPLIT_SCHEMA_SUFFIXES) do

        os.remove(
            group.SharedDir
            .. "DarnMenu_schema_"
            .. group.SchemaName
            .. "_"
            .. suffix
            .. ".lua"
        )

    end

end


local function WriteStaging(group, values)

    local source = "return " .. SerializeLua(values, 0) .. "\n"

    if not WriteFile(group.TargetPath, source) then
        return false,
            "Failed to write DarnMenu staging config: "
            .. tostring(group.TargetPath)
    end

    group.LastTargetText = source
    group.LastStagingValues = values

    return true

end


local function RebuildGroup(group)

    local model, modelError = BuildGroupModel(group)

    if not model then
        return false, modelError
    end

    RemoveSplitSchemaFiles(group)

    local schemaWritten, schemaError =
        WriteSchema(group, model)

    if not schemaWritten then
        return false, schemaError
    end

    local indexed, indexError =
        WriteSchemaIndex(group)

    if not indexed then
        return false, indexError
    end

    local staged, stagingError = WriteStaging(group, model.current)

    if not staged then
        return false, stagingError
    end

    group.Routes = model.routes
    group.LastManagerTexts = {}

    for configId, registration in pairs(group.Configs) do
        group.LastManagerTexts[configId] =
            registration.Manager:ReadSource()
    end

    Log(
        group,
        "DarnMenu schema synchronized:",
        group.SchemaName,
        "pages =",
        "1",
        "options =",
        tostring((function()
            local count = 0
            for _ in pairs(model.routes) do count = count + 1 end
            return count
        end)())
    )

    return true

end


local function LoadStaging(path)

    local chunk, loadError = loadfile(path)

    if not chunk then
        return nil, loadError
    end

    local ok, value = pcall(chunk)

    if not ok then
        return nil, value
    end

    if type(value) ~= "table" then
        return nil, "DarnMenu staging config did not return a table."
    end

    return value

end


local function ApplyStagingChanges(group, changedValues)

    local buckets = {}

    for stagingKey, value in pairs(changedValues) do

        local route = group.Routes[stagingKey]

        if route then

            local registration = route.registration
            local configId = registration.ConfigId

            local bucket = buckets[configId]

            if not bucket then
                bucket = {
                    registration = registration,
                    scalar = {},
                    states = {},
                    hotkeys = {},
                    gamepad = {},
                }
                buckets[configId] = bucket
            end

            if route.type == "scalar" then

                if route.kind == "hotkey" then

                    local expression = KeyNameToExpression(value)

                    if not expression then
                        return false,
                            "Invalid hotkey name from DarnMenu: "
                            .. tostring(value)
                    end

                    bucket.scalar[route.path] = {
                        RawValue = expression,
                    }

                else
                    bucket.scalar[route.path] = value
                end

            elseif route.type == "displaymode_state" then

                bucket.states[#bucket.states + 1] = {
                    hotkeyIndex = route.hotkeyIndex,
                    stateIndex = route.stateIndex,
                    fieldPath = route.fieldPath,
                    value = value,
                }

            elseif route.type == "displaymode_hotkey" then

                local expression = KeyNameToExpression(value)

                if not expression then
                    return false,
                        "Invalid DisplayMode hotkey name from DarnMenu: "
                        .. tostring(value)
                end

                bucket.hotkeys[route.hotkeyIndex] = expression

            elseif route.type == "displaymode_gamepad" then

                if type(value) ~= "string"
                    or not DISPLAY_MODE_GAMEPAD_BUTTON_SET[
                        value
                    ] then

                    return false,
                        "Invalid DisplayMode Gamepad button from DarnMenu: "
                        .. tostring(value)
                end

                bucket.gamepad[route.hotkeyIndex] = value
            end

        end

    end

    for _, bucket in pairs(buckets) do

        local manager = bucket.registration.Manager

        if next(bucket.scalar) ~= nil then

            local ok, updateError =
                manager:UpdateValues(bucket.scalar)

            if not ok then
                return false, updateError
            end

        end

        if #bucket.states > 0
            or next(bucket.hotkeys) ~= nil
            or next(bucket.gamepad) ~= nil then

            local sourceText = manager:ReadSource()

            if not sourceText then
                return false,
                    "Could not read config source for DisplayMode update."
            end

            local changed = false

            ------------------------------------------------
            -- GamepadButton belongs to the hotkey table itself.
            -- Apply it by source-order index before changing the
            -- hotkey expression, so F1 -> F2 keeps the assignment.
            ------------------------------------------------

            local gamepadIndices = {}

            for hotkeyIndex in pairs(
                bucket.gamepad
            ) do
                gamepadIndices[#gamepadIndices + 1] =
                    hotkeyIndex
            end

            table.sort(gamepadIndices)

            for _, hotkeyIndex in ipairs(
                gamepadIndices
            ) do

                local updated,
                    changedOrError =
                    DarnMenuIntegration.UpdateDisplayModeGamepadButtonSource(
                        sourceText,
                        hotkeyIndex,
                        bucket.gamepad[hotkeyIndex]
                    )

                if not updated then
                    return false, changedOrError
                end

                sourceText = updated
                changed =
                    changed
                    or changedOrError == true

            end

            table.sort(
                bucket.states,
                function(a, b)
                    if a.hotkeyIndex ~= b.hotkeyIndex then
                        return a.hotkeyIndex < b.hotkeyIndex
                    end
                    if a.stateIndex ~= b.stateIndex then
                        return a.stateIndex < b.stateIndex
                    end
                    return a.fieldPath < b.fieldPath
                end
            )

            for _, stateChange in ipairs(bucket.states) do

                if type(stateChange.value) ~= "boolean" then
                    return false,
                        "DisplayMode values from DarnMenu must be boolean."
                end

                local updated, changedOrError =
                    DarnMenuIntegration.UpdateDisplayModeStateSource(
                        sourceText,
                        stateChange.hotkeyIndex,
                        stateChange.stateIndex,
                        stateChange.fieldPath,
                        stateChange.value
                    )

                if not updated then
                    return false, changedOrError
                end

                sourceText = updated
                changed = changed or changedOrError == true

            end

            local rekeyed, rekeyedOrError =
                DarnMenuIntegration.UpdateDisplayModeHotkeysSource(
                    sourceText,
                    bucket.hotkeys
                )

            if not rekeyed then
                return false, rekeyedOrError
            end

            sourceText = rekeyed
            changed = changed or rekeyedOrError == true

            if changed then

                local written, writeError =
                    manager:WriteSource(
                        sourceText,
                        "DarnMenu DisplayMode settings updated"
                    )

                if not written then
                    return false, writeError
                end

            end

        end

    end

    return true

end


local function PollGroup(group)

    local targetText = ReadFile(group.TargetPath)

    if targetText
        and targetText ~= group.LastTargetText then

        local staged, stagingError =
            LoadStaging(group.TargetPath)

        group.LastTargetText = targetText

        if not staged then

            Log(
                group,
                "DarnMenu staging config load failed:",
                tostring(stagingError)
            )

            RebuildGroup(group)
            return
        end

        local changedValues = {}

        for key, value in pairs(staged) do

            local previous =
                group.LastStagingValues
                and group.LastStagingValues[key]
                or nil

            if not ValuesEqual(previous, value) then
                changedValues[key] = value
            end

        end

        if next(changedValues) ~= nil then

            local applied, applyError =
                ApplyStagingChanges(
                    group,
                    changedValues
                )

            if not applied then

                Log(
                    group,
                    "DarnMenu config apply failed:",
                    tostring(applyError)
                )

            else

                Log(
                    group,
                    "DarnMenu settings applied to user config."
                )

            end

        end

        local rebuilt, rebuildError = RebuildGroup(group)

        if not rebuilt then
            Log(
                group,
                "DarnMenu synchronization failed:",
                tostring(rebuildError)
            )
        end

        return
    end

    local managerChanged = false

    for configId, registration in pairs(group.Configs) do

        local currentText = registration.Manager:ReadSource()

        if currentText ~= group.LastManagerTexts[configId] then
            managerChanged = true
            break
        end

    end

    if managerChanged then

        local rebuilt, rebuildError = RebuildGroup(group)

        if not rebuilt then
            Log(
                group,
                "DarnMenu synchronization failed:",
                tostring(rebuildError)
            )
        end

    end

end


local function StartGroupWatch(group)

    if group.WatchStarted then
        return
    end

    if type(ExecuteWithDelay) ~= "function" then
        return
    end

    group.WatchStarted = true

    local function WatchLoop()

        if not IsCurrentRuntimeGeneration() then
            return
        end

        PollGroup(group)

        ExecuteWithDelay(
            group.PollMs,
            WatchLoop
        )

    end

    ExecuteWithDelay(
        group.PollMs,
        WatchLoop
    )

end


-- Register a successfully loaded ConfigManager instance automatically.
--
-- The integration metadata is derived from the user config path so the
-- ConfigManager caller does not need to know anything about DarnMenu:
--
--   Mods\shared\PalIconInfo\PalIconInfoConfig.lua
--       -> Schema / tab: PalIconInfo
--       -> Config ID:    PalIconInfo
--       -> Target:       PalIconInfo_DarnMenu_user.lua
--
-- Additional configs in the same shared subfolder are merged into the same
-- DarnMenu page and staging file. A config without any @darn annotations is
-- ignored successfully.
function DarnMenuIntegration.RegisterConfigManager(manager)

    if not manager
        or type(manager.GetConfigPath) ~= "function"
        or type(manager.ReadDefaultSource) ~= "function" then

        return false,
            "A loaded ConfigManager instance is required."
    end

    local configPath =
        manager:GetConfigPath()

    local sharedDir =
        DeriveSharedDirectory(configPath)

    if not sharedDir then

        -- Configs outside Mods/shared are simply not DarnMenu-managed.
        return true
    end

    local defaultSource =
        manager:ReadDefaultSource()

    if not defaultSource then
        return false,
            "Could not read the bundled default config for DarnMenu integration."
    end

    local annotatedItems, annotationError =
        DarnMenuIntegration.ParseAnnotatedConfig(defaultSource)

    if not annotatedItems then
        return false, annotationError
    end

    if #annotatedItems == 0 then

        -- The config intentionally exposes nothing to DarnMenu.
        return true
    end

    local configId =
        GetConfigIdFromPath(configPath)

    local schemaName =
        GetSchemaNameFromPath(
            configPath,
            sharedDir
        )

    if not configId
        or configId == ""
        or not schemaName
        or schemaName == "" then

        return false,
            "Could not derive DarnMenu registration names from ConfigPath."
    end

    local logger = nil

    if type(manager.GetLogger) == "function" then
        logger = manager:GetLogger()
    end

    return DarnMenuIntegration.RegisterConfig({

        ConfigId = configId,

        SchemaName = schemaName,
        Tab = schemaName,

        Target = schemaName .. "_DarnMenu_user",

        SharedDir = sharedDir,

        Manager = manager,
        Log = logger,

    })

end


-- Register one ConfigManager-backed config as part of a DarnMenu page.
-- Multiple configs may use the same SchemaName/Target; they are merged into
-- a single page and one flat DarnMenu staging file.
function DarnMenuIntegration.RegisterConfig(options)

    if type(options) ~= "table" then
        return false, "DarnMenu registration options are required."
    end

    local manager = options.Manager

    if not manager
        or type(manager.ReadSource) ~= "function"
        or type(manager.ReadDefaultSource) ~= "function"
        or type(manager.ReadSourceValues) ~= "function"
        or type(manager.UpdateValues) ~= "function"
        or type(manager.WriteSource) ~= "function" then

        return false,
            "ConfigManager v1.0.6+ instance is required."
    end

    local configId = tostring(options.ConfigId or "")
    local schemaName = tostring(options.SchemaName or "PalIconInfo")
    local target = tostring(options.Target or "PalIconInfo_DarnMenu_user")

    if configId == "" then
        return false, "ConfigId is required."
    end

    if not schemaName:match("^[%w_.%-]+$") then
        return false, "SchemaName contains unsupported characters."
    end

    if not target:match("^[%w_.%-]+_user$") then
        return false,
            "DarnMenu target must be a plain file name ending in _user."
    end

    local sharedDir =
        options.SharedDir
        or DeriveSharedDirectory(
            manager:GetConfigPath()
        )

    if not sharedDir then
        return false,
            "Could not determine Mods/shared directory from ConfigPath."
    end

    local group = IntegrationGroups[schemaName]

    if not group then

        group = {
            SchemaName = schemaName,
            SchemaVersion = tonumber(options.SchemaVersion) or 1,
            Tab = tostring(options.Tab or schemaName),
            Target = target,
            Order = tonumber(options.Order) or 100,
            Note = options.Note
                or "Settings are synchronized to PalIconInfo config files. Amber settings require a game or MOD restart.",
            ApplyNote = options.ApplyNote
                or "Saved. See the dots for settings that require a restart.",
            SharedDir = sharedDir,
            TargetPath = sharedDir .. target .. ".lua",
            PollMs = tonumber(options.PollMs) or 1000,
            Configs = {},
            Routes = {},
            LastManagerTexts = {},
            LastStagingValues = {},
            LastTargetText = nil,
            WatchStarted = false,
            Log = options.Log,
        }

        IntegrationGroups[schemaName] = group

    else

        if group.Target ~= target then
            return false,
                "All configs in one DarnMenu schema must use the same target."
        end

        if group.SharedDir ~= sharedDir then
            return false,
                "All configs in one DarnMenu schema must use the same shared directory."
        end

        if options.Log then
            group.Log = options.Log
        end

    end

    group.Configs[configId] = {
        ConfigId = configId,
        Manager = manager,
        SectionTitle = options.SectionTitle,
    }

    local rebuilt, rebuildError = RebuildGroup(group)

    if not rebuilt then
        return false, rebuildError
    end

    StartGroupWatch(group)

    return true

end


-- Exposed mainly for testing/manual resynchronization.
function DarnMenuIntegration.Sync(schemaName)

    local group = IntegrationGroups[schemaName or "PalIconInfo"]

    if not group then
        return false, "DarnMenu integration group is not registered."
    end

    return RebuildGroup(group)

end


DarnMenuIntegration.DisplayModeFields =
    DISPLAY_MODE_FIELDS

DarnMenuIntegration.DisplayModeLabels =
    DISPLAY_MODE_LABELS


return DarnMenuIntegration

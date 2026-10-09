------------------------------------------------
-- ConfigManager
-- Version: 1.1.0
--
-- Shared manager for user-editable configuration files.
--
-- Responsibilities:
--   - Create a user config from the bundled default config
--   - Detect config version changes
--   - Migrate user-edited scalar values onto the new default
--   - Preserve comments, formatting, and newly added settings
--     from the new default source
--   - Replace selected top-level tables entirely with the
--     existing user's table instead of recursively merging them
--   - Optionally upgrade preserved ReplaceTables source before replacement
--   - Back up the previous user config as .bak
--   - Detect runtime file edits and provide the reloaded table
--   - Notify optional configuration integrations after a successful load
--
-- Each config file creates its own manager instance.
------------------------------------------------
------------------------------------------------
-- Changelog
------------------------------------------------
-- Version 1.1.0 - 2026-09-06
-- - Improved source-preserving config migration and recovery.
-- - Added validated source read/write support for optional external configuration integrations.
-- - Added optional source transforms for preserved ReplaceTables during config migration.
--
-- Version 1.0.0 - 2026-09-04
-- - Initial release.
------------------------------------------------

local ConfigManager = {}

------------------------------------------------
-- Logging
------------------------------------------------

local function LogManager(self, ...)

    if self and type(self.Log) == "function" then

        local ok = pcall(
            self.Log,
            ...
        )

        if ok then
            return
        end

    end

    print("[ConfigManager]", ...)

end


------------------------------------------------
-- Optional Configuration Integration
--
-- ConfigManager itself does not implement any external configuration UI.
-- If DarnMenuIntegration.lua is present, a successfully loaded manager is
-- passed to that module. Missing or failed optional integration must never
-- prevent the underlying MOD/config from loading.
------------------------------------------------

local OptionalIntegrationChecked = false
local OptionalIntegration = nil


local function GetOptionalIntegration()

    if OptionalIntegrationChecked then
        return OptionalIntegration
    end

    OptionalIntegrationChecked = true

    local ok, module =
        pcall(
            require,
            "DarnMenuIntegration"
        )

    if ok
        and type(module) == "table"
        and type(module.RegisterConfigManager) == "function" then

        OptionalIntegration = module
    end

    return OptionalIntegration

end


local function NotifyOptionalIntegration(self)

    if not self
        or self.OptionalIntegrationNotified then

        return
    end

    self.OptionalIntegrationNotified = true

    local integration =
        GetOptionalIntegration()

    if not integration then
        return
    end

    local ok, result, errorMessage =
        pcall(
            integration.RegisterConfigManager,
            self
        )

    if not ok then

        LogManager(
            self,
            "Optional config integration failed:",
            tostring(result)
        )

        return
    end

    if result == false then

        LogManager(
            self,
            "Optional config integration failed:",
            tostring(errorMessage)
        )

    end

end


local function CountEntries(value)

    local count = 0

    for _ in pairs(value or {}) do
        count = count + 1
    end

    return count

end


------------------------------------------------
-- File Utilities
------------------------------------------------

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


local function CopyFile(sourcePath, destinationPath)

    local text = ReadFile(sourcePath)

    if not text then
        return false
    end

    return WriteFile(
        destinationPath,
        text
    )

end


------------------------------------------------
-- Directory Utilities
------------------------------------------------

-- Returns the parent directory portion of a file path.
local function GetParentDirectory(path)

    if type(path) ~= "string" then
        return nil
    end

    return path:match(
        "^(.*)[/\\][^/\\]+$"
    )

end


-- Verify that a directory exists and is writable by creating and
-- immediately removing a small temporary probe file.
local function IsDirectoryWritable(path)

    if type(path) ~= "string"
        or path == "" then

        return false
    end

    local separator =
        (package.config and package.config:sub(1, 1))
        or "\\"

    local probePath =
        path
        .. separator
        .. ".configmanager_write_test.tmp"

    local file = io.open(
        probePath,
        "w"
    )

    if not file then
        return false
    end

    file:close()
    os.remove(probePath)

    return true

end


-- Create the directory recursively using the platform shell.
-- ConfigPath is supplied by the MOD itself rather than user input.
local function CreateDirectoryRecursive(path)

    if type(path) ~= "string"
        or path == "" then

        return false,
            "Directory path is empty."
    end

    -- A quote would break shell quoting. Reject it rather than executing
    -- an ambiguous command. Normal filesystem paths do not contain quotes.
    if path:find("\"", 1, true) then

        return false,
            "Directory path contains an unsupported quote character: "
            .. path
    end

    local separator =
        (package.config and package.config:sub(1, 1))
        or "\\"

    local command

    if separator == "\\" then

        command =
            'mkdir "'
            .. path
            .. '" >nul 2>nul'

    else

        command =
            'mkdir -p "'
            .. path:gsub('"', '\\"')
            .. '" >/dev/null 2>&1'

    end

    local okCall, result1, _, result3 =
        pcall(
            os.execute,
            command
        )

    if not okCall then

        return false,
            "Failed to execute directory creation command: "
            .. tostring(result1)
    end

    local commandSucceeded =
        result1 == true
        or result1 == 0
        or result3 == 0

    if not commandSucceeded then

        return false,
            "Directory creation command failed."
    end

    return true

end


-- Ensure that ConfigPath's parent directory exists before any config,
-- temporary, or backup file is written there.
local function EnsureParentDirectory(filePath)

    local parentDirectory =
        GetParentDirectory(filePath)

    -- A simple filename has no parent directory to create.
    if not parentDirectory
        or parentDirectory == "" then

        return true, nil, false
    end

    if IsDirectoryWritable(parentDirectory) then
        return true, parentDirectory, false
    end

    local created, createError =
        CreateDirectoryRecursive(
            parentDirectory
        )

    if not created then
        return false, createError, false
    end

    if not IsDirectoryWritable(parentDirectory) then

        return false,
            "Directory was created or already existed, but is not writable: "
            .. parentDirectory,
            false
    end

    return true, parentDirectory, true

end


------------------------------------------------
-- Config Loading
------------------------------------------------

local function LoadConfigFile(path)

    local chunk, compileError = loadfile(path)

    if not chunk then
        return nil, compileError
    end

    local ok, result = pcall(chunk)

    if not ok then
        return nil, result
    end

    if type(result) ~= "table" then
        return nil,
            "Config did not return a table."
    end

    return result

end


------------------------------------------------
-- Version
------------------------------------------------

local function GetConfigVersion(text)

    if not text then
        return nil
    end

    -- Expected header:
    -- -- Version: 1.2.1a
    local version =
        text:match(
            "%-%-%s*Version:%s*([^\r\n]+)"
        )

    if version then
        version = version:gsub("%s+$", "")
    end

    return version

end


------------------------------------------------
-- Value Serialization
------------------------------------------------

local function SerializeValue(value)

    local valueType = type(value)

    if valueType == "boolean" then
        return value and "true" or "false"
    end

    if valueType == "number" then
        return tostring(value)
    end

    if valueType == "string" then
        return string.format("%q", value)
    end

    return nil

end


------------------------------------------------
-- Extract User Values
--
-- Extract scalar values from the existing user config.
-- Values are indexed by their complete table path, e.g.
--
--   DisplayOption.Talent.GreenThreshold
--   UI.Party.OffsetX
--
-- Top-level tables listed in ReplaceTables are intentionally
-- excluded from scalar migration because they are handled
-- separately as whole-table source replacements.
------------------------------------------------

local function ExtractUserValues(
    config,
    replaceTables
)

    local values = {}

    local function Walk(value, path)

        if type(value) ~= "table" then
            return
        end

        for key, child in pairs(value) do

            if type(key) == "string" then

                local childPath

                if path == "" then
                    childPath = key
                else
                    childPath = path .. "." .. key
                end

                if type(child) == "table" then

                    if path == ""
                        and replaceTables[key] then

                        ------------------------------------------------
                        -- Keep the entire table from the new default.
                        ------------------------------------------------

                    else

                        Walk(
                            child,
                            childPath
                        )

                    end

                elseif type(child) == "boolean"
                    or type(child) == "number"
                    or type(child) == "string" then

                    values[childPath] = {
                        value = child,
                        valueType = type(child),
                    }

                end

            end

        end

    end

    Walk(config, "")

    return values

end


------------------------------------------------
-- Source Scanner Helpers
------------------------------------------------

local function IsIdentifierStart(c)
    return c ~= ""
        and c:match("[%a_]") ~= nil
end


local function IsIdentifierChar(c)
    return c ~= ""
        and c:match("[%w_]") ~= nil
end


local function ReadIdentifier(text, pos)

    if not IsIdentifierStart(
        text:sub(pos, pos)
    ) then
        return nil, pos
    end

    local startPos = pos

    pos = pos + 1

    while pos <= #text
        and IsIdentifierChar(
            text:sub(pos, pos)
        ) do

        pos = pos + 1

    end

    return text:sub(
        startPos,
        pos - 1
    ), pos

end


local function SkipWhitespace(text, pos)

    while pos <= #text do

        local c = text:sub(pos, pos)

        if c == " "
            or c == "\t"
            or c == "\r"
            or c == "\n" then

            pos = pos + 1

        else
            break
        end

    end

    return pos

end


------------------------------------------------
-- Skip Lua long-bracket strings/comments.
-- Supports [[...]], [=[...]=], [==[...]==], etc.
------------------------------------------------

local function SkipLongBracket(text, pos)

    if text:sub(pos, pos) ~= "[" then
        return nil
    end

    local eq = text:match(
        "^%[(=*)%[",
        pos
    )

    if eq == nil then
        return nil
    end

    local closeToken =
        "]" .. eq .. "]"

    local contentStart =
        pos + 2 + #eq

    local closePos =
        text:find(
            closeToken,
            contentStart,
            true
        )

    if closePos then
        return closePos + #closeToken
    end

    return #text + 1

end


local function SkipQuotedString(text, pos)

    local quote = text:sub(pos, pos)

    pos = pos + 1

    while pos <= #text do

        local c = text:sub(pos, pos)

        if c == "\\" then
            pos = pos + 2

        elseif c == quote then
            return pos + 1

        else
            pos = pos + 1
        end

    end

    return #text + 1

end


local function SkipComment(text, pos)

    ------------------------------------------------
    -- Long comment:
    -- --[[ ... ]]
    -- --[=[ ... ]=]
    ------------------------------------------------

    local longStart = pos + 2

    local longEnd =
        SkipLongBracket(
            text,
            longStart
        )

    if longEnd then
        return longEnd
    end

    ------------------------------------------------
    -- Single-line comment.
    ------------------------------------------------

    local newline =
        text:find(
            "\n",
            pos + 2,
            true
        )

    if newline then
        return newline + 1
    end

    return #text + 1

end


local function SkipTrivia(text, pos)

    while pos <= #text do

        local oldPos = pos

        pos = SkipWhitespace(
            text,
            pos
        )

        if text:sub(pos, pos + 1) == "--" then
            pos = SkipComment(
                text,
                pos
            )
        end

        if pos == oldPos then
            break
        end

    end

    return pos

end


------------------------------------------------
-- Find the opening brace of:
--
--   local Config = {
--
-- The bundled default config uses this structure so that
-- the source parser only has to process one root table.
------------------------------------------------

local function FindConfigRoot(text)

    local pos = 1

    while pos <= #text do

        pos = SkipTrivia(
            text,
            pos
        )

        if pos > #text then
            break
        end

        local c = text:sub(pos, pos)

        if c == "\"" or c == "'" then

            pos = SkipQuotedString(
                text,
                pos
            )

        elseif c == "[" then

            local longEnd =
                SkipLongBracket(
                    text,
                    pos
                )

            if longEnd then
                pos = longEnd
            else
                pos = pos + 1
            end

        elseif IsIdentifierStart(c) then

            local token, nextPos =
                ReadIdentifier(
                    text,
                    pos
                )

            if token == "local" then

                local checkPos =
                    SkipTrivia(
                        text,
                        nextPos
                    )

                local name, afterName =
                    ReadIdentifier(
                        text,
                        checkPos
                    )

                if name == "Config" then

                    checkPos =
                        SkipTrivia(
                            text,
                            afterName
                        )

                    if text:sub(
                        checkPos,
                        checkPos
                    ) == "=" then

                        checkPos =
                            SkipTrivia(
                                text,
                                checkPos + 1
                            )

                        if text:sub(
                            checkPos,
                            checkPos
                        ) == "{" then

                            return checkPos

                        end

                    end

                end

            end

            pos = nextPos

        else
            pos = pos + 1
        end

    end

    return nil

end


------------------------------------------------
-- Skip a complete table literal.
--
-- This is used for tables such as DisplayMode that are
-- intentionally replaced wholesale and may contain syntax
-- such as [Key.F1] and anonymous array entries.
------------------------------------------------

local function SkipTable(text, pos)

    if text:sub(pos, pos) ~= "{" then
        return pos
    end

    local depth = 1

    pos = pos + 1

    while pos <= #text
        and depth > 0 do

        local c = text:sub(pos, pos)

        if text:sub(pos, pos + 1) == "--" then

            pos = SkipComment(
                text,
                pos
            )

        elseif c == "\"" or c == "'" then

            pos = SkipQuotedString(
                text,
                pos
            )

        elseif c == "[" then

            local longEnd =
                SkipLongBracket(
                    text,
                    pos
                )

            if longEnd then
                pos = longEnd
            else
                pos = pos + 1
            end

        elseif c == "{" then

            depth = depth + 1
            pos = pos + 1

        elseif c == "}" then

            depth = depth - 1
            pos = pos + 1

        else
            pos = pos + 1
        end

    end

    return pos

end


------------------------------------------------
-- Find the end of a scalar value in the source.
--
-- Only boolean / number / quoted string values are migrated.
-- Unsupported expressions are left at the new default value.
------------------------------------------------

local function FindScalarEnd(text, pos)

    local c = text:sub(pos, pos)

    if c == "\"" or c == "'" then
        return SkipQuotedString(
            text,
            pos
        ) - 1
    end

    if c == "[" then

        local longEnd =
            SkipLongBracket(
                text,
                pos
            )

        if longEnd then
            return longEnd - 1
        end

    end

    local startPos = pos

    while pos <= #text do

        local ch = text:sub(pos, pos)

        if ch == ","
            or ch == "}"
            or ch == "\r"
            or ch == "\n" then

            break
        end

        if text:sub(pos, pos + 1) == "--" then
            break
        end

        pos = pos + 1

    end

    local endPos = pos - 1

    while endPos >= startPos do

        local ch = text:sub(
            endPos,
            endPos
        )

        if ch == " "
            or ch == "\t" then

            endPos = endPos - 1

        else
            break
        end

    end

    return endPos

end

------------------------------------------------
-- Top-Level Table Source
--
-- ReplaceTables are preserved as complete source table literals.
-- This keeps user-defined keys, array ordering, comments, and
-- expressions such as [Key.F1] intact.
------------------------------------------------

local function GetLineIndent(text, pos)

    local lineStart = 1
    local previousNewline =
        text:sub(1, pos - 1):match(".*()\n")

    if previousNewline then
        lineStart = previousNewline + 1
    end

    return text:sub(
        lineStart,
        pos - 1
    ):match("^[ \t]*") or ""

end


local function FindRootTopLevelTableRange(text, targetKey)

    local rootPos = FindConfigRoot(text)

    if not rootPos then
        return nil, nil,
            "Could not find 'local Config = {' root table."
    end

    local pos = rootPos + 1

    while pos <= #text do

        pos = SkipTrivia(text, pos)

        if pos > #text then
            break
        end

        local c = text:sub(pos, pos)

        if c == "}" then
            break

        elseif c == "\"" or c == "'" then

            pos = SkipQuotedString(text, pos)

        elseif c == "[" then

            local longEnd = SkipLongBracket(text, pos)

            if longEnd then
                pos = longEnd
            else
                pos = pos + 1
            end

        elseif IsIdentifierStart(c) then

            local key, nextPos = ReadIdentifier(text, pos)
            local checkPos = SkipTrivia(text, nextPos)

            if text:sub(checkPos, checkPos) == "=" then

                local valueStart = SkipTrivia(text, checkPos + 1)

                if text:sub(valueStart, valueStart) == "{" then

                    local afterTable = SkipTable(text, valueStart)
                    local valueEnd = afterTable - 1

                    if text:sub(valueEnd, valueEnd) ~= "}" then
                        return nil, nil,
                            "Top-level table '" .. tostring(key)
                            .. "' is not properly closed."
                    end

                    if key == targetKey then

                        return valueStart,
                            valueEnd,
                            nil,
                            GetLineIndent(text, pos)

                    end

                    pos = afterTable

                else

                    local valueEnd = FindScalarEnd(text, valueStart)
                    pos = valueEnd + 1

                end

            else
                pos = nextPos
            end

        else
            pos = pos + 1
        end

    end

    return nil, nil,
        "Top-level table not found in root config: "
        .. tostring(targetKey)

end


local function ReindentTableSource(
    rawSource,
    sourceIndent,
    targetIndent
)

    sourceIndent = sourceIndent or ""
    targetIndent = targetIndent or ""

    if sourceIndent == targetIndent then
        return rawSource
    end

    return (
        rawSource:gsub(
            "(\r?\n)([^\r\n]*)",
            function(eol, line)

                if line == "" then
                    return eol
                end

                local relative = line

                if sourceIndent == ""
                    or line:sub(1, #sourceIndent) == sourceIndent then

                    relative =
                        line:sub(
                            #sourceIndent + 1
                        )

                end

                return eol .. targetIndent .. relative

            end
        )
    )

end


------------------------------------------------
-- Parse scalar value positions from the bundled default.
--
-- Because migration starts from the new default source,
-- every comment, blank line, newly added setting, and new
-- table structure remains exactly as written in that file.
------------------------------------------------

local function ParseSource(
    text,
    replaceTables
)

    local values = {}
    local stack = {}

    local rootPos = FindConfigRoot(text)

    if not rootPos then
        return nil,
            "Could not find 'local Config = {' in default config."
    end

    local pos = rootPos + 1
    local length = #text

    local function CurrentPath(key)

        if #stack == 0 then
            return key
        end

        return table.concat(
            stack,
            "."
        ) .. "." .. key

    end

    while pos <= length do

        pos = SkipTrivia(
            text,
            pos
        )

        if pos > length then
            break
        end

        local c = text:sub(pos, pos)

        ------------------------------------------------
        -- Closing brace of the current named table.
        -- If the stack is empty, this closes Config itself.
        ------------------------------------------------

        if c == "}" then

            if #stack == 0 then
                break
            end

            table.remove(stack)
            pos = pos + 1

        elseif c == "\"" or c == "'" then

            pos = SkipQuotedString(
                text,
                pos
            )

        elseif c == "[" then

            local longEnd =
                SkipLongBracket(
                    text,
                    pos
                )

            if longEnd then
                pos = longEnd
            else
                pos = pos + 1
            end

        elseif IsIdentifierStart(c) then

            local key, nextPos =
                ReadIdentifier(
                    text,
                    pos
                )

            local checkPos =
                SkipTrivia(
                    text,
                    nextPos
                )

            if text:sub(
                checkPos,
                checkPos
            ) == "=" then

                local valueStart =
                    SkipTrivia(
                        text,
                        checkPos + 1
                    )

                if text:sub(
                    valueStart,
                    valueStart
                ) == "{" then

                    ------------------------------------------------
                    -- Replace selected top-level tables completely.
                    ------------------------------------------------

                    if #stack == 0
                        and replaceTables[key] then

                        pos = SkipTable(
                            text,
                            valueStart
                        )

                    else

                        table.insert(
                            stack,
                            key
                        )

                        pos = valueStart + 1

                    end

                else

                    local valueEnd =
                        FindScalarEnd(
                            text,
                            valueStart
                        )

                    local path =
                        CurrentPath(key)

                    values[path] = {
                        startPos = valueStart,
                        endPos = valueEnd,
                        rawValue = text:sub(
                            valueStart,
                            valueEnd
                        ),
                    }

                    pos = valueEnd + 1

                end

            else
                pos = nextPos
            end

        else
            pos = pos + 1
        end

    end

    return values

end




------------------------------------------------
-- Legacy Source Scanner
--
-- Older configs may use:
--
--   local Config = {}
--   Config.DisplayMode = { ... }
--   Config.DisplayOption = { ... }
--   Config.UI = { ... }
--
-- Recovery must support this form even when one earlier table
-- (for example DisplayMode) is missing its closing brace.
-- Each top-level Config.<Name> assignment is therefore located
-- independently before its contents are parsed.
------------------------------------------------

local function FindLegacyConfigAssignments(text)

    local assignments = {}
    local pos = 1

    while pos <= #text do

        if text:sub(pos, pos + 1) == "--" then

            pos = SkipComment(text, pos)

        else

            local c = text:sub(pos, pos)

            if c == "\"" or c == "'" then

                pos = SkipQuotedString(text, pos)

            elseif c == "[" then

                local longEnd = SkipLongBracket(text, pos)

                if longEnd then
                    pos = longEnd
                else
                    pos = pos + 1
                end

            elseif IsIdentifierStart(c) then

                local token, nextPos = ReadIdentifier(text, pos)

                if token == "Config" then

                    local checkPos = SkipTrivia(text, nextPos)

                    if text:sub(checkPos, checkPos) == "." then

                        checkPos = SkipTrivia(text, checkPos + 1)

                        local key, afterKey = ReadIdentifier(text, checkPos)

                        if key then

                            checkPos = SkipTrivia(text, afterKey)

                            if text:sub(checkPos, checkPos) == "=" then

                                local valueStart = SkipTrivia(text, checkPos + 1)

                                if text:sub(valueStart, valueStart) == "{" then

                                    assignments[#assignments + 1] = {
                                        key = key,
                                        assignmentStart = pos,
                                        valueStart = valueStart,
                                    }

                                    pos = valueStart + 1

                                else
                                    pos = nextPos
                                end

                            else
                                pos = nextPos
                            end

                        else
                            pos = nextPos
                        end

                    else
                        pos = nextPos
                    end

                else
                    pos = nextPos
                end

            else
                pos = pos + 1
            end

        end

    end

    return assignments

end



local function ExtractTopLevelTableSource(
    text,
    tableName
)

    ------------------------------------------------
    -- Current format:
    --
    --   local Config = {
    --       DisplayMode = { ... },
    --   }
    ------------------------------------------------

    local startPos, endPos, _, sourceIndent =
        FindRootTopLevelTableRange(
            text,
            tableName
        )

    if startPos and endPos then

        return text:sub(startPos, endPos),
            nil,
            "root table",
            sourceIndent

    end

    ------------------------------------------------
    -- Legacy format:
    --
    --   local Config = {}
    --   Config.DisplayMode = { ... }
    ------------------------------------------------

    local assignments =
        FindLegacyConfigAssignments(text)

    for _, assignment in ipairs(assignments) do

        if assignment.key == tableName then

            local afterTable =
                SkipTable(
                    text,
                    assignment.valueStart
                )

            local legacyEnd =
                afterTable - 1

            if text:sub(
                legacyEnd,
                legacyEnd
            ) ~= "}" then

                return nil,
                    "Legacy table is not properly closed: "
                    .. tostring(tableName)
            end

            return text:sub(
                assignment.valueStart,
                legacyEnd
            ),
            nil,
            "legacy Config.<Name> assignment",
            GetLineIndent(
                text,
                assignment.assignmentStart
            )

        end

    end

    return nil,
        "Top-level table source not found: "
        .. tostring(tableName)

end


local function ParseLegacyTableRange(
    text,
    topLevelKey,
    valueStart,
    limitPos
)

    local values = {}
    local stack = { topLevelKey }
    local pos = valueStart + 1

    local function CurrentPath(key)
        return table.concat(stack, ".") .. "." .. key
    end

    while pos <= limitPos do

        pos = SkipTrivia(text, pos)

        if pos > limitPos then
            break
        end

        local c = text:sub(pos, pos)

        if c == "}" then

            if #stack <= 1 then
                break
            end

            table.remove(stack)
            pos = pos + 1

        elseif c == "\"" or c == "'" then

            pos = SkipQuotedString(text, pos)

        elseif c == "[" then

            local longEnd = SkipLongBracket(text, pos)

            if longEnd then
                pos = longEnd
            else
                pos = pos + 1
            end

        elseif IsIdentifierStart(c) then

            local key, nextPos = ReadIdentifier(text, pos)
            local checkPos = SkipTrivia(text, nextPos)

            if text:sub(checkPos, checkPos) == "=" then

                local scalarOrTableStart = SkipTrivia(text, checkPos + 1)

                if text:sub(scalarOrTableStart, scalarOrTableStart) == "{" then

                    stack[#stack + 1] = key
                    pos = scalarOrTableStart + 1

                else

                    local valueEnd = FindScalarEnd(text, scalarOrTableStart)

                    if valueEnd <= limitPos then

                        local path = CurrentPath(key)

                        values[path] = {
                            startPos = scalarOrTableStart,
                            endPos = valueEnd,
                            rawValue = text:sub(scalarOrTableStart, valueEnd),
                        }

                    end

                    pos = valueEnd + 1

                end

            else
                pos = nextPos
            end

        else
            pos = pos + 1
        end

    end

    return values

end


local function ParseLegacySource(text, replaceTables)

    local assignments = FindLegacyConfigAssignments(text)

    if #assignments == 0 then
        return nil, "No legacy Config.<Name> table assignments were found."
    end

    local values = {}

    for index, assignment in ipairs(assignments) do

        if not replaceTables[assignment.key] then

            local limitPos = #text

            if assignments[index + 1] then
                limitPos = assignments[index + 1].assignmentStart - 1
            end

            local sectionValues = ParseLegacyTableRange(
                text,
                assignment.key,
                assignment.valueStart,
                limitPos
            )

            for path, entry in pairs(sectionValues) do
                values[path] = entry
            end

        end

    end

    return values

end


------------------------------------------------
-- Config Source Format Detection
------------------------------------------------

local function ParseAnyConfigSource(
    text,
    replaceTables
)

    local sourceValues, rootError =
        ParseSource(
            text,
            replaceTables
        )

    if sourceValues
        and CountEntries(sourceValues) > 0 then

        return sourceValues, nil, "root table"

    end

    local legacyValues, legacyError =
        ParseLegacySource(
            text,
            replaceTables
        )

    if legacyValues
        and CountEntries(legacyValues) > 0 then

        return legacyValues, nil, "legacy Config.<Name> assignments"

    end

    return nil,
        "No config scalar settings were found in the source. "
        .. "Root parser: "
        .. tostring(rootError or "no scalar values")
        .. " / Legacy parser: "
        .. tostring(legacyError or "no scalar values")

end


------------------------------------------------
-- Literal / Simple Expression Type Detection
------------------------------------------------

local function IsSimpleMemberExpression(raw)

    local _, pos =
        ReadIdentifier(
            raw,
            1
        )

    if pos == 1 then
        return false
    end

    local memberCount = 0

    while pos <= #raw do

        if raw:sub(pos, pos) ~= "." then
            return false
        end

        local identifier, nextPos =
            ReadIdentifier(
                raw,
                pos + 1
            )

        if not identifier then
            return false
        end

        memberCount = memberCount + 1
        pos = nextPos

    end

    return memberCount > 0

end


local function GetLiteralType(raw)

    if not raw then
        return nil
    end

    raw = raw:match("^%s*(.-)%s*$")

    if raw == "true"
        or raw == "false" then

        return "boolean"
    end

    if (raw:sub(1, 1) == "\""
        and raw:sub(-1) == "\"")
        or
       (raw:sub(1, 1) == "'"
        and raw:sub(-1) == "'") then

        return "string"
    end

    if tonumber(raw) ~= nil then
        return "number"
    end

    ------------------------------------------------
    -- Preserve simple symbolic member expressions such as:
    --
    --   Key.D
    --   Key.F2
    --   SomeTable.Value
    --
    -- Only identifier/member chains are accepted here. Function calls,
    -- operators, indexing expressions, and arbitrary Lua code are not
    -- treated as migratable source expressions.
    ------------------------------------------------

    if IsSimpleMemberExpression(raw) then
        return "expression"
    end

    return nil

end


------------------------------------------------
-- Apply User Values
------------------------------------------------

local function ApplyUserValues(
    defaultText,
    sourceValues,
    userValues,
    tableReplacements
)

    local replacements = {}

    local stats = {
        Migrated = 0,
        Removed = 0,
        TypeMismatch = 0,
        Unsupported = 0,
        TablesReplaced = 0,
    }

    for path, userEntry in pairs(userValues) do

        local sourceEntry =
            sourceValues[path]

        if sourceEntry then

            local defaultType =
                GetLiteralType(
                    sourceEntry.rawValue
                )

            ------------------------------------------------
            -- Only migrate when the old and new value types match.
            -- A type change in a newer config therefore keeps the new
            -- default instead of injecting an incompatible old value.
            ------------------------------------------------

            local replacementValue = nil

            ------------------------------------------------
            -- If both the old user source and the new default use the
            -- same simple symbolic expression form, preserve the user's
            -- original source token. This keeps settings such as Key.F2
            -- readable instead of serializing the runtime key code.
            ------------------------------------------------

            if defaultType == "expression"
                and userEntry.sourceValueType == "expression"
                and userEntry.rawValue then

                replacementValue = userEntry.rawValue

            ------------------------------------------------
            -- Normal scalar migration uses runtime value types.
            ------------------------------------------------

            elseif defaultType == userEntry.valueType then

                replacementValue =
                    SerializeValue(
                        userEntry.value
                    )

            end

            if replacementValue then

                table.insert(
                    replacements,
                    {
                        startPos = sourceEntry.startPos,
                        endPos = sourceEntry.endPos,
                        value = replacementValue,
                    }
                )

                stats.Migrated = stats.Migrated + 1

            elseif defaultType ~= userEntry.valueType
                and not (
                    defaultType == "expression"
                    and userEntry.sourceValueType == "expression"
                ) then

                stats.TypeMismatch = stats.TypeMismatch + 1

            else
                stats.Unsupported = stats.Unsupported + 1
            end

        else
            ------------------------------------------------
            -- The setting existed in the old config but no longer
            -- exists in the new default. Do not restore it.
            ------------------------------------------------
            stats.Removed = stats.Removed + 1
        end

    end

    for _, tableReplacement in ipairs(tableReplacements or {}) do

        table.insert(
            replacements,
            tableReplacement
        )

        stats.TablesReplaced =
            stats.TablesReplaced + 1

    end

    ------------------------------------------------
    -- Replace from the end of the file toward the beginning
    -- so source positions recorded earlier never shift.
    ------------------------------------------------

    table.sort(
        replacements,
        function(a, b)
            return a.startPos > b.startPos
        end
    )

    local result = defaultText

    for _, replacement in ipairs(replacements) do

        result =
            result:sub(
                1,
                replacement.startPos - 1
            )
            ..
            replacement.value
            ..
            result:sub(
                replacement.endPos + 1
            )

    end

    return result, stats

end


------------------------------------------------
-- Source Recovery
--
-- If the existing config cannot be executed because of a syntax
-- error, attempt to recover scalar values directly from its source.
-- This is intentionally limited to boolean / number / string values.
------------------------------------------------

local function DeserializeLiteral(rawValue, valueType)

    if valueType == "boolean" then
        return rawValue:match("^%s*true%s*$") ~= nil
    end

    if valueType == "number" then
        return tonumber(rawValue)
    end

    if valueType == "string" then

        local chunk, compileError =
            load(
                "return " .. rawValue,
                "ConfigManagerRecoveredLiteral"
            )

        if not chunk then
            return nil, compileError
        end

        local ok, result = pcall(chunk)

        if not ok then
            return nil, result
        end

        if type(result) ~= "string" then
            return nil, "Recovered literal is not a string."
        end

        return result

    end

    return nil, "Unsupported literal type."

end


local function ExtractUserValuesFromSource(
    userText,
    replaceTables
)

    local sourceValues, recoveryError, recoveryFormat =
        ParseAnyConfigSource(
            userText,
            replaceTables
        )

    if not sourceValues then
        return nil, recoveryError
    end

    local values = {}

    for path, sourceEntry in pairs(sourceValues) do

        local valueType =
            GetLiteralType(
                sourceEntry.rawValue
            )

        if valueType == "expression" then

            values[path] = {
                valueType = "expression",
                sourceValueType = "expression",
                rawValue = sourceEntry.rawValue:match("^%s*(.-)%s*$"),
            }

        elseif valueType then

            local value =
                DeserializeLiteral(
                    sourceEntry.rawValue,
                    valueType
                )

            if value ~= nil then

                values[path] = {
                    value = value,
                    valueType = valueType,
                    sourceValueType = valueType,
                    rawValue = sourceEntry.rawValue:match("^%s*(.-)%s*$"),
                }

            end

        end

    end

    if CountEntries(values) == 0 then
        return nil,
            "No recoverable scalar settings were found after parsing the existing config source."
    end

    return values, nil, recoveryFormat

end


------------------------------------------------
-- Migration
------------------------------------------------

local function BuildMigratedSource(
    self,
    userText,
    defaultText
)

    local userValues
    local userTableSources = {}
    local sourceRecoveryUsed = false

    ------------------------------------------------
    -- Preferred path: execute the existing user config and obtain
    -- its actual runtime table values.
    ------------------------------------------------

    local userConfig, userError =
        LoadConfigFile(
            self.ConfigPath
        )

    if userConfig then

        userValues =
            ExtractUserValues(
                userConfig,
                self.ReplaceTables
            )

        ------------------------------------------------
        -- Also inspect the existing source so symbolic settings such as
        -- Key.D can be preserved in their readable source form.
        ------------------------------------------------

        local userSourceValues =
            ParseAnyConfigSource(
                userText,
                self.ReplaceTables
            )

        if userSourceValues then

            for path, userEntry in pairs(userValues) do

                local sourceEntry =
                    userSourceValues[path]

                if sourceEntry then

                    userEntry.rawValue =
                        sourceEntry.rawValue:match("^%s*(.-)%s*$")

                    userEntry.sourceValueType =
                        GetLiteralType(
                            sourceEntry.rawValue
                        )

                end

            end

        end

        LogManager(
            self,
            "Config migration: existing user config loaded successfully."
        )

        ------------------------------------------------
        -- ReplaceTables are not recursively merged.
        -- Preserve the complete user table source instead.
        ------------------------------------------------

        for tableName, enabled in pairs(self.ReplaceTables) do

            if enabled then

                if type(userConfig[tableName]) == "table" then

                    local rawSource,
                        sourceError,
                        sourceFormat,
                        sourceIndent =
                        ExtractTopLevelTableSource(
                            userText,
                            tableName
                        )

                    if rawSource then

                        ------------------------------------------------
                        -- Optional whole-table source upgrade.
                        --
                        -- This runs only during config migration. It lets the
                        -- owning MOD add a newly required member to a preserved
                        -- ReplaceTables source without teaching ConfigManager
                        -- anything about that MOD-specific table structure.
                        ------------------------------------------------

                        local transform =
                            self.ReplaceTableSourceTransforms[
                                tableName
                            ]

                        if type(transform) == "function" then

                            local okTransform,
                                transformedSource,
                                transformError =
                                pcall(
                                    transform,
                                    rawSource,
                                    {
                                        TableName = tableName,
                                        SourceFormat = sourceFormat,
                                        SourceIndent = sourceIndent,
                                        UserText = userText,
                                        DefaultText = defaultText,
                                    }
                                )

                            if not okTransform then

                                return nil,
                                    "ReplaceTables source transform failed for "
                                    .. tostring(tableName)
                                    .. ": "
                                    .. tostring(transformedSource)
                            end

                            if type(transformedSource) ~= "string" then

                                return nil,
                                    "ReplaceTables source transform did not return a source string for "
                                    .. tostring(tableName)
                                    .. ": "
                                    .. tostring(transformError or transformedSource)
                            end

                            rawSource = transformedSource

                            LogManager(
                                self,
                                "Config migration: transformed preserved user table source:",
                                tostring(tableName)
                            )

                        end

                        userTableSources[tableName] = {
                            rawSource = rawSource,
                            sourceFormat = sourceFormat,
                            sourceIndent = sourceIndent,
                        }

                        LogManager(
                            self,
                            "Config migration: preserving user table as a whole:",
                            tostring(tableName),
                            "(" .. tostring(sourceFormat) .. ")"
                        )

                    else

                        LogManager(
                            self,
                            "Config migration: user table exists but its source could not be extracted; new default table will be kept:",
                            tostring(tableName),
                            tostring(sourceError)
                        )

                    end

                else

                    LogManager(
                        self,
                        "Config migration: user table not found; new default table will be kept:",
                        tostring(tableName)
                    )

                end

            end

        end

    else

        sourceRecoveryUsed = true

        ------------------------------------------------
        -- Recovery path: the old source may itself contain a syntax
        -- error. Recover simple settings directly from the source so
        -- the user's edits can still be carried into the new config.
        ------------------------------------------------

        LogManager(
            self,
            "Config migration: existing user config could not be loaded; attempting source recovery:",
            tostring(userError)
        )

        local recoveryError
        local recoveryFormat

        userValues, recoveryError, recoveryFormat =
            ExtractUserValuesFromSource(
                userText,
                self.ReplaceTables
            )

        if not userValues then
            return nil,
                "Failed to load existing user config: "
                .. tostring(userError)
                .. " / Source recovery failed: "
                .. tostring(recoveryError)
        end

        LogManager(
            self,
            "Config migration: source recovery format:",
            tostring(recoveryFormat)
        )

        LogManager(
            self,
            "Config migration: recovered",
            CountEntries(userValues),
            "user setting values directly from the existing config source."
        )

        ------------------------------------------------
        -- A malformed config cannot safely provide a complete
        -- ReplaceTables source block. Keep the new default table.
        ------------------------------------------------

        for tableName, enabled in pairs(self.ReplaceTables) do

            if enabled then

                LogManager(
                    self,
                    "Config recovery: user table could not be safely restored from the malformed config; new default table will be used:",
                    tostring(tableName)
                )

            end

        end

    end

    local sourceValues, parseError =
        ParseSource(
            defaultText,
            self.ReplaceTables
        )

    if not sourceValues then
        return nil, parseError
    end

    ------------------------------------------------
    -- Build whole-table replacements against the untouched
    -- new default source so their source positions remain valid.
    ------------------------------------------------

    local tableReplacements = {}

    for tableName, sourceInfo in pairs(userTableSources) do

        local targetStart,
            targetEnd,
            targetError,
            targetIndent =
            FindRootTopLevelTableRange(
                defaultText,
                tableName
            )

        if targetStart and targetEnd then

            local adjustedSource =
                ReindentTableSource(
                    sourceInfo.rawSource,
                    sourceInfo.sourceIndent,
                    targetIndent
                )

            table.insert(
                tableReplacements,
                {
                    startPos = targetStart,
                    endPos = targetEnd,
                    value = adjustedSource,
                    tableName = tableName,
                }
            )

            LogManager(
                self,
                "Config migration: new default table will be overwritten by the user's existing table:",
                tostring(tableName)
            )

        else

            LogManager(
                self,
                "Config migration: replacement target does not exist in the new default; user table ignored:",
                tostring(tableName),
                tostring(targetError)
            )

        end

    end

    local migratedText, stats =
        ApplyUserValues(
            defaultText,
            sourceValues,
            userValues,
            tableReplacements
        )

    return migratedText,
        nil,
        stats,
        sourceRecoveryUsed

end

------------------------------------------------
-- Safe Migration
------------------------------------------------

local function PerformMigration(
    self,
    userText,
    defaultText
)

    LogManager(
        self,
        "Config migration started."
    )

    local migratedText,
        migrationError,
        stats,
        sourceRecoveryUsed =
        BuildMigratedSource(
            self,
            userText,
            defaultText
        )

    if not migratedText then
        return false, migrationError
    end

    LogManager(
        self,
        "Config merge completed:",
        stats and stats.Migrated or 0,
        "user values preserved;",
        stats and stats.Removed or 0,
        "obsolete values ignored;",
        stats and stats.TypeMismatch or 0,
        "type-mismatched values kept at new defaults;",
        stats and stats.TablesReplaced or 0,
        "top-level user tables preserved."
    )

    if sourceRecoveryUsed then

        LogManager(
            self,
            "Config migration completed using source recovery; unrecoverable whole-table settings remained at the new defaults."
        )

    end

    local tempPath =
        self.ConfigPath .. ".tmp"

    local backupPath =
        self.ConfigPath .. ".bak"

    ------------------------------------------------
    -- Write and execute the temporary config before touching
    -- the user's current config.
    ------------------------------------------------

    if not WriteFile(
        tempPath,
        migratedText
    ) then
        return false,
            "Failed to write temporary config."
    end

    LogManager(
        self,
        "New config created as temporary file:",
        tempPath
    )

    local _, validationError =
        LoadConfigFile(
            tempPath
        )

    if validationError then

        os.remove(tempPath)

        return false,
            "Generated config validation failed: "
            .. tostring(validationError)
    end

    LogManager(
        self,
        "Generated config validation succeeded."
    )

    ------------------------------------------------
    -- Keep exactly one backup of the previous user config.
    ------------------------------------------------

    os.remove(backupPath)

    if not WriteFile(
        backupPath,
        userText
    ) then

        os.remove(tempPath)

        return false,
            "Failed to create config backup."
    end

    LogManager(
        self,
        "Config backup created:",
        backupPath
    )

    ------------------------------------------------
    -- Replace the user config only after the temporary file
    -- has been validated and the backup has been created.
    ------------------------------------------------

    if not os.remove(self.ConfigPath) then

        os.remove(tempPath)

        return false,
            "Failed to replace existing user config."
    end

    if not os.rename(
        tempPath,
        self.ConfigPath
    ) then

        ------------------------------------------------
        -- Restore the original source if installation fails.
        ------------------------------------------------

        WriteFile(
            self.ConfigPath,
            userText
        )

        os.remove(tempPath)

        return false,
            "Failed to install migrated config."
    end

    LogManager(
        self,
        "Migrated config installed:",
        self.ConfigPath
    )

    return true

end


------------------------------------------------
-- Validated Source Update
--
-- Installs a complete replacement source after validating it as a
-- loadable config. Unlike version migration, this does not create or
-- overwrite the migration .bak file.
--
-- LastConfigText is intentionally not changed here. A running MOD's
-- normal CheckChanged() loop can therefore detect the written revision
-- and apply it through its existing reload callback.
------------------------------------------------

local function InstallValidatedSource(
    self,
    newText,
    operationName
)

    if type(newText) ~= "string" then
        return false,
            "New config source must be a string."
    end

    local oldText =
        ReadFile(
            self.ConfigPath
        )

    if not oldText then
        return false,
            "User config not found: "
            .. tostring(self.ConfigPath)
    end

    if newText == oldText then

        LogManager(
            self,
            operationName or "Config update",
            "made no changes."
        )

        return true, false
    end

    local tempPath =
        self.ConfigPath .. ".update.tmp"

    os.remove(tempPath)

    if not WriteFile(
        tempPath,
        newText
    ) then

        return false,
            "Failed to write temporary updated config."
    end

    local _, validationError =
        LoadConfigFile(
            tempPath
        )

    if validationError then

        os.remove(tempPath)

        return false,
            "Updated config validation failed: "
            .. tostring(validationError)
    end

    if not os.remove(
        self.ConfigPath
    ) then

        os.remove(tempPath)

        return false,
            "Failed to replace existing user config."
    end

    if not os.rename(
        tempPath,
        self.ConfigPath
    ) then

        ------------------------------------------------
        -- Restore the original source if installation fails.
        ------------------------------------------------

        WriteFile(
            self.ConfigPath,
            oldText
        )

        os.remove(tempPath)

        return false,
            "Failed to install updated config."
    end

    LogManager(
        self,
        operationName or "Config updated",
        ":",
        self.ConfigPath
    )

    return true, true

end


------------------------------------------------
-- Manager Instance
------------------------------------------------

local Manager = {}
Manager.__index = Manager


function ConfigManager.Create(options)

    assert(
        type(options) == "table",
        "ConfigManager.Create() requires an options table."
    )

    assert(
        type(options.ConfigPath) == "string",
        "ConfigPath is required."
    )

    assert(
        type(options.DefaultConfigPath) == "string",
        "DefaultConfigPath is required."
    )

    local self =
        setmetatable(
            {},
            Manager
        )

    self.ConfigPath =
        options.ConfigPath

    self.DefaultConfigPath =
        options.DefaultConfigPath

    self.ReplaceTables =
        options.ReplaceTables or {}

    -- Optional per-table source transforms applied only during version
    -- migration, after a ReplaceTables source block is extracted from the
    -- existing user config and before it replaces the new default table.
    --
    -- Example:
    --
    -- ReplaceTableSourceTransforms = {
    --     DisplayMode = function(rawSource, context)
    --         return upgradedSource
    --     end,
    -- }
    --
    -- The callback must return the complete replacement table source string.
    self.ReplaceTableSourceTransforms =
        options.ReplaceTableSourceTransforms or {}

    self.Log =
        options.Log

    self.LastConfigText = nil

    self.OptionalIntegrationNotified = false

    return self

end


------------------------------------------------
-- Prepare User Config
------------------------------------------------

function Manager:Prepare()

    ------------------------------------------------
    -- Ensure the user config directory exists before attempting
    -- to create, migrate, back up, or replace the config file.
    ------------------------------------------------

    local directoryReady, directoryResult, directoryCreated =
        EnsureParentDirectory(
            self.ConfigPath
        )

    if not directoryReady then

        return false,
            "Failed to prepare user config directory: "
            .. tostring(directoryResult)
    end

    if directoryCreated then

        LogManager(
            self,
            "User config directory created:",
            directoryResult
        )

    end

    local defaultText =
        ReadFile(
            self.DefaultConfigPath
        )

    if not defaultText then
        return false,
            "Default config not found: "
            .. self.DefaultConfigPath
    end

    local defaultVersion =
        GetConfigVersion(
            defaultText
        )

    local userText =
        ReadFile(
            self.ConfigPath
        )

    ------------------------------------------------
    -- First installation.
    ------------------------------------------------

    if not userText then

        LogManager(
            self,
            "User config not found. Creating a new config from the bundled default."
        )

        if not CopyFile(
            self.DefaultConfigPath,
            self.ConfigPath
        ) then

            return false,
                "Failed to create user config."
        end

        LogManager(
            self,
            "New config created:",
            self.ConfigPath,
            defaultVersion and ("Version " .. defaultVersion) or ""
        )

        return true
    end

    local userVersion =
        GetConfigVersion(
            userText
        )

    ------------------------------------------------
    -- Without both version headers, automatic migration is
    -- skipped so an unknown file is never rewritten blindly.
    ------------------------------------------------

    if not userVersion
        or not defaultVersion then

        LogManager(
            self,
            "Config migration skipped because a Version header is missing."
        )

        return true
    end

    ------------------------------------------------
    -- Same version: normally do not touch the user's file.
    -- However, if the file itself is invalid, rebuild it from the
    -- bundled default while recovering any scalar user settings
    -- that can still be read from the source.
    ------------------------------------------------

    if userVersion == defaultVersion then

        local existingConfig, existingError =
            LoadConfigFile(
                self.ConfigPath
            )

        if existingConfig then

            LogManager(
                self,
                "Config is up to date: Version",
                tostring(defaultVersion)
            )

            return true
        end

        LogManager(
            self,
            "Existing config failed validation even though the Version matches; attempting config recovery:",
            tostring(existingError)
        )

        local recovered, recoveryError =
            PerformMigration(
                self,
                userText,
                defaultText
            )

        if not recovered then

            LogManager(
                self,
                "Config recovery failed:",
                tostring(recoveryError)
            )

            return false, recoveryError
        end

        LogManager(
            self,
            "Config recovery completed for Version",
            tostring(defaultVersion)
        )

        return true
    end

    ------------------------------------------------
    -- Different version: build the new file from the bundled
    -- default and migrate matching user values into it.
    ------------------------------------------------

    LogManager(
        self,
        "Config version change detected:",
        tostring(userVersion),
        "->",
        tostring(defaultVersion)
    )

    local migrated, migrationError =
        PerformMigration(
            self,
            userText,
            defaultText
        )

    if not migrated then

        LogManager(
            self,
            "Config migration failed:",
            tostring(migrationError)
        )

        return false, migrationError
    end

    LogManager(
        self,
        "Config migration completed:",
        tostring(userVersion),
        "->",
        tostring(defaultVersion)
    )

    return true

end


------------------------------------------------
-- Initial Load
--
-- If automatic preparation/migration fails but the existing
-- user config is still valid, keep using it unchanged instead
-- of preventing the MOD from loading.
------------------------------------------------

function Manager:Load()

    local prepared, prepareMessage =
        self:Prepare()

    local config, loadError =
        LoadConfigFile(
            self.ConfigPath
        )

    if not config then

        if not prepared then

            return nil,
                "Config preparation failed: "
                .. tostring(prepareMessage)
                .. " / Config load failed: "
                .. tostring(loadError)
        end

        return nil,
            "Config load failed: "
            .. tostring(loadError)
    end

    local text =
        ReadFile(
            self.ConfigPath
        )

    self.LastConfigText = text

    LogManager(
        self,
        "Config loaded:",
        self.ConfigPath
    )

    if not prepared then

        LogManager(
            self,
            "Config preparation failed; existing valid config will be used unchanged:",
            tostring(prepareMessage)
        )

    end

    ------------------------------------------------
    -- Notify optional integrations only after the user config exists,
    -- has been migrated/recovered if necessary, and loaded successfully.
    -- Integration failures are intentionally non-fatal.
    ------------------------------------------------

    NotifyOptionalIntegration(self)

    return config

end


------------------------------------------------
-- Runtime Change Detection
--
-- The baseline is updated as soon as a new file revision is
-- detected. Therefore, an invalid edit produces one reload
-- error instead of repeating the same error every second.
-- Once the user edits the file again, the new contents differ
-- and another reload attempt is made.
------------------------------------------------

function Manager:CheckChanged(callback)

    local text =
        ReadFile(
            self.ConfigPath
        )

    if not text then
        return false
    end

    if self.LastConfigText == nil then

        self.LastConfigText = text

        return false
    end

    if text == self.LastConfigText then
        return false
    end

    LogManager(
        self,
        "Config file change detected."
    )

    ------------------------------------------------
    -- Record this revision before loading it so the same
    -- invalid file does not trigger repeatedly.
    ------------------------------------------------

    self.LastConfigText = text

    local newConfig, loadError =
        LoadConfigFile(
            self.ConfigPath
        )

    if not newConfig then

        LogManager(
            self,
            "Changed config failed validation:",
            tostring(loadError)
        )

        return false, loadError
    end

    if callback then

        local ok, result, callbackError =
            pcall(
                callback,
                newConfig
            )

        if not ok then
            return false, result
        end

        if result == false then
            return false,
                callbackError
                or "Config reload callback failed."
        end

    end

    return true

end


------------------------------------------------
-- Generic Source Update API
------------------------------------------------

-- Replace the complete user config source after syntax/runtime validation.
-- This is intended for integrations that already performed their own
-- source-preserving edit (for example, changing a table key or inserting
-- a missing field).
function Manager:WriteSource(
    newText,
    operationName
)

    return InstallValidatedSource(
        self,
        newText,
        operationName or "Config source updated"
    )

end


-- Update existing scalar settings by dot-separated config path while
-- preserving all surrounding comments and formatting.
--
-- Example:
--
--   manager:UpdateValues({
--       ["UI.Normal.OffsetX"] = 20,
--       ["DisplayOption.Talent.GreenThreshold"] = 80,
--   })
--
-- Simple member expressions can be supplied without converting them to
-- runtime numeric values:
--
--   manager:UpdateValues({
--       ["PageSkip.SkipForwardKey"] = {
--           RawValue = "Key.F2",
--       },
--   })
--
-- Every requested path must already exist in the source. Structural
-- insertion/removal is deliberately left to a caller that understands
-- that config structure, then passed through WriteSource().
function Manager:UpdateValues(updates)

    if type(updates) ~= "table" then
        return false,
            "UpdateValues() requires a table."
    end

    local text =
        ReadFile(
            self.ConfigPath
        )

    if not text then
        return false,
            "User config not found: "
            .. tostring(self.ConfigPath)
    end

    ------------------------------------------------
    -- Parse normal scalar paths. Top-level tables configured through
    -- ReplaceTables are intentionally skipped here because their
    -- structure may contain arbitrary array/expression keys. Callers
    -- that edit those structures should perform a source-aware edit
    -- and install it through WriteSource().
    ------------------------------------------------

    local sourceValues, parseError =
        ParseAnyConfigSource(
            text,
            self.ReplaceTables
        )

    if not sourceValues then
        return false, parseError
    end

    local replacements = {}
    local updateCount = 0

    for path, requestedValue in pairs(updates) do

        if type(path) ~= "string"
            or path == "" then

            return false,
                "Config update path must be a non-empty string."
        end

        local sourceEntry =
            sourceValues[path]

        if not sourceEntry then

            return false,
                "Config update path was not found in the source: "
                .. tostring(path)
        end

        local currentType =
            GetLiteralType(
                sourceEntry.rawValue
            )

        local replacementValue
        local replacementType

        if type(requestedValue) == "table"
            and requestedValue.RawValue ~= nil then

            replacementValue =
                tostring(
                    requestedValue.RawValue
                ):match("^%s*(.-)%s*$")

            replacementType =
                GetLiteralType(
                    replacementValue
                )

            if not replacementType then

                return false,
                    "Unsupported raw config value for path "
                    .. tostring(path)
                    .. ": "
                    .. tostring(replacementValue)
            end

        else

            replacementValue =
                SerializeValue(
                    requestedValue
                )

            replacementType =
                type(requestedValue)

            if not replacementValue then

                return false,
                    "Unsupported config value type for path "
                    .. tostring(path)
                    .. ": "
                    .. tostring(replacementType)
            end

        end

        ------------------------------------------------
        -- Keep normal scalar writes type-safe. Member-expression
        -- settings (for example Key.D) must remain expressions.
        ------------------------------------------------

        local compatible =
            currentType == replacementType
            or (
                currentType == "expression"
                and replacementType == "expression"
            )

        if not compatible then

            return false,
                "Config value type mismatch for path "
                .. tostring(path)
                .. ": current="
                .. tostring(currentType)
                .. ", new="
                .. tostring(replacementType)
        end

        table.insert(
            replacements,
            {
                startPos = sourceEntry.startPos,
                endPos = sourceEntry.endPos,
                value = replacementValue,
            }
        )

        updateCount =
            updateCount + 1

    end

    table.sort(
        replacements,
        function(a, b)
            return a.startPos > b.startPos
        end
    )

    local newText = text

    for _, replacement in ipairs(replacements) do

        newText =
            newText:sub(
                1,
                replacement.startPos - 1
            )
            ..
            replacement.value
            ..
            newText:sub(
                replacement.endPos + 1
            )

    end

    local installed, changedOrError =
        InstallValidatedSource(
            self,
            newText,
            "Config values updated"
        )

    if not installed then
        return false, changedOrError
    end

    if changedOrError then

        LogManager(
            self,
            "Config scalar values written:",
            updateCount
        )

    end

    return true, changedOrError

end


-- Read the current scalar source values keyed by dot-separated config path.
-- Selected ReplaceTables are omitted because their structure may contain
-- arbitrary array/expression keys and must be handled by a structure-aware caller.
function Manager:ReadSourceValues()

    local text =
        ReadFile(
            self.ConfigPath
        )

    if not text then
        return nil,
            "User config not found: "
            .. tostring(self.ConfigPath)
    end

    return ParseAnyConfigSource(
        text,
        self.ReplaceTables
    )

end


function Manager:ReadSource()
    return ReadFile(self.ConfigPath)
end


function Manager:ReadDefaultSource()
    return ReadFile(self.DefaultConfigPath)
end


function Manager:GetConfigPath()
    return self.ConfigPath
end


function Manager:GetDefaultConfigPath()
    return self.DefaultConfigPath
end


function Manager:GetLogger()
    return self.Log
end


return ConfigManager

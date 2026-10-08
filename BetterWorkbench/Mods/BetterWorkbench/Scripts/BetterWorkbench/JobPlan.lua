local Util = require("BetterWorkbench.Util")
local Job = {}
Job.__index = Job
local maxCount = 1000000000
local function id(value, label)
    assert(type(value) == "string" and #value >= 1 and #value <= 256
        and not value:find("%c"), "invalid " .. label)
    return value
end
local function same(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end
local function counts(values, allowZero)
    assert(type(values) == "table", "invalid material map")
    local result, count = {}, 0
    for item, amount in pairs(values) do
        id(item, "material ID")
        Util.integer(amount, allowZero and 0 or 1, maxCount, "material amount")
        if amount > 0 then result[item] = amount end
        count = count + 1
    end
    assert(count <= 5, "native input slot limit")
    return result
end
local function binding(value)
    assert(type(value) == "table", "stable task binding required")
    return { WorldId = id(value.WorldId, "world ID"), StationId = id(value.StationId, "station ID"),
        JobId = id(value.JobId, "job ID"), GameBuild = id(value.GameBuild, "game build"),
        Checkpoint = id(value.Checkpoint, "save checkpoint") }
end
local function validate(payload)
    assert(type(payload) == "table" and payload.Schema == 1, "unsupported task plan schema")
    local data = { Schema = 1, Binding = binding(payload.Binding),
        RecipeId = id(payload.RecipeId, "recipe ID"), OutputItem = id(payload.OutputItem, "output item"),
        Batches = Util.integer(payload.Batches, 1, 256, "task batches"),
        Completed = Util.integer(payload.Completed, 0, 256, "completed batches"), Units = {}, SlotItems = {} }
    assert(data.Completed <= data.Batches, "task progress outside schedule")
    assert(type(payload.Units) == "table" and #payload.Units == data.Batches, "task unit schedule mismatch")
    local totals, totalOutput, totalWork = {}, 0, 0
    for index = 1, data.Batches do
        local unit = payload.Units[index]
        assert(type(unit) == "table", "invalid task unit")
        local inputs = counts(unit.Inputs, false)
        local output = Util.integer(unit.OutputAmount, 1, maxCount, "unit output")
        local work = unit.WorkAmount
        assert(type(work) == "number" and work >= 0 and work < math.huge, "invalid unit work")
        data.Units[index] = { Inputs = inputs, OutputAmount = output, WorkAmount = work }
        totalOutput = Util.integer(totalOutput + output, 1, maxCount, "task output total")
        totalWork = totalWork + work
        assert(totalWork < math.huge, "task work overflow")
        for item, amount in pairs(inputs) do
            totals[item] = Util.integer((totals[item] or 0) + amount, 1, maxCount, "task input total")
        end
    end
    -- A persistent schedule contains identities and integers, never FName
    -- indices, UObject addresses, borrowed arrays, functions, or recipe rows.
    data.ActualInputs = counts(totals, false)
    data.SlotItems = Util.keys(data.ActualInputs)
    assert(type(payload.SlotItems) == "table" and #payload.SlotItems == #data.SlotItems, "task slot identity mismatch")
    for index, item in ipairs(data.SlotItems) do
        assert(payload.SlotItems[index] == item, "task slot order mismatch")
    end
    assert(same(counts(payload.ActualInputs, false), totals), "task total does not match unit schedule")
    assert(payload.OutputAmount == totalOutput and payload.WorkAmount == totalWork, "task metadata total mismatch")
    data.OutputAmount, data.WorkAmount = totalOutput, totalWork
    return data
end
local function remaining(data, completed)
    local values = {}
    for index = completed + 1, data.Batches do
        for item, amount in pairs(data.Units[index].Inputs) do values[item] = (values[item] or 0) + amount end
    end
    return values
end
local function check_native(data, native, completed, restoring)
    assert(type(native) == "table", "native task binding mismatch")
    local observed, expected = binding(native.Binding), Util.copy(data.Binding)
    -- Checkpoints advance on each save, while the task generation remains
    -- stable. Completion binds to the task; restore also binds to the archive.
    if not restoring then observed.Checkpoint, expected.Checkpoint = nil, nil end
    assert(same(observed, expected), "native task binding mismatch")
    assert(native.RecipeId == data.RecipeId and native.Requested == data.Batches
        and native.Remaining == data.Batches - completed, "native task progress mismatch")
    assert(type(native.SlotItems) == "table" and #native.SlotItems == #data.SlotItems, "native slot identity mismatch")
    for index, item in ipairs(data.SlotItems) do assert(native.SlotItems[index] == item, "native slot order mismatch") end
    assert(same(counts(native.Inputs, true), remaining(data, completed)), "native inputs do not match saved schedule")
end

function Job.new(schedule, stableBinding)
    assert(schedule.Craftable == true, "cannot create task from failed plan")
    local payload = Util.copy(schedule)
    payload.Schema, payload.Binding, payload.Completed = 1, stableBinding, 0
    return setmetatable({ data = validate(payload) }, Job)
end
function Job.restore(payload, native)
    local data = validate(payload)
    -- Caller MUST read this metadata from the SAME native save checkpoint.
    -- An unrelated sidecar cannot establish this condition after a crash.
    check_native(data, native, data.Completed, true)
    return setmetatable({ data = data }, Job)
end
function Job:export()
    return Util.copy(self.data)
end
function Job:forSave(checkpoint)
    local payload = self:export()
    payload.Binding.Checkpoint = id(checkpoint, "save checkpoint")
    return payload
end
function Job:view()
    local data = self.data
    local unit = data.Units[data.Completed + 1]
    return { RecipeId = data.RecipeId, Completed = data.Completed,
        Remaining = data.Batches - data.Completed, SlotItems = Util.copy(data.SlotItems),
        UnitInputs = Util.copy(unit and unit.Inputs or {}),
        InputRows = Util.rows(unit and unit.Inputs or {}), RemainingInputs = remaining(data, data.Completed),
        WorkAmount = unit and unit.WorkAmount or 0, OutputAmount = unit and unit.OutputAmount or 0,
        OutputItem = data.OutputItem }
end
function Job:confirmNativeCompletion(native)
    assert(self.data.Completed < self.data.Batches, "task already complete")
    local completed = self.data.Completed + 1
    -- No progress, refund, or inventory change on error. The adapter reports
    -- a SUCCESSFUL native consumption/output transaction with fresh state.
    check_native(self.data, native, completed)
    self.data.Completed = completed
    return self:view()
end

return Job

-- Offline conservation reference ONLY; not called by CraftService or the game.
-- Pure server-side cancellation policy. This module never credits inventory or
-- marks a job cancelled. The backend must supply its persisted, actual debit
-- receipt and atomically apply the returned refund + native job removal once.
local Util = require("BetterWorkbench.Util")
local Cancellation = {}

function Cancellation.forUnstarted(job, maxCount)
    maxCount = maxCount or 1000000000
    Util.integer(maxCount, 1, 1000000000, "MaxCount")
    assert(type(job) == "table" and type(job.JobId) == "string" and job.JobId ~= "", "invalid job receipt")
    if job.Status ~= "active" then return nil, "job_not_active" end
    Util.integer(job.TotalBatches, 1, maxCount, "total batches")
    Util.integer(job.CompletedBatches, 0, job.TotalBatches, "completed batches")
    -- Partial-completion refunds need a verified input-allocation policy.
    -- Never prorate aggregated recursive costs or recalculate today's recipes.
    if job.CompletedBatches ~= 0 then return nil, "partial_refund_unverified" end
    if type(job.ActualDebits) ~= "table" then return nil, "debit_receipt_unavailable" end
    local refund = {}
    for id, amount in pairs(job.ActualDebits) do
        assert(type(id) == "string" and id ~= "" and id ~= "None", "invalid debit item")
        refund[id] = Util.integer(amount, 1, maxCount, "debit amount")
    end
    return { JobId = job.JobId, Refund = refund }
end

return Cancellation

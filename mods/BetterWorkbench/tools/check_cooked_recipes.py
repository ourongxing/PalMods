"""Validate a LOCAL UAssetAPI recipe export against the real Lua resolver.

This checks static cooked data only; live research/mod costs and eligibility
must still be verified in Palworld. Extracted game data stays in .tools.
"""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parents[1] / 'tools'))
from palmods import load_lua_runtime, GAME_DATA_ROOT
LuaRuntime = load_lua_runtime()

export_path = Path(sys.argv[1]) if len(sys.argv) > 1 else GAME_DATA_ROOT / 'recipes.json'
asset = json.loads(export_path.read_text(encoding="utf-8-sig"))
exports = [row for row in asset["Exports"] if "DataTableExport" in row["$type"]]
assert len(exports) == 1, "Expected one recipe DataTable export"
recipes = {}
for row in exports[0]["Table"]["Data"]:
    raw = {field["Name"]: field.get("Value") for field in row["Value"]}
    materials = {}
    for index in range(1, 6):
        item = raw[f"Material{index}_Id"]
        amount = raw[f"Material{index}_Count"]
        assert isinstance(amount, int) and amount >= 0, (row["Name"], index)
        if amount and item not in (None, "None"):
            assert isinstance(item, str) and item not in ("", "None"), (row["Name"], index)
            materials[item] = materials.get(item, 0) + amount
    assert row["Name"] not in recipes, "Duplicate recipe ID"
    recipes[row["Name"]] = {
        "OutputItem": raw["Product_Id"], "OutputAmount": raw["Product_Count"],
        "WorkAmount": raw["WorkAmount"], "Materials": materials,
    }

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute("package.path = PROJECT_ROOT .. '/mod/Scripts/?.lua;' .. package.path")
check = lua.eval("""function(recipes)
    local resolver = require('BetterWorkbench.RecipeResolver').new(recipes)
    local row = resolver.book:get('PalSphere_Mega')
    assert(row and row.Materials.CopperIngot == 1)
    local snapshot = {}
    for item, amount in pairs(row.Materials) do snapshot[item] = amount * 2 end
    snapshot.CopperIngot = 1
    local ingot = resolver.book:get('CopperIngot')
    for item, amount in pairs(ingot.Materials) do snapshot[item] = (snapshot[item] or 0) + amount end
    -- Mock THIS station's recipe list, never a union of all base facilities.
    local policy = { canCraft = function() return true end,
        StationRecipes = { PalSphere_Mega = true, CarbonFiber2 = true } }
    local p = resolver:resolve('PalSphere_Mega', 2, snapshot, policy)
    assert(not p.Craftable and p.Missing.CopperIngot == 1)
    assert(p.Consumed.CopperIngot == 1)
    assert(p.Consumed.CopperOre == nil)
    assert(p.OutputAmount == row.OutputAmount * 2)
    snapshot.CopperIngot = 2
    p = resolver:resolve('PalSphere_Mega', 2, snapshot, policy)
    assert(p.Craftable and p.WorkAmount == row.WorkAmount * 2)
    snapshot.CopperIngot = 1
    snapshot.CopperOre = 1000
    local missing = resolver:resolve('PalSphere_Mega', 2, snapshot, policy)
    assert(not missing.Craftable and missing.Missing.CopperIngot == 1)
    -- Root recipe observed in the live 2026-10-06 craft / cancel trace.
    -- Synthetic inventory and policy only: no native memory access or debit.
    local carbon = resolver.book:get('CarbonFiber2')
    local charcoal = resolver.book:get('Charcoal')
    assert(carbon.Materials.Charcoal == 5 and carbon.Materials.FireOrgan == 1)
    assert(charcoal.Materials.Wood == 2)
    local penetrated = resolver:resolve('CarbonFiber2', 2,
        { Charcoal = 1, Wood = 18, FireOrgan = 2 }, policy)
    assert(not penetrated.Craftable and penetrated.Missing.Charcoal == 9)
    assert(penetrated.Consumed.Charcoal == 1 and penetrated.Consumed.Wood == nil)
    assert(penetrated.Consumed.FireOrgan == 2)
    assert(penetrated.Issues[1].Reason == 'cross_station_recipe')
    local enough = resolver:resolve('CarbonFiber2', 2,
        { Charcoal = 10, FireOrgan = 2 }, policy)
    assert(enough.Craftable and enough.Consumed.Charcoal == 10)
    assert(enough.Consumed.Wood == nil and enough.WorkAmount == carbon.WorkAmount * 2)
    local short = resolver:resolve('CarbonFiber2', 2,
        { Charcoal = 1, Wood = 17, FireOrgan = 2 }, policy)
    assert(not short.Craftable and short.Missing.Charcoal == 9 and short.Missing.Wood == nil)
    -- Real Bio_Battery and CarbonFiber recipes, with synthetic server policy /
    -- inventory only. Both carbon variants exist on this same workbench.
    local station = { Bio_Battery = true, CarbonFiber = true, CarbonFiber2 = true }
    local batteryPolicy = { canCraft = function() return true end, StationRecipes = station }
    local stock = { CarbonFiber = 1, ElectricOrgan = 3, IronIngot = 3,
        Coal = 4, Charcoal = 10, FireOrgan = 2 }
    local ambiguous = resolver:resolve('Bio_Battery', 3, stock, batteryPolicy)
    assert(not ambiguous.Craftable and ambiguous.Missing.CarbonFiber == 2)
    assert(ambiguous.Issues[1].Reason == 'ambiguous_recipe')
    for _, variant in ipairs({ 'CarbonFiber', 'CarbonFiber2' }) do
        local chosen = require('BetterWorkbench.RecipeResolver').new(recipes,
            { PreferredRecipes = { CarbonFiber = variant } })
        local plan = chosen:resolve('Bio_Battery', 3, stock, batteryPolicy)
        assert(plan.Craftable and plan.OutputAmount == 3)
        assert(plan.Consumed.CarbonFiber == 1 and plan.Consumed.FireOrgan == 2)
        assert(plan.Consumed.ElectricOrgan == 3 and plan.Consumed.IronIngot == 3)
        if variant == 'CarbonFiber' then
            assert(plan.Consumed.Coal == 4 and plan.Consumed.Charcoal == nil)
        else
            assert(plan.Consumed.Charcoal == 10 and plan.Consumed.Coal == nil)
            local blocked = chosen:resolve('Bio_Battery', 3,
                { CarbonFiber = 1, ElectricOrgan = 3, IronIngot = 3,
                    Charcoal = 1, Wood = 100, FireOrgan = 2 }, batteryPolicy)
            assert(not blocked.Craftable and blocked.Missing.Charcoal == 9)
            assert(blocked.Consumed.Wood == nil)
        end
        local refund = require('BetterWorkbench.CancellationPlan').forUnstarted({
            JobId = 'offline-battery', Status = 'active', TotalBatches = 3,
            CompletedBatches = 0, ActualDebits = plan.Consumed })
        for item, amount in pairs(plan.Consumed) do assert(refund.Refund[item] == amount) end
        assert(refund.Refund.CarbonFiber == 1) -- not 3 fabricated carbon fibres
    end
    stock.CarbonFiber = 3
    local stored = resolver:resolve('Bio_Battery', 3, stock, batteryPolicy)
    assert(stored.Craftable and stored.Consumed.Coal == nil and stored.Consumed.Charcoal == nil)
    return p
end""")
plan = check(lua.table_from(recipes, recursive=True))
print(f"Validated {len(recipes)} cooked recipes with Lua 5.4.")
print("PASS PalSphere_Mega x2: sufficient stored CopperIngot succeeds; ore cannot replace missing ingot across stations.")
print("PASS CarbonFiber2 x2: 1 stored Charcoal leaves 9 missing; Wood is never substituted across stations.")
print("PASS sufficient stored Charcoal succeeds without expansion.")
print("PASS Bio_Battery x3: existing carbon first, same-station coal/charcoal variants, ambiguity rejection and actual-input refund.")
print(f"Output={plan['OutputAmount']}, WorkAmount={plan['WorkAmount']} (native work units, not seconds).")

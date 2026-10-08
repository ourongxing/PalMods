#include "../../native/src/job_schedule.hpp"
#include "../../native/src/job_journal.hpp"
#include "../../native/src/recipe_scope.hpp"
#include "../../native/src/input_layout.hpp"
#include "../../native/src/consumption_ops.hpp"
#include <cassert>
using namespace better_workbench;
int main() {
    const std::vector<NativeRecipe> rows{
        {L"Battery", L"Battery", 1, {{L"Fiber", 2}, {L"Fluid", 1}}},
        {L"Fiber", L"Fiber", 1, {{L"Coal", 2}}},
        {L"Fiber2", L"Fiber", 1, {{L"Charcoal", 5}}},
        {L"Charcoal", L"Charcoal", 1, {{L"Wood", 2}}}};
    auto plan = NativePlanner(rows, {L"Battery",L"Fiber",L"Fiber2"}, {{L"Fiber",3},{L"Coal",6},{L"Fluid",3}}).resolve(L"Battery",3);
    assert(plan.units[0].at(L"Fiber")==2);
    assert(plan.units[1].at(L"Fiber")==1 && plan.units[1].at(L"Coal")==2);
    assert(plan.units[2].at(L"Coal")==4);
    assert(plan.total.at(L"Fiber")==3 && plan.total.at(L"Coal")==6);
    assert(suffix(plan,1).at(L"Coal")==6 && suffix(plan,1).at(L"Fluid")==2);
    auto alternate = NativePlanner(rows, {L"Battery",L"Fiber",L"Fiber2"}, {{L"Charcoal",10},{L"Fluid",1}}).resolve(L"Battery",1);
    assert(alternate.total.at(L"Charcoal")==10 && !alternate.total.contains(L"Coal"));
    // Failed producers must release every path entry and restore reservations
    // before a later alternative tries a dependency used by the failed branch.
    const std::vector<NativeRecipe> retry_rows{
        {L"Root",L"Root",1,{{L"Part",1}}},
        {L"Failed",L"Part",1,{{L"Nested",1},{L"Unavailable",1}}},
        {L"Success",L"Part",1,{{L"Nested",1}}},
        {L"Nested",L"Nested",1,{{L"Ore",1}}}};
    const auto retry_planner=NativePlanner(retry_rows,{L"Root",L"Failed",L"Success",L"Nested"},{{L"Ore",2}});
    const auto retry_plan=retry_planner.resolve(L"Root",2);
    assert((retry_plan.total==Amounts{{L"Ore",2}}));
    assert(retry_plan.units[0].at(L"Ore")==1 && retry_plan.units[1].at(L"Ore")==1);
    // Copies outlive their original catalog owner; preview and failures cannot
    // leak virtual stock or mutate later authoritative resolutions.
    const auto copied=[] {
        NativePlanner temporary({{L"Copy",L"Product",1,{{L"Input",1}}}},{L"Copy"},{{L"Input",2}});
        return NativePlanner(temporary);
    }();
    assert(copied.preview(L"Copy",3).total.at(L"Input")==3);
    assert(copied.resolve(L"Copy",2).total.at(L"Input")==2);
    assert(copied.resolve(L"Copy",2).units.size()==2);
    bool rejected{};
    try { NativePlanner(rows,{L"Battery",L"Fiber",L"Fiber2"},{{L"Wood",100},{L"Fluid",1}}).resolve(L"Battery",1); }
    catch (const std::runtime_error&) { rejected=true; }
    assert(rejected); // A furnace recipe cannot be used at this station.
    rejected=false;
    try { NativePlanner(rows,{L"Battery"},{{L"Coal",100},{L"Fluid",1}}).resolve(L"Battery",1); }
    catch (const std::runtime_error&) { rejected=true; }
    assert(rejected); // Locked intermediate recipe cannot be used.
    auto preview=NativePlanner(rows,{L"Battery",L"Fiber",L"Fiber2"},{{L"Fiber",1},{L"Fluid",3}}).preview(L"Battery",3);
    assert(preview.total.at(L"Fiber")==1 && preview.total.at(L"Coal")==10 && preview.total.at(L"Fluid")==3);
    auto exact_preview=NativePlanner(rows,{L"Battery",L"Fiber",L"Fiber2"},{{L"Fiber",3},{L"Coal",6},{L"Fluid",3}}).preview(L"Battery",3);
    assert(exact_preview.total==plan.total); // UI total is not first-unit cost times three.
    auto bulkrows=rows; bulkrows[1].output_amount=3;
    auto bulk=NativePlanner(bulkrows,{L"Battery",L"Fiber"},{{L"Coal",4},{L"Fluid",3}}).resolve(L"Battery",3);
    assert(bulk.total.at(L"Coal")==4 && bulk.units[1].at(L"Coal")==2 && !bulk.units[2].contains(L"Coal"));
    assert(alias_text(L"SRJ_0123456789abcdef0123456789abcdef"));
    assert(alias_text(L"BWJ_0123456789abcdef0123456789abcdef"));
    assert(!alias_text(L"BWJ_bad"));
    Journal journal{L"BWJ_0123456789abcdef0123456789abcdef",L"Bio_Battery",{1},plan};
    const std::wstring build(64,L'a');
    const auto bytes=encode_journal(journal,build);
    auto restored=decode_journal(bytes,journal.alias,build);
    assert(restored.schedule.total==plan.total && restored.schedule.units==plan.units && restored.station==journal.station);
    // The native save chooses progress, so an older checkpoint does not conflict
    // with a mutable sidecar counter. One immutable definition serves both saves.
    assert(suffix(restored.schedule,0)==plan.total);
    assert(suffix(restored.schedule,2)==plan.units[2]);
    for(auto bad:{bytes,std::vector<uint8_t>(bytes.begin(),bytes.end()-1)}) {
        bad[40]^=1; rejected=false;
        try { decode_journal(bad,journal.alias,build); } catch(const std::runtime_error&) { rejected=true; }
        assert(rejected);
    }
    rejected=false;
    try { decode_journal(bytes,journal.alias,std::wstring(64,L'b')); } catch(const std::runtime_error&) { rejected=true; }
    assert(rejected);
    rejected=false;
    try { decode_journal(bytes,L"SRJ_11111111111111111111111111111111",build); } catch(const std::runtime_error&) { rejected=true; }
    assert(rejected);
    // General recipe identities are discovered from station output products,
    // not from the old battery/fiber test whitelist. Recipe IDs may differ
    // from their product IDs, and one craft can yield several products.
    const std::vector<NativeRecipe> general{
        {L"Weapon_Mod",L"Weapon",1,{{L"Circuit",3},{L"Alloy",1}}},
        {L"Circuit_Pack",L"Circuit",2,{{L"Wire",3}}},
        {L"Wire_Pack",L"Wire",3,{{L"Ore",2}}},
        {L"ForeignSmelter",L"Alloy",1,{{L"MetalOre",2}}},
        {L"Unrelated",L"Unrelated",1,{{L"Other",1}}},
        {L"LockedCircuit",L"Circuit",1,{{L"Cheap",1}}}};
    const std::set<std::wstring> permitted{L"Weapon_Mod",L"Circuit_Pack",L"Wire_Pack",L"Unrelated"};
    const auto closure=dependency_recipes(general,permitted,L"Weapon_Mod");
    assert((closure==std::set<std::wstring>{L"Weapon_Mod",L"Circuit_Pack",L"Wire_Pack"}));
    auto general_plan=NativePlanner(general,closure,{{L"Circuit",1},{L"Ore",8},{L"Alloy",3}}).resolve(L"Weapon_Mod",3);
    assert(general_plan.total.at(L"Circuit")==1 && general_plan.total.at(L"Ore")==8);
    assert(general_plan.total.at(L"Alloy")==3 && !general_plan.total.contains(L"MetalOre"));
    Journal general_journal{L"SRJ_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",L"Weapon_Mod",{3},general_plan};
    const auto roundtrip=decode_journal(encode_journal(general_journal,build),general_journal.alias,build);
    assert(roundtrip.root==L"Weapon_Mod" && roundtrip.schedule.units==general_plan.units);
    rejected=false;
    try { dependency_recipes(general,permitted,L"ForeignSmelter"); } catch(const std::runtime_error&) { rejected=true; }
    assert(rejected);
    const std::vector<NativeRecipe> cyclic{
        {L"A",L"A",1,{{L"B",1}}},{L"B",L"B",1,{{L"A",1}}}};
    assert(dependency_recipes(cyclic,{L"A",L"B"},L"A").size()==2);
    const std::vector<NativeRecipe> computer_rows{
        {L"Computer",L"Computer",1,{{L"MachineParts2",2},{L"Plastic",3},{L"Bio_Battery",2},{L"CarbonFiber",2}}},
        {L"CarbonFiber",L"CarbonFiber",1,{{L"Coal",2},{L"FireOrgan",1}}}};
    const std::set<std::wstring> computer_scope{L"Computer",L"CarbonFiber"};
    const Amounts computer_stock{{L"MachineParts2",2},{L"Plastic",3},{L"Bio_Battery",2},
        {L"CarbonFiber",1},{L"Coal",4},{L"FireOrgan",2}};
    const auto computer=NativePlanner(computer_rows,computer_scope,computer_stock).resolve(L"Computer",1);
    assert(computer.total.size()==5 && !computer.total.contains(L"CarbonFiber"));
    assert(computer.total.at(L"Coal")==4 && computer.total.at(L"FireOrgan")==2);
    auto enough_carbon=computer_stock; enough_carbon[L"CarbonFiber"]=2;
    const auto stored=NativePlanner(computer_rows,computer_scope,enough_carbon).resolve(L"Computer",1);
    assert(stored.total.at(L"CarbonFiber")==2 && !stored.total.contains(L"Coal"));
    auto no_carbon=computer_stock; no_carbon[L"CarbonFiber"]=0;
    assert(NativePlanner(computer_rows,computer_scope,no_carbon).resolve(L"Computer",1).total==computer.total);
    auto short_raw=computer_stock; short_raw[L"Coal"]=2; short_raw[L"FireOrgan"]=1;
    rejected=false;
    try { NativePlanner(computer_rows,computer_scope,short_raw).resolve(L"Computer",1); }
    catch(const NativeSlotLimit&) { rejected=true; }
    assert(rejected); // Six slots cannot be hidden by inventing missing stock.
    const auto ui=NativePlanner(computer_rows,computer_scope,short_raw).preview(L"Computer",1);
    assert(ui.total==computer.total); // Shows the full raw requirement, including shortages.
    const auto repeated=NativePlanner(computer_rows,computer_scope,computer_stock);
    assert(repeated.resolve(L"Computer",1).total==repeated.resolve(L"Computer",1).total);
    const auto expanded=NativePlanner(computer_rows,computer_scope,short_raw,64).resolve(L"Computer",1);
    assert(expanded.total.size()==6 && expanded.total.at(L"CarbonFiber")==1);
    assert(expanded.total.at(L"Coal")==2 && expanded.total.at(L"FireOrgan")==1);
    Journal expanded_journal{L"SRJ_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",L"Computer",{4},expanded};
    const auto expanded_saved=decode_journal(encode_journal(expanded_journal,build),expanded_journal.alias,build);
    assert(expanded_saved.schedule.total==expanded.total);
    assert(suffix(expanded_saved.schedule,1).empty());
    const Amounts two_stock{{L"MachineParts2",4},{L"Plastic",6},{L"Bio_Battery",4},
        {L"CarbonFiber",1},{L"Coal",6},{L"FireOrgan",3}};
    const auto two=NativePlanner(computer_rows,computer_scope,two_stock,64).resolve(L"Computer",2);
    assert(two.total.size()==6 && two.units[0].at(L"CarbonFiber")==1);
    assert(!two.units[1].contains(L"CarbonFiber"));
    assert(suffix(two,1)==two.units[1]);
    for(const auto& [name,total]:two.total) {
        const auto first=two.units[0].contains(name)?two.units[0].at(name):0;
        const auto remainder=two.units[1].contains(name)?two.units[1].at(name):0;
        assert(first+remainder==total && total<=two_stock.at(name));
    }
    for(std::size_t count=1;count<=64;++count) {
        const auto indices=input_indices(count);
        assert(indices.size()==count);
        assert(std::find(indices.begin(),indices.end(),5)==indices.end());
        for(std::size_t index=0;index<count;++index) assert(indices[index]==(index<5?index:index+1));
        std::vector<int32_t> compact;
        for(std::size_t index=0;index<count;++index) compact.push_back(static_cast<int32_t>(index+100));
        const auto physical=physical_identities(compact,-1);
        for(std::size_t index=0;index<count;++index) assert(physical[indices[index]]==compact[index]);
        if(count>5) assert(physical[5]==-1);
    }
    rejected=false; try { input_indices(65); } catch(const std::runtime_error&) { rejected=true; } assert(rejected);
    // Actual native debit records cover every input, including positions after
    // the output slot. Sparse later units retain whole-job slot identities.
    auto remaining=two.total;
    for(std::size_t unit=0;unit<two.units.size();++unit) {
        const auto operations=input_debits(two.total,two.units[unit]);
        Amounts spent;
        for(const auto& operation:operations) {
            assert(operation.slot!=5);
            spent[operation.item]+=operation.quantity;
            remaining[operation.item]-=operation.quantity;
        }
        assert(spent==two.units[unit]);
        auto expected_remaining=suffix(two,unit+1);
        for(const auto& [item,count]:remaining) assert(count==(expected_remaining.contains(item)?expected_remaining.at(item):0));
    }
    const Amounts ai{{L"AncientParts2",4},{L"Bio_Battery",40},{L"Coal",80},{L"FireOrgan",40},
        {L"MachineParts2",40},{L"Plastic",60},{L"SkyislandIngot",40},{L"Thermal_Core",8}};
    Amounts ai_unit; for(const auto& [item,count]:ai) ai_unit[item]=count/4;
    const auto ai_debits=input_debits(ai,ai_unit);
    assert(ai_debits.size()==8);
    assert(ai_debits[5].item==L"Plastic" && ai_debits[5].slot==6 && ai_debits[5].quantity==15);
    assert(ai_debits[7].item==L"Thermal_Core" && ai_debits[7].slot==8 && ai_debits[7].quantity==2);
    rejected=false; try { input_debits(ai,{{L"Unknown",1}}); } catch(const std::runtime_error&) { rejected=true; } assert(rejected);
    // Quantity probes must agree with full schedules, including mixed stock,
    // slot fallback, alternative recipes, surplus and rejected requests.
    const auto agrees=[](const NativePlanner& planner,const std::wstring& root,int32_t batches) {
        bool craftable=true;
        try { planner.resolve(root,batches); } catch(const std::runtime_error&) { craftable=false; }
        assert(planner.can_resolve(root,batches)==craftable);
    };
    for(int32_t fiber=0;fiber<=4;++fiber) for(int32_t coal=0;coal<=12;coal+=3) {
        const auto planner=NativePlanner(rows,{L"Battery",L"Fiber",L"Fiber2"},
            {{L"Fiber",fiber},{L"Coal",coal},{L"Charcoal",10},{L"Fluid",3}});
        for(int32_t batches:{0,1,2,3,4,256,257}) agrees(planner,L"Battery",batches);
        agrees(planner,L"Unknown",1);
    }
    for(std::size_t capacity:{5u,64u}) for(int32_t fiber=0;fiber<=4;++fiber) {
        auto stock=two_stock; stock[L"CarbonFiber"]=fiber;
        const auto planner=NativePlanner(computer_rows,computer_scope,stock,capacity);
        for(int32_t batches:{1,2,3,256}) agrees(planner,L"Computer",batches);
    }
    agrees(NativePlanner(bulkrows,{L"Battery",L"Fiber"},{{L"Coal",4},{L"Fluid",3}}),L"Battery",3);
    agrees(retry_planner,L"Root",2);
    agrees(NativePlanner(cyclic,{L"A",L"B"},{}),L"A",1);
    assert(copied.can_resolve(L"Copy",2) && !copied.can_resolve(L"Copy",3));
    assert(copied.resolve(L"Copy",2).total.at(L"Input")==2);
}

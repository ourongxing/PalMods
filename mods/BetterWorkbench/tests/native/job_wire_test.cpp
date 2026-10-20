#include "../../native/src/job_wire.hpp"
#include <cassert>
using namespace better_workbench;
int main() {
    Journal job; job.alias=L"BWJ_0123456789abcdef0123456789abcdef_Battery";
    job.root=L"Battery"; job.station[0]=1;
    for (int i=0;i<256;++i) {
        job.schedule.units.push_back(i<2 ? Amounts{{L"Part",1}} : Amounts{{L"Ore",3},{L"Fiber",2}});
        for (const auto& [name,n]:job.schedule.units.back()) job.schedule.total[name]+=n;
    }
    auto wire=encode_wire(job);
    assert(wire.size()<512);
    auto received=decode_wire(wire,job.alias);
    assert(received.root==job.root && received.station==job.station);
    assert(received.schedule.total==job.schedule.total && received.schedule.units==job.schedule.units);
    auto rejects=[&](auto bytes,const auto& alias) {
        bool failed=false;
        try { decode_wire(bytes,alias); } catch (const std::runtime_error&) { failed=true; }
        assert(failed);
    };
    wire[4]^=1; rejects(wire,job.alias);
    rejects(encode_wire(job),L"BWJ_0123456789abcdef0123456789abcdef_Other");
    wire=encode_wire(job); wire.resize(8); rejects(wire,job.alias);
    job.alias=L"SRJ_0123456789abcdef0123456789abcdef";
    assert(decode_wire(encode_wire(job),job.alias).schedule.units==job.schedule.units);
    assert(!alias_text(L"BWJ_bad_Battery"));
    assert(!alias_text(L"BWJ_0123456789abcdef0123456789abcdef_../../escape"));
}

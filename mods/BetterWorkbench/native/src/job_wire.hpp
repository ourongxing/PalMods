#pragma once
#include "job_journal.hpp"

namespace better_workbench {
// Consecutive units usually share the same costs. Encode those runs so a
// 256-batch task does not send 256 identical inventory plans through RPC.
inline std::vector<uint8_t> encode_wire(const Journal& job) {
    Journal packed=job; packed.schedule={};
    std::vector<uint32_t> runs;
    for (const auto& unit:job.schedule.units) {
        if (!packed.schedule.units.empty() && packed.schedule.units.back()==unit) ++runs.back();
        else { packed.schedule.units.push_back(unit); runs.push_back(1); }
    }
    for (const auto& unit:packed.schedule.units)
        for (const auto& [name,count]:unit) packed.schedule.total[name]+=count;
    auto bytes=encode_journal(packed,L"BW-NET-1");
    JobBytes out; out.put(static_cast<uint32_t>(runs.size()));
    for (auto run:runs) out.put(run);
    out.bytes.insert(out.bytes.end(),bytes.begin(),bytes.end());
    const auto digest=checksum(out.bytes);
    for (unsigned i=0;i<8;++i) out.bytes.push_back(static_cast<uint8_t>(digest>>(i*8)));
    if (out.bytes.size()>262144) throw std::runtime_error("wire size limit");
    return out.bytes;
}
inline Journal decode_wire(std::vector<uint8_t> bytes,const std::wstring& alias) {
    if (bytes.size()<8 || bytes.size()>262144) throw std::runtime_error("wire size limit");
    uint64_t digest{};
    for (unsigned i=0;i<8;++i) digest|=uint64_t(bytes[bytes.size()-8+i])<<(i*8);
    bytes.resize(bytes.size()-8);
    if (checksum(bytes)!=digest) throw std::runtime_error("wire checksum mismatch");
    JobBytes input{std::move(bytes)};
    const auto count=input.get();
    if (!count || count>256) throw std::runtime_error("wire run limit");
    std::vector<uint32_t> runs; uint32_t total{};
    for (uint32_t i=0;i<count;++i) {
        const auto run=input.get();
        if (!run || run>256 || total+run>256) throw std::runtime_error("wire batch limit");
        total+=run; runs.push_back(run);
    }
    auto packed=decode_journal({input.bytes.begin()+input.position,input.bytes.end()},alias,L"BW-NET-1");
    if (packed.schedule.units.size()!=runs.size()) throw std::runtime_error("wire run mismatch");
    Journal job=packed; job.schedule={};
    for (std::size_t i=0;i<runs.size();++i)
        for (uint32_t j=0;j<runs[i];++j) {
            job.schedule.units.push_back(packed.schedule.units[i]);
            for (const auto& [name,count]:packed.schedule.units[i]) {
                const auto value=int64_t(job.schedule.total[name])+count;
                if (value>1000000000) throw std::runtime_error("wire total overflow");
                job.schedule.total[name]=static_cast<int32_t>(value);
            }
        }
    return job;
}
}

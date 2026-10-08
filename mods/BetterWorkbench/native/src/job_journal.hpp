#pragma once
#include "job_schedule.hpp"
#include <array>
#include <span>
namespace better_workbench {
struct Journal { std::wstring alias, root; std::array<uint8_t,16> station{}; Schedule schedule; };
inline bool alias_text(const std::wstring& name) {
    return name.size()==36 && (name.starts_with(L"BWJ_") || name.starts_with(L"SRJ_"))
        && std::all_of(name.begin()+4,name.end(),[](wchar_t c){return (c>=L'0'&&c<=L'9')||(c>=L'a'&&c<=L'f');});
}
inline uint64_t checksum(std::span<const uint8_t> bytes) {
    uint64_t value=14695981039346656037ULL;
    for(auto b:bytes){value^=b;value*=1099511628211ULL;} return value;
}
struct JobBytes {
    std::vector<uint8_t> bytes; std::size_t position{};
    void put(uint32_t n){for(unsigned i=0;i<4;++i)bytes.push_back(static_cast<uint8_t>(n>>(i*8)));}
    uint32_t get(){
        if(position+4>bytes.size())throw std::runtime_error("truncated job");
        uint32_t n{};for(unsigned i=0;i<4;++i)n|=uint32_t(bytes[position++])<<(i*8);return n;
    }
    void text(const std::wstring& name){
        if(name.empty()||name.size()>128)throw std::runtime_error("job name limit");put(static_cast<uint32_t>(name.size()));
        for(auto c:name){if(c<32||c>126)throw std::runtime_error("unsupported item identity");bytes.push_back(static_cast<uint8_t>(c));}
    }
    std::wstring text(){
        auto n=get();if(!n||n>128||position+n>bytes.size())throw std::runtime_error("invalid job name");std::wstring value;
        for(uint32_t i=0;i<n;++i){auto c=bytes[position++];if(c<32||c>126)throw std::runtime_error("invalid job name");value.push_back(c);}return value;
    }
};
inline std::vector<uint8_t> encode_journal(const Journal& job,const std::wstring& build){
    JobBytes data;data.put(0x34524a53);data.text(build);data.text(job.alias);data.text(job.root);
    data.bytes.insert(data.bytes.end(),job.station.begin(),job.station.end());data.put(static_cast<uint32_t>(job.schedule.units.size()));
    for(const auto& unit:job.schedule.units){data.put(static_cast<uint32_t>(unit.size()));for(const auto& [name,count]:unit){data.text(name);data.put(count);}}
    const auto digest=checksum(data.bytes);for(unsigned i=0;i<8;++i)data.bytes.push_back(static_cast<uint8_t>(digest>>(i*8)));return data.bytes;
}
inline Journal decode_journal(std::vector<uint8_t> bytes,const std::wstring& alias,const std::wstring& build){
    if(bytes.size()<100||bytes.size()>262144)throw std::runtime_error("job journal size mismatch");
    uint64_t digest{};for(unsigned i=0;i<8;++i)digest|=uint64_t(bytes[bytes.size()-8+i])<<(i*8);bytes.resize(bytes.size()-8);
    JobBytes data{std::move(bytes)};
    if(checksum(data.bytes)!=digest||data.get()!=0x34524a53||data.text()!=build)throw std::runtime_error("job build/checksum mismatch");
    Journal job;job.alias=data.text();job.root=data.text();
    if(job.alias!=alias||!alias_text(alias)||job.root==L"None"||alias_text(job.root)
        ||data.position+16>data.bytes.size())throw std::runtime_error("invalid job binding");
    std::copy_n(data.bytes.begin()+data.position,16,job.station.begin());data.position+=16;
    if(std::all_of(job.station.begin(),job.station.end(),[](auto b){return b==0;}))throw std::runtime_error("empty job station");
    const auto batches=data.get();if(!batches||batches>256)throw std::runtime_error("invalid job batches");
    for(uint32_t i=0;i<batches;++i){
        Amounts unit;const auto count=data.get();if(count>64)throw std::runtime_error("invalid job slots");
        for(uint32_t j=0;j<count;++j){
            auto material=data.text();const auto amount=data.get();
            if(material==L"None"||!amount||amount>1000000000||!unit.emplace(material,amount).second)throw std::runtime_error("invalid job amount");
            const auto total=int64_t(job.schedule.total[material])+amount;
            if(total>1000000000)throw std::runtime_error("job amount overflow");job.schedule.total[material]=static_cast<int32_t>(total);
        }job.schedule.units.push_back(std::move(unit));
    }
    if(data.position!=data.bytes.size()||job.schedule.total.empty()||job.schedule.total.size()>64)throw std::runtime_error("invalid job journal");return job;
}
}

#include "balance.hpp"
#include <cstdlib>
#include <iostream>
void require(bool value) {if(!value)std::abort();}
int main() {
    const std::array<int,3> base{70,70,70};
    const std::array<float,3> growth{5.5f,3.7f,3.7f};
    for(int s=0;s<3;++s) {
        const auto delta=bond::growth_delta(base,growth,s);
        require(delta>0);
        for(int rank=0;rank<=10;++rank) {
            const float old=base[s]+rank*growth[s];
            require(bond::gated_growth(base,growth,s,false)==growth[s]);
            const auto adjusted=base[s]+rank*bond::gated_growth(base,growth,s,true);
            require(adjusted>=old);
            require(std::abs(adjusted-(old+rank*delta))<0.0001f);
            require(bond::gated_growth(base,growth,s,true)==bond::gated_growth(base,growth,s,true));
            require(growth[s]==std::array<float,3>{5.5f,3.7f,3.7f}[s]);
        }
    }
    double total=0;
    for(int s=0;s<3;++s)total+=base[s]+10*(growth[s]+bond::growth_delta(base,growth,s));
    require(std::abs(total-450)<0.0001);
    for(int s=0;s<3;++s) {
        require(bond::growth_delta({140,140,135},{2,1,1.1f},s)==0);
        require(bond::growth_delta({100,100,100},{5,5,5},s)==0);
        require(bond::growth_delta({0,70,70},growth,s)==0);
    }
    std::cout<<"PASS: awakening gate, trust0..10, immutable original growth, target450, strong-Pal preservation\n";
}

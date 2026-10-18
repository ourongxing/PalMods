#include "PreviewPixels.hpp"
#include <cassert>
#include <iostream>
using namespace CustomPresetsPreview;
int main() {
    std::vector<LinearPixel> source(100*200,{0,0,0,0});
    for(int y=40;y<180;++y) for(int x=60;x<90;++x) source[y*100+x]={0.25f,0.5f,0.75f,1};
    const auto normal=compose_portrait(100,200,source.data(),false,false);
    assert(normal.size()==206*307);
    auto center=normal[153*206+103];
    assert((center>>24)==255);
    assert(std::abs(int((center>>16)&255)-137)<=1);
    assert(normal.front()==0 && normal.back()==0);
    int left=206,right=0,top=307,bottom=0;
    for(int y=0;y<307;++y) for(int x=0;x<206;++x) if(normal[y*206+x]>>24) {
        left=std::min(left,x);right=std::max(right,x);top=std::min(top,y);bottom=std::max(bottom,y);
    }
    assert(std::abs(left+right-205)<=1 && std::abs(top+bottom-306)<=1);
    auto differentLegs=source;
    for(int y=106;y<180;++y) for(int x=60;x<90;++x) differentLegs[y*100+x]={1,0,0,1};
    assert(compose_portrait(100,200,differentLegs.data(),false,false)==normal);
    for(auto& p:source) p.a=1-p.a;
    assert(compose_portrait(100,200,source.data(),false,false)==normal);
    for(auto& p:source) {p.a=1-p.a;p.r=srgb_encode(p.r)*255;p.g=srgb_encode(p.g)*255;p.b=srgb_encode(p.b)*255;p.a*=255;}
    assert(compose_portrait(100,200,source.data(),true,true)==normal);
    std::fill(source.begin(),source.end(),LinearPixel{0,0,0,0});
    bool rejected=false;
    try {compose_portrait(100,200,source.data(),false,false);} catch(const std::runtime_error&) {rejected=true;}
    assert(rejected);
    std::cout<<"PASS: portrait dimensions, alpha, gamma, centered torso and excluded legs\n";
}

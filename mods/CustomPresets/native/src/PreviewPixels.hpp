#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <vector>
namespace CustomPresetsPreview {
struct LinearPixel {float r,g,b,a;};
inline constexpr int portrait_width=206, portrait_height=307;
inline float srgb_encode(float v) {
    v=std::clamp(v,0.0f,1.0f);
    return v<=0.0031308f ? 12.92f*v : 1.055f*std::pow(v,1.0f/2.4f)-0.055f;
}
inline float srgb_decode(float v) {return v<=0.04045f ? v/12.92f : std::pow((v+0.055f)/1.055f,2.4f);}
inline std::vector<std::uint32_t> compose_portrait(int width,int height,const void* raw,bool ldr,bool encoded) {
    if (!raw || width<=0 || height<=0 || width>4096 || height>4096) throw std::runtime_error("Invalid portrait source");
    auto read=[&](int x,int y) {
        LinearPixel p;
        std::memcpy(&p,static_cast<const std::uint8_t*>(raw)+(y*width+x)*sizeof(p),sizeof(p));
        if (ldr) {p.r/=255; p.g/=255; p.b/=255; p.a/=255;}
        if (!std::isfinite(p.r)||!std::isfinite(p.g)||!std::isfinite(p.b)||!std::isfinite(p.a)) p={0,0,0,1};
        if (encoded) {p.r=srgb_decode(p.r);p.g=srgb_decode(p.g);p.b=srgb_decode(p.b);}
        return p;
    };
    float minAlpha=1,maxAlpha=0;
    for (int y=0;y<height;++y) for (int x=0;x<width;++x) {
        auto p=read(x,y); minAlpha=std::min(minAlpha,p.a);maxAlpha=std::max(maxAlpha,p.a);
    }
    const bool hasAlpha=maxAlpha-minAlpha>0.05f;
    const float cornerAlpha=(read(0,0).a+read(width-1,0).a+read(0,height-1).a+read(width-1,height-1).a)/4;
    auto opacity=[&](const LinearPixel& p) {
        if (hasAlpha) return std::clamp(cornerAlpha>0.5f ? 1-p.a : p.a,0.0f,1.0f);
        return std::max({p.r,p.g,p.b})>0.015f ? 1.0f : 0.0f;
    };
    int left=width,right=-1,top=height,bottom=-1;
    for (int y=0;y<height;++y) for (int x=0;x<width;++x) if (opacity(read(x,y))>0.04f) {
        left=std::min(left,x);right=std::max(right,x);top=std::min(top,y);bottom=std::max(bottom,y);
    }
    if (right<left || bottom<top) throw std::runtime_error("Character portrait not ready");
    // Native preset cards show the head and torso, ending around the waist.
    // Find the full silhouette first, then frame only its upper 46 percent.
    bottom=top+std::max(1,static_cast<int>(std::ceil((bottom-top+1)*0.46)))-1;
    left=width; right=-1;
    for (int y=top;y<=bottom;++y) for (int x=0;x<width;++x) if (opacity(read(x,y))>0.04f) {
        left=std::min(left,x);right=std::max(right,x);
    }
    if (right<left) throw std::runtime_error("Character torso not ready");
    constexpr double padding=6;
    const double scale=std::min((portrait_width-2*padding)/(right-left+1),(portrait_height-2*padding)/(bottom-top+1));
    const double offsetX=(portrait_width-(right-left+1)*scale)/2;
    const double offsetY=(portrait_height-(bottom-top+1)*scale)/2;
    std::vector<std::uint32_t> output(portrait_width*portrait_height,0);
    auto byte=[](float v) {return static_cast<std::uint32_t>(std::lround(std::clamp(v,0.0f,1.0f)*255));};
    for (int y=0;y<portrait_height;++y) for (int x=0;x<portrait_width;++x) {
        double u=(x+0.5-offsetX)/scale+left-0.5, v=(y+0.5-offsetY)/scale+top-0.5;
        if (u<left-0.5 || u>right+0.5 || v<top-0.5 || v>bottom+0.5) continue;
        int x0=static_cast<int>(std::floor(u)),y0=static_cast<int>(std::floor(v));
        float fx=static_cast<float>(u-x0),fy=static_cast<float>(v-y0);
        float r=0,g=0,b=0,a=0;
        for (int dy=0;dy<2;++dy) for (int dx=0;dx<2;++dx) {
            int sx=x0+dx,sy=y0+dy;
            if (sx<0 || sy<top || sx>=width || sy>bottom) continue;
            auto p=read(sx,sy);
            float weight=(dx?fx:1-fx)*(dy?fy:1-fy),alpha=opacity(p);
            a+=alpha*weight;
            // Scene color is premultiplied by coverage. PNG stores straight alpha.
            r+=p.r*weight;g+=p.g*weight;b+=p.b*weight;
        }
        if (a<0.001f) continue;
        output[y*portrait_width+x]=(byte(a)<<24)|(byte(srgb_encode(r/a))<<16)|(byte(srgb_encode(g/a))<<8)|byte(srgb_encode(b/a));
    }
    return output;
}
}

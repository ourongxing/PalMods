#pragma once
#include <algorithm>
#include <string>
#include <stdexcept>
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>
namespace CustomPresetsPreview {
using Microsoft::WRL::ComPtr;
inline void checked(HRESULT result) {
    if (FAILED(result)) throw std::runtime_error("PNG preview encoding failed");
}
inline std::wstring wide_path(const std::string& value) {
    const auto count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (count <= 0) throw std::runtime_error("Invalid preview path");
    std::wstring result(count, L'\0');
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), result.data(), count))
        throw std::runtime_error("Preview path conversion failed");
    return result;
}
inline void write_preview(const std::wstring& path, UINT width, UINT height, BYTE* pixels) {
    const auto initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) checked(initialized);
    struct Apartment { bool active; ~Apartment() { if (active) CoUninitialize(); } } apartment{SUCCEEDED(initialized)};
    const std::wstring temporary = path + L".tmp";
    try {
        {
            ComPtr<IWICImagingFactory> factory;
            checked(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)));
            ComPtr<IWICBitmap> bitmap;
            checked(factory->CreateBitmapFromMemory(width, height, GUID_WICPixelFormat32bppBGRA, width*4, width*height*4, pixels, &bitmap));
            // Keep the source aspect ratio and downsample, rather than stretching a portrait.
            const double scale = std::min(1.0, 512.0 / std::max(width,height));
            const UINT outWidth = std::max(1u, static_cast<UINT>(width*scale));
            const UINT outHeight = std::max(1u, static_cast<UINT>(height*scale));
            ComPtr<IWICBitmapScaler> scaler;
            checked(factory->CreateBitmapScaler(&scaler));
            checked(scaler->Initialize(bitmap.Get(), outWidth, outHeight, WICBitmapInterpolationModeFant));
            ComPtr<IWICStream> stream;
            checked(factory->CreateStream(&stream));
            checked(stream->InitializeFromFilename(temporary.c_str(), GENERIC_WRITE));
            ComPtr<IWICBitmapEncoder> encoder;
            checked(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder));
            checked(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache));
            ComPtr<IWICBitmapFrameEncode> frame;
            checked(encoder->CreateNewFrame(&frame, nullptr));
            checked(frame->Initialize(nullptr));
            checked(frame->SetSize(outWidth,outHeight));
            auto format = GUID_WICPixelFormat32bppBGRA;
            checked(frame->SetPixelFormat(&format));
            checked(frame->WriteSource(scaler.Get(), nullptr));
            checked(frame->Commit());
            checked(encoder->Commit());
        }
        if (!MoveFileExW(temporary.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))
            throw std::runtime_error("Preview file replacement failed");
    } catch (...) { DeleteFileW(temporary.c_str()); throw; }
}
}

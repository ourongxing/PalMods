#pragma once
#include "Engine/Texture2D.h"
#include "Materials/Material.h"
#include "Materials/MaterialExpressionTextureSample.h"
#include "Materials/MaterialExpressionWorldPosition.h"
#include "Materials/MaterialExpressionTransformPosition.h"
#include "Materials/MaterialExpressionComponentMask.h"
#include "Materials/MaterialExpressionMultiply.h"
#include "Materials/MaterialExpressionAdd.h"
#include "Materials/MaterialExpressionConstant3Vector.h"
#include "IImageWrapper.h"
#include "IImageWrapperModule.h"
#include "Misc/FileHelper.h"
#include "Modules/ModuleManager.h"

static bool SaveAsset(UObject* Asset);

static UTexture2D* WindTexture(const FString& Name, bool Icon) {
 const FString File=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("../wind-art")/(Name+TEXT(".png")));
 TArray<uint8> PNG; if(!FFileHelper::LoadFileToArray(PNG,*File)) return nullptr;
 auto& Images=FModuleManager::LoadModuleChecked<IImageWrapperModule>(TEXT("ImageWrapper"));
 auto Decoder=Images.CreateImageWrapper(EImageFormat::PNG);
 TArray64<uint8> Pixels;
 if(!Decoder->SetCompressed(PNG.GetData(),PNG.Num()) || !Decoder->GetRaw(ERGBFormat::BGRA,8,Pixels)) return nullptr;
 auto Package=CreatePackage(*(TEXT("/Game/Mods/CodexWindNative/Textures/")+Name));
 auto Texture=NewObject<UTexture2D>(Package,*Name,RF_Public|RF_Standalone);
 Texture->Source.Init(Decoder->GetWidth(),Decoder->GetHeight(),1,1,TSF_BGRA8,Pixels.GetData());
 Texture->SRGB=true;
 Texture->CompressionSettings=Icon?TC_EditorIcon:TC_Default;
 Texture->LODGroup=Icon?TEXTUREGROUP_UI:TEXTUREGROUP_World;
 Texture->MipGenSettings=Icon?TMGS_NoMipmaps:TMGS_FromTextureGroup;
 Texture->NeverStream=Icon;
 Texture->AddressX=TA_Clamp; Texture->AddressY=TA_Clamp;
 Texture->PostEditChange();
 return SaveAsset(Texture)?Texture:nullptr;
}

template<class T> static T* WindExpression(UMaterial* Material) {
 auto Expression=NewObject<T>(Material);
 Material->GetExpressionCollection().AddExpression(Expression);
 return Expression;
}

static UMaterial* WindDeckMaterial(const FString& Suffix,UTexture2D* Texture) {
 const FString Name=TEXT("M_WindDeck")+Suffix;
 auto Material=NewObject<UMaterial>(CreatePackage(*(TEXT("/Game/Mods/CodexWindNative/Materials/")+Name)),*Name,RF_Public|RF_Standalone);
 auto Position=WindExpression<UMaterialExpressionWorldPosition>(Material);
 auto Local=WindExpression<UMaterialExpressionTransformPosition>(Material);
 Local->TransformSourceType=TRANSFORMPOSSOURCE_World; Local->TransformType=TRANSFORMPOSSOURCE_Local;
 Local->Input.Connect(0,Position);
 auto XY=WindExpression<UMaterialExpressionComponentMask>(Material); XY->R=true; XY->G=true; XY->B=false; XY->A=false; XY->Input.Connect(0,Local);
 auto Scale=WindExpression<UMaterialExpressionMultiply>(Material); Scale->A.Connect(0,XY); Scale->ConstB=0.01f;
 auto UV=WindExpression<UMaterialExpressionAdd>(Material); UV->A.Connect(0,Scale); UV->ConstB=0.5f;
 auto Sample=WindExpression<UMaterialExpressionTextureSample>(Material); Sample->Texture=Texture; Sample->SamplerType=SAMPLERTYPE_Color; Sample->Coordinates.Connect(0,UV);
 auto Light=WindExpression<UMaterialExpressionMultiply>(Material); Light->A.Connect(0,Sample); Light->B.Connect(4,Sample);
 auto Glow=WindExpression<UMaterialExpressionMultiply>(Material); Glow->A.Connect(0,Light); Glow->ConstB=1.8f;
 auto Data=Material->GetEditorOnlyData(); Data->BaseColor.Connect(0,Sample); Data->EmissiveColor.Connect(0,Glow);
 Data->Metallic.UseConstant=true; Data->Metallic.Constant=0.65f;
 Data->Roughness.UseConstant=true; Data->Roughness.Constant=0.48f;
 Material->PostEditChange();
 return SaveAsset(Material)?Material:nullptr;
}

static UMaterial* WindMarkerMaterial(const FString& Suffix,const FLinearColor& Tint) {
 const FString Name=TEXT("M_WindMarker")+Suffix;
 auto Material=NewObject<UMaterial>(CreatePackage(*(TEXT("/Game/Mods/CodexWindNative/Materials/")+Name)),*Name,RF_Public|RF_Standalone);
 auto Color=WindExpression<UMaterialExpressionConstant3Vector>(Material); Color->Constant=Tint;
 auto Data=Material->GetEditorOnlyData(); Data->BaseColor.Connect(0,Color); Data->EmissiveColor.Connect(0,Color);
 Data->Metallic.UseConstant=true; Data->Metallic.Constant=0.25f;
 Data->Roughness.UseConstant=true; Data->Roughness.Constant=0.38f;
 Material->PostEditChange();
 return SaveAsset(Material)?Material:nullptr;
}

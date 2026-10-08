#pragma once
#include "Engine/SceneCapture2D.h"
#include "Engine/TextureRenderTarget2D.h"
#include "Engine/DirectionalLight.h"
#include "Components/SceneCaptureComponent2D.h"
#include "Components/DirectionalLightComponent.h"
#include "ImageUtils.h"
#include "ShaderCompiler.h"
#include "RenderingThread.h"
#include "AssetCompilingManager.h"

static int32 RenderWindPreview() {
 // The build commandlet is intentionally non-client. Allocate a real render
 // scene only while producing the editor preview; game assets are unchanged.
 TGuardValue<bool> ClientGuard(GIsClient,true);
 GShaderCompilingManager->FinishAllCompilation();
 const auto IVS=UWorld::InitializationValues().AllowAudioPlayback(false).CreatePhysicsScene(true).CreateNavigation(false).CreateAISystem(false).ShouldSimulatePhysics(false).SetTransactional(false);
 auto World=UWorld::CreateWorld(EWorldType::Game,false,TEXT("WindArtPreview"),nullptr,true,ERHIFeatureLevel::Num,&IVS);
 GEngine->CreateNewWorldContext(EWorldType::Game).SetCurrentWorld(World);
 TGuardValue<bool> ScriptGuard(GAllowActorScriptExecutionInEditor,true);
 FActorSpawnParameters Spawn; Spawn.SpawnCollisionHandlingOverride=ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
 const TCHAR* Sizes[]={TEXT("Small"),TEXT("Medium"),TEXT("Large")};
 const float Positions[]={-550.f,0.f,650.f};
 for(int32 I=0;I<3;I++) {
   const FString Name=FString(TEXT("BP_Wind"))+Sizes[I];
   auto Class=LoadObject<UClass>(nullptr,*(TEXT("/Game/Mods/CodexWindNative/")+Name+TEXT(".")+Name+TEXT("_C")));
   if(!Class) return 31;
   auto Pad=World->SpawnActor<APalBuildObject>(Class,FVector(Positions[I],0,0),FRotator::ZeroRotator,Spawn);
   auto Mesh=Cast<UStaticMeshComponent>(Pad->MainMeshRef.GetComponent(Pad));
   UE_LOG(LogTemp,Display,TEXT("WIND_PREVIEW_MESH: %s valid=%d visible=%d registered=%d render=%d"),Sizes[I],Mesh!=nullptr,Mesh?Mesh->IsVisible():false,Mesh?Mesh->IsRegistered():false,Mesh?Mesh->IsRenderStateCreated():false);
 }
 // Engine primitive meshes and texture resources compile asynchronously too.
 // A commandlet has no editor tick to finish them or recreate render states.
 FAssetCompilingManager::Get().FinishAllCompilation();
 GShaderCompilingManager->FinishAllCompilation();
 auto Light=World->SpawnActor<ADirectionalLight>(FVector(0,0,1000),FRotator(-55,-40,0),Spawn);
 Light->GetLightComponent()->SetMobility(EComponentMobility::Movable);
 Light->GetLightComponent()->SetIntensity(7.f);
 auto Capture=World->SpawnActor<ASceneCapture2D>(FVector(150,-1400,1800),FRotator::ZeroRotator,Spawn);
 Capture->SetActorRotation((FVector(150,0,0)-Capture->GetActorLocation()).Rotation());
 auto Component=Capture->GetCaptureComponent2D();
 auto Target=NewObject<UTextureRenderTarget2D>();
 Target->ClearColor=FLinearColor(0.025,0.04,0.055,1); Target->InitCustomFormat(1600,900,PF_B8G8R8A8,false);
 Component->TextureTarget=Target; Component->ProjectionType=ECameraProjectionMode::Orthographic; Component->OrthoWidth=1900.f;
 // Capture scene color to review textures without camera exposure history.
 Component->CaptureSource=SCS_SceneColorHDR;
 Component->bCaptureEveryFrame=false; Component->bCaptureOnMovement=false;
 Component->PostProcessSettings.bOverride_AutoExposureMethod=true; Component->PostProcessSettings.AutoExposureMethod=AEM_Manual;
 Component->PostProcessSettings.bOverride_AutoExposureBias=true; Component->PostProcessSettings.AutoExposureBias=1.f;
 World->UpdateWorldComponents(true,false); FlushRenderingCommands();
 Component->CaptureScene(); FlushRenderingCommands();
 TArray<FColor> Pixels; Target->GameThread_GetRenderTargetResource()->ReadPixels(Pixels);
 if(Pixels.Num()!=1600*900) return 32;
 int32 VisiblePixels=0;
 for(const FColor& Pixel:Pixels) if(Pixel.R>20 || Pixel.G>20 || Pixel.B>20) VisiblePixels++;
 if(VisiblePixels<1000) { UE_LOG(LogTemp,Error,TEXT("WIND_PREVIEW_EMPTY: %d pixels"),VisiblePixels); return 34; }
 TArray<uint8> PNG; FImageUtils::CompressImageArray(1600,900,Pixels,PNG);
 const FString File=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("../wind-art/wind-in-engine.png"));
 if(!FFileHelper::SaveArrayToFile(PNG,*File)) return 33;
 GEngine->DestroyWorldContext(World); World->DestroyWorld(false); FlushRenderingCommands();
 UE_LOG(LogTemp,Display,TEXT("WIND_PREVIEW_SUCCESS: %s"),*File);
 return 0;
}

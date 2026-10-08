#include "WindBuildCommandlet.h"
#include "PalBuildObject.h"
#include "Engine/Blueprint.h"
#include "Engine/BlueprintGeneratedClass.h"
#include "Engine/SimpleConstructionScript.h"
#include "Engine/SCS_Node.h"
#include "Components/StaticMeshComponent.h"
#include "Components/BoxComponent.h"
#include "Components/SceneComponent.h"
#include "GameFramework/Character.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Engine/World.h"
#include "Engine/OverlapResult.h"
#include "Engine/Engine.h"
#include "EngineGlobals.h"
#include "ScriptDisassembler.h"
#include "NiagaraComponent.h"
#include "NiagaraSystem.h"
#include "NiagaraSystemFactoryNew.h"
#include "Factories/Factory.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "KismetCompiler.h"
#include "K2Node_Event.h"
#include "K2Node_CallFunction.h"
#include "K2Node_IfThenElse.h"
#include "K2Node_DynamicCast.h"
#include "K2Node_VariableGet.h"
#include "EdGraphSchema_K2.h"
#include "UObject/SavePackage.h"
#include "Misc/PackageName.h"
#include "HAL/FileManager.h"
#include "Kismet/KismetMathLibrary.h"
#include "WindVisualAssets.h"
#include "WindPreview.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

UWindBuildCommandlet::UWindBuildCommandlet() { IsClient=false; IsServer=false; IsEditor=true; LogToConsole=true; }

static bool SaveAsset(UObject* Asset) {
 const FString File=FPackageName::LongPackageNameToFilename(Asset->GetOutermost()->GetName(), FPackageName::GetAssetPackageExtension());
 IFileManager::Get().MakeDirectory(*FPaths::GetPath(File),true);
 FSavePackageArgs Args; Args.TopLevelFlags=RF_Public|RF_Standalone; Args.SaveFlags=SAVE_NoError;
 return UPackage::SavePackage(Asset->GetOutermost(),Asset,*File,Args);
}
template<class T> static T* Node(UEdGraph* Graph) {
 T* N=NewObject<T>(Graph); Graph->AddNode(N,false,false); N->CreateNewGuid(); return N;
}
static void Link(UEdGraphPin* A, UEdGraphPin* B) {
 check(A && B); const UEdGraphSchema_K2* Schema=GetDefault<UEdGraphSchema_K2>();
 if(!Schema->TryCreateConnection(A,B)) UE_LOG(LogTemp,Fatal,TEXT("Cannot link %s to %s"),*A->PinName.ToString(),*B->PinName.ToString());
}
static UK2Node_Event* Event(UEdGraph* G,UClass* Owner,FName Name) {
 auto N=Node<UK2Node_Event>(G); N->EventReference.SetExternalMember(Name,Owner); N->bOverrideFunction=true; N->AllocateDefaultPins(); return N;
}
static UK2Node_CallFunction* Call(UEdGraph* G,UClass* Owner,FName Name) {
 auto N=Node<UK2Node_CallFunction>(G); N->SetFromFunction(Owner->FindFunctionByName(Name)); N->AllocateDefaultPins(); return N;
}
static UK2Node_VariableGet* Get(UEdGraph* G,FName Name) {
 auto N=Node<UK2Node_VariableGet>(G); N->VariableReference.SetSelfMember(Name); N->AllocateDefaultPins(); return N;
}
static void Default(UEdGraphPin* P,const FString& V) { check(P); GetDefault<UEdGraphSchema_K2>()->TrySetDefaultValue(*P,V); }
static void HideWindMeshes(UEdGraph* Graph,UEdGraphPin* Exec,bool Hidden,UEdGraphPin* HiddenValue=nullptr) {
 for(const FName Name:{FName(TEXT("StaticMesh"))}) {
   auto Mesh=Get(Graph,Name); auto Hide=Call(Graph,USceneComponent::StaticClass(),TEXT("SetHiddenInGame"));
   Link(Exec,Hide->GetExecPin()); Link(Mesh->FindPinChecked(Name),Hide->FindPinChecked(UEdGraphSchema_K2::PN_Self));
   if(HiddenValue) Link(HiddenValue,Hide->FindPinChecked(TEXT("NewHidden")));
   else Default(Hide->FindPinChecked(TEXT("NewHidden")),Hidden?TEXT("true"):TEXT("false"));
   Exec=Hide->GetThenPin();
 }
}

static int32 BuildWindVariant(UNiagaraSystem* FX,const FString& Suffix,float Radius,float FXHeightScale,UMaterial* Deck) {
 const FString BlueprintName=TEXT("BP_Wind")+Suffix;
 const FName BuildingId=*(TEXT("CodexWindNative")+Suffix);
 const float Size=Radius/100.f;
 UPackage* Package=CreatePackage(*(TEXT("/Game/Mods/CodexWindNative/")+BlueprintName));
 auto BP=FKismetEditorUtilities::CreateBlueprint(APalBuildObject::StaticClass(),Package,*BlueprintName,BPTYPE_Normal,UBlueprint::StaticClass(),UBlueprintGeneratedClass::StaticClass());
 auto SCS=BP->SimpleConstructionScript;
 // Keep the actor root unscaled. Placement and wind bounds must not inherit
 // the thin cylinder's nonuniform scale or its offset above the ground.
 auto RootNode=SCS->CreateNode(USceneComponent::StaticClass(),TEXT("WindRoot")); SCS->AddNode(RootNode);
 CastChecked<USceneComponent>(RootNode->ComponentTemplate)->SetMobility(EComponentMobility::Movable);
 auto BaseNode=SCS->CreateNode(UStaticMeshComponent::StaticClass(),TEXT("StaticMesh")); RootNode->AddChildNode(BaseNode);
 auto Base=CastChecked<UStaticMeshComponent>(BaseNode->ComponentTemplate);
 Base->SetStaticMesh(LoadObject<UStaticMesh>(nullptr,TEXT("/Engine/BasicShapes/Cylinder.Cylinder")));
 Base->SetRelativeLocation(FVector(0,0,5)); Base->SetRelativeScale3D(FVector(2*Size,2*Size,0.1));
 Base->SetMaterial(0,Deck);
 Base->SetCollisionProfileName(TEXT("MapObjectPhysics")); Base->SetGenerateOverlapEvents(false);
 Base->SetCollisionEnabled(ECollisionEnabled::NoCollision);
 Base->SetMobility(EComponentMobility::Movable);

 auto OverlapNode=SCS->CreateNode(UBoxComponent::StaticClass(),TEXT("CheckOverlapCollision")); RootNode->AddChildNode(OverlapNode);
 auto Placement=CastChecked<UBoxComponent>(OverlapNode->ComponentTemplate);
 // Leave clearance above the supporting surface. A box whose lower face is
 // exactly on the terrain can report permanent overlap due to contact margins.
 Placement->SetRelativeLocation(FVector(0,0,7)); Placement->SetBoxExtent(FVector(0.85f*Radius,0.85f*Radius,3));
 Placement->SetCollisionProfileName(TEXT("BuildingOverlap")); Placement->SetGenerateOverlapEvents(true);
 Placement->SetMobility(EComponentMobility::Movable);

 auto VolumeNode=SCS->CreateNode(UBoxComponent::StaticClass(),TEXT("WindVolume")); RootNode->AddChildNode(VolumeNode);
 auto Volume=CastChecked<UBoxComponent>(VolumeNode->ComponentTemplate);
 Volume->SetRelativeLocation(FVector(0,0,210));
 Volume->SetBoxExtent(FVector(0.9f*Radius,0.9f*Radius,200)); Volume->SetCollisionEnabled(ECollisionEnabled::NoCollision);
 Volume->SetCollisionResponseToAllChannels(ECR_Ignore);
 // Only character object channels participate, never placement/attack traces.
 Volume->SetCollisionResponseToChannel(ECC_Pawn,ECR_Overlap);
 Volume->SetCollisionResponseToChannel(ECC_GameTraceChannel3,ECR_Overlap); // PlayerPawn
 Volume->SetCollisionResponseToChannel(ECC_GameTraceChannel8,ECR_Overlap); // LiftedupPawn
 Volume->SetGenerateOverlapEvents(true); Volume->SetMobility(EComponentMobility::Movable);

 // A query-only selection volume survives native mesh collision/visibility
 // changes. It neither blocks players nor participates in placement overlap.
 auto TargetNode=SCS->CreateNode(UBoxComponent::StaticClass(),TEXT("DismantleTarget")); RootNode->AddChildNode(TargetNode);
 auto Target=CastChecked<UBoxComponent>(TargetNode->ComponentTemplate);
 Target->SetRelativeLocation(FVector(0,0,100)); Target->SetBoxExtent(FVector(0.9f*Radius,0.9f*Radius,100));
 Target->SetCollisionObjectType(ECC_WorldDynamic); Target->SetCollisionEnabled(ECollisionEnabled::NoCollision);
 Target->SetCollisionResponseToAllChannels(ECR_Ignore);
 Target->SetCollisionResponseToChannel(ECC_Visibility,ECR_Block);
 Target->SetCollisionResponseToChannel(ECC_GameTraceChannel7,ECR_Block);
 Target->SetGenerateOverlapEvents(false); Target->SetMobility(EComponentMobility::Movable);

 auto FXNode=SCS->CreateNode(UNiagaraComponent::StaticClass(),TEXT("WindFX")); RootNode->AddChildNode(FXNode);
 auto FXComp=CastChecked<UNiagaraComponent>(FXNode->ComponentTemplate);
 FXComp->SetRelativeScale3D(FVector(0.5*Size,0.5*Size,FXHeightScale)); FXComp->SetAsset(FX); FXComp->bAutoActivate=false;
 FXComp->SetMobility(EComponentMobility::Movable);
 // Scale the transform once; multiplying the Niagara user scale as well
 // would make medium/large effects grow quadratically on compatible systems.
 FXComp->SetVariableFloat(TEXT("User.Scale"),0.5f);

 FKismetEditorUtilities::CompileBlueprint(BP);
 auto CDO=CastChecked<APalBuildObject>(BP->GeneratedClass->GetDefaultObject());
 CDO->BuildObjectId=BuildingId;
 CDO->MainMeshRef.ComponentProperty=TEXT("StaticMesh");
 CDO->OverlapCheckCollisionRef.ComponentProperty=TEXT("CheckOverlapCollision");
 CDO->bIgnoreBuildInstallConnection=true;
 CDO->bNotConstructConnectorInGame=true;
 CDO->bExistsArrowInSimulatingTransform=false;
 CDO->ArrowInSimulatingRelativeTransform=FTransform(FRotator::ZeroRotator,FVector(0,0,30));

 UEdGraph* Graph=BP->UbergraphPages[0];
 // Actual player jump events are handled by the scoped Lua hook.
 // Walking or falling into the volume never launches characters.
 for(int Mode=0;Mode<2;Mode++) {
   auto State=Event(Graph,APalBuildObject::StaticClass(),Mode==0?TEXT("OnAvailable_BlueprintImpl"):TEXT("OnNotAvailable_BlueprintImpl"));
   auto FXGet=Get(Graph,TEXT("WindFX"));
   auto FXCall=Call(Graph,UActorComponent::StaticClass(),Mode==0?TEXT("Activate"):TEXT("Deactivate"));
   Link(State->FindPinChecked(UEdGraphSchema_K2::PN_Then),FXCall->GetExecPin());
   Link(FXGet->FindPinChecked(TEXT("WindFX")),FXCall->FindPinChecked(UEdGraphSchema_K2::PN_Self));
   if(Mode==0) Default(FXCall->FindPinChecked(TEXT("bReset")),TEXT("true"));
   auto VolumeGet=Get(Graph,TEXT("WindVolume"));
   auto Collision=Call(Graph,UPrimitiveComponent::StaticClass(),TEXT("SetCollisionEnabled"));
   Link(FXCall->GetThenPin(),Collision->GetExecPin());
   Link(VolumeGet->FindPinChecked(TEXT("WindVolume")),Collision->FindPinChecked(UEdGraphSchema_K2::PN_Self));
   Default(Collision->FindPinChecked(TEXT("NewType")),Mode==0?TEXT("QueryOnly"):TEXT("NoCollision"));
   auto MeshGet=Get(Graph,TEXT("StaticMesh"));
   auto MeshCollision=Call(Graph,UPrimitiveComponent::StaticClass(),TEXT("SetCollisionEnabled"));
   Link(Collision->GetThenPin(),MeshCollision->GetExecPin());
   Link(MeshGet->FindPinChecked(TEXT("StaticMesh")),MeshCollision->FindPinChecked(UEdGraphSchema_K2::PN_Self));
   Default(MeshCollision->FindPinChecked(TEXT("NewType")),TEXT("NoCollision"));
   auto TargetGet=Get(Graph,TEXT("DismantleTarget"));
   auto TargetCollision=Call(Graph,UPrimitiveComponent::StaticClass(),TEXT("SetCollisionEnabled"));
   Link(MeshCollision->GetThenPin(),TargetCollision->GetExecPin());
   Link(TargetGet->FindPinChecked(TEXT("DismantleTarget")),TargetCollision->FindPinChecked(UEdGraphSchema_K2::PN_Self));
   Default(TargetCollision->FindPinChecked(TEXT("NewType")),Mode==0?TEXT("QueryOnly"):TEXT("NoCollision"));
   HideWindMeshes(Graph,TargetCollision->GetThenPin(),Mode==0);
 }
 auto Dismantle=Event(Graph,APalBuildObject::StaticClass(),TEXT("OnChangeVisualForDismantle"));
 auto NotDismantle=Call(Graph,UKismetMathLibrary::StaticClass(),TEXT("Not_PreBool"));
 Link(Dismantle->FindPinChecked(TEXT("bDismantle")),NotDismantle->FindPinChecked(TEXT("A")));
 HideWindMeshes(Graph,Dismantle->FindPinChecked(UEdGraphSchema_K2::PN_Then),false,NotDismantle->GetReturnValuePin());
 FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(BP);
 FCompilerResultsLog Results; FKismetEditorUtilities::CompileBlueprint(BP,EBlueprintCompileOptions::None,&Results);
 if(Results.NumErrors>0 || BP->Status==BS_Error) { UE_LOG(LogTemp,Error,TEXT("Blueprint compilation failed: %d"),Results.NumErrors); return 2; }
 // Recompilation reinstantiates the CDO: explicitly preserve serialized defaults.
 CDO=CastChecked<APalBuildObject>(BP->GeneratedClass->GetDefaultObject());
 CDO->BuildObjectId=BuildingId; CDO->MainMeshRef.ComponentProperty=TEXT("StaticMesh");
 CDO->OverlapCheckCollisionRef.ComponentProperty=TEXT("CheckOverlapCollision");
 CDO->bIgnoreBuildInstallConnection=true; CDO->bNotConstructConnectorInGame=true;
 CDO->bExistsArrowInSimulatingTransform=false; CDO->ArrowInSimulatingRelativeTransform=FTransform::Identity;
 if(!SaveAsset(BP)) return 3;
 const auto IVS=UWorld::InitializationValues().AllowAudioPlayback(false).CreatePhysicsScene(true).EnableTraceCollision(true).CreateNavigation(false).CreateAISystem(false).ShouldSimulatePhysics(false).SetTransactional(false);
 UWorld* World=UWorld::CreateWorld(EWorldType::Game,false,TEXT("WindValidation"),nullptr,true,ERHIFeatureLevel::Num,&IVS);
 GEngine->CreateNewWorldContext(EWorldType::Game).SetCurrentWorld(World);
 TGuardValue<bool> ScriptGuard(GAllowActorScriptExecutionInEditor,true);
 FActorSpawnParameters SpawnParams; SpawnParams.SpawnCollisionHandlingOverride=ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
 auto Pad=World->SpawnActor<APalBuildObject>(BP->GeneratedClass,FVector::ZeroVector,FRotator::ZeroRotator,SpawnParams);
 auto OwnedPlacement=::Cast<UBoxComponent>(Pad->OverlapCheckCollisionRef.GetComponent(Pad));
 auto OwnedBase=::Cast<UStaticMeshComponent>(Pad->MainMeshRef.GetComponent(Pad));
 auto PreviewVolume=FindObject<UBoxComponent>(Pad,TEXT("WindVolume"));
 if(!OwnedPlacement || !OwnedBase || !PreviewVolume) return 11;
 if(Pad->BuildObjectId!=BuildingId || OwnedBase->GetMaterial(0)!=Deck) return 19;
 if(!OwnedPlacement->GetScaledBoxExtent().Equals(FVector(0.85f*Radius,0.85f*Radius,3),0.01f) ||
    !PreviewVolume->GetScaledBoxExtent().Equals(FVector(0.9f*Radius,0.9f*Radius,200),0.01f)) return 20;
 if(!Pad->GetRootComponent()->GetComponentScale().Equals(FVector::OneVector)) return 12;
 if(PreviewVolume->GetCollisionEnabled()!=ECollisionEnabled::NoCollision || OwnedBase->GetCollisionEnabled()!=ECollisionEnabled::NoCollision) return 13;
 OwnedPlacement->UpdateBounds();
 if(OwnedPlacement->Bounds.GetBox().Min.Z<4.f || !OwnedPlacement->GetGenerateOverlapEvents()) return 14;
 // Exercise real Chaos queries against a floor and a genuine obstacle. This
 // checks the collision geometry, not the mocked native installation strategy.
 auto Floor=World->SpawnActor<AActor>();
 auto FloorMesh=NewObject<UBoxComponent>(Floor); Floor->SetRootComponent(FloorMesh); Floor->AddInstanceComponent(FloorMesh);
 FloorMesh->SetBoxExtent(FVector(1000,1000,50)); FloorMesh->SetWorldLocation(FVector(0,0,-50));
 FloorMesh->SetCollisionProfileName(TEXT("BlockAll")); FloorMesh->RegisterComponent();
 if(!FloorMesh->IsPhysicsStateCreated()) return 18;
 auto HasPlacementOverlap=[&]() {
   // Query the body directly: a commandlet world has no physics frame to
   // publish newly registered/moved bodies into the scene's broadphase.
   return FloorMesh->OverlapComponent(OwnedPlacement->GetComponentLocation(),OwnedPlacement->GetComponentQuat(),
     FCollisionShape::MakeBox(OwnedPlacement->GetScaledBoxExtent()));
 };
 if(HasPlacementOverlap()) return 15;
 FloorMesh->SetWorldLocation(FVector(0,0,7)); // an obstacle intersecting the placement box
 if(!HasPlacementOverlap()) return 16;
 Floor->Destroy();
 UE_LOG(LogTemp,Display,TEXT("WIND_PLACEMENT_SUCCESS: references resolved, unit root scale, preview volume/base disabled, floor clear, obstacle detected."));
 auto Character=World->SpawnActor<ACharacter>(ACharacter::StaticClass(),FVector(5000,0,0),FRotator::ZeroRotator,SpawnParams);
 Character->GetCharacterMovement()->InitializeComponent();
 Character->GetCharacterMovement()->Activate(true);
 Character->GetCharacterMovement()->SetMovementMode(MOVE_Walking);
 auto PC=World->SpawnActor<APlayerController>(); PC->Possess(Character);
 if(!Character->IsLocallyControlled()) return 4;
 struct FOverlapParams { AActor* OtherActor; } OverlapParams={Character};
 UFunction* OverlapEvent=Pad->FindFunction(TEXT("ReceiveActorBeginOverlap"));
 check(OverlapEvent);
 Pad->ProcessEvent(OverlapEvent,&OverlapParams);
 if(!Character->GetCharacterMovement()->PendingLaunchVelocity.IsZero()) return 5;
 Pad->bEditorAvailable=true; Pad->OnAvailable_BlueprintImpl();
 auto OwnedTarget=FindObject<UBoxComponent>(Pad,TEXT("DismantleTarget"));
 if(PreviewVolume->GetCollisionEnabled()!=ECollisionEnabled::QueryOnly || OwnedBase->GetCollisionEnabled()!=ECollisionEnabled::NoCollision) return 17;
 if(!OwnedTarget || !OwnedBase->bHiddenInGame || OwnedTarget->GetCollisionEnabled()!=ECollisionEnabled::QueryOnly) return 24;
 if(Pad->bExistsArrowInSimulatingTransform || FindObject<UStaticMeshComponent>(Pad,TEXT("DirectionMarker"))) return 29;
 if(OwnedTarget->GetCollisionResponseToChannel(ECC_GameTraceChannel7)!=ECR_Block || OwnedTarget->GetCollisionResponseToChannel(ECC_Pawn)!=ECR_Ignore) return 25;
 FHitResult TargetHit;
 if(!OwnedTarget->LineTraceComponent(TargetHit,FVector(500,0,100),FVector(0,0,100),FCollisionQueryParams()) || TargetHit.GetActor()!=Pad) return 26;
 Pad->OnChangeVisualForDismantle(true);
 if(OwnedBase->bHiddenInGame) return 27;
 Pad->OnChangeVisualForDismantle(false);
 if(!OwnedBase->bHiddenInGame) return 28;
 UE_LOG(LogTemp,Display,TEXT("WIND_DISMANTLE_SUCCESS: %s invisible active meshes, ray hits owned target, target ignores players, selection visual toggles."),*Suffix);
 Pad->ProcessEvent(OverlapEvent,&OverlapParams);
 if(!Character->GetCharacterMovement()->PendingLaunchVelocity.IsZero()) return 6;
 auto OwnedFX=Pad->FindComponentByClass<UNiagaraComponent>();
 auto OwnedVolume=FindObject<UBoxComponent>(Pad,TEXT("WindVolume"));
 if(!OwnedFX || !OwnedVolume || OwnedFX->GetOwner()!=Pad || OwnedVolume->GetOwner()!=Pad) return 7;
 if(!FMath::IsNearlyEqual(OwnedFX->GetRelativeScale3D().Z,FXHeightScale)) return 30;
 Pad->bEditorAvailable=false; Pad->OnNotAvailable_BlueprintImpl();
 if(OwnedFX->IsActive() || OwnedVolume->GetCollisionEnabled()!=ECollisionEnabled::NoCollision || OwnedBase->GetCollisionEnabled()!=ECollisionEnabled::NoCollision || OwnedTarget->GetCollisionEnabled()!=ECollisionEnabled::NoCollision) return 8;
 Character->GetCharacterMovement()->PendingLaunchVelocity=FVector::ZeroVector;
 Pad->ProcessEvent(OverlapEvent,&OverlapParams);
 if(!Character->GetCharacterMovement()->PendingLaunchVelocity.IsZero()) return 9;
 Pad->Destroy();
 if(!Pad->IsActorBeingDestroyed()) return 10;
 GEngine->DestroyWorldContext(World); World->DestroyWorld(false);
 UE_LOG(LogTemp,Display,TEXT("WIND_TEST_SUCCESS: preview and walking entry never launch, owned FX/volume, inactive collision cleared, destruction accepted. Native game availability is mocked by editor stub."));
 UE_LOG(LogTemp,Display,TEXT("WIND_BUILD_SUCCESS: independent building Blueprint, owned components, no actor spawning or world scan."));
 UE_LOG(LogTemp,Display,TEXT("WIND_VARIANT_SUCCESS: %s radius=%g FX-height-scale=%g material=%s"),*Suffix,Radius,FXHeightScale,*Deck->GetName());
 return 0;
}

int32 UWindBuildCommandlet::Main(const FString& Params) {
 if(Params.Contains(TEXT("PreviewOnly"))) return RenderWindPreview();
 // Reference-only Niagara placeholder; never ship it or editor DLLs.
 UPackage* FXPackage=CreatePackage(TEXT("/Game/Pal/Effect/Common/JumpSpot/NS_JumpSpot"));
 auto Factory=NewObject<UFactory>(GetTransientPackage(),LoadObject<UClass>(nullptr,TEXT("/Script/NiagaraEditor.NiagaraSystemFactoryNew")));
 auto FX=Cast<UNiagaraSystem>(Factory->FactoryCreateNew(UNiagaraSystem::StaticClass(),FXPackage,TEXT("NS_JumpSpot"),RF_Public|RF_Standalone,nullptr,GWarn));
 if(!FX || !SaveAsset(FX)) return 1;
 FString JSON; TArray<TSharedPtr<FJsonValue>> Variants;
 const FString File=FPaths::ConvertRelativePathToFull(FPaths::ProjectDir()/TEXT("../wind_variants.json"));
 if(!FFileHelper::LoadFileToString(JSON,*File) || !FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(JSON),Variants) || Variants.Num()!=3) return 21;
 for(const auto& Value:Variants) {
   const auto Spec=Value->AsObject(); const FString Suffix=Spec->GetStringField(TEXT("Suffix"));
   auto Texture=WindTexture(TEXT("T_WindDeck")+Suffix,false);
   auto Icon=WindTexture(TEXT("T_WindIcon")+Suffix,true);
   if(!Texture || !Icon) return 22;
   const auto& RGB=Spec->GetArrayField(TEXT("Accent"));
   const FLinearColor Color=FLinearColor(FColor(RGB[0]->AsNumber(),RGB[1]->AsNumber(),RGB[2]->AsNumber()));
   auto Deck=WindDeckMaterial(Suffix,Texture);
   if(!Deck) return 23;
   const int32 Result=BuildWindVariant(FX,Suffix,Spec->GetNumberField(TEXT("RadiusCm")),Spec->GetNumberField(TEXT("FXHeightScale")),Deck);
   if(Result) { UE_LOG(LogTemp,Error,TEXT("WIND_VARIANT_FAILED: %s code=%d"),*Suffix,Result); return Result; }
 }
 UE_LOG(LogTemp,Display,TEXT("WIND_ALL_VARIANTS_SUCCESS: small/medium/large, textures and native UI icons."));
 return 0;
}

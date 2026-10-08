#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Engine/EngineTypes.h"
#include "PalBuildObject.generated.h"
// Editor-only declarations of existing game API. These DLLs are never shipped.
// Blueprint references resolve to the game's actual /Script/Pal classes.
UCLASS(Blueprintable)
class PAL_API APalMapObject : public AActor {
 GENERATED_BODY()
public:
 UPROPERTY(EditAnywhere,BlueprintReadWrite) bool bIgnoreBuildInstallConnection=false;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) bool bInDoorObject=false;
};
UCLASS(Blueprintable)
class PAL_API APalBuildObject : public APalMapObject {
 GENERATED_BODY()
public:
 UPROPERTY(EditAnywhere,BlueprintReadWrite) FName BuildObjectId;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) FComponentReference OverlapCheckCollisionRef;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) FComponentReference MainMeshRef;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) bool bNotConstructConnectorInGame=false;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) bool bPlayBuildCompleteFX=true;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) bool bExistsArrowInSimulatingTransform=false;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) FTransform ArrowInSimulatingRelativeTransform;
 // Unserialized editor test state; the game supplies its own IsAvailable function.
 bool bEditorAvailable=false;
 UFUNCTION(BlueprintCallable,BlueprintPure) bool IsAvailable() const { return bEditorAvailable; }
 UFUNCTION(BlueprintCallable,BlueprintImplementableEvent) void OnAvailable_BlueprintImpl();
 UFUNCTION(BlueprintCallable,BlueprintImplementableEvent) void OnNotAvailable_BlueprintImpl();
 UFUNCTION(BlueprintCallable,BlueprintImplementableEvent) void OnChangeVisualForDismantle(const bool bDismantle);
};

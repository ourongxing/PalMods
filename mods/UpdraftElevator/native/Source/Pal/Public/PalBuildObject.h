#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Engine/EngineTypes.h"
#include "Components/SceneComponent.h"
#include "PalBuildObject.generated.h"
// Editor-only declarations of existing game API. These DLLs are never shipped.
// Blueprint references resolve to the game's actual /Script/Pal classes.
UCLASS(Blueprintable)
class PAL_API APalLevelObjectActor : public AActor {
 GENERATED_BODY()
};
UCLASS(Blueprintable)
class PAL_API UPalActionBase : public UObject {
 GENERATED_BODY()
};
UCLASS(Blueprintable)
class PAL_API UPalAction_JumpFromJumpSpot : public UPalActionBase {
 GENERATED_BODY()
};
UCLASS(Blueprintable)
class PAL_API APalLevelGimmickJumpSpot : public APalLevelObjectActor {
 GENERATED_BODY()
public:
 APalLevelGimmickJumpSpot() { SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root"))); }
 UPROPERTY(EditAnywhere,BlueprintReadWrite) TSubclassOf<UPalAction_JumpFromJumpSpot> JumpActionClass;
 // Match the game's native defaults so true is serialized into each helper BP.
 UPROPERTY(EditAnywhere,BlueprintReadWrite) bool bPlayJumpPrepareMontage=false;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) float JumpFowardVelocity=0;
 UPROPERTY(EditAnywhere,BlueprintReadWrite) float JumpZVelocity=0;
};
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

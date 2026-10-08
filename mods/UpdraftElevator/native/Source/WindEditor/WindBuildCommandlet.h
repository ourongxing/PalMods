#pragma once
#include "CoreMinimal.h"
#include "Commandlets/Commandlet.h"
#include "WindBuildCommandlet.generated.h"
UCLASS()
class UWindBuildCommandlet : public UCommandlet {
 GENERATED_BODY()
public:
 UWindBuildCommandlet();
 virtual int32 Main(const FString& Params) override;
};

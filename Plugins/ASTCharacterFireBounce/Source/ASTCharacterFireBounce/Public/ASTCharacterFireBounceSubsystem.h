#pragma once
#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "ASTCharacterFireBounceSubsystem.generated.h"

class UPointLightComponent;
class USkinnedMeshComponent;

UCLASS()
class ASTCHARACTERFIREBOUNCE_API UASTCharacterFireBounceSubsystem : public UTickableWorldSubsystem
{
    GENERATED_BODY()
public:
    virtual void Tick(float DeltaTime) override;
    virtual TStatId GetStatId() const override;
    virtual void Deinitialize() override;
private:
    struct FReceiver
    {
        FVector Color = FVector::ZeroVector;
        FVector Direction = FVector::ForwardVector;
        FVector WrittenColor = FVector::ZeroVector;
        FVector WrittenDirection = FVector::ForwardVector;
        bool bWritten = false;
    };
    float ScanDebt = 1.f;
    float UpdateDebt = 0.f;
    TArray<TWeakObjectPtr<UPointLightComponent>> Sources;
    TMap<TWeakObjectPtr<USkinnedMeshComponent>, FReceiver> Receivers;
};

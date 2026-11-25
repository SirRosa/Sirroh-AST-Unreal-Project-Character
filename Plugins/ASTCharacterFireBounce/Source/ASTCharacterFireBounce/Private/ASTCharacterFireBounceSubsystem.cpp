#include "ASTCharacterFireBounceSubsystem.h"
#include "Camera/PlayerCameraManager.h"
#include "Components/PointLightComponent.h"
#include "Components/SkinnedMeshComponent.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "Materials/Material.h"
#include "Materials/MaterialInterface.h"
#include "UObject/UObjectIterator.h"

namespace
{
    const FName OwnedLightTag(TEXT("ASTFireOwnedLight"));
    constexpr int32 ColorIndex=24, DirectionIndex=28;
    constexpr float UpdateInterval=.05f, ScanInterval=.30f;
    constexpr float MaxEnergy=.46f;
    bool Supported(USkinnedMeshComponent* Mesh)
    {
        if(!IsValid(Mesh)||!Mesh->IsVisible()||!Mesh->GetSkinnedAsset())return false;
        for(int32 I=0;I<Mesh->GetNumMaterials();++I)
        {
            UMaterialInterface* MI=Mesh->GetMaterial(I);
            if(!MI)continue;
            UMaterial* Base=MI->GetMaterial();
            if(!Base)continue;
            const FString P=Base->GetPathName();
            if(P.StartsWith(TEXT("/Game/Characters/")) &&
                (P.Contains(TEXT("M_Grim_Ink."))||P.Contains(TEXT("M_GrimV7_Ink."))||
                 P.Contains(TEXT("M_GrimV10_Ink."))||P.Contains(TEXT("M_GrimGirl_Ink."))||
                 P.Contains(TEXT("M_SimpleMan_Ink."))))return true;
        }
        return false;
    }
    void Write(USkinnedMeshComponent* Mesh,const FVector& Color,const FVector& Direction)
    {
        Mesh->SetCustomPrimitiveDataFloat(ColorIndex,float(Color.X));
        Mesh->SetCustomPrimitiveDataFloat(ColorIndex+1,float(Color.Y));
        Mesh->SetCustomPrimitiveDataFloat(ColorIndex+2,float(Color.Z));
        Mesh->SetCustomPrimitiveDataFloat(DirectionIndex,float(Direction.X));
        Mesh->SetCustomPrimitiveDataFloat(DirectionIndex+1,float(Direction.Y));
        Mesh->SetCustomPrimitiveDataFloat(DirectionIndex+2,float(Direction.Z));
    }
}
TStatId UASTCharacterFireBounceSubsystem::GetStatId() const
{
    RETURN_QUICK_DECLARE_CYCLE_STAT(UASTCharacterFireBounceSubsystem,STATGROUP_Tickables);
}
void UASTCharacterFireBounceSubsystem::Deinitialize()
{
    for(auto& Pair:Receivers)
        if(auto* Mesh=Pair.Key.Get())Write(Mesh,FVector::ZeroVector,FVector::ForwardVector);
    Receivers.Empty();Sources.Empty();
    Super::Deinitialize();
}
void UASTCharacterFireBounceSubsystem::Tick(float DeltaTime)
{
    UWorld* World=GetWorld();
    if(!World||!World->IsGameWorld()||World->GetNetMode()==NM_DedicatedServer)return;
    ScanDebt+=DeltaTime;UpdateDebt+=DeltaTime;
    if(UpdateDebt<UpdateInterval)return;
    const float Dt=FMath::Min(UpdateDebt,.25f);UpdateDebt=0.f;
    if(ScanDebt>=ScanInterval)
    {
        ScanDebt=0.f;Sources.Reset();
        for(TObjectIterator<UPointLightComponent> It;It;++It)
            if(It->GetWorld()==World && It->IsRegistered() &&
                It->ComponentHasTag(OwnedLightTag))Sources.Add(*It);
    }
    APlayerController* PC=World->GetFirstPlayerController();
    if(!PC||!PC->IsLocalController()||!PC->PlayerCameraManager)return;
    const FVector Toward=-PC->PlayerCameraManager->GetCameraRotation().Vector();
    TSet<TWeakObjectPtr<USkinnedMeshComponent>> Seen;
    for(TActorIterator<APawn> It(World);It;++It)
    {
        APawn* Pawn=*It;
        if(!Pawn||!Pawn->IsPlayerControlled())continue;
        TArray<USkinnedMeshComponent*> Meshes;
        Pawn->GetComponents<USkinnedMeshComponent>(Meshes);
        for(auto* Mesh:Meshes)
        {
            if(!Supported(Mesh))continue;
            const TWeakObjectPtr<USkinnedMeshComponent> Key(Mesh);
            Seen.Add(Key);
            FVector Sum=FVector::ZeroVector, Weighted=FVector::ZeroVector;
            const FVector Target=Mesh->Bounds.Origin;
            for(const auto& Weak:Sources)
            {
                auto* Light=Weak.Get();
                if(!IsValid(Light)||!Light->IsVisible()||Light->Intensity<=.005f||Light->AttenuationRadius<=1.f)continue;
                const FVector Delta=Light->GetComponentLocation()-Target;
                const float Ratio=float(Delta.Size())/Light->AttenuationRadius;
                if(Ratio>=1.f)continue;
                const FVector Dir=Delta.GetSafeNormal();
                // Most correction when the physical source is behind the visible
                // face; front lights already illuminate it normally.
                const float Need=FMath::Clamp(.45f-.75f*float(FVector::DotProduct(Dir,Toward)),0.f,1.f);
                const float Weight=FMath::Min(1.65f,Light->Intensity)*Need*
                    FMath::Pow(FMath::Max(0.f,1.f-Ratio*Ratio),4.5f)*.34f;
                if(Weight<.003f)continue;
                FCollisionQueryParams Query(SCENE_QUERY_STAT(ASTCharacterBounce),false,Light->GetOwner());
                Query.AddIgnoredActor(Pawn);
                FCollisionObjectQueryParams Objects;
                Objects.AddObjectTypesToQuery(ECC_WorldStatic);
                Objects.AddObjectTypesToQuery(ECC_WorldDynamic);
                FHitResult Hit;
                if(World->LineTraceSingleByObjectType(Hit,Light->GetComponentLocation(),Target,Objects,Query))continue;
                const FLinearColor Tint=FLinearColor::MakeFromColorTemperature(
                    Light->bUseTemperature?Light->Temperature:2700.f);
                const FVector RGB(Tint.R,Tint.G,Tint.B);
                Sum+=RGB*Weight;
                Weighted+=(Toward*.85+FVector::VectorPlaneProject(Dir,Toward)*.65).GetSafeNormal()*Weight;
            }
            const double Peak=Sum.GetMax();
            if(Peak>MaxEnergy)Sum*=MaxEnergy/Peak;
            const FVector Direction=Weighted.IsNearlyZero()?Toward:Weighted.GetSafeNormal();
            FReceiver& State=Receivers.FindOrAdd(Key);
            const FVector NextColor=FMath::VInterpTo(State.Color,Sum,Dt,14.f);
            const FVector NextDir=FMath::VInterpTo(State.Direction,Direction,Dt,18.f).GetSafeNormal();
            if(!State.bWritten||!NextColor.Equals(State.Color,.0005)||!NextDir.Equals(State.Direction,.002))
            {
                Write(Mesh,NextColor,NextDir);
                State.bWritten=true;
            }
            State.Color=NextColor;State.Direction=NextDir;
        }
    }
    for(auto It=Receivers.CreateIterator();It;++It)
        if(!Seen.Contains(It.Key()))
        {
            if(auto* Mesh=It.Key().Get())Write(Mesh,FVector::ZeroVector,FVector::ForwardVector);
            It.RemoveCurrent();
        }
}

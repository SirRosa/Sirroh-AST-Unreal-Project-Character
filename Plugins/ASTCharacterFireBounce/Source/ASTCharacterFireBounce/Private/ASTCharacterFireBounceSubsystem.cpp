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
    constexpr float UpdateInterval=.033333f, ScanInterval=.30f;
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
        // One atomic primitive-data update: color and direction never reach
        // the render thread as six separate intermediate values.
        const TArray<float> Data{float(Color.X),float(Color.Y),float(Color.Z),0.f,
            float(Direction.X),float(Direction.Y),float(Direction.Z),0.f};
        Mesh->SetCustomPrimitiveDataFloatArray(ColorIndex,Data);
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
    if(!PC||!PC->IsLocalController()||!PC->PlayerCameraManager)
    {
        for(auto& Pair:Receivers)
            if(auto* Mesh=Pair.Key.Get())Write(Mesh,FVector::ZeroVector,FVector::ForwardVector);
        Receivers.Reset();return;
    }
    const FVector Toward=-PC->PlayerCameraManager->GetCameraRotation().Vector();
    TSet<TWeakObjectPtr<USkinnedMeshComponent>> Seen;
    for(TActorIterator<APawn> It(World);It;++It)
    {
        APawn* Pawn=*It;
        if(!Pawn||(!Pawn->IsPlayerControlled()&&!Pawn->GetPlayerState()))continue;
        TArray<USkinnedMeshComponent*> Meshes;
        Pawn->GetComponents<USkinnedMeshComponent>(Meshes);
        for(auto* Mesh:Meshes)
        {
            if(!Supported(Mesh))continue;
            const TWeakObjectPtr<USkinnedMeshComponent> Key(Mesh);
            Seen.Add(Key);
            FVector Sum=FVector::ZeroVector, Weighted=FVector::ZeroVector;
            // Actor center is stable while the final pose bridge refreshes bounds.
            const FVector Target=Pawn->GetActorLocation();
            const FVector Across=FVector::CrossProduct(FVector::UpVector,Toward).GetSafeNormal();
            for(const auto& Weak:Sources)
            {
                auto* Light=Weak.Get();
                if(!IsValid(Light)||!Light->IsVisible()||Light->Intensity<=0.f||Light->AttenuationRadius<=1.f)continue;
                const FVector Delta=Light->GetComponentLocation()-Target;
                const float Ratio=float(Delta.Size())/Light->AttenuationRadius;
                if(Ratio>=1.f)continue;
                const FVector Dir=Delta.GetSafeNormal();
                // Most correction when the physical source is behind the visible
                // face; front lights already illuminate it normally.
                const float Need=FMath::Clamp(.45f-.75f*float(FVector::DotProduct(Dir,Toward)),0.f,1.f);
                const float Weight=FMath::Min(1.65f,Light->Intensity)*Need*
                    FMath::Pow(FMath::Max(0.f,1.f-Ratio*Ratio),4.5f)*.34f;
                if(Weight<=0.f)continue;
                FCollisionQueryParams Query(SCENE_QUERY_STAT(ASTCharacterBounce),false,Light->GetOwner());
                Query.AddIgnoredActor(Pawn);
                FCollisionObjectQueryParams Objects;
                Objects.AddObjectTypesToQuery(ECC_WorldStatic);
                Objects.AddObjectTypesToQuery(ECC_WorldDynamic);
                // Average body coverage instead of a binary center ray. A
                // single edge crossing changes at most one of five samples.
                float Visible=0.f;
                const FVector Offsets[]={FVector::ZeroVector,FVector::UpVector*35.f,
                    -FVector::UpVector*35.f,Across*22.f,-Across*22.f};
                for(const FVector& Offset:Offsets)
                {
                    FHitResult Hit;
                    if(!World->LineTraceSingleByObjectType(Hit,Light->GetComponentLocation(),Target+Offset,Objects,Query))
                        Visible+=.2f;
                }
                const float Contribution=Weight*Visible;
                if(Contribution<=0.f)continue;
                const FLinearColor Tint=FLinearColor::MakeFromColorTemperature(
                    Light->bUseTemperature?Light->Temperature:2700.f);
                const FVector RGB(Tint.R,Tint.G,Tint.B);
                Sum+=RGB*Contribution;
                Weighted+=(Toward*.85+FVector::VectorPlaneProject(Dir,Toward)*.65).GetSafeNormal()*Contribution;
            }
            const double Peak=Sum.GetMax();
            if(Peak>MaxEnergy)Sum*=MaxEnergy/Peak;
            FReceiver& State=Receivers.FindOrAdd(Key);
            // Retain the last meaningful direction as energy tends to zero.
            const FVector Direction=Sum.GetMax()>.002 && !Weighted.IsNearlyZero()
                ?Weighted.GetSafeNormal():(State.bWritten?State.Direction:Toward);
            // Exponential smoothing is independent of frame rate, including
            // the moment a light crosses the radius or an occluder edge.
            const float ColorAlpha=1.f-FMath::Exp(-Dt*5.f);
            const float DirectionAlpha=1.f-FMath::Exp(-Dt*7.f);
            FVector NextColor=FMath::Lerp(State.Color,Sum,ColorAlpha);
            if(Sum.IsZero()&&NextColor.GetMax()<.00005)NextColor=FVector::ZeroVector;
            const FVector NextDir=FMath::Lerp(State.Direction,Direction,DirectionAlpha).GetSafeNormal();
            // Compare to the last submitted value, not the previous simulation
            // step, so tiny changes cannot accumulate invisibly at the edge.
            if(!State.bWritten||!NextColor.Equals(State.WrittenColor,.00005)||!NextDir.Equals(State.WrittenDirection,.001)||
                (NextColor.IsZero()&&!State.WrittenColor.IsZero()))
            {
                Write(Mesh,NextColor,NextDir);
                State.WrittenColor=NextColor;State.WrittenDirection=NextDir;
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

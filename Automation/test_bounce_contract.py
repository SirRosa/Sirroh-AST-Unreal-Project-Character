"""Reference math + source contract, not a PIE/shader-render test."""
from pathlib import Path
import math
root=Path(__file__).resolve().parents[1]
cpp=(root/"Plugins/ASTCharacterFireBounce/Source/ASTCharacterFireBounce/Private/ASTCharacterFireBounceSubsystem.cpp").read_text()
mat=(root/"Automation/apply_material_bounce.py").read_text()
for token in ("ASTFireOwnedLight","LineTraceSingleByObjectType","ECC_WorldStatic","ECC_WorldDynamic","ColorIndex=24, DirectionIndex=28","MaxEnergy=.46f","SetCustomPrimitiveDataFloat","Sum.IsNearlyZero()"):
    assert token in cpp,token
for token in ("ASTFireBounceRGB","ASTFireBounceDirection","floor(l*3.999)/3.","pow(saturate(Base.rgb),.72)","MP_EMISSIVE_COLOR","MP_BASE_COLOR"):
    assert token in mat,token
assert "NewObject<UPointLightComponent>" not in cpp
assert "SetWorldLocation" not in cpp
assert "delete_all_material_expressions" not in mat
def energy(intensity,ratio,dot,blocked=False):
    if blocked or ratio>=1:return 0.
    need=max(0.,min(1.,.45-.75*dot))
    return min(1.65,intensity)*need*max(0.,1-ratio*ratio)**4.5*.34
assert energy(1.,.1,-1)>energy(1.,.1,0)>energy(1.,.1,1)==0
assert energy(1.,.1,-1)>energy(1.,.5,-1)>energy(1.,.9,-1)>energy(1.,1.,-1)==0
assert energy(1.,.1,-1,True)==energy(0.,.1,-1)==0
assert min(.46,sum(energy(1.65,.1,-1) for _ in range(10)))==.46
assert len({math.floor(i/100*3.999)/3 for i in range(101)})==4
print("Character bounce reference: rear/front response, range, occlusion, zero, multi-source cap and four shade bands PASS")

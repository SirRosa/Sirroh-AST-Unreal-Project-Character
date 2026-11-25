"""Update the existing bounce node only. No base graph or texture changes."""
import unreal as u, os, json, traceback
E=u.MaterialEditingLibrary
L=u.EditorAssetLibrary
PATHS=["/Game/Characters/GrimModular/Materials/M_Grim_Ink","/Game/Characters/GrimModularV7/Materials/M_GrimV7_Ink","/Game/Characters/GrimModularV10/Materials/M_GrimV10_Ink","/Game/Characters/SimpleMan/Materials/M_SimpleMan_Ink","/Game/Characters/GrimGirl/Materials/M_GrimGirl_Ink"]
OLD="float3 n=normalize(Normal); float3 d=Direction.xyz*rsqrt(max(dot(Direction.xyz,Direction.xyz),1e-6)); float l=saturate(dot(n,d)); float band=floor(l*3.999)/3.; float shade=.13+.87*band; return pow(saturate(Base.rgb),.72)*min(max(Energy.rgb,0.),.46)*shade;"
NEW="""
float3 n=normalize(Normal);
float3 d=Direction.xyz*rsqrt(max(dot(Direction.xyz,Direction.xyz),1e-6));
// Approximate the angular lighting at the center of a 4-render-pixel cell
// using local screen derivatives. Do not pixelate albedo, silhouettes or UV.
float raw=dot(n,d);
float2 pixel=GetPixelPosition(Parameters);
float2 delta=clamp((floor(pixel/4.0)+0.5)*4.0-pixel,-2.0,2.0);
float l=saturate(raw+clamp(ddx(raw)*delta.x+ddy(raw)*delta.y,-0.25,0.25));
// Four bands with narrow transition zones to avoid temporal popping.
float band=(smoothstep(0.21,0.29,l)+smoothstep(0.46,0.54,l)+smoothstep(0.71,0.79,l))/3.0;
float shade=.13+.87*band;
return pow(saturate(Base.rgb),.72)*min(max(Energy.rgb,0.),.46)*shade;
"""
out={"status":"FAIL","materials":[],"errors":[]}
try:
    ready=[]
    for path in PATHS:
        m=L.load_asset(path)
        if not m:raise RuntimeError("Missing "+path)
        base=E.get_material_property_input_node(m,u.MaterialProperty.MP_BASE_COLOR)
        emissive=E.get_material_property_input_node(m,u.MaterialProperty.MP_EMISSIVE_COLOR)
        candidates=[n for n in u.ObjectIterator(u.MaterialExpressionCustom) if n.get_outer()==m and n.get_editor_property("code").strip()==OLD]
        if len(candidates)!=1 or not isinstance(emissive,u.MaterialExpressionAdd) or not isinstance(base,u.MaterialExpressionCustom):
            raise RuntimeError("Unexpected v1 graph "+path)
        ready.append((path,m,candidates[0],base,emissive))
    for path,m,n,base,emissive in ready:
        n.set_editor_property("code",NEW)
        E.recompile_material(m)
        if E.get_material_property_input_node(m,u.MaterialProperty.MP_BASE_COLOR)!=base or E.get_material_property_input_node(m,u.MaterialProperty.MP_EMISSIVE_COLOR)!=emissive:
            raise RuntimeError("Graph changed "+path)
        out["materials"].append(path)
    for path,m,*_ in ready:
        if not L.save_loaded_asset(m,only_if_is_dirty=False):raise RuntimeError("Save failed "+path)
    out["status"]="PASS"
except Exception:
    out["errors"].append(traceback.format_exc())
folder=os.path.join(u.Paths.convert_relative_path_to_full(u.Paths.project_saved_dir()),"ChatGPT","CharacterFireBounce")
os.makedirs(folder,exist_ok=True)
with open(os.path.join(folder,"material_pixel_update.json"),"w",encoding="utf-8") as f:json.dump(out,f,indent=2)
print("CHARACTER_BOUNCE_PIXEL "+json.dumps(out),flush=True)

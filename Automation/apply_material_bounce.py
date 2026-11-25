"""Append a reversible bounce term; never replace the existing base/normal graph."""
import unreal as u, os, json, traceback
E=u.MaterialEditingLibrary
L=u.EditorAssetLibrary
PATHS=["/Game/Characters/GrimModular/Materials/M_Grim_Ink","/Game/Characters/GrimModularV7/Materials/M_GrimV7_Ink","/Game/Characters/GrimModularV10/Materials/M_GrimV10_Ink","/Game/Characters/SimpleMan/Materials/M_SimpleMan_Ink","/Game/Characters/GrimGirl/Materials/M_GrimGirl_Ink"]
out={"status":"FAIL","materials":[],"errors":[]}
def require(v,msg):
    if not v:raise RuntimeError(msg)
def node(m,typ,x,y):
    n=E.create_material_expression(m,typ,x,y)
    require(n,"Cannot create "+str(typ))
    return n
def link(a,outpin,b,inpin):
    require(E.connect_material_expressions(a,outpin,b,inpin),"Cannot connect "+str(inpin))
def param(m,name,index,y):
    n=node(m,u.MaterialExpressionVectorParameter,-650,y)
    n.set_editor_property("parameter_name",u.Name(name))
    n.set_editor_property("default_value",u.LinearColor(0,0,0,0))
    n.set_editor_property("use_custom_primitive_data",True)
    n.set_editor_property("primitive_data_index",index)
    return n
def pin(name):
    p=u.CustomInput()
    p.set_editor_property("input_name",u.Name(name))
    return p
try:
    # Preflight every asset before mutating any. Fail closed on an unexpected graph.
    ready=[]
    for path in PATHS:
        m=L.load_asset(path)
        require(m and not m.get_editor_property("use_material_attributes"),"Unsupported material "+path)
        require(m.get_editor_property("blend_mode")==u.BlendMode.BLEND_OPAQUE,"Nonopaque material "+path)
        base=E.get_material_property_input_node(m,u.MaterialProperty.MP_BASE_COLOR)
        emissive=E.get_material_property_input_node(m,u.MaterialProperty.MP_EMISSIVE_COLOR)
        require(isinstance(base,u.MaterialExpressionCustom),"Unexpected base "+path)
        require(isinstance(emissive,u.MaterialExpressionConstant),"Unexpected emissive "+path)
        for n in u.ObjectIterator(u.MaterialExpression):
            if n.get_outer()!=m:continue
            if isinstance(n,(u.MaterialExpressionScalarParameter,u.MaterialExpressionVectorParameter)) and n.get_editor_property("use_custom_primitive_data"):
                i=n.get_editor_property("primitive_data_index")
                width=4 if isinstance(n,u.MaterialExpressionVectorParameter) else 1
                require(i+width<=24 or i>=32,"CPD overlap "+path)
        ready.append((path,m,base,emissive,E.get_material_property_input_node_output_name(m,u.MaterialProperty.MP_BASE_COLOR),E.get_material_property_input_node_output_name(m,u.MaterialProperty.MP_EMISSIVE_COLOR)))
    for path,m,base,old,base_pin,old_pin in ready:
        rgb=param(m,"ASTFireBounceRGB",24,780)
        direction=param(m,"ASTFireBounceDirection",28,960)
        normal=node(m,u.MaterialExpressionPixelNormalWS,-650,1150)
        custom=node(m,u.MaterialExpressionCustom,-270,780)
        custom.set_editor_property("description","AST Character Fire Bounce v1")
        custom.set_editor_property("output_type",u.CustomMaterialOutputType.CMOT_FLOAT3)
        custom.set_editor_property("inputs",[pin(x) for x in ("Base","Normal","Energy","Direction")])
        # Four discrete diffuse bands. Keep energy temporally smooth; only
        # the angular shade is quantized. Black ink stays black.
        custom.set_editor_property("code","float3 n=normalize(Normal); float3 d=Direction.xyz*rsqrt(max(dot(Direction.xyz,Direction.xyz),1e-6)); float l=saturate(dot(n,d)); float band=floor(l*3.999)/3.; float shade=.13+.87*band; return pow(saturate(Base.rgb),.72)*min(max(Energy.rgb,0.),.46)*shade;")
        link(base,base_pin,custom,"Base")
        link(normal,"",custom,"Normal")
        link(rgb,"",custom,"Energy")
        link(direction,"",custom,"Direction")
        add=node(m,u.MaterialExpressionAdd,110,780)
        link(old,old_pin,add,"A")
        link(custom,"",add,"B")
        require(E.connect_material_property(add,"",u.MaterialProperty.MP_EMISSIVE_COLOR),"Emissive connect failed")
        require(E.get_material_property_input_node(m,u.MaterialProperty.MP_BASE_COLOR)==base,"Base graph changed")
        E.recompile_material(m)
        require(E.get_material_property_input_node(m,u.MaterialProperty.MP_EMISSIVE_COLOR)==add,"New graph disconnected")
        out["materials"].append(path)
    for _,m,*rest in ready:
        require(L.save_loaded_asset(m,only_if_is_dirty=False),"Save failed "+m.get_path_name())
    out["status"]="PASS"
except Exception:
    out["errors"].append(traceback.format_exc())
folder=os.path.join(u.Paths.convert_relative_path_to_full(u.Paths.project_saved_dir()),"ChatGPT","CharacterFireBounce")
os.makedirs(folder,exist_ok=True)
with open(os.path.join(folder,"material_apply.json"),"w",encoding="utf-8") as f:json.dump(out,f,indent=2)
print("AST_CHARACTER_FIRE_BOUNCE "+json.dumps(out),flush=True)

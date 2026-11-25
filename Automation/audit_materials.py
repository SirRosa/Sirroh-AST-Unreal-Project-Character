import unreal as u, json, os, traceback
E=u.MaterialEditingLibrary
paths=["/Game/Characters/GrimModular/Materials/M_Grim_Ink","/Game/Characters/GrimModularV7/Materials/M_GrimV7_Ink","/Game/Characters/GrimModularV10/Materials/M_GrimV10_Ink","/Game/Characters/SimpleMan/Materials/M_SimpleMan_Ink","/Game/Characters/GrimGirl/Materials/M_GrimGirl_Ink"]
out={"materials":[],"errors":[]}
try:
    for path in paths:
        m=u.load_asset(path)
        if not m: raise RuntimeError("Missing "+path)
        row={"path":path,"blend":str(m.get_editor_property("blend_mode")),"attributes":m.get_editor_property("use_material_attributes"),"params":[],"inputs":{}}
        for p in (u.MaterialProperty.MP_BASE_COLOR,u.MaterialProperty.MP_EMISSIVE_COLOR,u.MaterialProperty.MP_NORMAL):
            n=E.get_material_property_input_node(m,p)
            row["inputs"][str(p)]={"class":n.get_class().get_name() if n else None,"name":n.get_name() if n else None,"output":E.get_material_property_input_node_output_name(m,p) if n else None}
        for method in ("get_scalar_parameter_names","get_vector_parameter_names"):
            row["params"].extend(str(x) for x in getattr(E,method)(m))
        for n in u.ObjectIterator(u.MaterialExpression):
            if n.get_outer() != m: continue
            if isinstance(n,(u.MaterialExpressionScalarParameter,u.MaterialExpressionVectorParameter)):
                if n.get_editor_property("use_custom_primitive_data"):
                    row.setdefault("cpd",[]).append([str(n.get_editor_property("parameter_name")),n.get_editor_property("primitive_data_index")])
        out["materials"].append(row)
    out["status"]="PASS"
except Exception:
    out["status"]="FAIL";out["errors"].append(traceback.format_exc())
folder=os.path.join(u.Paths.convert_relative_path_to_full(u.Paths.project_saved_dir()),"ChatGPT","CharacterFireBounce")
os.makedirs(folder,exist_ok=True)
with open(os.path.join(folder,"material_audit.json"),"w",encoding="utf-8") as f:json.dump(out,f,indent=2)
print("CHARACTER_MATERIAL_AUDIT "+json.dumps(out),flush=True)

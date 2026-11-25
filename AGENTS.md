# Sirroh AST — Character rendering

## Ownership
This repository owns character-specific rendering code, material integration scripts, tests and documentation. ASTFireRuntime remains owned by Sirroh-AST-Unreal-Project. Do not duplicate its flame, smoke, spark, fuel or physical lighting implementation here. The Unreal project is the integration target, not a second copy of the entire project.

## Initial task: stylized fire bounce lighting
Implement a bounded, camera-facing diffuse approximation in character materials while retaining physical torch lighting at the actual flame. Consume read-only fire samples (world position, linear color, intensity, radius). Prefer a small versioned interface and receiver-side visibility checks; support multiple nearby sources with capped total energy. Respect existing material parameters, charring, textures, normals, character equipment and animation. No extra PointLight is required for the target design. Character lighting must fade to zero without visible sources and remain stable when torches are carried, thrown or in ragdoll. Avoid changing global exposure or unrelated assets. Custom Primitive Data and material functions are candidates, subject to inspecting existing material contracts and slot usage first.

## Integration and verification
- Use a separate work branch and explicit revision pins for each repository.
- Before modifying materials, identify their actual parents, instances, existing emissive/charring paths and occupied parameter slots. Preserve originals and use reversible changes.
- Do not deploy the experimental point-light character fill alongside the material approximation. Verify actual installed baseline first.
- Keep physical fire changes in the fire repository; do not remove approved environmental lighting settings while changing character rendering.
- Build against the actual Unreal engine/project; run regression checks, then validate visually on POI_Light including occlusion, carried and thrown torches, several fires, and extinguishing.
- Guard installation against open editor, unexpected source changes and failed build/audit; retain backups. Batch remote device operations and prefer synced logs.
- Never publish third-party licensed project assets or source into this public repository without explicit authorization. Store original integration code and documentation only.
- Do not merge experimental branches before user approval.

Status: architecture decision only; no implementation or compilation yet.

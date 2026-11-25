#Requires -Version 5.1
param([Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')][string]$Revision,
 [string]$ProjectRoot='D:\0 Sirro\Unreal Projects\AST_V1_18',
 [string]$EngineRoot='D:\0 Sirro\UE 5.8.1\UE_5.8')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
function Assert-EditorClosed {
 if(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue){throw 'Editor is open; no live writes'}
}
function Check-Exit($name){if($LASTEXITCODE -ne 0){throw "$name failed $LASTEXITCODE"}}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$root=Join-Path $env:TEMP ('ASTBounceStability_'+$stamp)
$source=Join-Path $root 'Source'
$built=Join-Path $root 'Built'
$report=Join-Path $ProjectRoot 'Saved\ChatGPT\CharacterFireBounce'
$backup=Join-Path $report ('Backup_Stability_'+$stamp)
$rel='Plugins\ASTCharacterFireBounce'
$live=Join-Path $ProjectRoot $rel
$cpp="$rel\Source\ASTCharacterFireBounce\Private\ASTCharacterFireBounceSubsystem.cpp"
$header="$rel\Source\ASTCharacterFireBounce\Public\ASTCharacterFireBounceSubsystem.h"
$fire='Plugins/ASTFireRuntime/Source/ASTFireRuntime/Private/ASTFireReactiveComponent.cpp'
function Assert-Baseline {
 foreach($pair in @(@($cpp,'da17912ecc948dfbf5922421552568cab9717da8'),@($header,'baf88665d29d2752c2f2a76e26a1ddee02a63ebc'),@($fire,'fd10e349464778bab139bd4425dfe8980335fb07'))){
  $f=$pair[0]
  $sha=(& git -C $ProjectRoot hash-object ('--path='+$f.Replace('\','/')) (Join-Path $ProjectRoot $f)).Trim()
  Check-Exit 'Live hash'
  if($sha -ne $pair[1]){throw "Unexpected local revision $f $sha"}
 }
}
New-Item -ItemType Directory -Force $root,$report|Out-Null
Assert-Baseline
& git clone --quiet --depth 1 --branch work/fire-bounce-stability 'https://github.com/SirRosa/Sirroh-AST-Unreal-Project-Character.git' $source
Check-Exit 'Clone'
if((& git -C $source rev-parse HEAD).Trim() -ne $Revision){throw 'Revision mismatch'}
Write-Output "REVISION=$Revision"
& python (Join-Path $source 'Automation\test_bounce_contract.py')
Check-Exit 'Static tests'
$sourcePlugin=Join-Path $source $rel
$uat=Join-Path $EngineRoot 'Engine\Build\BatchFiles\RunUAT.bat'
$ue=Join-Path $EngineRoot 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
$log=Join-Path $report ('StabilityBuild_'+$stamp+'.log')
& $uat BuildPlugin ('-Plugin='+(Join-Path $sourcePlugin 'ASTCharacterFireBounce.uplugin')) ('-Package='+$built) '-TargetPlatforms=Win64' '-Rocket' '-NoXGE' '-NoUBA' *> $log
$code=$LASTEXITCODE
Write-Output "BUILD_EXIT=$code"
if($code -ne 0){Get-Content $log -Tail 60;throw 'Build failed'}
Assert-EditorClosed
Assert-Baseline
$assets=@(
 'Content\Characters\GrimModular\Materials\M_Grim_Ink.uasset',
 'Content\Characters\GrimModularV7\Materials\M_GrimV7_Ink.uasset',
 'Content\Characters\GrimModularV10\Materials\M_GrimV10_Ink.uasset',
 'Content\Characters\SimpleMan\Materials\M_SimpleMan_Ink.uasset',
 'Content\Characters\GrimGirl\Materials\M_GrimGirl_Ink.uasset'
)
$bin=Join-Path $built 'Binaries'
if(!(Test-Path (Join-Path $bin 'Win64\UnrealEditor-ASTCharacterFireBounce.dll'))){throw 'Missing runtime DLL'}
$restore=@($cpp,$header)+$assets
foreach($f in Get-ChildItem $bin -Recurse -File){$restore+=("$rel\Binaries\"+$f.FullName.Substring($bin.Length).TrimStart('\'))}
$restore=$restore|Select-Object -Unique
$had=@{}
foreach($f in $restore){
 $p=Join-Path $ProjectRoot $f
 $had[$f]=Test-Path $p
 if($had[$f]){
  $dst=Join-Path $backup $f
  New-Item -ItemType Directory -Force (Split-Path $dst -Parent)|Out-Null
  Copy-Item -LiteralPath $p -Destination $dst -Force
 }
}
Write-Output "BACKUP=$backup"
try {
 Assert-EditorClosed
 foreach($f in @($cpp,$header)){Copy-Item (Join-Path $source $f) (Join-Path $ProjectRoot $f) -Force}
 foreach($f in Get-ChildItem $bin -Recurse -File){
  $dst=Join-Path (Join-Path $live 'Binaries') $f.FullName.Substring($bin.Length).TrimStart('\')
  New-Item -ItemType Directory -Force (Split-Path $dst -Parent)|Out-Null
  Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
 }
 $result=Join-Path $report 'material_pixel_update.json'
 if(Test-Path $result){Remove-Item $result -Force}
 $script=Join-Path $source 'Automation\update_material_pixel.py'
 $project=Join-Path $ProjectRoot 'AST_V1_18.uproject'
 $shaderLog=Join-Path $report ('StabilityMaterial_'+$stamp+'.log')
 & $ue $project '-run=pythonscript' ('-script='+$script.Replace('\','/')) '-unattended' '-nop4' '-nosplash' '-AllowCommandletRendering' '-RenderOffscreen' '-d3d12' *> $shaderLog
 $exit=$LASTEXITCODE
 if(!(Test-Path $result)){Get-Content $shaderLog -Tail 60;throw "Material report missing $exit"}
 $data=Get-Content $result -Raw|ConvertFrom-Json
 Write-Output ('MATERIAL='+($data|ConvertTo-Json -Depth 10 -Compress))
 if($exit -ne 0 -or $data.status -ne 'PASS' -or (Select-String -Path $shaderLog -Pattern 'Failed to compile Material.*(Grim|SimpleMan)|LogShaderCompilers: Error' -Quiet)){throw 'Material update failed'}
 Write-Output 'BOUNCE_STABILITY_INSTALL_SUCCESS'
} catch {
 $why=$_.Exception.Message
 Assert-EditorClosed
 foreach($f in $restore){
  $p=Join-Path $ProjectRoot $f
  if($had[$f]){Copy-Item -LiteralPath (Join-Path $backup $f) -Destination $p -Force}
  elseif(Test-Path $p){Remove-Item -LiteralPath $p -Force}
 }
 Write-Output "ROLLBACK_COMPLETE=$why"
 throw
}

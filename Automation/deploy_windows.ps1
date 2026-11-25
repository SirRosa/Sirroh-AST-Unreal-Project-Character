#Requires -Version 5.1
param(
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')][string]$Revision,
 [string]$FireRevision='8583aa1514c8e81e357dd12a36b1e1be66b5d20e',
 [string]$ProjectRoot='D:\0 Sirro\Unreal Projects\AST_V1_18',
 [string]$EngineRoot='D:\0 Sirro\UE 5.8.1\UE_5.8',
 [string]$Dumpbin='D:\Sirro\Programy\VS\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\dumpbin.exe'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
function Assert-EditorClosed {
 if(Get-Process UnrealEditor,UnrealEditor-Cmd -ErrorAction SilentlyContinue){throw 'Editor is open; no live writes allowed'}
}
function Check-Exit([string]$label){if($LASTEXITCODE -ne 0){throw "$label failed: $LASTEXITCODE"}}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$root=Join-Path $env:TEMP ('ASTCharacterBounce_'+$stamp)
$report=Join-Path $ProjectRoot 'Saved\ChatGPT\CharacterFireBounce'
$backup=Join-Path $report ('Backup_'+$stamp)
$charSrc=Join-Path $root 'Character'
$fireSrc=Join-Path $root 'Fire'
$charBuilt=Join-Path $root 'CharacterBuilt'
$fireBuilt=Join-Path $root 'FireBuilt'
$fireRel='Plugins\ASTFireRuntime'
$charRel='Plugins\ASTCharacterFireBounce'
$cppRel="$fireRel\Source\ASTFireRuntime\Private\ASTFireReactiveComponent.cpp"
$baseline='b6a3d9cf8cdd8d6f63323d8436194b9060f5e15d'
$liveChar=Join-Path $ProjectRoot $charRel
$liveFire=Join-Path $ProjectRoot $fireRel
$project=Join-Path $ProjectRoot 'AST_V1_18.uproject'
$uat=Join-Path $EngineRoot 'Engine\Build\BatchFiles\RunUAT.bat'
$ue=Join-Path $EngineRoot 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
$assets=@(
 'Content\Characters\GrimModular\Materials\M_Grim_Ink.uasset',
 'Content\Characters\GrimModularV7\Materials\M_GrimV7_Ink.uasset',
 'Content\Characters\GrimModularV10\Materials\M_GrimV10_Ink.uasset',
 'Content\Characters\SimpleMan\Materials\M_SimpleMan_Ink.uasset',
 'Content\Characters\GrimGirl\Materials\M_GrimGirl_Ink.uasset'
)
function Assert-Baseline {
 $sha=(& git -C $ProjectRoot hash-object ('--path='+$cppRel.Replace('\','/')) (Join-Path $ProjectRoot $cppRel)).Trim()
 Check-Exit 'Live fire hash'
 if($sha -ne $baseline){throw "Unexpected installed fire version: $sha"}
 if(Test-Path $liveChar){throw 'Character plugin already exists; refusing overwrite'}
}
New-Item -ItemType Directory -Force -Path $root,$report|Out-Null
Assert-Baseline
& git clone --quiet --depth 1 --branch work/fire-bounce-material 'https://github.com/SirRosa/Sirroh-AST-Unreal-Project-Character.git' $charSrc
Check-Exit 'Character clone'
& git clone --quiet --depth 1 --branch work/fire-light-physical-bounce 'https://github.com/SirRosa/Sirroh-AST-Unreal-Project.git' $fireSrc
Check-Exit 'Fire clone'
if((& git -C $charSrc rev-parse HEAD).Trim() -ne $Revision){throw 'Character revision mismatch'}
if((& git -C $fireSrc rev-parse HEAD).Trim() -ne $FireRevision){throw 'Fire revision mismatch'}
Write-Output "REVISIONS=$Revision / $FireRevision"
$sourceFire=Join-Path $fireSrc $fireRel
foreach($f in Get-ChildItem (Join-Path $sourceFire 'Source') -File -Recurse){
 $rel=$fireRel+$f.FullName.Substring($sourceFire.Length)
 if($rel -eq $cppRel){continue}
 $live=Join-Path $ProjectRoot $rel
 if(!(Test-Path $live)){throw "Missing unrelated source $rel"}
 if((Get-Content $f.FullName -Raw).Replace("`r`n","`n").TrimEnd() -ne (Get-Content $live -Raw).Replace("`r`n","`n").TrimEnd()){throw "Unrelated source differs $rel"}
}
Push-Location $fireSrc
try {
 & python Automation/ASTFire/test_fire_v4.py
 Check-Exit 'Fire static test'
 & python Automation/ASTFire/test_stage7_mesh_motion.py
 Check-Exit 'Fire mesh regression'
} finally {Pop-Location}
function Build-One($plugin,$output,$label) {
 $log=Join-Path $report ($label+'_'+$stamp+'.log')
 & $uat BuildPlugin ('-Plugin='+$plugin) ('-Package='+$output) '-TargetPlatforms=Win64' '-Rocket' '-NoXGE' '-NoUBA' *> $log
 $code=$LASTEXITCODE
 Write-Output ($label+'_EXIT='+$code)
 if($code -ne 0){Get-Content $log -Tail 60;throw "$label failed"}
}
Build-One (Join-Path $charSrc "$charRel\ASTCharacterFireBounce.uplugin") $charBuilt 'CharacterBuild'
Build-One (Join-Path $fireSrc "$fireRel\ASTFireRuntime.uplugin") $fireBuilt 'FireBuild'
$runtime=Join-Path $fireBuilt 'Binaries\Win64\UnrealEditor-ASTFireRuntime.dll'
if(!(Test-Path $runtime) -or !(Test-Path $Dumpbin)){throw 'ABI inputs missing'}
$exports=[Collections.Generic.HashSet[string]]::new()
foreach($line in (& $Dumpbin /exports $runtime)){
 if($line -match '^\s*\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)'){[void]$exports.Add($Matches[1])}
}
$checked=0
foreach($dll in Get-ChildItem (Join-Path $ProjectRoot 'Binaries\Win64') -Filter 'UnrealEditor-*.dll' -File){
 foreach($line in (& $Dumpbin /imports:UnrealEditor-ASTFireRuntime.dll $dll.FullName 2>$null)){
  if($line -match '^\s*[0-9A-Fa-f]+\s+(\?\S+)'){
   $checked++
   if(!$exports.Contains($Matches[1])){throw "ABI missing $($Matches[1])"}
  }
 }
}
if($checked -eq 0){throw 'No ABI imports checked'}
Write-Output "ABI_CHECKED=$checked"
Assert-EditorClosed
Assert-Baseline
New-Item -ItemType Directory -Force $backup|Out-Null
$restore=@($cppRel,'AST_V1_18.uproject')+$assets
$bin=Join-Path $fireBuilt 'Binaries'
foreach($f in Get-ChildItem $bin -Recurse -File){$restore+=("$fireRel\Binaries\"+$f.FullName.Substring($bin.Length).TrimStart('\'))}
$restore=$restore|Select-Object -Unique
$had=@{}
foreach($rel in $restore){
 $live=Join-Path $ProjectRoot $rel
 $had[$rel]=Test-Path $live
 if($had[$rel]){
  $dst=Join-Path $backup $rel
  New-Item -ItemType Directory -Force (Split-Path $dst -Parent)|Out-Null
  Copy-Item -LiteralPath $live -Destination $dst -Force
 }
}
Write-Output "BACKUP=$backup"
function Run-Audit($script,$name,$result,$extra) {
 $path=Join-Path $report $result
 if(Test-Path $path){Remove-Item $path -Force}
 $log=Join-Path $report ($name+'_'+$stamp+'.log')
 & $ue $project '-run=pythonscript' ('-script='+$script.Replace('\','/')) '-unattended' '-nop4' '-nosplash' @extra *> $log
 $exit=$LASTEXITCODE
 if(!(Test-Path $path)){Get-Content $log -Tail 40;throw "$name produced no report ($exit)"}
 $data=Get-Content $path -Raw|ConvertFrom-Json
 Write-Output ($name+'='+($data|ConvertTo-Json -Depth 10 -Compress))
 if($exit -ne 0 -or $data.status -ne 'PASS'){throw "$name failed"}
 if(Select-String -Path $log -Pattern 'Failed to compile Material.*(Grim|SimpleMan)|LogShaderCompilers: Error' -Quiet){throw "$name shader errors"}
}
try {
 Assert-EditorClosed
 Copy-Item (Join-Path $fireSrc $cppRel) (Join-Path $ProjectRoot $cppRel) -Force
 foreach($f in Get-ChildItem $bin -Recurse -File){
  $dst=Join-Path (Join-Path $liveFire 'Binaries') $f.FullName.Substring($bin.Length).TrimStart('\')
  New-Item -ItemType Directory -Force (Split-Path $dst -Parent)|Out-Null
  Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
 }
 New-Item -ItemType Directory -Force $liveChar|Out-Null
 foreach($name in @('ASTCharacterFireBounce.uplugin','Source','Binaries','Intermediate')){
  $src=Join-Path $charBuilt $name
  if(Test-Path $src){Copy-Item -LiteralPath $src -Destination $liveChar -Recurse -Force}
 }
 if(!(Test-Path (Join-Path $liveChar 'Binaries\Win64\UnrealEditor-ASTCharacterFireBounce.dll'))){throw 'Character editor DLL missing'}
 $json=Get-Content $project -Raw|ConvertFrom-Json
 if(@($json.Plugins|Where-Object {$_.Name -eq 'ASTCharacterFireBounce'}).Count -ne 0){throw 'Unexpected prior plugin descriptor'}
 $json.Plugins=@($json.Plugins)+@([pscustomobject]@{Name='ASTCharacterFireBounce';Enabled=$true})
 [IO.File]::WriteAllText($project,($json|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
 $fireReport=Join-Path $ProjectRoot 'Saved\ChatGPT\NiagaraFire\FireV4\fire_light_result.json'
 if(Test-Path $fireReport){Copy-Item $fireReport (Join-Path $backup 'previous_fire_light_result.json');Remove-Item $fireReport}
 $fireLog=Join-Path $report ('FireAudit_'+$stamp+'.log')
 & $ue $project '-run=pythonscript' ('-script='+(Join-Path $fireSrc 'Automation\ASTFire\audit_fire_light.py').Replace('\','/')) '-unattended' '-nop4' '-nosplash' '-nullrhi' *> $fireLog
 if($LASTEXITCODE -ne 0 -or !(Test-Path $fireReport)){Get-Content $fireLog -Tail 50;throw 'Fire audit failed'}
 $data=Get-Content $fireReport -Raw|ConvertFrom-Json
 Write-Output ('FIRE_AUDIT='+($data|ConvertTo-Json -Depth 10 -Compress))
 if($data.status -ne 'PASS'){throw 'Fire regression failed'}
 Run-Audit (Join-Path $charSrc 'Automation\apply_material_bounce.py') 'MaterialApply' 'material_apply.json' @('-AllowCommandletRendering','-RenderOffscreen','-d3d12')
 Write-Output 'CHARACTER_BOUNCE_INSTALL_SUCCESS'
} catch {
 $why=$_.Exception.Message
 Assert-EditorClosed
 foreach($rel in $restore){
  $live=Join-Path $ProjectRoot $rel
  if($had[$rel]){Copy-Item -LiteralPath (Join-Path $backup $rel) -Destination $live -Force}
  elseif(Test-Path $live){Remove-Item -LiteralPath $live -Force}
 }
 if(Test-Path $liveChar){Remove-Item -LiteralPath $liveChar -Recurse -Force}
 Write-Output "ROLLBACK_COMPLETE=$why"
 throw
}

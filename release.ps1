#Requires -Version 5.1
<#
.SYNOPSIS
  Construit et publie une release Windows de GODS en une seule etape guardee.

.DESCRIPTION
  Derive TOUS les champs de version d'un seul argument -Version, exporte le .exe headless,
  zippe (exe + DLL OpenXR [+ README.txt]), commit/tag/push sur main, puis cree la release GitHub.
  A faire AVANT de lancer : mettre a jour build/RELEASE_NOTES.md (= corps de la release GitHub)
  et la section [Unreleased] -> [X.Y.Z] de CHANGELOG.md.

.EXAMPLE
  ./release.ps1 -Version 0.9.0 -DryRun   # stamp + export + zip, RIEN n'est pousse (verifie le zip d'abord)
  ./release.ps1 -Version 0.9.0           # release complete (commit, tag, push, gh release)
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$Root   = $PSScriptRoot
$Godot  = 'C:\Users\Olivier\Documents\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
$Preset = 'Windows Desktop'
$Tag    = "v$Version"
$Build  = Join-Path $Root 'build'
$OutExe = Join-Path $Build 'GODS.exe'
$Dll    = Join-Path $Build 'libgodotopenxrvendors.dll'
$RelDir = Join-Path $Build "GODS-Windows-$Tag"
$Zip    = Join-Path $Build "GODS-Windows-$Tag.zip"
$Notes  = Join-Path $Build 'RELEASE_NOTES.md'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }

# --- 0. Garde-fous ---
if (-not (Test-Path $Godot)) { throw "Godot introuvable : $Godot" }
if (-not (Test-Path $Notes)) { throw "Notes de release manquantes : $Notes (mets-les a jour d'abord)" }
if (git -C $Root status --porcelain) { throw "Arbre de travail non propre — committe ou stash d'abord." }
if ((git -C $Root rev-parse --abbrev-ref HEAD) -ne 'main') { throw "Pas sur la branche main." }
if (git -C $Root tag --list $Tag) { throw "Le tag $Tag existe deja." }

# --- 1. Estampille la version partout depuis un seul input (sans BOM) ---
Step "Version -> $Version (export_presets.cfg + project.godot)"
$ep = Join-Path $Root 'export_presets.cfg'
$t  = [System.IO.File]::ReadAllText($ep)
$t  = $t -replace 'product_version="[^"]*"', "product_version=`"$Version`""
$t  = $t -replace 'version/name="[^"]*"',    "version/name=`"$Version`""
$t  = [regex]::Replace($t, 'version/code=(\d+)', { param($m) 'version/code=' + ([int]$m.Groups[1].Value + 1) })
[System.IO.File]::WriteAllText($ep, $t)

$pg = Join-Path $Root 'project.godot'
$t  = [System.IO.File]::ReadAllText($pg)
if ($t -match 'config/version="') {
  $t = $t -replace 'config/version="[^"]*"', "config/version=`"$Version`""
} else {
  $t = $t -replace '(config/name="[^"]*")', "`$1`nconfig/version=`"$Version`""
}
[System.IO.File]::WriteAllText($pg, $t)

# --- 2. Export Windows headless ---
Step 'Export Windows (headless)'
& $Godot --headless --path $Root --export-release $Preset $OutExe
if ($LASTEXITCODE) { throw "Export Godot echoue (code $LASTEXITCODE)." }
if (-not (Test-Path $OutExe)) { throw 'Aucun exe produit.' }
if (-not (Test-Path $Dll))    { throw "DLL OpenXR manquante a cote de l'exe : $Dll" }

# --- 3. Dossier + zip (exe + dll [+ README.txt si build/README_TEMPLATE.txt existe]) ---
Step "Zip -> $Zip"
if (Test-Path $RelDir) { Remove-Item $RelDir -Recurse -Force }
New-Item -ItemType Directory -Path $RelDir | Out-Null
Copy-Item $OutExe $RelDir
Copy-Item $Dll $RelDir
$tpl = Join-Path $Build 'README_TEMPLATE.txt'
if (Test-Path $tpl) { Copy-Item $tpl (Join-Path $RelDir 'README.txt') }
if (Test-Path $Zip) { Remove-Item $Zip -Force }
Compress-Archive -Path (Join-Path $RelDir '*') -DestinationPath $Zip -CompressionLevel Optimal
Write-Host ("    Zip : {0:N1} Mo" -f ((Get-Item $Zip).Length / 1MB))

if ($DryRun) { Step "DRY RUN OK — rien n'est commite/tague/publie. Verifie : $Zip"; return }

# --- 4. Commit du bump de version, tag, push ---
Step 'Commit + tag + push'
git -C $Root add export_presets.cfg project.godot
git -C $Root commit -m "Release $Tag"
git -C $Root tag -a $Tag -m "GODS $Tag"
git -C $Root push origin main --follow-tags

# --- 5. Publication GitHub ---
Step 'gh release create'
gh release create $Tag $Zip --title "GODS $Tag" --notes-file $Notes
Step "Publie : https://github.com/Oli97430/GODS/releases/tag/$Tag"

# Build + déploiement de GODS sur Meta Quest (phase 5).
#
# Ce script N'écrit, NE stocke et N'affiche AUCUN mot de passe. Pour la signature
# release, Godot lit le keystore via des variables d'environnement (ci-dessous) que
# TOI seul renseignes dans ta session shell. Le keystore et ses mots de passe ne
# doivent jamais être versionnés.
#
# Prérequis (voir la checklist remise séparément) :
#   - Android SDK installé + adb sur le PATH (platform-tools)
#   - Build template Android installé (Projet > Installer le modèle de build Android)
#   - JDK 17 (déjà présent)
#   - export_presets.cfg avec le preset "Quest (Android)" (déjà créé)
#
# Pour un build RELEASE signé, définis d'abord (sans les committer) :
#   $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH     = "C:\chemin\vers\gods-release.keystore"
#   $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER     = "ton_alias"
#   $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = "********"
#
# Exemples :
#   .\tools\build_quest.ps1 -Mode debug -Install -Run
#   .\tools\build_quest.ps1 -Mode release -Install

param(
	[ValidateSet("debug", "release")] [string]$Mode = "debug",
	[string]$Godot = $env:GODOT_BIN,
	[string]$Preset = "Quest (Android)",
	[string]$Apk = "build/galaxyexplorer.apk",
	[string]$PackageName = "com.PLACEHOLDER.galaxyexplorer",
	[switch]$Install,
	[switch]$Run
)

# Chemin Godot par défaut (console = sortie lisible) si -Godot/GODOT_BIN absent.
if (-not $Godot) {
	$Godot = "C:\Users\Olivier\Documents\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$apkPath = Join-Path $projectRoot $Apk
New-Item -ItemType Directory -Force (Split-Path $apkPath) | Out-Null

# Garde-fou release : vérifie la PRÉSENCE des variables (sans afficher leur valeur).
if ($Mode -eq "release") {
	$missing = @()
	foreach ($v in "GODOT_ANDROID_KEYSTORE_RELEASE_PATH", "GODOT_ANDROID_KEYSTORE_RELEASE_USER", "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD") {
		if (-not [Environment]::GetEnvironmentVariable($v)) { $missing += $v }
	}
	if ($missing.Count -gt 0) {
		Write-Host "ERREUR : variables de keystore release manquantes : $($missing -join ', ')" -ForegroundColor Red
		Write-Host "Définis-les dans ta session (voir l'en-tête de ce script) puis relance." -ForegroundColor Yellow
		exit 1
	}
}

$exportFlag = if ($Mode -eq "release") { "--export-release" } else { "--export-debug" }
Write-Host "[build_quest] Export $Mode -> $apkPath"
& $Godot --headless --path $projectRoot $exportFlag $Preset $apkPath
if ($LASTEXITCODE -ne 0) { Write-Host "[build_quest] Export échoué (code $LASTEXITCODE)." -ForegroundColor Red; exit $LASTEXITCODE }

if ($Install) {
	Write-Host "[build_quest] adb install -r $apkPath"
	adb install -r $apkPath
}

if ($Run) {
	Write-Host "[build_quest] Lancement de $PackageName sur le casque"
	adb shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1
}

Write-Host "[build_quest] Terminé."

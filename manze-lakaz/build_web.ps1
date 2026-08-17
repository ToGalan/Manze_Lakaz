<#
.SYNOPSIS
    Exports Manze Lakaz for Web and packages it as an itch.io-ready zip.

.DESCRIPTION
    Runs the "Web" export preset (single-threaded Compatibility renderer,
    see export_presets.cfg), then zips the CONTENTS of the output folder
    so index.html sits at the root of the archive -- itch.io's HTML5
    embed requires index.html at the archive root, not inside a
    subfolder, or the game will fail to load after upload.

.PARAMETER GodotExe
    Path to the Godot editor executable (console build recommended so
    export errors are visible). Defaults to this machine's known install
    location; override with -GodotExe if yours differs.

.EXAMPLE
    ./build_web.ps1
    ./build_web.ps1 -GodotExe "C:\Godot\Godot_v4.7.1-stable_win64_console.exe"
#>
param(
    [string]$GodotExe = "C:\Users\brian\AppData\Local\Programs\Godot\Godot_v4.7.1-stable_win64_console.exe"
)

# Deliberately NOT $ErrorActionPreference = "Stop": Godot is a native exe
# that writes routine, harmless lines to stderr (e.g. the GDExtension web-
# library warning for the webrtc_native addon, which is expected -- Web
# builds use the browser's own WebRTC, not that native extension). Under
# "Stop", PowerShell 5.1 can promote those stderr lines to a terminating
# script error even though Godot's own exit code is 0. Exit code is
# checked explicitly below instead, which is the actual signal that matters.
$ProjectDir = $PSScriptRoot
$OutDir = Join-Path $ProjectDir "build\web"
$ZipPath = Join-Path $ProjectDir "build\manze-lakaz-web.zip"

if (-not (Test-Path $GodotExe)) {
    Write-Error "Godot executable not found at '$GodotExe'. Pass -GodotExe <path>."
    exit 1
}

Write-Host "Cleaning $OutDir ..."
if (Test-Path $OutDir) {
    Remove-Item -Recurse -Force $OutDir -ErrorAction Stop
}
New-Item -ItemType Directory -Force -Path $OutDir -ErrorAction Stop | Out-Null

Write-Host "Exporting Web preset ..."
& $GodotExe --headless --path $ProjectDir --export-release "Web" "build/web/index.html"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Godot export failed (exit code $LASTEXITCODE)."
    exit 1
}

if (-not (Test-Path (Join-Path $OutDir "index.html"))) {
    Write-Error "Export reported success but build/web/index.html is missing."
    exit 1
}

Write-Host "Packaging $ZipPath ..."
if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath -ErrorAction Stop
}
# Compress the CONTENTS of $OutDir (index.html, index.pck, index.wasm, ...)
# directly into the zip root -- Compress-Archive with a wildcard source
# does this; passing $OutDir itself as the source would nest everything
# one folder deeper, which is exactly the itch.io failure mode this
# script exists to avoid.
Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $ZipPath -CompressionLevel Optimal -ErrorAction Stop

$zipSize = (Get-Item $ZipPath).Length
$zipSizeMb = [math]::Round($zipSize / 1MB, 1)
Write-Host ""
Write-Host "Done: $ZipPath ($zipSizeMb MB)"
Write-Host "Upload this zip to itch.io. In the upload's file settings, check"
Write-Host "'This file will be played in the browser'. Leave 'SharedArrayBuffer"
Write-Host "support (COOP/COEP headers)' UNCHECKED -- this build is exported"
Write-Host "single-threaded and does not need or want those headers."

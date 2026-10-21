# Copies the "Three New Worlds" art pack into res://art/lishi_worlds/<world_id>/.
#   powershell -File tools/import_lishi_worlds.ps1 -Zip C:\path\LiShi_Mahjong_Three_New_Worlds_Assets_v1.zip
#
# Only what the game uses is copied: the world and gameplay backgrounds, the UI PNGs and the
# 256/512 prop PNGs. SVG originals, source_art and PREVIEWS stay out of the project (they would
# only grow the APK), and so does map_background: its painted route of round markers reads as
# level buttons behind the real level grid, so the map screen shows the world art instead.
# Files are copied unchanged. Run `godot --headless --path . --import` afterwards.
param(
    [Parameter(Mandatory = $true)][string]$Zip
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "art/lishi_worlds"
$worlds = @("jade_bamboo_valley", "sunset_lotus_palace", "frostlight_village")
$keep = @(
    @{ From = "backgrounds"; To = "backgrounds"; Pattern = '^(world|gameplay)_background_.*\.jpg$' },
    @{ From = "ui"; To = "ui"; Pattern = '\.png$' },
    @{ From = "props_png"; To = "props"; Pattern = '_(256|512)\.png$' }
)

$z = [System.IO.Compression.ZipFile]::OpenRead($Zip)
try {
    $n = 0
    foreach ($e in $z.Entries) {
        $parts = $e.FullName -split '/'
        if ($parts.Count -ne 4 -or $parts[0] -ne "worlds" -or $worlds -notcontains $parts[1]) { continue }
        foreach ($k in $keep) {
            if ($parts[2] -eq $k.From -and $parts[3] -match $k.Pattern) {
                $dir = Join-Path $dest (Join-Path $parts[1] $k.To)
                New-Item -ItemType Directory -Force $dir | Out-Null
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $dir $parts[3]), $true)
                $n++
            }
        }
    }
    Write-Output "copied $n files into $dest"
}
finally {
    $z.Dispose()
}

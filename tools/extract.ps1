# Extract your own Geometry Wars: Retro Evolved package (the Xbox Live Arcade LIVE container,
# 15.5 MB) into port/assets: default.xex, the three XACT wave banks, the .dat tables, the TGA
# sprites and the icons. Never committed. The package is only read.
#   pwsh -NoProfile -File tools/extract.ps1 -Package 'D:\path\to\584107ED\000D0000\<package>'
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Package)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$assets = Join-Path $root 'port\assets'
New-Item -ItemType Directory -Force $assets | Out-Null
python -I (Join-Path $PSScriptRoot 'stfs.py') $Package extract $assets
if ($LASTEXITCODE) { throw 'Extraction failed.' }
python -I (Join-Path $PSScriptRoot 'xexinfo.py') (Join-Path $assets 'default.xex')
"default.xex SHA-256 " + (Get-FileHash (Join-Path $assets 'default.xex') -Algorithm SHA256).Hash.ToLowerInvariant()

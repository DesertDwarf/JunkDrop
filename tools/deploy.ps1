# Copies the current JunkDrop files into your own WoW clients for testing. Run it through deploy.bat.
#
# For each AddOns folder listed in tools\deploy-targets.txt (one per line, # for comments; this
# file stays on your computer), it copies every file the release package would contain into that
# folder's JunkDrop folder. Files the package leaves out (see "ignore" in .pkgmeta, plus .git and
# the like) are skipped. Nothing is ever deleted: a file that is no longer part of the addon is
# listed as stale so you can remove it yourself.
#
#   deploy.bat          copy into every listed folder
#   deploy.bat -WhatIf  only show what would happen
#
# After deploying, type /reload in game. If files were added or removed, restart the game.

param([switch]$WhatIf)
$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$targetsFile = Join-Path $PSScriptRoot 'deploy-targets.txt'
if (-not (Test-Path $targetsFile)) { throw "List your AddOns folders in $targetsFile first, one per line." }
$targets = Get-Content $targetsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
if (-not $targets) { throw "$targetsFile has no folders in it." }

# Check every target before touching any: it must exist and be a folder named AddOns, so a typo
# can never write somewhere else.
foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Not a folder: $target" }
    if ((Split-Path $target -Leaf) -ne 'AddOns') { throw "Not an AddOns folder: $target" }
}

# What stays out of the addon: the packager's ignore list, plus things it never copies.
$skip = @('.git', '.pkgmeta', '.clairvoyance', 'library.md')
$inIgnore = $false
foreach ($line in Get-Content (Join-Path $repo '.pkgmeta')) {
    if ($line -match '^ignore:') { $inIgnore = $true; continue }
    if ($inIgnore -and $line -match '^\s*-\s*(.+?)\s*$') { $skip += $Matches[1]; continue }
    if ($line -match '^\S') { $inIgnore = $false }
}

$files = Get-ChildItem -LiteralPath $repo -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($repo.Length + 1).Replace('\', '/')
    $leftOut = $skip | Where-Object { $rel -eq $_ -or $rel.StartsWith("$_/") }
    if (-not $leftOut) { [pscustomobject]@{ Full = $_.FullName; Rel = $rel } }
}
if (-not $files) { throw 'Found no files to copy.' }

foreach ($target in $targets) {
    $addon = Join-Path $target 'JunkDrop'
    if ($WhatIf) {
        Write-Host "Would copy $($files.Count) files into $addon"
    } else {
        foreach ($file in $files) {
            $dest = Join-Path $addon $file.Rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
            Copy-Item -LiteralPath $file.Full -Destination $dest -Force
        }
        Write-Host "Copied $($files.Count) files into $addon"
    }

    if (Test-Path -LiteralPath $addon) {
        $shipped = $files | ForEach-Object { $_.Rel }
        $stale = Get-ChildItem -LiteralPath $addon -Recurse -File -Force | ForEach-Object {
            $_.FullName.Substring($addon.Length + 1).Replace('\', '/')
        } | Where-Object { $shipped -notcontains $_ }
        foreach ($name in $stale) { Write-Host "  Stale, not deleted: $name" }
    }
}
if (-not $WhatIf) { Write-Host 'In game: /reload (restart the game if files were added or removed).' }

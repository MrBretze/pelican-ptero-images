#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Fixes misplaced package names after apt cleanup commands
.DESCRIPTION
    Moves package names that appear AFTER the cleanup commands back into
    the apt install line where they belong
#>

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "🔍 Scanning for Dockerfiles with misplaced packages..." -ForegroundColor Cyan

$dockerfiles = Get-ChildItem -Path . -Recurse -Filter "Dockerfile" -File | Where-Object {
    $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\node_modules\\'
}

$fixedCount = 0

foreach ($dockerfile in $dockerfiles) {
    $content = Get-Content -Path $dockerfile.FullName -Raw
    $originalContent = $content

    # Pattern: Find cleanup line followed by package names
    # Example:
    # && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
    #                 package1 \
    #                 package2

    if ($content -match '(&& rm -rf /var/lib/apt/lists/\* /tmp/\* /var/tmp/\*)\r?\n((?:\s+\S+.*(?:\\\r?\n)?)+)') {
        $cleanupLine = $Matches[1]
        $packagesAfter = $Matches[2]

        # Extract package names
        $packageLines = $packagesAfter -split '\r?\n' | Where-Object { $_ -match '\S' }
        $packages = @()
        foreach ($line in $packageLines) {
            $line = $line.Trim()
            if ($line -match '^(\S+)') {
                $packages += $Matches[1] -replace '\\$', ''
            }
        }

        if ($packages.Count -gt 0) {
            Write-Host "  Found in: $($dockerfile.FullName)" -ForegroundColor Yellow
            Write-Host "    Packages: $($packages -join ', ')" -ForegroundColor Gray

            # Find the install line
            if ($content -match '(apt-get install -y --no-install-recommends)\s*\\\r?\n\s*\\\r?\n') {
                # Case 1: Install line has empty line marker
                $packageBlock = ($packages | ForEach-Object { "`t`t`t`t$_ \" }) -join "`n"

                $content = $content -replace `
                    [regex]::Escape('apt-get install -y --no-install-recommends \') + '\r?\n\s*\\\r?\n', `
                    "apt-get install -y --no-install-recommends \`n$packageBlock`n"

                # Remove the misplaced packages
                $content = $content -replace [regex]::Escape($cleanupLine) + '\r?\n' + [regex]::Escape($packagesAfter), $cleanupLine

            } elseif ($content -match 'apt-get install -y --no-install-recommends') {
                # Case 2: Install line exists but packages need to be added
                $packageBlock = ($packages | ForEach-Object { "`t`t`t`t$_ \" }) -join "`n"

                $content = $content -replace `
                    '(apt-get install -y --no-install-recommends\s+\\)', `
                    "apt-get install -y --no-install-recommends \`n$packageBlock`n"

                # Remove the misplaced packages
                $content = $content -replace [regex]::Escape($cleanupLine) + '\r?\n' + [regex]::Escape($packagesAfter), $cleanupLine
            }

            if ($content -ne $originalContent) {
                if ($DryRun) {
                    Write-Host "    [DRY RUN] Would fix" -ForegroundColor Yellow
                } else {
                    Set-Content -Path $dockerfile.FullName -Value $content -NoNewline
                    Write-Host "    ✅ Fixed" -ForegroundColor Green
                }
                $fixedCount++
            }
        }
    }
}

Write-Host "`n📊 Summary:" -ForegroundColor Cyan
Write-Host "  Fixed: $fixedCount Dockerfiles" -ForegroundColor Green

if ($DryRun) {
    Write-Host "`n💡 Run without -DryRun to apply changes" -ForegroundColor Yellow
} else {
    Write-Host "`n✅ All fixes applied!" -ForegroundColor Green
}

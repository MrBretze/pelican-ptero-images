#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Fixes DS017 security issue in all Dockerfiles by combining apt update/install statements
.DESCRIPTION
    This script finds all Dockerfiles and combines separate RUN apt update/upgrade/install
    statements into single RUN commands with proper cleanup
#>

param(
    [switch]$DryRun,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

Write-Host "🔍 Scanning for Dockerfiles with DS017 issues..." -ForegroundColor Cyan

# Find all Dockerfiles
$dockerfiles = Get-ChildItem -Path . -Recurse -Filter "Dockerfile" -File | Where-Object {
    $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\node_modules\\'
}

Write-Host "Found $($dockerfiles.Count) Dockerfiles" -ForegroundColor Green

$fixedCount = 0
$skippedCount = 0

foreach ($dockerfile in $dockerfiles) {
    if ($Verbose) {
        Write-Host "`nProcessing: $($dockerfile.FullName)" -ForegroundColor Yellow
    }

    $content = Get-Content -Path $dockerfile.FullName -Raw
    $originalContent = $content
    $changed = $false

    # Pattern 1: Separate RUN statements for update, upgrade, and install
    # Example:
    # RUN apt update -y
    # RUN apt -y upgrade
    # RUN apt install -y \
    #     package1 \
    #     package2

    $pattern1 = '(?ms)^RUN\s+apt(-get)?\s+update\s+.*?\n' +
                'RUN\s+apt(-get)?\s+.*?upgrade.*?\n' +
                'RUN\s+apt(-get)?\s+install\s+-y\s+([^\n]+(?:\\\n[^\n]+)*)'

    if ($content -match $pattern1) {
        if ($Verbose) {
            Write-Host "  Found Pattern 1 (update/upgrade/install separate)" -ForegroundColor Magenta
        }

        # Extract package list
        $installMatch = [regex]::Match($content, 'RUN\s+apt(-get)?\s+install\s+-y\s+((?:[^\n]+(?:\\\n)?)+)')
        if ($installMatch.Success) {
            $packages = $installMatch.Groups[2].Value

            # Build replacement
            $replacement = @"
RUN 		apt-get update \
			&& apt-get upgrade -y \
			&& apt-get install -y --no-install-recommends \
$packages
			&& apt-get clean \
			&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
"@

            $content = $content -replace $pattern1, $replacement
            $changed = $true
        }
    }

    # Pattern 2: update/upgrade combined, but install separate
    # Example:
    # RUN apt update -y \
    #     && apt -y upgrade
    #
    # RUN apt install -y \
    #     packages...

    $pattern2 = '(?ms)^RUN\s+apt(-get)?\s+update\s+.*?(?:&&|\\\n).*?upgrade.*?\n\n' +
                'RUN\s+apt(-get)?\s+install\s+-y\s+([^\n]+(?:\\\n[^\n]+)*)'

    if ($content -match $pattern2) {
        if ($Verbose) {
            Write-Host "  Found Pattern 2 (update+upgrade, install separate)" -ForegroundColor Magenta
        }

        $installMatch = [regex]::Match($content, 'RUN\s+apt(-get)?\s+install\s+-y\s+((?:[^\n]+(?:\\\n)?)+)')
        if ($installMatch.Success) {
            $packages = $installMatch.Groups[2].Value

            # Check if there's already a cleanup RUN after
            $hasCleanup = $content -match 'RUN\s+apt-get clean\s+\\'

            $replacement = @"
RUN 		apt-get update \
			&& apt-get upgrade -y \
			&& apt-get install -y --no-install-recommends \
$packages
			&& apt-get clean \
			&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
"@

            $content = $content -replace $pattern2, $replacement
            $changed = $true

            # Remove standalone cleanup if it exists
            if ($hasCleanup) {
                $content = $content -replace '\nRUN\s+apt-get clean\s+\\\n\s+&& rm -rf /var/lib/apt/lists/\*', ''
            }
        }
    }

    # Pattern 3: Separate apt update followed later by apt install (with intermediate RUN commands)
    # This is trickier - we look for apt update not followed by install in same RUN
    $lines = $content -split "`n"
    $inUpdateRun = $false
    $needsFix = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^RUN\s+apt(-get)?\s+update\s*$' -and $lines[$i+1] -notmatch 'apt(-get)?\s+install') {
            $needsFix = $true
            if ($Verbose) {
                Write-Host "  Found Pattern 3 (standalone apt update at line $($i+1))" -ForegroundColor Magenta
            }
            break
        }
    }

    # Save if changed
    if ($changed) {
        if ($DryRun) {
            Write-Host "  [DRY RUN] Would fix: $($dockerfile.FullName)" -ForegroundColor Yellow
        } else {
            Set-Content -Path $dockerfile.FullName -Value $content -NoNewline
            Write-Host "  ✅ Fixed: $($dockerfile.FullName)" -ForegroundColor Green
        }
        $fixedCount++
    } else {
        if ($Verbose) {
            Write-Host "  ⏭️  Skipped (no issues or already optimal): $($dockerfile.FullName)" -ForegroundColor Gray
        }
        $skippedCount++
    }
}

Write-Host "`n📊 Summary:" -ForegroundColor Cyan
Write-Host "  Fixed: $fixedCount" -ForegroundColor Green
Write-Host "  Skipped: $skippedCount" -ForegroundColor Gray
Write-Host "  Total: $($dockerfiles.Count)" -ForegroundColor White

if ($DryRun) {
    Write-Host "`n💡 Run without -DryRun to apply changes" -ForegroundColor Yellow
} else {
    Write-Host "`n✅ All fixes applied! Review changes with 'git diff'" -ForegroundColor Green
}

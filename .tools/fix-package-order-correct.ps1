# Fix Dockerfile package order
param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath
)

$ErrorActionPreference = 'Stop'

$content = Get-Content $FilePath -Raw -Encoding UTF8

# Pattern: Find RUN block with packages after cleanup
# Match: install line -> \  or \\n -> && apt-get clean -> packages
$pattern = '(?s)(apt-get install -y --no-install-recommends\s*\\\s*\n)(\\\s*\n)?(\s*&& apt-get clean\s*\\\s*\n\s*&& rm -rf[^\n]+\n)((?:\s+[^\s\n][^\n]*\\\s*\n?)+)'

if ($content -match $pattern) {
    $installLine = $matches[1]
    $cleanupLines = $matches[3]
    $packageBlock = $matches[4]

    # Extract packages - remove backslashes and empty lines
    $packages = @()
    foreach ($line in ($packageBlock -split '\r?\n')) {
        $pkg = $line.Trim() -replace '\s*\\s*$', ''
        if ($pkg -and $pkg -ne '\') {
            $packages += $pkg
        }
    }

    # Rebuild with correct order
    $newPackageBlock = ""
    for ($i = 0; $i -lt $packages.Count; $i++) {
        if ($i -lt ($packages.Count - 1)) {
            $newPackageBlock += "                $($packages[$i]) \`n"
        } else {
            # Last package gets \ before cleanup
            $newPackageBlock += "                $($packages[$i]) \`n"
        }
    }

    $newRun = $installLine + $newPackageBlock + $cleanupLines
    $content = $content -replace $pattern, $newRun

    Set-Content -Path $FilePath -Value $content -Encoding UTF8 -NoNewline
    return $true
}

return $false

# verify-bom.ps1 - BOM guard (deliberately ASCII-only source)
#
# WHY THIS FILE IS PURE ASCII:
#   PowerShell 5.1 reads a BOM-less Chinese .ps1 as GBK, mangling the text and
#   breaking the syntax -- so a BOM check written INSIDE a Chinese script can
#   never run in the exact situation it is meant to catch. This checker keeps
#   every byte ASCII (Chinese filenames are built from codepoints at runtime),
#   so it parses correctly with or without a BOM.
#
# USAGE:
#   powershell -ExecutionPolicy Bypass -File .\verify-bom.ps1          # check only
#   powershell -ExecutionPolicy Bypass -File .\verify-bom.ps1 -Fix     # check and repair
#
# EXIT: 0 = all good, 1 = problem found

[CmdletBinding()]
param(
    [string]$Root,
    [switch]$Fix
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = $PSScriptRoot }

# Build filenames from codepoints so this source stays ASCII.
# NOTE: use a name that is not a built-in alias (CP is Copy-Item!) -- without them PowerShell parses
#       `CP @(..) + '.ps1'` as passing '+.ps1' as an argument to CP.
function CodeStr { param([int[]]$Codes) -join ($Codes | ForEach-Object { [char]$_ }) }

$selfCheck = (CodeStr @(0x81EA, 0x68C0)) + '.ps1'                    # zi-jian.ps1  (self-check)
$manual    = (CodeStr @(0x4F7F, 0x7528, 0x8BF4, 0x660E)) + '.md'     # shi-yong-shuo-ming.md
$single    = (CodeStr @(0x5355, 0x6587, 0x4EF6, 0x901A, 0x7528, 0x7248, 0x63D0, 0x793A, 0x8BCD)) + '.md'

# Files that MUST carry a UTF-8 BOM (executed / parsed by PowerShell).
$mustHaveBom = @($selfCheck)

# Files that contain Chinese but do not require a BOM (informational listing).
$infoOnly = @('SKILL.md', 'README.md', $manual, $single,
              'assets\report-template.md', 'references\search-playbook.md',
              'references\source-verification.md', 'references\example-report.md')

$problems = 0
Write-Host ''
Write-Host '=== BOM guard ===' -ForegroundColor Cyan
Write-Host "Root: $Root"
Write-Host ''

foreach ($rel in $mustHaveBom) {
    $path = Join-Path $Root $rel
    if (-not (Test-Path $path)) {
        Write-Host "  [MISSING] $rel" -ForegroundColor Red
        $problems++
        continue
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if ($hasBom) {
        Write-Host "  [OK]      $rel  (BOM present, $($bytes.Length) bytes)" -ForegroundColor Green
    } else {
        Write-Host "  [NO BOM]  $rel  -- PowerShell 5.1 will parse Chinese as GBK and fail" -ForegroundColor Red
        $problems++
        if ($Fix) {
            $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($true))
            $after = [System.IO.File]::ReadAllBytes($path)
            if ($after[0] -eq 0xEF -and $after[1] -eq 0xBB -and $after[2] -eq 0xBF) {
                Write-Host '            repaired -> BOM restored' -ForegroundColor Yellow
                $problems--
            } else {
                Write-Host '            repair FAILED' -ForegroundColor Red
            }
        }
    }
}

Write-Host ''
Write-Host '--- informational (BOM not required) ---' -ForegroundColor DarkGray
foreach ($rel in $infoOnly) {
    $path = Join-Path $Root $rel
    if (-not (Test-Path $path)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $crlf = $false
    for ($i = 1; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10 -and $bytes[$i-1] -eq 13) { $crlf = $true; break } }
    Write-Host ("  {0,-46} BOM={1,-4} EOL={2}" -f $rel, $(if ($hasBom) { 'yes' } else { 'no' }), $(if ($crlf) { 'CRLF' } else { 'LF' })) -ForegroundColor DarkGray
}

Write-Host ''
# ---- line-ending consistency (repo convention is LF) ----
# Modelled on the BOM check above: report, then FAIL so the guard actually blocks.
# An editor or tool can silently flip line endings; a single CRLF file makes git
# diffs noisy and breaks byte-level comparisons.
$eolBad = @()
foreach ($rel in ($mustHaveBom + $infoOnly)) {
    $path = Join-Path $Root $rel
    if (-not (Test-Path $path)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $crlf = 0; $lf = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 10) { if ($i -gt 0 -and $bytes[$i-1] -eq 13) { $crlf++ } else { $lf++ } }
    }
    if ($crlf -gt 0) { $eolBad += "$rel (CRLF=$crlf, LF=$lf)" }
}
if ($eolBad.Count -gt 0) {
    if ($Fix) {
        $repaired = 0
        foreach ($rel in ($mustHaveBom + $infoOnly)) {
            $path = Join-Path $Root $rel
            if (-not (Test-Path $path)) { continue }
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $crlf = 0
            for ($i = 0; $i -lt $bytes.Length; $i++) {
                if ($bytes[$i] -eq 10 -and $i -gt 0 -and $bytes[$i-1] -eq 13) { $crlf++ }
            }
            if ($crlf -eq 0) { continue }
            # Preserve the BOM if present; normalise line endings to LF.
            $hadBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            if ($hadBom) { $text = $text.Substring(1) }
            $text = $text -replace "`r`n", "`n"
            [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($hadBom))
            Write-Host "  [FIX]     $rel  (CRLF -> LF)" -ForegroundColor Yellow
            $repaired++
        }
        if ($repaired -gt 0) { $eolBad = @(); Write-Host "  repaired $repaired file(s); re-run to confirm." -ForegroundColor Yellow }
    }
    if ($eolBad.Count -gt 0) {
        Write-Host ''
        Write-Host '  [EOL] line endings are not LF:' -ForegroundColor Red
        foreach ($x in $eolBad) { Write-Host "        $x" -ForegroundColor Red }
        $problems += $eolBad.Count
    }
}

if ($problems -gt 0) {
    Write-Host "RESULT: $problems problem(s). Re-run with -Fix to repair." -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: all required files carry a UTF-8 BOM.' -ForegroundColor Green
exit 0

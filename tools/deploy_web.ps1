# VoiceZoo web deploy: validate -> export -> publish to the gh-pages branch.
#
# Usage:  .\tools\deploy_web.ps1        (from anywhere; the script locates the repo root)
#
# Override the Godot binary with the GODOT_BIN environment variable, the same
# way run_checks.ps1 does.
#
# The site is published as a SINGLE orphan commit that is force-pushed. index.wasm
# is ~36 MB; a normal accumulating history would add that much to the repo on every
# deploy. Re-rooting the branch each time leaves the previous blobs unreachable, so
# GitHub can garbage-collect them.

[CmdletBinding()]
param(
    [string]$Godot  = $env:GODOT_BIN,
    [string]$Remote = 'origin',
    [string]$Branch = 'gh-pages'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Godot) { $Godot = 'C:\Users\fbrmp\Desktop\GodotExample\assets\Godot\Godot_v4.6-stable_win64_console.exe' }

$RepoRoot = Split-Path -Parent $PSScriptRoot
$WebDir   = Join-Path $RepoRoot 'export\web'
$Stage    = Join-Path ([System.IO.Path]::GetTempPath()) 'voicezoo-gh-pages'

function Fail([string]$Message) {
    Write-Host ''
    Write-Host "DEPLOY ABORTED: $Message" -ForegroundColor Red
    exit 1
}

# Native commands do not throw on failure, so every git/godot call is judged by
# its exit code. The preference is dropped to 'Continue' for the duration: under
# 'Stop', Windows PowerShell promotes anything a native command writes to stderr
# into a terminating error, and both Godot and run_checks.ps1 emit warnings there
# on a perfectly good run.
function Invoke-Checked([string]$What, [scriptblock]$Command) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Command } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0) { Fail "$What (exit code $LASTEXITCODE)" }
}

# For cleanup calls that are *expected* to fail on a clean checkout. Windows
# PowerShell turns a native command's stderr into a terminating error while
# $ErrorActionPreference is 'Stop', so failure has to be muted deliberately.
function Invoke-Tolerant([scriptblock]$Command) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Command 2>&1 | Out-Null } catch { }
    finally {
        $ErrorActionPreference = $previous
        $global:LASTEXITCODE = 0
    }
}

Push-Location $RepoRoot
try {
    if (-not (Test-Path $Godot)) { Fail "Godot binary not found at '$Godot'. Set GODOT_BIN." }

    # --- 1/5 Validation gate -------------------------------------------------
    # A red build must never reach the guests' phones.
    Write-Host '=== 1/5 Running run_checks.ps1 ===' -ForegroundColor Cyan
    Invoke-Checked 'run_checks.ps1 failed - not deploying a red build.' {
        & (Join-Path $RepoRoot 'run_checks.ps1')
    }

    # --- 2/5 Export ----------------------------------------------------------
    Write-Host ''
    Write-Host '=== 2/5 Exporting the Web preset (headless) ===' -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $WebDir | Out-Null
    $indexHtml = Join-Path $WebDir 'index.html'
    $indexWasm = Join-Path $WebDir 'index.wasm'
    $exportStart = Get-Date

    Invoke-Checked 'Godot export failed' {
        & $Godot --headless --export-release 'Web' $indexHtml
    }

    # Godot has been known to exit 0 after writing nothing, so confirm the two
    # files that actually matter exist AND were rewritten by this run.
    foreach ($f in @($indexHtml, $indexWasm)) {
        if (-not (Test-Path $f)) { Fail "Godot exited 0 but '$f' was not produced." }
        if ((Get-Item $f).LastWriteTime -lt $exportStart) {
            Fail "Godot exited 0 but '$f' is stale (not rewritten by this export)."
        }
    }
    $wasmMB = [math]::Round((Get-Item $indexWasm).Length / 1MB, 1)
    Write-Host "Export OK - index.wasm is $wasmMB MB" -ForegroundColor Green

    # --- 3/5 Static site extras ---------------------------------------------
    Write-Host ''
    Write-Host '=== 3/5 Staging .nojekyll and tools/web extras ===' -ForegroundColor Cyan

    # GitHub Pages runs Jekyll by default, which silently drops paths beginning
    # with an underscore. .nojekyll serves the directory verbatim instead.
    New-Item -ItemType File -Force -Path (Join-Path $WebDir '.nojekyll') | Out-Null

    # export/ is gitignored, so hand-written companion pages live in tools/web/
    # and are copied in on every deploy. mic_test.html is the differential
    # diagnostic for the iPhone test and must ship with the site.
    $extras = Join-Path $RepoRoot 'tools\web'
    if (Test-Path $extras) {
        Get-ChildItem -Force -File -Path $extras | ForEach-Object {
            Copy-Item $_.FullName -Destination $WebDir -Force
            Write-Host "  + $($_.Name)"
        }
    }
    if (-not (Test-Path (Join-Path $WebDir 'mic_test.html'))) {
        Fail 'mic_test.html is missing from export/web - it is required for the device test.'
    }

    # The site is served from https://<user>.github.io/VoiceZoo/, not a domain
    # root, so any root-absolute asset reference would 404. Catch it here rather
    # than discovering it on the phone; the fix belongs in export_presets.cfg,
    # not in a hand-edit of generated output.
    $absolute = Select-String -Path $indexHtml -Pattern '(?:src|href)\s*=\s*"(?:/|https?://)' -AllMatches
    if ($absolute) {
        $absolute | ForEach-Object { Write-Host "  $($_.Line.Trim())" -ForegroundColor Red }
        Fail 'index.html contains absolute asset paths; fix the Web export preset, not the generated file.'
    }
    Write-Host 'Asset paths are relative - OK' -ForegroundColor Green

    # --- 4/5 Publish ---------------------------------------------------------
    Write-Host ''
    Write-Host "=== 4/5 Publishing to '$Branch' as a single orphan commit ===" -ForegroundColor Cyan

    # Clear any worktree/branch left behind by an interrupted run. These are
    # expected to fail on a clean checkout, so their exit codes are ignored.
    if (Test-Path $Stage) { Invoke-Tolerant { git worktree remove --force $Stage } }
    Invoke-Tolerant { git worktree prune }
    Invoke-Tolerant { git branch -D $Branch }
    if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }

    # --orphan gives an unborn branch with no ancestry, so the commit below is
    # the branch's only commit.
    Invoke-Checked 'git worktree add failed' {
        git worktree add --quiet --orphan -b $Branch $Stage
    }

    try {
        Get-ChildItem -Force -Path $WebDir | Copy-Item -Destination $Stage -Recurse -Force

        Invoke-Checked 'git add failed' { git -C $Stage add -A }
        Invoke-Checked 'git commit failed' {
            git -C $Stage commit -q -m "Deploy web build ($wasmMB MB wasm)"
        }
        Invoke-Checked "git push to $Remote/$Branch failed" {
            git -C $Stage push --force --quiet $Remote "HEAD:refs/heads/$Branch"
        }
    }
    finally {
        # Always detach the worktree, even if the push failed, so the next run
        # starts clean.
        Invoke-Tolerant { git worktree remove --force $Stage }
        Invoke-Tolerant { git worktree prune }
    }

    # --- 5/5 Report ----------------------------------------------------------
    $originUrl = (git remote get-url $Remote).Trim()
    if ($originUrl -match '[:/]([^/]+)/([^/]+?)(?:\.git)?$') {
        $owner = $Matches[1]; $repo = $Matches[2]
        $siteUrl = "https://$owner.github.io/$repo/"
    } else {
        $siteUrl = '(could not derive the URL from the origin remote)'
    }

    Write-Host ''
    Write-Host '=== 5/5 Deployed ===' -ForegroundColor Green
    Write-Host "  $siteUrl" -ForegroundColor Green
    Write-Host "  ${siteUrl}mic_test.html" -ForegroundColor Green
    Write-Host ''
    Write-Host 'If this is the first deploy, enable it once under' -ForegroundColor Yellow
    Write-Host "  Settings -> Pages -> Deploy from a branch -> $Branch -> / (root)" -ForegroundColor Yellow
    Write-Host 'Free GitHub Pages requires the repository to be public.' -ForegroundColor Yellow
    exit 0
}
finally {
    Pop-Location
}

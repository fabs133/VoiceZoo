# VoiceZoo validation loop: unit tests + headless boot smoke test.
# Usage: .\run_checks.ps1   (from the project root)
# Override the Godot binary with the GODOT_BIN environment variable.

$godot = $env:GODOT_BIN
if (-not $godot) { $godot = 'C:\Users\fbrmp\Desktop\GodotExample\assets\Godot\Godot_v4.6-stable_win64_console.exe' }

Write-Host '=== 0/3 Import (registers new class_name scripts, refreshes caches) ==='
& $godot --headless --import 2>&1 | Out-Null

Write-Host '=== 1/3 Unit tests (core + presentation logic) ==='
& $godot --headless --script tests/test_runner.gd
if ($LASTEXITCODE -ne 0) {
    Write-Host 'UNIT TESTS FAILED' -ForegroundColor Red
    exit 1
}

Write-Host '=== 2/3 Boot smoke test (catches presentation/ parse errors) ==='
$errors = & $godot --headless --quit-after 10 --verbose 2>&1 |
    Select-String -Pattern 'SCRIPT ERROR|ERROR: Failed|Fatal'
if ($errors) {
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host 'BOOT SMOKE TEST FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
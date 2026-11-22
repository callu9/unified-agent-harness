# Full local verification (replaces GitHub Actions CI): doctor, Pester, Python unit tests.
# No StrictMode/ErrorActionPreference here: they would leak into the Pester test scopes.
Set-Location (Split-Path -Parent $PSScriptRoot)

& pwsh -NoLogo -NoProfile -File ./scripts/doctor.ps1 -Mode Core -Path . -Strict
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# -ErrorAction Stop: a missing Pester must fail the check, not silently skip the tests.
Import-Module Pester -MinimumVersion 5.7.1 -Force -ErrorAction Stop
Invoke-Pester -Path ./tests -CI -ErrorAction Stop
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# macOS /usr/bin/python3 is the compatibility target; elsewhere fall back to python3 on PATH.
$python = if (Test-Path /usr/bin/python3) { '/usr/bin/python3' } else { 'python3' }
Get-Command $python -ErrorAction Stop | Out-Null
& $python -m unittest discover -s tests/python
exit $LASTEXITCODE

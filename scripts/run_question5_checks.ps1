$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Write-Host 'Question 5: isolated backend HTTP contract / concurrency regression tests'
Push-Location "$root\backend"
try { & "$root\backend\.venv\Scripts\python.exe" -m pytest -q tests/test_question5_contract.py; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'Question 5: Flutter repository <-> API contract tests (mock HTTP; no SQL writes)'
Push-Location "$root\frontend"
try { & (Get-Command flutter).Source test test/question5_api_contract_test.dart; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
finally { Pop-Location }
Write-Host 'SQL Server MandaiDB concurrency is opt-in: scripts/run_q5_sqlserver_concurrency.py'

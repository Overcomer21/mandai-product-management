$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
python .\scripts\run_tests.py @args
exit $LASTEXITCODE

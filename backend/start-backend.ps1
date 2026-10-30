Set-Location $PSScriptRoot

$python = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $python)) {
    throw "Python virtual environment not found."
}

& $python -c "import stripe; import uvicorn"
if ($LASTEXITCODE -ne 0) {
    throw "Backend dependencies missing. Run pip install -r requirements.txt"
}

& $python -m uvicorn app.main:app --host 127.0.0.1 --port 8000

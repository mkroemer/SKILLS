$ErrorActionPreference = "Stop"

if ($env:PYTHON) {
    $Python = $env:PYTHON
} elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    $Python = "python3"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $Python = "python"
} else {
    throw "Python 3 was not found. Install Python 3.9+ or set the PYTHON environment variable."
}

& $Python (Join-Path $PSScriptRoot "office-vba.py") @args
exit $LASTEXITCODE

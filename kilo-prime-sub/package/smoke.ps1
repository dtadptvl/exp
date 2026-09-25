param([switch]$Keep)
$ErrorActionPreference = 'Stop'

foreach ($name in @('kilo', 'git', 'python')) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "$name is required for the live smoke test." }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("kilo-prime-sub-smoke-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    @'
def add(a, b):
    return a - b
'@ | Set-Content -LiteralPath (Join-Path $root 'calc.py') -Encoding UTF8

    @'
import unittest
from calc import add

class CalcTests(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(2, 3), 5)

if __name__ == "__main__":
    unittest.main()
'@ | Set-Content -LiteralPath (Join-Path $root 'test_calc.py') -Encoding UTF8

    Push-Location $root
    try {
        & git init -b smoke | Out-Null
        & git config user.email 'smoke@example.invalid'
        & git config user.name 'Prime Sub Smoke'
        & git add .
        & git commit -m 'smoke baseline' | Out-Null

        & kilo run --auto --agent prime 'Fix calc.add so the existing unit test passes. Preserve the public add(a, b) API. Inspect, implement, verify, and finish only with evidence.'
        if ($LASTEXITCODE -ne 0) { throw "kilo smoke run failed with exit code $LASTEXITCODE" }

        & python -m unittest -q
        if ($LASTEXITCODE -ne 0) { throw 'Smoke validator failed.' }

        Write-Host "PASS: live Prime -> Sub coding smoke succeeded in $root" -ForegroundColor Green
    } finally {
        Pop-Location
    }
} finally {
    if ($Keep) {
        Write-Host "Kept smoke repository: $root"
    } elseif (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

$ErrorActionPreference = 'Stop'
$env:LC_ALL = 'C'
$rscript = 'C:\Program Files\R\R-4.6.0\bin\Rscript.exe'
if (-not (Test-Path -LiteralPath $rscript)) {
    throw "Rscript not found at $rscript"
}
& $rscript --vanilla @args
exit $LASTEXITCODE

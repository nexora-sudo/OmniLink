param([ValidateSet('windows','android')][string]$Target = 'windows')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao resolver dependências.' }
    & flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Análise falhou.' }
    & flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Testes falharam.' }
    if ($Target -eq 'windows') {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Build Windows falhou.' }
        $artifact = 'build\windows\x64\runner\Release\omnilink.exe'
    } else {
        & flutter build apk --debug
        if ($LASTEXITCODE -ne 0) { throw 'Build Android falhou.' }
        $artifact = 'build\app\outputs\flutter-apk\app-debug.apk'
    }
    if (-not (Test-Path -LiteralPath $artifact)) { throw 'Artefato não encontrado.' }
    Get-Item -LiteralPath $artifact | Select-Object FullName,Length
    Get-FileHash -LiteralPath $artifact -Algorithm SHA256
} finally { Pop-Location }

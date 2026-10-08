param([string]$ApiUrl = '')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $project 'android/key.properties'))) {
    throw 'Release signing is missing. Restore android/key.properties and its keystore, or initialize a key with scripts/Initialize-AndroidSigning.ps1 for a new app.'
}
$buildId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$symbols = Join-Path $project "artifacts/android-symbols/$buildId"
New-Item -ItemType Directory -Path $symbols -Force | Out-Null
$buildArgs = @('build', 'apk', '--release', '--split-per-abi', '--obfuscate', "--split-debug-info=$symbols")
if ($ApiUrl) { $buildArgs += "--dart-define=API_URL=$ApiUrl" }
Push-Location $project
try {
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Secure APK build failed ($LASTEXITCODE)." }
    $mapping = Join-Path $project 'build/app/outputs/mapping/release/mapping.txt'
    if (-not (Test-Path -LiteralPath $mapping)) { throw 'Android obfuscation mapping was not generated.' }
    Copy-Item -LiteralPath $mapping -Destination (Join-Path $symbols 'android-mapping.txt')
    @('armeabi-v7a', 'arm64-v8a', 'x86_64') |
        ForEach-Object { Join-Path $project "build/app/outputs/flutter-apk/app-$_-release.apk" } |
        Get-FileHash -Algorithm SHA256 | Select-Object Hash, Path |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $symbols 'apk-hashes.json')
    Write-Host "Secure release APKs: $(Join-Path $project 'build/app/outputs/flutter-apk')"
    Write-Host "Private crash symbols: $symbols"
} finally { Pop-Location }

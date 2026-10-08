param([string]$KeyTool = 'keytool')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$properties = Join-Path $project 'android/key.properties'
$keystore = Join-Path $project 'android/app/dharmaj-release.jks'
if ((Test-Path -LiteralPath $properties) -or (Test-Path -LiteralPath $keystore)) {
    throw 'Signing files already exist. Restore/reuse the original key for updates; do not replace it.'
}
$bytes = New-Object byte[] 32
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $random.GetBytes($bytes) } finally { $random.Dispose() }
$password = [Convert]::ToBase64String($bytes)
$env:DHARMAJ_ANDROID_SIGNING_PASSWORD = $password
try {
    & $KeyTool -genkeypair -keystore $keystore -storetype JKS -alias dharmaj-release -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=Dharmaj Android' -storepass:env DHARMAJ_ANDROID_SIGNING_PASSWORD -keypass:env DHARMAJ_ANDROID_SIGNING_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Release signing key generation failed.' }
    @("storePassword=$password", "keyPassword=$password", 'keyAlias=dharmaj-release', 'storeFile=app/dharmaj-release.jks') |
        Set-Content -LiteralPath $properties -Encoding ascii
    foreach ($path in @($properties, $keystore)) {
        $acl = Get-Acl -LiteralPath $path
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.WindowsIdentity]::GetCurrent().User, 'FullControl', 'Allow'))
        Set-Acl -LiteralPath $path -AclObject $acl
    }
    Write-Host 'Release signing initialized. Back up android/key.properties and android/app/dharmaj-release.jks privately; keep the same key for future updates.'
} finally {
    Remove-Item Env:DHARMAJ_ANDROID_SIGNING_PASSWORD -ErrorAction SilentlyContinue
    $password = $null
    [Array]::Clear($bytes, 0, $bytes.Length)
}

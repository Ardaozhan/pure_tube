param (
    [string]$Version = "",
    [string]$Notes = "PureTube kablosuz OTA guncellemesi ve performans iyilestirmeleri."
)

$ErrorActionPreference = "Stop"
$ProjectDir = "C:\Users\ardao\.gemini\antigravity\scratch\pure_tube"
Set-Location $ProjectDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  PURETUBE OTA KABLOSUZ GUNCELLEME YAYINLAMA MOTORU       " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Mevcut surumu pubspec.yaml'den oku
$pubspecPath = Join-Path $ProjectDir "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
    $currentVer = $matches[1]
    $currentBuild = [int]$matches[2]
} else {
    $currentVer = "1.0.0"
    $currentBuild = 1
}

# Eger yeni surum belirtilmediyse otomatik bir ust surume gec (patch bump)
if ([string]::IsNullOrWhiteSpace($Version)) {
    $parts = $currentVer.Split('.')
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2] + 1
    $newVer = "$major.$minor.$patch"
    $newBuild = $currentBuild + 1
} else {
    $newVer = $Version.Trim().TrimStart('v','V')
    $newBuild = $currentBuild + 1
}

Write-Host "[*] Eski Surum : v$currentVer+$currentBuild" -ForegroundColor DarkGray
Write-Host "[*] Yeni Surum : v$newVer+$newBuild" -ForegroundColor Green
Write-Host "[*] Notlar     : $Notes" -ForegroundColor White
Write-Host "----------------------------------------------------------"

# 2. pubspec.yaml dosyasini guncelle
$newPubspec = $pubspecContent -replace 'version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+', "version: $newVer+$newBuild"
Set-Content -Path $pubspecPath -Value $newPubspec -NoNewline

# 3. lib/services/update_service.dart icindeki currentVersion ve currentBuildNumber'i guncelle
$updateServicePath = Join-Path $ProjectDir "lib\services\update_service.dart"
$updateContent = Get-Content $updateServicePath -Raw
$updateContent = $updateContent -replace "static const String currentVersion = '[^']+';", "static const String currentVersion = '$newVer';"
$updateContent = $updateContent -replace "static const int currentBuildNumber = \d+;", "static const int currentBuildNumber = $newBuild;"
Set-Content -Path $updateServicePath -Value $updateContent -NoNewline

Write-Host "[1/4] Versiyon dosyalari guncellendi (v$newVer)." -ForegroundColor Cyan

# 4. Release APK Derle
Write-Host "[2/4] Release APK derleniyor (flutter build apk --release)..." -ForegroundColor Yellow
$buildOutput = flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Flutter derleme hatasi olustu!" -ForegroundColor Red
    exit 1
}

$sourceApk = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-release.apk"
$targetApkName = "PureTube-v$newVer.apk"
$targetApk = Join-Path $ProjectDir $targetApkName
Copy-Item $sourceApk $targetApk -Force

Write-Host "[3/4] APK hazirlandi: $targetApkName" -ForegroundColor Cyan

# 5. Git Commit & Push
Write-Host "[4/4] GitHub Releases'e yukleniyor..." -ForegroundColor Yellow
git add .
git commit -m "Release v$newVer: $Notes"
git push -u origin main --force

# 6. GitHub Release Olustur ve APK'yi yukle
$tag = "v$newVer"
gh release create $tag $targetApk --title "PureTube $tag" --notes "$Notes"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  TEBRIKLER! PURETUBE v$newVer YAYINLANDI!              " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Telefonundaki PureTube uygulamasi acildiginda:" -ForegroundColor White
Write-Host "-> 'Yeni Surum v$newVer Mevcut!' uyarisi cikacak ve tek tikla guncellenecek." -ForegroundColor Cyan
Write-Host ""

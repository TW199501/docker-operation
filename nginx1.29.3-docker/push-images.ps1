# 用法（在專案根目錄）:
#   pwsh -File .\nginx1.29.3-docker\push-images.ps1
#   pwsh -File .\nginx1.29.3-docker\push-images.ps1 -NginxVersion 1.29.3 -HaproxyVersion trixie

Param(
  [string]$NginxVersion = "1.29.3",
  [string]$HaproxyVersion = "trixie"
)

$ErrorActionPreference = "Stop"

$nginxImageBase = "tw199501/nginx"
$haproxyImageBase = "tw199501/haproxy"

Write-Host "[INFO] Tagging nginx image..." -ForegroundColor Cyan
docker tag "$nginxImageBase`:$NginxVersion" "$nginxImageBase`:latest"

Write-Host "[INFO] Tagging haproxy image..." -ForegroundColor Cyan
docker tag "$haproxyImageBase`:$HaproxyVersion" "$haproxyImageBase`:latest"

Write-Host "[INFO] Pushing nginx tags: $NginxVersion, latest" -ForegroundColor Green
docker push "$nginxImageBase`:$NginxVersion"
docker push "$nginxImageBase`:latest"

Write-Host "[INFO] Pushing haproxy tags: $HaproxyVersion, latest" -ForegroundColor Green
docker push "$haproxyImageBase`:$HaproxyVersion"
docker push "$haproxyImageBase`:latest"

Write-Host "[INFO] Done." -ForegroundColor Yellow

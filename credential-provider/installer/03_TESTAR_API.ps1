#requires -Version 5.1
$ErrorActionPreference = "Stop"

$RegPath = "HKLM:\SOFTWARE\LabCPFProvider"

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}
Ensure-Admin

$config = Get-ItemProperty $RegPath
$url = $config.ApiUrl
$token = $config.ApiToken

$cpf = Read-Host "CPF para testar [12345678909]"
if (-not $cpf) { $cpf = "12345678909" }

$body = @{
    cpf = $cpf
    computer = $env:COMPUTERNAME
} | ConvertTo-Json -Compress

Write-Host ""
Write-Host "POST $url" -ForegroundColor Cyan

$response = Invoke-RestMethod `
    -Method Post `
    -Uri $url `
    -Headers @{ "X-Lab-Token" = $token } `
    -ContentType "application/json" `
    -Body $body `
    -TimeoutSec 5

$response | ConvertTo-Json

if ($response.authorized -eq $true) {
    Write-Host ""
    Write-Host "API AUTORIZOU O CPF." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "API NEGOU O CPF." -ForegroundColor Yellow
}

Read-Host "ENTER para fechar"

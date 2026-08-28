#requires -Version 5.1
$ErrorActionPreference = "Stop"

$Guid = "{D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}"
$Providers = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
$ExcludeKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$DefaultKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}
Ensure-Admin

if (-not (Test-Path "$Providers\$Guid")) {
    throw "LabCPFProvider nao registrado."
}

Get-ChildItem $Providers | ForEach-Object {
    Remove-ItemProperty $_.PSPath -Name Disabled -Force -ErrorAction SilentlyContinue
}

$excluded = @(
    Get-ChildItem $Providers |
    ForEach-Object { $_.PSChildName } |
    Where-Object { $_ -ine $Guid }
)

New-Item $ExcludeKey -Force | Out-Null
New-ItemProperty $ExcludeKey `
    -Name ExcludedCredentialProviders `
    -PropertyType String `
    -Value ($excluded -join ",") `
    -Force | Out-Null

New-Item $DefaultKey -Force | Out-Null
New-ItemProperty $DefaultKey `
    -Name DefaultCredentialProvider `
    -PropertyType String `
    -Value $Guid `
    -Force | Out-Null

Write-Host ""
Write-Host "MODO ALUNO ATIVO." -ForegroundColor Green
Write-Host "Reinicie o Windows." -ForegroundColor Cyan
Read-Host "ENTER para fechar"

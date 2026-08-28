#requires -Version 5.1
$ErrorActionPreference = "Stop"

$Guid = "{D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}"
$Providers = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
$Clsid = "Registry::HKEY_CLASSES_ROOT\CLSID"
$ExcludeKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$DefaultKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
$ConfigKey = "HKLM:\SOFTWARE\LabCPFProvider"
$DllTarget = "$env:WINDIR\System32\LabCPFProvider.dll"

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}
Ensure-Admin

Remove-ItemProperty $ExcludeKey -Name ExcludedCredentialProviders -Force -ErrorAction SilentlyContinue
Remove-ItemProperty $DefaultKey -Name DefaultCredentialProvider -Force -ErrorAction SilentlyContinue
Remove-Item "$Providers\$Guid" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$Clsid\$Guid" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $ConfigKey -Recurse -Force -ErrorAction SilentlyContinue

$userTileBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\UserTile"
if (Test-Path $userTileBase) {
    Get-ChildItem $userTileBase | ForEach-Object {
        try {
            if ([string]$_.GetValue("") -ieq $Guid) {
                Remove-Item $_.PSPath -Recurse -Force
            }
        } catch {}
    }
}

Remove-Item $DllTarget -Force -ErrorAction SilentlyContinue

Write-Host "LabCPFProvider removido. Reinicie o Windows." -ForegroundColor Green
Read-Host "ENTER para fechar"

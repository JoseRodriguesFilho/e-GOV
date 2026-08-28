#requires -Version 5.1
$ErrorActionPreference = "Stop"

$Guid = "{D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}"
$OldGuid = "{5FD3D285-0DD9-4362-8855-E0ABAACD4AF6}"
$DllSource = Join-Path $PSScriptRoot "LabCPFProvider.dll"
$DllTarget = "$env:WINDIR\System32\LabCPFProvider.dll"
$Providers = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"
$Clsid = "Registry::HKEY_CLASSES_ROOT\CLSID"
$UserTile = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\UserTile"

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit
    }
}
Ensure-Admin

if (-not (Test-Path $DllSource)) {
    throw "LabCPFProvider.dll nao encontrado."
}

# Conta local usada pela POC.
& net.exe user AlunoLab "Lab@Teste2026!" /add /passwordchg:no *> $null
if ($LASTEXITCODE -ne 0) {
    & net.exe user AlunoLab "Lab@Teste2026!" *> $null
}

& net.exe localgroup Administradores AlunoLab /delete *> $null
& net.exe localgroup Administrators AlunoLab /delete *> $null

Copy-Item $DllSource $DllTarget -Force

# Limpa sample antigo.
Remove-Item "$Providers\$OldGuid" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$Clsid\$OldGuid" -Recurse -Force -ErrorAction SilentlyContinue

# Registra provider.
New-Item "$Providers\$Guid" -Force | Out-Null
Set-Item "$Providers\$Guid" -Value "Acesso do Aluno"

New-Item "$Clsid\$Guid" -Force | Out-Null
Set-Item "$Clsid\$Guid" -Value "Acesso do Aluno"

New-Item "$Clsid\$Guid\InprocServer32" -Force | Out-Null
Set-Item "$Clsid\$Guid\InprocServer32" -Value $DllTarget
New-ItemProperty "$Clsid\$Guid\InprocServer32" `
    -Name ThreadingModel `
    -PropertyType String `
    -Value "Apartment" `
    -Force | Out-Null

# Preferencia do usuario AlunoLab.
$account = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, "AlunoLab")
$sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value

New-Item "$UserTile\$sid" -Force | Out-Null
Set-Item "$UserTile\$sid" -Value $Guid

Write-Host ""
Write-Host "LabCPFProvider v7 instalado." -ForegroundColor Green
Write-Host "Agora execute 02_CONFIGURAR_API.cmd." -ForegroundColor Cyan
Read-Host "ENTER para fechar"

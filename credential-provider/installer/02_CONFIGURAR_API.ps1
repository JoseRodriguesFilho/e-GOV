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

$existingUrl = ""
$existingToken = ""

try { $existingUrl = (Get-ItemProperty $RegPath -Name ApiUrl -ErrorAction Stop).ApiUrl } catch {}
try { $existingToken = (Get-ItemProperty $RegPath -Name ApiToken -ErrorAction Stop).ApiToken } catch {}

Write-Host ""
Write-Host "CONFIGURACAO DA API" -ForegroundColor Cyan
Write-Host ""

if ($existingUrl) {
    Write-Host "Atual: $existingUrl"
}

$apiUrl = Read-Host "URL completa do endpoint (ex.: https://login.exemplo.gov.br/auth/cpf)"
if (-not $apiUrl) { $apiUrl = $existingUrl }

if (-not $apiUrl -or ($apiUrl -notmatch '^https?://')) {
    throw "URL invalida."
}

$secureToken = Read-Host "LAB_API_TOKEN" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
try {
    $apiToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

if (-not $apiToken) {
    if ($existingToken) {
        $apiToken = $existingToken
    } else {
        throw "Token nao informado."
    }
}

$allowHttp = 0

if ($apiUrl.StartsWith("http://", [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host ""
    Write-Host "ATENCAO: HTTP envia CPF e token sem criptografia." -ForegroundColor Yellow
    $confirm = Read-Host "Permitir HTTP somente para teste? Digite SIM"
    if ($confirm -ne "SIM") {
        throw "Configuracao cancelada. Use HTTPS."
    }
    $allowHttp = 1
}

New-Item $RegPath -Force | Out-Null
New-ItemProperty $RegPath -Name ApiUrl -PropertyType String -Value $apiUrl -Force | Out-Null
New-ItemProperty $RegPath -Name ApiToken -PropertyType String -Value $apiToken -Force | Out-Null
New-ItemProperty $RegPath -Name AllowHttp -PropertyType DWord -Value $allowHttp -Force | Out-Null

# Protege a chave: SYSTEM e Administradores apenas.
$acl = New-Object System.Security.AccessControl.RegistrySecurity
$acl.SetAccessRuleProtection($true, $false)

$systemRule = New-Object System.Security.AccessControl.RegistryAccessRule(
    "SYSTEM",
    "FullControl",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)

$adminsSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminRule = New-Object System.Security.AccessControl.RegistryAccessRule(
    $adminsSid,
    "FullControl",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)

$acl.AddAccessRule($systemRule)
$acl.AddAccessRule($adminRule)
Set-Acl -Path $RegPath -AclObject $acl

Write-Host ""
Write-Host "API configurada." -ForegroundColor Green
Write-Host "URL: $apiUrl"
Write-Host "Token protegido em HKLM\SOFTWARE\LabCPFProvider" -ForegroundColor Green
Write-Host ""
Write-Host "Execute 03_TESTAR_API.cmd antes de bloquear a maquina." -ForegroundColor Cyan
Read-Host "ENTER para fechar"

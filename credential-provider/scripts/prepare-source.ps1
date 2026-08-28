$ErrorActionPreference = "Stop"

$repo = "https://raw.githubusercontent.com/microsoft/Windows-classic-samples/main/Samples/CredentialProvider/cpp"
$out = Join-Path $PSScriptRoot "..\generated"

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null

$files = @(
    "CSampleCredential.cpp",
    "CSampleCredential.h",
    "CSampleProvider.cpp",
    "CSampleProvider.h",
    "Dll.cpp",
    "Dll.h",
    "helpers.cpp",
    "helpers.h",
    "guid.cpp",
    "guid.h",
    "common.h",
    "resource.h",
    "resources.rc",
    "samplev2credentialprovider.def",
    "SampleV2CredentialProvider.vcxproj",
    "tileimage.bmp"
)

foreach ($file in $files) {
    Write-Host "Downloading $file"
    Invoke-WebRequest -UseBasicParsing -Uri "$repo/$file" -OutFile (Join-Path $out $file)
}

Copy-Item (Join-Path $PSScriptRoot "LabApi.h.template") (Join-Path $out "LabApi.h") -Force
Copy-Item (Join-Path $PSScriptRoot "LabApi.cpp.template") (Join-Path $out "LabApi.cpp") -Force

# Moderniza projeto e adiciona os dois arquivos da integracao HTTP.
$projPath = Join-Path $out "SampleV2CredentialProvider.vcxproj"
$proj = Get-Content $projPath -Raw
$proj = $proj.Replace("<PlatformToolset>v110</PlatformToolset>", "<PlatformToolset>v143</PlatformToolset>")

$compileAnchor = '<ClCompile Include="CSampleCredential.cpp" />'
$includeAnchor = '<ClInclude Include="CSampleCredential.h" />'

if (-not $proj.Contains($compileAnchor)) { throw "Anchor ClCompile nao encontrado." }
if (-not $proj.Contains($includeAnchor)) { throw "Anchor ClInclude nao encontrado." }

$proj = $proj.Replace(
    $compileAnchor,
    $compileAnchor + "`r`n    <ClCompile Include=`"LabApi.cpp`" />")

$proj = $proj.Replace(
    $includeAnchor,
    $includeAnchor + "`r`n    <ClInclude Include=`"LabApi.h`" />")

Set-Content $projPath $proj -Encoding UTF8

# GUID proprio.
$guidPath = Join-Path $out "guid.h"
$guidText = @'
// LabCPFProvider
// {D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}
DEFINE_GUID(CLSID_CSample,
    0xd2d9e531, 0x8db1, 0x4c83,
    0xab, 0xf9, 0x81, 0x0f, 0x70, 0xa1, 0xeb, 0x09);
'@
Set-Content $guidPath $guidText -Encoding UTF8

# Interface: somente titulo + CPF + botao.
$commonPath = Join-Path $out "common.h"
$c = Get-Content $commonPath -Raw

$c = $c.Replace('L"Sample Credential Provider"', 'L"Acesso do Aluno"')
$c = $c.Replace('L"Edit text"', 'L"CPF"')

$map = @{
'SFI_TILEIMAGE'='CPFS_HIDDEN,                     CPFIS_NONE'
'SFI_PASSWORD'='CPFS_HIDDEN,                     CPFIS_NONE'
'SFI_LAUNCHWINDOW_LINK'='CPFS_HIDDEN,                     CPFIS_NONE'
'SFI_HIDECONTROLS_LINK'='CPFS_HIDDEN,                     CPFIS_NONE'
'SFI_FULLNAME_TEXT'='CPFS_HIDDEN,                     CPFIS_NONE'
'SFI_DISPLAYNAME_TEXT'='CPFS_HIDDEN,                     CPFIS_NONE'
'SFI_LOGONSTATUS_TEXT'='CPFS_HIDDEN,                     CPFIS_NONE'
'SFI_CHECKBOX'='CPFS_HIDDEN,                     CPFIS_NONE'
'SFI_EDIT_TEXT'='CPFS_DISPLAY_IN_SELECTED_TILE,   CPFIS_FOCUSED'
'SFI_COMBOBOX'='CPFS_HIDDEN,                     CPFIS_NONE'
}

foreach ($k in $map.Keys) {
    $pattern = '\{\s*CPFS_[A-Z_]+,\s*CPFIS_[A-Z_]+\s*\},\s*//\s*' + $k
    $replacement = '{ ' + $map[$k] + ' },    // ' + $k
    $c = [regex]::Replace($c, $pattern, $replacement)
}
Set-Content $commonPath $c -Encoding UTF8

# Credential.
$credPath = Join-Path $out "CSampleCredential.cpp"
$x = Get-Content $credPath -Raw

$x = $x.Replace('#include "guid.h"', "#include `"guid.h`"`r`n#include `"LabApi.h`"")
$x = $x.Replace('SHStrDupW(L"Sample Credential", &_rgFieldStrings[SFI_LABEL])',
                'SHStrDupW(L"Acesso do Aluno", &_rgFieldStrings[SFI_LABEL])')
$x = $x.Replace('SHStrDupW(L"Sample Credential Provider", &_rgFieldStrings[SFI_LARGE_TEXT])',
                'SHStrDupW(L"Acesso do Aluno", &_rgFieldStrings[SFI_LARGE_TEXT])')
$x = $x.Replace('SHStrDupW(L"Edit Text", &_rgFieldStrings[SFI_EDIT_TEXT])',
                'SHStrDupW(L"", &_rgFieldStrings[SFI_EDIT_TEXT])')
$x = $x.Replace('SHStrDupW(L"Submit", &_rgFieldStrings[SFI_SUBMIT_BUTTON])',
                'SHStrDupW(L"Entrar", &_rgFieldStrings[SFI_SUBMIT_BUTTON])')
$x = $x.Replace('*pdwAdjacentTo = SFI_PASSWORD;', '*pdwAdjacentTo = SFI_EDIT_TEXT;')

# A senha local ainda e POC; o CPF nao fica mais fixo na DLL.
$oldProtect = 'ProtectIfNecessaryAndCopyPassword(_rgFieldStrings[SFI_PASSWORD], _cpus, &pwzProtectedPassword)'
$newProtect = 'ProtectIfNecessaryAndCopyPassword(L"Lab@Teste2026!", _cpus, &pwzProtectedPassword)'

if (-not $x.Contains($oldProtect)) {
    throw "ProtectIfNecessaryAndCopyPassword nao encontrado."
}
$x = $x.Replace($oldProtect, $newProtect)

$authBlock = @'

    // LabCPFProvider v7: normaliza CPF e consulta API.
    wchar_t normalizedCpf[12] = {0};
    size_t cpfPos = 0;
    bool invalidCharacter = false;

    if (_rgFieldStrings[SFI_EDIT_TEXT] != nullptr)
    {
        for (const wchar_t* p = _rgFieldStrings[SFI_EDIT_TEXT]; *p != L'\0'; ++p)
        {
            if (*p >= L'0' && *p <= L'9')
            {
                if (cpfPos >= 11)
                {
                    cpfPos = 12;
                    break;
                }

                normalizedCpf[cpfPos++] = *p;
            }
            else if (*p == L'.' || *p == L'-' || *p == L' ' || *p == L'\t')
            {
                // Pontuacao permitida.
            }
            else
            {
                invalidCharacter = true;
                break;
            }
        }
    }

    if (invalidCharacter || cpfPos != 11)
    {
        SHStrDupW(L"CPF invalido.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;
        return S_OK;
    }

    LAB_AUTH_RESULT authResult = LabAuthorizeCpf(normalizedCpf);

    if (authResult != LAB_AUTH_AUTHORIZED)
    {
        PCWSTR statusText = L"CPF nao autorizado.";

        if (authResult == LAB_AUTH_SERVICE_UNAVAILABLE)
        {
            statusText = L"Servico de autenticacao indisponivel.";
        }
        else if (authResult == LAB_AUTH_NOT_CONFIGURED)
        {
            statusText = L"API de autenticacao nao configurada.";
        }
        else if (authResult == LAB_AUTH_CLIENT_UNAUTHORIZED)
        {
            statusText = L"Este computador nao foi autorizado pela API.";
        }

        SHStrDupW(statusText, ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;

        if (_pCredProvCredentialEvents)
        {
            _pCredProvCredentialEvents->SetFieldString(this, SFI_EDIT_TEXT, L"");
        }

        return S_OK;
    }
'@

$serializationAnchor = 'ZeroMemory(pcpcs, sizeof(*pcpcs));'
$anchorIndex = $x.IndexOf($serializationAnchor)

if ($anchorIndex -lt 0) {
    throw "Anchor GetSerialization nao encontrado."
}

$insertAt = $anchorIndex + $serializationAnchor.Length
$x = $x.Insert($insertAt, $authBlock)

if (-not $x.Contains('LabAuthorizeCpf(normalizedCpf)')) {
    throw "Integracao API nao foi inserida."
}
if ($x.Contains('wcscmp(normalizedCpf, L"12345678909")')) {
    throw "Validacao fixa de CPF ainda existe."
}
if (-not $x.Contains('L"Lab@Teste2026!"')) {
    throw "Senha POC nao foi inserida."
}

Set-Content $credPath $x -Encoding UTF8

# Provider: enumera somente AlunoLab e corrige contagem nula.
$providerPath = Join-Path $out "CSampleProvider.cpp"
$y = Get-Content $providerPath -Raw

$enumPattern = '(?s)HRESULT CSampleProvider::_EnumerateCredentials\(\)\s*\{.*?\n\}\s*\n\s*// Boilerplate code to create our provider\.'

$newFunction = @'
HRESULT CSampleProvider::_EnumerateCredentials()
{
    HRESULT hr = HRESULT_FROM_WIN32(ERROR_NO_SUCH_USER);

    if (_pCredProviderUserArray != nullptr)
    {
        DWORD dwUserCount = 0;
        HRESULT hrCount = _pCredProviderUserArray->GetCount(&dwUserCount);

        if (FAILED(hrCount))
        {
            return hrCount;
        }

        for (DWORD i = 0; i < dwUserCount; i++)
        {
            ICredentialProviderUser *pCredUser = nullptr;
            HRESULT hrUser = _pCredProviderUserArray->GetAt(i, &pCredUser);

            if (SUCCEEDED(hrUser) && pCredUser != nullptr)
            {
                PWSTR pszUserName = nullptr;
                hrUser = pCredUser->GetStringValue(PKEY_Identity_UserName, &pszUserName);

                BOOL isAlunoLab = FALSE;

                if (SUCCEEDED(hrUser) && pszUserName != nullptr)
                {
                    PCWSTR leafName = wcsrchr(pszUserName, L'\\');
                    leafName = (leafName != nullptr) ? (leafName + 1) : pszUserName;
                    isAlunoLab = (_wcsicmp(leafName, L"AlunoLab") == 0);
                }

                CoTaskMemFree(pszUserName);

                if (isAlunoLab)
                {
                    _pCredential = new(std::nothrow) CSampleCredential();

                    if (_pCredential != nullptr)
                    {
                        hr = _pCredential->Initialize(
                            _cpus,
                            s_rgCredProvFieldDescriptors,
                            s_rgFieldStatePairs,
                            pCredUser);

                        if (FAILED(hr))
                        {
                            _pCredential->Release();
                            _pCredential = nullptr;
                        }
                    }
                    else
                    {
                        hr = E_OUTOFMEMORY;
                    }

                    pCredUser->Release();
                    break;
                }

                pCredUser->Release();
            }
        }
    }

    return hr;
}

// Boilerplate code to create our provider.
'@

$y2 = [regex]::Replace($y, $enumPattern, $newFunction)
if ($y2 -eq $y) {
    throw "Nao consegui substituir _EnumerateCredentials()."
}
$y = $y2

$countOld = '*pdwCount = 1;'
$countNew = '*pdwCount = (_pCredential != nullptr) ? 1 : 0;'
if (-not $y.Contains($countOld)) { throw "GetCredentialCount esperado nao encontrado." }
$y = $y.Replace($countOld, $countNew)

$atOld = 'if ((dwIndex == 0) && ppcpc)'
$atNew = 'if ((dwIndex == 0) && ppcpc && (_pCredential != nullptr))'
if (-not $y.Contains($atOld)) { throw "GetCredentialAt esperado nao encontrado." }
$y = $y.Replace($atOld, $atNew)

Set-Content $providerPath $y -Encoding UTF8

Write-Host "LabCPFProvider v7 preparado." -ForegroundColor Green
Write-Host "Validacao de CPF: API" -ForegroundColor Green
Write-Host "Conta interna: AlunoLab" -ForegroundColor Yellow
Write-Host "Provider GUID: {D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}" -ForegroundColor Green

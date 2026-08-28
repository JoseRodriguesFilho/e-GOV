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

$projPath = Join-Path $out "SampleV2CredentialProvider.vcxproj"
$proj = Get-Content $projPath -Raw
$proj = $proj.Replace("<PlatformToolset>v110</PlatformToolset>", "<PlatformToolset>v143</PlatformToolset>")
Set-Content $projPath $proj -Encoding UTF8

$guidPath = Join-Path $out "guid.h"
$guidText = @'
// LabCPFProvider
// {D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}
DEFINE_GUID(CLSID_CSample,
    0xd2d9e531, 0x8db1, 0x4c83,
    0xab, 0xf9, 0x81, 0x0f, 0x70, 0xa1, 0xeb, 0x09);
'@
Set-Content $guidPath $guidText -Encoding UTF8

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

$credPath = Join-Path $out "CSampleCredential.cpp"
$x = Get-Content $credPath -Raw

$x = $x.Replace('SHStrDupW(L"Sample Credential", &_rgFieldStrings[SFI_LABEL])',
                'SHStrDupW(L"Acesso do Aluno", &_rgFieldStrings[SFI_LABEL])')
$x = $x.Replace('SHStrDupW(L"Sample Credential Provider", &_rgFieldStrings[SFI_LARGE_TEXT])',
                'SHStrDupW(L"Acesso do Aluno", &_rgFieldStrings[SFI_LARGE_TEXT])')
$x = $x.Replace('SHStrDupW(L"Edit Text", &_rgFieldStrings[SFI_EDIT_TEXT])',
                'SHStrDupW(L"", &_rgFieldStrings[SFI_EDIT_TEXT])')
$x = $x.Replace('SHStrDupW(L"", &_rgFieldStrings[SFI_PASSWORD])',
                'SHStrDupW(L"__TEST_PASS__", &_rgFieldStrings[SFI_PASSWORD])')
$x = $x.Replace('SHStrDupW(L"Submit", &_rgFieldStrings[SFI_SUBMIT_BUTTON])',
                'SHStrDupW(L"Entrar", &_rgFieldStrings[SFI_SUBMIT_BUTTON])')
$x = $x.Replace('*pdwAdjacentTo = SFI_PASSWORD;', '*pdwAdjacentTo = SFI_EDIT_TEXT;')

$cpfBlock = @'

    // v4.1 TESTE: o aluno ve apenas o CPF.
    wchar_t normalizedCpf[12] = {0};
    size_t cpfPos = 0;

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
        }
    }

    if (cpfPos != 11 || wcscmp(normalizedCpf, L"12345678909") != 0)
    {
        SHStrDupW(L"CPF nao autorizado.", ppwszOptionalStatusText);
        *pcpsiOptionalStatusIcon = CPSI_ERROR;

        if (_pCredProvCredentialEvents)
        {
            _pCredProvCredentialEvents->SetFieldString(this, SFI_EDIT_TEXT, L"");
        }

        return S_OK;
    }
'@

# Insere logo apos ZeroMemory dentro de GetSerialization.
# Nao depende mais do comentario exato do sample Microsoft.
$serializationAnchor = 'ZeroMemory(pcpcs, sizeof(*pcpcs));'
$anchorIndex = $x.IndexOf($serializationAnchor)

if ($anchorIndex -lt 0) {
    throw "Nao encontrei a ancora de GetSerialization em CSampleCredential.cpp."
}

$insertAt = $anchorIndex + $serializationAnchor.Length
$x = $x.Insert($insertAt, $cpfBlock)

Set-Content $credPath $x -Encoding UTF8

$providerPath = Join-Path $out "CSampleProvider.cpp"
$y = Get-Content $providerPath -Raw

$pattern = '(?s)HRESULT CSampleProvider::_EnumerateCredentials\(\)\s*\{.*?\n\}\s*\n\s*// Boilerplate code to create our provider\.'

$newFunction = @'
HRESULT CSampleProvider::_EnumerateCredentials()
{
    HRESULT hr = E_UNEXPECTED;

    if (_pCredProviderUserArray != nullptr)
    {
        DWORD dwUserCount = 0;
        hr = _pCredProviderUserArray->GetCount(&dwUserCount);

        if (SUCCEEDED(hr))
        {
            hr = HRESULT_FROM_WIN32(ERROR_NO_SUCH_USER);

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
                        isAlunoLab = (_wcsicmp(pszUserName, L"AlunoLab") == 0);
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
    }

    return hr;
}

// Boilerplate code to create our provider.
'@

$y2 = [regex]::Replace($y, $pattern, $newFunction)

if ($y2 -eq $y) {
    throw "Nao consegui substituir CSampleProvider::_EnumerateCredentials()."
}
Set-Content $providerPath $y2 -Encoding UTF8

Write-Host "LabCPFProvider v4.1 preparado." -ForegroundColor Green
Write-Host "CPF de teste: 12345678909" -ForegroundColor Yellow
Write-Host "Conta interna: AlunoLab" -ForegroundColor Yellow
Write-Host "Provider GUID: {D2D9E531-8DB1-4C83-ABF9-810F70A1EB09}" -ForegroundColor Green

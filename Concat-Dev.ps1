param([switch]$Check, [switch]$BuildOnly, [switch]$Verify, [switch]$FromSource)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$release = '995b205492f2da908cc8aa8c83812008b10ae22f'
$official = Join-Path $PSScriptRoot 'vendor\official'
$head = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the local checkout.' }
$inputs = @('src', 'assets', 'models', 'scripts', 'android-native')
git diff --quiet $release -- @inputs
$diff = $LASTEXITCODE
if ($diff -gt 1) { throw 'Cannot compare the checkout to the packaged release.' }
$changes = git ls-files --others --exclude-standard -- @inputs
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect local changes.' }
$useRelease = !$FromSource -and $diff -eq 0 -and !$changes -and (Test-Path "$official\concat.exe")
if ($useRelease) {
    $exe = Join-Path $official 'concat.exe'
    Write-Host "Official v0.2.12 (matches local source): $exe"
    if (!(Test-Path -LiteralPath $exe)) { throw 'Official application files are missing.' }
} else {
    Write-Host "Local source build (Cargo quick profile): $head"
    if (!$Check) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (!$vs) { throw 'Visual C++ x64 build tools were not found.' }
        $tools = Get-ChildItem "$vs\VC\Tools\MSVC" -Directory |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        $sdk = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots').KitsRoot10
        $version = (Get-ChildItem (Join-Path $sdk 'Lib') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1).Name
        $vc = $tools.FullName
        if (!$env:FFMPEG_DIR) {
            $env:FFMPEG_DIR = Join-Path $PSScriptRoot 'vendor\dev\ffmpeg-n8.1.3-9-g29e619e767-win64-lgpl-shared-8.1'
        }
        if (!$env:LIBCLANG_PATH) {
            $llvm = @("$env:ProgramFiles\LLVM\bin", 'D:\Program Files\LLVM\bin') |
                Where-Object { Test-Path "$_\libclang.dll" } | Select-Object -First 1
            if (!$llvm) { throw 'Set LIBCLANG_PATH to the LLVM bin directory.' }
            $env:LIBCLANG_PATH = $llvm
        }
        if (!$env:ORT_LIB_LOCATION) {
            $env:ORT_LIB_LOCATION = Join-Path $PSScriptRoot 'vendor\dev\runtimes\win-x64\native'
        }
        $env:ORT_PREFER_DYNAMIC_LINK = '1'
        $env:CMAKE_GENERATOR = 'Ninja'
        $env:CC = 'clang-cl'
        $env:CXX = 'clang-cl'
        $env:PATH = "$vc\bin\Hostx64\x64;$sdk\bin\$version\x64;$env:LIBCLANG_PATH;$env:FFMPEG_DIR\bin;$env:ORT_LIB_LOCATION;$env:PATH"
        $env:LIB = "$vc\lib\x64;$sdk\Lib\$version\ucrt\x64;$sdk\Lib\$version\um\x64;$env:LIB"
        $env:INCLUDE = "$vc\include;$sdk\Include\$version\ucrt;$sdk\Include\$version\shared;$sdk\Include\$version\um;$sdk\Include\$version\winrt;$env:INCLUDE"
        $env:CARGO_TARGET_DIR = Join-Path $PSScriptRoot 'src\target'
        Push-Location src
        try {
            cargo build --locked --profile quick -p concat
            if ($LASTEXITCODE -ne 0) { throw 'Local build failed. The old editor was not started.' }
        } finally { Pop-Location }
        $exe = Join-Path $env:CARGO_TARGET_DIR 'quick\concat.exe'
    }
}
if ($Check) { exit 0 }
if ($Verify) {
    $p = Start-Process -FilePath $exe -ArgumentList '--version' -Wait -NoNewWindow -PassThru
    exit $p.ExitCode
}
if (!$BuildOnly) { Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) }

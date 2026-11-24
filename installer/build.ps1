[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\docs\downloads'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = Join-Path $PSScriptRoot 'install.ps1'
$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
# PowerShell 5.1 needs a BOM for non-ASCII embedded resources.
$stage = Join-Path ([IO.Path]::GetTempPath()) ('oneclick-build-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
try {
    $resource = Join-Path $stage 'install.ps1'
    [IO.File]::WriteAllText($resource, [IO.File]::ReadAllText($source), [Text.UTF8Encoding]::new($true))
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $resource -SelfTest
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell self-test failed.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory)) | Out-Null
    $output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'OneClick-UNIVAP-Setup.exe'
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) { throw '.NET Framework C# compiler not found. Build on Windows x64.' }
    & $csc /nologo /target:winexe /platform:x64 /optimize+ /utf8output "/out:$output" "/win32manifest:$(Join-Path $PSScriptRoot 'app.manifest')" "/resource:$resource,OneClick.install.ps1" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Core.dll (Join-Path $PSScriptRoot 'Program.cs')
    if ($LASTEXITCODE -ne 0) { throw 'C# compilation failed.' }
    $test = Start-Process -FilePath $output -ArgumentList '--self-test' -Wait -PassThru
    if ($test.ExitCode -ne 0) { throw 'Embedded executable self-test failed.' }
    $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'OneClick-UNIVAP-Setup.exe.sha256'), "$hash  OneClick-UNIVAP-Setup.exe`n", [Text.UTF8Encoding]::new($false))
    Write-Host "BUILD OK: $output"
    Write-Host "SHA-256: $hash"
} finally { Remove-Item -LiteralPath $stage -Recurse -Force }

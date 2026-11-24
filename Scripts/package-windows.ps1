param([string]$OutDir = "dist")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid version" }
$out = (New-Item -ItemType Directory -Force -Path $OutDir).FullName
$stage = Join-Path ([IO.Path]::GetTempPath()) ("clawd-build-" + [guid]::NewGuid())
New-Item -Path $stage -ItemType Directory | Out-Null
try {
    python "$root/Scripts/freeze-desktop.py" --out $stage
    if ($LASTEXITCODE -ne 0) { throw "Freezing the Windows program failed" }
    $app = Join-Path $stage "ClawdCompanion"
    $marker = Join-Path $app "clawd-package.txt"
    Set-Content $marker -Encoding ascii -Value 'windows-portable'
    $zip = Join-Path $out "Clawd-Companion-$version-Windows-x64-Portable.zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $zip) { Remove-Item -LiteralPath $zip }
    [IO.Compression.ZipFile]::CreateFromDirectory($app, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
    Set-Content $marker -Encoding ascii -Value 'windows-installer'
    $installer = Join-Path $out "Clawd-Companion-$version-Windows-x64-Setup.exe"
    $nsis = Get-Command makensis -ErrorAction SilentlyContinue
    $compiler = if ($nsis) { $nsis.Source } else { "${env:ProgramFiles(x86)}\NSIS\makensis.exe" }
    if (!(Test-Path $compiler)) { throw "Install NSIS 3 first" }
    & $compiler "/DVERSION=$version" "/DSOURCE=$app" "/DOUTFILE=$installer" "$root/Packaging/windows/companion.nsi"
    if ($LASTEXITCODE -ne 0 -or !(Test-Path $installer)) { throw "Compiling the installer failed" }
} finally {
    Remove-Item $stage -Recurse -Force
}

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ArchivePath,
    [Parameter(Mandatory = $true)][string]$ChecksumPath,
    [Parameter(Mandatory = $true)][string]$ManifestPath
)

# Uses actual release binaries in an isolated temp directory; never edits user PATH or an installed omp.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install.ps1'
$archive = (Get-Item -LiteralPath $ArchivePath).FullName
$checksums = (Get-Item -LiteralPath $ChecksumPath).FullName
$manifest = (Get-Item -LiteralPath $ManifestPath).FullName
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('omp-installer-regression-' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $fixture 'installed'
$oldProcessPath = $env:Path
$oldUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Invoke-Install([string]$Zip, [string]$Sums) {
    & $installer -ArchivePath $Zip -ChecksumPath $Sums -ManifestPath $manifest -InstallDir $target -NoPath
}

function Assert-Rejected([scriptblock]$Action) {
    $failure = $null
    try { & $Action } catch { $failure = $_ }
    Assert-That ($null -ne $failure) 'The invalid operation was accepted.'
}

function Get-InstalledHashes {
    $snapshot = @{}
    foreach ($file in Get-ChildItem -LiteralPath $target -File -Recurse -Force) {
        $snapshot[$file.FullName.Substring($target.Length)] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $snapshot
}

function Assert-Unchanged($Before) {
    $after = Get-InstalledHashes
    Assert-That ($Before.Count -eq $after.Count) 'Installed file count changed after rejection/rollback.'
    foreach ($name in $Before.Keys) {
        Assert-That ($after.ContainsKey($name) -and $after[$name] -eq $Before[$name]) "File was not preserved: $name"
    }
}

[IO.Directory]::CreateDirectory($fixture) | Out-Null
try {
    Invoke-Install $archive $checksums
    Assert-That (Test-Path -LiteralPath (Join-Path $target 'omp.exe')) 'Offline install did not produce omp.exe.'
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $target 'omp-localized.json'))) 'Portable install created developer metadata.'

    $customPack = Join-Path $target 'locales/ko.json'
    [IO.File]::WriteAllText($customPack, '{"USAGE":"CUSTOM_INSTALLER_REGRESSION"}', $utf8)
    [IO.File]::WriteAllText((Join-Path $target 'unmanaged-settings.json'), '{"keep":true}', $utf8)
    $customHash = (Get-FileHash -LiteralPath $customPack -Algorithm SHA256).Hash
    Invoke-Install $archive $checksums
    Assert-That ((Get-FileHash -LiteralPath $customPack -Algorithm SHA256).Hash -eq $customHash) 'Reinstall rewrote the custom Korean pack.'
    Assert-That ([IO.File]::ReadAllText((Join-Path $target 'unmanaged-settings.json')) -ceq '{"keep":true}') 'Reinstall changed unrelated settings.'
    $baseline = Get-InstalledHashes

    $badDirectory = Join-Path $fixture 'bad-checksum'
    [IO.Directory]::CreateDirectory($badDirectory) | Out-Null
    $badArchive = Join-Path $badDirectory ([IO.Path]::GetFileName($archive))
    [IO.File]::Copy($archive, $badArchive)
    $stream = [IO.File]::Open($badArchive, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite)
    try {
        $first = $stream.ReadByte()
        $stream.Position = 0
        $stream.WriteByte([byte]($first -bxor 1))
    } finally { $stream.Dispose() }
    Assert-Rejected { Invoke-Install $badArchive $checksums }
    Assert-Unchanged $baseline

    $traversalDirectory = Join-Path $fixture 'bad-entry'
    [IO.Directory]::CreateDirectory($traversalDirectory) | Out-Null
    $traversalArchive = Join-Path $traversalDirectory ([IO.Path]::GetFileName($archive))
    [IO.File]::Copy($archive, $traversalArchive)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($traversalArchive, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $zip.CreateEntry('../escaped.txt')
        $writer = New-Object IO.StreamWriter($entry.Open())
        try { $writer.Write('must never escape') } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
    $traversalSums = Join-Path $traversalDirectory 'SHA256SUMS'
    [IO.File]::WriteAllText($traversalSums,
        (Get-FileHash -LiteralPath $traversalArchive -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($archive) + "`n", $utf8)
    Assert-Rejected { Invoke-Install $traversalArchive $traversalSums }
    Assert-Unchanged $baseline
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $fixture 'escaped.txt'))) 'ZIP traversal wrote outside staging.'

    # A locked late-promotion file forces rollback after earlier files were already replaced.
    [IO.File]::WriteAllText((Join-Path $target 'LICENSE'), 'ROLLBACK_ORIGINAL_LICENSE', $utf8)
    $baseline = Get-InstalledHashes
    $lock = [IO.File]::Open((Join-Path $target 'README.md'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        # Windows lock error text is localized; file hashes below assert successful rollback.
        Assert-Rejected { Invoke-Install $archive $checksums }
    } finally { $lock.Dispose() }
    Assert-Unchanged $baseline

    [IO.File]::WriteAllText((Join-Path $target 'omp-localized.json'), '{"private":"do not replace"}', $utf8)
    $baseline = Get-InstalledHashes
    Assert-Rejected { Invoke-Install $archive $checksums }
    Assert-Unchanged $baseline
    Assert-That ($env:Path -ceq $oldProcessPath) '-NoPath changed current-process PATH.'
    Assert-That ([Environment]::GetEnvironmentVariable('Path', 'User') -ceq $oldUserPath) '-NoPath changed User PATH.'
    Assert-That (@(Get-ChildItem -LiteralPath $fixture -Directory -Filter '.omp-korean-install-*' -Force).Count -eq 0) 'Installer left staging/backup directories after successful rollback.'
    Write-Host 'Installer regression smoke passed: offline verification, preserved partial pack, checksum rejection, traversal rejection, rollback, developer-install protection, and unchanged PATH.'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

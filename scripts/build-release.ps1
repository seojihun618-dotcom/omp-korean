#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$BinaryPath,
    [string]$UpdateKitPath,
    [string]$Repository = $env:GITHUB_REPOSITORY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $PSScriptRoot
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed ($LASTEXITCODE): $($Arguments -join ' ')" }
}

function Read-Checked {
    param([string]$Program, [string[]]$Arguments)
    $text = (& $Program @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "$Program failed ($LASTEXITCODE): $text" }
    return $text
}

function Export-TarMember {
    param([string]$Archive, [string]$Member, [string]$Destination)
    # Stream one literal member to a caller-chosen path: tar never writes archive paths or links.
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Command tar.exe -ErrorAction Stop).Source
    $info.Arguments = '-xOf "' + $Archive + '" "' + $Member + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $file = $null
    try {
        [void]$process.Start()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $file = [IO.File]::Create($Destination)
        $process.StandardOutput.BaseStream.CopyTo($file)
        $file.Dispose()
        $file = $null
        $process.WaitForExit()
        $details = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Cannot read native package member ${Member}: $details" }
        if ((Get-Item -LiteralPath $Destination).Length -eq 0) { throw "Empty native package member: $Member" }
    } finally {
        if ($null -ne $file) { $file.Dispose() }
        $process.Dispose()
    }
}

if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or
    $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Build on Windows x64 using 64-bit PowerShell.' }
if ($Repository -and $Repository -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw 'Repository must be a GitHub owner/name.'
}
if ($SkipBuild -and (-not $BinaryPath -or -not $UpdateKitPath)) { throw '-SkipBuild requires explicit -BinaryPath and -UpdateKitPath.' }
if (-not $SkipBuild -and ($BinaryPath -or $UpdateKitPath)) { throw '-BinaryPath and -UpdateKitPath are only valid with -SkipBuild.' }
$manifestPath = Join-Path $Root 'release.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.version -cnotmatch '^(\d+\.\d+\.\d+)-ko\.\d+$') { throw 'Invalid release version.' }
if ($manifest.upstreamVersion -cne $Matches[1] -or $manifest.upstreamCommit -cnotmatch '^[0-9a-f]{40}$' -or
    $manifest.bunVersion -cne '1.4.4' -or $manifest.platform -cne 'windows-x64' -or
    $manifest.archive -cne "omp-korean-$($manifest.version)-windows-x64.zip") { throw 'Invalid release manifest.' }
foreach ($relative in @('source/omp-language-pack.patch', 'locales/ko.json', 'locales/en.json', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'README.md', 'install.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relative) -PathType Leaf)) { throw "Missing release input: $relative" }
}
Add-Type -AssemblyName System.Web.Extensions
$jsonParser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$jsonParser.MaxJsonLength = [int]::MaxValue
foreach ($locale in @('ko', 'en')) {
    # Locale keys are case-sensitive; PowerShell 5.1 ConvertFrom-Json is not.
    $catalog = $jsonParser.DeserializeObject([IO.File]::ReadAllText((Join-Path $Root "locales/$locale.json")))
    if ($catalog -isnot [System.Collections.IDictionary]) { throw "Locale $locale must be a JSON object." }
}

$work = Join-Path $Root ('build/' + [Guid]::NewGuid().ToString('N'))
$stage = Join-Path $work 'package'
$output = Join-Path $Root 'release'
[void](New-Item -ItemType Directory -Path $stage -Force)
[void](New-Item -ItemType Directory -Path $output -Force)
if ($SkipBuild) {
    $kit = (Resolve-Path -LiteralPath $UpdateKitPath -ErrorAction Stop).Path
    $binary = (Resolve-Path -LiteralPath $BinaryPath -ErrorAction Stop).Path
} else {
    $bunVersion = Read-Checked 'bun' @('--version')
    if ($bunVersion -cne $manifest.bunVersion) { throw "Bun $($manifest.bunVersion) required; found $bunVersion." }
    $source = Join-Path $work 'source'
    Invoke-Checked 'git' @('init', '--quiet', $source)
    Invoke-Checked 'git' @('-C', $source, 'remote', 'add', 'origin', 'https://github.com/can1357/oh-my-pi.git')
    Invoke-Checked 'git' @('-C', $source, 'fetch', '--depth=1', 'origin', $manifest.upstreamCommit)
    Invoke-Checked 'git' @('-C', $source, '-c', 'core.autocrlf=false', '-c', 'core.longpaths=true', 'checkout', '--detach', 'FETCH_HEAD')
    $commit = Read-Checked 'git' @('-C', $source, 'rev-parse', 'HEAD')
    if ($commit -cne $manifest.upstreamCommit) { throw 'Reconstructed upstream commit mismatch.' }
    Invoke-Checked 'git' @('-C', $source, 'apply', '--binary', '--whitespace=nowarn', (Join-Path $Root 'source/omp-language-pack.patch'))
    $sourceLocales = Join-Path $source 'packages/utils/src/locales'
    [void](New-Item -ItemType Directory -Path $sourceLocales -Force)
    foreach ($locale in @('ko', 'en')) {
        Copy-Item -LiteralPath (Join-Path $Root "locales/$locale.json") -Destination (Join-Path $sourceLocales "$locale.json") -Force
    }
    Push-Location $source
    try { Invoke-Checked 'bun' @('install', '--frozen-lockfile', '--ignore-scripts') } finally { Pop-Location }

    $packageName = '@oh-my-pi/pi-natives-win32-x64'
    $packageVersion = $manifest.upstreamVersion
    $nativeManifest = Get-Content -LiteralPath (Join-Path $source 'packages/natives/package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($nativeManifest.version -cne $packageVersion) { throw 'Reconstructed native package version mismatch.' }
    $metadataUrl = 'https://registry.npmjs.org/' + [Uri]::EscapeDataString($packageName) + '/' + $packageVersion
    $metadata = Invoke-RestMethod -Uri $metadataUrl
    if ($metadata.name -cne $packageName -or $metadata.version -cne $packageVersion -or
        $metadata.dist.integrity -cnotmatch '^sha512-([A-Za-z0-9+/]+={0,2})$') { throw 'Invalid exact-version native package metadata.' }
    $expectedIntegrity = $Matches[1]
    $tarballUri = [Uri]$metadata.dist.tarball
    if ($tarballUri.Scheme -cne 'https' -or $tarballUri.Host -cne 'registry.npmjs.org' -or $tarballUri.UserInfo) {
        throw 'Native package tarball must come from HTTPS registry.npmjs.org.'
    }
    $archive = Join-Path $work 'native.tgz'
    Invoke-WebRequest -UseBasicParsing -Uri $tarballUri.AbsoluteUri -OutFile $archive
    $stream = [IO.File]::OpenRead($archive)
    $sha = [Security.Cryptography.SHA512]::Create()
    try { $actualIntegrity = [Convert]::ToBase64String($sha.ComputeHash($stream)) } finally { $sha.Dispose(); $stream.Dispose() }
    if ($actualIntegrity -cne $expectedIntegrity) { throw 'Native package SHA-512 integrity mismatch.' }
    $memberText = Read-Checked 'tar.exe' @('-tf', $archive)
    $members = @($memberText -split '\r?\n')
    $seen = @{}
    foreach ($member in $members) {
        if ($member -cnotmatch '^package/[A-Za-z0-9._/-]+$' -or $member -match '(^|/)\.\.?(/|$)' -or $seen.ContainsKey($member)) {
            throw "Unsafe or duplicate native archive member: $member"
        }
        $seen[$member] = $true
    }
    $packageJson = Join-Path $work 'native-package.json'
    if ($members -cnotcontains 'package/package.json') { throw 'Native archive lacks package.json.' }
    Export-TarMember $archive 'package/package.json' $packageJson
    $package = Get-Content -LiteralPath $packageJson -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($package.name -cne $packageName -or $package.version -cne $packageVersion) { throw 'Native archive package identity mismatch.' }
    $nativeDir = Join-Path $source 'packages/natives/native'
    foreach ($variant in @('baseline', 'modern')) {
        $name = "pi_natives.win32-x64-$variant.node"
        if ($members -cnotcontains "package/$name") {
            if ($variant -eq 'baseline') { throw "Native archive lacks $name." }
            continue
        }
        Export-TarMember $archive "package/$name" (Join-Path $nativeDir $name)
    }
    Push-Location $source
    try { Invoke-Checked 'bun' @('scripts/build-localized.ts') } finally { Pop-Location }
    $kit = Join-Path $work 'update'
    [void](New-Item -ItemType Directory -Path (Join-Path $kit 'scripts') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $kit 'locales') -Force)
    Push-Location $source
    try {
        Invoke-Checked 'bun' @('scripts/reapply-localization.ts', 'create', '--source', $source, '--base', $manifest.upstreamCommit, '--output', (Join-Path $kit 'reference.json'))
        Invoke-Checked 'bun' @('build', 'scripts/update-localized.ts', '--target=bun', '--outfile', (Join-Path $kit 'update-localized.js'))
    } finally { Pop-Location }
    Copy-Item -LiteralPath (Get-Command bun -ErrorAction Stop).Source -Destination (Join-Path $kit 'bun.exe')
    foreach ($name in @('update-localized.ts', 'reapply-localization.ts', 'build-localized.ts')) {
        Copy-Item -LiteralPath (Join-Path $source "scripts/$name") -Destination (Join-Path $kit "scripts/$name")
    }
    foreach ($locale in @('ko', 'en')) {
        Copy-Item -LiteralPath (Join-Path $Root "locales/$locale.json") -Destination (Join-Path $kit "locales/$locale.json")
    }
    Copy-Item -LiteralPath (Join-Path $source 'packages/coding-agent/src/cli/localized-update.ts') -Destination (Join-Path $kit 'scripts/localized-update.ts')
    $binary = Join-Path $source 'packages/coding-agent/binaries/omp-windows-x64.exe'
}

# Package only this explicit allowlist, never an installed directory or developer metadata.
Copy-Item -LiteralPath $binary -Destination (Join-Path $stage 'omp.exe')
[void](New-Item -ItemType Directory -Path (Join-Path $stage 'locales'))
foreach ($relative in @('locales/ko.json', 'locales/en.json', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $Root $relative) -Destination (Join-Path $stage $relative)
}
$kitFiles = @('bun.exe', 'update-localized.js', 'reference.json', 'scripts/update-localized.ts', 'scripts/reapply-localization.ts', 'scripts/build-localized.ts', 'scripts/localized-update.ts', 'locales/ko.json', 'locales/en.json')
foreach ($relative in $kitFiles) {
    $destination = Join-Path $stage "update/$relative"
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
    Copy-Item -LiteralPath (Join-Path $kit $relative) -Destination $destination
}
$packageFiles = @('omp.exe', 'locales/ko.json', 'locales/en.json', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'README.md') + @($kitFiles | ForEach-Object { "update/$_" })
$environmentKeys = @('OMP_LANG', 'OMP_LOCALE_DIR', 'PI_CODING_AGENT_DIR', 'PI_PROFILE')
$savedEnvironment = @{}
foreach ($key in $environmentKeys) { $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
Push-Location $work
try {
    $env:OMP_LOCALE_DIR = Join-Path $stage 'locales'
    [Environment]::SetEnvironmentVariable('PI_PROFILE', $null, 'Process')
    foreach ($locale in @('en', 'ko')) {
        $env:OMP_LANG = $locale
        $env:PI_CODING_AGENT_DIR = Join-Path $work "smoke-$locale"
        $reported = Read-Checked (Join-Path $stage 'omp.exe') @('--version')
        if ($reported -cne "omp/$($manifest.upstreamVersion)") { throw "Binary version mismatch: $reported" }
        $help = Read-Checked (Join-Path $stage 'omp.exe') @('--help')
        if ($help.Length -lt 100 -or -not $help.Contains('--model')) { throw "Incomplete $locale help." }
        $smoke = Read-Checked (Join-Path $stage 'omp.exe') @('--smoke-test')
        if (-not $smoke.Contains('smoke-test: ok')) { throw "Binary $locale smoke did not complete." }
    }
    # A tiny probe proves that this is the external-language-pack fork, not an official binary.
    $probe = Join-Path $work 'probe-locales'
    [void](New-Item -ItemType Directory -Path $probe)
    [IO.File]::WriteAllText((Join-Path $probe 'ko.json'), '{"USAGE":"RELEASE_LANGUAGE_PACK_PROBE"}', $Utf8)
    $env:OMP_LOCALE_DIR = $probe
    $env:OMP_LANG = 'en'
    $english = Read-Checked (Join-Path $stage 'omp.exe') @('--help')
    $env:OMP_LANG = 'ko'
    $korean = Read-Checked (Join-Path $stage 'omp.exe') @('--help')
    if (-not $english.Contains('USAGE') -or $english.Contains('RELEASE_LANGUAGE_PACK_PROBE') -or -not $korean.Contains('RELEASE_LANGUAGE_PACK_PROBE')) {
        throw 'Binary did not honor the external language pack.'
    }
} finally {
    Pop-Location
    foreach ($key in $environmentKeys) { [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process') }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $output $manifest.archive
$tempZip = Join-Path $work $manifest.archive
$zip = [IO.Compression.ZipFile]::Open($tempZip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relative in $packageFiles) {
        $entry = $zip.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $inputFile = [IO.File]::OpenRead((Join-Path $stage $relative))
        try {
            $outputEntry = $entry.Open()
            try { $inputFile.CopyTo($outputEntry) } finally { $outputEntry.Dispose() }
        } finally { $inputFile.Dispose() }
    }
} finally { $zip.Dispose() }
$checksum = (Get-FileHash -LiteralPath $tempZip -Algorithm SHA256).Hash.ToLowerInvariant()
$installer = [IO.File]::ReadAllText((Join-Path $Root 'install.ps1'))
$marker = '$DefaultRepository = '''' # RELEASE_REPOSITORY'
if (($installer.Split([string[]]@($marker), [StringSplitOptions]::None)).Count -ne 2) { throw 'Installer repository stamp marker is missing or ambiguous.' }
if ($Repository) {
    $installer = $installer.Replace($marker, ('$DefaultRepository = ''' + $Repository + ''' # RELEASE_REPOSITORY'))
} else {
    Write-Warning 'release/install.ps1 is unbound: online installation requires -Repository owner/name. Tag builds bind GITHUB_REPOSITORY automatically.'
}
Move-Item -LiteralPath $tempZip -Destination $zipPath -Force
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS'), "$checksum  $($manifest.archive)`n", $Utf8)
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $output 'release.json') -Force
[IO.File]::WriteAllText((Join-Path $output 'install.ps1'), $installer, $Utf8)
Write-Host "Created $zipPath"
Write-Host "SHA256 $checksum"
Write-Host 'Release assets: ZIP, SHA256SUMS, release.json, install.ps1 (all in release/).'

[CmdletBinding()]
param(
    [string]$Repository,
    [string]$Version,
    [string]$InstallDir,
    [switch]$NoPath,
    [string]$ArchivePath,
    [string]$ChecksumPath,
    [string]$ManifestPath
)

$DefaultRepository = '' # RELEASE_REPOSITORY

# Keep functions, strict mode, and temporary preferences out of an irm | iex caller's scope.
& {
    param($Options, [string]$PublishedRepository)
    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    function Assert-PlainPath([string]$Path) {
        $cursor = [IO.Path]::GetFullPath($Path)
        while ($cursor) {
            if (Test-Path -LiteralPath $cursor) {
                $item = Get-Item -LiteralPath $cursor -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Reparse points are not permitted in the installation path: $cursor"
                }
            }
            $parent = [IO.Path]::GetDirectoryName($cursor)
            if ($parent -eq $cursor) { break }
            $cursor = $parent
        }
    }

    function Test-Within([string]$Path, [string]$Root) {
        $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
        return $Path.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
            $Path.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    }

    function Read-ReleaseManifest([string]$Path) {
        $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($field in @('version', 'upstreamVersion', 'upstreamCommit', 'bunVersion', 'platform', 'archive')) {
            if (-not ($manifest.PSObject.Properties.Name -contains $field) -or
                $manifest.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($manifest.$field)) {
                throw "release.json is missing a string field: $field"
            }
        }
        if ($manifest.version -cnotmatch '^(\d+\.\d+\.\d+)-ko\.\d+$') {
            throw 'release.json version must have the form 18.13.0-ko.1.'
        }
        $upstream = $Matches[1]
        if ($manifest.upstreamVersion -cne $upstream -or
            $manifest.upstreamCommit -cnotmatch '^[a-fA-F0-9]{40}$' -or
            $manifest.bunVersion -cnotmatch '^\d+\.\d+\.\d+$' -or
            $manifest.platform -cne 'windows-x64' -or
            $manifest.archive -cne "omp-korean-$($manifest.version)-windows-x64.zip") {
            throw 'release.json has inconsistent version, platform, build metadata, or archive name.'
        }
        return $manifest
    }

    function Assert-ArchiveChecksum([string]$Archive, [string]$Checksums, [string]$Name) {
        if ([IO.Path]::GetFileName($Archive) -cne $Name) {
            throw "Archive filename must be exactly $Name."
        }
        $expected = $null
        foreach ($line in [IO.File]::ReadAllLines($Checksums)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -cnotmatch '^([a-fA-F0-9]{64}) [ *](.+)$') {
                throw 'SHA256SUMS contains an invalid checksum entry.'
            }
            if ($Matches[2] -ceq $Name) {
                if ($null -ne $expected) { throw "Duplicate SHA256SUMS entry for $Name." }
                $expected = $Matches[1]
            }
        }
        if ($null -eq $expected) { throw "SHA256SUMS has no exact entry for $Name." }
        $actual = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
        if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Archive SHA256 verification failed. Nothing has been installed.'
        }
    }

    function Expand-VerifiedArchive([string]$Archive, [string]$Destination, [string[]]$Allowed) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
        try {
            $seen = @{}
            foreach ($entry in $zip.Entries) {
                $name = $entry.FullName
                if ($seen.ContainsKey($name)) { throw "Duplicate ZIP entry: $name" }
                $seen[$name] = $true
                $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
                if ($name -ceq 'locales/') {
                    if ($entry.Length -ne 0 -or ($mode -ne 0 -and $mode -ne 0x4000)) {
                        throw 'Invalid ZIP locales directory entry.'
                    }
                    continue
                }
                if (-not ($Allowed -ccontains $name) -or ($mode -ne 0 -and $mode -ne 0x8000) -or
                    (($entry.ExternalAttributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0)) {
                    throw "Unsafe or unexpected ZIP entry: $name"
                }
            }
            foreach ($name in $Allowed) {
                if (-not $seen.ContainsKey($name)) { throw "ZIP is missing $name." }
            }
            # Only explicit allowlisted regular files are ever written, never archive-selected paths.
            foreach ($name in $Allowed) {
                $destinationFile = Join-Path $Destination $name
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationFile)) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry($name), $destinationFile, $false)
            }
        } finally {
            $zip.Dispose()
        }
    }

    function Invoke-Candidate([string]$Binary, [string]$Argument, [string]$Language, [string]$Locales, [string]$Work) {
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $Binary
        $start.Arguments = $Argument
        $start.WorkingDirectory = $Work
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
        $start.EnvironmentVariables['OMP_LANG'] = $Language
        $start.EnvironmentVariables['OMP_LOCALE_DIR'] = $Locales
        $start.EnvironmentVariables['PI_CODING_AGENT_DIR'] = Join-Path $Work "agent-$Language"
        $start.EnvironmentVariables.Remove('PI_PROFILE')
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $start
        try {
            if (-not $process.Start()) { throw 'Could not start the verified candidate.' }
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(120000)) {
                $process.Kill()
                $process.WaitForExit()
                throw "Candidate $Argument timed out."
            }
            $text = $stdout.GetAwaiter().GetResult()
            $errorText = $stderr.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0) {
                # Candidate diagnostics can contain local paths; do not echo them into download logs.
                throw "Candidate $Argument failed for $Language (exit $($process.ExitCode)). Check the selected locale pack."
            }
            return $text
        } finally {
            $process.Dispose()
        }
    }

    function Assert-Candidate([string]$Stage, $Manifest, [string]$Work) {
        $binary = Join-Path $Stage 'omp.exe'
        $locales = Join-Path $Stage 'locales'
        foreach ($language in @('en', 'ko')) {
            $reported = (Invoke-Candidate $binary '--version' $language $locales $Work).Trim()
            if ($reported -cne "omp/$($Manifest.upstreamVersion)") {
                throw 'Candidate version does not match release.json.'
            }
            $help = Invoke-Candidate $binary '--help' $language $locales $Work
            if ($help.Trim().Length -lt 100 -or -not $help.Contains('--model')) {
                throw "Candidate $language help is incomplete."
            }
            $smoke = Invoke-Candidate $binary '--smoke-test' $language $locales $Work
            if (-not $smoke.Contains('smoke-test: ok')) { throw "Candidate $language smoke test did not complete." }
        }
        $probe = Join-Path $Work 'probe-locales'
        [IO.Directory]::CreateDirectory($probe) | Out-Null
        [IO.File]::WriteAllText((Join-Path $probe 'ko.json'), '{"USAGE":"OMP_INSTALL_LANGUAGE_PROBE"}', (New-Object Text.UTF8Encoding($false)))
        $english = Invoke-Candidate $binary '--help' 'en' $probe $Work
        $korean = Invoke-Candidate $binary '--help' 'ko' $probe $Work
        if (-not $english.Contains('USAGE') -or $english.Contains('OMP_INSTALL_LANGUAGE_PROBE') -or
            -not $korean.Contains('OMP_INSTALL_LANGUAGE_PROBE')) {
            throw 'Candidate did not honor external Korean packs and English fallback.'
        }
    }

    function Get-PrependedPath([string]$OldPath, [string]$Directory) {
        $parts = New-Object 'System.Collections.Generic.List[string]'
        $parts.Add($Directory)
        foreach ($part in ($OldPath -split ';')) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $comparison = [Environment]::ExpandEnvironmentVariables($part.Trim().Trim('"')).TrimEnd('\', '/')
            if (-not $comparison.Equals($Directory, [StringComparison]::OrdinalIgnoreCase)) { $parts.Add($part) }
        }
        return ($parts -join ';')
    }

    function Send-EnvironmentChange {
        if (-not ('OmpKoreanInstaller.EnvironmentBroadcast' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace OmpKoreanInstaller {
    public static class EnvironmentBroadcast {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam,
            string lParam, uint flags, uint timeout, out UIntPtr result);
    }
}
'@
        }
        $result = [UIntPtr]::Zero
        # Explorer may be absent (SSH/CI); the registry remains authoritative for new logins.
        [OmpKoreanInstaller.EnvironmentBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x001a,
            [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result) | Out-Null
    }

    $repository = [string]$Options['Repository']
    if ([string]::IsNullOrWhiteSpace($repository)) { $repository = $PublishedRepository }
    $version = [string]$Options['Version']
    $offlineCount = 0
    foreach ($name in @('ArchivePath', 'ChecksumPath', 'ManifestPath')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Options[$name])) { $offlineCount++ }
    }
    if ($offlineCount -ne 0 -and $offlineCount -ne 3) {
        throw 'Offline installation requires -ArchivePath, -ChecksumPath, and -ManifestPath together.'
    }
    $offline = $offlineCount -eq 3
    if (-not $offline -and [string]::IsNullOrWhiteSpace($repository)) {
        throw 'Specify -Repository owner/name for your published GitHub distribution, or supply all three offline artifact paths. The source installer has no default repository.'
    }
    if ($repository -and $repository -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$') {
        throw '-Repository must be a GitHub owner/name, not a URL.'
    }
    if ($version -and $version -cne 'latest' -and $version -cnotmatch '^v?\d+\.\d+\.\d+-ko\.\d+$') {
        throw '-Version must be latest or a release version such as 18.13.0-ko.1.'
    }
    $architecture = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $architecture = $env:PROCESSOR_ARCHITEW6432 }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $architecture -ne 'AMD64') {
        throw 'This package requires Windows x64 (AMD64).'
    }
    $target = [string]$Options['InstallDir']
    if ([string]::IsNullOrWhiteSpace($target)) {
        if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is unavailable; supply -InstallDir.' }
        $target = Join-Path $env:LOCALAPPDATA 'omp-korean'
    }
    $target = [IO.Path]::GetFullPath($target).TrimEnd('\', '/')
    if (-not [IO.Path]::IsPathRooted($target) -or $target.StartsWith('\\') -or $target -match ';' -or
        [string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($target))) {
        throw 'Choose a local, non-root installation directory without semicolons.'
    }
    foreach ($root in @($env:LOCALAPPDATA, $env:USERPROFILE, $env:APPDATA, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root -and $target.Equals([IO.Path]::GetFullPath($root).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Choose a dedicated installation directory, not a profile or system root.'
        }
    }
    $forbidden = @()
    if ($env:LOCALAPPDATA) { $forbidden += (Join-Path $env:LOCALAPPDATA 'omp') }
    if ($env:USERPROFILE) {
        $forbidden += (Join-Path $env:USERPROFILE '.omp')
        $forbidden += (Join-Path $env:USERPROFILE '.pi')
        $forbidden += (Join-Path $env:USERPROFILE '.local\bin')
    }
    foreach ($directory in $forbidden) {
        if (Test-Within $target $directory) { throw "Choose a separate directory, not an official binary or user-state directory: $directory" }
    }
    Assert-PlainPath $target
    if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath $target -PathType Container)) {
        throw 'InstallDir is not a directory.'
    }
    if (Test-Path -LiteralPath (Join-Path $target 'omp-localized.json')) {
        throw 'This is a developer-managed localized install (omp-localized.json exists). Choose another directory; this installer will not overwrite it.'
    }
    $allowed = @('omp.exe', 'locales/ko.json', 'locales/en.json', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'README.md')
    foreach ($name in $allowed) {
        $path = Join-Path $target $name
        Assert-PlainPath $path
        if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Expected an ordinary file at $path."
        }
    }
    $parent = [IO.Path]::GetDirectoryName($target)
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $work = Join-Path $parent ('.omp-korean-install-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $oldTls = [Net.ServicePointManager]::SecurityProtocol
    $userKey = $null
    $keepRecovery = $false
    try {
        if ($offline) {
            $sourceArchive = Get-Item -LiteralPath $Options['ArchivePath'] -Force
            $sourceChecksums = Get-Item -LiteralPath $Options['ChecksumPath'] -Force
            $sourceManifest = Get-Item -LiteralPath $Options['ManifestPath'] -Force
            foreach ($item in @($sourceArchive, $sourceChecksums, $sourceManifest)) {
                if ($item.PSIsContainer) { throw "Artifact is not a file: $($item.FullName)" }
            }
            $archive = Join-Path $work $sourceArchive.Name
            $checksums = Join-Path $work 'SHA256SUMS'
            $manifestFile = Join-Path $work 'release.json'
            [IO.File]::Copy($sourceArchive.FullName, $archive, $false)
            [IO.File]::Copy($sourceChecksums.FullName, $checksums, $false)
            [IO.File]::Copy($sourceManifest.FullName, $manifestFile, $false)
        } else {
            [Net.ServicePointManager]::SecurityProtocol = $oldTls -bor [Net.SecurityProtocolType]::Tls12
            $headers = @{ 'User-Agent' = 'omp-korean-installer'; 'Accept' = 'application/vnd.github+json' }
            $releaseEndpoint = "https://api.github.com/repos/$repository/releases/latest"
            if ($version -and $version -cne 'latest') {
                $tag = 'v' + $version.TrimStart('v')
                $releaseEndpoint = "https://api.github.com/repos/$repository/releases/tags/$tag"
            }
            $release = Invoke-RestMethod -Uri $releaseEndpoint -Headers $headers -TimeoutSec 60
            if ($release.draft -or -not $release.tag_name) { throw 'GitHub did not return a published release.' }
            function Get-ReleaseAsset([string]$Name) {
                $matches = @($release.assets | Where-Object { $_.name -ceq $Name })
                if ($matches.Count -ne 1) { throw "Release must contain exactly one $Name asset." }
                $url = [string]$matches[0].browser_download_url
                $prefix = "https://github.com/$repository/releases/download/$($release.tag_name)/"
                if (-not $url.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
                    $url.Substring($prefix.Length) -cne $Name) {
                    throw "Unexpected download URL for $Name."
                }
                $destination = Join-Path $work $Name
                Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $headers -OutFile $destination -TimeoutSec 600
                return $destination
            }
            $manifestFile = Get-ReleaseAsset 'release.json'
        }
        $manifest = Read-ReleaseManifest $manifestFile
        if ($version -and $version -cne 'latest' -and $version.TrimStart('v') -cne $manifest.version) {
            throw 'Requested version does not match release.json.'
        }
        if (-not $offline) {
            if ($release.tag_name -cne "v$($manifest.version)" -and $release.tag_name -cne $manifest.version) {
                throw 'GitHub release tag does not match release.json.'
            }
            $checksums = Get-ReleaseAsset 'SHA256SUMS'
            $archive = Get-ReleaseAsset $manifest.archive
        }
        Assert-ArchiveChecksum $archive $checksums $manifest.archive
        $stage = Join-Path $work 'candidate'
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        Expand-VerifiedArchive $archive $stage $allowed
        $customPack = Join-Path $target 'locales/ko.json'
        $preservePack = Test-Path -LiteralPath $customPack -PathType Leaf
        if ($preservePack) { [IO.File]::Copy($customPack, (Join-Path $stage 'locales/ko.json'), $true) }
        Assert-Candidate $stage $manifest $work

        $backup = Join-Path $work 'backup'
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        $saved = New-Object 'System.Collections.Generic.List[string]'
        $promoted = New-Object 'System.Collections.Generic.List[string]'
        $createdTarget = -not (Test-Path -LiteralPath $target)
        $createdLocales = -not (Test-Path -LiteralPath (Join-Path $target 'locales'))
        $oldProcessPath = $env:Path
        $pathAttempted = $false
        $oldUserPath = $null
        $oldUserPathKind = [Microsoft.Win32.RegistryValueKind]::String
        $hadUserPath = $false
        try {
            Assert-PlainPath $target
            if (Test-Path -LiteralPath (Join-Path $target 'omp-localized.json')) { throw 'Developer metadata appeared during installation; refusing promotion.' }
            foreach ($name in $allowed) {
                # A customization is never moved, normalized, or rewritten during a reinstall.
                if ($preservePack -and $name -ceq 'locales/ko.json') { continue }
                $destination = Join-Path $target $name
                Assert-PlainPath $destination
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
                if (Test-Path -LiteralPath $destination) {
                    $savedFile = Join-Path $backup $name
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($savedFile)) | Out-Null
                    [IO.File]::Move($destination, $savedFile)
                    $saved.Add($name)
                }
                [IO.File]::Move((Join-Path $stage $name), $destination)
                $promoted.Add($name)
            }
            if (-not $Options['NoPath']) {
                $userKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
                $hadUserPath = $userKey.GetValueNames() -contains 'Path'
                if ($hadUserPath) {
                    $oldUserPath = [string]$userKey.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    $oldUserPathKind = $userKey.GetValueKind('Path')
                    if ($oldUserPathKind -ne [Microsoft.Win32.RegistryValueKind]::String -and
                        $oldUserPathKind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) { throw 'User PATH has an unsupported registry value type.' }
                }
                $pathAttempted = $true
                $userKey.SetValue('Path', (Get-PrependedPath $oldUserPath $target), $oldUserPathKind)
                $env:Path = Get-PrependedPath $oldProcessPath $target
                Send-EnvironmentChange
            }
        } catch {
            $failure = $_
            $rollbackErrors = New-Object 'System.Collections.Generic.List[string]'
            if ($pathAttempted) {
                $env:Path = $oldProcessPath
                try {
                    if ($hadUserPath) { $userKey.SetValue('Path', $oldUserPath, $oldUserPathKind) }
                    else { $userKey.DeleteValue('Path', $false) }
                    Send-EnvironmentChange
                } catch { $rollbackErrors.Add('User PATH: ' + $_.Exception.Message) }
            }
            for ($index = $promoted.Count - 1; $index -ge 0; $index--) {
                try { [IO.File]::Delete((Join-Path $target $promoted[$index])) }
                catch { $rollbackErrors.Add($promoted[$index] + ': ' + $_.Exception.Message) }
            }
            for ($index = $saved.Count - 1; $index -ge 0; $index--) {
                $name = $saved[$index]
                try { [IO.File]::Move((Join-Path $backup $name), (Join-Path $target $name)) }
                catch { $rollbackErrors.Add($name + ': ' + $_.Exception.Message) }
            }
            if ($createdLocales) {
                try { [IO.Directory]::Delete((Join-Path $target 'locales'), $false) } catch { }
            }
            if ($createdTarget) {
                try { [IO.Directory]::Delete($target, $false) } catch { }
            }
            if ($rollbackErrors.Count -gt 0) {
                # Do not delete recoverable originals if a lock/permission change prevents rollback.
                $keepRecovery = $true
                throw "Installation failed: $($failure.Exception.Message) Rollback needs attention; originals are in $backup. $($rollbackErrors -join '; ')"
            }
            throw $failure
        }
        Write-Host "Installed omp Korean $($manifest.version) in $target"
        if ($preservePack) { Write-Host 'Preserved existing locales/ko.json; missing keys fall back to English.' }
        if (-not $Options['NoPath']) {
            Write-Host 'User and current-process PATH updated. Open a new terminal, especially after irm | iex, then run Get-Command omp.'
        }
        Write-Host 'Run omp update --check to check compatibility. omp update switches to the official version when no matching Korean build is available; reinstall this distribution to return to Korean.'
    } finally {
        if ($null -ne $userKey) { $userKey.Dispose() }
        [Net.ServicePointManager]::SecurityProtocol = $oldTls
        if (-not $keepRecovery) {
            if (Test-Path -LiteralPath $work) {
                Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
} $PSBoundParameters $DefaultRepository

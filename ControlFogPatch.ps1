#requires -Version 5.1

[CmdletBinding()]
param(
    [string] $GameFolder,
    [ValidateSet('Install', 'Restore', 'Status')]
    [string] $Action = 'Install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ByteHash {
    param([byte[]] $Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Expand-ShaderDelta {
    param([byte[]] $Before, $Entry)

    $result = [IO.MemoryStream]::new()
    try {
        $cursor = 0
        foreach ($hunk in $Entry.hunks) {
            $offset = [int] $hunk.offset
            $removed = [int] $hunk.remove
            if ($offset -lt $cursor -or $removed -lt 0 -or ([long] $offset + $removed) -gt $Before.Length) {
                throw "Invalid delta range in $($Entry.name)."
            }
            $result.Write($Before, $cursor, $offset - $cursor)
            $inserted = [Convert]::FromBase64String([string] $hunk.insert)
            $result.Write($inserted, 0, $inserted.Length)
            $cursor = $offset + $removed
        }
        $result.Write($Before, $cursor, $Before.Length - $cursor)
        if ($result.Length -ne $Entry.patchedSize) {
            throw "Incorrect patched size for $($Entry.name)."
        }
        return ,($result.ToArray())
    } finally {
        $result.Dispose()
    }
}

function Replace-ShaderFile {
    param(
        [string] $Path,
        [byte[]] $Bytes,
        [string] $ExpectedHash,
        [string] $NewBackup
    )

    $stage = Join-Path ([IO.Path]::GetDirectoryName($Path)) ('.control-fog-' + [Guid]::NewGuid() + '.tmp')
    try {
        [IO.File]::WriteAllBytes($stage, $Bytes)
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) {
            throw "The shader changed during the operation. $Path"
        }

        if ($NewBackup) {
            if (Test-Path -LiteralPath $NewBackup) {
                throw "A backup appeared during the operation. $NewBackup"
            }
            [IO.File]::Replace($stage, $Path, $NewBackup)
        } else {
            [IO.File]::Replace($stage, $Path, [NullString]::Value)
        }
    } finally {
        if ([IO.File]::Exists($stage)) {
            [IO.File]::Delete($stage)
        }
    }
}

if (-not $GameFolder) {
    if (Test-Path -LiteralPath (Join-Path (Get-Location).Path 'Control_DX11.exe') -PathType Leaf) {
        $GameFolder = (Get-Location).Path
    } else {
        $GameFolder = Read-Host 'Enter the folder containing Control_DX11.exe'
    }
}
if ([string]::IsNullOrWhiteSpace($GameFolder)) {
    throw 'Enter the Control installation folder or pass -GameFolder.'
}

$root = Get-Item -LiteralPath $GameFolder.Trim().Trim('"', "'")
if (-not $root.PSIsContainer -or -not (Test-Path -LiteralPath (Join-Path $root.FullName 'Control_DX11.exe') -PathType Leaf)) {
    throw 'Select the game folder containing Control_DX11.exe.'
}

$shaderDir = (Get-Item -LiteralPath (Join-Path $root.FullName 'data\shaders\build\pc_dx11')).FullName
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'patch-data.json') -Raw | ConvertFrom-Json
$expectedNames = @('volumetriclight.obj', 'deferredlight_volume.obj')
if ($manifest.schema -ne 1 -or @($manifest.files).Count -ne $expectedNames.Count) {
    throw 'The patch manifest has an unsupported format.'
}
foreach ($name in $expectedNames) {
    if (@($manifest.files | Where-Object { $_.name -ceq $name }).Count -ne 1) {
        throw "The patch manifest must contain exactly one entry for $name."
    }
}

$lockHash = Get-ByteHash ([Text.Encoding]::UTF8.GetBytes($shaderDir.ToUpperInvariant()))
$mutex = [Threading.Mutex]::new($false, "Local\ControlDX11FogFix-$lockHash")
$locked = $false
try {
    try {
        $locked = $mutex.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        $locked = $true
    }
    if (-not $locked) {
        throw 'Another copy of the patch tool is already working on this installation.'
    }
    if ($Action -ne 'Status' -and (Get-Process -Name Control,Control_DX11,Control_DX12 -ErrorAction SilentlyContinue)) {
        throw 'Close Control before installing or restoring the shaders.'
    }

    $plan = [Collections.Generic.List[object]]::new()
    $issues = [Collections.Generic.List[string]]::new()
    foreach ($entry in $manifest.files) {
        $path = Join-Path $shaderDir $entry.name
        $backup = "$path.pre-codex"
        $before = [IO.File]::ReadAllBytes($path)
        $beforeHash = Get-ByteHash $before

        if ($beforeHash -eq $entry.cleanSha256) {
            $state = 'original'
        } elseif ($beforeHash -eq $entry.patchedSha256) {
            $state = 'patched'
        } else {
            $state = 'unrecognized'
            $issues.Add("Unsupported or modified shader $($entry.name) has SHA-256 $beforeHash.")
        }
        Write-Host "$($entry.name) - $state"

        $backupExists = Test-Path -LiteralPath $backup
        $backupBytes = $null
        if ($backupExists) {
            $backupBytes = [IO.File]::ReadAllBytes($backup)
            if ((Get-ByteHash $backupBytes) -ne $entry.cleanSha256) {
                $issues.Add("Backup $backup has an unexpected SHA-256.")
                continue
            }
        }
        if ($state -eq 'patched' -and -not $backupExists) {
            Write-Host "  Original backup missing for $($entry.name)."
            if ($Action -ne 'Status') {
                $issues.Add("Original backup missing for $($entry.name).")
                continue
            }
        }
        if ($Action -eq 'Install' -and $state -eq 'original') {
            if ($before.Length -ne $entry.cleanSize) {
                throw "Incorrect original size for $($entry.name)."
            }
            $after = Expand-ShaderDelta -Before $before -Entry $entry
            $afterHash = $entry.patchedSha256
            $newBackup = if ($backupExists) { '' } else { $backup }
        } elseif ($Action -eq 'Restore' -and $state -eq 'patched') {

            $after = $backupBytes
            $afterHash = $entry.cleanSha256
            $newBackup = ''
        } else {

            continue
        }

        if ((Get-ByteHash $after) -ne $afterHash) {
            throw "Output SHA-256 verification failed for $($entry.name)."
        }
        $plan.Add([pscustomobject]@{
            Path = $path
            Before = $before
            After = $after
            BeforeHash = $beforeHash
            AfterHash = $afterHash
            NewBackup = $newBackup
        })
    }

    if ($issues.Count) {
        throw ($issues -join [Environment]::NewLine)
    }
    if ($Action -eq 'Status') {
        return
    }
    if ($plan.Count -eq 0) {
        Write-Host 'Both shaders are already in the requested state.'
        return
    }

    $committed = [Collections.Generic.List[object]]::new()
    try {
        foreach ($item in $plan) {
            Replace-ShaderFile -Path $item.Path -Bytes $item.After -ExpectedHash $item.BeforeHash -NewBackup $item.NewBackup
            $committed.Add($item)
            if ((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.AfterHash) {
                throw "On-disk verification failed for $($item.Path)."
            }
            if ($item.NewBackup -and (Get-FileHash -LiteralPath $item.NewBackup -Algorithm SHA256).Hash -ne $item.BeforeHash) {
                throw "Backup verification failed for $($item.NewBackup)."
            }
        }
    } catch {
        $failure = $_
        $rollbackIssues = [Collections.Generic.List[string]]::new()
        for ($i = $committed.Count - 1; $i -ge 0; $i--) {
            $item = $committed[$i]
            try {
                Replace-ShaderFile -Path $item.Path -Bytes $item.Before -ExpectedHash $item.AfterHash
            } catch {
                $rollbackIssues.Add($_.Exception.Message)
            }
        }
        if ($rollbackIssues.Count) {
            throw "Patch operation failed. $($failure.Exception.Message) Rollback needs attention. $($rollbackIssues -join ' ')"
        }
        throw $failure
    }

    if ($Action -eq 'Install') {
        Write-Host 'DX11 fog fix installed. Launch Control in DirectX 11.'
    } else {
        Write-Host 'Original DX11 shaders restored.'
    }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

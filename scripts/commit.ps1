[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$MessageBase64,

    [string]$Repository = ".",

    [string]$GitExecutable = "git"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $GitExecutable -C $WorkingDirectory --no-pager @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $details = ($output | Out-String).Trim()
        throw "git $($Arguments -join ' ') failed with exit code $exitCode.`n$details"
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = @($output)
    }
}

function Get-FirstLine {
    param([object[]]$Output)

    if ($Output.Count -eq 0) {
        return ""
    }

    return $Output[0].ToString().Trim()
}

function Resolve-GitPath {
    param(
        [string]$RepositoryRoot,
        [string]$GitPath
    )

    if ([System.IO.Path]::IsPathRooted($GitPath)) {
        return $GitPath
    }

    return Join-Path $RepositoryRoot $GitPath
}

function Test-PathWithin {
    param(
        [string]$Root,
        [string]$Candidate
    )

    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]"\/")
    $candidatePath = [System.IO.Path]::GetFullPath($Candidate).TrimEnd([char[]]"\/")
    $comparison = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }

    if ($candidatePath.Equals($rootPath, $comparison)) {
        return $true
    }

    $rootPrefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar
    return $candidatePath.StartsWith($rootPrefix, $comparison)
}

function New-ExternalTempDirectory {
    param([string]$RepositoryRoot)

    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $roamingAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    $candidateRoots = @(
        [System.IO.Path]::GetTempPath(),
        $(if ($localAppData) { Join-Path $localAppData "Codex\git-commit-helper" }),
        $(if ($roamingAppData) { Join-Path $roamingAppData "Codex\git-commit-helper" })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $lastError = $null
    foreach ($candidateRoot in $candidateRoots) {
        $candidatePath = Join-Path $candidateRoot ("codex-git-commit-{0}" -f [Guid]::NewGuid().ToString("N"))
        if (Test-PathWithin -Root $RepositoryRoot -Candidate $candidatePath) {
            continue
        }

        try {
            [System.IO.Directory]::CreateDirectory($candidatePath) | Out-Null
            return [System.IO.Path]::GetFullPath($candidatePath)
        }
        catch {
            $lastError = $_.Exception
        }
    }

    $details = if ($lastError) { " $($lastError.Message)" } else { "" }
    throw "Could not create a temporary directory outside the repository.$details"
}

function Get-CommitParentInfo {
    param(
        [string]$RepositoryRoot,
        [string]$Commit
    )

    $parentsResult = Invoke-GitCapture -WorkingDirectory $RepositoryRoot -Arguments @("rev-list", "--parents", "-n", "1", $Commit)
    $tokens = @((Get-FirstLine $parentsResult.Output) -split '\s+' | Where-Object { $_ })
    if ($tokens.Count -eq 0) {
        throw "Could not read parent information for commit $Commit."
    }

    return [PSCustomObject]@{
        Commit  = $tokens[0]
        Parents = [string[]]@(if ($tokens.Count -gt 1) { $tokens[1..($tokens.Count - 1)] })
    }
}

function Restore-IdentifiedCommit {
    param(
        [string]$RepositoryRoot,
        [string]$CreatedCommit,
        [AllowNull()]
        [string]$HeadBefore,
        [AllowNull()]
        [string]$SymbolicHead
    )

    if (-not $SymbolicHead) {
        throw "Automatic rollback is disabled for detached HEAD. No automatic rollback was attempted. Do not retry commit; inspect the repository."
    }

    $currentSymbolicResult = Invoke-GitCapture -WorkingDirectory $RepositoryRoot -Arguments @("symbolic-ref", "-q", "HEAD") -AllowFailure
    $currentSymbolicHead = if ($currentSymbolicResult.ExitCode -eq 0) { Get-FirstLine $currentSymbolicResult.Output } else { $null }
    if ($currentSymbolicHead -ne $SymbolicHead) {
        $displayCurrent = if ($currentSymbolicHead) { $currentSymbolicHead } else { "<detached>" }
        throw "The symbolic HEAD moved from '$SymbolicHead' to '$displayCurrent'. No automatic rollback was attempted. Do not retry commit; inspect the repository."
    }

    $currentHeadResult = Invoke-GitCapture -WorkingDirectory $RepositoryRoot -Arguments @("rev-parse", "--verify", "HEAD") -AllowFailure
    $currentHead = if ($currentHeadResult.ExitCode -eq 0) { Get-FirstLine $currentHeadResult.Output } else { $null }
    if ($currentHead -ne $CreatedCommit) {
        throw "HEAD moved from the identified commit $CreatedCommit to $currentHead. No automatic rollback was attempted. Do not retry commit; inspect the repository."
    }

    try {
        if ($HeadBefore) {
            Invoke-GitCapture -WorkingDirectory $RepositoryRoot -Arguments @("update-ref", $SymbolicHead, $HeadBefore, $CreatedCommit) | Out-Null
            return
        }

        Invoke-GitCapture -WorkingDirectory $RepositoryRoot -Arguments @("update-ref", "-d", $SymbolicHead, $CreatedCommit) | Out-Null
    }
    catch {
        throw "Could not atomically restore HEAD after rejecting commit $CreatedCommit. HEAD may have moved concurrently. Do not retry commit; inspect the repository. $($_.Exception.Message)"
    }
}

$repositoryPath = (Resolve-Path -LiteralPath $Repository).Path
$rootResult = Invoke-GitCapture -WorkingDirectory $repositoryPath -Arguments @("rev-parse", "--show-toplevel")
$repositoryRoot = Get-FirstLine $rootResult.Output

if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw "Could not resolve the Git repository root."
}

$blockedStateNames = @(
    "MERGE_HEAD",
    "CHERRY_PICK_HEAD",
    "REVERT_HEAD",
    "rebase-merge",
    "rebase-apply"
)

foreach ($stateName in $blockedStateNames) {
    $pathResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("rev-parse", "--git-path", $stateName)
    $statePath = Resolve-GitPath -RepositoryRoot $repositoryRoot -GitPath (Get-FirstLine $pathResult.Output)
    if (Test-Path -LiteralPath $statePath) {
        throw "Refusing a normal commit while Git operation state '$stateName' exists."
    }
}

$unmergedResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("diff", "--name-only", "--diff-filter=U")
if ($unmergedResult.Output.Count -gt 0) {
    throw "Refusing to commit with unmerged paths:`n$($unmergedResult.Output -join "`n")"
}

$stagedResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("diff", "--cached", "--quiet", "--exit-code") -AllowFailure
if ($stagedResult.ExitCode -eq 0) {
    throw "There are no staged changes to commit."
}
if ($stagedResult.ExitCode -ne 1) {
    throw "Could not inspect staged changes; git diff exited with code $($stagedResult.ExitCode)."
}

$checkResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("diff", "--cached", "--check") -AllowFailure
if ($checkResult.ExitCode -ne 0) {
    $checkDetails = ($checkResult.Output | Out-String).Trim()
    throw "git diff --cached --check failed.`n$checkDetails"
}

try {
    $messageBytes = [Convert]::FromBase64String($MessageBase64)
    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    $message = $utf8Strict.GetString($messageBytes)
}
catch {
    throw "MessageBase64 must contain valid Base64-encoded UTF-8 text. $($_.Exception.Message)"
}

$message = $message.TrimEnd([char[]]"`r`n")
if ([string]::IsNullOrWhiteSpace($message)) {
    throw "Commit message must not be empty."
}
if ($message.IndexOf([char]0) -ge 0) {
    throw "Commit message must not contain NUL characters."
}

$headBeforeResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("rev-parse", "--verify", "HEAD") -AllowFailure
$headBefore = if ($headBeforeResult.ExitCode -eq 0) { Get-FirstLine $headBeforeResult.Output } else { $null }
$symbolicHeadResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("symbolic-ref", "-q", "HEAD") -AllowFailure
$symbolicHead = if ($symbolicHeadResult.ExitCode -eq 0) { Get-FirstLine $symbolicHeadResult.Output } else { $null }

$indexResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("rev-parse", "--git-path", "index")
$indexPath = Resolve-GitPath -RepositoryRoot $repositoryRoot -GitPath (Get-FirstLine $indexResult.Output)
if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "Could not locate the repository index at '$indexPath'."
}

$tempWorkDirectory = New-ExternalTempDirectory -RepositoryRoot $repositoryRoot
$tempIndexPath = Join-Path $tempWorkDirectory "index"
$tempMessagePath = Join-Path $tempWorkDirectory "commit-message.txt"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$cleanupFailure = $null
$commitOutput = @()
$previousGitIndexFile = [Environment]::GetEnvironmentVariable("GIT_INDEX_FILE", "Process")
$previousReflogAction = [Environment]::GetEnvironmentVariable("GIT_REFLOG_ACTION", "Process")
$reflogAction = "codex-git-commit-helper-{0}" -f [Guid]::NewGuid().ToString("N")

try {
    [System.IO.File]::Copy($indexPath, $tempIndexPath, $false)

    $sharedIndexResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("rev-parse", "--shared-index-path") -AllowFailure
    if ($sharedIndexResult.ExitCode -eq 0) {
        $sharedIndexValue = Get-FirstLine $sharedIndexResult.Output
        if ($sharedIndexValue) {
            $sharedIndexPath = Resolve-GitPath -RepositoryRoot $repositoryRoot -GitPath $sharedIndexValue
            if (Test-Path -LiteralPath $sharedIndexPath -PathType Leaf) {
                [System.IO.File]::Copy(
                    $sharedIndexPath,
                    (Join-Path $tempWorkDirectory ([System.IO.Path]::GetFileName($sharedIndexPath))),
                    $false
                )
            }
        }
    }

    [System.IO.File]::WriteAllText($tempMessagePath, $message + "`n", $utf8NoBom)
    [Environment]::SetEnvironmentVariable("GIT_INDEX_FILE", $tempIndexPath, "Process")

    $snapshotUnmerged = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("diff", "--name-only", "--diff-filter=U")
    if ($snapshotUnmerged.Output.Count -gt 0) {
        throw "Refusing to commit with unmerged paths in the staged snapshot:`n$($snapshotUnmerged.Output -join "`n")"
    }

    $snapshotStaged = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("diff", "--cached", "--quiet", "--exit-code") -AllowFailure
    if ($snapshotStaged.ExitCode -eq 0) {
        throw "There are no staged changes to commit."
    }
    if ($snapshotStaged.ExitCode -ne 1) {
        throw "Could not inspect the staged snapshot; git diff exited with code $($snapshotStaged.ExitCode)."
    }

    $snapshotCheck = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("diff", "--cached", "--check") -AllowFailure
    if ($snapshotCheck.ExitCode -ne 0) {
        $checkDetails = ($snapshotCheck.Output | Out-String).Trim()
        throw "git diff --cached --check failed.`n$checkDetails"
    }

    $expectedTreeResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("write-tree")
    $expectedTree = Get-FirstLine $expectedTreeResult.Output

    $headImmediatelyBeforeResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("rev-parse", "--verify", "HEAD") -AllowFailure
    $headImmediatelyBefore = if ($headImmediatelyBeforeResult.ExitCode -eq 0) { Get-FirstLine $headImmediatelyBeforeResult.Output } else { $null }
    if ($headImmediatelyBefore -ne $headBefore) {
        throw "HEAD changed while preparing the isolated staged snapshot. No commit was attempted."
    }

    [Environment]::SetEnvironmentVariable("GIT_REFLOG_ACTION", $reflogAction, "Process")
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $commitOutput = & $GitExecutable -C $repositoryRoot --no-pager -c "core.logAllRefUpdates=true" commit -F $tempMessagePath 2>&1
        $commitExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $currentHeadResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("rev-parse", "--verify", "HEAD") -AllowFailure
    $currentHead = if ($currentHeadResult.ExitCode -eq 0) { Get-FirstLine $currentHeadResult.Output } else { $null }
    $reflogRef = if ($symbolicHead) { $symbolicHead } else { "HEAD" }
    $reflogResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("reflog", "show", "--format=%H%x09%gs", "-n", "100", $reflogRef) -AllowFailure
    $createdCandidates = New-Object System.Collections.Generic.List[string]

    if ($reflogResult.ExitCode -eq 0) {
        foreach ($entry in $reflogResult.Output) {
            $parts = $entry.ToString() -split "`t", 2
            if ($parts.Count -ne 2 -or -not $parts[1].StartsWith("$reflogAction`:", [StringComparison]::Ordinal)) {
                continue
            }

            $candidate = $parts[0].Trim()
            $candidateInfo = Get-CommitParentInfo -RepositoryRoot $repositoryRoot -Commit $candidate
            $candidateMatchesParent = if ($headBefore) {
                $candidateInfo.Parents.Count -eq 1 -and $candidateInfo.Parents[0] -eq $headBefore
            }
            else {
                $candidateInfo.Parents.Count -eq 0
            }

            if ($candidateMatchesParent -and -not $createdCandidates.Contains($candidate)) {
                $createdCandidates.Add($candidate)
            }
        }
    }

    if ($commitExitCode -ne 0) {
        $commitDetails = ($commitOutput | Out-String).Trim()
        if ($createdCandidates.Count -gt 0 -or $currentHead -ne $headBefore) {
            throw "git commit returned exit code $commitExitCode, but a commit or HEAD change may have occurred. Current HEAD is $currentHead. Do not retry commit; inspect the repository.`n$commitDetails"
        }
        throw "git commit failed with exit code $commitExitCode; HEAD did not change.`n$commitDetails"
    }

    if ($createdCandidates.Count -ne 1) {
        throw "git commit returned success, but the created commit could not be identified unambiguously from its isolated reflog action. Current HEAD is $currentHead. Do not retry commit; inspect the repository."
    }

    $createdCommit = $createdCandidates[0]
    if ($currentHead -ne $createdCommit) {
        throw "HEAD moved after commit: created $createdCommit, current $currentHead. No automatic rollback was attempted. Do not retry commit; inspect the repository."
    }

    $commitTreeResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("rev-parse", "$createdCommit^{tree}")
    $commitTree = Get-FirstLine $commitTreeResult.Output

    if ($commitTree -ne $expectedTree) {
        Restore-IdentifiedCommit -RepositoryRoot $repositoryRoot -CreatedCommit $createdCommit -HeadBefore $headBefore -SymbolicHead $symbolicHead
        throw "The staged tree changed during git commit (expected $expectedTree, committed $commitTree). The original branch ref was atomically restored; inspect hooks before retrying."
    }
}
finally {
    [Environment]::SetEnvironmentVariable("GIT_INDEX_FILE", $previousGitIndexFile, "Process")
    [Environment]::SetEnvironmentVariable("GIT_REFLOG_ACTION", $previousReflogAction, "Process")

    if ($tempWorkDirectory -and (Test-Path -LiteralPath $tempWorkDirectory)) {
        try {
            [System.IO.Directory]::Delete($tempWorkDirectory, $true)
            if (Test-Path -LiteralPath $tempWorkDirectory) {
                throw "The directory still exists after deletion completed."
            }
        }
        catch {
            $cleanupFailure = $_.Exception.Message
            Write-Warning "Could not remove temporary commit directory '$tempWorkDirectory': $cleanupFailure"
        }
    }
}

$logResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("log", "-1", "--pretty=format:%H%n%B")
$statusResult = Invoke-GitCapture -WorkingDirectory $repositoryRoot -Arguments @("status", "--short", "--branch")

$commitOutput | ForEach-Object { Write-Output $_ }
Write-Output "--- commit readback ---"
$logResult.Output | ForEach-Object { Write-Output $_ }
Write-Output "--- final status ---"
$statusResult.Output | ForEach-Object { Write-Output $_ }

if ($cleanupFailure) {
    Write-Output "TEMP_CLEANUP_FAILURE=$tempWorkDirectory"
    throw "Commit succeeded, but the temporary commit directory could not be removed: '$tempWorkDirectory'. Do not retry commit. Remove the directory manually. $cleanupFailure"
}

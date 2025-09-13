# High-Performance Git Sync and Status Tools
# Optimized for Git 2.x with maximum speed and minimal overhead

#region Core Sync Function
function Sync-GitRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$RepositoryPath,
        
        [switch]$SkipMaintenance,
        [switch]$UseFastForward,
        [switch]$FastMode
    )

    $originalLocation = Get-Location
    try {
        Push-Location $RepositoryPath -ErrorAction Stop

        # Validate repo
        git rev-parse --is-inside-work-tree >$null 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Not a Git repository: $RepositoryPath" }

        # Branch info
        $currentBranch = git symbolic-ref --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { $currentBranch = git rev-parse --short HEAD }

        # Skip expensive check if FastMode
        $hasChanges = $false
        if (-not $FastMode) {
            git diff-index --quiet HEAD --
            if ($LASTEXITCODE -ne 0) { $hasChanges = $true }
        }

        # Async background maintenance
        if (-not $SkipMaintenance) {
            Start-Job -ScriptBlock {
                git -C $using:RepositoryPath maintenance run --task=incremental-repack --quiet
            } | Out-Null
        }

        # Fetch
        git fetch --quiet --prune --prune-tags --jobs=4 origin
        if ($LASTEXITCODE -ne 0) { throw "Fetch failed" }

        # Merge/Rebase with remote branch
        $remoteBranch = "origin/$currentBranch"
        git rev-parse --verify "$remoteBranch" >$null 2>&1
        if ($LASTEXITCODE -eq 0) {
            if ($UseFastForward) {
                git merge --ff-only "$remoteBranch" --quiet
            } else {
                git rebase --autostash --quiet "$remoteBranch"
            }
            if ($LASTEXITCODE -ne 0) { throw "Sync failed – conflicts exist" }
        }

        # Commit if changes exist
        if ($hasChanges) {
            git add -A
            if ($LASTEXITCODE -eq 0) {
                git commit -qm "Automated sync"
            }
        }

        # Push
        git push --quiet --force-with-lease --atomic origin $currentBranch
        if ($LASTEXITCODE -ne 0) {
            git push --quiet origin $currentBranch
        }

        Write-Host "✅ Sync complete" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error $_
        return $false
    }
    finally {
        Pop-Location
        Get-Job | Where-Object { $_.State -eq 'Completed' } | Remove-Job -Force
    }
}
#endregion

#region Helper Functions

# Ultra-fast sync for current directory
function gsync {
    [CmdletBinding()]
    param(
        [string]$Path = $PWD.Path,
        [switch]$SkipMaintenance,
        [switch]$UseFastForward,
        [switch]$FastMode
    )

    Sync-GitRepository -RepositoryPath $Path `
        -SkipMaintenance:$SkipMaintenance `
        -UseFastForward:$UseFastForward `
        -FastMode:$FastMode
}

# Lightning-fast project sync with caching
function gsync-projects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$ProjectName,
        [string]$ProjectsRoot = "$env:USERPROFILE\Projects",
        [switch]$SkipMaintenance,
        [switch]$UseFastForward,
        [switch]$FastMode
    )

    if (-not $global:ProjectPathCache) { $global:ProjectPathCache = @{} }
    $cacheKey = "$ProjectsRoot|$ProjectName"

    if (-not $global:ProjectPathCache.ContainsKey($cacheKey)) {
        $projectPath = Join-Path $ProjectsRoot $ProjectName
        if (-not (Test-Path $projectPath)) {
            Write-Error "Project not found: $projectPath"
            return $false
        }
        $global:ProjectPathCache[$cacheKey] = $projectPath
    }

    Write-Host "⚡ Syncing project: $ProjectName" -ForegroundColor Magenta
    Sync-GitRepository -RepositoryPath $global:ProjectPathCache[$cacheKey] `
        -SkipMaintenance:$SkipMaintenance `
        -UseFastForward:$UseFastForward `
        -FastMode:$FastMode
}

# Parallel batch sync
function gsync-batch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$RepositoryPaths,
        [int]$MaxParallel = 4,
        [switch]$SkipMaintenance,
        [switch]$UseFastForward,
        [switch]$FastMode,
        [switch]$ContinueOnError
    )

    $results = @{}
    Write-Host "🚀 Starting parallel sync of $($RepositoryPaths.Count) repositories..." -ForegroundColor Magenta

    for ($i = 0; $i -lt $RepositoryPaths.Count; $i += $MaxParallel) {
        $batch = $RepositoryPaths[$i..([Math]::Min($i + $MaxParallel - 1, $RepositoryPaths.Count - 1))]

        $jobs = foreach ($repo in $batch) {
            Start-Job -ArgumentList $repo,$SkipMaintenance,$UseFastForward,$FastMode -ScriptBlock {
                param($repoPath,$skipMaint,$useFF,$fastMode)
                try {
                    $result = Sync-GitRepository -RepositoryPath $repoPath `
                        -SkipMaintenance:$skipMaint `
                        -UseFastForward:$useFF `
                        -FastMode:$fastMode
                    return @{ Path=$repoPath; Success=$result; Error=$null }
                } catch {
                    return @{ Path=$repoPath; Success=$false; Error=$_.Exception.Message }
                }
            }
        }

        foreach ($job in $jobs) {
            $result = Receive-Job -Job $job -Wait
            Remove-Job -Job $job -Force
            $results[$result.Path] = $result.Success

            $status = if ($result.Success) { "✅" } else { "❌" }
            $color  = if ($result.Success) { "Green" } else { "Red" }
            Write-Host "$status $($result.Path)" -ForegroundColor $color

            if ($result.Error -and -not $result.Success) {
                Write-Warning "Error in $($result.Path): $($result.Error)"
                if (-not $ContinueOnError) { break }
            }
        }
    }

    $successCount = ($results.Values | Where-Object { $_ }).Count
    Write-Host "`n🎯 Completed: $successCount/$($RepositoryPaths.Count) repositories" -ForegroundColor Green
    return $results
}

# High-speed single repo status
function gstatus {
    [CmdletBinding()]
    param([string]$Path = $PWD.Path)

    if (-not (Test-Path $Path)) {
        Write-Error "Path not found: $Path"
        return
    }

    Push-Location $Path
    try {
        git rev-parse --is-inside-work-tree >$null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Not a Git repository: $Path" -ForegroundColor Red
            return
        }

        $topLevel     = git rev-parse --show-toplevel
        $currentBranch = git symbolic-ref --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { $currentBranch = git rev-parse --short HEAD }
        $remoteUrl   = git config --get remote.origin.url

        Write-Host "📁 Repository: $topLevel" -ForegroundColor Cyan
        Write-Host "🌿 Branch: $currentBranch" -ForegroundColor Green
        if ($remoteUrl) { Write-Host "🌐 Remote: $remoteUrl" -ForegroundColor Blue }

        $aheadBehind = git for-each-ref --format="%(ahead-behind:origin/$currentBranch)" refs/heads/$currentBranch 2>$null
        if ($aheadBehind -and $aheadBehind -match '^(\d+)\s+(\d+)$') {
            $ahead = $matches[1]; $behind = $matches[2]
            Write-Host "📊 Ahead: $ahead, Behind: $behind" -ForegroundColor Magenta
        }

        git diff-index --quiet HEAD -- 2>$null
        $dirty = ($LASTEXITCODE -ne 0)

        if (-not $dirty) {
            Write-Host "✨ Working tree clean" -ForegroundColor Green
        } else {
            Write-Host "📝 Changes present" -ForegroundColor Yellow
            $changes = git diff --name-only HEAD | Select-Object -First 5
            foreach ($file in $changes) {
                Write-Host "   $file" -ForegroundColor Gray
            }
        }
    }
    finally {
        Pop-Location
    }
}

# Parallel status check for multiple repos
function gstatus-batch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$RepositoryPaths,
        [int]$MaxParallel = 4
    )

    Write-Host "🚀 Checking status of $($RepositoryPaths.Count) repositories in parallel..." -ForegroundColor Magenta
    $results = @{}

    for ($i = 0; $i -lt $RepositoryPaths.Count; $i += $MaxParallel) {
        $batch = $RepositoryPaths[$i..([Math]::Min($i + $MaxParallel - 1, $RepositoryPaths.Count - 1))]

        $jobs = foreach ($repo in $batch) {
            Start-Job -ArgumentList $repo -ScriptBlock {
                param($repoPath)
                try {
                    Push-Location $repoPath
                    git rev-parse --is-inside-work-tree >$null 2>&1
                    if ($LASTEXITCODE -ne 0) { return @{ Path=$repoPath; Repo=$false } }

                    $branch = git symbolic-ref --short HEAD 2>$null
                    if ($LASTEXITCODE -ne 0) { $branch = git rev-parse --short HEAD }
                    $remote = git config --get remote.origin.url

                    $aheadBehind = git for-each-ref --format="%(ahead-behind:origin/$branch)" refs/heads/$branch 2>$null
                    $ahead=0; $behind=0
                    if ($aheadBehind -and $aheadBehind -match '^(\d+)\s+(\d+)$') {
                        $ahead = [int]$matches[1]; $behind = [int]$matches[2]
                    }

                    git diff-index --quiet HEAD -- 2>$null
                    $dirty = ($LASTEXITCODE -ne 0)

                    Pop-Location

                    return @{
                        Path=$repoPath; Repo=$true; Branch=$branch;
                        Remote=$remote; Ahead=$ahead; Behind=$behind; Dirty=$dirty
                    }
                } catch {
                    return @{ Path=$repoPath; Repo=$false; Error=$_.Exception.Message }
                }
            }
        }

        foreach ($job in $jobs) {
            $result = Receive-Job -Job $job -Wait
            Remove-Job -Job $job -Force
            $results[$result.Path] = $result

            if (-not $result.Repo) {
                Write-Host "❌ $($result.Path) (not a Git repo)" -ForegroundColor Red
                continue
            }

            $status = if ($result.Dirty) { "📝 Dirty" } else { "✨ Clean" }
            $aheadBehind = if ($result.Ahead -eq 0 -and $result.Behind -eq 0) { "Up to date" } else { "+$($result.Ahead)/-$($result.Behind)" }

            Write-Host "📁 $($result.Path)" -ForegroundColor Cyan
            Write-Host "   🌿 $($result.Branch) | 🌐 $($result.Remote) | 📊 $aheadBehind | $status" -ForegroundColor White
        }
    }

    return $results
}
#endregion

function print-git-sync-usage {
    # Banner
    Write-Host "⚡ High-Performance Git Sync Tools Loaded!" -ForegroundColor Green
    Write-Host "🚀 Commands available:" -ForegroundColor Cyan
    Write-Host "  gsync [path] [-FastMode]" -ForegroundColor White
    Write-Host "  gsync-projects <name> [-FastMode]" -ForegroundColor White
    Write-Host "  gsync-batch <paths> [-MaxParallel]" -ForegroundColor White
    Write-Host "  gstatus [path]" -ForegroundColor White
    Write-Host "  gstatus-batch <paths> [-MaxParallel]" -ForegroundColor White

# Check 3 repos at once
    Write-Host @"
gstatus-batch -RepositoryPaths @(
  "C:\Projects\api-service",
  "C:\Projects\frontend-app",
  "C:\Projects\infra"
) -MaxParallel 3
"@
}


# Quick aliases
Set-Alias -Name gs -Value gstatus
# Set-Alias -Name gsp -Value gsync-projects
# PowerShell Profile Configuration for Sync-GitRepository
# Add this to your PowerShell profile to enable convenient Git syncing

# Method 1: Direct function inclusion
# Copy the entire Sync-GitRepository function here, or dot-source it from a file

# Method 2: Dot-source from external file (recommended)
# Save the Sync-GitRepository function to a separate .ps1 file and source it
# Uncomment and modify the path below:
# . "$PSScriptRoot\Sync-GitRepository.ps1"

# Method 3: Load from a module location
# if (Test-Path "$PSScriptRoot\GitSync\Sync-GitRepository.ps1") {
#     . "$PSScriptRoot\GitSync\Sync-GitRepository.ps1"
# }

#region Sync-GitRepository Function
# Place your enhanced Sync-GitRepository function here
function Sync-GitRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Path to the Git repository")]
        [ValidateScript({
            if (-not (Test-Path -Path $_ -PathType Container)) {
                throw "Directory does not exist: $_"
            }
            $true
        })]
        [string]$RepositoryPath,
        
        [Parameter(HelpMessage="Skip maintenance run for faster execution")]
        [switch]$SkipMaintenance,
        
        [Parameter(HelpMessage="Use fast-forward merge instead of rebase")]
        [switch]$UseFastForward
    )

    # Save original location
    $originalLocation = Get-Location

    try {
        # Change to the repository directory
        Write-Verbose "Changing to repository directory: $RepositoryPath"
        Set-Location $RepositoryPath

        # Use git rev-parse --git-dir for faster repository detection (Git 2.x)
        $gitDir = git rev-parse --git-dir 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitDir)) {
            Write-Error "Not in a Git repository. Please provide a valid Git repository path."
            return $false
        }

        # Use git config --get-regexp for faster remote checking (Git 2.x)
        $remoteConfig = git config --get-regexp "remote\..*\.url" 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteConfig)) {
            Write-Error "No remote configured. Please set up a remote repository."
            return $false
        }

        # Extract origin URL more efficiently
        $originUrl = git config --get remote.origin.url 2>$null
        if ([string]::IsNullOrWhiteSpace($originUrl)) {
            # Fallback to first available remote
            $firstRemote = ($remoteConfig -split "`n")[0] -replace '^remote\.([^.]+)\.url.*', '$1'
            $originUrl = git config --get "remote.$firstRemote.url" 2>$null
            Write-Verbose "Using remote '$firstRemote' instead of 'origin'"
        }

        # Run incremental maintenance for better performance (Git 2.30+)
        if (-not $SkipMaintenance) {
            Write-Verbose "Running incremental repository maintenance..."
            # Use --task=incremental-repack for faster maintenance
            git maintenance run --task=incremental-repack --quiet 2>$null | Out-Null
        }

        # Use git status --porcelain=v1 for faster status checking (Git 2.x)
        $statusOutput = git status --porcelain=v1 --untracked-files=normal 2>$null
        $hasUncommittedChanges = -not [string]::IsNullOrWhiteSpace($statusOutput)
        
        if ($hasUncommittedChanges) {
            Write-Host "Uncommitted changes detected. Will autostash for sync..." -ForegroundColor Yellow
        }

        # Use modern fetch + merge/rebase approach for better control (Git 2.x)
        Write-Host "Fetching latest changes from remote..." -ForegroundColor Cyan
        
        # Fetch with prune and force to ensure we get all updates
        git fetch --prune --force origin 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git fetch failed. Check your network connection and remote access."
            return $false
        }

        # Get current branch name using modern syntax (Git 2.22+)
        $currentBranch = git branch --show-current 2>$null
        if ([string]::IsNullOrWhiteSpace($currentBranch)) {
            # Fallback for older Git versions
            $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
        }

        # Check if remote branch exists
        $remoteBranch = "origin/$currentBranch"
        $remoteBranchExists = git rev-parse --verify "$remoteBranch" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Remote branch '$remoteBranch' not found. Will push current branch."
        } else {
            # Perform merge or rebase based on preference
            if ($UseFastForward) {
                Write-Host "Merging with fast-forward from $remoteBranch..." -ForegroundColor Cyan
                if ($hasUncommittedChanges) {
                    git stash push --include-untracked --message "Auto-stash before fast-forward merge" 2>$null
                }
                git merge --ff-only "$remoteBranch" 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Fast-forward not possible, falling back to regular merge..." -ForegroundColor Yellow
                    git merge "$remoteBranch" 2>$null
                }
                if ($hasUncommittedChanges) {
                    git stash pop 2>$null
                }
            } else {
                Write-Host "Rebasing with latest changes from $remoteBranch..." -ForegroundColor Cyan
                # Use --autostash and --rebase-merges for better conflict handling (Git 2.18+)
                git rebase --autostash --rebase-merges "$remoteBranch" 2>$null
            }

            if ($LASTEXITCODE -ne 0) {
                Write-Error "Merge/rebase failed. Please resolve conflicts manually."
                return $false
            }
        }

        # Use git add --all for comprehensive staging (includes renames/deletes)
        Write-Host "Staging all changes..." -ForegroundColor Cyan
        git add --all 2>$null

        # Check for staged changes using git diff-index for better performance (Git 2.x)
        $headCommit = git rev-parse HEAD 2>$null
        $hasStagedChanges = $false
        if (-not [string]::IsNullOrWhiteSpace($headCommit)) {
            $diffIndex = git diff-index --cached --quiet HEAD 2>$null
            $hasStagedChanges = ($LASTEXITCODE -ne 0)
        } else {
            # Initial commit scenario
            $hasStagedChanges = -not [string]::IsNullOrWhiteSpace((git ls-files --cached 2>$null))
        }

        if ($hasStagedChanges) {
            # Generate commit message using git status --porcelain=v2 for better parsing (Git 2.11+)
            $statusV2 = git status --porcelain=v2 2>$null
            if ([string]::IsNullOrWhiteSpace($statusV2)) {
                $statusV2 = git status --porcelain=v1 2>$null
            }
            
            $changedFiles = @()
            if (-not [string]::IsNullOrWhiteSpace($statusV2)) {
                $changedFiles = ($statusV2 -split "`n" | Select-Object -First 3 | ForEach-Object {
                    if ($_.StartsWith('2 ')) {
                        # Renamed file (porcelain v2 format)
                        ($_ -split '\t')[-1]
                    } elseif ($_.Contains(' ')) {
                        # Regular file change
                        ($_ -split ' ', 2)[-1] -replace '\t.*$', ''
                    } else {
                        $_
                    }
                }) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            }
            
            # Construct more informative commit message
            $commitMessage = if ($changedFiles.Count -eq 0) {
                "Automated snapshot: Repository sync"
            } else {
                $fileList = $changedFiles -join ', '
                if ($fileList.Length -gt 47) {
                    $fileList = $fileList.Substring(0, 44) + "..."
                }
                "Automated sync: $fileList"
            }
            
            Write-Host "Committing changes: $commitMessage" -ForegroundColor Cyan
            # Use --quiet for faster commit (Git 2.x)
            git commit --quiet -m "$commitMessage" 2>$null
            
            if ($LASTEXITCODE -ne 0) {
                Write-Error "git commit failed."
                return $false
            }
        } else {
            Write-Host "No staged changes to commit." -ForegroundColor Gray
        }

        # Push with lease for safer pushing (Git 2.x)
        Write-Host "Pushing changes to remote..." -ForegroundColor Cyan
        # Use --force-with-lease for safer force pushing if needed
        git push --force-with-lease origin "$currentBranch" 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            # Fallback to regular push
            git push origin "$currentBranch" 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "git push failed. You might need to pull again or check your remote access."
                return $false
            }
        }

        # Verify sync status using git status --ahead-behind (Git 2.16+)
        $aheadBehind = git rev-list --count --left-right "HEAD...origin/$currentBranch" 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($aheadBehind)) {
            $counts = $aheadBehind -split '\s+'
            if ($counts.Length -eq 2 -and $counts[0] -eq "0" -and $counts[1] -eq "0") {
                Write-Host "✅ Repository is fully synchronized." -ForegroundColor Green
            } else {
                Write-Host "✅ Sync complete. Local: +$($counts[0]), Remote: +$($counts[1])" -ForegroundColor Green
            }
        } else {
            Write-Host "✅ Sync complete." -ForegroundColor Green
        }
        
        return $true
    }
    catch {
        Write-Error "An error occurred during sync: $($_.Exception.Message)"
        return $false
    }
    finally {
        # Always return to the original directory
        Write-Verbose "Returning to original directory: $originalLocation"
        Set-Location $originalLocation
    }
}
#endregion

#region Aliases and Convenience Functions

# Simple alias that syncs current directory
function gsync {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, HelpMessage="Path to repository (defaults to current directory)")]
        [string]$Path = (Get-Location).Path,

        [switch]$SkipMaintenance,
        [switch]$UseFastForward
    )
    
    $params = @{
        RepositoryPath = $Path
    }

    if ($SkipMaintenance) { $params.SkipMaintenance = $true }
    if ($UseFastForward) { $params.UseFastForward = $true }

    Sync-GitRepository @params
}

# Quick sync for common project directories
function gsync-projects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Project name to sync")]
        [string]$ProjectName,
        
        [Parameter(HelpMessage="Base projects directory")]
        [string]$ProjectsRoot = "$env:USERPROFILE\Projects", # Customize this path
        
        [switch]$SkipMaintenance,
        [switch]$UseFastForward
    )
    
    $projectPath = Join-Path $ProjectsRoot $ProjectName
    
    if (-not (Test-Path $projectPath)) {
        Write-Error "Project directory not found: $projectPath"
        return $false
    }
    
    $params = @{
        RepositoryPath = $projectPath
    }
    
    if ($SkipMaintenance) { $params.SkipMaintenance = $true }
    if ($UseFastForward) { $params.UseFastForward = $true }
    
    Write-Host "Syncing project: $ProjectName" -ForegroundColor Magenta
    Sync-GitRepository @params
}

# Batch sync multiple repositories
function gsync-batch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Array of repository paths")]
        [string[]]$RepositoryPaths,
        
        [switch]$SkipMaintenance,
        [switch]$UseFastForward,
        [switch]$ContinueOnError
    )
    
    $results = @{}
    $successCount = 0
    $totalCount = $RepositoryPaths.Count
    
    Write-Host "Starting batch sync of $totalCount repositories..." -ForegroundColor Magenta
    
    foreach ($repo in $RepositoryPaths) {
        Write-Host "`n--- Syncing: $repo ---" -ForegroundColor Yellow
        
        try {
            $params = @{
                RepositoryPath = $repo
            }
            
            if ($SkipMaintenance) { $params.SkipMaintenance = $true }
            if ($UseFastForward) { $params.UseFastForward = $true }
            
            $success = Sync-GitRepository @params
            $results[$repo] = $success
            
            if ($success) {
                $successCount++
            } else {
                Write-Error "Failed to sync: $repo"
                if (-not $ContinueOnError) {
                    break
                }
            }
        }
        catch {
            Write-Error "Error syncing $repo`: $($_.Exception.Message)"
            $results[$repo] = $false
            if (-not $ContinueOnError) {
                break
            }
        }
    }
    
    Write-Host "`n=== Batch Sync Results ===" -ForegroundColor Magenta
    Write-Host "Successfully synced: $successCount/$totalCount repositories" -ForegroundColor Green
    
    # Show detailed results
    foreach ($repo in $RepositoryPaths) {
        $status = if ($results[$repo]) { "✅ SUCCESS" } else { "❌ FAILED" }
        $color = if ($results[$repo]) { "Green" } else { "Red" }
        Write-Host "$status - $repo" -ForegroundColor $color
    }
    
    return $results
}

# Create tab completion for project names
Register-ArgumentCompleter -CommandName gsync-projects -ParameterName ProjectName -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $projectsRoot = if ($fakeBoundParameters.ProjectsRoot) { 
        $fakeBoundParameters.ProjectsRoot 
    } else { 
        "$env:USERPROFILE\Projects" 
    }
    
    if (Test-Path $projectsRoot) {
        Get-ChildItem -Path $projectsRoot -Directory |
            Where-Object { $_.Name -like "$wordToComplete*" } |
            ForEach-Object { $_.Name }
    }
}

#endregion

#region Utility Functions

# Function to check Git repository status quickly
function gstatus {
    param(
        [string]$Path = (Get-Location).Path
    )
    
    if (-not (Test-Path $Path)) {
        Write-Error "Path does not exist: $Path"
        return
    }
    
    Push-Location $Path
    try {
        if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
            Write-Host "Not a Git repository: $Path" -ForegroundColor Red
            return
        }
        
        Write-Host "Repository Status for: $Path" -ForegroundColor Cyan
        Write-Host "Current Branch: $(git branch --show-current)" -ForegroundColor Green
        Write-Host "Remote URL: $(git config --get remote.origin.url)" -ForegroundColor Blue
        
        $status = git status --porcelain=v1
        if ([string]::IsNullOrWhiteSpace($status)) {
            Write-Host "Working tree clean ✅" -ForegroundColor Green
        } else {
            Write-Host "Uncommitted changes:" -ForegroundColor Yellow
            git status --short
        }
        
        # Show ahead/behind info
        $remoteBranch = "origin/$(git branch --show-current)"
        $aheadBehind = git rev-list --count --left-right "HEAD...$remoteBranch" 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($aheadBehind)) {
            $counts = $aheadBehind -split '\s+'
            if ($counts[0] -ne "0" -or $counts[1] -ne "0") {
                Write-Host "Ahead: $($counts[0]), Behind: $($counts[1])" -ForegroundColor Magenta
            }
        }
    }
    finally {
        Pop-Location
    }
}

#endregion

# Display available commands
Write-Host "Git Sync Tools Loaded!" -ForegroundColor Green
Write-Host "Available commands:" -ForegroundColor Cyan
Write-Host "  gsync [path]              - Sync repository (current directory if no path)" -ForegroundColor White
Write-Host "  gsync-projects <name>     - Sync project by name from projects directory" -ForegroundColor White
Write-Host "  gsync-batch <paths>       - Sync multiple repositories" -ForegroundColor White
Write-Host "  gstatus [path]            - Quick repository status" -ForegroundColor White
Write-Host "  Sync-GitRepository <path> - Full function with all parameters" -ForegroundColor White

# Quick aliases
Set-Alias -Name gs -Value gstatus
# Set-Alias -Name gsp -Value gsync-projects
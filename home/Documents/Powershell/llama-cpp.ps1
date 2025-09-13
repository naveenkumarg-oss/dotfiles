# https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md

# Set your desired model name
$modelName = "liquidai-lfm2-1.2b"
#$modelName = "gemma-3n-e2b"
#$modelName = "gemma-3n-e4b"
#$modelName = "qwen3-4b-it-2507"
#$modelName = "gpt-oss-20b"


# Define or import the Get-ModelArgs function first
function Get-ModelArgs {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModelName
    )

    switch ($ModelName.Trim().ToLower()) {		
        "gemma-3n-e2b" {
            return '-m c:\worktools\gguf-models\gemma-3n-E2B-it-Q5_K_M.gguf -c 4096 -ngl 99 --seed 3407 --prio 2 --temp 1.0 --repeat-penalty 1.0 --min-p 0.00 --top-k 64 --top-p 0.95'
        }
		"gemma-3n-e4b" {
            return '-m c:\worktools\gguf-models\gemma-3n-E4B-it-Q4_K_M.gguf -c 4096 -ngl 20 --n-cpu-moe 12 --temp 1.0 --min-p 0.00 --top-k 64 --top-p 0.95 --repeat-penalty 1.0 -ub 2048 -b 2048'
        }
        "gpt-oss-20b" {
            return '-m c:\worktools\gguf-models\gpt-oss-20b-Q5_K_M.gguf -c 8192 --temp 1.0 --top-p 1.0 --top-k 0 --jinja --reasoning-format none --reasoning-budget 0 -ub 2048 -b 2048 --n-cpu-moe 35'
        }
		"qwen3-4b-it-2507" {
            return '-m c:\worktools\gguf-models\Qwen3-4B-Instruct-2507-Q5_K_M.gguf -c 8192 -ngl 20 --n-cpu-moe 12 -ub 2048 -b 2048 --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.00 --presence_penalty 1.0 --jinja'
        }
		"liquidai-lfm2-1.2b" {
            return '-m c:\worktools\gguf-models\LFM2-1.2B-F16.gguf -c 24576 -ngl 16 --temp 0.3 --min-p 0.15 --presence_penalty 1.05 -ub 2048 -b 2048'
        }
        "mellum-4b" {
            return '-m c:\worktools\gguf-models\mellum-4b-sft-all.Q8_0.gguf -c 8192 -ngl 15 --temp 0'
        }
        default {
            Write-Warning "Model configuration for '$ModelName' not found."
            return $null
        }
    }
}

# Get model-specific arguments
$modelSpecificArgs = Get-ModelArgs -ModelName $modelName

if (-not $modelSpecificArgs) {
    Write-Error "Failed to retrieve arguments for model '$modelName'. Exiting."
    exit 1
}

# Common arguments - now using array to avoid parsing issues
# -ngl, --n-gpu-layers				number of layers to store in VRAM
# -n, --predict, --n-predict N 		number of tokens to predict (default: -1, -1 = infinity)
# -mg, --main-gpu 					INDEX the GPU to use for the model 
# -fa, --flash-attn					enable Flash Attention (default: disabled)
# --log-disable
$cliToolArguments = "-t 12", "-n -1", "-mg 1", "-fa on", "--log-verbosity 0", "--no-webui", "--offline", "--port 5001"
$cliToolArguments += $modelSpecificArgs -split ' ' | Where-Object { $_ -ne '' }

$basePath = "c:\worktools\llama-cpp-vulkan"
$cliToolPath = "$basePath\llama-cli.exe"
$serverToolPath = "$basePath\llama-server.exe"
$pidFilePath = "$basePath\.pid"

# Now $cliToolArguments is a clean array of arguments, ready to pass to a CLI tool


# --- Helper Functions ---

function Get-RunningProcessId {
    <#
    .SYNOPSIS
    Reads the PID from the PID file and checks if the corresponding process is running.

    .OUTPUTS
    System.Diagnostics.Process object if the process is running, otherwise $null.
    #>
    param()
    
    if (-not (Test-Path $pidFilePath)) {
        Write-Host "PID file '$pidFilePath' not found." -ForegroundColor Yellow
        return $null
    }

    $pidContent = Get-Content $pidFilePath -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($pidContent)) {
        Write-Host "PID file '$pidFilePath' is empty or invalid." -ForegroundColor Yellow
        Remove-Item $pidFilePath -ErrorAction SilentlyContinue
        return $null
    }

    $parsedPid = 0
    if (-not ([int]::TryParse($pidContent, [ref]$parsedPid))) {
        Write-Host "PID in file '$pidFilePath' is not a valid number: '$pidContent'. Deleting file." -ForegroundColor Red
        Remove-Item $pidFilePath -ErrorAction SilentlyContinue
        return $null
    }

    try {
        # Using $parsedPid instead of $pid to avoid conflict
        $process = Get-Process -Id $parsedPid -ErrorAction SilentlyContinue
        if ($process -and -not $process.HasExited) {
            return $process
        } else {
            Write-Host "Process with PID $parsedPid (from file) is not running or has exited." -ForegroundColor Yellow
            Remove-Item $pidFilePath -ErrorAction SilentlyContinue
            return $null
        }
    } catch {
        # Corrected line: Using ${_} to explicitly delimit the $_ variable for parsing
		Write-Host "Error checking process with PID $processId $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $pidFilePath -ErrorAction SilentlyContinue
        return $null
    }
}

function Write-ProcessIdToFile {
    <#
    .SYNOPSIS
    Writes the given Process ID to the PID file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [int]$ProcessId
    )
    try {
        Set-Content -Path $pidFilePath -Value $ProcessId -Force
        Write-Host "Process ID $ProcessId written to '$pidFilePath'." -ForegroundColor Green
    } catch {
        Write-Host "Error writing PID to file '$pidFilePath': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Main Functions for User Options ---

function Start-CliProcess {
    <#
    .SYNOPSIS
    Starts the CLI tool in the background, checking for existing processes first.
    #>
    param()

    Write-Host "Attempting to start CLI tool..." -ForegroundColor Cyan

    $existingProcess = Get-RunningProcessId
    if ($existingProcess) {
        Write-Host "CLI tool is already running with PID $($existingProcess.Id). Not starting a new instance." -ForegroundColor Yellow
        return
    }

    Write-Host "No existing process found or existing process is invalid. Starting a new instance..." -ForegroundColor Yellow
    try {
        # Start the process in the background without a new window
        $newProcess = Start-Process -FilePath $serverToolPath `
                                    -ArgumentList $cliToolArguments `
                                    -NoNewWindow `
                                    -PassThru `
                                    -ErrorAction Stop

        Write-ProcessIdToFile -ProcessId $newProcess.Id
        Write-Host "CLI tool started successfully in the background with PID $($newProcess.Id)." -ForegroundColor Green
    } catch {
        Write-Host "Failed to start CLI tool: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please ensure '$serverToolPath' is a valid executable and accessible." -ForegroundColor Red
    }
}

function Check-CliProcessStatus {
    <#
    .SYNOPSIS
    Checks and reports the status of the background CLI tool.
    #>
    param()

    Write-Host "Checking CLI tool status..." -ForegroundColor Cyan

    $process = Get-RunningProcessId
    if ($process) {
        Write-Host "CLI tool is currently RUNNING with PID $($process.Id)." -ForegroundColor Green
    } else {
        Write-Host "CLI tool is NOT running or its PID is not tracked." -ForegroundColor Red
    }
}

function Stop-AndRemoveCliProcess {
    <#
    .SYNOPSIS
    Stops the background CLI tool and cleans up the PID file.
    #>
    param()

    Write-Host "Attempting to stop CLI tool and clean up..." -ForegroundColor Cyan

    $process = Get-RunningProcessId
    if ($process) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
            Write-Host "CLI tool with PID $($process.Id) stopped successfully." -ForegroundColor Green
        } catch {
            Write-Host "Failed to stop process with PID $($process.Id): $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "No running CLI tool found or PID not tracked." -ForegroundColor Yellow
    }

    if (Test-Path $pidFilePath) {
        try {
            Remove-Item $pidFilePath -ErrorAction Stop
            Write-Host "PID file '$pidFilePath' removed successfully." -ForegroundColor Green
        } catch {
            Write-Host "Failed to remove PID file '$pidFilePath': $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "PID file '$pidFilePath' does not exist." -ForegroundColor Yellow
    }
}

function Print-LlamaVersion {
	$output = & $cliToolPath --version 2>&1

	$match = $output | Select-String -Pattern 'version: (\d+)'

	if ($match) {
		$versionNumber = $match.Matches.Groups[1].Value
		Write-Host "Extracted version: $versionNumber" -ForegroundColor Green
	} else {
		Write-Host "No version number found in the text." -ForegroundColor Yellow
		Write-Host "Full output was:"
		Write-Host $output
	}
}

function Show-CliOptions {
    Write-Host "`n--- CLI Tool Manager ---" -ForegroundColor DarkCyan
    Write-Host "1. Start process" -ForegroundColor White
    Write-Host "2. Check process status" -ForegroundColor White
    Write-Host "3. Stop and remove process (cleanup)" -ForegroundColor White
	Write-Host "4. Print Version" -ForegroundColor White
    Write-Host "Q. Quit" -ForegroundColor White
    Write-Host "------------------------" -ForegroundColor DarkCyan

    $choice = Read-Host "Enter your choice (1, 2, 3, 4, Q)"
    $choice = $choice.ToUpper()

    switch ($choice) {
        "1" { Start-CliProcess }
        "2" { Check-CliProcessStatus }
        "3" { Stop-AndRemoveCliProcess }
		"4" { Print-LlamaVersion }
        "Q" {
            Write-Host "Exiting CLI Tool Manager. Goodbye!" -ForegroundColor Green
        }
        default {
            Write-Host "Invalid choice. Please try again." -ForegroundColor Red
        }
    }
}

Show-CliOptions
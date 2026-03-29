# =============================================================================
# llama-server Manager
# Docs: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
# My Configuration: NVIDIA T600 4GB VRAM, 64GB RAM, 12th Gen i7-12800H (16P+4E cores = 20 threads), Vulkan backend
# Backend: Vulkan / CUDA / CPU
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# =============================================================================
# CONFIGURATION — Edit this section only
# =============================================================================

# --- Active model (uncomment one) ---
#$ActiveModel = "qwen3.5-9B"
#$ActiveModel = "qwen3.5-4B"
#$ActiveModel = "qwen3.5-9B-instruct"
$ActiveModel = "qwen3.5-4B-instruct"
#$ActiveModel = "gemma-3n-e2b"
#$ActiveModel = "gemma-3n-e4b"
#$ActiveModel = "liquidai-lfm2-2.6b"

# --- Backend (uncomment one) ---
#$Backend = "cuda"
#$Backend = "cpu"
$Backend = "vulkan"

# --- Paths ---
$Paths = @{
    cuda   = "C:\worktools\llama-cpp-cuda"
    cpu    = "C:\worktools\llama-cpp-cpu"
    vulkan = "C:\worktools\llama-cpp-vulkan"
    models = "C:\worktools\gguf-models"
}

# --- Common server flags (applied to all models) ---
# Keys map 1:1 to llama-server CLI flags. Use $null for bare flags (no value).
$CommonArgs = [ordered]@{
    "-t"              = 12       # CPU threads (P-cores only on i7-12800H)
    "-n"              = -1       # Max tokens to predict (-1 = unlimited)
    "-mg"             = 1        # Main GPU index — 0 = Intel Iris Xe, 1 = NVIDIA T600
    "--port"          = 5001
    "--host"          = "127.0.0.1"
    "--log-verbosity" = 0		 # 1 lowest, 10 highest
    "--no-webui"      = $null    # bare flag
    "--offline"       = $null    # bare flag
    "-fa"             = "on"     # Flash Attention (accepts on|off|auto)
}

# =============================================================================
# MODEL REGISTRY
# Each entry is a hashtable with:
#   File        - GGUF filename (resolved against $Paths.models)
#   Args        - hashtable of model-specific flags
#   Reasoning   - value for --reasoning flag: "on", "off", or $null (omit flag)
#   Description - shown in status output
# =============================================================================
$ModelRegistry = @{

    "qwen3.5-9b" = @{
        Description       = "Qwen3.5 9B (thinking, Q4_K_XL)"
        File              = "Qwen3.5-9B-UD-Q4_K_XL.gguf"
        Reasoning         = "on"
        Args              = [ordered]@{
            "-ngl"              = 15       # ~3.3 GB on T600 — tune up if VRAM allows
            "--cache-type-k"    = "q8_0"
            "--cache-type-v"    = "q8_0"
            "-c"                = 16384
            "--temp"            = 0.6
            "--top-k"           = 20
            "--top-p"           = 0.95
            "--min-p"           = 0.0
            "--presence-penalty"= 1.0
        }
    }

    "qwen3.5-9b-instruct" = @{
        Description       = "Qwen3.5 9B (non-thinking / instruct, Q4_K_XL)"
        File              = "Qwen3.5-9B-UD-Q4_K_XL.gguf"
        Reasoning         = "off"
        Args              = [ordered]@{
            "-ngl"              = 15
            "--cache-type-k"    = "q8_0"
            "--cache-type-v"    = "q8_0"
            "-c"                = 16384
            "--temp"            = 0.7
            "--top-k"           = 20
            "--top-p"           = 0.8
            "--min-p"           = 0.0
            "--presence-penalty"= 1.5
        }
    }

    "qwen3.5-4b" = @{
        Description       = "Qwen3.5 4B (thinking, Q4_K_XL)"
        File              = "Qwen3.5-4B-UD-Q4_K_XL.gguf"
        Reasoning         = "on"
        Args              = [ordered]@{
			"-t"				= 4
			"--threads-batch" 	= 8
            "-ngl"              = 99		# 33 layers, leads to OOM if kept at 99" or -1 for auto/all
			"--no-mmap"			= $null
            "--cache-type-k"    = "q4_0"
            "--cache-type-v"    = "q4_0"
            "-c"                = 8192
			"-b"				= 2048
			"-ub"				= 768
			"--prio"			= 3
            "--temp"            = 0.6
            "--top-k"           = 20
            "--top-p"           = 0.95
            "--min-p"           = 0.0
            "--presence-penalty"= 1.0
        }
    }

    "qwen3.5-4b-instruct" = @{
        Description       = "Qwen3.5 4B (non-thinking / instruct, Q4_K_XL)"
        File              = "Qwen3.5-4B-UD-Q4_K_XL.gguf"
        Reasoning         = "off"
        Args              = [ordered]@{
			"-t"				= 4
			"--threads-batch" 	= 8
            "-ngl"              = 99		# 33 layers, leads to OOM if kept at 99" or -1 for auto/all
			"--no-mmap"			= $null
            "--cache-type-k"    = "q4_0"
            "--cache-type-v"    = "q4_0"
            "-c"                = 8192
			"-b"				= 2048
			"-ub"				= 512
			"--prio"			= 3
            "--reasoning-format"= "none"
            "--reasoning-budget"= 0
            "--temp"            = 0.7
            "--top-k"           = 20
            "--top-p"           = 0.8
            "--min-p"           = 0.0
            "--presence-penalty"= 1.5
        }
    }

    "qwen3-4b-it-2507" = @{
        Description       = "Qwen3 4B Instruct 2507 (Q5_K_M)"
        File              = "Qwen3-4B-Instruct-2507-Q5_K_M.gguf"
        Reasoning         = $null
        Args              = [ordered]@{
            "-ngl"              = 20
            "-c"                = 8192
            "-ub"               = 2048
            "-b"                = 2048
            "--jinja"           = $null
            "--temp"            = 0.7
            "--top-k"           = 20
            "--top-p"           = 0.8
            "--min-p"           = 0.0
            "--presence-penalty"= 1.0
        }
    }

    "gemma-3n-e4b" = @{
        Description       = "Gemma 3n E4B Instruct (Q4_K_M)"
        File              = "gemma-3n-E4B-it-Q4_K_M.gguf"
        Reasoning         = $null
        Args              = [ordered]@{
            "-ngl"              = 20
            "--n-cpu-moe"       = 12
            "-c"                = 4096
            "-ub"               = 2048
            "-b"                = 2048
            "--temp"            = 1.0
            "--top-k"           = 64
            "--top-p"           = 0.95
            "--min-p"           = 0.0
            "--repeat-penalty"  = 1.0
        }
    }

    "gpt-oss-20b" = @{
        Description       = "GPT-OSS 20B (Q5_K_M, non-thinking)"
        File              = "gpt-oss-20b-Q5_K_M.gguf"
        Reasoning         = $null
        Args              = [ordered]@{
            "-c"                = 8192
            "-ub"               = 2048
            "-b"                = 2048
            "--n-cpu-moe"       = 35
            "--jinja"           = $null
            "--reasoning-format"= "none"
            "--reasoning-budget"= 0
            "--temp"            = 1.0
            "--top-k"           = 0
            "--top-p"           = 1.0
        }
    }

    "liquidai-lfm2-2.6b" = @{
        Description       = "LiquidAI LFM2 2.6B (Q8_0)"
        File              = "LFM2-2.6B-Q8_0.gguf"
        Reasoning         = $null
        Args              = [ordered]@{
            "-ngl"              = 99
            "--temp"            = 0.3
            "--min-p"           = 0.15
            "--presence-penalty"= 1.05
        }
    }
}

# =============================================================================
# DERIVED PATHS — do not edit below this line
# =============================================================================
$BasePath      = $Paths[$Backend]
$ServerExe     = Join-Path $BasePath "llama-server.exe"
$CliExe        = Join-Path $BasePath "llama-cli.exe"
$PidFile       = Join-Path $BasePath ".pid"

# =============================================================================
# ARGUMENT BUILDER
# Converts an ordered hashtable into a clean string[] suitable for Start-Process.
# Bare flags (value = $null) are emitted without a value.
# =============================================================================
function Build-ArgArray {
    param(
        [System.Collections.Specialized.OrderedDictionary]$ArgTable
    )
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $ArgTable.Keys) {
        $val = $ArgTable[$key]
        if ($null -eq $val) {
            $result.Add($key)
        } else {
            $result.Add($key)
            $result.Add([string]$val)
        }
    }
    return $result.ToArray()
}

function Get-ResolvedModelConfig {
    param([string]$ModelName)

    $key = $ModelName.Trim().ToLower()
    if (-not $ModelRegistry.ContainsKey($key)) {
        return $null
    }
    $config = $ModelRegistry[$key]
    $config.ModelPath = Join-Path $Paths.models $config.File
    return $config
}

function Build-ServerArgArray {
    param([string]$ModelName)

    $config = Get-ResolvedModelConfig -ModelName $ModelName
    if (-not $config) { return $null }

    # Merge: common args first, then model-specific (model wins on collision)
    $merged = [ordered]@{}
    foreach ($k in $CommonArgs.Keys)          { $merged[$k] = $CommonArgs[$k] }
    foreach ($k in $config.Args.Keys)         { $merged[$k] = $config.Args[$k] }

    # Prepend model path
    $merged = [ordered]@{ "-m" = $config.ModelPath } + $merged

    # Append --reasoning if defined for this model
    if ($config.Reasoning) {
        $merged["--reasoning"] = $config.Reasoning
    }

    return Build-ArgArray -ArgTable $merged
}

# =============================================================================
# PID FILE HELPERS
# =============================================================================
function Get-TrackedProcess {
    if (-not (Test-Path $PidFile)) { return $null }

    $raw = Get-Content $PidFile -ErrorAction SilentlyContinue
    $parsedPid = 0
    if (-not ([int]::TryParse($raw, [ref]$parsedPid))) {
        Write-Warning "PID file contains invalid value '$raw'. Removing."
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        return $null
    }

    $proc = Get-Process -Id $parsedPid -ErrorAction SilentlyContinue
    if ($proc -and -not $proc.HasExited) {
        return $proc
    }

    Write-Host "  Stale PID $parsedPid — process no longer running." -ForegroundColor DarkYellow
    Remove-Item $PidFile -ErrorAction SilentlyContinue
    return $null
}

function Write-PidFile {
    param([int]$ProcessId)
    Set-Content -Path $PidFile -Value $ProcessId -Force
    Write-Host "  PID $ProcessId saved to '$PidFile'." -ForegroundColor DarkGreen
}

# =============================================================================
# MENU ACTIONS
# =============================================================================
function Start-Server {
    Write-Host "`n[Start]" -ForegroundColor Cyan

    $existing = Get-TrackedProcess
    if ($existing) {
        Write-Host "  Server already running — PID $($existing.Id). Aborting." -ForegroundColor Yellow
        return
    }

    $config = Get-ResolvedModelConfig -ModelName $ActiveModel
    if (-not $config) {
        Write-Error "  Model '$ActiveModel' not found in registry."
        return
    }
    if (-not (Test-Path $config.ModelPath)) {
        Write-Error "  Model file not found: $($config.ModelPath)"
        return
    }
    if (-not (Test-Path $ServerExe)) {
        Write-Error "  Server executable not found: $ServerExe"
        return
    }

    $args = Build-ServerArgArray -ModelName $ActiveModel

    Write-Host "  Backend  : $Backend ($BasePath)" -ForegroundColor DarkCyan
    Write-Host "  Model    : $($config.Description)" -ForegroundColor DarkCyan
    Write-Host "  Command  : $ServerExe $($args -join ' ')" -ForegroundColor DarkGray

    try {
        $proc = Start-Process -FilePath $ServerExe `
                              -ArgumentList $args `
                              -NoNewWindow `
                              -PassThru `
                              -ErrorAction Stop
        Write-PidFile -ProcessId $proc.Id
        Write-Host "  Server started — PID $($proc.Id). Listening on port $($CommonArgs['--port'])." -ForegroundColor Green
    } catch {
        Write-Host "  Failed to start server: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Show-Status {
    Write-Host "`n[Status]" -ForegroundColor Cyan

    $proc = Get-TrackedProcess
    if ($proc) {
        $uptime = (Get-Date) - $proc.StartTime
        $config  = Get-ResolvedModelConfig -ModelName $ActiveModel
        Write-Host "  Status   : RUNNING" -ForegroundColor Green
        Write-Host "  PID      : $($proc.Id)"
        Write-Host "  Uptime   : $([math]::Round($uptime.TotalMinutes, 1)) min"
        Write-Host "  Model    : $($config.Description)"
        Write-Host "  Backend  : $Backend"
        Write-Host "  Endpoint : http://127.0.0.1:$($CommonArgs['--port'])/v1"
    } else {
        Write-Host "  Status   : NOT RUNNING" -ForegroundColor Red
    }
}

function Stop-Server {
    Write-Host "`n[Stop]" -ForegroundColor Cyan

    $proc = Get-TrackedProcess
    if (-not $proc) {
        Write-Host "  No tracked server process found." -ForegroundColor Yellow
    } else {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Host "  PID $($proc.Id) stopped." -ForegroundColor Green
        } catch {
            Write-Host "  Could not stop PID $($proc.Id): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if (Test-Path $PidFile) {
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        Write-Host "  PID file removed." -ForegroundColor DarkGreen
    }
}

function Restart-Server {
    Write-Host "`n[Restart]" -ForegroundColor Cyan
    Stop-Server
    Start-Sleep -Seconds 1
    Start-Server
}

function Show-Version {
    Write-Host "`n[Version]" -ForegroundColor Cyan
    if (-not (Test-Path $CliExe)) {
        Write-Host "  llama-cli not found at: $CliExe" -ForegroundColor Red
        return
    }

    $output = & $CliExe --version 2>&1

    $versionMatch = $output | Select-String -Pattern 'version:\s*(\d+)'
    if ($versionMatch) {
        Write-Host "  llama.cpp build : $($versionMatch.Matches.Groups[1].Value)" -ForegroundColor Green
    } else {
        Write-Host "  llama.cpp build : (could not parse)" -ForegroundColor Yellow
    }
    Write-Host "  Backend         : $Backend"
    Write-Host "  Executable      : $CliExe"

    # Print full output with colour coding:
    #   Green    - CUDA/Vulkan device found summary line
    #   DarkCyan - individual device detail lines, load_backend lines
    #   DarkGray - everything else
    Write-Host ""
    Write-Host "  --- llama-cli --version output ---" -ForegroundColor DarkGray
    foreach ($line in $output) {
        $text = $line.ToString()
        if ($text -match 'found \d+ CUDA device|found \d+ Vulkan device') {
            Write-Host "  $text" -ForegroundColor Green
        } elseif ($text -match 'Device \d+:' -or $text -match 'ggml_cuda_init|ggml_vulkan') {
            Write-Host "  $text" -ForegroundColor DarkCyan
        } elseif ($text -match 'load_backend') {
            Write-Host "  $text" -ForegroundColor DarkCyan
        } else {
            Write-Host "  $text" -ForegroundColor DarkGray
        }
    }
}

function Show-Config {
    Write-Host "`n[Config Preview]" -ForegroundColor Cyan
    $config = Get-ResolvedModelConfig -ModelName $ActiveModel
    if (-not $config) {
        Write-Host "  Model '$ActiveModel' not in registry." -ForegroundColor Red
        return
    }
    $args = Build-ServerArgArray -ModelName $ActiveModel
    Write-Host "  Model    : $($config.Description)" -ForegroundColor DarkCyan
    Write-Host "  Backend  : $Backend" -ForegroundColor DarkCyan
    Write-Host "  File     : $($config.ModelPath)" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Full command:" -ForegroundColor DarkGray
    Write-Host "  $ServerExe \" -ForegroundColor White
    for ($i = 0; $i -lt $args.Length; $i += 2) {
        if ($i + 1 -lt $args.Length -and -not $args[$i+1].StartsWith('-')) {
            Write-Host "    $($args[$i]) $($args[$i+1]) \" -ForegroundColor White
        } else {
            Write-Host "    $($args[$i]) \" -ForegroundColor White
            $i--  # flag had no value, don't skip next
        }
    }
}

# =============================================================================
# MAIN MENU LOOP
# =============================================================================
function Show-Menu {
    $config = Get-ResolvedModelConfig -ModelName $ActiveModel
    $modelLabel = if ($config) { $config.Description } else { "$ActiveModel (NOT FOUND)" }

    Write-Host "`n╔══════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "║      llama-server Manager            ║" -ForegroundColor DarkCyan
    Write-Host "╠══════════════════════════════════════╣" -ForegroundColor DarkCyan
    Write-Host "║  Model  : $($modelLabel.PadRight(27))║" -ForegroundColor White
    Write-Host "║  Backend: $($Backend.PadRight(27))║" -ForegroundColor White
    Write-Host "╠══════════════════════════════════════╣" -ForegroundColor DarkCyan
    Write-Host "║  1. Start server                     ║" -ForegroundColor White
    Write-Host "║  2. Status                           ║" -ForegroundColor White
    Write-Host "║  3. Stop server                      ║" -ForegroundColor White
    Write-Host "║  4. Restart server                   ║" -ForegroundColor White
    Write-Host "║  5. Preview config / command         ║" -ForegroundColor White
    Write-Host "║  6. Print version                    ║" -ForegroundColor White
    Write-Host "║  Q. Quit                             ║" -ForegroundColor White
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor DarkCyan
}

Show-Menu
$choice = (Read-Host "`n  Enter choice").Trim().ToUpper()

switch ($choice) {
    "1" { Start-Server }
    "2" { Show-Status }
    "3" { Stop-Server }
    "4" { Restart-Server }
    "5" { Show-Config }
    "6" { Show-Version }
    "Q" { Write-Host "`n  Goodbye." -ForegroundColor Green }
    default { Write-Host "`n  Invalid choice '$choice'." -ForegroundColor Red }
}
<#
.SYNOPSIS
    Gathers detailed system configuration, including CPU, RAM, storage, network, and GPU information.
    Also attempts to detect CUDA and Vulkan support.

.DESCRIPTION
    This script provides a comprehensive overview of your system's hardware and software.
    It leverages WMI (Windows Management Instrumentation), system commands, and checks for
    the presence of NVIDIA CUDA Toolkit and Vulkan SDK tools to determine relevant support
    for local LLM execution.

.NOTES
    Author: AI Assistant
    Date: July 12, 2025
    Requires: PowerShell 5.1 or later (for Get-CimInstance, Get-ComputerInfo)
    Run with Administrator privileges for best results.
#>

Function Get-SystemInfo {
    Write-Host "Gathering System Information..." -ForegroundColor Green
    Write-Host "---------------------------------------------------`n"

    # --- System Information ---
    Write-Host "### System ###" -ForegroundColor Cyan
    Get-ComputerInfo | Select-Object @{N='OS Name';E={$_.OsName}},
                                    @{N='OS Version';E={$_.OsVersion}},
                                    @{N='OS Build';E={$_.OsBuildNumber}},
                                    @{N='System Manufacturer';E={$_.CsManufacturer}},
                                    @{N='System Model';E={$_.CsModel}},
                                    @{N='Processor';E={(Get-CimInstance Win32_Processor).Name}},
                                    @{N='Logical Processors';E={(Get-CimInstance Win32_Processor).NumberOfLogicalProcessors}},
                                    @{N='Physical Cores';E={(Get-CimInstance Win32_Processor).NumberOfCores}},
                                    @{N='Total Physical Memory (GB)';E={[math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB), 2)}},
                                    @{N='Free Physical Memory (GB)';E={[math]::Round(((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1GB), 2)}} | Format-List

    # --- Storage Information ---
    Write-Host "`n### Storage (C: Drive) ###" -ForegroundColor Cyan
    Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object @{N='Drive Letter';E={$_.DeviceID}},
                                                                 @{N='File System';E={$_.FileSystem}},
                                                                 @{N='Total Size (GB)';E={[math]::Round(($_.Size / 1GB), 2)}},
                                                                 @{N='Free Space (GB)';E={[math]::Round(($_.FreeSpace / 1GB), 2)}} | Format-List

    # --- Network Information ---
    Write-Host "`n### Network Adapters ###" -ForegroundColor Cyan
    Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true } | Select-Object Description,
                                                                                                    @{N='IP Address';E={$_.IPAddress[0]}},
                                                                                                    @{N='MAC Address';E={$_.MACAddress}} | Format-List

    # --- GPU Information ---
    Write-Host "`n### GPU Information ###" -ForegroundColor Cyan
    $gpus = Get-CimInstance Win32_VideoController
    if ($gpus) {
        foreach ($gpu in $gpus) {
            Write-Host "  Name: $($gpu.Name)"
            Write-Host "  Adapter RAM: $($gpu.AdapterRAM / 1MB) MB"
            Write-Host "  Driver Version: $($gpu.DriverVersion)"
            Write-Host "  Driver Date: $($gpu.DriverDate)"
            Write-Host "  Video Processor: $($gpu.VideoProcessor)"
            Write-Host "  PNP Device ID: $($gpu.PNPDeviceID)"
            Write-Host ""
        }
    } else {
        Write-Host "  No GPU information found via Win32_VideoController."
    }

    # --- Check for CUDA Support ---
    Write-Host "`n### CUDA Support ###" -ForegroundColor Cyan
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        Write-Host "  NVIDIA GPU detected and nvidia-smi found. Checking CUDA information..."
        try {
            $nvidiaSmiOutput = nvidia-smi
            $cudaVersionLine = $nvidiaSmiOutput | Select-String "CUDA Version"
            if ($cudaVersionLine) {
                Write-Host "  $($cudaVersionLine.ToString().Trim())"
            } else {
                Write-Host "  Could not parse CUDA Version from nvidia-smi output."
            }
            Write-Host "  (Run 'nvidia-smi' in Command Prompt/PowerShell for full details)"
        }
        catch {
            Write-Host "  Error running nvidia-smi: $($_.Exception.Message)"
        }
        Write-Host "  Generally, if nvidia-smi is available and shows a CUDA version, your NVIDIA GPU supports CUDA."
    } elseif ($gpus | Where-Object { $_.Name -like "*NVIDIA*" }) {
        Write-Host "  NVIDIA GPU detected, but 'nvidia-smi' command not found."
        Write-Host "  CUDA support is likely, but you may need to install the NVIDIA CUDA Toolkit for full functionality."
        Write-Host "  Download from: https://developer.nvidia.com/cuda-downloads"
    } else {
        Write-Host "  No NVIDIA GPU detected. CUDA is specific to NVIDIA GPUs."
    }

    # --- Check for Vulkan Support ---
    Write-Host "`n### Vulkan Support ###" -ForegroundColor Cyan
    # Checking for Vulkan often involves checking for the Vulkan Runtime or SDK.
    # The vulkaninfo tool is part of the Vulkan SDK.
    if (Get-Command vulkaninfo -ErrorAction SilentlyContinue) {
        Write-Host "  'vulkaninfo' command found. Checking Vulkan information..."
        try {
            # Use the call operator (&) to ensure vulkaninfo.exe receives its arguments correctly
            $vulkanInfoOutput = & vulkaninfo.exe --summary 2>&1 # 2>&1 redirects stderr to stdout for capture
            if ($vulkanInfoOutput) {
                Write-Host "  Vulkan Info Summary:"
                # Filter out the help text if it still appears due to some specific vulkaninfo versions or environments
                $vulkanInfoOutput | Where-Object { $_ -notmatch "vulkaninfo - Summarize Vulkan information" -and $_ -notmatch "USAGE:" } | ForEach-Object { Write-Host "    $_" }
            } else {
                Write-Host "  Could not get summary from vulkaninfo, or output was empty."
            }
            Write-Host "  (Run 'vulkaninfo' in Command Prompt/PowerShell for full details)"
        }
        catch {
            Write-Host "  Error running vulkaninfo: $($_.Exception.Message)"
            Write-Host "  Ensure 'vulkaninfo' is in your PATH and accessible."
        }
        Write-Host "  If 'vulkaninfo' executes, your system likely has Vulkan support and compatible drivers."
    } else {
        Write-Host "  'vulkaninfo' command not found."
        Write-Host "  Vulkan support requires appropriate GPU drivers and the Vulkan Runtime/SDK."
        Write-Host "  You can check for Vulkan drivers via your GPU vendor's website or install the Vulkan SDK:"
        Write-Host "  Download Vulkan SDK: [https://sdk.lunarg.com/sdk/download/](https://sdk.lunarg.com/sdk/download/)"
        # Attempt to see if any display adapters mention Vulkan in their capabilities (less reliable)
        $gpus | ForEach-Object {
            if ($_.DriverVersion -like "*vulkan*" -or $_.Caption -like "*Vulkan*") {
                Write-Host "  (Potentially Vulkan-capable GPU driver detected: $($_.Name))"
            }
        }
    }

    Write-Host "`n---------------------------------------------------"
    Write-Host "Script finished. Review the output above." -ForegroundColor Green
}

# Run the function
Get-SystemInfo
# This script runs the whisper-cli.exe tool with a specified MP3 audio file.

# Define a parameter for the audio file path.
# The `[string]` specifies the data type, and `[Parameter(Mandatory=$true)]`
# makes it a required argument for the script to run.
param(
    [Parameter(Mandatory=$true)]
    [string]$AudioFilePath
)

# Define the path to the whisper-cli.exe executable.
$WhisperCliPath = "c:\worktools\whisper.cpp-bin\whisper-cli.exe"

# Define the path to the GGUF model file.
$ModelPath = "c:\worktools\gguf-models\ggml-base.bin"

# Check if the whisper-cli.exe executable exists before running.
if (-not (Test-Path $WhisperCliPath)) {
    Write-Host "Error: The whisper-cli.exe file was not found at '$WhisperCliPath'." -ForegroundColor Red
    exit
}

# Check if the model file exists.
if (-not (Test-Path $ModelPath)) {
    Write-Host "Error: The model file was not found at '$ModelPath'." -ForegroundColor Red
    exit
}

# Check if the provided audio file path exists.
if (-not (Test-Path $AudioFilePath)) {
    Write-Host "Error: The audio file was not found at '$AudioFilePath'." -ForegroundColor Red
    exit
}

# Construct the arguments for the command.
# The -m argument is followed by the model path, and the audio file path is the final argument.
$arguments = "-m", $ModelPath, $AudioFilePath

# Use the call operator `&` to execute the command with the defined arguments.
# This ensures that spaces or special characters in paths are handled correctly.
Write-Host "Executing command: $WhisperCliPath -m $ModelPath $AudioFilePath"
& $WhisperCliPath $arguments

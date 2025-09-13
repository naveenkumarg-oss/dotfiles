Set-Alias -Name "sysinfo" -Value $HOME\Documents\PowerShell\SystemInfo.ps1

Set-Alias -Name "llm" -Value $HOME\Documents\PowerShell\llama-cpp.ps1

if (Test-Path (Get-Command nvim).path) {
	Set-Alias -Name "n" -Value (Get-Command nvim).path
}

function Sync-Obsidian {
	if (Test-Path $HOME\my-docs\tools\private-obsidian-vault) {
		gsync "$HOME\my-docs\tools\private-obsidian-vault"
	}
}
Set-Alias -Name ob -Value Sync-Obsidian -Description "Sync Obsidian changes to GitHub."

function Invoke-Whisper {
    param(
        [string]$AudioFile
    )

    $AudioFilePath = Join-Path -Path "$HOME\Music" -ChildPath $AudioFile
    $WhisperScriptPath = Join-Path -Path "$HOME\Documents\PowerShell" -ChildPath "whisper-cpp.ps1"

    if (Test-Path -Path $AudioFilePath -PathType Leaf) {
        if (Test-Path -Path $WhisperScriptPath) {
            Invoke-Expression "& '$WhisperScriptPath' -AudioFilePath '$AudioFilePath'"
        } else {
            Write-Error "The whisper-cpp.ps1 script was not found at $WhisperScriptPath"
        }
    } else {
        Write-Error "The audio file was not found: $AudioFilePath"
    }
}
Set-Alias -Name whisper -Value Invoke-Whisper -Description "Transcribes audio to text."
# whisper "2025-09-13-09-46-42.mp3"
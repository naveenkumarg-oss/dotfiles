# Install latest version of `Microsoft.PowerShell.PSResourceGet` so that other modules can be installed.
# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/?view=powershellget-3.x
if(-not (Get-Module PowerShellGet -ListAvailable)) {
    Write-Host "Installing Microsoft.PowerShell.PSResourceGet" -ForegroundColor Cyan
    Install-Module -Name Microsoft.PowerShell.PSResourceGet
}

if(-not (Get-Module Terminal-Icons -ListAvailable)) {
    Install-PSResource -Name Terminal-Icons -Reinstall -Repository PSGallery
}

if(-not (Get-Module PSReadLine -ListAvailable)) {
    Install-PSResource -Name PSReadLine -Reinstall -Repository PSGallery
}

# Install Nerd Fonts
If (Test-Path "$ENV:USERPROFILE\AppData\Local\Microsoft\Windows\Fonts\MonoidNerdFont-Regular.ttf") { 
    Write-Host "Font Monoid is already installed..." -ForegroundColor Green
} else { 
    Write-Host "Font is not installed" -ForegroundColor Cyan

    Set-Location $HOME\.local\share
    git clone --filter=blob:none --sparse https://github.com/ryanoasis/nerd-fonts.git
    
    Set-Location nerd-fonts
    git sparse-checkout add patched-fonts/Monoid
    
    ./install.ps1 Monoid
}
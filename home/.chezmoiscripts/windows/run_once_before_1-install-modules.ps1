# Install-PSResource is the newer cmdlet introduced with PowerShellGet v3 and is the successor to Install-Module. 
# Especially PowerShell 7.x and later, favor using Install-PSResource for module installation. 
# If you are using an older version, consider installing Microsoft.PowerShell.PSResourceGet to enable Install-PSResource

# In 2025, we are using PowerShell 7.5 and later. Don't expect to use older versions of PowerShell.
# Install latest version of `Microsoft.PowerShell.PSResourceGet` so that other modules can be installed.
# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/?view=powershellget-3.x
# if(-not (Get-Module PowerShellGet -ListAvailable)) {
#     Write-Host "Installing Microsoft.PowerShell.PSResourceGet" -ForegroundColor Cyan
#     Install-Module -Name Microsoft.PowerShell.PSResourceGet
# }

if(-not (Get-Module Terminal-Icons -ListAvailable)) {
    Install-PSResource -Name Terminal-Icons -Reinstall -Repository PSGallery
}

if(-not (Get-Module PSReadLine -ListAvailable)) {
    Install-PSResource -Name PSReadLine -Prerelease
}

if(-not (Get-Module z -ListAvailable)) {
    Install-PSResource -Name z
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
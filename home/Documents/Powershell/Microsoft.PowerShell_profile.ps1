Invoke-Expression (&starship init powershell)

# https://github.com/devblackops/Terminal-Icons
Import-Module -Name Terminal-Icons

# Import Module PSReadLine and configure using the sample profile from the PSReadLine module.
$psreadlineModulePath = (Get-Module PSReadLine).ModuleBase
$sampleProfile = Join-Path $psreadlineModulePath 'SamplePSReadLineProfile.ps1'
if (Test-Path $sampleProfile) {
    . $sampleProfile
}

# https://github.com/badmotorfinger/z
Import-Module -Name z

# Determine user profile parent directory.
$ProfilePath=Split-Path -parent $profile

# Load functions declarations from separate configuration file.
if (Test-Path $ProfilePath/functions.ps1) {
    . $ProfilePath/functions.ps1
}

# Load alias definitions from separate configuration file.
if (Test-Path $ProfilePath/aliases.ps1) {
    . $ProfilePath/aliases.ps1
}

# Load custom code from separate configuration file.
if (Test-Path $ProfilePath/extras.ps1) {
    . $ProfilePath/extras.ps1
}

$env:Path += ";$env:UserProfile\.local\bin"

# Alias
function gst { git status } 
param([Parameter(Mandatory=$true)][string]$ExePath)
# User-level registration. Must point to the installed/packaged Windows exe, not a temporary build.
if (!(Test-Path -LiteralPath $ExePath)) { throw "Executable not found: $ExePath" }
$full = (Resolve-Path -LiteralPath $ExePath).Path
$base = 'HKCU:\Software\Classes\mandai-merchandise'
New-Item -Path $base -Force | Out-Null
Set-Item -Path $base -Value 'URL:Mandai Merchandise Payment Return'
New-ItemProperty -Path $base -Name 'URL Protocol' -PropertyType String -Value '' -Force | Out-Null
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-Item -Path "$base\shell\open\command" -Value ('"' + $full + '" "%1"')
Write-Host 'Registered custom URL scheme for the current Windows user.'
Write-Host 'Windows Flutter runner must forward URI command-line to app_links; see README.'

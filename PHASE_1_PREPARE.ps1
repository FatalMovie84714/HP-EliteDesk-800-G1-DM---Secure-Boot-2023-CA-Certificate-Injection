# ==============================================================================
# AUTHORIZED COMPLIANCE DEPLOYMENT: SECURE BOOT PHASE 1 PREPARE (LOGGING ACTIVE)
# TARGET PLATFORM: HP ELITEDESK 800 G1 DM (OFFLINE STANDALONE DEPLOYMENT)
# ==============================================================================

$CurrentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $CurrentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "CRITICAL ERROR: This deployment script must be executed within an elevated Administrator session."
    Exit
}

try {
    $SBStatus = Confirm-SecureBootUEFI
} catch {
    Write-Error "CRITICAL ERROR: Secure Boot UEFI infrastructure is unavailable or disabled. Verify BIOS configurations."
    Exit
}

$DesktopPath    = "$env:USERPROFILE\Desktop"
$MS2023CertPath = Join-Path $DesktopPath "windows uefi ca 2023.crt"
$CustomPKPath   = Join-Path $DesktopPath "custom_pk.crt"
$Win2011Path    = Join-Path $DesktopPath "MicWinProPCA2011.crt"
$Uefi2011Path   = Join-Path $DesktopPath "MicCorUEFCA2011.crt"
$ReportPath     = Join-Path $DesktopPath "SecureBoot_Deployment_Report.txt"

if (-not (Test-Path $MS2023CertPath)) {
    Write-Error "CRITICAL FILE MISSING: 'windows uefi ca 2023.crt' was not found on the Desktop."
    Exit
}

# Initialize Log Report File
$Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$HeaderBlock = @"
================================================================================
                       SECURE BOOT COMPLIANCE AUDIT REPORT
================================================================================
Timestamp           : $Timestamp
Host Workstation    : $env:COMPUTERNAME
Operating System    : $((Get-WmiObject Win32_OperatingSystem).Caption) (Build $((Get-WmiObject Win32_OperatingSystem).BuildNumber))
Hardware Platform   : HP EliteDesk 800 G1 DM (Haswell Architecture)

[PHASE 1: STAGING & EXTRACTION]
--------------------------------------------------------------------------------
"@
$HeaderBlock | Out-File -FilePath $ReportPath -Encoding utf8

function Write-Log($Message, $IsError = $false) {
    $Prefix = if ($IsError) { "[-]" } else { "[+]" }
    $FormattedMessage = "$Prefix $Message"
    Write-Output $FormattedMessage
    $FormattedMessage | Out-File -FilePath $ReportPath -Append -Encoding utf8
}

Write-Log "Environment verified. Starting offline cryptographic payload compilation..."
Write-Log "Querying firmware non-volatile storage for active signature databases..."

try {
    $DBBytes = (Get-SecureBootUEFI -Name db).Bytes
} catch {
    Write-Log "READ FAILURE: Unable to access the active 'db' variable. Ensure system is booted under standard HP factory keys." -IsError $true
    Exit
}

Remove-Item $Win2011Path, $Uefi2011Path -ErrorAction SilentlyContinue

$Index = 0
$CertCount = 1
while ($Index -lt $DBBytes.Length) {
    if ($DBBytes[$Index] -eq 0x30 -and $DBBytes[$Index+1] -eq 0x82) {
        $Length = ($DBBytes[$Index+2] * 256) + $DBBytes[$Index+3] + 4
        if (($Index + $Length) -le $DBBytes.Length) {
            $CertBytes = $DBBytes[$Index..($Index + $Length - 1)]
            
            if ($CertCount -eq 1) {
                [System.IO.File]::WriteAllBytes($Win2011Path, $CertBytes)
                Write-Log "Natively extracted 'Windows Production PCA 2011' structure."
            } elseif ($CertCount -eq 2) {
                [System.IO.File]::WriteAllBytes($Uefi2011Path, $CertBytes)
                Write-Log "Natively extracted 'Microsoft Corporation UEFI CA 2011' structure."
            }
            $CertCount++
            $Index += $Length - 1
        }
    }
    $Index++
}

if (-not (Test-Path $Win2011Path) -or -not (Test-Path $Uefi2011Path)) {
    Write-Log "EXTRACTION FAILURE: Failed to securely isolate native 2011 boot keys from firmware memory." -IsError $true
    Exit
}

Write-Log "Synthesizing administrative Platform Key container..."
Remove-Item $CustomPKPath -ErrorAction SilentlyContinue

$NewCert = New-SelfSignedCertificate -Type Custom -Subject "CN=Custom PK" -KeyUsage DigitalSignature -FriendlyName "Custom PK" -CertStoreLocation "Cert:\CurrentUser\My"
Export-Certificate -Cert $NewCert -FilePath $CustomPKPath | Out-Null

if (-not (Test-Path $CustomPKPath)) {
    Write-Log "COMPILATION FAILURE: Failed to generate or write 'custom_pk.crt' to workspace." -IsError $true
    Exit
}
Write-Log "Successfully generated private administrative token: 'custom_pk.crt' (Thumbprint: $($NewCert.Thumbprint))."

Write-Output ""
Write-Output "================================================================================"
Write-Output "                     MANDATORY HARDWARE INTERACTION REQUIRED                    "
Write-Output "================================================================================"
Write-Output " Phase 1 has completed. Report initialized at Desktop\SecureBoot_Deployment_Report.txt"
Write-Output " Follow the documented BIOS change rules to toggle 'Clear Keys' to 'Custom' mode."
Write-Output "================================================================================"
Write-Output ""

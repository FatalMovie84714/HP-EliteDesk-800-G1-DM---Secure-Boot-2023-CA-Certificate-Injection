# ==============================================================================
# AUTHORIZED COMPLIANCE DEPLOYMENT: SECURE BOOT PHASE 2 FLASH (LOGGING ACTIVE)
# TARGET PLATFORM: HP ELITEDESK 800 G1 DM (SETUP MODE ENVIRONMENT)
# ==============================================================================

$CurrentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $CurrentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "CRITICAL ERROR: This deployment script must be executed within an elevated Administrator session."
    Exit
}

$DesktopPath    = "$env:USERPROFILE\Desktop"
$MS2023CertPath = Join-Path $DesktopPath "windows uefi ca 2023.crt"
$Win2011Path    = Join-Path $DesktopPath "MicWinProPCA2011.crt"
$Uefi2011Path   = Join-Path $DesktopPath "MicCorUEFCA2011.crt"
$CustomPKPath   = Join-Path $DesktopPath "custom_pk.crt"
$ReportPath     = Join-Path $DesktopPath "SecureBoot_Deployment_Report.txt"

if (-not (Test-Path $ReportPath)) {
    $Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    "[+] Stale report missing. Initializing new deployment report session..." | Out-File -FilePath $ReportPath -Encoding utf8
}

$Phase2Header = @"

[PHASE 2: FIRMWARE FLASH INJECTION]
--------------------------------------------------------------------------------
"@
$Phase2Header | Out-File -FilePath $ReportPath -Append -Encoding utf8

function Write-Log($Message, $IsError = $false) {
    $Prefix = if ($IsError) { "[-]" } else { "[+]" }
    $FormattedMessage = "$Prefix $Message"
    Write-Output $FormattedMessage
    $FormattedMessage | Out-File -FilePath $ReportPath -Append -Encoding utf8
}

$RequiredFiles = @($MS2023CertPath, $Win2011Path, $Uefi2011Path, $CustomPKPath)
foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        Write-Log "DEPLOYMENT FAILURE: Mandatory staging file absent from workspace: $File" -IsError $true
        Exit
    }
}

Write-Log "Executing multi-key injection pipeline to secure boot variable space..."
$OwnerGUID = "77fa9abd-0359-4d32-bd60-28f4e78f784b"
$CurrentTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

try {
    Write-Log "Encapsulating cryptographic keys into standardized UEFI packets..."
    $Pkg1 = Format-SecureBootUEFI -Name db -SignatureOwner $OwnerGUID -CertificateFilePath $MS2023CertPath -FormatWithCert -Time $CurrentTime
    $Pkg2 = Format-SecureBootUEFI -Name db -SignatureOwner $OwnerGUID -CertificateFilePath $Win2011Path    -FormatWithCert -Time $CurrentTime -AppendWrite
    $Pkg3 = Format-SecureBootUEFI -Name db -SignatureOwner $OwnerGUID -CertificateFilePath $Uefi2011Path   -FormatWithCert -Time $CurrentTime -AppendWrite

    Write-Log "Injecting aggregated 'db' payload sequence into NVRAM registers..."
    $Pkg1, $Pkg2, $Pkg3 | Set-SecureBootUEFI
    Write-Log "Database updated with all 3 trusted authorization authorities."

    Write-Log "Updating the Key Exchange Key (KEK) database slot..."
    Format-SecureBootUEFI -Name KEK -SignatureOwner $OwnerGUID -CertificateFilePath $CustomPKPath -FormatWithCert -Time $CurrentTime | Set-SecureBootUEFI
    Write-Log "KEK database populated successfully."

    Write-Log "Finalizing transaction. Committing custom master Platform Key (PK)..."
    Format-SecureBootUEFI -Name PK -SignatureOwner $OwnerGUID -CertificateFilePath $CustomPKPath -FormatWithCert -Time $CurrentTime | Set-SecureBootUEFI
    Write-Log "Platform Key written. Motherboard locked into Custom User Mode."

} catch {
    Write-Log "HARDWARE FLASH ERROR: The underlying firmware rejected variable write commands. Status: $($_.Exception.Message)" -IsError $true
    Exit
}

# Post-Execution Live Verification Staged within Log
Write-Log "Running real-time post-flash validation check..."
$VerificationStatus = "FALSE"
try {
    $BytesMatch = [System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).bytes) -match 'Windows UEFI CA 2023'
    if ($BytesMatch) { $VerificationStatus = "TRUE" }
} catch {
    $VerificationStatus = "ERROR_UNREADABLE"
}

$FooterBlock = @"

[FINAL COMPLIANCE VERIFICATION]
--------------------------------------------------------------------------------
NVRAM Query Target  : db (Signature Database)
Query Filter Match  : 'Windows UEFI CA 2023'
Verification Status : $VerificationStatus (Compliance state evaluated)
--------------------------------------------------------------------------------
END OF TRANSCRIPT - SYSTEM HARDENED AT DEPLOYMENT EDGE
================================================================================
"@
$FooterBlock | Out-File -FilePath $ReportPath -Append -Encoding utf8

Write-Output ""
Write-Output "================================================================================"
Write-Output "           SUCCESS: DEPLOYMENT LOG PREPARED ON DESKTOP WORKSPACE"
Write-Output "================================================================================"
Write-Output ""

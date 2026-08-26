# ==========================================
# SECURE BOOT COMPLIANCE TOOL - HP 800 G1 DM
# ==========================================

$CurrentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $CurrentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "CRITICAL ERROR: Run within an elevated Administrator session."
    Exit
}

$DesktopPath    = "$env:USERPROFILE\Desktop"
$MS2023CertPath = Join-Path $DesktopPath "windows uefi ca 2023.crt"
$CustomPKPath   = Join-Path $DesktopPath "custom_pk.crt"
$Win2011Path    = Join-Path $DesktopPath "MicWinProPCA2011.crt"
$Uefi2011Path   = Join-Path $DesktopPath "MicCorUEFCA2011.crt"
$ReportPath     = Join-Path $DesktopPath "SecureBoot_Deployment_Report.txt"

if (-not (Test-Path $MS2023CertPath)) {
    Write-Error "CRITICAL FILE MISSING: Place 'windows uefi ca 2023.crt' on the Desktop."
    Exit
}

$InSetupMode = $false
try {
    $PKBytes = (Get-SecureBootUEFI -Name PK).Bytes
    if ($null -eq $PKBytes -or $PKBytes.Length -eq 0) { $InSetupMode = $true }
} catch {
    $InSetupMode = $true
}

# ==========================================
# RUN 1: EXTRACTION (LOCKED HP FACTORY KEYS)
# ==========================================
if (-not $InSetupMode) {
    Write-Output "[+] RUN 1 DETECTED: Extracting factory authorities..."
    
    $Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    "SECURE BOOT COMPLIANCE AUDIT REPORT" | Out-File -FilePath $ReportPath -Encoding utf8
    "Timestamp : $Timestamp" | Out-File -FilePath $ReportPath -Append
    "Host      : $env:COMPUTERNAME" | Out-File -FilePath $ReportPath -Append

    try {
        $DBBytes = (Get-SecureBootUEFI -Name db).Bytes
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
                        Write-Output "    -> Extracted: 'MicWinProPCA2011.crt'"
                    } elseif ($CertCount -eq 2) {
                        [System.IO.File]::WriteAllBytes($Uefi2011Path, $CertBytes)
                        Write-Output "    -> Extracted: 'MicCorUEFCA2011.crt'"
                    }
                    $CertCount++
                    $Index += $Length - 1
                }
            }
            $Index++
        }
        "[SUCCESS] Factory 2011 certificates isolated cleanly." | Out-File -FilePath $ReportPath -Append
    } catch {
        "[-] CRITICAL EXTRACTION FAILURE: $_" | Out-File -FilePath $ReportPath -Append
        Write-Error "Local file structure parsing failed."
        Exit
    }

    Write-Output "    -> Synthesizing administrative Platform Key container..."
    Remove-Item $CustomPKPath -ErrorAction SilentlyContinue
    $NewCert = New-SelfSignedCertificate -Type Custom -Subject "CN=Custom PK" -KeyUsage DigitalSignature -FriendlyName "Custom PK" -CertStoreLocation "Cert:\CurrentUser\My"
    Export-Certificate -Cert $NewCert -FilePath $CustomPKPath | Out-Null
    Write-Output "    -> Generated master token: 'custom_pk.crt'"

    Write-Output ""
    Write-Output "MANDATORY BIOS GATING HARDWARE CHANGE REQUIRED"
    Write-Output "1. Restart this workstation immediately."
    Write-Output "2. Strike [F10] repeatedly to open the HP Computer Setup utility."
    Write-Output "3. Navigate to: Security -> Secure Boot Configuration."
    Write-Output "4. Execute the command: 'Clear Keys'."
    Write-Output "5. Change configuration item: 'Custom or Hp Keys' to 'Custom'."
    Write-Output "6. Confirm 'Secure Boot' remains set to 'Enabled'."
    Write-Output "7. Save structural changes, exit BIOS, and boot back into Windows."
    Write-Output "8. Run this script again to complete the flash update."
    Write-Output ""
    Exit
}

# ==========================================
# RUN 2: PIPELINE INJECTION & HARDWARE LOCK
# ==========================================
if ($InSetupMode) {
    Write-Output "[+] RUN 2 DETECTED: Motherboard unlocked. Flashing..."

    $RequiredFiles = @($MS2023CertPath, $Win2011Path, $Uefi2011Path, $CustomPKPath)
    foreach ($File in $RequiredFiles) {
        if (-not (Test-Path $File)) {
            Write-Error "DEPLOYMENT FAILURE: Asset absent from workspace: $File"
            Exit
        }
    }

    $OwnerGUID   = "77fa9abd-0359-4d32-bd60-28f4e78f784b"
    $CurrentTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

    try {
        Write-Output "    -> Packaging signatures into memory variables..."
        $Pkg1 = Format-SecureBootUEFI -Name db -SignatureOwner $OwnerGUID -CertificateFilePath $MS2023CertPath -FormatWithCert -Time $CurrentTime
        $Pkg2 = Format-SecureBootUEFI -Name db -SignatureOwner $OwnerGUID -CertificateFilePath $Win2011Path    -FormatWithCert -Time $CurrentTime -AppendWrite
        $Pkg3 = Format-SecureBootUEFI -Name db -SignatureOwner $OwnerGUID -CertificateFilePath $Uefi2011Path   -FormatWithCert -Time $CurrentTime -AppendWrite

        Write-Output "    -> Injecting sequential signature collection block into NVRAM..."
        $Pkg1, $Pkg2, $Pkg3 | Set-SecureBootUEFI
        Write-Output "    -> [SUCCESS] Secure Boot database updated."

        Write-Output "    -> Populating Key Exchange Key (KEK) database slot..."
        $KekPayload = Format-SecureBootUEFI -Name KEK -SignatureOwner $OwnerGUID -CertificateFilePath $CustomPKPath -FormatWithCert -Time $CurrentTime
        $KekPayload | Set-SecureBootUEFI
        Write-Output "    -> [SUCCESS] KEK database link established."

        Write-Output "    -> Finalizing transaction. Sealing custom Platform Key (PK)..."
        $PkPayload = Format-SecureBootUEFI -Name PK -SignatureOwner $OwnerGUID -CertificateFilePath $CustomPKPath -FormatWithCert -Time $CurrentTime
        $PkPayload | Set-SecureBootUEFI
        Write-Output "    -> [SUCCESS] Platform Key written. Motherboard locked into Custom User Mode."

        $Valid = "FALSE"
        $VerifyBytes = [System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).bytes)
        if ($VerifyBytes -match 'Windows UEFI CA 2023') { $Valid = "TRUE" }

        "[PHASE 2: FIRMWARE INJECTION STATUS]" | Out-File -FilePath $ReportPath -Append
        "Flash Execution Status : SUCCESS" | Out-File -FilePath $ReportPath -Append
        "Verification Match State : $Valid" | Out-File -FilePath $ReportPath -Append

        Write-Output ""
        Write-Output "CRITICAL SUCCESS: TRANSITION COMPLETED WITHOUT LOOPS"
        Write-Output "Action: Restart the machine. The BIOS will seal cleanly into User Mode."
        Write-Output ""
    } catch {
        $ErrorMsg = "[-] HARDWARE FLASH EXCEPTION: NVRAM write rejected. Status: $($_.Exception.Message)"
        Write-Error $ErrorMsg
        $ErrorMsg | Out-File -FilePath $ReportPath -Append
        Exit
    }
}

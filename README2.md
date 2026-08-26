# HP EliteDesk 800 G1 DM - Secure Boot Compliance Tool

An automated, two-phase PowerShell deployment utility designed to safely inject the modern **Microsoft Windows UEFI CA 2023** certificate into legacy HP EliteDesk 800 G1 Desktop Mini firmware without bricking the operating system or triggering permanent boot loops.

## The Problem
Legacy 4th-generation Intel (Haswell) business desktops, such as the HP EliteDesk 800 G1, run older UEFI firmware variations that cannot natively parse or process modern automated background Secure Boot certificate payloads (such as Microsoft's staged updates). 

Manually dropping the motherboard into **Setup Mode (Custom Keys / Clear Keys)** allows database writes, but overwriting the signature database (`db`) with a bare 2023 certificate wipes out the legacy **2011 Windows Production PCA** and **2011 UEFI CA** identities. This results in an immediate **"Secure Boot Violation: Invalid signature detected"** error, locking users out of Windows or modern Linux distributions that rely on standard trust chains.

## The Solution
This tool automates a resilient, **completely offline** two-phase deployment cycle:
1. **Run 1 (HP Keys Active):** Leverages native byte-scanning logic to isolate and extract the working factory 2011 cryptographic signatures straight out of active NVRAM firmware memory. It also synthesizes a local custom administrative Platform Key (`custom_pk.crt`).
2. **Hardware Gate:** The user manually sets the BIOS to Custom Mode and clears the keys.
3. **Run 2 (Setup Mode Active):** Streams all three formatted signing certificates (2011 Windows, 2011 Drivers, and 2023 Microsoft) simultaneously via an memory-variable pipeline utilizing explicit sequential `-AppendWrite` flags to bypass legacy hardware overwrite write-locks. Finally, it provisions the custom KEK and seals the firmware environment into a functional **Custom User Mode**.

---

##  Prerequisites & Workspace Prep
Because target host machines may be entirely **offline**, ensure the following parameters are established before executing the script:

1. **Operating System:** Windows 10/11 running PowerShell 5.1+ elevated as an Administrator.
2. **Target File Placement:** Place your official copy of `windows uefi ca 2023.crt` directly onto the current user's **Desktop**.
3. **Initial BIOS State:** Verify your machine is configured for baseline Secure Boot before initiating Phase 1:
   * Legacy Support: **Disabled**
   * Secure Boot: **Enabled**
   * Custom or HP Keys: **HP Keys**

---

##  Step-by-Step Deployment Instructions

### Phase 1: Key Extraction & Preparation
1. Open PowerShell as an **Administrator**.
2. Execute the script (`SecureBoot_Compliance.ps1`).
3. The script will automatically detect that the system is running on protected factory keys. It will pull the 2011 keys to the Desktop, generate your `custom_pk.crt`, log a success state to `SecureBoot_Deployment_Report.txt`, and gracefully halt execution.

### Phase 2: Hardware Gating (BIOS Configuration)
1. Restart the EliteDesk workstation immediately.
2. Press **[F10]** repeatedly during power-on to open the **HP Computer Setup** configuration utility.
3. Use the arrow keys to navigate to: **Security** -> **Secure Boot Configuration**.
4. Change the configuration item **Clear Keys?** to **Clear Keys** (this drops the motherboard into an unlocked Setup Mode).
5. Change the configuration item **Custom or Hp Keys** to **Custom**.
6. Ensure that the master **Secure Boot** switch remains set to **Enabled**.
7. Save changes, exit the BIOS configuration screen, and allow the system to boot back up into Windows.

### Phase 3: Firmware Injection & Platform Locking
1. Log back into Windows and open PowerShell as an **Administrator**.
2. Execute the exact same script (`SecureBoot_Compliance.ps1`) a second time.
3. The script will automatically detect that the platform key is unpopulated (Setup Mode). 
4. It formats all three databases in memory, feeds them into the NVRAM chip sequentially, updates your KEK, and writes your custom PK.
5. Once complete, the script runs an instant compliance verification match, appends the metrics to your deployment report, and outputs a **CRITICAL SUCCESS** confirmation prompt.
6. **Restart your machine.** The hardware will automatically seal into permanent, working **Custom User Mode**.

---

##  Deployment Artifacts
Following a complete execution sequence, the current user's Desktop space will contain the following items:
* `windows uefi ca 2023.crt` — The core Microsoft database compliance target update.
* `MicWinProPCA2011.crt` — The isolated local Windows 10/11 operating system boot trust key.
* `MicCorUEFCA2011.crt` — The isolated hardware Option ROM and modern Linux kernel loader key.
* `custom_pk.crt` — Your generated administrative Platform Root identity token.
* `SecureBoot_Deployment_Report.txt` — An explicit audit log detailing execution runtime metrics, hosts, timestamps, and compliance string validation states.

---

##  Architectural Isolation Disclaimer
The architectural updates implemented by this utility are primarily intended to resolve forward-compatibility blocks for modern operating system installers (such as deploying modern Linux distributions). 

Due to the physical platform age of Haswell 4th-generation hardware layouts (such as Intel AMT/ME 9.x frameworks), these older business workstations are naturally insulated from modern runtime firmware memory manipulation loops and bootkit vulnerabilities (e.g., BlackLotus execution paths) that target modern power sleep states and virtualization-based architectures. This script retrofits compatibility properties to legacy devices while maintaining stable physical root-of-trust constraints.

##  License
This tool is shared under the **MIT License**. Use it freely across your enterprise deployments or homelab architectures.

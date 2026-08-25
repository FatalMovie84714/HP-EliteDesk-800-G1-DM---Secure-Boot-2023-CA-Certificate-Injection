# HP EliteDesk 800 G1 DM - Secure Boot 2023 CA Certificate Injection

An automated, 100% offline deployment workflow to securely update the UEFI Signature Database (`db`) with the **Windows UEFI CA 2023** certificate on older 4th-Gen Intel (Haswell) HP motherboards without triggering `Secure Boot Violation` errors.

## The Problem
Older HP firmware (such as the EliteDesk 800 G1) treats native Windows updates or raw `.bin` flashes via standard User Mode commands as unauthorized or unreadable. Furthermore, executing a standard `Clear Keys` action in the BIOS wipes out the underlying Microsoft 2011 identities required to boot the Windows operating system. Overwriting the variable space with a standalone 2023 key bricks the boot cycle.

## The Solution
This workflow utilizes a two-phase deployment pipeline. It extracts the pristine native 2011 certificates from active firmware memory under factory keys, generates a localized custom administrative key link, drops the motherboard's guards via a controlled Setup Mode step, and uses a sequenced multi-variable PowerShell pipeline with explicit `-AppendWrite` flags to flash all keys into the firmware simultaneously.

## Deployment Blueprint

### Staging Dependencies
1. Ensure the offline machine is booted normally under **HP Factory Keys** and **Secure Boot Enabled**.
2. Clear the Desktop workspace of all old assets.
3. Download or transfer Microsoft's official `windows uefi ca 2023.crt` file directly to the **Desktop**.

### Phase 1: Environment Preparation
Run the first script inside an elevated Administrator PowerShell terminal:
```powershell
.\PHASE_1_PREPARE.ps1
```
* **Action:** This script natively extracts the running Microsoft 2011 boot certificates, appends the outer X.509 headers, generates a custom platform key file (`custom_pk.crt`), and initializes an automated audit log on the desktop.

### Manual Hardware Transition
1. Restart the machine and tap `F10` to enter **HP Computer Setup**.
2. Navigate to: `Security` -> `Secure Boot Configuration`.
3. Select **`Clear Keys`** (wipes factory keys and enters Setup Mode).
4. Change **`Custom or Hp Keys`** to **`Custom`**.
5. Ensure the main **`Secure Boot`** toggle is explicitly checked as **`Enabled`**.
6. Save structural changes, exit, and boot back into the Windows desktop environment.

### Phase 2: Firmware Flash Injection
Launch an elevated Administrator PowerShell terminal and execute the final stage:
```powershell
.\PHASE_2_FLASH.ps1
```
* **Action:** This script serializes the multi-variable byte payload streams, pushes all three database authorities to the active firmware register simultaneously via memory pipelines, establishes the custom Key Exchange Key (`KEK`), and writes the master Platform Key (`PK`) to seal the platform securely back into a custom locked User Mode.

## Compliance Logging
Both scripts dynamically track execution progress and output a comprehensive runtime audit transcript directly onto the workspace at:
`Desktop\SecureBoot_Deployment_Report.txt`

## License
Distributed under the MIT License. See `LICENSE` for more information.

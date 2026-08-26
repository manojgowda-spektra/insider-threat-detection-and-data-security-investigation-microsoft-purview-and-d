# Challenge 02: Onboard the VM to Defender for Endpoint and Generate Investigation Telemetry

### Estimated Duration: 1 Hour

## Scenario

Zava Manufacturing needs endpoint and collaboration telemetry for the suspected departing design engineer. In this challenge, you will use the lab admin account as that engineer, onboard the Azure lab VM to Microsoft Defender for Endpoint with a tenant-specific onboarding package, generate controlled file and email activity, trigger a safe Defender alert with the EICAR test file, and enable Microsoft Purview Insider Risk Management data sharing with Microsoft Defender XDR.

## Overview

You will download the Defender for Endpoint onboarding package from your own Microsoft Defender portal, run it on the Windows lab VM named **labvm-<inject key="DeploymentID" enableCopy="false"/>**, and verify the device starts reporting before generating evidence. You will then copy the staged Zava design files, send one file as an email attachment, run the prepared EICAR helper script, and configure Insider Risk Management data sharing to Defender XDR. The CloudLabs validation for this challenge uses automated checks for the Defender for Endpoint onboarding and EICAR evidence. The Purview data-sharing setting is a manual, non-graded checklist item because Microsoft does not expose a stable lab-safe validator surface for that tenant setting.

> [!Important]
> Do not use an onboarding package from another tenant or from a previous lab. Defender for Endpoint onboarding packages are tenant-specific. This lab intentionally does not pre-stage the package on the VM.

## Objectives

- Task 1: Sign in to the VM and confirm the learner identity
- Task 2: Download the tenant-specific Defender for Endpoint onboarding package
- Task 3: Run the onboarding package on the lab VM
- Task 4: Verify the lab VM is onboarded to Defender for Endpoint
- Task 5: Generate controlled file movement telemetry
- Task 6: Generate outbound email activity with a design-file attachment
- Task 7: Run the safe EICAR detection test
- Task 8: Enable Purview-to-Defender XDR alert sharing
- Task 9: Validate Defender onboarding and EICAR telemetry, and review the manual sharing checklist

## Task 1: Sign in to the VM and confirm the learner identity

In this task, you will connect to the lab VM, sign in to Microsoft 365 portals with the CloudLabs-provided account, and confirm the VM and account values you will use throughout the challenge.

1. Connect to the Windows lab VM provided by CloudLabs.

2. On the VM, open Microsoft Edge and go to the Microsoft Defender portal:

   https://security.microsoft.com

3. Sign in with the lab credentials:

   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
   - Tenant ID for reference: <inject key="TenantID"></inject>

4. If prompted to stay signed in, select **Yes**.

5. Open **Windows PowerShell** as Administrator.

6. Confirm the VM name. It should match **labvm-<inject key="DeploymentID" enableCopy="false"/>** or the CloudLabs-assigned computer name for this lab run.

   ```powershell
   hostname
   ```

7. Confirm that the local lab files are present.

   ```powershell
   Test-Path C:\LabFiles\ZavaDesignFiles
   Get-ChildItem C:\LabFiles\ZavaDesignFiles
   Test-Path C:\LabFiles\Invoke-ZavaEicarTest.ps1
   ```

8. If any of the expected paths return **False**, return to Challenge 1 and rerun the lab preparation helper before continuing.

## Task 2: Download the tenant-specific Defender for Endpoint onboarding package

In this task, you will download the Windows local-script onboarding package directly from your tenant's Defender portal.

1. In Microsoft Edge, open the Microsoft Defender portal:

   https://security.microsoft.com

2. In the left navigation, select **System** > **Settings**.

3. Select **Endpoints**.

4. Under **Device management**, select **Onboarding**. You can also open the onboarding page directly:

   https://security.microsoft.com/securitysettings/endpoints/onboarding

   > [!Tip]
   > If **Endpoints** or **Onboarding** is not visible, do not use a package from another source. Confirm you are signed in as <inject key="AzureAdUserEmail"></inject>, refresh the portal, open another Defender area such as **Incidents** or **Hunting**, and retry the navigation. If the section still does not appear, verify your tenant licensing and security administrator permissions.

5. On the **Onboarding** page, configure the onboarding options. Microsoft Learn's server onboarding guidance lists the Windows Server operating-system option for this deployed Windows Server 2019 VM as **Windows Server 2019, 2022, and 2025**.

   - Operating system: **Windows Server 2019, 2022, and 2025**
   - Connectivity type: **Standard** unless your instructor tells you to use streamlined connectivity
   - Deployment method: **Local script (for up to 10 devices)**

6. Select **Download onboarding package**.

7. Save the package to the current user's **Downloads** folder. The downloaded file is typically named **GatewayWindowsDefenderATPOnboardingPackage.zip**.

8. In File Explorer, right-click the ZIP file, select **Extract All**, and extract it to a folder that is easy to find, such as the Desktop. The extracted folder should contain **WindowsDefenderATPLocalOnboardingScript.cmd**.

> [!Important]
> The onboarding script is for manual onboarding of a small number of devices. It is appropriate for this lab VM, but production deployments normally use deployment tools such as Intune, Group Policy, Configuration Manager, or another supported onboarding method.

## Task 3: Run the onboarding package on the lab VM

In this task, you will run the local onboarding script from an elevated command prompt.

1. On the VM, select **Start**, type **cmd**, right-click **Command Prompt**, and select **Run as administrator**.

2. In the elevated Command Prompt, change to the folder where you extracted the onboarding script. If you extracted it to the Desktop, use the following command:

   ```cmd
   if exist "%OneDrive%\Desktop" (cd /d "%OneDrive%\Desktop") else if exist "%USERPROFILE%\Desktop" cd /d "%USERPROFILE%\Desktop"
   ```

3. If the script is inside an extracted subfolder, change into that subfolder. For example:

   ```cmd
   dir
   cd GatewayWindowsDefenderATPOnboardingPackage
   dir
   ```

4. Run the onboarding script.

   ```cmd
   WindowsDefenderATPLocalOnboardingScript.cmd
   ```

5. If Windows asks whether you want to allow the script to make changes, select **Yes**.

6. When the script displays **Press any key to continue...**, press any key to close the script.

7. Return to the elevated PowerShell window and review the Sense service status.

   ```powershell
   Get-Service Sense -ErrorAction SilentlyContinue
   ```

8. If the service is present but not running, retry by starting it and then checking status again.

   ```powershell
   Start-Service Sense
   Get-Service Sense
   ```

> [!Note]
> Local service status confirms that the endpoint sensor exists on the VM. The portal inventory is the authoritative confirmation that the device is onboarded and reporting to Defender for Endpoint.

## Task 4: Verify the lab VM is onboarded to Defender for Endpoint

In this task, you will confirm the VM appears in the Defender device inventory before generating evidence.

1. In the Microsoft Defender portal, go to **Assets** > **Devices**.

2. Select **All devices**.

3. Search for the device name **labvm-<inject key="DeploymentID" enableCopy="false"/>**. If the full name does not match, search for the hostname value you collected in Task 1.

4. Open the device page when it appears.

5. Confirm that the device has a recent **Last seen** value and is listed as onboarded or active.

6. If the device does not appear immediately, use retry-oriented troubleshooting instead of waiting a fixed amount of time:

   - Refresh the **Devices** page.
   - Confirm the onboarding script completed without errors.
   - Confirm the **Sense** service exists and is running on the VM.
   - Confirm the VM has internet access by opening https://security.microsoft.com.
   - Reopen **System** > **Settings** > **Endpoints** > **Onboarding** and confirm you downloaded the package from the same tenant where you are looking for the device.
   - Retry the device inventory search periodically until the VM appears or until you identify a specific error to resolve.

7. Do not proceed to the EICAR test until the device page is visible in Defender. File copy and email activity can be generated earlier, but the EICAR alert is only useful for this lab after the device is reporting.

## Task 5: Generate controlled file movement telemetry

In this task, you will copy staged design files to an exfiltration-like staging folder. This creates endpoint file activity that you will hunt in Challenge 3.

1. In the elevated PowerShell window, confirm the evidence staging path. The helper always uses **C:\ExfilStaging**, which is the path the Challenge 3 hunting query filters on.

   ```powershell
   $source = 'C:\LabFiles\ZavaDesignFiles'
   $destination = if (Test-Path 'D:\') { 'D:\ExfilStaging' } else { 'C:\ExfilStaging' }
   New-Item -ItemType Directory -Force -Path $destination | Out-Null
   $destination
   ```

2. Copy the design files into the staging folder.

   ```powershell
   Copy-Item -Path "$source\*" -Destination $destination -Force
   Get-ChildItem $destination
   ```

3. Create a small activity log that you can reference during the later hunting and case-report challenges.

   ```powershell
   $log = 'C:\LabFiles\zava_activity_notes.txt'
   "[$(Get-Date -Format o)] Copied Zava design files from $source to $destination on $(hostname)." | Add-Content $log
   Get-Content $log
   ```

4. Record the exact destination path shown by PowerShell. You will use it in Challenge 3 when querying **DeviceFileEvents**.

> [!Tip]
> The staging folder is always **C:\ExfilStaging**. It deliberately sits on the system drive: the D: volume on an Azure VM is an ephemeral temp disk, and the Challenge 3 hunting query filters on the C: path.

## Task 6: Generate outbound email activity with a design-file attachment

In this task, you will send an email from the lab admin account with one staged design file attached. This creates collaboration evidence for the investigation.

1. In Microsoft Edge, open Outlook on the web:

   https://outlook.office.com

2. Confirm you are signed in as <inject key="AzureAdUserEmail"></inject>.

3. Select **New mail**.

4. In **To**, enter a safe external test recipient that you control or that your instructor provides. If you do not have an external recipient available, send to another safe mailbox available in the tenant and record that limitation in your notes.

5. Use the following subject:

   **Zava prototype files for review**

6. Use the following message body:

   **Please review the attached prototype design file before my departure date.**

7. Attach one file from the staging folder you created in Task 5. Recommended files include:

   - **AeroFrame-Assembly-RevC.step**
   - **ZV-9000-Cooling-Manifold.dwg**
   - **Prototype-Test-Matrix.xlsx**

8. Send the message.

9. Add an entry to your activity notes.

   ```powershell
   "[$(Get-Date -Format o)] Sent outbound email with one staged Zava design-file attachment from Outlook on the web." | Add-Content C:\LabFiles\zava_activity_notes.txt
   ```

> [!Note]
> Email telemetry may not appear in Microsoft Defender XDR advanced hunting at the same speed as endpoint telemetry. In Challenge 3, you will use retry-oriented queries and record whether email rows are available in your tenant during the lab session.

## Task 7: Run the safe EICAR detection test

In this task, you will use the prepared lab helper to write the standard EICAR antivirus test string. Microsoft Defender Antivirus treats this harmless test string as malware and Defender for Endpoint can generate a real alert from it.

1. Confirm that the device appeared in the Defender device inventory in Task 4.

2. In the elevated PowerShell window, run the lab helper script.

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
   & C:\LabFiles\Invoke-ZavaEicarTest.ps1
   ```

3. If the script reports that the test file was blocked, quarantined, or removed, that is expected.

4. If the script cannot run because of PowerShell execution policy or file permissions, retry from an elevated PowerShell session using the same command above.

5. If no local detection appears, verify that Microsoft Defender Antivirus real-time protection is enabled and rerun the helper.

   ```powershell
   Get-MpComputerStatus | Select-Object AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled
   ```

6. In the Microsoft Defender portal, go to **Incidents & alerts** > **Alerts**.

7. Filter or search for alerts related to the VM. Useful search terms include the device name, **EICAR**, **test file**, or **antivirus**.

8. If the EICAR alert does not appear immediately, do not wait for a fixed number of minutes. Use this retry checklist:

   - Confirm the VM still appears under **Assets** > **Devices** with a recent **Last seen** value.
   - Refresh the alert queue and widen the time range.
   - Re-run the EICAR helper once after confirming real-time protection is enabled.
   - Open the device page and review its timeline or alerts tab.
   - Continue only after you have either found the alert or documented the exact onboarding or antivirus issue that prevents alert generation.

9. Add the alert observation to your activity notes.

   ```powershell
   "[$(Get-Date -Format o)] Ran EICAR safe detection test and checked Defender alert queue for the lab VM." | Add-Content C:\LabFiles\zava_activity_notes.txt
   ```

> [!Important]
> The EICAR test is the real Defender for Endpoint alert source used later in this lab. You are not expected to receive an Insider Risk Management alert or a correlated Insider Risk Management incident during this challenge.

## Task 8: Enable Purview-to-Defender XDR alert sharing

In this task, you will manually configure Microsoft Purview Insider Risk Management data sharing so Defender XDR can receive Insider Risk Management alert severity context when qualifying Insider Risk Management alerts exist. This Purview configuration is manual and non-graded in this lab.

1. In Microsoft Edge, open the Microsoft Purview portal:

   https://purview.microsoft.com

2. If prompted, sign in as <inject key="AzureAdUserEmail"></inject>.

3. In the left navigation, select **Solutions** > **Insider Risk Management**.

4. Select **Settings**.

5. Select **Data sharing**.

6. Under **Sharing data with other Microsoft security solutions**, turn on the data-sharing setting.

7. Select **Save** or **Apply** if the portal presents a save button.

8. Stay on the page and confirm the setting remains enabled after the page refreshes.

9. Add the manual checklist confirmation to your notes.

   ```powershell
   "[$(Get-Date -Format o)] Manually enabled Insider Risk Management data sharing with other Microsoft security solutions from Purview Data sharing settings. This checklist item is non-graded." | Add-Content C:\LabFiles\zava_activity_notes.txt
   ```

> [!Note]
> Microsoft Learn documents this as a single setting under **Insider Risk Management settings** > **Data sharing** > **Sharing data with other Microsoft security solutions**. When the setting is enabled, Insider Risk Management alert severity levels can be shared with Microsoft Defender XDR, DLP alerts, and Communication Compliance. It does not force the policy from Challenge 1 to score an Insider Risk Management alert during the lab session.

> [!Important]
> This Purview sharing step is manual and non-graded in CloudLabs. The automated validation for this challenge checks real Defender for Endpoint onboarding and EICAR evidence; it does not grade your manual Purview data-sharing checklist note.

## Task 9: Validate Defender onboarding and EICAR telemetry, and review the manual sharing checklist

In this task, you will validate that the graded Defender for Endpoint outcomes are complete before moving to Advanced Hunting. You will also review the Purview data-sharing checklist item, but that checklist item is not graded by CloudLabs.

1. Confirm the VM appears in the Defender device inventory:

   - Portal: **Microsoft Defender** > **Assets** > **Devices**
   - Device: **labvm-<inject key="DeploymentID" enableCopy="false"/>** or the hostname recorded in Task 1
   - Expected evidence: device page exists and has a recent **Last seen** value

2. Confirm staged files were copied:

   ```powershell
   Get-ChildItem C:\ExfilStaging -ErrorAction SilentlyContinue
   Get-ChildItem D:\ExfilStaging -ErrorAction SilentlyContinue
   ```

3. Confirm an outbound email was sent with a Zava design-file attachment:

   - Portal: **Outlook on the web** > **Sent Items**
   - Expected evidence: subject **Zava prototype files for review** and one staged design-file attachment

4. Confirm the EICAR alert was generated or is being actively troubleshot:

   - Portal: **Microsoft Defender** > **Incidents & alerts** > **Alerts**
   - Expected evidence: an alert associated with the lab VM, EICAR, test file, or antivirus detection

5. Manually confirm Purview sharing is enabled. This is a checklist item, not a graded validation condition:

   - Portal: **Microsoft Purview** > **Solutions** > **Insider Risk Management** > **Settings** > **Data sharing**
   - Expected evidence: the **Sharing data with other Microsoft security solutions** setting remains enabled

6. Review the notes file to ensure the timestamped activity record is complete.

   ```powershell
   Get-Content C:\LabFiles\zava_activity_notes.txt
   ```

7. Run the CloudLabs validation for this challenge. This automated validation checks only Defender for Endpoint onboarding and EICAR telemetry for the lab VM. It does not validate the manual Purview sharing checklist.

   <validation step="02-task-defender-onboarding-telemetry-alert-and-alert-sharing"/>

> [!Important]
> The validation must not require an Insider Risk Management alert, a correlated Defender XDR incident, or the Purview data-sharing setting. The graded evidence for this challenge is Defender for Endpoint onboarding plus EICAR-sourced Defender telemetry only. Purview data sharing remains a manual, non-graded configuration checklist item.

## Summary

You onboarded **labvm-<inject key="DeploymentID" enableCopy="false"/>** to Microsoft Defender for Endpoint by downloading and running your tenant-specific onboarding package. You generated controlled file movement, outbound email, and EICAR alert telemetry, and you manually enabled Microsoft Purview Insider Risk Management sharing to other Microsoft security solutions. In the next challenge, you will hunt for the evidence you created using Defender XDR Advanced Hunting.

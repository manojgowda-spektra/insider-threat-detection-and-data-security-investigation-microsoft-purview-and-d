# Challenge 01: Configure Insider Risk Management with HR connector data

### Estimated Duration: 1 Hour

## Scenario

Zava Manufacturing suspects that a departing design engineer may remove proprietary engineering files before leaving the company. In this challenge, you will prepare Microsoft Purview Insider Risk Management for the investigation by enabling audit collection, granting yourself Insider Risk Management permissions, importing HR departure data, and creating the departing-user data theft policy that will scope the risky user.

## Overview

You will use the existing lab admin account as the departing Zava design engineer. The lab VM contains a prepared HR CSV file at `C:\LabFiles\ZavaHRData.csv` and helper scripts under `C:\LabFiles`. You will verify that the CSV contains your real lab admin user principal name (UPN), confirm the HR dates are valid ISO 8601 date-time values, import the file through a Microsoft Purview HR connector, and create an active Insider Risk Management policy named `Zava Departing Employee Data Theft`.

> [!Important]
> The VM readiness checkpoint in Task 1 is the only automated validation in this challenge. The audit logging, Purview role-group membership, HR connector creation, HR CSV import, and Insider Risk Management policy configuration tasks are manual/facilitator-inspected portal tasks and are not graded by an automated Purview validator.

> [!Important]
> Do not wait for an Insider Risk Management alert in this challenge. Fresh tenants often need several hours or longer for audit ingestion, connector processing, risk scoring, and alert generation. The expected outcome for this challenge is a verified configuration: audit logging enabled, the HR connector import completed, and the policy active.

## Objectives

- Task 1: Sign in to the lab VM and run the local readiness helper
- Task 2: Enable unified audit logging
- Task 3: Add your account to the Insider Risk Management role group
- Task 4: Review and correct the Zava HR departure CSV
- Task 5: Create the HR connector upload app and Purview HR connector
- Task 6: Import the HR CSV and verify three records were saved
- Task 7: Create and verify the Insider Risk Management policy

## Task 1: Sign in to the lab VM and run the local readiness helper

In this task, you will sign in to the Windows lab VM, verify the local lab assets, and identify the lab admin UPN that will represent the departing Zava engineer.

1. Sign in to the CloudLabs VM named **labvm-<inject key="DeploymentID" enableCopy="false"/>** using the remote desktop connection information provided by your lab environment.

2. Open Microsoft Edge and sign in to the Azure portal at <https://portal.azure.com> with the following credentials:

   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>

3. Keep the signed-in account available in the browser. This same account is the risky departing engineer for this lab and is also the administrator you will use to configure Microsoft Purview.

4. Open **Windows PowerShell** as an administrator on the lab VM.

5. Run the local preparation helper:

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
   cd C:\LabFiles
   .\Prepare-ZavaLab.ps1
   ```

6. If the helper prompts for the lab admin UPN, enter the same username shown above: <inject key="AzureAdUserEmail"></inject>

7. Confirm that the helper reports the expected lab folders and scripts, including:

   - `C:\LabFiles\ZavaHRData.csv`
   - `C:\LabFiles\ZavaDesignFiles\`
   - `C:\LabFiles\Invoke-ZavaEicarTest.ps1`
   - `C:\LabFiles\get_insider_alerts.py`

> [!Note]
> This checkpoint verifies VM readiness and local lab assets only. It does not inspect or grade the Microsoft Purview audit, HR connector, import, role-group, or policy configuration that you complete manually in later tasks.

<validation step="01-task-vm-readiness-and-lab-assets"/>

## Task 2: Enable unified audit logging

In this task, you will verify and enable Microsoft 365 unified audit logging. Insider Risk Management uses Microsoft 365 audit data for policy insights and risk activity evaluation. This is a manual/facilitator-inspected task.

1. On the lab VM, open **Windows PowerShell** as an administrator.

2. Install or import the Exchange Online PowerShell module if needed:

   ```powershell
   if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
       Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
   }
   Import-Module ExchangeOnlineManagement
   ```

3. Connect to Exchange Online PowerShell:

   ```powershell
   Connect-ExchangeOnline
   ```

4. When prompted, sign in with the lab admin account: <inject key="AzureAdUserEmail"></inject>

5. Verify the current unified audit logging status:

   ```powershell
   Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled
   ```

6. If `UnifiedAuditLogIngestionEnabled` is `False`, enable auditing:

   ```powershell
   Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
   ```

7. Run the verification command again:

   ```powershell
   Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled
   ```

8. Confirm that the value is `True`.

> [!Note]
> Microsoft Learn notes that this status check must be run in Exchange Online PowerShell. The same property can show an incorrect `False` value in Security & Compliance PowerShell. Audit events might also take up to 60 minutes or longer to become searchable after auditing is enabled.

## Task 3: Add your account to the Insider Risk Management role group

In this task, you will explicitly grant your lab admin account Insider Risk Management permissions in Microsoft Purview. Global Administrator rights alone should not be treated as sufficient for the solution workflow. This is a manual/facilitator-inspected task.

> [!Important]
> Select **Settings** > **Roles and groups** (or **Roles and scopes** in some tenants), then open **Role groups**. To view and edit role groups, the signed-in administrator must be a **Global Administrator** or must have the Microsoft Purview **Role Management** role, which is assigned through the **Organization Management** role group. If you cannot see **Role groups**, verify that your lab admin account has one of those permissions before continuing.

1. In Microsoft Edge, open the Microsoft Purview portal at <https://purview.microsoft.com>.

2. If prompted, sign in with <inject key="AzureAdUserEmail"></inject>.

3. In the Microsoft Purview portal, select the **Settings** gear in the upper-right corner.

4. Select **Settings** > **Roles and groups** (or **Roles and scopes** in some tenants), then open **Role groups**.

5. Search for and select the **Insider Risk Management** role group.

6. Select **Edit**.

7. On the members page, select **Choose users** or **Add users**.

8. Search for your lab admin account, <inject key="AzureAdUserEmail"></inject>, select it, and then select **Select**.

9. Select **Next**, then select **Save**, and then select **Done**.

10. If Microsoft Purview does not immediately show Insider Risk Management features, sign out of the Purview portal, close the browser tab, wait a few minutes, and sign back in.

> [!Important]
> Role group changes can take up to 30 minutes to apply. Continue with the next tasks, but if an Insider Risk Management page is unavailable, refresh the portal session and retry after a short wait.

## Task 4: Review and correct the Zava HR departure CSV

In this task, you will inspect the HR CSV that identifies the departing engineer and two simulated colleagues. The first row must contain your real lab admin UPN so later telemetry can be tied to an actual licensed account in the tenant. The HR connector documentation requires employee resignation dates to be ISO 8601 date-time values, not informal dates.

1. In PowerShell, display the HR CSV rows:

   ```powershell
   Import-Csv C:\LabFiles\ZavaHRData.csv | Format-Table UserPrincipalName, ResignationDate, LastWorkingDate -AutoSize
   ```

2. Confirm that the CSV contains three rows.

3. Confirm that one row uses your lab admin UPN: <inject key="AzureAdUserEmail"></inject>

4. Confirm that the CSV has the following columns:

   - `UserPrincipalName`
   - `ResignationDate`
   - `LastWorkingDate`

5. Run this verification command to confirm that `ResignationDate` and `LastWorkingDate` are parseable ISO 8601 date-time values for every row. Values should include a date, time, and offset or UTC designator, for example `2026-01-15T00:00:00.0000000+00:00` or `2026-01-15T00:00:00Z`.

   ```powershell
   $rows = Import-Csv C:\LabFiles\ZavaHRData.csv
   $rows | ForEach-Object {
       [pscustomobject]@{
           UserPrincipalName = $_.UserPrincipalName
           ResignationDate   = $_.ResignationDate
           ResignationIsIso  = $_.ResignationDate -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
           LastWorkingDate   = $_.LastWorkingDate
           LastWorkingIsIso  = $_.LastWorkingDate -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
       }
   } | Format-Table -AutoSize
   ```

6. If any row shows `False` for either ISO check, normalize the CSV dates to ISO 8601 date-time values and display the updated rows:

   ```powershell
   $csvPath = 'C:\LabFiles\ZavaHRData.csv'
   $rows = Import-Csv $csvPath
   foreach ($row in $rows) {
       $row.ResignationDate = ([datetimeoffset]([datetime]$row.ResignationDate)).ToString('o')
       $row.LastWorkingDate = ([datetimeoffset]([datetime]$row.LastWorkingDate)).ToString('o')
   }
   $rows | Export-Csv $csvPath -NoTypeInformation
   Import-Csv $csvPath | Format-Table UserPrincipalName, ResignationDate, LastWorkingDate -AutoSize
   ```

7. If the first row does not contain your lab admin UPN, update it with the following commands. When prompted, type your lab admin UPN.

   ```powershell
   $csvPath = 'C:\LabFiles\ZavaHRData.csv'
   $rows = Import-Csv $csvPath
   $rows[0].UserPrincipalName = Read-Host 'Enter the lab admin UPN'
   $rows | Export-Csv $csvPath -NoTypeInformation
   Import-Csv $csvPath | Format-Table UserPrincipalName, ResignationDate, LastWorkingDate -AutoSize
   ```

> [!Tip]
> The HR connector supports mapping your CSV column names during connector setup. In this lab, keep the prepared column names unchanged so the mapping is straightforward.

## Task 5: Create the HR connector upload app and Purview HR connector

In this task, you will create the Microsoft Entra app credentials required by the Microsoft 365 HR connector, and then create the HR connector in Microsoft Purview. This is a manual/facilitator-inspected task.

### Create the Microsoft Entra app registration

1. Open the Microsoft Entra admin center at <https://entra.microsoft.com>.

2. Select **Identity** > **Applications** > **App registrations**.

3. Select **New registration**.

4. For **Name**, enter **Zava HR Connector Upload - <inject key="DeploymentID" enableCopy="false"/>**.

5. For **Supported account types**, select **Accounts in this organizational directory only**.

6. Select **Register**.

7. On the app **Overview** page, copy the following values into a temporary Notepad file:

   - Application (client) ID
   - Directory (tenant) ID

8. Select **Certificates & secrets**.

9. Select **New client secret**.

10. Enter the description `Zava HR connector lab secret`, choose an expiration suitable for the lab, and select **Add**.

11. Copy the client secret **Value** immediately into your temporary Notepad file. You will not be able to view the secret value again after you leave this page.

### Create the Microsoft Purview HR connector

1. Return to the Microsoft Purview portal at <https://purview.microsoft.com>.

2. Select the **Settings** gear.

3. Select **Data connectors**.

4. Select **My connectors**, and then select **Add connector**.

5. Select **HR**. If the portal shows **HR (preview)**, select that option.

6. On the connection setup page, enter the following values:

   - Connector name: `Zava HR Departing Employees`
   - Microsoft Entra application ID: the Application (client) ID you copied from the app registration

7. Select **Next**.

8. On the HR scenarios page, select **Employee resignation** or **Resignation** as the HR data scenario, and then select **Next**.

9. On the file mapping method page, choose **Upload a sample file** if that option is available.

10. Upload `C:\LabFiles\ZavaHRData.csv` as the sample file.

11. Map the CSV columns to the HR connector fields:

    | Connector field | CSV column |
    | --- | --- |
    | User principal name or user identifier | `UserPrincipalName` |
    | Resignation date | `ResignationDate` |
    | Last working date | `LastWorkingDate` |

12. Review the connector settings and select **Finish**.

13. On the confirmation page, copy the **Job ID** into your temporary Notepad file. You will use it to upload the HR CSV.

14. Select **Done**.

> [!Note]
> The HR connector import flow uses the app registration and connector job ID to authenticate the upload script and associate the uploaded CSV rows with this connector.

## Task 6: Import the HR CSV and verify three records were saved

In this task, you will run the Microsoft sample HR connector upload script from the lab VM and verify that the connector processed the three CSV rows. This is a manual/facilitator-inspected task.

1. In PowerShell, download the Microsoft HR connector sample script to `C:\LabFiles`:

   ```powershell
   Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/microsoft/m365-compliance-connector-sample-scripts/main/sample_script.ps1' -OutFile 'C:\LabFiles\HRConnector.ps1'
   ```

2. Change to the lab files directory:

   ```powershell
   cd C:\LabFiles
   ```

3. Store the Directory (tenant) ID, Application (client) ID, client secret value, and connector Job ID that you copied earlier as PowerShell variables:

   ```powershell
   $tenantId = Read-Host 'Paste the Directory tenant ID'
   $appId = Read-Host 'Paste the Application client ID'
   $appSecret = Read-Host 'Paste the client secret value'
   $jobId = Read-Host 'Paste the HR connector Job ID'
   ```

4. Run the upload script:

   ```powershell
   .\HRConnector.ps1 -tenantId $tenantId -appId $appId -appSecret $appSecret -jobId $jobId -filePath 'C:\LabFiles\ZavaHRData.csv'
   ```

5. Confirm that the script returns an upload success message.

6. In the Microsoft Purview portal, go to **Settings** > **Data connectors** > **My connectors**.

7. Select the `Zava HR Departing Employees` connector.

8. In the connector details pane, review **Progress** and **Last import**.

9. If a **Download log** link is available, download and open the log.

10. Verify that the log shows `RecordsSaved` as `3` or otherwise shows that three rows were imported successfully.

> [!Tip]
> If the import status is not immediately updated, wait a few minutes and refresh the connector details pane. If the script fails, re-check the client secret value, job ID, and whether the CSV file path is exactly `C:\LabFiles\ZavaHRData.csv`.

## Task 7: Create and verify the Insider Risk Management policy

In this task, you will create the departing-user data theft policy that uses the HR connector resignation data as the triggering event. This is a manual/facilitator-inspected task.

1. In the Microsoft Purview portal, select **Solutions** > **Insider Risk Management**.

2. If you are prompted to get started or enable the solution, follow the prompts to continue to the Insider Risk Management workspace.

3. Select **Policies**.

4. Select **Create policy**.

5. Choose the **Data theft by departing users** policy template.

   > [!Note]
   > Some portals may show a closely related quick policy label such as data theft from Microsoft 365 apps by users leaving your organization. For this lab, use the full policy workflow where you can name the policy and confirm the HR connector trigger settings.

6. For the policy name, enter `Zava Departing Employee Data Theft`.

7. For the description, enter `Detects potential data theft activity for Zava departing engineers imported through the HR connector.`

8. For users and groups in scope, select the option that includes all users, if prompted. The HR connector resignation trigger will bring the imported departing user into scope.

9. For triggering events, select the option that uses resignation or termination data from the Microsoft 365 HR connector.

10. If the wizard asks you to choose a connector, select `Zava HR Departing Employees`.

11. Configure the policy time window or data collection window for **90 days before and 90 days after** the resignation date, if the wizard exposes both values.

12. On the indicators or risk score boosters pages, select or confirm indicators related to the following activity types:

    - Files copied to USB or removable media
    - Files uploaded to personal cloud storage
    - Emails with attachments sent to external recipients

13. If the portal prompts you to enable required global policy indicators before selecting them in the policy, open the indicated settings page, enable the required indicators, save the settings, and then return to the policy wizard.

14. Review the policy configuration.

15. Select **Submit**, **Create**, or **Finish** to create the policy.

16. Return to **Insider Risk Management** > **Policies**.

17. Locate `Zava Departing Employee Data Theft`.

18. Verify that the policy status is **Active**.

19. Open the policy details page and confirm the policy health does not show a blocking HR connector error. If the policy reports that HR connector data is still processing, refresh after a few minutes and confirm that the connector import in Task 6 succeeded.

> [!Important]
> Stop after the policy is active. Do not wait for a Microsoft Purview Insider Risk Management alert. In this lab, later challenges generate Defender for Endpoint and hunting evidence during the session; Insider Risk Management scoring and alert creation can occur outside the lab time window.

## Summary

You enabled unified audit logging, granted your lab admin account Insider Risk Management permissions, reviewed and imported Zava HR resignation data with ISO 8601 date-time values, and created the active `Zava Departing Employee Data Theft` policy. The automated checkpoint in this challenge verified only VM readiness and local lab assets; the Purview configuration was completed as manual/facilitator-inspected work. The tenant is now prepared for the controlled activity and Defender XDR integration work in the next challenges, even though no Insider Risk Management alert is expected during the live lab session.

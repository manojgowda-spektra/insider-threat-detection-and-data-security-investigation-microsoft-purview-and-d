# Exercise 05: Python and Microsoft Graph alert export

### Estimated Duration: 45 Minutes

## Scenario

Zava Manufacturing's investigation team needs a portable evidence package that includes Defender for Endpoint alert data, user evidence, and exported DSI/eDiscovery evidence from the hunting and data security investigation work you completed earlier. In this exercise, you will use the prepared Python starter file on the lab VM to authenticate to Microsoft Graph, query the Microsoft Graph security `alerts_v2` endpoint, filter for recent Microsoft Defender for Endpoint evidence from this lab, and export both a JSON evidence file and a plain-text case report.

## Overview

You will first confirm whether the deployment was able to create `C:\LabFiles\config.json` for app-only Microsoft Graph authentication. The deployment attempts a best-effort Graph app bootstrap by using the lab context, but that bootstrap can fail in modern tenants because of MFA, Conditional Access, tenant security defaults, or directory permission restrictions. This is expected and does not mean the lab is broken. If the automated setup is missing or authentication fails, you will manually create an app registration in Microsoft Entra ID, add the Microsoft Graph **SecurityAlert.Read.All** application permission, grant admin consent, create a client secret, and write the real tenant ID, client ID, and client secret to VM-local `config.json`. You will then inspect the existing generated `C:\LabFiles\get_insider_alerts.py` script, run the built-in smoke test, query `/security/alerts_v2`, confirm pagination handling, and export the final case files.

## Objectives

- Task 1: Confirm sign-in context and inspect `C:\LabFiles\config.json`
- Task 2: Run an authentication smoke test
- Task 3: Manually create the Microsoft Graph app registration if needed
- Task 4: Inspect and checkpoint the Python Microsoft Graph export script
- Task 5: Run the export and review the case files
- Task 6: Validate the Graph export artifacts

## Task 1: Confirm sign-in context and inspect `C:\LabFiles\config.json`

In this task, you will confirm that you are using the lab administrator account and check whether the best-effort deployment created the Graph app configuration file.

1. Connect to the lab VM named **labvm-<inject key="DeploymentID" enableCopy="false"/>**.

2. Open Microsoft Edge and sign in to the Microsoft Entra admin center at <https://entra.microsoft.com> with the lab administrator account.

   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>

3. Keep the tenant ID available for later configuration.

   - Tenant ID: <inject key="TenantID"></inject>

4. Open **Windows PowerShell** as an administrator.

5. Confirm that the lab files and starter script exist.

   ```powershell
   Test-Path C:\LabFiles
   Test-Path C:\LabFiles\get_insider_alerts.py
   Test-Path C:\LabFiles\config.json
   Test-Path C:\LabFiles\Exercise3-HuntingNotes.txt
   Test-Path C:\LabFiles\dsi-notes.txt
   Test-Path C:\LabFiles\DSIExports
   ```

6. If `C:\LabFiles\config.json` exists, inspect its property names without displaying the full secret value.

   ```powershell
   $configPath = 'C:\LabFiles\config.json'
   if (Test-Path $configPath) {
       $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
       [pscustomobject]@{
           tenant_id_present     = -not [string]::IsNullOrWhiteSpace($cfg.tenant_id)
           client_id_present     = -not [string]::IsNullOrWhiteSpace($cfg.client_id)
           client_secret_present = -not [string]::IsNullOrWhiteSpace($cfg.client_secret)
           bootstrap_created     = [bool]$cfg.createdByBootstrap
       }
   }
   else {
       Write-Host 'config.json is missing. You will create it in the manual fallback task.'
   }
   ```

7. Confirm the Python packages used by this exercise are installed.

   ```powershell
   python -m pip show msal requests
   ```

   If either package is missing, install it now.

   ```powershell
   python -m pip install msal requests
   ```

> [!Important]
> `C:\LabFiles\config.json` stores an application secret for a disposable lab app registration. Do not paste its value into screenshots, chat, or public notes.

> [!Note]
> If `createdByBootstrap` is true but token acquisition fails in the next task, use the manual app registration fallback. The deployment's Graph bootstrap is intentionally best-effort only and is commonly blocked by modern tenant security controls.

## Task 2: Run an authentication smoke test

In this task, you will test whether the existing configuration can acquire an app-only Microsoft Graph token. The generated `C:\LabFiles\get_insider_alerts.py` script uses the `--smoke-test` switch for this check.

1. In the same administrator PowerShell window, change to the lab folder.

   ```powershell
   Set-Location C:\LabFiles
   ```

2. Run the authentication smoke test.

   ```powershell
   python .\get_insider_alerts.py --smoke-test
   ```

3. Interpret the result:

   - If the smoke test prints a successful token acquisition message, continue to Task 4.
   - If the script reports that `config.json` is missing, the tenant ID, client ID, or secret is blank, or the token request fails with an authorization or consent error, complete Task 3.
   - If the `--smoke-test` switch is not recognized, reopen `C:\LabFiles\get_insider_alerts.py` and confirm you are using the generated script created by the lab bootstrap.

> [!Note]
> This exercise uses the OAuth 2.0 client credentials flow. The app authenticates as itself with an application permission; it does not sign in as the lab user and it does not use the user's password in Python. For Microsoft Graph app-only tokens, the requested scope is `https://graph.microsoft.com/.default`, which asks Microsoft Entra ID to issue the app permissions that an administrator granted to the app registration.

## Task 3: Manually create the Microsoft Graph app registration if needed

In this task, you will create the app-only Microsoft Graph configuration when the automated deployment did not create it or when authentication failed. This fallback is expected in many tenants.

1. In Microsoft Edge, open the Microsoft Entra admin center at <https://entra.microsoft.com>.

2. Browse to **Microsoft Entra ID** > **Identity** > **Applications** > **App registrations**.

3. Select **New registration**.

4. Configure the registration with the following values:

   | Setting | Value |
   |---|---|
   | Name | `Zava Graph Alert Export` |
   | Supported account types | **Accounts in this organizational directory only** |
   | Redirect URI | Leave blank |

5. Select **Register**.

6. On the app registration **Overview** page, copy the following values to a temporary Notepad window:

   - **Application (client) ID**
   - **Directory (tenant) ID**

7. In the left menu for the app registration, select **API permissions**.

8. If the default delegated **User.Read** permission is present, remove it.

9. Select **Add a permission** > **Microsoft Graph** > **Application permissions**.

10. In the permission search box, search for `SecurityAlert.Read.All`.

11. Select **SecurityAlert.Read.All**, and then select **Add permissions**.

12. On the **API permissions** page, select **Grant admin consent for** your tenant, and then select **Yes**.

13. Confirm that the permission row shows admin consent granted for **SecurityAlert.Read.All**.

14. In the left menu, select **Certificates & secrets**.

15. Select **Client secrets** > **New client secret**.

16. Enter the following description, select the shortest suitable expiration for the lab, and then select **Add**.

   ```text
   Zava lab Graph alert export secret
   ```

17. Immediately copy the client secret **Value** to Notepad. You will not be able to retrieve this value again after leaving the page.

18. Return to the administrator PowerShell window and create or replace `C:\LabFiles\config.json` with the real values you copied from the portal.

   ```powershell
   $tenantId = Read-Host 'Directory (tenant) ID'
   $clientId = Read-Host 'Application (client) ID'
   $secret = Read-Host 'Client secret value'

   [ordered]@{
       tenant_id     = $tenantId.Trim()
       client_id     = $clientId.Trim()
       client_secret = $secret
   } | ConvertTo-Json | Set-Content C:\LabFiles\config.json -Encoding UTF8
   ```

19. Confirm the local configuration has the expected keys and no empty values. The lab tenant ID is <inject key="TenantID"></inject>; compare it to the `tenant_id` shown by the command output, and do not print the secret value.

   ```powershell
   $cfg = Get-Content C:\LabFiles\config.json -Raw | ConvertFrom-Json
   [pscustomobject]@{
       tenant_id = $cfg.tenant_id
       client_id_present = -not [string]::IsNullOrWhiteSpace($cfg.client_id)
       client_secret_present = -not [string]::IsNullOrWhiteSpace($cfg.client_secret)
   }
   ```

20. Run the authentication smoke test again after you inspect the script in Task 4.

> [!Tip]
> If token acquisition still fails after granting admin consent, wait one or two minutes and retry. Fresh tenants can take a short time to reflect new app permissions.

## Task 4: Inspect and checkpoint the Python Microsoft Graph export script

In this task, you will inspect the prepared `C:\LabFiles\get_insider_alerts.py` script instead of pasting a large replacement script. The Custom Script Extension created a near-complete MSAL/requests script that reads `C:\LabFiles\config.json`, uses the client credentials flow, calls `/security/alerts_v2`, follows `@odata.nextLink`, filters recent Microsoft Defender for Endpoint lab alerts, imports earlier hunting notes, requires exported DSI/eDiscovery metadata from `C:\LabFiles\DSIExports`, and writes the investigation exports.

1. Open the starter script in Visual Studio Code.

   ```powershell
   code C:\LabFiles\get_insider_alerts.py
   ```

2. Use Visual Studio Code search to find `TODO`. Review only the small TODO/configuration areas. Do not replace the whole file unless your facilitator specifically instructs you to do so.

   ```powershell
   Select-String -Path C:\LabFiles\get_insider_alerts.py -Pattern 'TODO','alerts_v2','SecurityAlert.Read.All','@odata.nextLink','createdDateTime','microsoftDefenderForEndpoint','.default'
   ```

3. Confirm the script reads the real VM-local config keys: `tenant_id`, `client_id`, and `client_secret`. If your starter accepts alternate casing, keep that compatibility, but the final `C:\LabFiles\config.json` must contain the real values you verified in Task 1 or created in Task 3.

   ```powershell
   Select-String -Path C:\LabFiles\get_insider_alerts.py -Pattern 'tenant_id','client_id','client_secret','ConfidentialClientApplication','acquire_token_for_client'
   ```

4. Confirm the Graph request logic uses the current alerts endpoint and a supported server-side filter. The script should call Microsoft Graph v1.0 `/security/alerts_v2`, use `$filter` with `createdDateTime ge <UTC cutoff>`, and use `$top` to control page size.

   ```powershell
   Select-String -Path C:\LabFiles\get_insider_alerts.py -Pattern '/security/alerts_v2','\$filter','createdDateTime ge','\$top'
   ```

5. Confirm the pagination logic follows the full `@odata.nextLink` URL until no next page is returned.

   ```powershell
   Select-String -Path C:\LabFiles\get_insider_alerts.py -Pattern '@odata.nextLink','while url','requests.get'
   ```

6. Confirm the client-side lab filtering logic keeps Microsoft Defender for Endpoint alerts and then narrows the results by local VM name or EICAR/test-file indicators built into the script.

   ```powershell
   hostname
   Select-String -Path C:\LabFiles\get_insider_alerts.py -Pattern 'microsoftDefenderForEndpoint','vm-name','EICAR','test-file','is_lab_scoped_mde_alert'
   ```

7. Confirm the output and evidence-import paths are present.

   ```powershell
   Select-String -Path C:\LabFiles\get_insider_alerts.py -Pattern 'insider_risk_case.json','insider_risk_case_report.txt','Exercise3-HuntingNotes.txt','DSIExports','dsi_case_evidence.json','labScopedMdeAlerts','labScopedMdeAlertSummaries','dsiCaseEvidenceParsed','dsiExportInventory'
   ```

8. Save the file if you made any small TODO adjustments.

9. Run the authentication smoke test again.

   ```powershell
   python C:\LabFiles\get_insider_alerts.py --smoke-test
   ```

10. Confirm the script prints a successful token acquisition message. The exact wording can vary by starter version, but it must indicate that MSAL acquired an app-only Microsoft Graph token.

> [!Important]
> Microsoft Learn documents that Microsoft Graph `alerts_v2` supports `$filter` on `assignedTo`, `classification`, `determination`, `createdDateTime`, `lastUpdateDateTime`, `severity`, `serviceSource`, and `status`, supports `$top`, and uses `@odata.nextLink` for pagination. This lab uses the supported `createdDateTime ge` server-side filter with a UTC cutoff first, follows `@odata.nextLink` until all returned pages are read, then applies client-side filters for Microsoft Defender for Endpoint plus the lab VM hostname or built-in EICAR/test-file indicators before writing `C:\LabFiles\insider_risk_case.json`. This prevents the export from accidentally including stale or unrelated tenant alerts.

> [!Note]
> Microsoft Graph alerts v2 commonly identifies Microsoft Defender for Endpoint alerts through `serviceSource` equal to `microsoftDefenderForEndpoint`. The script also checks other alert text and product fields client-side so the export remains tolerant of tenant-specific alert shapes.

## Task 5: Run the export and review the case files

In this task, you will query recent alerts, export evidence, and review the generated case files. The script imports your earlier hunting notes and the real DSI/eDiscovery export metadata from Exercise 4; it does not ask you to type a new ungraded narrative summary in this exercise.

1. Confirm the earlier notes and required DSI/eDiscovery export index exist. If the DSI export index is missing, return to Exercise 4 and complete the `C:\LabFiles\DSIExports` export collection before running the Graph export.

   ```powershell
   Test-Path C:\LabFiles\Exercise3-HuntingNotes.txt
   Test-Path C:\LabFiles\dsi-notes.txt
   Test-Path C:\LabFiles\DSIExports\dsi_case_evidence.json
   Get-ChildItem C:\LabFiles\DSIExports -Recurse
   ```

2. Inspect the DSI/eDiscovery metadata you created in Exercise 4. The file `C:\LabFiles\DSIExports\dsi_case_evidence.json` is a normalized index of the real DSI or eDiscovery portal export; it is not the only evidence file. It should identify the case name, investigation type, custodian or risky user, search/query, result count, and evidence finding from the Purview DSI or eDiscovery workflow.

   ```powershell
   Get-Content C:\LabFiles\DSIExports\dsi_case_evidence.json -Raw | ConvertFrom-Json | Format-List
   ```

3. Run the export script. By default, it queries Microsoft Graph for alerts created in the last 72 hours, follows any `@odata.nextLink` pages returned by Graph, then keeps only recent Microsoft Defender for Endpoint alerts that contain the local VM hostname or built-in EICAR/test-file indicators.

   ```powershell
   python C:\LabFiles\get_insider_alerts.py
   ```

4. If the script exports zero alerts, first confirm the local hostname that the script is using and then rerun with the explicit VM name shown by `hostname` or the expected lab VM name.

   ```powershell
   hostname
   python C:\LabFiles\get_insider_alerts.py --vm-name $env:COMPUTERNAME
   ```

5. If all runs still return zero alerts, wait five to ten minutes for Defender alert ingestion and rerun the script. Confirm that Exercise 2 successfully onboarded the VM and triggered the EICAR test alert in the Microsoft Defender portal. Do not widen the lookback window unless you are intentionally troubleshooting; the default 72-hour cutoff is designed to avoid stale or unrelated alerts.

6. Confirm that the JSON export exists.

   ```powershell
   Test-Path C:\LabFiles\insider_risk_case.json
   Get-Content C:\LabFiles\insider_risk_case.json -Raw | ConvertFrom-Json | Select-Object generatedUtc, cutoffUtc, labVmName, recentAlertCount, labScopedMdeAlertCount
   ```

7. Confirm that the JSON export includes the server-side Graph cutoff metadata, the lab VM name used for filtering, imported hunting notes, normalized DSI/eDiscovery index, and recursive DSI/eDiscovery file inventory. The JSON shape must include top-level `labScopedMdeAlerts` and `labScopedMdeAlertSummaries` arrays plus `exercise3HuntingNotes`, `dsiCaseEvidenceParsed`, and `dsiExportInventory` objects.

   ```powershell
   $case = Get-Content C:\LabFiles\insider_risk_case.json -Raw | ConvertFrom-Json
   $case | Select-Object generatedUtc, cutoffUtc, labVmName, recentAlertCount, labScopedMdeAlertCount
   $case.labScopedMdeAlertSummaries | Format-Table id, title, severity, serviceSource, detectionSource, createdDateTime -AutoSize
   $case.exercise3HuntingNotes | Select-Object path, exists, length, truncated
   $case.dsiCaseEvidenceParsed | Format-List
   $case.dsiExportInventory.files | Format-Table relativePath, sizeBytes, modifiedUtc -AutoSize
   ```

8. Confirm that the text report exists and contains alert identifiers, hunting findings, DSI/eDiscovery export metadata, the recursive export file inventory, and the Graph cutoff scope.

   ```powershell
   Test-Path C:\LabFiles\insider_risk_case_report.txt
   Select-String -Path C:\LabFiles\insider_risk_case_report.txt -Pattern 'Server-side Graph cutoff','Lab VM filter','Exercise 3 hunting notes','DSI/eDiscovery normalized case evidence','DSI/eDiscovery export inventory','Recent lab-scoped MDE alerts matched','Alert ID'
   ```

9. Open the JSON export in Visual Studio Code.

   ```powershell
   code C:\LabFiles\insider_risk_case.json
   ```

10. Review at least one exported alert in the `labScopedMdeAlerts` array and identify these fields:

   - `id`
   - `providerAlertId`
   - `incidentId`
   - `severity`
   - `serviceSource`
   - `detectionSource`
   - `evidence`
   - `alertWebUrl`

11. In the top-level metadata, confirm `cutoffUtc` contains the UTC timestamp used by the script's `createdDateTime ge` server-side filter and `labVmName` contains the VM name used for client-side filtering.

12. In the `labScopedMdeAlertSummaries` section, review the summarized fields for each matched Microsoft Defender for Endpoint alert.

13. In the `dsiCaseEvidenceParsed` section, review the normalized DSI/eDiscovery evidence index exported in Exercise 4 and confirm that it ties back to **Insider Threat Case - Design Engineer**. Then review `dsiExportInventory.files` to confirm the real portal export files and any subfolders under `C:\LabFiles\DSIExports` were inventoried recursively.

14. Open the text report.

   ```powershell
   notepad C:\LabFiles\insider_risk_case_report.txt
   ```

15. Confirm that the report includes the content of `C:\LabFiles\Exercise3-HuntingNotes.txt`, parsed metadata from the normalized index at `C:\LabFiles\DSIExports\dsi_case_evidence.json`, a recursive file inventory for `C:\LabFiles\DSIExports`, and the server-side Graph cutoff used for the export.

> [!Tip]
> The JSON file is the machine-readable evidence package. The text report is the analyst-facing case narrative that combines the Graph export with your hunting and Data Security Investigation or eDiscovery export evidence.

> [!Important]
> `C:\LabFiles\DSIExports\dsi_case_evidence.json` is a normalized index that summarizes what you exported from the Purview DSI or eDiscovery portal. It is not intended to replace the actual portal export files. Keep the full contents of `C:\LabFiles\DSIExports`, including any nested folders, with the case package.

## Task 6: Validate the Graph export artifacts

In this task, you will run the validation for the final export output.

1. Confirm that the expected files are present:

   - `C:\LabFiles\config.json`
   - `C:\LabFiles\get_insider_alerts.py`
   - `C:\LabFiles\DSIExports\dsi_case_evidence.json`
   - `C:\LabFiles\insider_risk_case.json`
   - `C:\LabFiles\insider_risk_case_report.txt`

2. Confirm that the report includes a case summary, imported hunting findings, imported DSI/eDiscovery export metadata, Graph cutoff metadata, and alert identifiers.

3. Run the validation check for this exercise.

<validation step="05-task-graph-export-artifacts-and-alert-content"/>

> [!Note]
> If your facilitator asks you to retain the tenant after validation, clean up the disposable Graph credentials for this lab: in the Microsoft Entra admin center, delete the app registration named `Zava Graph Alert Export`, and remove the local secret file with `Remove-Item C:\LabFiles\config.json -Force`. Do this only after validation is complete, because the validator checks the export configuration and output files.

## Summary

You completed the final evidence export for the Zava insider threat investigation. You verified or manually created an app-only Microsoft Graph configuration, granted the **SecurityAlert.Read.All** application permission with admin consent, used MSAL Python to acquire a token, queried Microsoft Graph `/security/alerts_v2` with a supported `createdDateTime ge <UTC cutoff>` server-side filter, followed `@odata.nextLink` until all returned pages were read, applied client-side Microsoft Defender for Endpoint and lab-indicator filtering to avoid stale or unrelated alerts, imported earlier hunting and DSI/eDiscovery exported evidence, inventoried the real DSI/eDiscovery portal export recursively, and exported both `C:\LabFiles\insider_risk_case.json` and `C:\LabFiles\insider_risk_case_report.txt` for the case file.

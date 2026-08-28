# Challenge 04: Microsoft Purview Data Security Investigation

### Estimated Duration: 1 Hour

## Scenario

Zava Manufacturing has enough endpoint and email evidence to justify a data-focused investigation. In this challenge, you will use Microsoft Purview Data Security Investigations when your tenant and instructor explicitly approve the required metering/capacity setup, or Microsoft Purview eDiscovery as the low-export fallback, to scope the suspected departing design engineer and prove whether Zava design-file evidence exists in Microsoft 365 content.

## Overview

You will create an investigation or case named **Insider Threat Case - Design Engineer**, add the lab admin account as the risky user custodian/data source, and run searches across the Microsoft 365 workloads available in your sandbox tenant. The default lab path is **no/low-export**: inspect search results and export only the smallest report or metadata package needed to prove the Zava evidence. Do not enable DSI metering, configure AI capacity, or export native source items unless your instructor or tenant owner has approved that usage. When DSI usage is not approved or DSI does not expose a clear downloadable report/list, use the eDiscovery fallback and choose the smallest report/export option that proves the Zava evidence. You will save the resulting portal evidence under `C:\LabFiles\DSIExports` and normalize parseable evidence metadata for use in the final case report.

> [!Important]
> Data Security Investigations can require pay-as-you-go storage metering and compute capacity before it can be used. Microsoft Learn describes DSI billing as a model based on stored investigation data and computing capacity used for analysis. Therefore, the default path for this lab is to avoid adding data to DSI scope or running DSI analysis unless your instructor explicitly approves DSI metering/capacity usage. If DSI is not approved, do not configure DSI billing and do not create a DSI investigation for this lab; use Microsoft Purview eDiscovery instead.

> [!Note]
> Microsoft Learn documents that eDiscovery search exports support **Export items report only**, which creates the summary and item report without exporting source items. Use that report-only option first when it contains enough metadata to prove the Zava evidence. Use a larger export, such as **Export items with items report**, only if the report-only export does not contain the needed Zava filename, sender, recipient, custodian, or location metadata and your instructor approves exporting source items.

### Success criteria for Challenge 4

Challenge 4 is successful only when `C:\LabFiles\DSIExports` contains evidence exported from the Microsoft Purview portal, not a locally invented JSON file. The export can be a DSI downloadable report/list when your tenant exposes one and your instructor approves DSI use, or a Microsoft Purview eDiscovery case/search export. Treat the eDiscovery export as the reliable validation artifact when DSI does not expose a clear downloadable report/list in your tenant. The evidence collection must include:

- A real DSI downloadable report/list, eDiscovery portal export file, report, package, or downloaded process/search metadata saved under `C:\LabFiles\DSIExports`.
- A normalized metadata file named `dsi_case_evidence.json` generated from that real portal export.
- Non-empty metadata identifying the case or search, the custodian or searched UPN, Zava file or email evidence, and the result count or exported item count.
- At least one exported item, report row, or result metadata entry that ties back to the Zava scenario.

## Objectives

- Task 1: Sign in and confirm the investigation context and DSI availability
- Task 2: Create the Data Security Investigation or eDiscovery case
- Task 3: Add the risky user as custodian and data source
- Task 4: Run broad searches across available Microsoft 365 workloads
- Task 5: Refine searches with filename, keyword, file type, date, size, and external indicators
- Task 6: Explore sensitivity label filters safely in a fresh tenant
- Task 7: Export the smallest real DSI or eDiscovery evidence artifact to the lab VM
- Task 8: Normalize the portal export for validation and the final report
- Task 9: Record findings for the final case report

## Task 1: Sign in and confirm the investigation context and DSI availability

> [!Note]
> In a new tenant the Microsoft Purview portal shows a **Welcome to the new Microsoft Purview portal!** dialog over the page, and it can reappear later in the session. Close it with the **X** in its top-right corner. Selecting **Get started** does not dismiss it, so if your clicks stop registering, check whether this dialog has come back.

In this task, you will sign in to Microsoft Purview, identify the account and artifacts that define the investigation, and decide whether to use Data Security Investigations or the low-export eDiscovery fallback.

1. In the lab VM, open Microsoft Edge.

2. Go to `https://purview.microsoft.com`.

3. Sign in with the lab admin account:

   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>

4. If prompted, complete any first-run or stay-signed-in prompts.

5. Confirm the risky user identity for this investigation is the same lab admin account:

   - Risky user UPN: <inject key="AzureAdUserEmail"></inject>
   - Lab VM evidence source: **labvm-<inject key="DeploymentID" enableCopy="false"/>**
   - Investigation/case name to create: **Insider Threat Case - Design Engineer**

6. In the Microsoft Purview portal, select **Solutions** and look for **Data Security Investigations**.

7. If **Data Security Investigations** opens normally and your instructor has approved any required DSI metering/capacity usage, continue with the DSI steps in Task 2.

8. If the portal asks you to configure billing, usage, storage meter, or capacity, stop and use the eDiscovery fallback unless your instructor explicitly approves that configuration for this lab tenant. Do not enable DSI pay-as-you-go or compute capacity just to complete this challenge.

9. Use the fallback path for this challenge when DSI is unavailable, DSI metering/capacity is not approved, DSI setup cannot be completed in your sandbox, or DSI does not expose a clear downloadable report/list:

   - Select **Solutions** > **eDiscovery**.
   - Create or use an eDiscovery case with the same case name, **Insider Threat Case - Design Engineer**.
   - Follow the same search, export, and documentation tasks below using the eDiscovery search experience.
   - Treat the fallback as a valid successful path if the final evidence under `C:\LabFiles\DSIExports` is a real Microsoft Purview portal export/report and the normalized metadata file is generated from that export.

10. Open `C:\LabFiles\ZavaDesignFiles` on the lab VM and review the file names you staged earlier in the lab. Use these names as search terms during this challenge:

    - `AeroFrame-Assembly-RevC.step`
    - `ZV-9000-Cooling-Manifold.dwg`
    - `Prototype-Test-Matrix.xlsx`
    - `Supplier-Costed-BOM-Q4.xlsx`
    - `Manufacturing-Tolerances.pdf`

11. Open your Challenge 3 hunting notes at `C:\LabFiles\Challenge3-HuntingNotes.txt`. You will use the same approximate date/time window, risky user, file names, and external recipient indicators in this challenge.

> [!Important]
> Data Security Investigations and eDiscovery search results depend on Microsoft 365 service indexing and on the data you created earlier in the lab. Endpoint-only file copies from Challenge 2 are not automatically content-searchable unless those files were also placed in a Microsoft 365 workload, attached to email, or captured by a configured Purview evidence feature. If a search returns no Zava results, broaden and rerun it before exporting.

## Task 2: Create the Data Security Investigation or eDiscovery case

In this task, you will create a new Microsoft Purview Data Security Investigation only when DSI use is approved. Otherwise, you will create an eDiscovery case with the same case name.

1. If DSI usage is approved, in the Microsoft Purview portal, select **Solutions** if the left navigation does not already show the solution list.

2. Select **Data Security Investigations**.

3. Select **Investigations**.

4. Select **Create investigation**.

5. In the **Create an investigation** dialog, enter the following values:

   - **Title** or **Name**: `Insider Threat Case - Design Engineer`
   - **Description**: `Investigation of possible Zava design file exfiltration by the departing design engineer represented by the lab admin account.`
   - **Additional context** if the field is present: `Focus on Zava design files, outbound email, externally shared content, engineering file extensions, and activity by the lab admin account.`

6. Select **Switch to full draft mode** if the option is displayed.

7. Select **Create investigation**, **Create**, or the equivalent button shown by your tenant.

8. Wait for the investigation workspace to open.

9. If DSI usage is not approved or you are using the eDiscovery fallback, create an eDiscovery case instead:

   - Select **Solutions** > **eDiscovery** > **Cases**.
   - Select **Create case**.
   - Name the case `Insider Threat Case - Design Engineer`.
   - Add a description that identifies this as the low-export fallback for the Zava insider threat lab.
   - Record in `C:\LabFiles\dsi-notes.txt` that the case was created as an eDiscovery fallback instead of a DSI case.

> [!Note]
> Microsoft Learn describes manual DSI investigations using full draft mode for scenarios where the investigation is not created from another Microsoft security workflow. In this lab, full draft mode is used only when DSI usage has been approved.

## Task 3: Add the risky user as custodian and data source

In this task, you will scope the investigation to the lab admin account so searches focus on the suspected departing engineer.

> [!Note]
> The eDiscovery experience has no case-level **Custodians** or **Data sources** area. Scope is set inside each search, so you create the search first and then add the risky user to it. If your tenant still shows a case-level custodian page, use that instead and skip to step 6.

1. In **Insider Threat Case - Design Engineer**, select **Searches**.

2. Select **Create a search**.

3. Enter a name such as `Zava design file evidence` and a description that identifies the departing engineer, then select **Create**. The creation panel asks only for a name and a description - sources and conditions are added afterwards, inside the search.

4. Open the search you just created.

5. Select **Add sources**.

6. Search for the risky user UPN: <inject key="AzureAdUserEmail"></inject>, select the account, and save. Depending on tenant data and licensing the available sources may include:

   - Exchange Online mailbox
   - OneDrive account
   - Teams chat data stored for the user
   - SharePoint locations associated with files the user uploaded or shared

7. Do not use **Add tenant-wide sources** as your only scope. Keep the risky user selected so the result set stays defensible and tied to the suspected custodian.

9. Checkpoint: before continuing, verify that the case or search scope visibly includes <inject key="AzureAdUserEmail"></inject> and that your notes identify whether you are using **Data Security Investigations** or the **eDiscovery fallback**.

> [!Tip]
> In Data Security Investigations, Microsoft documentation describes selecting users, groups, locations, or tenant-wide sources as investigation data sources. Some Purview experiences use the legal term **custodian** for the person of interest. In this lab, the custodian and risky user are the same account: <inject key="AzureAdUserEmail"></inject>.

## Task 4: Run broad searches across available Microsoft 365 workloads

In this task, you will run a broad search first, then narrow the query in later tasks.

1. In the investigation or case, select the search experience for your path:

   - DSI approved path: select **Summary**, then on the **Search** tab select **Query builder**.
   - eDiscovery fallback path: select the **Searches** tab, then create or open a search.

2. Confirm the data source is scoped to the risky user you added in Task 3.

3. Create a broad query with the following filter pattern:

   | Filter | Operator | Value |
   | --- | --- | --- |
   | Keyword | Equal or contains | `Zava OR AeroFrame OR ZV-9000 OR Prototype OR BOM OR Manufacturing` |
   | Date | Between | Start one day before Challenge 2 and end at the current date/time |

4. Select **Save** if required by the UI.

5. Select **Review scope**, **Run query**, **Generate statistics**, or the equivalent action in your tenant.

6. Review the estimates, statistics, and sample results when they appear.

7. Record the following information in a temporary note file such as `C:\LabFiles\dsi-notes.txt`:

   - Search name or query description
   - Date/time range used
   - Data sources included
   - Total matches, if shown
   - Top locations or workloads with hits
   - Any sample item titles or subjects that match the Zava scenario

8. If results are empty, broaden the keyword value to one term at a time, such as `Zava`, `Prototype`, or `BOM`, and rerun the query.

> [!Note]
> The search experience can search Microsoft 365 content from services such as Exchange Online, Teams, OneDrive, and SharePoint when those workloads contain indexed data in your tenant.

## Task 5: Refine searches with filename, keyword, file type, date, size, and external indicators

In this task, you will run several focused searches that mirror real investigation pivots. Keep each search small and record whether it returns data.

1. Create a filename search for known Zava design artifacts.

   Use **Query builder** filters where available, or use the keyword box with filename terms. Run separate searches if your tenant does not support grouping many file names together.

   | Search purpose | Suggested filter or keyword |
   | --- | --- |
   | STEP design file | `AeroFrame-Assembly-RevC.step` or `filename="AeroFrame-Assembly-RevC*"` |
   | CAD drawing | `ZV-9000-Cooling-Manifold.dwg` or `filename="ZV-9000-Cooling-Manifold*"` |
   | Spreadsheet evidence | `Prototype-Test-Matrix.xlsx` or `Supplier-Costed-BOM-Q4.xlsx` |
   | Manufacturing PDF | `Manufacturing-Tolerances.pdf` |

2. For each filename search, select **Review scope**, **Run query**, or **Generate statistics**, then record:

   - Match count, if available
   - Workload or location type
   - Subject/title
   - Sender/author if shown
   - Whether the item appears to be an email attachment, OneDrive file, SharePoint file, or Teams-related item

3. Create a file type search for engineering and business file extensions.

   Use the **File type**, **Type**, **Kind**, or **Keyword** filter your tenant exposes. Try these values separately if a combined query does not validate:

   | File type goal | Values to try |
   | --- | --- |
   | CAD or design | `step`, `dwg` |
   | Spreadsheet | `xlsx` |
   | PDF | `pdf` |

4. Add a **Date** filter to the file type search. Use a range that starts before you copied or emailed the design files in Challenge 2 and ends at the current time.

5. Add a **Size (in bytes)** filter if your tenant exposes it. Use a broad lower bound such as **Greater than** `1000` bytes to remove tiny system items without excluding the prepared lab files.

6. Run the query and review the result estimates or samples.

7. Create an external-indicator search for outbound messages.

   Use one or more of the following filters based on what your tenant exposes:

   | Indicator | Suggested condition |
   | --- | --- |
   | Sender | Sender contains <inject key="AzureAdUserEmail"></inject> |
   | To or Recipients | The external recipient you used in Challenge 2 |
   | Participants | The risky user and the external recipient |
   | Message kind or Kind | `email` |
   | Keyword | One of the Zava file names or subject keywords used in the email |
   | Date or Sent | The Challenge 2 email time window |

8. Run the external-indicator search.

9. If the search finds the email you sent in Challenge 2, open the sample or source preview and verify whether the attachment name, recipient, subject, or body text ties the email to the suspected exfiltration.

10. If the external-indicator search returns no results, document the exact filters used and then broaden the query by removing file name restrictions while keeping the sender and date range.

11. Select the best search that returns a non-empty Zava result set. You will export this search in Task 7. Prefer the search that contains the outbound email with a Zava attachment or a filename result tied to the risky user.

12. Checkpoint: before continuing, confirm `C:\LabFiles\dsi-notes.txt` lists at least one broad search and at least one refined filename, file type, or external-recipient search. The selected export candidate must be a real portal search or process result, not a locally typed note.

> [!Important]
> Use supported filters exposed by your Purview portal. Filter names vary slightly between Data Security Investigations and eDiscovery, and some filters apply only to mailboxes while others apply to SharePoint and OneDrive content. The defensible investigation pattern is to start with reliable filters, review estimates/samples, and then refine.

## Task 6: Explore sensitivity label filters safely in a fresh tenant

In this task, you will inspect sensitivity-label filtering without requiring any specific label to exist or return results.

1. In the same investigation search experience, select **Add filter**.

2. Search the filter picker for label-related filters. Depending on tenant capabilities, you may see filters such as **Sensitivity label**, **Compliance tag**, **Information protection label**, or no label filter at all.

3. If a sensitivity-label filter is available, add it to a copy of one earlier search. Do not replace your working filename or email search.

4. If the filter lists label values, select any existing label value that is already present in the tenant. Do not create, publish, or wait for a new sensitivity label during this lab.

5. Run the label-filtered search.

6. Record one of the following outcomes in `C:\LabFiles\dsi-notes.txt`:

   - `Sensitivity label filter available; no labeled Zava content found.`
   - `Sensitivity label filter available; labeled item found: <title or subject>.`
   - `Sensitivity label filter not exposed in this tenant/search experience.`

7. Select **Search** > **Audit** if available in Data Security Investigations, or open the available audit/search activity view in your tenant.

8. Configure an audit search for the risky user with a date/time range covering this lab. Include label-related activities only if they are available, such as **Changed sensitivity label applied to file** or **Removed sensitivity label from file**.

9. Select **Search**.

10. Document whether label-change activity exists. In a fresh tenant, no results is expected unless labels were already configured before the lab.

> [!Note]
> This lab intentionally treats sensitivity-label filtering as no-results-safe exploration. Sensitivity labels and label policies can require publishing and client propagation time, so this challenge does not depend on label creation or a labeled-result count.

## Task 7: Export the smallest real DSI or eDiscovery evidence artifact to the lab VM

In this task, you will create `C:\LabFiles\DSIExports` and save a real Microsoft Purview portal export or downloadable report/list. The default is **no native item export** and **report-only eDiscovery export** unless DSI metering/capacity and larger exports have been approved. Do not create the final `dsi_case_evidence.json` by typing evidence values yourself; Task 8 uses a helper to normalize the portal export you download here.

1. Open **Windows PowerShell** on the lab VM.

2. Create the export folder:

   ```powershell
   New-Item -ItemType Directory -Force -Path C:\LabFiles\DSIExports | Out-Null
   ```

3. Return to the DSI or eDiscovery search that produced the best Zava result set in Task 5.

4. If you are using Data Security Investigations and your instructor approved any required DSI metering/capacity usage, save the smallest real downloadable artifact your tenant exposes in the DSI experience. Examples include a downloadable result list, activity list, process list, or report such as a CSV. Save the file under `C:\LabFiles\DSIExports`. Do not add more data to DSI scope, run extra analysis, or assume a generic DSI export button exists in every tenant.

5. If DSI use is not approved, if DSI does not expose a clear downloadable report/list, or if you need the reliable low-export validation path, use the eDiscovery fallback and export the smallest result/report that proves the Zava evidence:

   - Go to **Solutions** > **eDiscovery** > **Cases**.
   - Open **Insider Threat Case - Design Engineer**.
   - Select the **Searches** tab.
   - Select the search that returned Zava evidence.
   - Select **Export**.
   - Use an export name such as `Zava-Design-Evidence-Export`.
   - In **Select items to include in your export**, select **Indexed items that match your search query**.
   - Avoid options that expand scope, such as partially indexed items, cloud attachments, conversation expansion, or all versions, unless your instructor approves them and the report-only export cannot prove the Zava evidence.
   - In **Export type**, select **Export items report only**. Microsoft Learn states this creates only the summary and item report, which is the smallest appropriate validation artifact for this lab.
   - Use **Export items with items report** only if the report-only export does not include enough Zava metadata for validation and your instructor approves exporting source items.
   - Select **Export**, then select **OK** when the export process starts.

6. Monitor the export from **Process manager** in the appropriate eDiscovery area, such as the case or search area. Microsoft Learn states that eDiscovery export progress can be tracked in **Process manager**, and completed search exports can be viewed from the **Exports** tab while the package remains available.

7. When the export completes, download the package or report files to the lab VM. Save or extract the contents under `C:\LabFiles\DSIExports`. Keep filenames that show they came from the portal, such as:

   - `Zava-Design-Evidence-Export.zip`
   - `Items.csv`
   - `Export_summary.csv`
   - `ProcessReport.csv`
   - `dsi_process_list.csv`
   - `dsi_search_results.csv`

8. Confirm at least one downloaded or extracted file exists and is not empty:

   ```powershell
   Get-ChildItem C:\LabFiles\DSIExports -Recurse | Where-Object { -not $_.PSIsContainer -and $_.Length -gt 0 } | Select-Object FullName, Length, LastWriteTime
   ```

9. If the export contains a ZIP file, extract it into a subfolder so the validator and your helper can inspect CSV, TXT, HTML, or report files:

   ```powershell
   $zip = Get-ChildItem C:\LabFiles\DSIExports -Filter *.zip -File | Select-Object -First 1
   if ($zip) {
       $destination = Join-Path $zip.DirectoryName ($zip.BaseName + '_extracted')
       Expand-Archive -Path $zip.FullName -DestinationPath $destination -Force
       Get-ChildItem $destination -Recurse | Select-Object FullName, Length
   }
   ```

10. Checkpoint: confirm the export folder contains a non-empty file downloaded from the Microsoft Purview portal, such as an eDiscovery report-only export ZIP, an items report CSV, an export summary, a process report, or an approved DSI downloadable report/list CSV. A screenshot, typed note, or hand-created JSON file does not satisfy this checkpoint.

> [!Important]
> The evidence source for this challenge must be a real Microsoft Purview portal export or downloadable report/list. A locally typed JSON file, copied notes, or an empty placeholder file is not sufficient. If your first export has no rows or no Zava evidence, return to the search page, broaden the query, and export a non-empty result set. Prefer the smallest possible eDiscovery report-only export unless your instructor approves DSI metering/capacity usage or source-item export.

## Task 8: Normalize the portal export for validation and the final report

In this task, you will run a local normalization helper. The helper reads the exported files saved in `C:\LabFiles\DSIExports`, verifies that the files contain the risky user or Zava evidence, counts exported rows/items where possible, and writes `dsi_case_evidence.json`. The helper does not accept a manually invented result count or typed Zava evidence as the source of truth.

1. In PowerShell, set the risky user variable when prompted. Enter the lab admin UPN shown here: <inject key="AzureAdUserEmail"></inject>.

2. Run the following helper:

   ```powershell
   $exportRoot = 'C:\LabFiles\DSIExports'
   $caseName = 'Insider Threat Case - Design Engineer'
   $searchedUpn = Read-Host 'Enter the searched/custodian UPN exactly as shown in the Purview case or search'

   $files = Get-ChildItem -Path $exportRoot -Recurse -File -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -ne 'dsi_case_evidence.json' -and $_.Length -gt 0 }

   if (-not $files) {
       throw 'No non-empty portal export files were found under C:\LabFiles\DSIExports. Download a DSI report/list or eDiscovery export first.'
   }

   $textExtensions = '.csv', '.txt', '.json', '.xml', '.html', '.htm', '.log'
   $readableFiles = $files | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() }
   if (-not $readableFiles) {
       throw 'No readable CSV/TXT/JSON/XML/HTML report files were found. Extract the Purview export package and rerun this helper.'
   }

   $zavaTerms = @(
       'Zava',
       'AeroFrame-Assembly-RevC',
       'ZV-9000-Cooling-Manifold',
       'Prototype-Test-Matrix',
       'Supplier-Costed-BOM-Q4',
       'Manufacturing-Tolerances',
       'BOM',
       'Prototype'
   )

   $combinedText = New-Object System.Text.StringBuilder
   foreach ($file in $readableFiles) {
       try {
           [void]$combinedText.AppendLine((Get-Content -Path $file.FullName -Raw -ErrorAction Stop))
       } catch {
           Write-Warning "Could not read $($file.FullName): $($_.Exception.Message)"
       }
   }

   $allText = $combinedText.ToString()
   $matchedTerms = $zavaTerms | Where-Object { $allText -match [regex]::Escape($_) } | Select-Object -Unique
   $upnFound = $false
   if ($searchedUpn) {
       $upnFound = $allText -match [regex]::Escape($searchedUpn)
   }

   $csvSummaries = @()
   foreach ($csv in ($readableFiles | Where-Object { $_.Extension -ieq '.csv' })) {
       try {
           $rows = Import-Csv -Path $csv.FullName -ErrorAction Stop
           $csvSummaries += [pscustomobject]@{
               path = $csv.FullName
               rowCount = @($rows).Count
               columns = (($rows | Select-Object -First 1).PSObject.Properties.Name -join ',')
           }
       } catch {
           $lineCount = (Get-Content -Path $csv.FullName -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
           $csvSummaries += [pscustomobject]@{
               path = $csv.FullName
               rowCount = [Math]::Max(0, $lineCount - 1)
               columns = 'unparsed csv'
           }
       }
   }

   $bestResultCount = 0
   if ($csvSummaries) {
       $bestResultCount = ($csvSummaries | Measure-Object -Property rowCount -Maximum).Maximum
   }
   if (-not $bestResultCount -or $bestResultCount -lt 1) {
       $bestResultCount = @($files).Count
   }

   if (-not $matchedTerms -or @($matchedTerms).Count -lt 1) {
       throw 'The portal export does not contain any Zava file or email terms. Export a search result that includes Zava evidence.'
   }

   if ($searchedUpn -and -not $upnFound) {
       throw 'The searched/custodian UPN was not found in the exported report files. Export the case/search report that includes custodian, location, sender, or participant metadata.'
   }

   if ($bestResultCount -lt 1) {
       throw 'The portal export did not contain a non-empty result count or exported item file.'
   }

   $metadata = [ordered]@{
       caseName = $caseName
       searchOrExportName = (($files | Where-Object { $_.BaseName -match 'Zava|Export|Search|Items|Process' } | Select-Object -First 1).BaseName)
       custodianOrSearchedUpn = $searchedUpn
       source = 'Microsoft Purview portal export normalized locally'
       sourceExportRoot = $exportRoot
       sourceExportFiles = @($files | Select-Object FullName, Length, LastWriteTimeUtc)
       readableReportFiles = @($readableFiles | Select-Object FullName, Length, LastWriteTimeUtc)
       csvSummaries = @($csvSummaries)
       zavaEvidenceTermsFound = @($matchedTerms)
       custodianUpnFoundInExport = [bool]$upnFound
       resultCountOrExportedItems = [int]$bestResultCount
       normalizedCreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
       notesPath = 'C:\LabFiles\dsi-notes.txt'
   }

   $outFile = Join-Path $exportRoot 'dsi_case_evidence.json'
   $metadata | ConvertTo-Json -Depth 8 | Set-Content -Path $outFile -Encoding UTF8
   Get-Content $outFile -Raw | ConvertFrom-Json | Format-List
   ```

3. Confirm that `dsi_case_evidence.json` was created from the portal export and includes non-empty values:

   ```powershell
   $evidence = Get-Content C:\LabFiles\DSIExports\dsi_case_evidence.json -Raw | ConvertFrom-Json
   $evidence.caseName
   $evidence.custodianOrSearchedUpn
   $evidence.zavaEvidenceTermsFound
   $evidence.resultCountOrExportedItems
   $evidence.sourceExportFiles | Select-Object FullName, Length
   ```

4. If any field is blank, if the result count is zero, or if the helper reports that no Zava terms or UPN were found, return to Task 5 or Task 7 and export a better DSI/eDiscovery result set.

<validation step="04-task-dsi-exported-evidence"/>

### Optional cleanup — only after you have finished Challenge 5

> [!WARNING]
> Do not run this cleanup until you have finished Challenge 5 and are not going to re-run any
> validation. The Challenge 4 validation cross-checks `dsi_case_evidence.json` against the source
> export files it references, so deleting those files fails the validation even though your
> investigation work was correct.

This cleanup is optional. Run it only if your instructor or tenant owner asks you to remove the
exported evidence, and only once the lab is complete.

1. If your instructor requires retaining the case and export evidence, record the retention requirement in `C:\LabFiles\dsi-notes.txt` and do not delete the retained evidence.

2. If retention is not required and you created an eDiscovery search export, delete the completed export from the Microsoft Purview portal:

   - Go to **Solutions** > **eDiscovery** > **Cases**.
   - Open **Insider Threat Case - Design Engineer**.
   - Select the **Exports** tab for the case or search.
   - Select the completed `Zava-Design-Evidence-Export` export.
   - Select the ellipsis or available action menu, then select **Delete**.
   - Confirm the deletion. Microsoft Learn states that deleting an export removes the export and all data contained in the export package, but does not delete data in the original location.

3. If retention is not required and you created a DSI investigation with approved metering/capacity, delete the lab investigation after preserving any required report:

   - Go to **Data Security Investigations** > **Investigations**.
   - Select **Insider Threat Case - Design Engineer**.
   - Open **Investigation settings**.
   - Select **Actions** > **Delete investigations** or the equivalent delete action shown by your tenant.
   - Confirm the deletion only after you have saved any required local evidence. Deleting investigations and associated data is irreversible.

4. If retention is not required for downloaded native items, ZIP files, or large report packages on the lab VM, remove the unneeded local export files after preserving the normalized JSON and notes for Challenge 5:

   ```powershell
   # Keep the normalized index AND the source exports it references - the Challenge 4
   # validation reads both. Only large native/binary downloads are removed here.
   $keepNames      = @('dsi_case_evidence.json')
   $keepExtensions = @('.json','.csv','.txt','.xml','.html','.htm','.log','.eml')
   Get-ChildItem C:\LabFiles\DSIExports -Recurse -File |
       Where-Object { $keepNames -notcontains $_.Name -and $keepExtensions -notcontains $_.Extension } |
       Remove-Item -Force
   Get-ChildItem C:\LabFiles\DSIExports -Recurse | Select-Object FullName, Length
   ```

5. If DSI AI capacity was enabled only for this lab and is no longer needed, coordinate with your instructor or tenant owner before removing any DSI compute unit capacity resource or disabling billing. Do not remove shared tenant capacity without approval.

## Task 9: Record findings for the final case report

In this task, you will summarize your investigation in a format you can reuse in Challenge 5.

1. Open Windows PowerShell or File Explorer on the lab VM.

2. Create or update `C:\LabFiles\dsi-notes.txt`.

3. Add the following investigation summary. Replace bracketed values with your actual findings from the portal export and the normalized metadata file:

   ```text
   Data Security Investigation: Insider Threat Case - Design Engineer
   Investigation type: [DSI approved path or eDiscovery fallback]
   Risky user/custodian: <your lab admin UPN>
   Lab VM: labvm-<your deployment ID>

   Scope:
   - Data sources searched: [Exchange / OneDrive / SharePoint / Teams / other]
   - Date range: [start UTC/local] to [end UTC/local]

   Searches performed:
   - Broad keyword search: [match count and top locations]
   - Filename searches: [file names found or no-result notes]
   - File type searches: [extensions searched and outcomes]
   - File size/date refinements: [filters used and outcomes]
   - External recipient/sharing indicators: [recipient/domain and outcomes]
   - Sensitivity label exploration: [available/not available/results]

   Relevant exported items:
   - [Subject/title, workload, sender/author, date, exported result count, why relevant]

   Export collection:
   - Folder: C:\LabFiles\DSIExports
   - Portal export source: [approved DSI downloadable report/list name or eDiscovery report-only export name]
   - Metadata file: C:\LabFiles\DSIExports\dsi_case_evidence.json
   - Cleanup completed: [yes/no; list retained files or portal exports if retained]

   Link to Challenge 3 hunting:
   - [DeviceFileEvents or endpoint evidence summary]
   - [EmailEvents or outbound message evidence summary]
   - [Defender alert evidence summary]

   Investigator conclusion:
   - [Concise statement of whether content search evidence supports the suspected design-file exfiltration scenario]
   ```

4. Save the file.

5. Return to the Purview portal. If instructor retention requires keeping the investigation or case, confirm **Insider Threat Case - Design Engineer** remains visible under **Data Security Investigations** > **Investigations** or under your eDiscovery fallback case list. If you followed the required cleanup after validation, confirm instead that the minimum local evidence files remain available under `C:\LabFiles\DSIExports` and do not recreate deleted DSI investigations or eDiscovery exports.

6. Keep `C:\LabFiles\dsi-notes.txt` and `C:\LabFiles\DSIExports\dsi_case_evidence.json` available. You will use them when you export Defender alert evidence and build the case report in Challenge 5.

## Summary

You created the **Insider Threat Case - Design Engineer** investigation only where DSI was available and approved, or used the low-export eDiscovery fallback when DSI setup, billing, capacity, permissions, approval, or downloadable DSI report/list options were unavailable. You scoped the investigation to the lab admin account as the risky user custodian, searched available Microsoft 365 workloads for Zava design-file evidence, and documented filename, keyword, file type, date, file size, external-recipient, and sensitivity-label pivots. You also saved the smallest real DSI downloadable report/list or eDiscovery portal report/export under `C:\LabFiles\DSIExports`, normalized it into `dsi_case_evidence.json` for validation and the final report, and cleaned up unneeded DSI/eDiscovery exports when retention was not required.

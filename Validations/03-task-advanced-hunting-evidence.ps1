using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
#
# Validation 3 proves the learner's activity is genuinely present in Advanced Hunting.
#
# It previously graded C:\LabFiles\Challenge3-HuntingNotes.txt with substring matching. That was
# defeatable: the lab guide itself supplies an example evidence row and a model summary containing
# every term the checks looked for, so a learner could paste the guide's own text and pass without
# ever opening Advanced Hunting. Text matching is not evidence of work.
#
# This validator now runs the hunting queries itself, using the validation identity, and scores the
# rows returned. The notes file must still exist and be non-empty because Validation 5 consumes it,
# but its wording is no longer graded.
#
# Fail-closed contract: any token failure, non-success response, unparseable body or absent result
# set FAILS with a message naming what could not be read. An empty result array is never a pass -
# runHuntingQuery returns HTTP 200 with zero rows when nothing matches, so row counts are tested
# explicitly rather than status codes.

$vmName = "labvm-$DID"
$notesFileName = "Challenge3-HuntingNotes.txt"
$finalFailureMessage = "Advanced Hunting evidence for '$vmName' was not validated."

$stagedFileNames = @(
    "AeroFrame-Assembly-RevC.step",
    "ZV-9000-Cooling-Manifold.dwg",
    "Prototype-Test-Matrix.xlsx",
    "Supplier-Costed-BOM-Q4.xlsx",
    "Manufacturing-Tolerances.pdf"
)

$result = [ordered]@{
    VmName           = $vmName
    NotesPresent     = $false
    NotesLength      = 0
    FileActivityRows = 0
    AlertRows        = 0
    EmailRows        = $null
    EmailEvaluated   = $false
    Failures         = New-Object System.Collections.Generic.List[string]
    Passed           = $false
}

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $result.Failures.Add($Message) | Out-Null
}

function Convert-TokenToPlainText {
    param([Parameter(Mandatory = $true)]$AccessToken)
    if ($AccessToken.Token -is [System.Security.SecureString]) {
        return ([System.Net.NetworkCredential]::new("", $AccessToken.Token)).Password
    }
    return [string]$AccessToken.Token
}

# Runs one Advanced Hunting query and returns its rows. Throws on every failure path so the
# caller fails closed with a specific reason rather than defaulting to success.
function Invoke-HuntingQuery {
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)][string]$Purpose
    )
    $body = @{ Query = $Query } | ConvertTo-Json -Depth 3
    try {
        $response = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/security/runHuntingQuery" -Headers $Headers -Body $body -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        $suffix = ""
        if ($status) { $suffix = " (HTTP $status)" }
        throw "Could not run the $Purpose Advanced Hunting query$suffix. $($_.Exception.Message)"
    }
    if ($null -eq $response) {
        throw "The $Purpose Advanced Hunting query returned an empty response body."
    }
    if (-not ($response.PSObject.Properties.Name -contains 'results')) {
        throw "The $Purpose Advanced Hunting response contained no 'results' property, so it could not be read."
    }
    return @($response.results)
}

function Get-RowCount {
    param($Rows)
    if ($null -ne $Rows -and @($Rows).Count -gt 0 -and $null -ne $Rows[0].RowCount) {
        return [int]$Rows[0].RowCount
    }
    return 0
}

try {
    # Token: the validation identity, as Validation 2 already uses. Deliberately NOT the learner's
    # config.json app - the bootstrap grants that app only SecurityAlert.Read.All, so
    # runHuntingQuery would return 403, and Challenge 5 teaches least privilege with that one role.
    try {
        $ctx = Get-AzContext -ErrorAction Stop
        $tenantId = $ctx.Tenant.Id
        $graphToken = Convert-TokenToPlainText -AccessToken (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -TenantId $tenantId -ErrorAction Stop)
    }
    catch {
        throw "Could not acquire a Microsoft Graph token for the validation identity. $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($graphToken)) {
        throw "The Microsoft Graph token for the validation identity was empty."
    }
    $headers = @{ Authorization = "Bearer $graphToken"; Accept = "application/json"; "User-Agent" = "CloudLabs-Validation/1.0" }

    # DeviceName in Advanced Hunting is a lowercased FQDN, so match on prefix, not equality.
    $deviceFilter = "DeviceName startswith tolower('$vmName')"
    $fileNameList = ($stagedFileNames | ForEach-Object { "'$_'" }) -join ","

    # 1. File activity on the staged design files. Covers the source folder and the staging folder,
    #    because the learner copies between them.
    $fileQuery = "DeviceFileEvents | where Timestamp > ago(12h) | where $deviceFilter | where FolderPath has 'ZavaDesignFiles' or FolderPath has 'ExfilStaging' or FileName in~ ($fileNameList) | summarize RowCount = count()"
    $result.FileActivityRows = Get-RowCount (Invoke-HuntingQuery -Query $fileQuery -Headers $headers -Purpose "file-activity")
    if ($result.FileActivityRows -lt 1) {
        Add-Failure "No DeviceFileEvents rows were found in the last 12 hours for '$vmName' touching the Zava design files or the ExfilStaging folder. Complete the Challenge 2 file activity, confirm the device is onboarded and reporting, then retry - endpoint telemetry can take several minutes to arrive."
    }

    # 2. The learner's own Defender for Endpoint alert, tied to this device.
    $alertQuery = "AlertInfo | where Timestamp > ago(12h) | where ServiceSource == 'Microsoft Defender for Endpoint' | join kind=inner AlertEvidence on AlertId | where $deviceFilter | summarize RowCount = count()"
    $result.AlertRows = Get-RowCount (Invoke-HuntingQuery -Query $alertQuery -Headers $headers -Purpose "alert-evidence")
    if ($result.AlertRows -lt 1) {
        Add-Failure "No Microsoft Defender for Endpoint alert was found in the last 12 hours linked to device '$vmName'. Run the EICAR test from Challenge 2, confirm Defender Antivirus real-time protection is on, then retry."
    }

    # 3. Email activity, scored only where the table exists. A tenant without Defender for Office P2
    #    has no EmailEvents table and the guide allows a DSI fallback there, so a missing table is
    #    recorded as not-evaluated - never as a pass.
    try {
        $emailQuery = "EmailEvents | where Timestamp > ago(12h) | where AttachmentCount > 0 | summarize RowCount = count()"
        $result.EmailRows = Get-RowCount (Invoke-HuntingQuery -Query $emailQuery -Headers $headers -Purpose "email-activity")
        $result.EmailEvaluated = $true
    }
    catch {
        $result.EmailEvaluated = $false
        $result.EmailRows = $null
    }

    # 4. The notes artefact must exist because Validation 5 reads it, but its text proves nothing.
    try {
        $rg = (Get-AzVM -ErrorAction Stop | Where-Object { $_.Name -ieq $vmName } | Select-Object -First 1).ResourceGroupName
        if ([string]::IsNullOrWhiteSpace($rg)) { throw "VM '$vmName' was not found in this subscription." }
        $notesFullPath = "C:\LabFiles\" + $notesFileName
        $probe = 'if (Test-Path "' + $notesFullPath + '") { $c = Get-Content -Path "' + $notesFullPath + '" -Raw -ErrorAction SilentlyContinue; "PRESENT:" + $c.Length } else { "MISSING:0" }'
        $run = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $probe -ErrorAction Stop
        $out = ($run.Value | Where-Object { $_.Code -like '*StdOut*' } | Select-Object -First 1).Message
        if ($out -match 'PRESENT:(\d+)') {
            $result.NotesPresent = $true
            $result.NotesLength = [int]$Matches[1]
            if ($result.NotesLength -lt 50) {
                Add-Failure "The hunting notes file '$notesFullPath' exists but is effectively empty. Record your findings there - Challenge 5 reads this file for the final report."
            }
        }
        else {
            Add-Failure "The hunting notes file '$notesFullPath' was not found on '$vmName'. Save your Advanced Hunting summary there before validating."
        }
    }
    catch {
        Add-Failure "Could not read the hunting notes file on '$vmName': $($_.Exception.Message)"
    }

    # Verdict: real rows required. No credit for text.
    $result.Passed = (
        $result.FileActivityRows -ge 1 -and
        $result.AlertRows -ge 1 -and
        $result.NotesPresent -and
        $result.NotesLength -ge 50
    )
}
catch {
    $result.Passed = $false
    Add-Failure $_.Exception.Message
}

if ($result.Passed) {
    if ($result.EmailEvaluated) {
        $emailNote = " EmailEvents rows: $($result.EmailRows)."
    }
    else {
        $emailNote = " EmailEvents was not available in this tenant and was not scored."
    }
    $message = "PASS: Advanced Hunting confirms the learner's own activity on '$vmName'. DeviceFileEvents rows: $($result.FileActivityRows). Defender for Endpoint alert rows: $($result.AlertRows).$emailNote"
    Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
}
else {
    if ($result.Failures.Count -gt 0) { $detail = ($result.Failures -join ' ') } else { $detail = $finalFailureMessage }
    Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = "FAIL: $detail" })
}

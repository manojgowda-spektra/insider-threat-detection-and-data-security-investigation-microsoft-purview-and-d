using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
# Validation 3 uses Azure VM Run Command to inspect the learner-created local notes artifact.
# It does not call Microsoft 365, Defender, Graph, or any other external service API.

$vmName = "labvm-$DID"
$rg = $null
$count = 0
$found = $false
$lastFailure = "Advanced Hunting evidence notes were not validated."

$huntingNotesScript = @'
$ErrorActionPreference = "Stop"

$deploymentId = "__DEPLOYMENT_ID__"
$vmName = "labvm-$deploymentId"
$slash = [char]92
$root = "C" + [char]58 + $slash
$labRoot = Join-Path -Path $root -ChildPath "LabFiles"
$notesPath = Join-Path -Path $labRoot -ChildPath "Exercise3-HuntingNotes.txt"
$stagingPath = Join-Path -Path $labRoot -ChildPath "ZavaDesignFiles"

$advancedHuntingTables = @(
    "DeviceFileEvents",
    "DeviceEvents",
    "EmailEvents",
    "EmailAttachmentInfo",
    "AlertInfo",
    "AlertEvidence"
)

$zavaEvidenceTerms = @(
    "ZavaDesignFiles",
    $stagingPath,
    "AeroFrame-Assembly-RevC.step",
    "ZV-9000-Cooling-Manifold.dwg",
    "Prototype-Test-Matrix.xlsx",
    "Supplier-Costed-BOM-Q4.xlsx",
    "Manufacturing-Tolerances.pdf"
)

$fileEvidenceTerms = @(
    "FileName",
    "FolderPath",
    "DeviceFileEvents",
    "InitiatingProcess",
    "SHA1",
    "SHA256",
    "copied",
    "created",
    "modified",
    "ZavaDesignFiles"
)

$emailEvidenceTerms = @(
    "EmailEvents",
    "EmailAttachmentInfo",
    "SenderFromAddress",
    "RecipientEmailAddress",
    "NetworkMessageId",
    "Subject",
    "attachment",
    "outbound",
    "sent"
)

$alertEvidenceTerms = @(
    "AlertInfo",
    "AlertEvidence",
    "EICAR",
    "MDE",
    "Microsoft Defender",
    "Defender for Endpoint",
    "test file",
    "malware",
    "virus"
)

$result = [ordered]@{
    NotesPath                  = $notesPath
    Exists                     = $false
    LengthBytes                = 0
    NonEmpty                   = $false
    CharacterCount             = 0
    ContainsLabScope           = $false
    LabScopeMatches            = @()
    MatchedTables              = @()
    ContainsRequiredTables     = $false
    MatchedZavaEvidence        = @()
    ContainsZavaEvidence       = $false
    MatchedFileEvidenceTerms   = @()
    ContainsFileEvidence       = $false
    MatchedEmailEvidenceTerms  = @()
    ContainsEmailEvidence      = $false
    MatchedAlertEvidenceTerms  = @()
    ContainsAlertEvidence      = $false
    Failures                   = New-Object System.Collections.ArrayList
    Passed                     = $false
}

function Add-Failure {
    param([string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        [void]$result.Failures.Add($Message)
    }
}

function Find-TermMatches {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Terms
    )
    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($term in $Terms) {
        if (-not [string]::IsNullOrWhiteSpace($term) -and $Text -match [regex]::Escape($term)) {
            $matches.Add($term) | Out-Null
        }
    }
    return @($matches | Select-Object -Unique)
}

if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
    Add-Failure "Missing required notes file '$notesPath'. Save the Exercise 3 Advanced Hunting summary to this exact path on the lab VM."
}
else {
    $item = Get-Item -LiteralPath $notesPath -ErrorAction Stop
    $result.Exists = $true
    $result.LengthBytes = [int64]$item.Length

    if ($item.Length -le 0) {
        Add-Failure "Notes file '$notesPath' exists but is empty."
    }
    else {
        $content = Get-Content -LiteralPath $notesPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            Add-Failure "Notes file '$notesPath' contains only whitespace."
        }
        else {
            $result.NonEmpty = $true
            $result.CharacterCount = $content.Length
            $normalized = $content -replace "`0", " "

            if ($normalized.Length -lt 150) {
                Add-Failure "Notes file '$notesPath' is too short to contain concrete hunting evidence. Add a concise summary with KQL table names, VM/deployment scope, Zava file/path evidence, and alert/email/file findings."
            }

            $labScopeMatches = New-Object System.Collections.Generic.List[string]
            if ($normalized -match [regex]::Escape($vmName)) { $labScopeMatches.Add($vmName) | Out-Null }
            if ($normalized -match [regex]::Escape($deploymentId)) { $labScopeMatches.Add($deploymentId) | Out-Null }
            if ($normalized -match "(?i)\blabvm[-_ ]") { $labScopeMatches.Add("labvm reference") | Out-Null }
            $result.LabScopeMatches = @($labScopeMatches | Select-Object -Unique)
            $result.ContainsLabScope = ($result.LabScopeMatches.Count -gt 0)
            if (-not $result.ContainsLabScope) {
                Add-Failure "Notes do not identify the lab scope. Include VM '$vmName' or deployment id '$deploymentId'."
            }

            $result.MatchedTables = @(Find-TermMatches -Text $normalized -Terms $advancedHuntingTables)
            $hasDeviceTable = @($result.MatchedTables | Where-Object { $_ -in @("DeviceFileEvents", "DeviceEvents") }).Count -gt 0
            $hasMessageOrAlertTable = @($result.MatchedTables | Where-Object { $_ -in @("EmailEvents", "EmailAttachmentInfo", "AlertInfo", "AlertEvidence") }).Count -gt 0
            $result.ContainsRequiredTables = ($result.MatchedTables.Count -ge 3 -and $hasDeviceTable -and $hasMessageOrAlertTable)
            if (-not $result.ContainsRequiredTables) {
                Add-Failure "Notes must include at least three relevant Advanced Hunting table names, including a device table and an email or alert table. Expected examples: DeviceFileEvents, DeviceEvents, EmailEvents, EmailAttachmentInfo, AlertInfo, AlertEvidence. Matched: $(@($result.MatchedTables) -join ', ')."
            }

            $result.MatchedZavaEvidence = @(Find-TermMatches -Text $normalized -Terms $zavaEvidenceTerms)
            $result.ContainsZavaEvidence = ($result.MatchedZavaEvidence.Count -gt 0)
            if (-not $result.ContainsZavaEvidence) {
                Add-Failure "Notes do not cite a staged Zava filename or staging path. Include evidence such as the ZavaDesignFiles staging folder or a staged file name like 'AeroFrame-Assembly-RevC.step'."
            }

            $result.MatchedFileEvidenceTerms = @(Find-TermMatches -Text $normalized -Terms $fileEvidenceTerms)
            $result.ContainsFileEvidence = ($result.MatchedFileEvidenceTerms.Count -ge 2)
            if (-not $result.ContainsFileEvidence) {
                Add-Failure "Notes do not include sufficient file-activity evidence terms. Include file hunting fields/actions such as FileName, FolderPath, DeviceFileEvents, copied, created, SHA1, or InitiatingProcess."
            }

            $result.MatchedEmailEvidenceTerms = @(Find-TermMatches -Text $normalized -Terms $emailEvidenceTerms)
            $result.ContainsEmailEvidence = ($result.MatchedEmailEvidenceTerms.Count -ge 2)
            if (-not $result.ContainsEmailEvidence) {
                Add-Failure "Notes do not include sufficient email/attachment evidence terms. Include terms such as EmailEvents, EmailAttachmentInfo, SenderFromAddress, RecipientEmailAddress, Subject, attachment, or outbound."
            }

            $result.MatchedAlertEvidenceTerms = @(Find-TermMatches -Text $normalized -Terms $alertEvidenceTerms)
            $result.ContainsAlertEvidence = ($result.MatchedAlertEvidenceTerms.Count -ge 2)
            if (-not $result.ContainsAlertEvidence) {
                Add-Failure "Notes do not include sufficient alert evidence terms. Include terms such as AlertInfo, AlertEvidence, EICAR, Microsoft Defender, Defender for Endpoint, MDE, or test file."
            }
        }
    }
}

$result.Passed = (
    $result.Exists -and
    $result.NonEmpty -and
    $result.CharacterCount -ge 150 -and
    $result.ContainsLabScope -and
    $result.ContainsRequiredTables -and
    $result.ContainsZavaEvidence -and
    $result.ContainsFileEvidence -and
    $result.ContainsEmailEvidence -and
    $result.ContainsAlertEvidence -and
    $result.Failures.Count -eq 0
)

Write-Output "CL_VALIDATION_JSON_START"
Write-Output ($result | ConvertTo-Json -Depth 8 -Compress)
Write-Output "CL_VALIDATION_JSON_END"
'@

$escapedDeploymentId = $DID -replace "'", "''"
$huntingNotesScript = $huntingNotesScript.Replace("__DEPLOYMENT_ID__", $escapedDeploymentId)

do {
    $count = $count + 1
    $message = $null

    try {
        if ([string]::IsNullOrWhiteSpace($sub)) {
            throw "Injected subscription id `$sub is null or empty."
        }
        if ([string]::IsNullOrWhiteSpace($DID)) {
            throw "Injected deployment id `$DID is null or empty."
        }

        Set-AzContext -Subscription $sub -ErrorAction Stop | Out-Null

        $vmCandidates = @(Get-AzVM -Name $vmName -ErrorAction Stop)
        if ($null -eq $vmCandidates -or $vmCandidates.Count -eq 0) {
            $lastFailure = "Azure VM '$vmName' was not found in subscription '$sub'."
        }
        elseif ($vmCandidates.Count -gt 1) {
            $candidateGroups = ($vmCandidates | ForEach-Object { $_.ResourceGroupName }) -join ", "
            $lastFailure = "Multiple VMs named '$vmName' were found in subscription '$sub' (resource groups: $candidateGroups); cannot validate Advanced Hunting notes deterministically."
        }
        else {
            $vmModel = $vmCandidates[0]
            $rg = $vmModel.ResourceGroupName
            if ([string]::IsNullOrWhiteSpace($rg)) {
                throw "VM '$vmName' lookup returned an empty ResourceGroupName."
            }

            $vmStatus = Get-AzVM -ResourceGroupName $rg -Name $vmName -Status -ErrorAction Stop
            $powerStatus = @($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -First 1)
            if ($null -eq $powerStatus -or $powerStatus.Code -ne "PowerState/running") {
                $state = if ($null -eq $powerStatus) { "unknown" } else { $powerStatus.Code }
                $lastFailure = "VM '$vmName' in RG '$rg' is not running; current power state is '$state'. Start the VM and retry validation."
            }
            else {
                $runResult = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vmName -CommandId "RunPowerShellScript" -ScriptString $huntingNotesScript -ErrorAction Stop
                if ($null -eq $runResult -or $null -eq $runResult.Value -or $runResult.Value.Count -eq 0) {
                    throw "Invoke-AzVMRunCommand returned no output while checking Exercise 3 notes on '$vmName'."
                }

                $runOutput = (@($runResult.Value | ForEach-Object { $_.Message }) -join "`n")
                if ([string]::IsNullOrWhiteSpace($runOutput)) {
                    throw "Invoke-AzVMRunCommand output was empty while checking Exercise 3 notes on '$vmName'."
                }

                $jsonMatch = [regex]::Match($runOutput, "(?s)CL_VALIDATION_JSON_START\s*(\{.*\})\s*CL_VALIDATION_JSON_END")
                if (-not $jsonMatch.Success -or [string]::IsNullOrWhiteSpace($jsonMatch.Groups[1].Value)) {
                    throw "Could not parse Advanced Hunting notes validation JSON from VM run-command output. Raw output: $runOutput"
                }

                $notesState = $jsonMatch.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $notesState) {
                    throw "Advanced Hunting notes validation JSON parsed to a null object."
                }

                if ($notesState.Passed -eq $true) {
                    $found = $true
                    $tables = @($notesState.MatchedTables) -join ", "
                    $zava = @($notesState.MatchedZavaEvidence) -join ", "
                    $fileTerms = @($notesState.MatchedFileEvidenceTerms) -join ", "
                    $emailTerms = @($notesState.MatchedEmailEvidenceTerms) -join ", "
                    $alertTerms = @($notesState.MatchedAlertEvidenceTerms) -join ", "
                    $message = @{
                        Status  = "Succeeded"
                        Message = "Exercise 3 Advanced Hunting notes were found at '$($notesState.NotesPath)' on VM '$vmName' in RG '$rg' with $($notesState.LengthBytes) bytes. The notes include lab scope '$vmName/$DID', Advanced Hunting tables ($tables), Zava evidence ($zava), file terms ($fileTerms), email terms ($emailTerms), and alert terms ($alertTerms)."
                    } | ConvertTo-Json
                }
                else {
                    $failureDetails = @($notesState.Failures) -join " "
                    if ([string]::IsNullOrWhiteSpace($failureDetails)) {
                        $failureDetails = "The VM-side notes validation did not pass but did not return detailed failures."
                    }
                    $lastFailure = $failureDetails
                    $message = @{
                        Status  = "Failed"
                        Message = "Exercise 3 Advanced Hunting notes validation failed for VM '$vmName' in RG '$rg'. $lastFailure"
                    } | ConvertTo-Json
                }
            }
        }

        if (-not $found -and [string]::IsNullOrWhiteSpace($message)) {
            $message = @{
                Status  = "Failed"
                Message = $lastFailure
            } | ConvertTo-Json
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })

        if (-not $found -and $count -lt 3) {
            Start-Sleep -Seconds 10
        }
    }
    catch {
        $lastFailure = "Error during Advanced Hunting notes check. Attempt $count of 3. Error: $($_.Exception.Message)"
        $message = @{
            Status  = "Failed"
            Message = $lastFailure
        } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })
        Start-Sleep -Seconds 10
    }
} while ($count -lt 3 -and -not $found)

# Post-loop: if every attempt failed, emit a final failure JSON so CloudLabs always sees a structured result.
if (-not $found) {
    if ([string]::IsNullOrWhiteSpace($rg)) {
        $rg = "not discovered"
    }
    $message = @{
        Status  = "Failed"
        Message = "Exercise 3 Advanced Hunting evidence notes were not validated for VM '$vmName' in RG '$rg' after 3 attempts. Last failure: $lastFailure"
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}

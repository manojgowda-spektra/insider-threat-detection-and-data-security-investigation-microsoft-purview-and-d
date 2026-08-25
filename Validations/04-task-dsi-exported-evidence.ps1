using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$vmName = "labvm-$DID"
$rg = $null
$count = 0
$found = $false
$lastFailure = "DSI/eDiscovery exported evidence artifact was not validated."

$dsiEvidenceScript = @'
$ErrorActionPreference = "Stop"

$slash = [char]92
$root = "C" + [char]58 + $slash
$labRoot = Join-Path -Path $root -ChildPath "LabFiles"
$exportRoot = Join-Path -Path $labRoot -ChildPath "DSIExports"
$indexPath = Join-Path -Path $exportRoot -ChildPath "dsi_case_evidence.json"
$hrCsvPath = Join-Path -Path $labRoot -ChildPath "ZavaHRData.csv"

$expectedCaseName = "Insider Threat Case - Design Engineer"
$expectedDesignFiles = @(
    "AeroFrame-Assembly-RevC.step",
    "ZV-9000-Cooling-Manifold.dwg",
    "Prototype-Test-Matrix.xlsx",
    "Supplier-Costed-BOM-Q4.xlsx",
    "Manufacturing-Tolerances.pdf"
)
$zavaTerms = @(
    "Zava",
    "AeroFrame-Assembly-RevC",
    "ZV-9000-Cooling-Manifold",
    "Prototype-Test-Matrix",
    "Supplier-Costed-BOM-Q4",
    "Manufacturing-Tolerances",
    "BOM",
    "Prototype"
)
$emailRegex = "[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"
$allowedSourceExtensions = @(".csv", ".txt", ".zip", ".json", ".xml", ".html", ".htm", ".log", ".eml")
$readableExtensions = @(".csv", ".txt", ".json", ".xml", ".html", ".htm", ".log", ".eml")

$result = [ordered]@{
    ExportRoot                  = $exportRoot
    EvidenceIndex               = $indexPath
    ExpectedCaseName            = $expectedCaseName
    ExpectedRiskyUpns           = New-Object System.Collections.ArrayList
    CandidateSourceFiles        = New-Object System.Collections.ArrayList
    ReferencedSourceFiles       = New-Object System.Collections.ArrayList
    ValidatedSourceArtifacts    = New-Object System.Collections.ArrayList
    SourceFilesWithReadableText = New-Object System.Collections.ArrayList
    ParseFailures               = New-Object System.Collections.ArrayList
    Failures                    = New-Object System.Collections.ArrayList
    MatchedCaseIdentity         = $false
    MatchedUser                 = $false
    MatchedUserValue            = $null
    MatchedZavaEvidence         = $false
    MatchedZavaValue            = $null
    PositiveResultCount         = $false
    PositiveCountSource         = $null
    Passed                      = $false
}

function Add-Failure {
    param([string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        [void]$result.Failures.Add($Message)
    }
}

function Add-ParseFailure {
    param([string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        [void]$result.ParseFailures.Add($Message)
    }
}

function Add-SourceTextEvidence {
    param(
        [string]$Source,
        [string]$Text
    )
    if ([string]::IsNullOrWhiteSpace($script:combinedSourceText)) {
        $script:combinedSourceText = ""
    }
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $script:combinedSourceText += "`nSOURCE: $Source`n"
    }
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        if ($Text.Length -gt 1048576) {
            $script:combinedSourceText += $Text.Substring(0, 1048576)
        }
        else {
            $script:combinedSourceText += $Text
        }
        $script:combinedSourceText += "`n"
        if (-not $result.SourceFilesWithReadableText.Contains($Source)) {
            [void]$result.SourceFilesWithReadableText.Add($Source)
        }
    }
}

function Get-IndexSourcePathValue {
    param([object]$Reference)

    if ($null -eq $Reference) {
        return $null
    }

    if ($Reference -is [string]) {
        return [string]$Reference
    }

    $propertyNames = @("FullName", "fullName", "Path", "path", "FilePath", "filePath", "Name", "name")
    foreach ($propertyName in $propertyNames) {
        $property = $Reference.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }

    return $null
}

function Resolve-ExportSourcePath {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    $trimmed = $PathValue.Trim().Trim('"')
    if ([System.IO.Path]::IsPathRooted($trimmed)) {
        return [System.IO.Path]::GetFullPath($trimmed)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $exportRoot -ChildPath $trimmed))
}

function Test-PathUnderExportRoot {
    param([string]$CandidatePath)

    if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
        return $false
    }

    $rootFull = [System.IO.Path]::GetFullPath($exportRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath)
    return $candidateFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PositiveJsonEvidence {
    param(
        [object]$Object,
        [string]$Source,
        [int]$Depth = 0
    )

    if ($Depth -gt 20 -or $null -eq $Object) {
        return $false
    }

    if ($Object -is [System.Array]) {
        foreach ($entry in @($Object)) {
            if (Test-PositiveJsonEvidence -Object $entry -Source $Source -Depth ($Depth + 1)) {
                return $true
            }
        }
        return $false
    }

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            $value = $Object[$key]
            if ($key -match "(?i)(count|total|result|item|row|matched|exported)" -and $value -is [ValueType]) {
                try {
                    if ([double]$value -gt 0) {
                        $script:positiveCountSource = "$Source JSON property '$key'=$value"
                        return $true
                    }
                }
                catch { }
            }
            if ($value -is [System.Array] -and $key -match "(?i)^(items|results|rows|records|messages|alerts|evidence)$" -and @($value).Count -gt 0) {
                $script:positiveCountSource = "$Source JSON array '$key' contains $(@($value).Count) item(s)"
                return $true
            }
            if (Test-PositiveJsonEvidence -Object $value -Source $Source -Depth ($Depth + 1)) {
                return $true
            }
        }
        return $false
    }

    $properties = @($Object.PSObject.Properties)
    foreach ($property in $properties) {
        $value = $property.Value
        if ($property.Name -match "(?i)(count|total|result|item|row|matched|exported)" -and $value -is [ValueType]) {
            try {
                if ([double]$value -gt 0) {
                    $script:positiveCountSource = "$Source JSON property '$($property.Name)'=$value"
                    return $true
                }
            }
            catch { }
        }
        if ($value -is [System.Array] -and $property.Name -match "(?i)^(items|results|rows|records|messages|alerts|evidence)$" -and @($value).Count -gt 0) {
            $script:positiveCountSource = "$Source JSON array '$($property.Name)' contains $(@($value).Count) item(s)"
            return $true
        }
        if (Test-PositiveJsonEvidence -Object $value -Source $Source -Depth ($Depth + 1)) {
            return $true
        }
    }
    return $false
}

function Inspect-JsonSourceText {
    param(
        [string]$Source,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Add-ParseFailure "$Source is an empty JSON source export file."
        return
    }

    try {
        $jsonObject = $Text | ConvertFrom-Json -ErrorAction Stop
        Add-SourceTextEvidence -Source $Source -Text $Text
        if (Test-PositiveJsonEvidence -Object $jsonObject -Source $Source) {
            $script:structuredPositiveFromSource = $true
        }
        if (-not $result.ValidatedSourceArtifacts.Contains($Source)) {
            [void]$result.ValidatedSourceArtifacts.Add($Source)
        }
    }
    catch {
        Add-ParseFailure "$Source is malformed JSON and cannot be used as source export proof: $($_.Exception.Message)"
    }
}

function Inspect-CsvSourceText {
    param(
        [string]$Source,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Add-ParseFailure "$Source is an empty CSV source export file."
        return
    }

    $firstLine = (($Text -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($firstLine) -or ($firstLine -notmatch "," -and $firstLine -notmatch "`t")) {
        Add-ParseFailure "$Source does not contain a recognizable CSV header row."
        return
    }

    try {
        $rows = @($Text | ConvertFrom-Csv -ErrorAction Stop)
        if ($rows.Count -eq 0) {
            Add-ParseFailure "$Source parsed as CSV but contains zero data rows."
            return
        }
        Add-SourceTextEvidence -Source $Source -Text $Text
        $script:structuredPositiveFromSource = $true
        $script:positiveCountSource = "$Source contains $($rows.Count) CSV data row(s)"
        if (-not $result.ValidatedSourceArtifacts.Contains($Source)) {
            [void]$result.ValidatedSourceArtifacts.Add($Source)
        }
    }
    catch {
        Add-ParseFailure "$Source is malformed CSV and cannot be used as source export proof: $($_.Exception.Message)"
    }
}

function Inspect-PlainSourceText {
    param(
        [string]$Source,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Add-ParseFailure "$Source is an empty text source export file."
        return
    }
    Add-SourceTextEvidence -Source $Source -Text $Text
    if (-not $result.ValidatedSourceArtifacts.Contains($Source)) {
        [void]$result.ValidatedSourceArtifacts.Add($Source)
    }
}

function Read-ZipTextEntry {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)
    $stream = $null
    $reader = $null
    try {
        $stream = $Entry.Open()
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Inspect-SourceFile {
    param([System.IO.FileInfo]$File)

    if ($null -eq $File) {
        return
    }

    if ($File.Name -ieq "dsi_case_evidence.json") {
        Add-Failure "The normalized index file '$($File.FullName)' was encountered as a source artifact. It is not accepted as primary proof."
        return
    }

    if ($File.Length -le 0) {
        Add-Failure "Referenced source export file '$($File.FullName)' is empty."
        return
    }

    $extension = $File.Extension.ToLowerInvariant()
    try {
        if ($extension -eq ".json") {
            $text = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
            Inspect-JsonSourceText -Source $File.FullName -Text $text
        }
        elseif ($extension -eq ".csv") {
            $text = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
            Inspect-CsvSourceText -Source $File.FullName -Text $text
        }
        elseif ($extension -in @(".txt", ".xml", ".html", ".htm", ".log", ".eml")) {
            $text = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
            Inspect-PlainSourceText -Source $File.FullName -Text $text
        }
        elseif ($extension -eq ".zip") {
            try {
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                $zip = [System.IO.Compression.ZipFile]::OpenRead($File.FullName)
                try {
                    $entries = @($zip.Entries)
                    if ($entries.Count -eq 0) {
                        Add-Failure "Referenced ZIP source export package '$($File.FullName)' contains zero entries."
                    }
                    else {
                        Add-SourceTextEvidence -Source $File.FullName -Text (($entries | ForEach-Object { "$($_.FullName),$($_.Length)" }) -join "`n")
                        if (-not $result.ValidatedSourceArtifacts.Contains($File.FullName)) {
                            [void]$result.ValidatedSourceArtifacts.Add($File.FullName)
                        }
                        foreach ($entry in $entries) {
                            if ($entry.Length -le 0) { continue }
                            if ([System.IO.Path]::GetFileName($entry.FullName) -ieq "dsi_case_evidence.json") { continue }
                            $entryExt = [System.IO.Path]::GetExtension($entry.FullName).ToLowerInvariant()
                            if ($entryExt -in $readableExtensions) {
                                $entryText = Read-ZipTextEntry -Entry $entry
                                $entrySource = "$($File.FullName)!$($entry.FullName)"
                                if ($entryExt -eq ".json") {
                                    Inspect-JsonSourceText -Source $entrySource -Text $entryText
                                }
                                elseif ($entryExt -eq ".csv") {
                                    Inspect-CsvSourceText -Source $entrySource -Text $entryText
                                }
                                else {
                                    Inspect-PlainSourceText -Source $entrySource -Text $entryText
                                }
                            }
                        }
                    }
                }
                finally {
                    if ($null -ne $zip) { $zip.Dispose() }
                }
            }
            catch {
                Add-Failure "Referenced ZIP source export package '$($File.FullName)' could not be opened or inspected: $($_.Exception.Message)"
            }
        }
        else {
            if (-not $result.ValidatedSourceArtifacts.Contains($File.FullName)) {
                [void]$result.ValidatedSourceArtifacts.Add($File.FullName)
            }
        }
    }
    catch {
        Add-Failure "Referenced source export file '$($File.FullName)' could not be read: $($_.Exception.Message)"
    }
}

$script:combinedSourceText = ""
$script:structuredPositiveFromSource = $false
$script:positiveCountSource = $null
$indexObject = $null
$referencedFiles = @()

if (-not (Test-Path -LiteralPath $exportRoot -PathType Container)) {
    Add-Failure "Missing required DSI/eDiscovery export folder '$exportRoot'. Export the Microsoft Purview DSI/eDiscovery evidence package to this exact folder."
}
else {
    if (-not (Test-Path -LiteralPath $hrCsvPath -PathType Leaf)) {
        Add-Failure "Cannot determine the lab admin/risky-user UPN because '$hrCsvPath' is missing."
    }
    else {
        try {
            $hrRaw = Get-Content -LiteralPath $hrCsvPath -Raw -ErrorAction Stop
            $hrRows = @($hrRaw | ConvertFrom-Csv -ErrorAction Stop)
            $candidateRows = @()
            foreach ($row in $hrRows) {
                $rowText = ($row.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join " "
                if ($rowText -match "(?i)(depart|resign|terminat|leav|lastworking)") {
                    $candidateRows += $row
                }
            }
            if ($candidateRows.Count -eq 0 -and $hrRows.Count -gt 0) {
                $candidateRows = @($hrRows[0])
            }
            foreach ($row in $candidateRows) {
                $rowText = ($row.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join " "
                $matches = [regex]::Matches($rowText, $emailRegex)
                foreach ($match in $matches) {
                    $upn = $match.Value.ToLowerInvariant()
                    if (-not $result.ExpectedRiskyUpns.Contains($upn)) {
                        [void]$result.ExpectedRiskyUpns.Add($upn)
                    }
                }
            }
            if ($result.ExpectedRiskyUpns.Count -eq 0) {
                $matches = [regex]::Matches($hrRaw, $emailRegex)
                if ($matches.Count -gt 0) {
                    [void]$result.ExpectedRiskyUpns.Add($matches[0].Value.ToLowerInvariant())
                }
            }
            if ($result.ExpectedRiskyUpns.Count -eq 0) {
                Add-Failure "No UPN could be extracted from '$hrCsvPath'; the DSI/eDiscovery export cannot be tied to the risky lab admin user."
            }
        }
        catch {
            Add-Failure "Failed to parse '$hrCsvPath' while determining the risky lab admin UPN: $($_.Exception.Message)"
        }
    }

    $candidateFiles = @(Get-ChildItem -LiteralPath $exportRoot -Recurse -File -ErrorAction Stop | Where-Object { $_.Name -ine "dsi_case_evidence.json" -and $allowedSourceExtensions -contains $_.Extension.ToLowerInvariant() })
    foreach ($candidate in $candidateFiles) {
        [void]$result.CandidateSourceFiles.Add($candidate.FullName)
    }
    if ($candidateFiles.Count -eq 0) {
        Add-Failure "No non-index DSI/eDiscovery source export files were found under '$exportRoot'. A fabricated 'dsi_case_evidence.json' file alone is not accepted; download or extract a non-empty CSV, TXT, ZIP, JSON, XML, HTML, LOG, or EML export artifact from Microsoft Purview."
    }

    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        Add-Failure "Missing normalized correlation index '$indexPath'. Create it from the real portal export after downloading the DSI/eDiscovery source artifacts."
    }
    else {
        try {
            $indexFile = Get-Item -LiteralPath $indexPath -ErrorAction Stop
            if ($indexFile.Length -le 0) {
                Add-Failure "Normalized correlation index '$indexPath' is empty."
            }
            else {
                $indexRaw = Get-Content -LiteralPath $indexPath -Raw -ErrorAction Stop
                $indexObject = $indexRaw | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $indexObject) {
                    Add-Failure "Normalized correlation index '$indexPath' parsed to a null object."
                }
            }
        }
        catch {
            Add-Failure "Normalized correlation index '$indexPath' is not valid JSON: $($_.Exception.Message)"
        }
    }

    if ($null -ne $indexObject) {
        $sourceExportProperty = $indexObject.PSObject.Properties["sourceExportFiles"]
        if ($null -eq $sourceExportProperty -or $null -eq $sourceExportProperty.Value -or @($sourceExportProperty.Value).Count -eq 0) {
            Add-Failure "Normalized correlation index '$indexPath' does not include a non-empty 'sourceExportFiles' array. The index must reference the real portal export files it normalized."
        }
        else {
            $seenPaths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($reference in @($sourceExportProperty.Value)) {
                $pathValue = Get-IndexSourcePathValue -Reference $reference
                $resolvedPath = Resolve-ExportSourcePath -PathValue $pathValue
                if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
                    Add-Failure "A sourceExportFiles entry in '$indexPath' does not contain a usable path or FullName value."
                    continue
                }
                if (-not (Test-PathUnderExportRoot -CandidatePath $resolvedPath)) {
                    Add-Failure "sourceExportFiles entry '$pathValue' resolves outside '$exportRoot'. Source evidence must be stored under the lab export folder."
                    continue
                }
                if ([System.IO.Path]::GetFileName($resolvedPath) -ieq "dsi_case_evidence.json") {
                    Add-Failure "sourceExportFiles in '$indexPath' references 'dsi_case_evidence.json'. The normalized JSON is only an index/correlation file and cannot be listed as primary source proof."
                    continue
                }
                if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
                    Add-Failure "sourceExportFiles entry '$pathValue' references '$resolvedPath', but that source export file does not exist."
                    continue
                }

                $fileInfo = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
                if ($fileInfo.Length -le 0) {
                    Add-Failure "sourceExportFiles entry '$pathValue' references '$resolvedPath', but that source export file is empty."
                    continue
                }
                if ($seenPaths.Add($fileInfo.FullName)) {
                    [void]$result.ReferencedSourceFiles.Add($fileInfo.FullName)
                    $referencedFiles += $fileInfo
                }
            }
        }
    }

    if ($referencedFiles.Count -eq 0) {
        Add-Failure "No non-empty source export artifact referenced by 'dsi_case_evidence.json.sourceExportFiles' could be validated. A hand-created JSON index alone cannot pass this check."
    }
    else {
        foreach ($sourceFile in $referencedFiles) {
            Inspect-SourceFile -File $sourceFile
        }
    }
}

$sourceText = $script:combinedSourceText
if ($result.ParseFailures.Count -gt 0 -and $result.SourceFilesWithReadableText.Count -eq 0) {
    foreach ($parseFailure in @($result.ParseFailures)) {
        Add-Failure $parseFailure
    }
}

if ([string]::IsNullOrWhiteSpace($sourceText)) {
    Add-Failure "The referenced source export artifacts did not contain readable text or report data that can corroborate the normalized index. Extract the Purview ZIP package or include CSV/TXT/report files under '$exportRoot'."
}
else {
    if ($sourceText -match [regex]::Escape($expectedCaseName) -or
        $sourceText -match "(?i)\b(Insider Threat Case|Design Engineer)\b" -or
        $sourceText -match "(?is)\b(case|search|query|export|process)\b.{0,140}\b(Zava|Insider|Design)\b" -or
        $sourceText -match "(?is)\b(Zava|Insider|Design)\b.{0,140}\b(case|search|query|export|process)\b") {
        $result.MatchedCaseIdentity = $true
    }
    else {
        Add-Failure "The referenced source export artifacts do not identify case '$expectedCaseName' or a corresponding Zava/Insider search, export, or process name. The normalized JSON index is not used as primary proof for this requirement."
    }

    foreach ($upn in @($result.ExpectedRiskyUpns)) {
        if (-not [string]::IsNullOrWhiteSpace($upn) -and $sourceText.ToLowerInvariant().Contains($upn.ToLowerInvariant())) {
            $result.MatchedUser = $true
            $result.MatchedUserValue = $upn
            break
        }
    }
    if (-not $result.MatchedUser) {
        $expectedUserText = @($result.ExpectedRiskyUpns) -join ", "
        if ([string]::IsNullOrWhiteSpace($expectedUserText)) { $expectedUserText = "<no risky UPN discovered from ZavaHRData.csv>" }
        Add-Failure "The referenced source export artifacts do not identify the lab admin/risky-user UPN as custodian, searched user, sender, or participant. Expected one of: $expectedUserText. The normalized JSON index is not used as primary proof for this requirement."
    }

    foreach ($designFile in $expectedDesignFiles) {
        if ($sourceText -match [regex]::Escape($designFile)) {
            $result.MatchedZavaEvidence = $true
            $result.MatchedZavaValue = $designFile
            break
        }
    }
    if (-not $result.MatchedZavaEvidence) {
        foreach ($term in $zavaTerms) {
            if ($sourceText -match [regex]::Escape($term)) {
                $result.MatchedZavaEvidence = $true
                $result.MatchedZavaValue = $term
                break
            }
        }
    }
    if (-not $result.MatchedZavaEvidence -and $sourceText -match "(?is)\b(outbound|sent|sender|recipient|message|email)\b.{0,220}\b(attachment|attached|AeroFrame|Cooling-Manifold|Prototype-Test-Matrix|Supplier-Costed-BOM|Manufacturing-Tolerances|Zava)\b") {
        $result.MatchedZavaEvidence = $true
        $result.MatchedZavaValue = "outbound message/attachment evidence"
    }
    if (-not $result.MatchedZavaEvidence) {
        Add-Failure "The referenced source export artifacts do not contain an expected staged Zava design file name or outbound message evidence containing a staged design file. The normalized JSON index is not used as primary proof for this requirement."
    }

    $countMatch = [regex]::Match($sourceText, "(?is)\b(result\s*count|item\s*count|total\s*(items|results)|exported\s*(items|results)|rows?|matches|total)\b\D{0,50}([1-9]\d*)\b")
    if ($script:structuredPositiveFromSource) {
        $result.PositiveResultCount = $true
        $result.PositiveCountSource = $script:positiveCountSource
    }
    elseif ($countMatch.Success) {
        $result.PositiveResultCount = $true
        $result.PositiveCountSource = $countMatch.Value.Trim()
    }
    else {
        Add-Failure "The referenced source export artifacts do not show a positive/nonzero result count, exported item count, or non-empty result rows. The resultCountOrExportedItems value in the normalized JSON index is not accepted as primary proof."
    }
}

$result.Passed = ($result.Failures.Count -eq 0 -and $result.ReferencedSourceFiles.Count -gt 0 -and $result.ValidatedSourceArtifacts.Count -gt 0 -and $result.SourceFilesWithReadableText.Count -gt 0 -and $result.MatchedCaseIdentity -and $result.MatchedUser -and $result.MatchedZavaEvidence -and $result.PositiveResultCount)

Write-Output "CL_VALIDATION_JSON_START"
Write-Output ($result | ConvertTo-Json -Depth 10 -Compress)
Write-Output "CL_VALIDATION_JSON_END"
'@

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
            $lastFailure = "Multiple VMs named '$vmName' were found in subscription '$sub' (resource groups: $candidateGroups); cannot validate deterministically."
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
                $runResult = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vmName -CommandId "RunPowerShellScript" -ScriptString $dsiEvidenceScript -ErrorAction Stop
                if ($null -eq $runResult -or $null -eq $runResult.Value -or $runResult.Value.Count -eq 0) {
                    throw "Invoke-AzVMRunCommand returned no output while checking DSI/eDiscovery exported evidence on '$vmName'."
                }

                $runOutput = (@($runResult.Value | ForEach-Object { $_.Message }) -join "`n")
                if ([string]::IsNullOrWhiteSpace($runOutput)) {
                    throw "Invoke-AzVMRunCommand output was empty while checking DSI/eDiscovery exported evidence on '$vmName'."
                }

                $jsonMatch = [regex]::Match($runOutput, "(?s)CL_VALIDATION_JSON_START\s*(\{.*\})\s*CL_VALIDATION_JSON_END")
                if (-not $jsonMatch.Success -or [string]::IsNullOrWhiteSpace($jsonMatch.Groups[1].Value)) {
                    throw "Could not parse DSI/eDiscovery exported evidence validation JSON from VM run-command output. Raw output: $runOutput"
                }

                $dsiState = $jsonMatch.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $dsiState) {
                    throw "DSI/eDiscovery exported evidence validation JSON parsed to a null object."
                }

                if ($dsiState.Passed -eq $true) {
                    $found = $true
                    $referencedFiles = @($dsiState.ReferencedSourceFiles) -join "; "
                    $validatedArtifacts = @($dsiState.ValidatedSourceArtifacts) -join "; "
                    $matchedUser = $dsiState.MatchedUserValue
                    $matchedEvidence = $dsiState.MatchedZavaValue
                    $countSource = $dsiState.PositiveCountSource
                    $message = @{
                        Status  = "Succeeded"
                        Message = "DSI/eDiscovery evidence under '$($dsiState.ExportRoot)' on VM '$vmName' in RG '$rg' is backed by non-empty source export artifacts referenced by dsi_case_evidence.json. Referenced source files: $referencedFiles. Validated source artifacts: $validatedArtifacts. The source artifacts identify the case/search, risky user '$matchedUser', Zava evidence '$matchedEvidence', and positive result evidence '$countSource'."
                    } | ConvertTo-Json
                }
                else {
                    $failureDetails = @($dsiState.Failures) -join " "
                    if ([string]::IsNullOrWhiteSpace($failureDetails)) {
                        $failureDetails = "The VM-side DSI/eDiscovery exported evidence validation did not pass but did not return detailed failures."
                    }
                    $lastFailure = $failureDetails
                    $message = @{
                        Status  = "Failed"
                        Message = "DSI/eDiscovery exported evidence validation failed for VM '$vmName' in RG '$rg'. $lastFailure"
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
        $lastFailure = "Error during DSI/eDiscovery exported evidence check. Attempt $count of 3. Error: $($_.Exception.Message)"
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
        Message = "DSI/eDiscovery exported evidence artifact was not validated for VM '$vmName' in RG '$rg' after 3 attempts. Last failure: $lastFailure"
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}

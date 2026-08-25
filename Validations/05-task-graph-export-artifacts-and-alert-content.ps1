using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
# Validation 5 validates the files produced by the delivered get_insider_alerts.py script on the VM.
# The delivered Python script is the source of truth for the JSON schema: labScopedMdeAlerts,
# labScopedMdeAlertSummaries, exercise3HuntingNotes, dsiCaseEvidenceParsed, and dsiExportInventory.
# Microsoft Graph /security/alerts_v2 is checked with documented application permission behavior and
# documented OData support for createdDateTime filtering plus $top sizing.

$vmName = "labvm-$DID"
$rg = $null
$count = 0
$found = $false
$lastFailure = "Graph export validation did not run."

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop | Out-Null
        $vm = Get-AzVM -Status -ErrorAction Stop | Where-Object { $_.Name -eq $vmName } | Select-Object -First 1
        if (-not $vm) {
            $lastFailure = "VM '$vmName' was not found in subscription '$sub'."
            $message = @{ Status = "Failed"; Message = "$lastFailure Attempt $count of 3." } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
            Start-Sleep -Seconds 10
            continue
        }

        $rg = $vm.ResourceGroupName

        $remoteTemplate = @'
$ErrorActionPreference = "Stop"
$expectedVmName = '__EXPECTED_VM_NAME__'
$recentCutoffUtc = (Get-Date).ToUniversalTime().AddHours(-72)
$graphCutoffText = $recentCutoffUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')

function Emit-Result {
    param([string]$Status, [string]$Message, [hashtable]$Details = @{})
    Write-Output 'CL_VALIDATION_RESULT_START'
    Write-Output (@{ Status = $Status; Message = $Message; Details = $Details } | ConvertTo-Json -Depth 80 -Compress)
    Write-Output 'CL_VALIDATION_RESULT_END'
}

function Get-JsonPropertyValue {
    param([object]$Object, [string[]]$Names)
    if ($null -eq $Object) { return $null }
    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) { return [string]$prop.Value }
    }
    return $null
}

function Get-ConfigValue {
    param([object]$Config, [string[]]$Names)
    $roots = New-Object System.Collections.Generic.List[object]
    $roots.Add($Config) | Out-Null
    foreach ($containerName in @('AzureAd','azureAd','AzureAD','graph','Graph','microsoftGraph','MicrosoftGraph')) {
        $container = $Config.PSObject.Properties[$containerName]
        if ($null -ne $container -and $null -ne $container.Value) { $roots.Add($container.Value) | Out-Null }
    }
    foreach ($root in $roots) {
        $value = Get-JsonPropertyValue -Object $root -Names $Names
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $null
}

function Get-ArrayProperty {
    param([object]$Object, [string[]]$Names)
    if ($null -eq $Object) { return @() }
    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value) { return @($prop.Value | Where-Object { $null -ne $_ }) }
    }
    return @()
}

function Test-HasProperty {
    param([object]$Object, [string]$Name)
    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

function Test-MdeSourceValue {
    param([string]$Source)
    if ([string]::IsNullOrWhiteSpace($Source)) { return $false }
    $normalized = $Source.ToLowerInvariant() -replace '[^a-z0-9]', ''
    return ($normalized -eq 'microsoftdefenderforendpoint' -or $normalized -eq 'microsoftdefenderatp' -or $normalized -eq 'windowsdefenderatp' -or $normalized -eq 'microsoftdefenderadvancedthreatprotection')
}

function Get-AlertSourceValues {
    param([object]$Alert)
    $values = New-Object System.Collections.Generic.List[string]
    foreach ($field in @('serviceSource','detectionSource','productName','source')) {
        $prop = $Alert.PSObject.Properties[$field]
        if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) { $values.Add([string]$prop.Value) | Out-Null }
    }
    return @($values)
}

function Test-RecentAlert {
    param([object]$Alert, [datetime]$CutoffUtc)
    foreach ($field in @('createdDateTime','lastUpdateDateTime','alertCreationTime')) {
        $prop = $Alert.PSObject.Properties[$field]
        if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            try { return (([datetime]::Parse([string]$prop.Value)).ToUniversalTime() -ge $CutoffUtc) } catch { return $false }
        }
    }
    return $false
}

function Test-LabAlertIndicator {
    param([object]$Alert, [string]$ExpectedVmName)
    $text = ($Alert | ConvertTo-Json -Depth 80 -Compress)
    if ($text -match [regex]::Escape($ExpectedVmName)) { return $true }
    if ($text -match '(?i)eicar|eicar\.txt|standard-antivirus-test-file|antivirus test|test file|test-file|labfiles.*eicartest|zavaeicar') { return $true }
    return $false
}

function Get-AlertIdValues {
    param([object[]]$Alerts, [object[]]$Summaries)
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Alerts + $Summaries)) {
        if ($null -eq $item) { continue }
        foreach ($idField in @('id','providerAlertId')) {
            $prop = $item.PSObject.Properties[$idField]
            if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) { $ids.Add([string]$prop.Value) | Out-Null }
        }
    }
    return @($ids | Select-Object -Unique)
}

function Test-ReportHasAnyValue {
    param([string]$ReportText, [string[]]$Values)
    foreach ($value in $Values) {
        if (-not [string]::IsNullOrWhiteSpace($value) -and $ReportText.IndexOf($value, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

try {
    $drivePrefix = 'C' + [char]58
    $labFolder = Join-Path -Path $drivePrefix -ChildPath 'LabFiles'
    $configPath = Join-Path -Path $labFolder -ChildPath 'config.json'
    $exportPath = Join-Path -Path $labFolder -ChildPath 'insider_risk_case.json'
    $reportPath = Join-Path -Path $labFolder -ChildPath 'insider_risk_case_report.txt'

    foreach ($path in @($configPath,$exportPath,$reportPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Emit-Result -Status 'Failed' -Message "Required file '$path' was not found on the lab VM." -Details @{ MissingPath = $path }; return }
    }

    try { $config = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { Emit-Result -Status 'Failed' -Message "The Graph configuration file exists but is unreadable or invalid JSON: $($_.Exception.Message)" -Details @{ Path = $configPath }; return }

    $tenantId = Get-ConfigValue -Config $config -Names @('tenant_id','tenantId','TenantId','tenant','directoryTenantId')
    $clientId = Get-ConfigValue -Config $config -Names @('client_id','clientId','ClientId','appId','applicationId')
    $clientSecret = Get-ConfigValue -Config $config -Names @('client_secret','clientSecret','ClientSecret','secret','client_secret_value')
    if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret)) { Emit-Result -Status 'Failed' -Message 'The Graph configuration file must contain non-empty tenant_id, client_id, and client_secret values, or their camelCase aliases.' -Details @{}; return }
    if ($tenantId -notmatch '^[0-9a-fA-F-]{36}$' -or $clientId -notmatch '^[0-9a-fA-F-]{36}$') { Emit-Result -Status 'Failed' -Message 'The tenant ID and client ID in config.json must be GUID-shaped values.' -Details @{ TenantId = $tenantId; ClientId = $clientId }; return }

    $tokenBody = @{ client_id = $clientId; scope = 'https://graph.microsoft.com/.default'; client_secret = $clientSecret; grant_type = 'client_credentials' }
    try { $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -Headers @{ Accept = 'application/json'; 'User-Agent' = 'CloudLabs-Zava-GraphExport-Validation/1.1' } -ErrorAction Stop }
    catch { Emit-Result -Status 'Failed' -Message "Microsoft Graph token acquisition failed for the app in config.json. Run the delivered Python script with --smoke-test or repair config.json using the manual fallback. Error: $($_.Exception.Message)" -Details @{ TenantId = $tenantId; ClientId = $clientId }; return }
    if ([string]::IsNullOrWhiteSpace([string]$tokenResponse.access_token)) { Emit-Result -Status 'Failed' -Message 'Microsoft Graph token acquisition returned no access_token.' -Details @{ TenantId = $tenantId; ClientId = $clientId }; return }

    $graphHeaders = @{ Authorization = "Bearer $($tokenResponse.access_token)"; Accept = 'application/json'; 'User-Agent' = 'CloudLabs-Zava-GraphExport-Validation/1.1' }
    $encodedFilter = [System.Uri]::EscapeDataString("createdDateTime ge $graphCutoffText")
    $alertsUri = 'https://graph.microsoft.com/v1.0/security/alerts_v2?$filter=' + $encodedFilter + '&$top=1'
    try { $graphResponse = Invoke-RestMethod -Method Get -Uri $alertsUri -Headers $graphHeaders -ErrorAction Stop }
    catch { Emit-Result -Status 'Failed' -Message "Microsoft Graph /security/alerts_v2 call failed with the documented createdDateTime filter and `$top parameter: $($_.Exception.Message)" -Details @{ TenantId = $tenantId; ClientId = $clientId; Uri = $alertsUri }; return }
    if ($null -eq $graphResponse -or $null -eq $graphResponse.PSObject.Properties['value']) { Emit-Result -Status 'Failed' -Message 'Microsoft Graph security alerts API did not return the expected collection response with a value property.' -Details @{ Uri = $alertsUri }; return }

    try {
        $exportRaw = Get-Content -LiteralPath $exportPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($exportRaw)) { throw 'Export file is empty.' }
        $exportParsed = $exportRaw | ConvertFrom-Json -ErrorAction Stop
    }
    catch { Emit-Result -Status 'Failed' -Message "The JSON alert export is unreadable, empty, or invalid JSON: $($_.Exception.Message)" -Details @{ Path = $exportPath }; return }

    foreach ($requiredField in @('generatedUtc','cutoffUtc','labVmName','labScopedMdeAlertCount','labScopedMdeAlertSummaries','labScopedMdeAlerts','exercise3HuntingNotes','dsiCaseEvidenceParsed','dsiExportInventory')) {
        if (-not (Test-HasProperty -Object $exportParsed -Name $requiredField)) {
            Emit-Result -Status 'Failed' -Message "The JSON alert export is not in the schema produced by the delivered get_insider_alerts.py script. Missing top-level field '$requiredField'." -Details @{ Path = $exportPath; MissingField = $requiredField }
            return
        }
    }

    $exportVmName = Get-JsonPropertyValue -Object $exportParsed -Names @('labVmName','vmName')
    if ([string]::IsNullOrWhiteSpace($exportVmName) -or $exportVmName -ne $expectedVmName) {
        Emit-Result -Status 'Failed' -Message "The JSON export must be produced with --vm-name $expectedVmName so labVmName matches the deployed VM." -Details @{ Path = $exportPath; ExpectedVmName = $expectedVmName; ObservedVmName = $exportVmName }
        return
    }

    $labScopedAlerts = @(Get-ArrayProperty -Object $exportParsed -Names @('labScopedMdeAlerts'))
    $labScopedSummaries = @(Get-ArrayProperty -Object $exportParsed -Names @('labScopedMdeAlertSummaries'))
    $declaredLabScopedCount = 0
    try { $declaredLabScopedCount = [int]$exportParsed.labScopedMdeAlertCount } catch { $declaredLabScopedCount = -1 }

    if ($declaredLabScopedCount -lt 1 -or $labScopedAlerts.Count -lt 1 -or $labScopedSummaries.Count -lt 1) {
        Emit-Result -Status 'Failed' -Message "The delivered script output must include at least one lab-scoped MDE alert in labScopedMdeAlerts and labScopedMdeAlertSummaries. Re-run get_insider_alerts.py without --smoke-test after MDE alert ingestion." -Details @{ Path = $exportPath; DeclaredLabScopedMdeAlertCount = $declaredLabScopedCount; LabScopedMdeAlerts = $labScopedAlerts.Count; LabScopedMdeAlertSummaries = $labScopedSummaries.Count }
        return
    }

    $qualifiedAlerts = New-Object System.Collections.Generic.List[object]
    $sourceValues = New-Object System.Collections.Generic.List[string]
    foreach ($alert in $labScopedAlerts) {
        $sources = @(Get-AlertSourceValues -Alert $alert)
        $isMde = $false
        foreach ($source in $sources) { if (Test-MdeSourceValue -Source $source) { $isMde = $true; $sourceValues.Add($source) | Out-Null } }
        if ($isMde -and (Test-RecentAlert -Alert $alert -CutoffUtc $recentCutoffUtc) -and (Test-LabAlertIndicator -Alert $alert -ExpectedVmName $expectedVmName)) { $qualifiedAlerts.Add($alert) | Out-Null }
    }

    if ($qualifiedAlerts.Count -lt 1) {
        Emit-Result -Status 'Failed' -Message "The labScopedMdeAlerts array exists, but none of its entries are recent Microsoft Defender for Endpoint alerts linked to '$expectedVmName' or EICAR/test-file evidence." -Details @{ Path = $exportPath; RecentCutoffUtc = $recentCutoffUtc.ToString('o'); ExpectedVmName = $expectedVmName; ObservedSourceValues = @($sourceValues); LabScopedMdeAlerts = $labScopedAlerts.Count }
        return
    }

    $alertIds = @(Get-AlertIdValues -Alerts @($qualifiedAlerts) -Summaries $labScopedSummaries)
    if ($alertIds.Count -lt 1) { Emit-Result -Status 'Failed' -Message 'The qualifying Microsoft Defender for Endpoint alert must include id or providerAlertId in labScopedMdeAlerts or labScopedMdeAlertSummaries.' -Details @{ Path = $exportPath; QualifiedAlertCount = $qualifiedAlerts.Count }; return }

    $exercise3 = $exportParsed.exercise3HuntingNotes
    if ($null -eq $exercise3 -or $exercise3.exists -ne $true -or [int]($exercise3.length) -lt 20 -or [string]::IsNullOrWhiteSpace([string]$exercise3.content)) {
        Emit-Result -Status 'Failed' -Message 'The JSON export must include non-empty exercise3HuntingNotes as produced by the delivered script from the Exercise 3 hunting notes file.' -Details @{ Path = $exportPath; Exercise3Exists = $exercise3.exists; Exercise3Length = $exercise3.length }
        return
    }

    $dsiCase = $exportParsed.dsiCaseEvidenceParsed
    $dsiInventory = $exportParsed.dsiExportInventory
    if ($null -eq $dsiCase -or $dsiCase.exists -ne $true -or $null -eq $dsiCase.parsed) {
        Emit-Result -Status 'Failed' -Message 'The JSON export must include dsiCaseEvidenceParsed with exists=true and parsed normalized DSI/eDiscovery evidence from the DSIExports evidence JSON file.' -Details @{ Path = $exportPath; DsiCasePath = $dsiCase.path; DsiCaseExists = $dsiCase.exists }
        return
    }
    if ($null -eq $dsiInventory -or $dsiInventory.exists -ne $true -or [int]($dsiInventory.fileCount) -lt 1) {
        Emit-Result -Status 'Failed' -Message 'The JSON export must include dsiExportInventory with at least one real DSI/eDiscovery export file inventoried under the lab DSIExports folder.' -Details @{ Path = $exportPath; DsiRoot = $dsiInventory.root; DsiExists = $dsiInventory.exists; DsiFileCount = $dsiInventory.fileCount }
        return
    }

    try { $reportRaw = Get-Content -LiteralPath $reportPath -Raw -ErrorAction Stop }
    catch { Emit-Result -Status 'Failed' -Message "The text case report is unreadable: $($_.Exception.Message)" -Details @{ Path = $reportPath }; return }
    if ([string]::IsNullOrWhiteSpace($reportRaw)) { Emit-Result -Status 'Failed' -Message 'The text case report exists but is empty.' -Details @{ Path = $reportPath }; return }

    if ($reportRaw.IndexOf($expectedVmName, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { Emit-Result -Status 'Failed' -Message "The text report must include the lab VM name '$expectedVmName' written by get_insider_alerts.py." -Details @{ Path = $reportPath }; return }
    if (-not (Test-ReportHasAnyValue -ReportText $reportRaw -Values $alertIds)) { Emit-Result -Status 'Failed' -Message 'The text report must include an actual id or providerAlertId from the qualifying labScopedMdeAlerts/labScopedMdeAlertSummaries export.' -Details @{ Path = $reportPath; CheckedIdentifierCount = $alertIds.Count }; return }
    foreach ($reportSection in @('Exercise 3 hunting notes','DSI/eDiscovery normalized case evidence','DSI/eDiscovery export inventory','Matched alerts')) {
        if ($reportRaw.IndexOf($reportSection, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            Emit-Result -Status 'Failed' -Message "The text report does not contain the '$reportSection' section written by the delivered get_insider_alerts.py script." -Details @{ Path = $reportPath; MissingSection = $reportSection }
            return
        }
    }

    Emit-Result -Status 'Succeeded' -Message "Validated config.json, app-only Microsoft Graph access to /security/alerts_v2, get_insider_alerts.py output schema, $($qualifiedAlerts.Count) recent lab-scoped Microsoft Defender for Endpoint alert(s), Exercise 3 notes, DSI/eDiscovery export inventory, and report content for VM '$expectedVmName'." -Details @{ QualifiedMdeLabAlertCount = $qualifiedAlerts.Count; DeclaredLabScopedMdeAlertCount = $declaredLabScopedCount; LabScopedMdeAlertSummaries = $labScopedSummaries.Count; DsiFileCount = $dsiInventory.fileCount; RecentCutoffUtc = $recentCutoffUtc.ToString('o') }
}
catch { Emit-Result -Status 'Failed' -Message "Unexpected error while validating Graph export files on the VM: $($_.Exception.Message)" -Details @{ ExceptionType = $_.Exception.GetType().FullName } }
'@
        $remoteScript = $remoteTemplate.Replace('__EXPECTED_VM_NAME__', $vmName)
        $runCommand = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $remoteScript -ErrorAction Stop
        $runOutput = ($runCommand.Value | ForEach-Object { $_.Message }) -join "`n"
        $resultMatch = [System.Text.RegularExpressions.Regex]::Match($runOutput, 'CL_VALIDATION_RESULT_START\s*(\{.*?\})\s*CL_VALIDATION_RESULT_END', [System.Text.RegularExpressions.RegexOptions]::Singleline)

        if (-not $resultMatch.Success) {
            $lastFailure = "Run command completed on VM '$vmName' in RG '$rg', but did not return a structured validation result. Output: $runOutput"
            $message = @{ Status = "Failed"; Message = "$lastFailure Attempt $count of 3." } | ConvertTo-Json
        }
        else {
            $remoteResult = $resultMatch.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
            if ($remoteResult.Status -eq 'Succeeded') {
                $found = $true
                $message = @{ Status = "Succeeded"; Message = $remoteResult.Message } | ConvertTo-Json
            }
            else {
                $lastFailure = $remoteResult.Message
                $message = @{ Status = "Failed"; Message = "$($remoteResult.Message) Attempt $count of 3." } | ConvertTo-Json
            }
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
        if (-not $found) { Start-Sleep -Seconds 10 }
    }
    catch {
        $lastFailure = "Error during Graph export validation. Attempt $count of 3. Error: $($_.Exception.Message)"
        $message = @{ Status = "Failed"; Message = $lastFailure } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
        Start-Sleep -Seconds 10
    }
} while ($count -lt 3 -and -not $found)

if (-not $found) {
    if ([string]::IsNullOrWhiteSpace($rg)) { $rg = "the subscription containing VM '$vmName'" }
    $message = @{ Status = "Failed"; Message = "Graph export artifacts and alert content validation failed for VM '$vmName' in RG '$rg' after 3 attempts. Last failure: $lastFailure" } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
}

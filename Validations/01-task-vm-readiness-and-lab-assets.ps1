using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$vmName = "labvm-$DID"
$rg = $null
$count = 0
$found = $false
$lastFailure = "VM readiness, Custom Script Extension status, local lab assets, and Python readiness were not validated."

$assetCheckScript = @'
$ErrorActionPreference = "Stop"

$slash = [char]92
$root = "C" + [char]58 + $slash
$labRoot = Join-Path -Path $root -ChildPath "LabFiles"
$designRoot = Join-Path -Path $labRoot -ChildPath "ZavaDesignFiles"
$dsiExportRoot = Join-Path -Path $labRoot -ChildPath "DSIExports"
$hrCsvPath = Join-Path -Path $labRoot -ChildPath "ZavaHRData.csv"
$graphStarterPath = Join-Path -Path $labRoot -ChildPath "get_insider_alerts.py"

$expectedDesignFiles = @(
    "AeroFrame-Assembly-RevC.step",
    "ZV-9000-Cooling-Manifold.dwg",
    "Prototype-Test-Matrix.xlsx",
    "Supplier-Costed-BOM-Q4.xlsx",
    "Manufacturing-Tolerances.pdf"
)

$expectedPaths = @(
    @{ Name = "LabFiles folder"; Path = $labRoot; Type = "Container" },
    @{ Name = "Zava design files folder"; Path = $designRoot; Type = "Container" },
    @{ Name = "DSI exports folder"; Path = $dsiExportRoot; Type = "Container" },
    @{ Name = "Zava HR data CSV"; Path = $hrCsvPath; Type = "Leaf" },
    @{ Name = "Graph starter script"; Path = $graphStarterPath; Type = "Leaf" },
    @{ Name = "Preparation helper"; Path = (Join-Path -Path $labRoot -ChildPath "Prepare-ZavaLab.ps1"); Type = "Leaf" },
    @{ Name = "EICAR helper"; Path = (Join-Path -Path $labRoot -ChildPath "Invoke-ZavaEicarTest.ps1"); Type = "Leaf" }
)

$result = [ordered]@{
    ComputerName       = $env:COMPUTERNAME
    Checks             = [ordered]@{}
    Missing            = New-Object System.Collections.ArrayList
    DesignFiles        = New-Object System.Collections.ArrayList
    HrCsv              = [ordered]@{ Present = $false; RowCount = 0; HasDepartingIndicator = $false; HasIso8601Date = $false; Error = $null }
    StarterScript      = [ordered]@{ Present = $false; HasAlertsEndpoint = $false; HasMsalReference = $false; HasRequestsReference = $false; Error = $null }
    Python             = [ordered]@{ PythonAvailable = $false; Version = $null; RequestsImport = $false; MsalImport = $false; Error = $null }
    Ready              = $false
}

foreach ($item in $expectedPaths) {
    $pathFound = Test-Path -LiteralPath $item.Path -PathType $item.Type
    $result.Checks[$item.Name] = $pathFound
    if (-not $pathFound) { [void]$result.Missing.Add($item.Name) }
}

foreach ($fileName in $expectedDesignFiles) {
    $filePath = Join-Path -Path $designRoot -ChildPath $fileName
    if (Test-Path -LiteralPath $filePath -PathType Leaf) { [void]$result.DesignFiles.Add($fileName) }
    else { [void]$result.Missing.Add("Design file: $fileName") }
}

try {
    if (Test-Path -LiteralPath $hrCsvPath -PathType Leaf) {
        $result.HrCsv.Present = $true
        $hrRows = @(Import-Csv -LiteralPath $hrCsvPath -ErrorAction Stop)
        $result.HrCsv.RowCount = $hrRows.Count
        if ($hrRows.Count -lt 3) { [void]$result.Missing.Add("Zava HR data CSV with at least three rows") }
        $hrText = Get-Content -LiteralPath $hrCsvPath -Raw -ErrorAction Stop
        $result.HrCsv.HasDepartingIndicator = ($hrText -match '(?i)depart')
        $result.HrCsv.HasIso8601Date = ($hrText -match '\d{4}-\d{2}-\d{2}')
        if (-not $result.HrCsv.HasDepartingIndicator) { [void]$result.Missing.Add("departing employee indicator in Zava HR data CSV") }
        if (-not $result.HrCsv.HasIso8601Date) { [void]$result.Missing.Add("ISO 8601-style dates in Zava HR data CSV") }
    }
}
catch {
    $result.HrCsv.Error = $_.Exception.Message
    [void]$result.Missing.Add("readable parseable Zava HR data CSV")
}

try {
    if (Test-Path -LiteralPath $graphStarterPath -PathType Leaf) {
        $result.StarterScript.Present = $true
        $starterText = Get-Content -LiteralPath $graphStarterPath -Raw -ErrorAction Stop
        $result.StarterScript.HasAlertsEndpoint = ($starterText -match '/security/alerts_v2')
        $result.StarterScript.HasMsalReference = ($starterText -match '(?i)msal')
        $result.StarterScript.HasRequestsReference = ($starterText -match '(?i)requests')
        if (-not $result.StarterScript.HasAlertsEndpoint) { [void]$result.Missing.Add("/security/alerts_v2 reference in Graph starter script") }
        if (-not $result.StarterScript.HasMsalReference) { [void]$result.Missing.Add("MSAL reference in Graph starter script") }
        if (-not $result.StarterScript.HasRequestsReference) { [void]$result.Missing.Add("requests reference in Graph starter script") }
    }
}
catch {
    $result.StarterScript.Error = $_.Exception.Message
    [void]$result.Missing.Add("readable Graph starter script")
}

try {
    $pythonExecutable = $null
    $pythonArguments = @()
    $pyCommand = Get-Command -Name "py" -ErrorAction SilentlyContinue
    if ($null -ne $pyCommand) {
        $versionProbe = & py -3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')" 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($versionProbe | Select-Object -First 1))) {
            $pythonExecutable = "py"
            $pythonArguments = @("-3")
            $result.Python.Version = ($versionProbe | Select-Object -First 1).ToString().Trim()
        }
    }
    if ([string]::IsNullOrWhiteSpace($pythonExecutable)) {
        $pythonCommand = Get-Command -Name "python" -ErrorAction SilentlyContinue
        if ($null -ne $pythonCommand) {
            $versionProbe = & python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')" 2>&1
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($versionProbe | Select-Object -First 1))) {
                $pythonExecutable = "python"
                $pythonArguments = @()
                $result.Python.Version = ($versionProbe | Select-Object -First 1).ToString().Trim()
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($pythonExecutable)) {
        $version = [version]$result.Python.Version
        $result.Python.PythonAvailable = ($version -ge [version]"3.10.0")
        $requestsProbe = & $pythonExecutable @pythonArguments -c "import requests; print('requests-ok')" 2>&1
        $result.Python.RequestsImport = ($LASTEXITCODE -eq 0 -and (($requestsProbe -join "`n") -match "requests-ok"))
        $msalProbe = & $pythonExecutable @pythonArguments -c "import msal; print('msal-ok')" 2>&1
        $result.Python.MsalImport = ($LASTEXITCODE -eq 0 -and (($msalProbe -join "`n") -match "msal-ok"))
    }
    else { $result.Python.Error = "No usable Python command was found." }
}
catch { $result.Python.Error = $_.Exception.Message }

if (-not $result.Python.PythonAvailable) { [void]$result.Missing.Add("Python 3.10 or later") }
if (-not $result.Python.RequestsImport) { [void]$result.Missing.Add("Python package: requests") }
if (-not $result.Python.MsalImport) { [void]$result.Missing.Add("Python package: msal") }

$result.Ready = ($result.Missing.Count -eq 0)
Write-Output "CL_VALIDATION_JSON_START"
Write-Output ($result | ConvertTo-Json -Depth 10 -Compress)
Write-Output "CL_VALIDATION_JSON_END"
'@

do {
    $count = $count + 1
    $message = $null
    try {
        if ([string]::IsNullOrWhiteSpace($sub)) { throw "Injected subscription id `$sub is null or empty." }
        if ([string]::IsNullOrWhiteSpace($DID)) { throw "Injected deployment id `$DID is null or empty." }
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
            if ([string]::IsNullOrWhiteSpace($rg)) { throw "VM '$vmName' lookup returned an empty ResourceGroupName." }
            $failures = New-Object System.Collections.Generic.List[string]

            $vmStatus = Get-AzVM -ResourceGroupName $rg -Name $vmName -Status -ErrorAction Stop
            $provisioningStatus = @($vmStatus.Statuses | Where-Object { $_.Code -like "ProvisioningState/*" } | Select-Object -First 1)
            if ($null -eq $provisioningStatus -or $provisioningStatus.Code -ne "ProvisioningState/succeeded") { $failures.Add("VM provisioning status is '$($provisioningStatus.Code)', expected 'ProvisioningState/succeeded'.") }
            $powerStatus = @($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -First 1)
            if ($null -eq $powerStatus -or $powerStatus.Code -ne "PowerState/running") { $failures.Add("VM power status is '$($powerStatus.Code)', expected 'PowerState/running'.") }
            if ($null -eq $vmStatus.VMAgent -or $null -eq $vmStatus.VMAgent.Statuses -or $vmStatus.VMAgent.Statuses.Count -eq 0) { $failures.Add("Azure VM Agent status is missing or unreadable.") }
            else {
                $agentReady = @($vmStatus.VMAgent.Statuses | Where-Object { $_.DisplayStatus -eq "Ready" -or $_.Code -eq "ProvisioningState/succeeded" })
                if ($agentReady.Count -eq 0) { $failures.Add("Azure VM Agent is not reporting Ready.") }
            }
            $extensions = @($vmStatus.Extensions)
            $customScriptExtensions = @($extensions | Where-Object { $_.Type -eq "Microsoft.Compute.CustomScriptExtension" -or $_.Type -like "*CustomScript*" -or $_.Name -like "*CustomScript*" })
            if ($customScriptExtensions.Count -eq 0) { $failures.Add("Custom Script Extension was not found in the VM instance view.") }
            elseif (@($customScriptExtensions | Where-Object { @($_.Statuses | Where-Object { $_.Code -eq "ProvisioningState/succeeded" }).Count -gt 0 }).Count -eq 0) { $failures.Add("Custom Script Extension is present but not reporting ProvisioningState/succeeded.") }

            $runResult = Invoke-AzVMRunCommand -ResourceGroupName $rg -VMName $vmName -CommandId "RunPowerShellScript" -ScriptString $assetCheckScript -ErrorAction Stop
            $runOutput = (@($runResult.Value | ForEach-Object { $_.Message }) -join "`n")
            if ([string]::IsNullOrWhiteSpace($runOutput)) { throw "Invoke-AzVMRunCommand output was empty while checking local lab assets on '$vmName'." }
            $jsonMatch = [regex]::Match($runOutput, "(?s)CL_VALIDATION_JSON_START\s*(\{.*\})\s*CL_VALIDATION_JSON_END")
            if (-not $jsonMatch.Success) { throw "Could not parse local asset validation JSON from VM run-command output. Raw output: $runOutput" }
            $assetState = $jsonMatch.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop

            if ($assetState.Ready -ne $true) {
                $missingItems = @($assetState.Missing) -join "; "
                if ([string]::IsNullOrWhiteSpace($missingItems)) { $missingItems = "VM-side readiness script reported Ready=false but did not list missing items." }
                $failures.Add("Local assets or Python prerequisites failed: $missingItems")
            }

            if ($failures.Count -eq 0) {
                $found = $true
                $designFiles = @($assetState.DesignFiles) -join ", "
                $pythonVersion = $assetState.Python.Version
                $message = @{
                    Status  = "Succeeded"
                    Message = "VM '$vmName' in RG '$rg' is provisioned/running with a succeeded Custom Script Extension. Required Zava lab assets are present, HR CSV has $($assetState.HrCsv.RowCount) rows with departing/ISO-date indicators, Graph starter script has expected local code references, and Python '$pythonVersion' imports requests and msal. Design files found: $designFiles."
                } | ConvertTo-Json
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
            }
            else {
                $lastFailure = ($failures -join " ")
                $message = @{ Status = "Failed"; Message = "VM readiness and local asset validation failed for '$vmName' in RG '$rg'. $lastFailure" } | ConvertTo-Json
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
            }
        }
        if (-not $found -and [string]::IsNullOrWhiteSpace($message)) {
            $message = @{ Status = "Failed"; Message = $lastFailure } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
        }
        if (-not $found -and $count -lt 3) { Start-Sleep -Seconds 10 }
    }
    catch {
        $lastFailure = "Error during VM readiness, Custom Script Extension, local asset, and Python check. Attempt $count of 3. Error: $($_.Exception.Message)"
        $message = @{ Status = "Failed"; Message = $lastFailure } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
        Start-Sleep -Seconds 10
    }
} while ($count -lt 3 -and -not $found)

# Post-loop: if every attempt failed, emit a final failure JSON so CloudLabs always sees a structured result.
if (-not $found) {
    if ([string]::IsNullOrWhiteSpace($rg)) { $rg = "not discovered" }
    $message = @{
        Status  = "Failed"
        Message = "VM readiness, Custom Script Extension, local lab asset, and Python readiness validation did not succeed for VM '$vmName' in RG '$rg' after 3 attempts. Last failure: $lastFailure"
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
}

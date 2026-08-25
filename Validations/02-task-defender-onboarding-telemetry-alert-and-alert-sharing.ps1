using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
# Validation 2 scores only observable Microsoft Defender for Endpoint state:
# - the Azure VM exists and is running,
# - Defender for Endpoint reports the VM as onboarded/active with recent lastSeen telemetry,
# - a recent Microsoft Defender for Endpoint EICAR/test-file alert exists for the VM or lab admin account.
# Microsoft Purview / Insider Risk Management data-sharing settings are intentionally out of scope and are not read or graded by this validator.

$vmName = "labvm-$DID"
$rg = ""
$count = 0
$found = $false
$finalFailureMessage = "Defender for Endpoint onboarding and EICAR telemetry were not validated."

function Convert-TokenToPlainText {
    param([Parameter(Mandatory = $true)]$AccessToken)
    if ($AccessToken.Token -is [System.Security.SecureString]) {
        return ([System.Net.NetworkCredential]::new("", $AccessToken.Token)).Password
    }
    return [string]$AccessToken.Token
}

function Invoke-JsonGet {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][hashtable]$Headers
    )
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -ErrorAction Stop
}

function Get-AllPagedValues {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [int]$MaxPages = 5
    )
    $allValues = @()
    $nextUri = $Uri
    $page = 0
    while (-not [string]::IsNullOrWhiteSpace($nextUri) -and $page -lt $MaxPages) {
        $page++
        $response = Invoke-JsonGet -Uri $nextUri -Headers $Headers
        if ($null -ne $response.value) { $allValues += @($response.value) }
        $nextUri = $response.'@odata.nextLink'
    }
    return $allValues
}

function Test-DeviceNameMatch {
    param(
        [string]$Candidate,
        [Parameter(Mandatory = $true)][string]$ExpectedShortName
    )
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $false }
    $candidateShortName = ($Candidate -split '\.')[0]
    return ($candidateShortName -ieq $ExpectedShortName -or $Candidate -ieq $ExpectedShortName)
}

function Get-ObjectText {
    param($InputObject)
    if ($null -eq $InputObject) { return "" }
    return ($InputObject | ConvertTo-Json -Depth 40 -Compress)
}

function Test-AlertDeviceOrUserMatch {
    param(
        $Alert,
        [string]$MdeMachineId,
        [Parameter(Mandatory = $true)][string]$ExpectedShortName,
        [string]$ExpectedUserPrincipalName
    )

    $alertText = Get-ObjectText -InputObject $Alert
    if (-not [string]::IsNullOrWhiteSpace($MdeMachineId) -and $alertText -match [regex]::Escape($MdeMachineId)) { return $true }
    if ($alertText -match [regex]::Escape($ExpectedShortName)) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedUserPrincipalName) -and $alertText -match [regex]::Escape($ExpectedUserPrincipalName)) { return $true }

    foreach ($evidence in @($Alert.evidence)) {
        if (Test-DeviceNameMatch -Candidate $evidence.deviceDnsName -ExpectedShortName $ExpectedShortName) { return $true }
        if (Test-DeviceNameMatch -Candidate $evidence.hostName -ExpectedShortName $ExpectedShortName) { return $true }
        if (Test-DeviceNameMatch -Candidate $evidence.computerDnsName -ExpectedShortName $ExpectedShortName) { return $true }
        if (-not [string]::IsNullOrWhiteSpace($MdeMachineId) -and $evidence.mdeDeviceId -eq $MdeMachineId) { return $true }
        if (-not [string]::IsNullOrWhiteSpace($MdeMachineId) -and $evidence.machineId -eq $MdeMachineId) { return $true }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedUserPrincipalName) -and $null -ne $evidence.userAccount -and $evidence.userAccount.userPrincipalName -ieq $ExpectedUserPrincipalName) { return $true }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedUserPrincipalName) -and $evidence.userPrincipalName -ieq $ExpectedUserPrincipalName) { return $true }
    }

    return $false
}

function Test-EicarAlert {
    param(
        $Alert,
        [string]$MdeMachineId,
        [Parameter(Mandatory = $true)][string]$ExpectedShortName,
        [string]$ExpectedUserPrincipalName
    )

    $alertText = Get-ObjectText -InputObject $Alert
    $isMde = (
        $Alert.serviceSource -ieq "microsoftDefenderForEndpoint" -or
        $Alert.source -ieq "WindowsDefenderAtp" -or
        $Alert.detectionSource -match "(?i)antivirus|windowsdefender|defender|edr|microsoftDefenderForEndpoint|windowsDefenderAv" -or
        -not [string]::IsNullOrWhiteSpace([string]$Alert.machineId) -or
        -not [string]::IsNullOrWhiteSpace([string]$Alert.computerDnsName)
    )
    $isEicar = ($alertText -match "(?i)eicar|eicar_test_file|eicar-test-file|virus:DOS/EICAR|test file|antivirus test")
    $matchesDeviceOrUser = Test-AlertDeviceOrUserMatch -Alert $Alert -MdeMachineId $MdeMachineId -ExpectedShortName $ExpectedShortName -ExpectedUserPrincipalName $ExpectedUserPrincipalName
    return ($isMde -and $isEicar -and $matchesDeviceOrUser)
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop | Out-Null
        $context = Get-AzContext -ErrorAction Stop
        $tenantId = $context.Tenant.Id
        $candidateUpn = $context.Account.Id

        $vmResource = Get-AzResource -ResourceType "Microsoft.Compute/virtualMachines" -Name $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $vmResource) {
            $finalFailureMessage = "Azure VM '$vmName' was not found in subscription '$sub'; Defender for Endpoint telemetry cannot be mapped to the lab VM."
            $message = @{ Status = "Failed"; Message = "$finalFailureMessage Attempt $count of 3." } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
            Start-Sleep -Seconds 10
            continue
        }
        $rg = $vmResource.ResourceGroupName

        $vmStatus = Get-AzVM -ResourceGroupName $rg -Name $vmName -Status -ErrorAction Stop
        $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -First 1).DisplayStatus
        if ($powerState -ne "VM running") {
            $finalFailureMessage = "Azure VM '$vmName' in resource group '$rg' is not running. Current power state: '$powerState'. Start the VM before validating Defender for Endpoint telemetry."
            $message = @{ Status = "Failed"; Message = "$finalFailureMessage Attempt $count of 3." } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
            Start-Sleep -Seconds 10
            continue
        }

        $mdeToken = Convert-TokenToPlainText -AccessToken (Get-AzAccessToken -ResourceUrl "https://api.securitycenter.microsoft.com" -TenantId $tenantId -ErrorAction Stop)
        $graphToken = Convert-TokenToPlainText -AccessToken (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -TenantId $tenantId -ErrorAction Stop)
        $mdeHeaders = @{ Authorization = "Bearer $mdeToken"; Accept = "application/json"; "User-Agent" = "CloudLabs-Zava-Defender-Validation/1.0" }
        $graphHeaders = @{ Authorization = "Bearer $graphToken"; Accept = "application/json"; "User-Agent" = "CloudLabs-Zava-Defender-Validation/1.0" }

        $machineLookbackUtc = (Get-Date).ToUniversalTime().AddHours(-48).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $machinesFilter = [uri]::EscapeDataString("lastSeen ge $machineLookbackUtc")
        $machinesUri = "https://api.security.microsoft.com/api/machines?`$filter=$machinesFilter&`$top=10000"
        $machines = Get-AllPagedValues -Uri $machinesUri -Headers $mdeHeaders -MaxPages 3
        $machine = @($machines | Where-Object { (Test-DeviceNameMatch -Candidate $_.computerDnsName -ExpectedShortName $vmName) -or (Test-DeviceNameMatch -Candidate $_.deviceName -ExpectedShortName $vmName) } | Sort-Object -Property lastSeen -Descending | Select-Object -First 1)

        if ($machine.Count -eq 0) {
            $finalFailureMessage = "Microsoft Defender for Endpoint did not return a recent machine record for '$vmName'. Onboard the VM, keep it running, and wait for device inventory telemetry before retrying."
            $message = @{ Status = "Failed"; Message = "$finalFailureMessage Attempt $count of 3." } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
            Start-Sleep -Seconds 10
            continue
        }

        $machine = $machine[0]
        $onboardingStatus = [string]$machine.onboardingStatus
        $healthStatus = [string]$machine.healthStatus
        $machineLastSeen = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$machine.lastSeen)) {
            $machineLastSeen = [datetime]::Parse([string]$machine.lastSeen).ToUniversalTime()
        }
        $isOnboarded = ($onboardingStatus -ieq "Onboarded")
        $isActive = ($healthStatus -ieq "Active")
        $isRecentlySeen = ($null -ne $machineLastSeen -and $machineLastSeen -ge (Get-Date).ToUniversalTime().AddHours(-48))

        if (-not ($isOnboarded -and $isActive -and $isRecentlySeen)) {
            $finalFailureMessage = "MDE machine '$($machine.computerDnsName)' was found, but it is not confirmed onboarded, active, and recent. onboardingStatus='$onboardingStatus', healthStatus='$healthStatus', lastSeen='$($machine.lastSeen)'."
            $message = @{ Status = "Failed"; Message = "$finalFailureMessage Attempt $count of 3." } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
            Start-Sleep -Seconds 10
            continue
        }

        $alertLookbackUtc = (Get-Date).ToUniversalTime().AddHours(-72).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $graphAlertFilter = [uri]::EscapeDataString("serviceSource eq 'microsoftDefenderForEndpoint' and createdDateTime ge $alertLookbackUtc")
        $graphAlertsUri = "https://graph.microsoft.com/v1.0/security/alerts_v2?`$filter=$graphAlertFilter&`$top=100"
        $graphAlerts = Get-AllPagedValues -Uri $graphAlertsUri -Headers $graphHeaders -MaxPages 5
        $matchingAlert = @($graphAlerts | Where-Object { Test-EicarAlert -Alert $_ -MdeMachineId $machine.id -ExpectedShortName $vmName -ExpectedUserPrincipalName $candidateUpn } | Sort-Object -Property createdDateTime -Descending | Select-Object -First 1)
        $alertSurface = "Microsoft Graph security alerts_v2"

        if ($matchingAlert.Count -eq 0) {
            $mdeAlertFilter = [uri]::EscapeDataString("alertCreationTime ge $alertLookbackUtc")
            $mdeAlertsUri = "https://api.security.microsoft.com/api/alerts?`$filter=$mdeAlertFilter&`$expand=evidence&`$top=100"
            $mdeAlerts = Get-AllPagedValues -Uri $mdeAlertsUri -Headers $mdeHeaders -MaxPages 5
            $matchingAlert = @($mdeAlerts | Where-Object { Test-EicarAlert -Alert $_ -MdeMachineId $machine.id -ExpectedShortName $vmName -ExpectedUserPrincipalName $candidateUpn } | Sort-Object -Property alertCreationTime -Descending | Select-Object -First 1)
            if ($matchingAlert.Count -gt 0) { $alertSurface = "Microsoft Defender for Endpoint alerts API" }
        }

        if ($matchingAlert.Count -eq 0) {
            $finalFailureMessage = "No recent Microsoft Defender for Endpoint EICAR/test-file alert was found for VM '$vmName' or account '$candidateUpn' in the last 72 hours through Graph alerts_v2 or Defender for Endpoint alert APIs. Generate the EICAR test alert after onboarding and wait for alert ingestion before retrying."
            $message = @{ Status = "Failed"; Message = "$finalFailureMessage Attempt $count of 3." } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
            Start-Sleep -Seconds 10
            continue
        }

        $matchingAlert = $matchingAlert[0]
        $alertId = if ($matchingAlert.id) { $matchingAlert.id } else { $matchingAlert.providerAlertId }
        $alertCreated = if ($matchingAlert.createdDateTime) { $matchingAlert.createdDateTime } else { $matchingAlert.alertCreationTime }
        $alertTitle = $matchingAlert.title
        $found = $true
        $message = @{
            Status  = "Succeeded"
            Message = "Defender for Endpoint checks passed. Azure VM '$vmName' is running in resource group '$rg'. MDE device '$($machine.computerDnsName)' is onboarded and active with lastSeen '$($machine.lastSeen)'. Recent EICAR/test-file alert '$alertTitle' ('$alertId') was found via $alertSurface at '$alertCreated'."
        } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
    }
    catch {
        $finalFailureMessage = "Error during Defender for Endpoint onboarding and EICAR telemetry check. Attempt $count of 3. Error: $($_.Exception.Message)"
        $message = @{ Status = "Failed"; Message = $finalFailureMessage } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
        Start-Sleep -Seconds 10
    }
} while ($count -lt 3 -and -not $found)

if (-not $found) {
    if ([string]::IsNullOrWhiteSpace($rg)) { $rg = "resource group containing $vmName" }
    $message = @{ Status = "Failed"; Message = "$finalFailureMessage Validation did not reach a pass state after 3 attempts for VM '$vmName' in '$rg'." } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
}

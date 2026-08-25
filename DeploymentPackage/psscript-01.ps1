Param(
    [string] $AzureUserName,
    [string] $AzurePassword,
    [string] $AzureTenantID,
    [string] $AzureSubscriptionID,
    [string] $ODLID,
    [string] $InstallCloudLabsShadow,
    [string] $DeploymentID,
    [string] $vmAdminUsername,
    [string] $vmAdminPassword,
    [string] $trainerUserName,
    [string] $trainerUserPassword
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$logDirectory = 'C:\WindowsAzure\Logs'
if (-not (Test-Path $logDirectory)) { New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null }
Start-Transcript -Path 'C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt' -Force

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $labRoot = 'C:\LabFiles'
    $designRoot = Join-Path $labRoot 'ZavaDesignFiles'
    $commonUri = 'https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/'

    function Write-Log { param([string] $Message) Write-Host "[$(Get-Date -Format o)] $Message" }
    function Ensure-Directory { param([string] $Path) if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null } }
    function Save-TextFile { param([string] $Path, [string] $Content) $parent = Split-Path -Path $Path -Parent; if ($parent) { Ensure-Directory -Path $parent }; Set-Content -Path $Path -Value $Content -Encoding UTF8 -Force }

    function CreateCredFile {
        Write-Log 'Creating CloudLabs credential files.'
        Ensure-Directory -Path $labRoot
        Ensure-Directory -Path 'C:\Users\Public\Desktop'
        foreach ($fileName in @('AzureCreds.txt', 'AzureCreds.ps1')) {
            $destination = Join-Path $labRoot $fileName
            try {
                Invoke-WebRequest -Uri ($commonUri + $fileName) -OutFile $destination -UseBasicParsing -ErrorAction Stop
                Write-Log "Downloaded $fileName from cloudlabs-common."
            }
            catch {
                Write-Log "Could not download $fileName. Writing local fallback. $_"
                if ($fileName -eq 'AzureCreds.txt') {
                    @"
Azure Username: $AzureUserName
Azure Password: $AzurePassword
Tenant ID: $AzureTenantID
Subscription ID: $AzureSubscriptionID
Deployment ID: $DeploymentID
ODL ID: $ODLID
"@ | Set-Content -Path $destination -Encoding UTF8 -Force
                }
                else {
                    @"
`$AzureUserName = '$AzureUserName'
`$AzurePassword = '$AzurePassword'
`$AzureTenantID = '$AzureTenantID'
`$AzureSubscriptionID = '$AzureSubscriptionID'
`$DeploymentID = '$DeploymentID'
`$ODLID = '$ODLID'
"@ | Set-Content -Path $destination -Encoding UTF8 -Force
                }
            }
            if (Test-Path $destination) {
                try {
                    $content = Get-Content -Path $destination -Raw -ErrorAction Stop
                    $replacementMap = @{
                        'GET-AZUSER-UPN' = $AzureUserName
                        'GET-AZUSER-PASSWORD' = $AzurePassword
                        'GET-TENANT-ID' = $AzureTenantID
                        'GET-SUBSCRIPTION-ID' = $AzureSubscriptionID
                        'GET-ODL-ID' = $ODLID
                        'GET-DEPLOYMENT-ID' = $DeploymentID
                        'AzureUserNameValue' = $AzureUserName
                        'AzurePasswordValue' = $AzurePassword
                        'AzureTenantIDValue' = $AzureTenantID
                        'AzureSubscriptionIDValue' = $AzureSubscriptionID
                        'ODLIDValue' = $ODLID
                        'DeploymentIDValue' = $DeploymentID
                        '<AzureUserName>' = $AzureUserName
                        '<AzurePassword>' = $AzurePassword
                        '<AzureTenantID>' = $AzureTenantID
                        '<AzureSubscriptionID>' = $AzureSubscriptionID
                        '<ODLID>' = $ODLID
                        '<DeploymentID>' = $DeploymentID
                    }
                    foreach ($key in $replacementMap.Keys) { $content = $content.Replace($key, [string]$replacementMap[$key]) }
                    Set-Content -Path $destination -Value $content -Encoding UTF8 -Force
                }
                catch { Write-Log "Credential placeholder replacement failed for $fileName. $_" }
                Copy-Item -Path $destination -Destination (Join-Path 'C:\Users\Public\Desktop' $fileName) -Force -ErrorAction SilentlyContinue
            }
        }
    }

    function Ensure-TrainerShadowAccount {
        $shadowDisabled = $false
        if (-not [string]::IsNullOrWhiteSpace($InstallCloudLabsShadow)) { $shadowDisabled = ($InstallCloudLabsShadow.Trim() -match '^(false|0|no)$') }
        if ($shadowDisabled) { Write-Log 'InstallCloudLabsShadow is explicitly false. Skipping trainer local account creation.'; return }
        if ([string]::IsNullOrWhiteSpace($trainerUserName) -or [string]::IsNullOrWhiteSpace($trainerUserPassword)) { Write-Log 'Trainer username/password were not provided. Skipping trainer local account creation.'; return }
        try {
            $securePassword = ConvertTo-SecureString $trainerUserPassword -AsPlainText -Force
            $existingUser = Get-LocalUser -Name $trainerUserName -ErrorAction SilentlyContinue
            if ($null -eq $existingUser) {
                New-LocalUser -Name $trainerUserName -Password $securePassword -PasswordNeverExpires -AccountNeverExpires -FullName 'CloudLabs Trainer Shadow Account' -Description 'Local account used by CloudLabs VM Shadow.' | Out-Null
            }
            else {
                Set-LocalUser -Name $trainerUserName -Password $securePassword -PasswordNeverExpires $true -ErrorAction SilentlyContinue
                Enable-LocalUser -Name $trainerUserName -ErrorAction SilentlyContinue
            }
            foreach ($groupName in @('Remote Desktop Users', 'Administrators')) {
                try { Add-LocalGroupMember -Group $groupName -Member $trainerUserName -ErrorAction Stop } catch { Write-Log "Could not add $trainerUserName to $groupName or membership already exists. $_" }
            }
        }
        catch { Write-Log "Trainer local account setup failed. $_" }
    }

    function Ensure-Chocolatey {
        if (Get-Command choco.exe -ErrorAction SilentlyContinue) { return $true }
        try {
            Write-Log 'Installing Chocolatey.'
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
            return [bool](Get-Command choco.exe -ErrorAction SilentlyContinue)
        }
        catch { Write-Log "Chocolatey installation failed. $_"; return $false }
    }

    function Invoke-ChocoInstall { param([string] $PackageName, [string] $ExtraArgs = '') if (Get-Command choco.exe -ErrorAction SilentlyContinue) { try { Start-Process -FilePath 'choco.exe' -ArgumentList "install $PackageName -y --no-progress $ExtraArgs" -Wait -NoNewWindow -ErrorAction Stop; $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User') } catch { Write-Log "Chocolatey package $PackageName failed or was already handled. $_" } } }

    function Get-PythonCommand {
        foreach ($candidate in @('python.exe', 'py.exe')) { $cmd = Get-Command $candidate -ErrorAction SilentlyContinue; if ($cmd) { if ($candidate -eq 'py.exe') { return 'py -3' }; return $cmd.Source } }
        foreach ($path in @('C:\Python313\python.exe','C:\Python312\python.exe','C:\Python311\python.exe','C:\Python310\python.exe','C:\Program Files\Python313\python.exe','C:\Program Files\Python312\python.exe','C:\Program Files\Python311\python.exe','C:\Program Files\Python310\python.exe')) { if (Test-Path $path) { return $path } }
        return $null
    }

    function Test-Python310OrNewer { param([string] $PythonCommand) try { $versionText = & cmd.exe /c "$PythonCommand -c ""import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')""" 2>$null; if ([string]::IsNullOrWhiteSpace($versionText)) { return $false }; return ([version]($versionText.Trim()) -ge [version]'3.10.0') } catch { return $false } }

    function Ensure-PythonAndPackages {
        $pythonCommand = Get-PythonCommand
        if (-not $pythonCommand -or -not (Test-Python310OrNewer -PythonCommand $pythonCommand)) { Invoke-ChocoInstall -PackageName 'python' -ExtraArgs '--version=3.12.6'; $pythonCommand = Get-PythonCommand }
        if (-not $pythonCommand) { Write-Log 'Python could not be located after installation attempt.'; return }
        try { & cmd.exe /c "$pythonCommand -m ensurepip --upgrade" | Write-Host; & cmd.exe /c "$pythonCommand -m pip install --upgrade pip requests msal" | Write-Host } catch { Write-Log "Python package installation failed. $_" }
    }

    function Ensure-ProductivityTools {
        Ensure-Chocolatey | Out-Null
        Ensure-PythonAndPackages
        if (-not (Test-Path 'C:\Program Files\Microsoft VS Code\Code.exe') -and -not (Get-Command code.cmd -ErrorAction SilentlyContinue)) { Invoke-ChocoInstall -PackageName 'vscode' }
        if (-not (@('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1)) { Invoke-ChocoInstall -PackageName 'microsoft-edge' }
    }

    function New-ZavaDesignFiles {
        Ensure-Directory -Path $designRoot
        Save-TextFile -Path (Join-Path $designRoot 'AeroFrame-Assembly-RevC.step') -Content @'
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('Zava Manufacturing training artifact - nonproduction STEP content'),'2;1');
FILE_NAME('AeroFrame-Assembly-RevC.step','LAB_DATE',('Zava Design Engineering'),('Zava Manufacturing'),'CloudLabs','CloudLabs','');
ENDSEC;
DATA;
#10=PRODUCT('ZV-AEROFRAME-REV-C','AeroFrame Assembly Rev C','Training-only geometry metadata',(#20));
#20=PRODUCT_CONTEXT('',#30,'mechanical');
#30=APPLICATION_CONTEXT('Zava Manufacturing insider risk lab');
#40=CARTESIAN_POINT('root datum',(0.0,0.0,0.0));
ENDSEC;
END-ISO-10303-21;
'@
        Save-TextFile -Path (Join-Path $designRoot 'ZV-9000-Cooling-Manifold.dwg') -Content "ZAVA MANUFACTURING - TRAINING DWG PLACEHOLDER`r`nDrawing: ZV-9000 Cooling Manifold`r`nRevision: B`r`n"
        Save-TextFile -Path (Join-Path $designRoot 'Prototype-Test-Matrix.xlsx') -Content "TestId,Assembly,TemperatureC,PressureKPa,FlowRateLpm,PassFail,EngineerNotes`r`nPT-001,AeroFrame-RevC,22,101,14.7,Pass,Baseline ambient run`r`nPT-004,ZV-9000-Manifold,95,132,10.8,Fail,Prototype cooling redesign required`r`n"
        Save-TextFile -Path (Join-Path $designRoot 'Supplier-Costed-BOM-Q4.xlsx') -Content "PartNumber,Description,Supplier,LeadTimeDays,UnitCostUSD,Quarter`r`nZV-AF-1001,AeroFrame carbon spar,Northwind Composites,42,1840.50,Q4`r`nZV-CM-9000,Cooling manifold additive blank,Fabrikam Additive,35,1275.00,Q4`r`n"
        Save-TextFile -Path (Join-Path $designRoot 'Manufacturing-Tolerances.pdf') -Content "Zava Manufacturing - Manufacturing Tolerances`r`nTraining-only PDF placeholder content.`r`nAeroFrame Assembly Rev C tolerance notes.`r`n"
    }

    function New-ZavaHrFiles {
        $baseUtcDate = (Get-Date).Date.ToUniversalTime()
        $resignationDate = $baseUtcDate.AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        $lastWorkingDate = $baseUtcDate.AddDays(14).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        $colleagueResignationDate = $baseUtcDate.AddDays(-15).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        $colleagueLastWorkingDate = $baseUtcDate.AddDays(7).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        $adminUpn = if ([string]::IsNullOrWhiteSpace($AzureUserName)) { 'REPLACE_WITH_LAB_ADMIN_UPN' } else { $AzureUserName }
        $template = @'
UserPrincipalName,EmployeeId,FirstName,LastName,ManagerUserPrincipalName,Department,JobTitle,EmploymentStatus,ResignationDate,LastWorkingDate,EventType
REPLACE_WITH_LAB_ADMIN_UPN,ZAVA-ENG-0142,Alex,Chen,manager@zava.example,Design Engineering,Senior Design Engineer,Departing,REPLACE_WITH_RESIGNATION_DATE,REPLACE_WITH_LAST_WORKING_DATE,Resignation
maria.lopez@zava.example,ZAVA-ENG-0201,Maria,Lopez,manager@zava.example,Design Engineering,Design Engineer,Departing,REPLACE_WITH_RESIGNATION_DATE,REPLACE_WITH_LAST_WORKING_DATE,Resignation
samir.patel@zava.example,ZAVA-MFG-0317,Samir,Patel,manager@zava.example,Manufacturing Engineering,Manufacturing Engineer,Departing,REPLACE_WITH_RESIGNATION_DATE,REPLACE_WITH_LAST_WORKING_DATE,Resignation
'@
        Save-TextFile -Path (Join-Path $labRoot 'ZavaHRData.template.csv') -Content $template
        $csv = $template.Replace('REPLACE_WITH_LAB_ADMIN_UPN', $adminUpn).Replace('REPLACE_WITH_RESIGNATION_DATE', $resignationDate).Replace('REPLACE_WITH_LAST_WORKING_DATE', $lastWorkingDate)
        $csvLines = $csv -split "`r?`n"
        if ($csvLines.Count -ge 4) { $csvLines[2] = $csvLines[2].Replace($resignationDate, $colleagueResignationDate).Replace($lastWorkingDate, $colleagueLastWorkingDate) }
        Save-TextFile -Path (Join-Path $labRoot 'ZavaHRData.csv') -Content ($csvLines -join [Environment]::NewLine)
    }

    function New-PrepareScript {
        Save-TextFile -Path (Join-Path $labRoot 'Prepare-ZavaLab.ps1') -Content @'
Param([string] $AdminUPN, [switch] $Force)
$ErrorActionPreference = 'Continue'
$LabRoot = 'C:\LabFiles'
$TemplatePath = Join-Path $LabRoot 'ZavaHRData.template.csv'
$CsvPath = Join-Path $LabRoot 'ZavaHRData.csv'
function Write-Step { param([string] $Message) Write-Host "[Zava Prep] $Message" -ForegroundColor Cyan }
if ([string]::IsNullOrWhiteSpace($AdminUPN) -and (Test-Path (Join-Path $LabRoot 'AzureCreds.ps1'))) { try { . (Join-Path $LabRoot 'AzureCreds.ps1'); if ($AzureUserName) { $AdminUPN = $AzureUserName } } catch { } }
if ([string]::IsNullOrWhiteSpace($AdminUPN)) { $AdminUPN = Read-Host 'Enter the lab admin UPN that represents the departing Zava design engineer' }
if (-not [string]::IsNullOrWhiteSpace($AdminUPN)) {
    $baseUtcDate = (Get-Date).Date.ToUniversalTime()
    $resignationDate = $baseUtcDate.AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
    $lastWorkingDate = $baseUtcDate.AddDays(14).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
    $secondResignationDate = $baseUtcDate.AddDays(-15).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
    $secondLastWorkingDate = $baseUtcDate.AddDays(7).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
    $csv = if (Test-Path $TemplatePath) { Get-Content -Path $TemplatePath -Raw } else { "UserPrincipalName,EmployeeId,FirstName,LastName,ManagerUserPrincipalName,Department,JobTitle,EmploymentStatus,ResignationDate,LastWorkingDate,EventType`r`nREPLACE_WITH_LAB_ADMIN_UPN,ZAVA-ENG-0142,Alex,Chen,manager@zava.example,Design Engineering,Senior Design Engineer,Departing,REPLACE_WITH_RESIGNATION_DATE,REPLACE_WITH_LAST_WORKING_DATE,Resignation`r`nmaria.lopez@zava.example,ZAVA-ENG-0201,Maria,Lopez,manager@zava.example,Design Engineering,Design Engineer,Departing,REPLACE_WITH_RESIGNATION_DATE,REPLACE_WITH_LAST_WORKING_DATE,Resignation`r`nsamir.patel@zava.example,ZAVA-MFG-0317,Samir,Patel,manager@zava.example,Manufacturing Engineering,Manufacturing Engineer,Departing,REPLACE_WITH_RESIGNATION_DATE,REPLACE_WITH_LAST_WORKING_DATE,Resignation`r`n" }
    $csv = $csv.Replace('REPLACE_WITH_LAB_ADMIN_UPN', $AdminUPN).Replace('REPLACE_WITH_RESIGNATION_DATE', $resignationDate).Replace('REPLACE_WITH_LAST_WORKING_DATE', $lastWorkingDate)
    $lines = $csv -split "`r?`n"
    if ($lines.Count -ge 4) { $lines[2] = $lines[2].Replace($resignationDate, $secondResignationDate).Replace($lastWorkingDate, $secondLastWorkingDate) }
    Set-Content -Path $CsvPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8 -Force
    Write-Host "HR CSV ready: $CsvPath" -ForegroundColor Green
}
$exfilPath = if (Test-Path 'D:\') { 'D:\ExfilStaging' } else { 'C:\ExfilStaging' }
if (-not (Test-Path $exfilPath)) { New-Item -Path $exfilPath -ItemType Directory -Force | Out-Null }
Set-Content -Path (Join-Path $exfilPath 'README-ZavaEvidence.txt') -Value "Use this folder as the local exfiltration-like staging location during Exercise 2." -Encoding UTF8 -Force
Write-Host "Evidence staging folder: $exfilPath" -ForegroundColor Green
Write-Step 'Preparation complete. Review C:\LabFiles\ZavaHRData.csv before importing it into the Purview HR connector.'
'@
    }

    function New-EicarScript {
        Save-TextFile -Path (Join-Path $labRoot 'Invoke-ZavaEicarTest.ps1') -Content @'
Param([string] $OutputDirectory = 'C:\LabFiles\EicarTest')
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutputDirectory)) { New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null }
$eicar = 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
$target = Join-Path $OutputDirectory 'EICAR.txt'
Write-Host "Writing the standard EICAR antivirus test string to $target."
try {
    [io.file]::WriteAllText($target, $eicar)
    Write-Host 'EICAR test file write attempted. Microsoft Defender Antivirus should detect/quarantine it when protection is active.' -ForegroundColor Green
}
catch { Write-Warning "EICAR write attempt returned an error. This can occur if Microsoft Defender blocks the file immediately. Details: $_" }
'@
    }

    function New-GraphStarterScript {
        Save-TextFile -Path (Join-Path $labRoot 'get_insider_alerts.py') -Content @'
"""
Zava Manufacturing - Exercise 5 Microsoft Graph security alert export.

This script is intentionally near-complete so Exercise 5 can focus on reviewing
configuration, device naming, and evidence indicators instead of pasting a large
program. It uses MSAL client credentials against Microsoft Graph /security/alerts_v2.

Required Microsoft Graph application permission: SecurityAlert.Read.All with admin consent.
Microsoft Learn reference: GET /security/alerts_v2 supports delegated and application
SecurityAlert.Read.All; application secrets are returned only once by addPassword.

C:\LabFiles\config.json is created only when bootstrap successfully creates an Entra
app registration and client secret. No ARM output publishes Graph client values. If
config.json is missing or authentication fails, complete the Exercise 5 manual fallback,
then save tenant_id, client_id, and client_secret in that local file.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional

import msal
import requests

LAB_ROOT = Path(r"C:\LabFiles")
CONFIG_PATH = LAB_ROOT / "config.json"
EXERCISE3_NOTES_PATH = LAB_ROOT / "Exercise3-HuntingNotes.txt"
DEFAULT_JSON_OUTPUT = LAB_ROOT / "insider_risk_case.json"
DEFAULT_REPORT_OUTPUT = LAB_ROOT / "insider_risk_case_report.txt"
DEFAULT_DSI_ROOT = LAB_ROOT / "DSIExports"
DEFAULT_DSI_CASE_JSON = DEFAULT_DSI_ROOT / "dsi_case_evidence.json"
GRAPH_BASE = "https://graph.microsoft.com/v1.0"
MDE_SERVICE_SOURCE = "microsoftdefenderforendpoint"


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def parse_graph_time(value: str) -> dt.datetime:
    if not value:
        return dt.datetime.min.replace(tzinfo=dt.timezone.utc)
    text = value.replace("Z", "+00:00")
    parsed = dt.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def graph_time(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_config(path: Path = CONFIG_PATH) -> Dict[str, str]:
    if not path.exists():
        raise FileNotFoundError(
            f"Missing {path}. Create an Entra app registration with Microsoft Graph "
            "application permission SecurityAlert.Read.All, grant admin consent, create a client secret, "
            "then save tenant_id, client_id, and client_secret in config.json."
        )
    with path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    normalized = {
        "tenant_id": config.get("tenant_id") or config.get("tenantId") or config.get("TenantId"),
        "client_id": config.get("client_id") or config.get("clientId") or config.get("ClientId"),
        "client_secret": config.get("client_secret") or config.get("clientSecret") or config.get("ClientSecret"),
    }
    missing = [key for key, value in normalized.items() if not value]
    if missing:
        raise ValueError(f"Missing required config values: {', '.join(missing)}")
    placeholder_tokens = ("GET-", "GEN-", "<", ">", "REPLACE_WITH")
    leaked = [key for key, value in normalized.items() if any(token in str(value) for token in placeholder_tokens)]
    if leaked:
        raise ValueError(f"Config contains placeholder-looking values instead of real Entra values: {', '.join(leaked)}")
    return normalized


def acquire_token(config: Dict[str, str]) -> str:
    app = msal.ConfidentialClientApplication(
        client_id=config["client_id"],
        authority=f"https://login.microsoftonline.com/{config['tenant_id']}",
        client_credential=config["client_secret"],
    )
    result = app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])
    if "access_token" not in result:
        raise RuntimeError(
            "MSAL client-credentials token acquisition failed. "
            f"Error: {result.get('error')} Description: {result.get('error_description')}"
        )
    return result["access_token"]


def graph_get(url: str, token: str, params: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    response = requests.get(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "ZavaInsiderRiskLab/2.1",
        },
        params=params,
        timeout=60,
    )
    if response.status_code >= 400:
        raise RuntimeError(f"Graph request failed: {response.status_code} {response.text}")
    return response.json()


def list_alerts_since(token: str, cutoff_utc: dt.datetime, top: int) -> List[Dict[str, Any]]:
    # Microsoft Graph alerts_v2 supports $filter on createdDateTime and @odata.nextLink pagination.
    params: Dict[str, str] = {
        "$filter": f"createdDateTime ge {graph_time(cutoff_utc)}",
        "$top": str(top),
    }
    alerts: List[Dict[str, Any]] = []
    url: Optional[str] = f"{GRAPH_BASE}/security/alerts_v2"
    while url:
        data = graph_get(url, token, params=params)
        alerts.extend(data.get("value", []))
        url = data.get("@odata.nextLink")
        params = None  # nextLink already contains the query string for subsequent pages.
    return alerts


def iter_strings(value: Any) -> Iterator[str]:
    if value is None:
        return
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            if isinstance(key, str):
                yield key
            yield from iter_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_strings(item)
    else:
        yield str(value)


def compact_alert_text(alert: Dict[str, Any]) -> str:
    return "\n".join(iter_strings(alert)).lower()


def is_defender_for_endpoint_alert(alert: Dict[str, Any]) -> bool:
    source_fields = [
        alert.get("serviceSource"),
        alert.get("detectionSource"),
        alert.get("providerName"),
        (alert.get("vendorInformation") or {}).get("provider"),
    ]
    normalized = {str(value).replace(" ", "").lower() for value in source_fields if value}
    if MDE_SERVICE_SOURCE in normalized:
        return True
    text = compact_alert_text(alert).replace(" ", "")
    return MDE_SERVICE_SOURCE in text or "microsoftdefenderendpoint" in text


def alert_mentions_lab_vm(alert: Dict[str, Any], vm_name: str) -> bool:
    if not vm_name:
        return False
    needle = vm_name.lower()
    return any(needle in text.lower() for text in iter_strings(alert))


def alert_mentions_eicar_or_test_file(alert: Dict[str, Any]) -> bool:
    indicators = [
        "eicar",
        "eicar.txt",
        "eicar.com",
        "standard-antivirus-test-file",
        "antivirus test",
        "test file",
        r"c:\labfiles\eicartest",
        "zavaeicar",
    ]
    text = compact_alert_text(alert)
    return any(indicator in text for indicator in indicators)


def is_lab_scoped_mde_alert(alert: Dict[str, Any], vm_name: str) -> bool:
    return is_defender_for_endpoint_alert(alert) and (
        alert_mentions_lab_vm(alert, vm_name) or alert_mentions_eicar_or_test_file(alert)
    )


def sha256_file(path: Path) -> Optional[str]:
    try:
        h = hashlib.sha256()
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                h.update(block)
        return h.hexdigest()
    except OSError:
        return None


def read_text_if_exists(path: Path, max_chars: int = 20000) -> Dict[str, Any]:
    result: Dict[str, Any] = {"path": str(path), "exists": path.exists(), "content": ""}
    if not path.exists() or not path.is_file():
        return result
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        result.update({"content": text[:max_chars], "length": len(text), "truncated": len(text) > max_chars})
    except OSError as exc:
        result["error"] = str(exc)
    return result


def load_json_if_exists(path: Path) -> Dict[str, Any]:
    result: Dict[str, Any] = {"path": str(path), "exists": path.exists(), "parsed": None}
    if not path.exists() or not path.is_file():
        return result
    try:
        result["parsed"] = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        result["error"] = str(exc)
    return result


def inventory_dsi_exports(root: Path) -> Dict[str, Any]:
    inventory: Dict[str, Any] = {"root": str(root), "exists": root.exists(), "files": []}
    if not root.exists():
        return inventory
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        try:
            stat = path.stat()
            inventory["files"].append(
                {
                    "relativePath": str(path.relative_to(root)),
                    "fullPath": str(path),
                    "sizeBytes": stat.st_size,
                    "modifiedUtc": dt.datetime.fromtimestamp(stat.st_mtime, dt.timezone.utc).isoformat(),
                    "sha256": sha256_file(path) if stat.st_size <= 50 * 1024 * 1024 else None,
                }
            )
        except OSError as exc:
            inventory["files"].append({"fullPath": str(path), "error": str(exc)})
    inventory["fileCount"] = len(inventory["files"])
    return inventory


def summarize_alert(alert: Dict[str, Any]) -> Dict[str, Any]:
    evidence = alert.get("evidence") if isinstance(alert.get("evidence"), list) else []
    return {
        "id": alert.get("id"),
        "title": alert.get("title"),
        "severity": alert.get("severity"),
        "status": alert.get("status"),
        "serviceSource": alert.get("serviceSource"),
        "detectionSource": alert.get("detectionSource"),
        "createdDateTime": alert.get("createdDateTime"),
        "lastUpdateDateTime": alert.get("lastUpdateDateTime"),
        "alertWebUrl": alert.get("alertWebUrl"),
        "evidenceCount": len(evidence),
    }


def write_outputs(
    all_recent: List[Dict[str, Any]],
    lab_matches: List[Dict[str, Any]],
    dsi_inventory: Dict[str, Any],
    exercise3_notes: Dict[str, Any],
    dsi_case_json: Dict[str, Any],
    json_path: Path,
    report_path: Path,
    cutoff: dt.datetime,
    vm_name: str,
) -> None:
    payload = {
        "generatedUtc": graph_time(utc_now()),
        "cutoffUtc": graph_time(cutoff),
        "labVmName": vm_name,
        "recentAlertCount": len(all_recent),
        "labScopedMdeAlertCount": len(lab_matches),
        "labScopedMdeAlertSummaries": [summarize_alert(alert) for alert in lab_matches],
        "labScopedMdeAlerts": lab_matches,
        "exercise3HuntingNotes": exercise3_notes,
        "dsiCaseEvidenceParsed": dsi_case_json,
        "dsiExportInventory": dsi_inventory,
    }
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    lines = [
        "Zava Manufacturing Defender for Endpoint Alert Export",
        f"Generated (UTC): {payload['generatedUtc']}",
        f"Server-side Graph cutoff: createdDateTime ge {payload['cutoffUtc']}",
        f"Lab VM filter: {vm_name or '(not supplied)'}",
        f"Recent alerts returned: {len(all_recent)}",
        f"Recent lab-scoped MDE alerts matched: {len(lab_matches)}",
        "",
        "Matched alerts:",
    ]
    for alert in lab_matches:
        summary = summarize_alert(alert)
        lines.extend([
            f"- Alert ID: {summary.get('id')}",
            f"  Title: {summary.get('title')}",
            f"  Severity: {summary.get('severity')}",
            f"  Status: {summary.get('status')}",
            f"  Service source: {summary.get('serviceSource')}",
            f"  Detection source: {summary.get('detectionSource')}",
            f"  Created: {summary.get('createdDateTime')}",
            f"  Evidence objects: {summary.get('evidenceCount')}",
            f"  Portal URL: {summary.get('alertWebUrl')}",
            "",
        ])
    lines.extend([
        "Exercise 3 hunting notes:",
        f"- Path: {exercise3_notes.get('path')}",
        f"- Exists: {exercise3_notes.get('exists')}",
        f"- Length: {exercise3_notes.get('length', 0)}",
    ])
    if exercise3_notes.get("content"):
        lines.extend(["- Preview:", exercise3_notes["content"][:3000], ""])
    lines.extend([
        "DSI/eDiscovery normalized case evidence:",
        f"- Path: {dsi_case_json.get('path')}",
        f"- Exists: {dsi_case_json.get('exists')}",
        f"- Parsed: {dsi_case_json.get('parsed') is not None}",
        "",
        "DSI/eDiscovery export inventory:",
        f"- Root: {dsi_inventory.get('root')}",
        f"- Exists: {dsi_inventory.get('exists')}",
        f"- Files: {dsi_inventory.get('fileCount', 0)}",
    ])
    for item in dsi_inventory.get("files", []):
        lines.append(f"  - {item.get('relativePath', item.get('fullPath'))} ({item.get('sizeBytes', 'unknown')} bytes)")
    report_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Export recent lab-scoped Microsoft Defender for Endpoint alerts from Microsoft Graph alerts_v2.")
    parser.add_argument("--config", default=str(CONFIG_PATH), help="Path to config.json containing tenant_id, client_id, and client_secret")
    parser.add_argument("--smoke-test", action="store_true", help="Only test MSAL client-credentials token acquisition")
    parser.add_argument("--since-hours", type=int, default=72, help="UTC lookback window for server-side createdDateTime filter")
    parser.add_argument("--cutoff-utc", help="Exact UTC cutoff, for example 2025-01-31T18:00:00Z. Overrides --since-hours")
    parser.add_argument("--top", type=int, default=50, help="Graph page size")
    parser.add_argument("--vm-name", default=os.environ.get("COMPUTERNAME", ""), help="Lab VM name used for client-side alert filtering")
    parser.add_argument("--exercise3-notes", default=str(EXERCISE3_NOTES_PATH), help="Exercise 3 hunting notes to incorporate into final report")
    parser.add_argument("--dsi-root", default=str(DEFAULT_DSI_ROOT), help="Folder to recursively inventory for DSI/eDiscovery exports")
    parser.add_argument("--dsi-case-json", default=str(DEFAULT_DSI_CASE_JSON), help="Normalized dsi_case_evidence.json to embed when present")
    parser.add_argument("--json-output", default=str(DEFAULT_JSON_OUTPUT), help="JSON output path")
    parser.add_argument("--report-output", default=str(DEFAULT_REPORT_OUTPUT), help="Text report output path")
    args = parser.parse_args()

    config = load_config(Path(args.config))
    token = acquire_token(config)
    if args.smoke_test:
        print("Token acquisition succeeded. Graph app configuration is usable for client credentials.")
        return 0

    cutoff = parse_graph_time(args.cutoff_utc) if args.cutoff_utc else utc_now() - dt.timedelta(hours=args.since_hours)
    recent_alerts = list_alerts_since(token, cutoff, max(1, min(args.top, 100)))
    lab_matches = [alert for alert in recent_alerts if is_lab_scoped_mde_alert(alert, args.vm_name)]
    dsi_inventory = inventory_dsi_exports(Path(args.dsi_root))
    exercise3_notes = read_text_if_exists(Path(args.exercise3_notes))
    dsi_case_json = load_json_if_exists(Path(args.dsi_case_json))
    write_outputs(recent_alerts, lab_matches, dsi_inventory, exercise3_notes, dsi_case_json, Path(args.json_output), Path(args.report_output), cutoff, args.vm_name)

    print(f"Retrieved {len(recent_alerts)} recent alerts_v2 objects using createdDateTime ge {graph_time(cutoff)}.")
    print(f"Matched {len(lab_matches)} recent lab-scoped Microsoft Defender for Endpoint alert(s).")
    print(f"Wrote {args.json_output}")
    print(f"Wrote {args.report_output}")

    if not lab_matches:
        print(
            "ERROR: No recent lab-scoped Microsoft Defender for Endpoint alert matched the VM/EICAR/test-file filters. "
            "Confirm the VM is onboarded to MDE, rerun Invoke-ZavaEicarTest.ps1, wait for alert ingestion, "
            "or increase --since-hours.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
'@
    }

    function New-DesktopShortcuts {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut('C:\Users\Public\Desktop\LabFiles.lnk')
            $shortcut.TargetPath = $labRoot
            $shortcut.Save()
            foreach ($link in @(@{ Name = 'Microsoft Purview Portal.url'; Url = 'https://purview.microsoft.com/' }, @{ Name = 'Microsoft Defender Portal.url'; Url = 'https://security.microsoft.com/' }, @{ Name = 'Microsoft Entra Admin Center.url'; Url = 'https://entra.microsoft.com/' })) {
                Set-Content -Path (Join-Path 'C:\Users\Public\Desktop' $link.Name) -Value "[InternetShortcut]`r`nURL=$($link.Url)`r`n" -Encoding ASCII -Force
            }
        }
        catch { Write-Log "Shortcut creation failed. $_" }
    }

    function Invoke-GraphRequest {
        param([string] $Method, [string] $Uri, [string] $Token, [object] $Body = $null)
        $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json'; 'Content-Type' = 'application/json'; 'User-Agent' = 'ZavaCloudLabsBootstrap/1.1' }
        if ($null -ne $Body) { return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body ($Body | ConvertTo-Json -Depth 20) -ErrorAction Stop }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ErrorAction Stop
    }

    function Test-IsRealBootstrapValue {
        param([string] $Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
        if ($Value -match 'GET-|GEN-|REPLACE_WITH|<|>|\$\(') { return $false }
        return $true
    }

    function Write-GraphBootstrapStatus {
        param(
            [string] $Status,
            [string] $Message,
            [string] $ConfigPath = '',
            [string] $TenantId = '',
            [string] $ClientId = '',
            [string] $ClientSecret = ''
        )
        try {
            $statusObject = [ordered]@{
                status = $Status
                message = $Message
                generatedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
                configPath = $ConfigPath
                permission = 'SecurityAlert.Read.All'
                permissionType = 'Microsoft Graph application permission'
                appRoleId = '472e4a4d-bb4a-4026-98d1-0b0d74cb74a5'
                graphEndpoint = 'https://graph.microsoft.com/v1.0/security/alerts_v2'
                credentialLocation = 'Graph client values are written only to VM-local C:\LabFiles\config.json and, when bootstrap succeeds, this VM-local GraphBootstrapStatus.json file. They are not published as ARM outputs.'
                expectation = 'Best-effort Graph app bootstrap can fail when password grant is blocked, MFA/Conditional Access is enforced, or delegated directory writes/admin consent are unavailable. If config.json is missing or authentication fails, use the manual Exercise 5 app-registration fallback.'
            }
            if ($Status -eq 'best-effort-created' -and (Test-IsRealBootstrapValue $TenantId) -and (Test-IsRealBootstrapValue $ClientId) -and (Test-IsRealBootstrapValue $ClientSecret)) {
                $statusObject['tenant_id'] = $TenantId
                $statusObject['client_id'] = $ClientId
                $statusObject['client_secret'] = $ClientSecret
                $statusObject['sensitive'] = $true
            }
            ($statusObject | ConvertTo-Json -Depth 8) | Set-Content -Path (Join-Path $labRoot 'GraphBootstrapStatus.json') -Encoding UTF8 -Force
        }
        catch { Write-Log "Could not write Graph bootstrap status file. $_" }
    }

    function Get-GraphTokenViaPasswordGrant {
        if ([string]::IsNullOrWhiteSpace($AzureUserName) -or [string]::IsNullOrWhiteSpace($AzurePassword) -or [string]::IsNullOrWhiteSpace($AzureTenantID)) { return $null }
        try {
            $tokenBody = @{ client_id = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'; resource = 'https://graph.microsoft.com'; grant_type = 'password'; username = $AzureUserName; password = $AzurePassword }
            return (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$AzureTenantID/oauth2/token" -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop).access_token
        }
        catch { Write-Log "Best-effort Graph bootstrap authentication did not succeed. This is expected in many tenants and non-blocking. $_"; return $null }
    }

    function Try-CreateGraphAlertExportApp {
        Write-Log 'Attempting best-effort Graph app/config creation. This step is non-blocking.'
        $configPath = Join-Path $labRoot 'config.json'
        if (Test-Path $configPath) { Write-GraphBootstrapStatus -Status 'skipped-existing-config' -Message 'config.json already existed. Use the Exercise 5 smoke test to verify authentication; if it fails, use the manual app-registration fallback.' -ConfigPath $configPath; return }
        if (-not (Test-IsRealBootstrapValue $AzureTenantID)) {
            $message = 'AzureTenantID did not contain a real tenant value. Bootstrap will not write placeholder Graph credentials. Use the manual Exercise 5 fallback to create config.json.'
            Write-GraphBootstrapStatus -Status 'manual-fallback-required' -Message $message -ConfigPath $configPath
            return
        }
        $token = Get-GraphTokenViaPasswordGrant
        if ([string]::IsNullOrWhiteSpace($token)) {
            $message = 'Best-effort app bootstrap could not obtain a delegated Graph token. Use the manual Exercise 5 fallback to create config.json.'
            Write-GraphBootstrapStatus -Status 'manual-fallback-required' -Message $message -ConfigPath $configPath
            return
        }
        try {
            $graphRoot = 'https://graph.microsoft.com/v1.0'
            $securityAlertReadAllAppRoleId = '472e4a4d-bb4a-4026-98d1-0b0d74cb74a5'
            $app = Invoke-GraphRequest -Method Post -Uri "$graphRoot/applications" -Token $token -Body @{ displayName = "Zava Graph Alert Export - $DeploymentID"; signInAudience = 'AzureADMyOrg' }
            $passwordResponse = Invoke-GraphRequest -Method Post -Uri "$graphRoot/applications/$($app.id)/addPassword" -Token $token -Body @{ passwordCredential = @{ displayName = 'zava-lab-client-secret'; endDateTime = (Get-Date).AddMonths(6).ToUniversalTime().ToString('o') } }
            $secret = $passwordResponse.secretText
            if (-not (Test-IsRealBootstrapValue $app.appId) -or -not (Test-IsRealBootstrapValue $secret)) { throw 'Graph application creation did not return a real application ID and one-time client secret.' }
            Invoke-GraphRequest -Method Patch -Uri "$graphRoot/applications/$($app.id)" -Token $token -Body @{ requiredResourceAccess = @(@{ resourceAppId = '00000003-0000-0000-c000-000000000000'; resourceAccess = @(@{ id = $securityAlertReadAllAppRoleId; type = 'Role' }) }) } | Out-Null
            try {
                $clientSp = Invoke-GraphRequest -Method Post -Uri "$graphRoot/servicePrincipals" -Token $token -Body @{ appId = $app.appId }
                $encodedGraphFilter = [System.Uri]::EscapeDataString("appId eq '00000003-0000-0000-c000-000000000000'")
                $graphSp = (Invoke-GraphRequest -Method Get -Uri "$graphRoot/servicePrincipals?`$filter=$encodedGraphFilter&`$select=id,appId,displayName,appRoles" -Token $token).value | Select-Object -First 1
                if ($clientSp -and $graphSp) { Invoke-GraphRequest -Method Post -Uri "$graphRoot/servicePrincipals/$($clientSp.id)/appRoleAssignments" -Token $token -Body @{ principalId = $clientSp.id; resourceId = $graphSp.id; appRoleId = $securityAlertReadAllAppRoleId } | Out-Null }
            }
            catch { Write-Log "Admin consent app role assignment failed. The app may require manual admin consent. $_" }
            $config = [ordered]@{
                tenant_id = $AzureTenantID
                client_id = $app.appId
                client_secret = $secret
                authority = "https://login.microsoftonline.com/$AzureTenantID"
                scope = 'https://graph.microsoft.com/.default'
                graphEndpoint = 'https://graph.microsoft.com/v1.0/security/alerts_v2'
                permission = 'SecurityAlert.Read.All'
                permissionType = 'Microsoft Graph application permission'
                appRoleId = $securityAlertReadAllAppRoleId
                createdByBootstrap = $true
                bootstrapStatus = 'best-effort-created'
                note = 'Graph client values are VM-local only. They are not ARM outputs. If token acquisition or Graph calls fail, complete the manual Entra app registration fallback in Exercise 5 and update this file.'
            }
            ($config | ConvertTo-Json -Depth 10) | Set-Content -Path $configPath -Encoding UTF8 -Force
            Write-GraphBootstrapStatus -Status 'best-effort-created' -Message 'config.json was created by bootstrap. Run the Exercise 5 smoke test and use the manual fallback if authentication or Graph access fails.' -ConfigPath $configPath -TenantId $AzureTenantID -ClientId $app.appId -ClientSecret $secret
        }
        catch {
            $message = "Best-effort Graph app/config creation failed. Use the manual Exercise 5 fallback to create or repair config.json. $_"
            Write-Log $message
            Write-GraphBootstrapStatus -Status 'manual-fallback-required' -Message $message -ConfigPath $configPath
        }
    }

    function New-ReadinessNotes {
        Save-TextFile -Path (Join-Path $labRoot 'README-ZavaLab.txt') -Content @"
Zava Manufacturing Insider Threat Lab - VM Bootstrap Summary
Generated: $(Get-Date -Format o)
Deployment ID: $DeploymentID
ODL ID: $ODLID
Lab admin UPN candidate: $AzureUserName
Tenant ID: $AzureTenantID

Created local assets:
- C:\LabFiles\ZavaHRData.csv
- C:\LabFiles\ZavaHRData.template.csv
- C:\LabFiles\ZavaDesignFiles\
- C:\LabFiles\Prepare-ZavaLab.ps1
- C:\LabFiles\Invoke-ZavaEicarTest.ps1
- C:\LabFiles\get_insider_alerts.py
- C:\LabFiles\GraphBootstrapStatus.json

Important lab boundaries:
- This bootstrap does not onboard the VM to Defender for Endpoint. Download the tenant-specific onboarding package from your Defender portal during Exercise 2.
- This bootstrap does not create Microsoft 365 users, assign Insider Risk Management role-group membership, create Purview policies/HR connectors, or create DSI/eDiscovery cases.
- Graph app/config creation is best effort only. Real Graph tenant_id, client_id, and client_secret values are written only to VM-local C:\LabFiles\config.json and, on successful bootstrap, C:\LabFiles\GraphBootstrapStatus.json. They are not ARM outputs.
- If C:\LabFiles\config.json is missing or authentication fails, use the manual fallback in Exercise 5.
"@
    }

    Write-Log 'Starting Zava Manufacturing Stage 1 VM bootstrap.'
    Ensure-Directory -Path $labRoot
    Ensure-Directory -Path $designRoot
    Ensure-Directory -Path (Join-Path $labRoot 'DSIExports')
    CreateCredFile
    Ensure-TrainerShadowAccount
    Ensure-ProductivityTools
    New-ZavaDesignFiles
    New-ZavaHrFiles
    New-PrepareScript
    New-EicarScript
    New-GraphStarterScript
    New-DesktopShortcuts
    Try-CreateGraphAlertExportApp
    New-ReadinessNotes
    try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force } catch { Write-Log "Execution policy update failed or was not required. $_" }
    Write-Log 'Zava Manufacturing Stage 1 VM bootstrap completed.'
}
catch { Write-Host "Bootstrap encountered an unhandled error: $_" }
finally { Stop-Transcript }

<#
.SYNOPSIS
    Validates sensitivity label configuration for the Executive Workspace libraries.

.DESCRIPTION
    Confirms that:
        - Both ExecWorkspace sensitivity labels exist in Purview
        - Both labels are included in the ExecWorkspace-LabelPolicy
        - Each library has the correct default sensitivity label assigned

    Exits with code 1 if any checks fail, blocking progression to WS-4 Power Automate flows.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.EXAMPLE
    .\03-validate-mip.ps1 `
        -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace"

.NOTES
    Requires: PnP.PowerShell, ExchangeOnlineManagement, Microsoft.Graph modules
    Run after: 02-apply-sensitivity-labels.ps1
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl
)

. "$PSScriptRoot\..\config.ps1"
# Pin EXO to ≤3.8.99 — EXO 3.9.x bundles a MSAL version that conflicts with Microsoft.Graph 2.x
Import-Module ExchangeOnlineManagement -MaximumVersion 3.8.99 -Force -ErrorAction SilentlyContinue
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = @()

function Write-Check {
    param([bool]$Pass, [string]$Message)
    if ($Pass) { Write-Host "  [PASS]  $Message" -ForegroundColor Green }
    else        { Write-Host "  [FAIL]  $Message" -ForegroundColor Red; $script:failures += $Message }
}

$ExpectedLabels = @("ExecWorkspace-Confidential", "ExecWorkspace-HighlyConfidential")
$PolicyName     = "ExecWorkspace-LabelPolicy"

$LabelMap = @(
    @{ Library = "Draft";    LabelName = "ExecWorkspace-Confidential" },
    @{ Library = "Review";   LabelName = "ExecWorkspace-Confidential" },
    @{ Library = "Approved"; LabelName = "ExecWorkspace-HighlyConfidential" },
    @{ Library = "Archive";  LabelName = "ExecWorkspace-HighlyConfidential" }
)

# --- Connect to IPPS ---
Write-Host "`nConnecting to Security & Compliance (cert auth)..." -ForegroundColor Cyan
Connect-WorkspaceIPPS

# === CHECK 1: Labels exist ===
Write-Host "`n--- Sensitivity Labels ---" -ForegroundColor Cyan
$labelIds = @{}
foreach ($labelName in $ExpectedLabels) {
    $label = Get-Label -Identity $labelName -ErrorAction SilentlyContinue
    Write-Check -Pass ($null -ne $label) -Message "Label exists: $labelName"
    if ($label) { $labelIds[$labelName] = $label.ImmutableId }
}

# === CHECK 2: Labels in policy ===
Write-Host "`n--- Label Policy ---" -ForegroundColor Cyan
$policy = Get-LabelPolicy -Identity $PolicyName -ErrorAction SilentlyContinue
Write-Check -Pass ($null -ne $policy) -Message "Policy exists: $PolicyName"

if ($policy) {
    foreach ($labelName in $ExpectedLabels) {
        $inPolicy = $policy.Labels -contains $labelName
        Write-Check -Pass $inPolicy -Message "Label '$labelName' is included in $PolicyName"
    }
}

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

# === CHECK 3: Library label assignments ===
# Uses SPO REST API for authoritative check — Graph API's defaultSensitivityLabelForLibrary
# has a read-side sync delay (can be absent for hours even when labels are correctly set).
# SPO REST is the authoritative source for this property.
Write-Host "`n--- Library Default Labels ---" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl

foreach ($entry in $LabelMap) {
    $list = Get-PnPList -Identity $entry.Library -ErrorAction SilentlyContinue
    if (-not $list) {
        Write-Check -Pass $false -Message "Library not found: $($entry.Library)"
        continue
    }

    # Query via SPO REST — authoritative for DefaultSensitivityLabelForLibrary
    $restResult = $null
    $assignedId = $null
    try {
        $restResult = Invoke-PnPSPRestMethod -Url "$SiteUrl/_api/web/lists/getbytitle('$($entry.Library)')?`$select=DefaultSensitivityLabelForLibrary"
        $assignedId = $restResult.DefaultSensitivityLabelForLibrary
    } catch {}

    $expectedId = $labelIds[$entry.LabelName]

    if ([string]::IsNullOrEmpty($assignedId)) {
        Write-Host "  [WARN]  $($entry.Library): Default label not yet visible (propagation pending — allow up to 24h from label publication)" -ForegroundColor Yellow
        $script:failures += "$($entry.Library): Label propagation pending — re-run after 24h"
    }
    else {
        Write-Check -Pass ($assignedId -eq $expectedId) -Message "$($entry.Library): Default label is '$($entry.LabelName)'"
    }
}

# === Result ===
Write-Host "`n--- Validation Result ---" -ForegroundColor Cyan
$propagationPending = @($failures | Where-Object { $_ -like "*propagation pending*" })
$realFailures       = @($failures | Where-Object { $_ -notlike "*propagation pending*" })

if ($failures.Count -eq 0) {
    Write-Host "[PASS]  All MIP checks passed. Information protection is correctly configured." -ForegroundColor Green
    Write-Host "[NEXT]  Proceed to WS-5: implement Power Automate lifecycle flows." -ForegroundColor White
}
elseif ($realFailures.Count -eq 0 -and $propagationPending.Count -gt 0) {
    Write-Host "[WARN]  Labels and policy are correctly configured. Library label assignments are pending" -ForegroundColor Yellow
    Write-Host "        SharePoint propagation (up to 24h after label publication)." -ForegroundColor Yellow
    Write-Host "        Re-run 02-apply-sensitivity-labels.ps1 and this script once propagation completes." -ForegroundColor Yellow
    Write-Host "[NEXT]  Proceed to 04-create-dlp-policies.ps1 — does not require SP propagation." -ForegroundColor White
}
else {
    Write-Host "[FAIL]  $($realFailures.Count) check(s) failed:" -ForegroundColor Red
    $realFailures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    if ($propagationPending.Count -gt 0) {
        Write-Host "`n[WARN]  $($propagationPending.Count) item(s) pending propagation:" -ForegroundColor Yellow
        $propagationPending | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    Write-Host "`nResolve all failures before proceeding to WS-5." -ForegroundColor Yellow
}

Disconnect-PnPOnline

exit $(if ($failures.Count -eq 0) { 0 } else { 1 })

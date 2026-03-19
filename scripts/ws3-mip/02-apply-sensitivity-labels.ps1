<#
.SYNOPSIS
    Applies default sensitivity labels to the four document libraries.

.DESCRIPTION
    Sets the default sensitivity label on each lifecycle library, aligned to LLD Section 6:

        Draft    → Confidential – Executive     (ExecWorkspace-Confidential)
        Review   → Confidential – Executive     (ExecWorkspace-Confidential)
        Approved → Highly Confidential – Board  (ExecWorkspace-HighlyConfidential)
        Archive  → Highly Confidential – Board  (ExecWorkspace-HighlyConfidential)

    Default labels ensure all documents uploaded to a library automatically inherit the
    correct sensitivity classification, reducing reliance on user action.

    Idempotent — existing label assignments are validated and only updated if incorrect.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\02-apply-sensitivity-labels.ps1 `
        -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace"

.NOTES
    Requires: PnP.PowerShell, ExchangeOnlineManagement, Microsoft.Graph modules
    Required roles: SharePoint Administrator + Compliance Administrator
    Prerequisites: Labels must be published and propagated (allow 24h after 01-create-sensitivity-labels.ps1)
    Run after: WS-2 validate-spo.ps1 passes
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
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

# --- Library → label mapping (LLD Section 6) ---
$LabelMap = @(
    @{ Library = "Draft";    LabelName = "ExecWorkspace-Confidential" },
    @{ Library = "Review";   LabelName = "ExecWorkspace-Confidential" },
    @{ Library = "Approved"; LabelName = "ExecWorkspace-HighlyConfidential" },
    @{ Library = "Archive";  LabelName = "ExecWorkspace-HighlyConfidential" }
)

# --- Step 1: Resolve label IDs from Purview ---
Write-Host "`nConnecting to Security & Compliance to resolve label IDs (cert auth)..." -ForegroundColor Cyan
Connect-WorkspaceIPPS
Write-Host "Connected.`n" -ForegroundColor Green

$labelIds = @{}
foreach ($entry in $LabelMap) {
    if ($labelIds.ContainsKey($entry.LabelName)) { continue }

    $label = Get-Label -Identity $entry.LabelName -ErrorAction SilentlyContinue
    if (-not $label) {
        Write-Host "[FAIL] Label not found: $($entry.LabelName)" -ForegroundColor Red
        Write-Host "       Run ws3-mip/01-create-sensitivity-labels.ps1 first and allow 24h for propagation." -ForegroundColor Yellow
        exit 1
    }
    $labelIds[$entry.LabelName] = $label.ImmutableId
    Write-Host "  Resolved: $($entry.LabelName) → $($label.ImmutableId)" -ForegroundColor DarkGray
}

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

# --- Step 2: Connect to SharePoint via PnP ---
# NOTE: We use Invoke-PnPGraphMethod for all Graph calls here instead of the Microsoft.Graph SDK
# module. PnP.PowerShell 3.x bundles Microsoft.Graph.Core 1.25.x which conflicts with
# Microsoft.Graph SDK 2.x — using PnP's own Graph caller avoids the assembly version conflict.
Write-Host "`nConnecting to SharePoint site: $SiteUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl
Write-Host "Connected.`n" -ForegroundColor Green

# --- Step 3: Apply labels ---
Write-Host "--- Applying Sensitivity Labels ---`n" -ForegroundColor Cyan
$results = @{ Applied = 0; Queued = 0; Skipped = 0; Failed = 0 }

foreach ($entry in $LabelMap) {
    $labelId = $labelIds[$entry.LabelName]

    $list = Get-PnPList -Identity $entry.Library -ErrorAction SilentlyContinue
    if (-not $list) {
        Write-Host "  [FAIL]  Library not found: $($entry.Library)" -ForegroundColor Red
        $results.Failed++
        continue
    }
    $listId   = [string]$list.Id

    # Check current label via SPO REST (more reliable than Graph for this property)
    # Graph API's defaultSensitivityLabelForLibrary has a read-side sync delay; SPO REST is authoritative.
    $restCheck    = Invoke-PnPSPRestMethod -Url "$SiteUrl/_api/web/lists/getbytitle('$($entry.Library)')?`$select=DefaultSensitivityLabelForLibrary"
    $currentLabel = $restCheck.DefaultSensitivityLabelForLibrary

    if ($currentLabel -eq $labelId) {
        Write-Host "  [SKIP]  Label already set: $($entry.Library) → $($entry.LabelName)" -ForegroundColor Yellow
        $results.Skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess("$($entry.Library)", "Apply label: $($entry.LabelName)")) {
        try {
            # Set-PnPList uses SPO CSOM/REST directly — more reliable than Graph PATCH for
            # defaultSensitivityLabelForLibrary, which is silently ignored via Graph until the
            # tenant's SPO label store fully syncs (can take 24h+ on first activation).
            Set-PnPList -Identity $entry.Library -DefaultSensitivityLabelForLibrary $labelId -ErrorAction Stop

            # Verify via SPO REST (authoritative)
            $verify = Invoke-PnPSPRestMethod -Url "$SiteUrl/_api/web/lists/getbytitle('$($entry.Library)')?`$select=DefaultSensitivityLabelForLibrary"
            if ($verify.DefaultSensitivityLabelForLibrary -eq $labelId) {
                Write-Host "  [OK]    Applied and verified: $($entry.Library) → $($entry.LabelName)" -ForegroundColor Green
                $results.Applied++
            }
            else {
                Write-Host "  [WARN]  Queued: $($entry.Library) → $($entry.LabelName)" -ForegroundColor Yellow
                Write-Host "          SPO did not persist the label. Run 00-enable-aip-integration.ps1 first." -ForegroundColor Yellow
                $results.Queued++
            }
        }
        catch {
            Write-Host "  [FAIL]  $($entry.Library): $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Applied : $($results.Applied)" -ForegroundColor Green
Write-Host "  Queued  : $($results.Queued)"  -ForegroundColor $(if ($results.Queued -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Skipped : $($results.Skipped)" -ForegroundColor Yellow
Write-Host "  Failed  : $($results.Failed)"  -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

if ($results.Failed -gt 0) {
    Write-Host "`n[WARNING] Resolve failures before proceeding to validate-mip." -ForegroundColor Red
    exit 1
}

if ($results.Queued -gt 0) {
    Write-Host "`n[WARN]  $($results.Queued) label(s) queued — SharePoint label sync pending." -ForegroundColor Yellow
    Write-Host "        Labels were accepted by the API but not yet visible in SharePoint." -ForegroundColor Yellow
    Write-Host "        Re-run this script after 24h from when labels were first published." -ForegroundColor Yellow
    Write-Host "        Proceed to 04-create-dlp-policies.ps1 (does not require SP propagation)." -ForegroundColor White
    exit 0
}

Write-Host "`n[NEXT]  Run 03-validate-mip.ps1 to confirm labels are applied before proceeding to Power Automate flows." -ForegroundColor White

Disconnect-PnPOnline

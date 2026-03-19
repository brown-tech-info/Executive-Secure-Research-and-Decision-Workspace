<#
.SYNOPSIS
    Enables all tenant-level prerequisites for SharePoint sensitivity label support (WS3).

.DESCRIPTION
    Activates the full chain of settings required before default sensitivity labels can be
    assigned to document libraries via the Graph API (defaultSensitivityLabelForLibrary).

    Without ALL of these settings, the Graph API silently accepts PATCH requests but
    SharePoint never writes the label — 02-apply-sensitivity-labels.ps1 always reports [WARN] Queued.

    Steps performed (idempotent):
        1. SPO tenant — EnableAIPIntegration     (PnP.PowerShell / SharePoint Admin)
        2. IPPS       — EnableLabelCoauth        (ExchangeOnlineManagement)
        3. IPPS       — PurviewLabelConsent      (ExchangeOnlineManagement — the critical gate)
        4. IPPS       — Execute-AzureAdLabelSync  (triggers Purview → SPO label store sync)
        5. IPPS       — EnableSensitivityLabelingForPdf (optional but recommended)

    Root-cause discovery (dev tenant, March 2026):
        - EnableAIPIntegration alone is NOT sufficient.
        - PurviewLabelConsent = False blocks the feature entirely. Graph API won't populate
          defaultSensitivityLabelForLibrary regardless of other settings.
        - EnableSpoAipMigration can only be set after EnableLabelCoauth is True in a prior
          session; it is a legacy AIP→built-in migration flag and may not be settable on
          new tenants (non-blocking for this feature).
        - Execute-AzureAdLabelSync must be re-run AFTER PurviewLabelConsent is set to True
          to trigger the initial SPO label store population.
        - After all steps: allow 15–30 minutes before re-running 02-apply-sensitivity-labels.ps1.

    Microsoft reference:
        https://learn.microsoft.com/en-us/microsoft-365/compliance/sensitivity-labels-sharepoint-onedrive-files

.PARAMETER WhatIf
    Preview the change without applying it.

.EXAMPLE
    .\00-enable-aip-integration.ps1
    .\00-enable-aip-integration.ps1 -WhatIf

.NOTES
    Requires: PnP.PowerShell, ExchangeOnlineManagement (≤3.8.99)
    Required roles: SharePoint Administrator + Compliance Administrator
    Run before: 01-create-sensitivity-labels.ps1 (or at any point before 02-apply-sensitivity-labels.ps1)
    After enabling: Wait 15–30 minutes before re-running 02-apply-sensitivity-labels.ps1.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

. "$PSScriptRoot\..\config.ps1"
# Pin EXO to ≤3.8.99 — EXO 3.9.x bundles a MSAL version that conflicts with Microsoft.Graph 2.x
Import-Module ExchangeOnlineManagement -MaximumVersion 3.8.99 -Force -ErrorAction SilentlyContinue
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$anyChange = $false

# ---------------------------------------------------------------------------
# Step 1: SPO tenant — EnableAIPIntegration
# ---------------------------------------------------------------------------
Write-Host "`n[Step 1] SharePoint Admin: EnableAIPIntegration" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $script:AdminUrl
$tenantSettings = Get-PnPTenant
$aipEnabled = $tenantSettings.EnableAIPIntegration

if ($aipEnabled -eq $true) {
    Write-Host "  [SKIP] EnableAIPIntegration already True" -ForegroundColor Yellow
} else {
    if ($PSCmdlet.ShouldProcess("SPO Tenant", "Set EnableAIPIntegration = True")) {
        Set-PnPTenant -EnableAIPIntegration $true
        Write-Host "  [OK] EnableAIPIntegration = True" -ForegroundColor Green
        $anyChange = $true
    }
}
Disconnect-PnPOnline

# ---------------------------------------------------------------------------
# Step 2–5: IPPS (Security & Compliance) settings
# ---------------------------------------------------------------------------
Write-Host "`n[Step 2-5] Security & Compliance: PolicyConfig + Label Sync" -ForegroundColor Cyan
Connect-WorkspaceIPPS

$cfg = Get-PolicyConfig

# Step 2: EnableLabelCoauth
if ($cfg.EnableLabelCoauth -eq $true) {
    Write-Host "  [SKIP] EnableLabelCoauth already True" -ForegroundColor Yellow
} else {
    if ($PSCmdlet.ShouldProcess("PolicyConfig", "Set EnableLabelCoauth = True")) {
        try {
            Set-PolicyConfig -EnableLabelCoauth $true -ErrorAction Stop
            Write-Host "  [OK] EnableLabelCoauth = True" -ForegroundColor Green
            $anyChange = $true
            # Refresh config — subsequent calls depend on this being persisted
            $cfg = Get-PolicyConfig
        } catch { Write-Host "  [WARN] EnableLabelCoauth: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

# Step 3: PurviewLabelConsent — the critical gate for defaultSensitivityLabelForLibrary
if ($cfg.PurviewLabelConsent -eq $true) {
    Write-Host "  [SKIP] PurviewLabelConsent already True" -ForegroundColor Yellow
} else {
    if ($PSCmdlet.ShouldProcess("PolicyConfig", "Set PurviewLabelConsent = True")) {
        try {
            Set-PolicyConfig -PurviewLabelConsent $true -ErrorAction Stop
            Write-Host "  [OK] PurviewLabelConsent = True" -ForegroundColor Green
            $anyChange = $true
        } catch { Write-Host "  [WARN] PurviewLabelConsent: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

# Step 4: EnableSensitivityLabelingForPdf (optional, non-blocking)
if ($cfg.EnableSensitivityLabelingForPdf -eq $true) {
    Write-Host "  [SKIP] EnableSensitivityLabelingForPdf already True" -ForegroundColor Yellow
} else {
    if ($PSCmdlet.ShouldProcess("PolicyConfig", "Set EnableSensitivityLabelingForPdf = True")) {
        try {
            Set-PolicyConfig -EnableSensitivityLabelingForPdf $true -ErrorAction Stop
            Write-Host "  [OK] EnableSensitivityLabelingForPdf = True" -ForegroundColor Green
        } catch { Write-Host "  [WARN] EnableSensitivityLabelingForPdf: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

# Step 5: EnableSpoAipMigration (legacy AIP→built-in migration flag; may fail on new tenants — non-blocking)
if ($cfg.EnableSpoAipMigration -eq $true) {
    Write-Host "  [SKIP] EnableSpoAipMigration already True" -ForegroundColor Yellow
} else {
    if ($PSCmdlet.ShouldProcess("PolicyConfig", "Set EnableSpoAipMigration = True")) {
        try {
            Set-PolicyConfig -EnableSpoAipMigration $true -ErrorAction Stop
            Write-Host "  [OK] EnableSpoAipMigration = True" -ForegroundColor Green
        } catch {
            Write-Host "  [INFO] EnableSpoAipMigration skipped (non-blocking on new tenants): $($_.Exception.Message.Split('|')[1])" -ForegroundColor DarkGray
        }
    }
}

# Step 6: Execute-AzureAdLabelSync — triggers Purview → SPO label store sync
# Must run AFTER PurviewLabelConsent is True for the sync to populate SPO's label store.
if ($PSCmdlet.ShouldProcess("Purview", "Execute-AzureAdLabelSync (trigger SPO label store population)")) {
    try {
        Execute-AzureAdLabelSync -ErrorAction Stop
        Write-Host "  [OK] Execute-AzureAdLabelSync triggered" -ForegroundColor Green
        $anyChange = $true
    } catch { Write-Host "  [WARN] AzureAdLabelSync: $($_.Exception.Message)" -ForegroundColor Yellow }
}

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Final state verification
# ---------------------------------------------------------------------------
Write-Host "`n--- Final PolicyConfig State ---" -ForegroundColor Cyan
Connect-WorkspaceIPPS
$final = Get-PolicyConfig
Write-Host "  PurviewLabelConsent          : $($final.PurviewLabelConsent)"   -ForegroundColor $(if ($final.PurviewLabelConsent) { 'Green' } else { 'Red' })
Write-Host "  EnableLabelCoauth            : $($final.EnableLabelCoauth)"     -ForegroundColor $(if ($final.EnableLabelCoauth) { 'Green' } else { 'Yellow' })
Write-Host "  EnableSpoAipMigration        : $($final.EnableSpoAipMigration)" -ForegroundColor $(if ($final.EnableSpoAipMigration) { 'Green' } else { 'DarkGray' })
Write-Host "  EnableSensitivityLabelingForPdf: $($final.EnableSensitivityLabelingForPdf)" -ForegroundColor $(if ($final.EnableSensitivityLabelingForPdf) { 'Green' } else { 'Yellow' })
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

if ($anyChange) {
    Write-Host "`n[NOTE] Changes were applied. Allow 15–30 minutes for SharePoint's label store to populate." -ForegroundColor Yellow
    Write-Host "       Then re-run: .\02-apply-sensitivity-labels.ps1 -SiteUrl '$($script:SiteUrl)'" -ForegroundColor White
} else {
    Write-Host "`n[OK] All prerequisites already satisfied." -ForegroundColor Green
    Write-Host "     If 02-apply-sensitivity-labels.ps1 still reports Queued, wait 15–30 min and retry." -ForegroundColor White
}

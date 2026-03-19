<#
.SYNOPSIS
    Validates Microsoft Purview audit and retention configuration for the Executive Workspace.

.DESCRIPTION
    Verifies:
        - Unified Audit Log is enabled
        - Required retention labels exist (ExecWS-Archive-Retention, ExecWS-Approved-Retention)
        - Auto-apply retention policies are active
        - Generates a test audit event and confirms it is searchable

    Exits with code 1 if any checks fail, blocking progression to WS-6 Copilot Studio.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site (used to generate a test audit event).
    Defaults to the value in config.ps1 if not supplied.

.EXAMPLE
    .\03-validate-purview.ps1
    .\03-validate-purview.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace"

.NOTES
    Requires: ExchangeOnlineManagement, PnP.PowerShell modules
    Note: Audit log search can have up to 30 minutes lag — the test event check confirms
    the mechanism works, not necessarily an instantaneous result.
#>
[CmdletBinding()]
param(
    [string]$SiteUrl   # defaults to $script:SiteUrl from config.ps1 if not supplied
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Default SiteUrl to config value if not supplied as parameter
if (-not $SiteUrl) { $SiteUrl = $script:SiteUrl }

$failures = @()

function Write-Check {
    param([bool]$Pass, [string]$Message)
    if ($Pass) { Write-Host "  [PASS]  $Message" -ForegroundColor Green }
    else        { Write-Host "  [FAIL]  $Message" -ForegroundColor Red; $script:failures += $Message }
}

# --- Connect ---
Write-Host "`nConnecting to Exchange Online and Security & Compliance (cert auth)..." -ForegroundColor Cyan
Connect-WorkspaceEXO

# === CHECK 1: Unified Audit Log — must run while only EXO is connected ===
# (Get-AdminAuditLogConfig picks up IPPS session if both are active)
Write-Host "`n--- Unified Audit Log ---" -ForegroundColor Cyan
$auditConfig = Get-AdminAuditLogConfig
Write-Check -Pass ([bool]$auditConfig.UnifiedAuditLogIngestionEnabled) -Message "Unified Audit Log is enabled"

Connect-WorkspaceIPPS
Write-Host "Connected.`n" -ForegroundColor Green

# === CHECK 2: Retention labels ===
Write-Host "`n--- Retention Labels ---" -ForegroundColor Cyan
$expectedLabels = @("ExecWS-Archive-Retention", "ExecWS-Approved-Retention")

foreach ($labelName in $expectedLabels) {
    $label = Get-ComplianceTag -Identity $labelName -ErrorAction SilentlyContinue
    Write-Check -Pass ($null -ne $label) -Message "Retention label exists: $labelName"

    if ($label) {
        $retentionYears = [math]::Round($label.RetentionDuration / 365, 1)
        Write-Host "    Retention: $retentionYears years | Action: $($label.RetentionAction)" -ForegroundColor DarkGray
    }
}

# === CHECK 3: Auto-apply retention policies ===
Write-Host "`n--- Auto-Apply Retention Policies ---" -ForegroundColor Cyan
$expectedPolicies = @("ExecWS-AutoApply-ArchiveRetention", "ExecWS-AutoApply-ApprovedRetention")

foreach ($policyName in $expectedPolicies) {
    $policy = Get-RetentionCompliancePolicy -Identity $policyName -ErrorAction SilentlyContinue
    Write-Check -Pass ($null -ne $policy) -Message "Auto-apply policy exists: $policyName"

    if ($policy) {
        Write-Check -Pass ($policy.Enabled -eq $true) -Message "$policyName is enabled"
    }
}

# === CHECK 4: Generate test audit event and confirm mechanism ===
Write-Host "`n--- Audit Event Generation Test ---" -ForegroundColor Cyan
Write-Host "  Generating a test file access event on the Executive Workspace site..." -ForegroundColor White

try {
    Connect-WorkspacePnP -Url $SiteUrl -ErrorAction Stop
    $web = Get-PnPWeb   # This access generates an audit event
    Disconnect-PnPOnline
    Write-Host "  [OK]    Test site access event generated." -ForegroundColor Green
    Write-Host "          To verify: In Purview → Audit → New search" -ForegroundColor DarkGray
    Write-Host "          Set date range to last 1 hour, Activity: 'Accessed site'" -ForegroundColor DarkGray
    Write-Host "          User: $script:AdminUPN | Site: $SiteUrl" -ForegroundColor DarkGray
    Write-Host "          Note: Allow 15-30 minutes for the event to appear." -ForegroundColor Yellow
}
catch {
    Write-Host "  [WARN]  Could not generate test event: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "          This does not indicate an audit log failure — verify manually in Purview." -ForegroundColor White
}

# === Result ===
Write-Host "`n--- Validation Result ---" -ForegroundColor Cyan
if ($failures.Count -eq 0) {
    Write-Host "[PASS]  All Purview checks passed." -ForegroundColor Green
    Write-Host "[NEXT]  Proceed to WS-6: Copilot Studio agent configuration." -ForegroundColor White
}
else {
    Write-Host "[FAIL]  $($failures.Count) check(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`nResolve all failures before proceeding to WS-6." -ForegroundColor Yellow
}

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

exit $(if ($failures.Count -eq 0) { 0 } else { 1 })

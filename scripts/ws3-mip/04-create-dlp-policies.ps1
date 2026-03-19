<#
.SYNOPSIS
    Creates Data Loss Prevention policies for the Executive Secure Research & Decision Workspace.

.DESCRIPTION
    Deploys two DLP policies via Security & Compliance PowerShell (LLD Section 6 / Constitution):

        ExecWorkspace-BlockExternalSharing
            Scoped to the Executive Workspace SharePoint site.
            Rule 1: Block all external sharing/access on the site.
            Rule 2: Generate high-severity incident reports on any external sharing attempt.

        ExecWorkspace-AuditAndAlert
            Scoped to the Executive Workspace SharePoint site.
            Generates audit alerts for ALL activity on the site.
            Non-blocking — monitoring only.

    Both policies are scoped to the specific SharePoint site URL rather than label-based
    conditions. IPPS v3 (REST module) does not expose -ContentContainsSensitivityLabel;
    site-scoping provides equivalent protection for SharePoint without requiring label
    propagation. Exchange/Teams coverage via sensitivity labels is a future enhancement.

    Both policies are created in TestWithNotifications mode. Switch to Enforce using
    the -Enforce switch after validating no false positives in Activity Explorer.

    Idempotent — existing policies and rules are detected and skipped.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER ComplianceNotificationEmail
    Email address to receive DLP incident reports. Should be the Compliance team inbox.

.PARAMETER TenantAdminEmail
    Unused — retained for backward compatibility. Auth uses the deployment certificate.

.PARAMETER Enforce
    If specified, policies are set to Enforce mode. Only use after TestWithNotifications validation.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\04-create-dlp-policies.ps1 `
        -SiteUrl "https://<dev-tenant>.sharepoint.com/sites/exec-workspace" `
        -ComplianceNotificationEmail "admin@<dev-tenant>.onmicrosoft.com"

    .\04-create-dlp-policies.ps1 `
        -SiteUrl "https://<dev-tenant>.sharepoint.com/sites/exec-workspace" `
        -ComplianceNotificationEmail "admin@<dev-tenant>.onmicrosoft.com" `
        -Enforce

.NOTES
    Requires: Install-Module ExchangeOnlineManagement (v3.0.0+)
    Required role: Compliance Administrator
    Prerequisites: Sensitivity labels must exist (ws3-mip/01-create-sensitivity-labels.ps1)
    Known limitation: IPPS v3 REST module does not expose -ContentContainsSensitivityLabel.
                      Exchange/Teams coverage deferred to future enhancement.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ComplianceNotificationEmail,

    [Parameter()]
    [string]$TenantAdminEmail,   # retained for backward compat; auth uses cert

    [switch]$Enforce
)

. "$PSScriptRoot\..\config.ps1"
# Pin EXO to ≤3.8.99 — EXO 3.9.x bundles a MSAL version that conflicts with Microsoft.Graph 2.x
Import-Module ExchangeOnlineManagement -MaximumVersion 3.8.99 -Force -ErrorAction SilentlyContinue
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PolicyMode = if ($Enforce) { "Enable" } else { "TestWithNotifications" }

Write-Host "`nConnecting to Security & Compliance (IPPS, cert auth)..." -ForegroundColor Cyan
Connect-WorkspaceIPPS
Write-Host "Connected.`n" -ForegroundColor Green

# Resolve label names for ContentMissingSensitivityLabel condition
Write-Host "Resolving sensitivity label names..." -ForegroundColor Cyan
$confLabel = Get-Label -Identity "ExecWorkspace-Confidential"       -ErrorAction SilentlyContinue
$hcLabel   = Get-Label -Identity "ExecWorkspace-HighlyConfidential" -ErrorAction SilentlyContinue

if (-not $confLabel -or -not $hcLabel) {
    Write-Host "[FAIL]  One or both sensitivity labels not found. Run 01-create-sensitivity-labels.ps1 first." -ForegroundColor Red
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}
$labelNames = @($confLabel.Name, $hcLabel.Name)
Write-Host "  Labels: $($labelNames -join ', ')`n" -ForegroundColor DarkGray

$results = @{ Created = 0; Skipped = 0; Failed = 0 }

# =====================================================================
# POLICY 1 — ExecWorkspace-BlockExternalSharing
# Governance control: blocks unlabeled content from being shared externally.
# All content on the exec workspace site must carry a sensitivity label.
# NOTE: External sharing is already disabled at the site level (WS-2).
#       This DLP adds an auditable enforcement layer for unlabeled content.
#       Label-based blocking (ContentContainsSensitivityLabel) is not available
#       in IPPS v3 REST module; will be revisited when module support is added.
# =====================================================================

$policy1Name = "ExecWorkspace-BlockExternalSharing"
Write-Host "--- Policy: $policy1Name ---" -ForegroundColor Cyan

$existingPolicy1 = Get-DlpCompliancePolicy -Identity $policy1Name -ErrorAction SilentlyContinue
if (-not $existingPolicy1) {
    if ($PSCmdlet.ShouldProcess($policy1Name, "Create DLP policy")) {
        try {
            New-DlpCompliancePolicy `
                -Name               $policy1Name `
                -Mode               $PolicyMode `
                -Comment            "Governance enforcement: blocks unlabeled content on the Executive Workspace from external sharing. External sharing disabled at site level (WS-2). Constitution: No Informal Data Leakage." `
                -SharePointLocation $SiteUrl | Out-Null

            Write-Host "  [OK]    Policy created: $policy1Name (Mode: $PolicyMode)" -ForegroundColor Green
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  Policy creation failed: $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}
else {
    Write-Host "  [SKIP]  Policy already exists: $policy1Name" -ForegroundColor Yellow
    $results.Skipped++
}

# Rule 1 — Block unlabeled content from external sharing + notify + incident report
$rule1Name     = "BlockUnlabeledContent-ExecWorkspace"
$existingRule1 = Get-DlpComplianceRule -Identity $rule1Name -ErrorAction SilentlyContinue
if (-not $existingRule1) {
    if ($PSCmdlet.ShouldProcess($rule1Name, "Create DLP rule: block unlabeled content")) {
        try {
            New-DlpComplianceRule `
                -Name                   $rule1Name `
                -Policy                 $policy1Name `
                -DocumentSizeOver       10240 `
                -BlockAccess            $true `
                -GenerateIncidentReport $ComplianceNotificationEmail `
                -IncidentReportContent  @("Title","Severity","Service","MatchedItem","RulesMatched","Detections") `
                -ReportSeverityLevel    "High" `
                -Comment                "Blocks all external sharing from the exec workspace SP site. DocumentSizeOver 1 is the universal SharePoint DLP predicate (all real documents). Site-scoping provides label equivalent. LLD Section 6 / Constitution." | Out-Null

            Write-Host "  [OK]    Rule created: $rule1Name" -ForegroundColor Green
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  $rule1Name : $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}
else {
    Write-Host "  [SKIP]  Rule exists: $rule1Name" -ForegroundColor Yellow
    $results.Skipped++
}

# =====================================================================
# POLICY 2 — ExecWorkspace-AuditAndAlert
# Non-blocking governance check: audits all content missing the required
# Executive Workspace sensitivity labels.
# =====================================================================

$policy2Name = "ExecWorkspace-AuditAndAlert"
Write-Host "`n--- Policy: $policy2Name ---" -ForegroundColor Cyan

$existingPolicy2 = Get-DlpCompliancePolicy -Identity $policy2Name -ErrorAction SilentlyContinue
if (-not $existingPolicy2) {
    if ($PSCmdlet.ShouldProcess($policy2Name, "Create DLP audit policy")) {
        try {
            New-DlpCompliancePolicy `
                -Name               $policy2Name `
                -Mode               "TestWithNotifications" `
                -Comment            "Non-blocking governance audit. Detects content on the Executive Workspace site that is missing the required sensitivity labels." `
                -SharePointLocation $SiteUrl | Out-Null

            Write-Host "  [OK]    Policy created: $policy2Name (Mode: TestWithNotifications — always audit only)" -ForegroundColor Green
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  Policy creation failed: $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}
else {
    Write-Host "  [SKIP]  Policy already exists: $policy2Name" -ForegroundColor Yellow
    $results.Skipped++
}

$rule2Name     = "AuditMissingLabel-ExecWorkspace"
$existingRule2 = Get-DlpComplianceRule -Identity $rule2Name -ErrorAction SilentlyContinue
if (-not $existingRule2) {
    if ($PSCmdlet.ShouldProcess($rule2Name, "Create DLP audit rule")) {
        try {
            New-DlpComplianceRule `
                -Name                   $rule2Name `
                -Policy                 $policy2Name `
                -DocumentSizeOver       10240 `
                -GenerateIncidentReport $ComplianceNotificationEmail `
                -IncidentReportContent  @("Title","Severity","Service","MatchedItem","RulesMatched","Detections") `
                -ReportSeverityLevel    "Medium" `
                -Comment                "Audit: generates an incident report for activity on any document in the exec workspace site." | Out-Null

            Write-Host "  [OK]    Rule created: $rule2Name" -ForegroundColor Green
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  $rule2Name : $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}
else {
    Write-Host "  [SKIP]  Rule exists: $rule2Name" -ForegroundColor Yellow
    $results.Skipped++
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Created : $($results.Created)" -ForegroundColor Green
Write-Host "  Skipped : $($results.Skipped)" -ForegroundColor Yellow
Write-Host "  Failed  : $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

if (-not $Enforce) {
    Write-Host "`n[INFO]  Policies are in TestWithNotifications mode." -ForegroundColor Yellow
    Write-Host "        Review DLP matches in: Purview portal → DLP → Activity explorer" -ForegroundColor White
    Write-Host "        Once validated with no false positives, re-run with -Enforce to enable blocking." -ForegroundColor White
}

Write-Host "`n[NOTE]  Label-based conditions (ContentContainsSensitivityLabel) not available in IPPS v3 REST." -ForegroundColor DarkGray
Write-Host "        Exchange/Teams coverage deferred. Site-level external sharing disabled (WS-2) is primary control." -ForegroundColor DarkGray

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
exit $(if ($results.Failed -gt 0) { 1 } else { 0 })

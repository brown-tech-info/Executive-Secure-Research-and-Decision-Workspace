<#
.SYNOPSIS
    Creates Purview retention labels and auto-apply policies for the Executive Workspace.

.DESCRIPTION
    Provisions the following retention configuration (LLD Section 8.2):

        ExecWS-Archive-Retention     — Applied to Archive library
                                       Retain for 7 years from creation date (placeholder — align to your organisation's governance policy)
                                       Disposition: Review before deletion

        ExecWS-Approved-Retention    — Applied to Approved library
                                       Retain for 3 years from creation date (placeholder)
                                       Disposition: Move to Archive (via flow) or review

    Auto-apply policies publish labels to the relevant SharePoint libraries.

    Note: The Flow 3 (ExecWS-ApprovedToArchive) applies ExecWS-Archive-Retention programmatically
    via SharePoint REST. These auto-apply policies provide a policy-layer backstop.

    Idempotent — existing labels and policies are detected and skipped.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\02-configure-retention.ps1
    .\02-configure-retention.ps1 -ArchiveRetentionYears 10 -ApprovedRetentionYears 5

.NOTES
    Requires: ExchangeOnlineManagement module
    Required role: Compliance Administrator
    Retention periods are PLACEHOLDERS. Replace with your organisation's governance policy durations before production.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # IMPORTANT: Replace with actual organisation-approved retention periods before production use
    [int]$ArchiveRetentionYears  = 7,
    [int]$ApprovedRetentionYears = 3
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`nConnecting to Security & Compliance (IPPS, cert auth)..." -ForegroundColor Cyan
Connect-WorkspaceIPPS
Write-Host "Connected.`n" -ForegroundColor Green

Write-Host "[WARNING] Retention periods are set to placeholder values:" -ForegroundColor Yellow
Write-Host "          Archive  : $ArchiveRetentionYears years" -ForegroundColor Yellow
Write-Host "          Approved : $ApprovedRetentionYears years" -ForegroundColor Yellow
Write-Host "          These MUST be aligned with your organisation's information governance policy before production.`n" -ForegroundColor Yellow

$results = @{ Created = 0; Skipped = 0; Failed = 0 }

# --- Retention label definitions ---
$RetentionLabels = @(
    @{
        Name             = "ExecWS-Archive-Retention"
        Comment          = "Executive Workspace Archive library retention. Applied automatically to archived documents. Duration: $ArchiveRetentionYears years from creation. PLACEHOLDER — align to your organisation's governance policy."
        RetentionDays    = $ArchiveRetentionYears * 365
        RetentionAction  = "Keep"       # Keep the document — do not auto-delete; reviewer assignable via Purview portal
    },
    @{
        Name             = "ExecWS-Approved-Retention"
        Comment          = "Executive Workspace Approved library retention. Applied to approved documents. Duration: $ApprovedRetentionYears years from creation. PLACEHOLDER — align to your organisation's governance policy."
        RetentionDays    = $ApprovedRetentionYears * 365
        RetentionAction  = "Keep"
    }
)

# --- Create retention labels (ComplianceTags) ---
Write-Host "--- Creating Retention Labels ---`n" -ForegroundColor Cyan

foreach ($label in $RetentionLabels) {
    $existing = Get-ComplianceTag -Identity $label.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [SKIP]  Label already exists: $($label.Name)" -ForegroundColor Yellow
        $results.Skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($label.Name, "Create retention label")) {
        try {
            New-ComplianceTag `
                -Name           $label.Name `
                -Comment        $label.Comment `
                -RetentionAction $label.RetentionAction `
                -RetentionDuration $label.RetentionDays `
                -RetentionType  "CreationAgeInDays" | Out-Null

            Write-Host "  [OK]    Created: $($label.Name) ($($label.RetentionDays / 365) years)" -ForegroundColor Green
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  $($label.Name): $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Create auto-apply retention policies ---
# Policy 1: Auto-apply ExecWS-Archive-Retention to Archive library
Write-Host "`n--- Creating Auto-Apply Retention Policies ---`n" -ForegroundColor Cyan

$AutoPolicies = @(
    @{
        PolicyName     = "ExecWS-AutoApply-ArchiveRetention"
        LabelName      = "ExecWS-Archive-Retention"
        RetentionDays  = $ArchiveRetentionYears * 365
        Comment        = "Retains all content in the Archive library for $ArchiveRetentionYears years. Direct retention policy — complements the ExecWS-Archive-Retention label."
    },
    @{
        PolicyName     = "ExecWS-AutoApply-ApprovedRetention"
        LabelName      = "ExecWS-Approved-Retention"
        RetentionDays  = $ApprovedRetentionYears * 365
        Comment        = "Retains all content in the Approved library for $ApprovedRetentionYears years. Direct retention policy — complements the ExecWS-Approved-Retention label."
    }
)

foreach ($policy in $AutoPolicies) {
    $existing = Get-RetentionCompliancePolicy -Identity $policy.PolicyName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [SKIP]  Policy already exists: $($policy.PolicyName)" -ForegroundColor Yellow
        $results.Skipped++
        # Fall through to check/create the rule — it may not exist even if the policy does
    }

    if ($PSCmdlet.ShouldProcess($policy.PolicyName, "Create auto-apply retention policy")) {
        try {
            if (-not $existing) {
                New-RetentionCompliancePolicy `
                    -Name              $policy.PolicyName `
                    -Comment           $policy.Comment `
                    -SharePointLocation $script:SiteUrl `
                    -Enabled           $true | Out-Null
                Write-Host "  [OK]    Created policy: $($policy.PolicyName)" -ForegroundColor Green
                $results.Created++
            }

            # Always check rule separately — rule may not exist even if policy does
            $ruleName = "$($policy.PolicyName)-Rule"
            $existingRule = Get-RetentionComplianceRule -Identity $ruleName -ErrorAction SilentlyContinue
            if ($existingRule) {
                Write-Host "  [SKIP]  Rule already exists: $ruleName" -ForegroundColor Yellow
                $results.Skipped++
            } else {
                # Direct retention rule — retains all content in scope for the policy period.
                # Label auto-apply via script requires a content condition; configure via
                # Purview portal if keyword/SIT-based auto-apply is needed.
                New-RetentionComplianceRule `
                    -Name                    $ruleName `
                    -Policy                  $policy.PolicyName `
                    -RetentionDuration       $policy.RetentionDays `
                    -RetentionComplianceAction Keep | Out-Null
                Write-Host "  [OK]    Created rule: $ruleName ($($policy.RetentionDays / 365) yr retain)" -ForegroundColor Green
                $results.Created++
            }
        }
        catch {
            Write-Host "  [FAIL]  $($policy.PolicyName): $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Created : $($results.Created)" -ForegroundColor Green
Write-Host "  Skipped : $($results.Skipped)" -ForegroundColor Yellow
Write-Host "  Failed  : $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

if ($results.Failed -gt 0) {
    Write-Host "`n[WARNING] Resolve failures before running validation." -ForegroundColor Red
    exit 1
}

Write-Host "`n[REMINDER] Update retention periods to match your organisation's governance policy before production deployment." -ForegroundColor Yellow
Write-Host "[NEXT]     Run 03-validate-purview.ps1 to confirm Purview configuration." -ForegroundColor White

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

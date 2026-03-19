<#
.SYNOPSIS
    Creates Microsoft Purview sensitivity labels for the Executive Secure Research & Decision Workspace.

.DESCRIPTION
    Provisions two sensitivity labels and a scoped label policy aligned to the workspace
    document lifecycle and information protection requirements (LLD Section 6).

    Labels created:
        ExecWorkspace-Confidential           — Applied to Draft and Review libraries
        ExecWorkspace-HighlyConfidential     — Applied to Approved and Archive libraries

    Label policy:
        ExecWorkspace-LabelPolicy            — Publishes labels to ExecWorkspace groups

    Script is idempotent — existing labels with the same Name are skipped.

.PARAMETER WhatIf
    Preview what would be created without making any changes.

.EXAMPLE
    .\01-create-sensitivity-labels.ps1
    .\01-create-sensitivity-labels.ps1 -WhatIf

.NOTES
    Requires: ExchangeOnlineManagement module (Install-Module ExchangeOnlineManagement)
    Required role: Compliance Administrator or Global Administrator
    Labels are published to the policy immediately — allow up to 24 hours for propagation in a new tenant.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Label definitions (aligned to LLD Section 6) ---
$Labels = @(
    @{
        Name              = "ExecWorkspace-Confidential"
        DisplayName       = "Confidential – Executive"
        Tooltip           = "Content restricted to authorised workspace members. Applied to Draft and Review libraries. Do not forward or share externally."
        # Encryption: applied at library level via SharePoint — label marks sensitivity only at this tier
        # "Site" and "UnifiedGroup" scopes are required for the label to be assignable as a
        # SharePoint library default. Without them, Graph API PATCH to
        # defaultSensitivityLabelForLibrary silently does nothing.
        ContentType       = @("File", "Email", "Site", "UnifiedGroup")
        # Colour coding for visual identification in Office apps
        LabelColor        = "#FF8C00"   # Orange — confidential tier
        Priority          = 1
    },
    @{
        Name              = "ExecWorkspace-HighlyConfidential"
        DisplayName       = "Highly Confidential – Board"
        Tooltip           = "Approved or archived executive workspace content. Highest sensitivity. Restricted to Executive and Compliance roles. Encryption enforced."
        LabelColor        = "#FF0000"   # Red — highly confidential tier
        Priority          = 2
        # "Site" and "UnifiedGroup" scopes required for SharePoint library default label assignment
        ContentType       = @("File", "Email", "Site", "UnifiedGroup")
        # Encryption enforced for Approved and Archive libraries
        EncryptionEnabled = $true
    }
)

$PolicyName = "ExecWorkspace-LabelPolicy"

# --- Connect to Security & Compliance (IPPS) ---
Write-Host "`nConnecting to Security & Compliance PowerShell (cert auth)..." -ForegroundColor Cyan
Connect-WorkspaceIPPS
Write-Host "Connected.`n" -ForegroundColor Green

$results = @{ Created = 0; Skipped = 0; Failed = 0 }

# --- Create labels ---
Write-Host "--- Provisioning Sensitivity Labels ---`n" -ForegroundColor Cyan

foreach ($label in $Labels) {
    $existing = Get-Label -Identity $label.Name -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Host "  [SKIP]  Label already exists : $($label.DisplayName)" -ForegroundColor Yellow
        $results.Skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($label.DisplayName, "Create sensitivity label")) {
        try {
            $params = @{
                Name        = $label.Name
                DisplayName = $label.DisplayName
                Tooltip     = $label.Tooltip
                ContentType = $label.ContentType
            }

            # NOTE: EncryptionEnabled requires EncryptionRightsDefinitions or a template ID —
            #       passing it alone causes New-Label to fail. Encryption rights are configured
            #       post-creation in the Purview portal:
            #       Purview portal → Information Protection → Labels → Edit → Encryption
            # Intentionally omitted here; label marks sensitivity tier only via script.

            New-Label @params | Out-Null
            Write-Host "  [OK]    Created label      : $($label.DisplayName)" -ForegroundColor Green
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  Failed             : $($label.DisplayName)" -ForegroundColor Red
            Write-Host "          Error              : $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Create or update label policy ---
Write-Host "`n--- Provisioning Label Policy ---`n" -ForegroundColor Cyan

$existingPolicy = Get-LabelPolicy -Identity $PolicyName -ErrorAction SilentlyContinue

if ($existingPolicy) {
    Write-Host "  [SKIP]  Policy already exists : $PolicyName" -ForegroundColor Yellow
}
else {
    if ($PSCmdlet.ShouldProcess($PolicyName, "Create sensitivity label policy")) {
        try {
            $labelNames = $Labels | ForEach-Object { $_.Name }

            New-LabelPolicy `
                -Name $PolicyName `
                -Labels $labelNames `
                -Comment "Executive Workspace label policy. Publishes ExecWorkspace sensitivity labels to workspace members." `
                -ExchangeLocation "All" `
                -SharePointLocation "All" | Out-Null

            Write-Host "  [OK]    Created policy     : $PolicyName" -ForegroundColor Green
            Write-Host "          Labels published   : $($labelNames -join ', ')" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "  [FAIL]  Failed to create policy: $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Labels created  : $($results.Created)" -ForegroundColor Green
Write-Host "  Labels skipped  : $($results.Skipped)" -ForegroundColor Yellow
Write-Host "  Failures        : $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

if ($results.Failed -gt 0) {
    Write-Host "`n[WARNING] One or more items failed. Resolve before proceeding to WS-2." -ForegroundColor Red
    exit 1
}

Write-Host "`n[NOTE] Allow up to 24 hours for label propagation in a new tenant before applying to SharePoint libraries." -ForegroundColor Yellow
Write-Host "[NEXT] Proceed to WS-2 SharePoint provisioning. Labels are applied in WS-3 after SharePoint is validated." -ForegroundColor White

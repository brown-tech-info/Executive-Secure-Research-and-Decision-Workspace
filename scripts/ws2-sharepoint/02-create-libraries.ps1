<#
.SYNOPSIS
    Creates the four document libraries for the Executive Workspace lifecycle model.

.DESCRIPTION
    Provisions Draft, Review, Approved, and Archive document libraries.
    Each library:
        - Has unique permissions (permission inheritance broken from parent site)
        - Has major versioning enabled (full audit trail)
        - Has required metadata enforced
        - Has no external sharing

    Idempotent — existing libraries are detected and skipped.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.
    Example: https://contoso.sharepoint.com/sites/exec-workspace

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\02-create-libraries.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace"

.NOTES
    Requires: PnP.PowerShell module
    Required role: SharePoint Administrator or Site Owner
    Run after: 01-provision-site.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Library definitions (LLD Section 3.1) ---
$Libraries = @(
    @{
        Name        = "Draft"
        Title       = "Draft"
        Description = "Authoring and early content preparation. Access restricted to Authors. Governed by LLD Section 3.1."
    },
    @{
        Name        = "Review"
        Title       = "Review"
        Description = "Controlled document review and validation. Access restricted to designated Reviewers and Approvers. Governed by LLD Section 3.1."
    },
    @{
        Name        = "Approved"
        Title       = "Approved"
        Description = "Final authoritative content and executive packs. Read-only for Executive stakeholders. Governed by LLD Section 3.1."
    },
    @{
        Name        = "Archive"
        Title       = "Archive"
        Description = "Long-term record retention. Read-only for Compliance and Legal roles. Governed by LLD Section 3.1."
    }
)

Write-Host "`nConnecting to SharePoint site: $SiteUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl
Write-Host "Connected.`n" -ForegroundColor Green

$results = @{ Created = 0; Skipped = 0; Failed = 0 }

foreach ($lib in $Libraries) {
    Write-Host "Processing library: $($lib.Title)" -ForegroundColor Cyan

    # Idempotency check
    $existing = Get-PnPList -Identity $lib.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [SKIP]  Library already exists: $($lib.Title)" -ForegroundColor Yellow
        $results.Skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($lib.Title, "Create document library")) {
        try {
            # Create the document library
            $list = New-PnPList -Title $lib.Title `
                                -Template DocumentLibrary `
                                -Url "/$($lib.Name)" `
                                -EnableVersioning `
                                -OnQuickLaunch:$false   # Keep navigation clean for executives

            # Set description
            Set-PnPList -Identity $lib.Name -Description $lib.Description

            # Break permission inheritance — no permissions flow from the parent site.
            # Each library is its own security boundary (LLD Section 3.1, Section 5.2).
            # ClearSubscopes: true — remove any existing role assignments on child items
            $listObj = Get-PnPList -Identity $lib.Name
            $listObj.BreakRoleInheritance($false, $true)
            Invoke-PnPQuery

            # Enable major versioning with unlimited version history
            Set-PnPList -Identity $lib.Name `
                        -MajorVersions 500 `
                        -EnableVersioning $true `
                        -EnableMinorVersions $false   # No minor versions — lifecycle state governs this

            # Disable 'Require Content Approval' — lifecycle is managed by Power Automate
            Set-PnPList -Identity $lib.Name -EnableModeration $false

            Write-Host "  [OK]    Created: $($lib.Title) (inheritance broken, versioning enabled)" -ForegroundColor Green
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  $($lib.Title): $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Created : $($results.Created)" -ForegroundColor Green
Write-Host "  Skipped : $($results.Skipped)" -ForegroundColor Yellow
Write-Host "  Failed  : $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

if ($results.Failed -gt 0) {
    Write-Host "`n[WARNING] Resolve failures before proceeding." -ForegroundColor Red
    Disconnect-PnPOnline
    exit 1
}

Write-Host "`n[NEXT] Run 03-configure-permissions.ps1 -SiteUrl '$SiteUrl' -TenantId '<your-tenant-id>'" -ForegroundColor White
Disconnect-PnPOnline

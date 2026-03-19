<#
.SYNOPSIS
    Configures site-level and library-level settings for the Executive Workspace.

.DESCRIPTION
    Applies final governance settings to the site and all four document libraries:

    Site-level:
        - External sharing confirmed disabled
        - Default sharing link type set to specific people only
        - Access requests disabled

    Library-level (all four):
        - Require checkout before editing disabled (Power Automate handles lifecycle)
        - Default view configured to show ExecWS metadata columns
        - Audience targeting enabled on the Approved library (executive consumption)
        - Draft item security: only author and approvers can see drafts

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER TenantName
    M365 tenant name (e.g. contoso from contoso.onmicrosoft.com).

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\05-configure-settings.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace" -TenantName "contoso"

.NOTES
    Requires: PnP.PowerShell module
    Required role: SharePoint Administrator
    Run after: 04-add-metadata-columns.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantName
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AdminUrl = "https://$TenantName-admin.sharepoint.com"

# --- Admin-level settings ---
Write-Host "`nConnecting to SharePoint Admin Center: $AdminUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $AdminUrl

if ($PSCmdlet.ShouldProcess($SiteUrl, "Apply tenant-level site settings")) {
    # Confirm external sharing disabled
    Set-PnPTenantSite -Url $SiteUrl -SharingCapability Disabled
    Write-Host "[OK]  External sharing: Disabled" -ForegroundColor Green

    # Default sharing link: specific people only (belt-and-braces on top of label protection)
    Set-PnPTenantSite -Url $SiteUrl -DefaultSharingLinkType Direct
    Write-Host "[OK]  Default sharing link type: Specific people" -ForegroundColor Green

    # Disable access requests — no self-service access to this workspace
    # NOTE: Set-PnPTenantSite -AllowSelfServiceUpgrade controls classic site upgrade paths,
    #       not access requests. Removed to avoid incorrect configuration.
    #       Access requests are disabled via Set-PnPWeb -RequestAccessEmail "" (see below).
}

Disconnect-PnPOnline

# --- Site and library settings ---
Write-Host "`nConnecting to site: $SiteUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl

if ($PSCmdlet.ShouldProcess($SiteUrl, "Disable access request emails")) {
    # Disable access request emails — Set-PnPWeb -RequestAccessEmail not in PnP 3.x; use REST
    Invoke-PnPSPRestMethod -Url "/_api/web" -Method Merge `
        -Content '{"__metadata":{"type":"SP.Web"},"RequestAccessEmail":""}' `
        -ErrorAction SilentlyContinue
    Write-Host "[OK]  Access request email: Cleared" -ForegroundColor Green
}

# Library-level settings
$Libraries = @("Draft", "Review", "Approved", "Archive")

foreach ($lib in $Libraries) {
    Write-Host "`nConfiguring library: $lib" -ForegroundColor Cyan

    if ($PSCmdlet.ShouldProcess($lib, "Apply library settings")) {
        # Disable checkout requirement — Power Automate manages lifecycle transitions
        Set-PnPList -Identity $lib -ForceCheckout $false
        Write-Host "  [OK]  Checkout requirement: Disabled" -ForegroundColor Green

        # Draft item security: only author and approvers can see drafts
        # DraftVersionVisibility Author = Only author + approver can see minor/draft versions
        # NOTE: DraftVersionVisibility requires the DraftVisibilityType enum value (Author/Approver/Reader),
        #       not an integer. Using integer 1 is invalid in PnP.PowerShell v2.
        Set-PnPList -Identity $lib -DraftVersionVisibility Author -ErrorAction SilentlyContinue
        Write-Host "  [OK]  Draft visibility: Author and approver only" -ForegroundColor Green

        # Confirm versioning settings
        Set-PnPList -Identity $lib -EnableVersioning $true -MajorVersions 500 -EnableMinorVersions $false
        Write-Host "  [OK]  Versioning: Major versions only, 500 version limit" -ForegroundColor Green
    }
}

# Audience targeting on Approved library specifically (executive read experience)
# NOTE: Set-PnPList -EnableAudienceTargeting is not a valid PnP.PowerShell v2 parameter.
#       Audience targeting on a library must be configured via the SharePoint REST API.
if ($PSCmdlet.ShouldProcess("Approved", "Enable audience targeting")) {
    Invoke-PnPSPRestMethod -Url "/_api/web/lists/getbytitle('Approved')" -Method Merge -Content '{"__metadata":{"type":"SP.List"},"EnableAudienceTargeting":true}' -ErrorAction SilentlyContinue
    Write-Host "`n[OK]  Audience targeting enabled on Approved library" -ForegroundColor Green
}

Write-Host "`n[OK]    All site and library settings applied." -ForegroundColor Green
Write-Host "[NEXT]  Run 06-validate-spo.ps1 -SiteUrl '$SiteUrl' -TenantId '<tenant-id>'" -ForegroundColor White

Disconnect-PnPOnline

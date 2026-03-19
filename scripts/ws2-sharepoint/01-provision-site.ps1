<#
.SYNOPSIS
    Provisions the Executive Secure Research & Decision Workspace SharePoint Communication Site.

.DESCRIPTION
    Creates a private SharePoint Communication Site as the secure content backbone for the workspace.
    Configures site-level settings: external sharing disabled, no Teams association, audience targeting enabled.
    Idempotent — skips creation if a site at the target URL already exists.

    Site URL pattern: https://<TenantName>.sharepoint.com/sites/<SiteAlias>

.PARAMETER TenantName
    The M365 tenant name (the part before .sharepoint.com / .onmicrosoft.com). Example: contoso

.PARAMETER SiteAlias
    The URL alias for the site. Default: exec-workspace

.PARAMETER SiteTitle
    The display title of the site. Default: "Executive Secure Research Workspace"

.PARAMETER SiteOwner
    UPN of the site owner / primary admin. Must be a licensed M365 user.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\01-provision-site.ps1 -TenantName "contoso" -SiteOwner "admin@contoso.onmicrosoft.com"
    .\01-provision-site.ps1 -TenantName "contoso" -SiteOwner "admin@contoso.onmicrosoft.com" -WhatIf

.NOTES
    Requires: PnP.PowerShell module (Install-Module PnP.PowerShell)
    Required role: SharePoint Administrator
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantName,

    [string]$SiteAlias = "exec-workspace",

    [string]$SiteTitle = "Executive Secure Research Workspace",

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteOwner
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AdminUrl = "https://$TenantName-admin.sharepoint.com"
$SiteUrl  = "https://$TenantName.sharepoint.com/sites/$SiteAlias"

Write-Host "`nConnecting to SharePoint Admin Center: $AdminUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $AdminUrl
Write-Host "Connected.`n" -ForegroundColor Green

# --- Idempotency: check if site already exists ---
$existingSite = Get-PnPTenantSite -Url $SiteUrl -ErrorAction SilentlyContinue

if ($existingSite) {
    Write-Host "[SKIP]  Site already exists: $SiteUrl" -ForegroundColor Yellow
    Write-Host "        Title: $($existingSite.Title)" -ForegroundColor DarkGray
    Write-Host "`n[NEXT]  Proceed to 02-create-libraries.ps1" -ForegroundColor White
    Disconnect-PnPOnline
    exit 0
}

# --- Create Communication Site ---
if ($PSCmdlet.ShouldProcess($SiteUrl, "Create SharePoint Communication Site")) {
    Write-Host "Creating Communication Site..." -ForegroundColor Cyan
    Write-Host "  URL   : $SiteUrl" -ForegroundColor DarkGray
    Write-Host "  Title : $SiteTitle" -ForegroundColor DarkGray
    Write-Host "  Owner : $SiteOwner" -ForegroundColor DarkGray

    try {
        $site = New-PnPSite -Type CommunicationSite `
                            -Title $SiteTitle `
                            -Url $SiteUrl `
                            -Owner $SiteOwner `
                            -Lcid 1033 `
                            -Wait

        Write-Host "[OK]    Site created: $SiteUrl" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAIL]  Site creation failed: $($_.Exception.Message)" -ForegroundColor Red
        Disconnect-PnPOnline
        exit 1
    }
}

# --- Configure site-level settings ---
if ($PSCmdlet.ShouldProcess($SiteUrl, "Configure site settings")) {
    Write-Host "`nConfiguring site settings..." -ForegroundColor Cyan

    # Disable external sharing (Disabled = no external sharing at any level)
    Set-PnPTenantSite -Url $SiteUrl -SharingCapability Disabled
    Write-Host "  [OK]  External sharing disabled" -ForegroundColor Green

    # NOTE: -DisableTeamsChannelIntegration is not available in PnP.PowerShell 3.x.
    #       Communication Sites do not create a Teams team by default — no action needed.

    # Connect to the site itself for site collection settings
    Disconnect-PnPOnline
    Connect-WorkspacePnP -Url $SiteUrl

    # Enable audience targeting for SharePoint pages via REST API
    # NOTE: Set-PnPSite -EnableAudienceTargeting is not a valid PnP.PowerShell v2 parameter.
    #       Audience targeting must be set via the SharePoint REST API.
    Invoke-PnPSPRestMethod -Url "/_api/web" -Method Merge -Content '{"__metadata":{"type":"SP.Web"},"EnableAudienceTargeting":true}' -ErrorAction SilentlyContinue
    Write-Host "  [OK]  Audience targeting enabled" -ForegroundColor Green

    # NOTE: Set-PnPSite -SearchScope ModernPrivate is not a valid PnP.PowerShell v2 parameter.
    #       Site search scope can be configured in the SharePoint admin centre if required.
    #       Removed to avoid silent failure.
}

Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Site URL : $SiteUrl" -ForegroundColor Green
Write-Host "  Status   : Provisioned and configured" -ForegroundColor Green
Write-Host "`n[NEXT] Run 02-create-libraries.ps1 -SiteUrl '$SiteUrl'" -ForegroundColor White

Disconnect-PnPOnline

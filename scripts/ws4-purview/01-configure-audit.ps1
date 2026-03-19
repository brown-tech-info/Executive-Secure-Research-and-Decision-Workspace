<#
.SYNOPSIS
    Enables and verifies the Microsoft Purview Unified Audit Log.

.DESCRIPTION
    Confirms that the Unified Audit Log is enabled for the tenant — required for capturing
    all access, modification, approval, and lifecycle transition events from the Executive Workspace.

    If the audit log is not enabled, this script enables it.

    Auditability is a non-negotiable requirement per the project constitution and LLD Section 8.1.

.EXAMPLE
    .\01-configure-audit.ps1

.NOTES
    Requires: ExchangeOnlineManagement module (Install-Module ExchangeOnlineManagement)
    Required role: Exchange Administrator or Global Administrator
    The Unified Audit Log typically takes 30-60 minutes to start capturing events after enablement.
    In new tenants it may already be enabled by default (M365 E3/E5).
#>
[CmdletBinding()]
param()

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`nConnecting to Exchange Online (cert auth)..." -ForegroundColor Cyan
Connect-WorkspaceEXO
Write-Host "Connected.`n" -ForegroundColor Green

# --- Check current audit log status ---
Write-Host "--- Unified Audit Log Status ---`n" -ForegroundColor Cyan
$auditConfig = Get-AdminAuditLogConfig

$isEnabled = $auditConfig.UnifiedAuditLogIngestionEnabled

if ($isEnabled) {
    Write-Host "[OK]    Unified Audit Log is ENABLED." -ForegroundColor Green
}
else {
    Write-Host "[INFO]  Unified Audit Log is currently DISABLED. Enabling now..." -ForegroundColor Yellow
    Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
    Write-Host "[OK]    Unified Audit Log has been ENABLED." -ForegroundColor Green
    Write-Host "        Note: Allow 30-60 minutes for audit events to start appearing in Purview." -ForegroundColor Yellow
}

# --- Document key events to monitor ---
Write-Host "`n--- Key Audit Events for Executive Workspace ---`n" -ForegroundColor Cyan

$events = @(
    @{ Category = "SharePoint";  Event = "FileAccessed";           Description = "A file was viewed or downloaded" },
    @{ Category = "SharePoint";  Event = "FileModified";           Description = "A file was modified" },
    @{ Category = "SharePoint";  Event = "FileCopied";             Description = "A file was copied (lifecycle transitions)" },
    @{ Category = "SharePoint";  Event = "FileDeleted";            Description = "A file was deleted (lifecycle transitions)" },
    @{ Category = "SharePoint";  Event = "FileUploaded";           Description = "A file was uploaded" },
    @{ Category = "SharePoint";  Event = "SharingSet";             Description = "A sharing permission was set" },
    @{ Category = "SharePoint";  Event = "PermissionLevelChanged"; Description = "Library permission level was changed" },
    @{ Category = "Purview";     Event = "LabelApplied";           Description = "A sensitivity or retention label was applied" },
    @{ Category = "Purview";     Event = "LabelChanged";           Description = "A label was changed on a document" },
    @{ Category = "PowerAutomate"; Event = "FlowRun";              Description = "A lifecycle flow ran (approval, move, archive)" },
    @{ Category = "Entra ID";    Event = "AddMemberToGroup";       Description = "A user was added to an ExecWorkspace security group" },
    @{ Category = "Entra ID";    Event = "RemoveMemberFromGroup";  Description = "A user was removed from an ExecWorkspace security group" }
)

foreach ($event in $events) {
    Write-Host ("  {0,-15} {1,-30} {2}" -f "[$($event.Category)]", $event.Event, $event.Description) -ForegroundColor White
}

Write-Host "`n[INFO]  These events are captured automatically by the Unified Audit Log." -ForegroundColor Cyan
Write-Host "        Search for them in: Purview portal → Audit → New search" -ForegroundColor White
Write-Host "        Scope searches to site: $script:SiteUrl" -ForegroundColor White
Write-Host "`n[NEXT]  Run 02-configure-retention.ps1 to create retention labels." -ForegroundColor White

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

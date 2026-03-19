<#
.SYNOPSIS
    Applies Entra ID security group permissions to each document library.

.DESCRIPTION
    Assigns role-based access to the four lifecycle libraries using Entra ID security groups.
    Permission mapping (LLD Section 5.2):

        Draft    → ExecWorkspace-Authors      (Contribute)
        Review   → ExecWorkspace-Reviewers    (Contribute)
                   ExecWorkspace-Authors      (Read)       — authors can read their submitted docs
        Approved → ExecWorkspace-Executives   (Read)
                   ExecWorkspace-Reviewers    (Read)
        Archive  → ExecWorkspace-Compliance   (Read)

        All libs → ExecWorkspace-PlatformAdmins (Full Control) — via PIM-activated access only

    Idempotent — existing role assignments are detected and not duplicated.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER TenantId
    Entra ID Tenant ID (GUID). Required to resolve group object IDs.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\03-configure-permissions.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace" -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.NOTES
    Requires: PnP.PowerShell and Microsoft.Graph modules
    Required roles: SharePoint Administrator + Groups Administrator
    Run after: 02-create-libraries.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helper: resolve Entra ID group to SharePoint login name ---
# Uses Invoke-PnPGraphMethod to avoid Microsoft.Graph DLL version conflicts with PnP.PowerShell
function Get-SPOGroupLoginName {
    param([string]$GroupDisplayName)
    $encoded = [Uri]::EscapeDataString($GroupDisplayName)
    $result  = Invoke-PnPGraphMethod -Url "groups?`$filter=displayName eq '$encoded'&`$select=id,displayName" -Method Get
    if (-not $result.value -or $result.value.Count -eq 0) { throw "Group not found: $GroupDisplayName" }
    # Claim format for Entra ID security groups in SharePoint Online
    return "c:0t.c|tenant|$($result.value[0].id)"
}

# --- Helper: ensure principal exists in SPO and grant role on a library ---
function Set-LibraryPermission {
    param(
        [string]$LibraryName,
        [string]$LoginName,
        [string]$RoleName,
        [string]$DisplayName
    )
    try {
        # Ensure the Entra ID group is recognised by this SPO site collection
        $principal = Get-PnPUser -Identity $LoginName -ErrorAction SilentlyContinue
        if (-not $principal) {
            $principal = New-PnPUser -LoginName $LoginName
        }

        # Check if assignment already exists (idempotency)
        $list       = Get-PnPList -Identity $LibraryName
        $ctx        = Get-PnPContext
        $assignments = $list.RoleAssignments
        $ctx.Load($assignments)
        Invoke-PnPQuery

        $alreadyAssigned = $false
        foreach ($assignment in $assignments) {
            $ctx.Load($assignment.Member)
            Invoke-PnPQuery
            if ($assignment.Member.LoginName -eq $LoginName) {
                $alreadyAssigned = $true
                break
            }
        }

        if ($alreadyAssigned) {
            Write-Host "    [SKIP]  Already assigned: $DisplayName → $LibraryName ($RoleName)" -ForegroundColor Yellow
            return
        }

        # Apply the role assignment
        $roleDefinition = Get-PnPRoleDefinition -Identity $RoleName
        $roleBindings   = New-Object Microsoft.SharePoint.Client.RoleDefinitionBindingCollection($ctx)
        $roleBindings.Add($roleDefinition)
        $list.RoleAssignments.Add($principal, $roleBindings) | Out-Null
        Invoke-PnPQuery

        Write-Host "    [OK]    Granted: $DisplayName → $LibraryName ($RoleName)" -ForegroundColor Green
    }
    catch {
        Write-Host "    [FAIL]  $DisplayName → $LibraryName : $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# --- Connect (PnP only — Graph calls go through Invoke-PnPGraphMethod to avoid DLL conflicts) ---
Write-Host "Connecting to SharePoint site: $SiteUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl
Write-Host "Connected.`n" -ForegroundColor Green

# --- Resolve group login names ---
Write-Host "Resolving Entra ID group login names..." -ForegroundColor Cyan

$groups = @{}
foreach ($name in @("ExecWorkspace-Authors","ExecWorkspace-Reviewers","ExecWorkspace-Executives","ExecWorkspace-Compliance","ExecWorkspace-PlatformAdmins")) {
    $groups[$name] = Get-SPOGroupLoginName -GroupDisplayName $name
    Write-Host "  Resolved: $name" -ForegroundColor DarkGray
}
Write-Host ""

# --- Apply permissions per library (LLD Section 5.2) ---
$permissionMap = @(
    @{ Library = "Draft";    Group = "ExecWorkspace-Authors";       Role = "Contribute" },
    @{ Library = "Review";   Group = "ExecWorkspace-Reviewers";     Role = "Contribute" },
    @{ Library = "Review";   Group = "ExecWorkspace-Authors";       Role = "Read" },
    @{ Library = "Approved"; Group = "ExecWorkspace-Executives";    Role = "Read" },
    @{ Library = "Approved"; Group = "ExecWorkspace-Reviewers";     Role = "Read" },
    @{ Library = "Archive";  Group = "ExecWorkspace-Compliance";    Role = "Read" }
)

# PlatformAdmins get Full Control on all libraries (used only when PIM-activated)
foreach ($lib in @("Draft","Review","Approved","Archive")) {
    $permissionMap += @{ Library = $lib; Group = "ExecWorkspace-PlatformAdmins"; Role = "Full Control" }
}

foreach ($entry in $permissionMap) {
    if ($PSCmdlet.ShouldProcess("$($entry.Group) → $($entry.Library)", "Grant $($entry.Role)")) {
        Set-LibraryPermission `
            -LibraryName $entry.Library `
            -LoginName   $groups[$entry.Group] `
            -RoleName    $entry.Role `
            -DisplayName $entry.Group
    }
}

Write-Host "`n[OK]    Permission configuration complete." -ForegroundColor Green
Write-Host "[NEXT]  Run 04-add-metadata-columns.ps1 -SiteUrl '$SiteUrl'" -ForegroundColor White

Disconnect-PnPOnline

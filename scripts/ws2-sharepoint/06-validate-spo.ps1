<#
.SYNOPSIS
    Validates the SharePoint site provisioning against the LLD specification.

.DESCRIPTION
    Runs a comprehensive validation of the Executive Workspace SharePoint configuration:
        - Site exists with correct settings
        - All four document libraries present with broken inheritance
        - Group permissions assigned correctly per library
        - All five metadata columns present on each library
        - Versioning enabled

    Exits with code 1 if any checks fail, blocking progression to WS-3 MIP.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER TenantId
    Entra ID Tenant ID (GUID). Required to resolve group permissions.

.EXAMPLE
    .\06-validate-spo.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace" -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.NOTES
    Requires: PnP.PowerShell and Microsoft.Graph modules
    Run after all WS-2 scripts have completed successfully.
    All checks must pass before proceeding to WS-3 (MIP label application).
#>
[CmdletBinding()]
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

$failures = @()

function Write-Check {
    param([bool]$Pass, [string]$Message)
    if ($Pass) { Write-Host "  [PASS]  $Message" -ForegroundColor Green }
    else        { Write-Host "  [FAIL]  $Message" -ForegroundColor Red; $script:failures += $Message }
}

# --- Connect ---
Write-Host "`nConnecting to Microsoft Graph and SharePoint..." -ForegroundColor Cyan
Connect-WorkspaceGraph
Connect-WorkspacePnP -Url $SiteUrl
Write-Host "Connected.`n" -ForegroundColor Green

# === CHECK 1: Site exists ===
Write-Host "--- Site Existence ---" -ForegroundColor Cyan
$web = Get-PnPWeb -ErrorAction SilentlyContinue
Write-Check -Pass ($null -ne $web) -Message "Site is accessible: $SiteUrl"
if ($web) {
    Write-Host "    Title: $($web.Title)" -ForegroundColor DarkGray
}

# === CHECK 2: Libraries exist with broken inheritance ===
Write-Host "`n--- Document Libraries ---" -ForegroundColor Cyan
$expectedLibs = @("Draft", "Review", "Approved", "Archive")

foreach ($libName in $expectedLibs) {
    $list = Get-PnPList -Identity $libName `
        -Includes HasUniqueRoleAssignments,EnableVersioning,EnableMinorVersions `
        -ErrorAction SilentlyContinue
    Write-Check -Pass ($null -ne $list) -Message "Library exists: $libName"

    if ($list) {
        Write-Check -Pass ([bool]$list.HasUniqueRoleAssignments) -Message "${libName}: Permission inheritance is broken (unique permissions)"
        Write-Check -Pass ([bool]$list.EnableVersioning)         -Message "${libName}: Versioning is enabled"
        Write-Check -Pass (-not [bool]$list.EnableMinorVersions) -Message "${libName}: Minor versions disabled (major only)"
    }
}

# === CHECK 3: Metadata columns ===
Write-Host "`n--- Metadata Columns ---" -ForegroundColor Cyan
$requiredColumns = @(
    "ExecWS_DocumentType",
    "ExecWS_LifecycleState",
    "ExecWS_MeetingDecisionId",
    "ExecWS_SensitivityClassification",
    "ExecWS_DocumentOwner"
)

foreach ($libName in $expectedLibs) {
    foreach ($colName in $requiredColumns) {
        $field = Get-PnPField -List $libName -Identity $colName -ErrorAction SilentlyContinue
        Write-Check -Pass ($null -ne $field) -Message "${libName}: Column '$colName' exists"
    }
}

# === CHECK 4: Group permissions ===
Write-Host "`n--- Group Permissions ---" -ForegroundColor Cyan

# Permission expectations: library → group → expected role
$permChecks = @(
    @{ Library = "Draft";    Group = "ExecWorkspace-Authors";       Role = "Contribute" },
    @{ Library = "Review";   Group = "ExecWorkspace-Reviewers";     Role = "Contribute" },
    @{ Library = "Approved"; Group = "ExecWorkspace-Executives";    Role = "Read" },
    @{ Library = "Archive";  Group = "ExecWorkspace-Compliance";    Role = "Read" }
)

foreach ($check in $permChecks) {
    # Resolve group via PnP Graph (avoids Microsoft.Graph DLL conflict)
    $grpResult = Invoke-PnPGraphMethod -Url "groups?`$filter=displayName eq '$($check.Group)'&`$select=id" -Method Get
    $group     = if ($grpResult.value.Count -gt 0) { $grpResult.value[0] } else { $null }

    if (-not $group) {
        Write-Check -Pass $false -Message "$($check.Library): Group not found in Entra: $($check.Group)"
        continue
    }

    $loginName = "c:0t.c|tenant|$($group.id)"

    # Check permissions via SPO REST API (avoids CSOM ctx requirement)
    $assignments = Invoke-PnPSPRestMethod `
        -Url "/_api/web/lists/getbytitle('$($check.Library)')/roleassignments?`$expand=Member,RoleDefinitionBindings" `
        -Method Get

    $found = $false
    foreach ($a in $assignments.value) {
        if ($a.Member.LoginName -eq $loginName) {
            $roleNames = $a.RoleDefinitionBindings | ForEach-Object { $_.Name }
            if ($check.Role -in $roleNames) { $found = $true; break }
        }
    }
    Write-Check -Pass $found -Message "$($check.Library): $($check.Group) has $($check.Role) permission"
}

# === Result ===
Write-Host "`n--- Validation Result ---" -ForegroundColor Cyan
if ($failures.Count -eq 0) {
    Write-Host "[PASS]  All checks passed. SharePoint provisioning is valid." -ForegroundColor Green
    Write-Host "[NEXT]  Proceed to WS-3: run ws3-mip/02-apply-sensitivity-labels.ps1" -ForegroundColor White
}
else {
    Write-Host "[FAIL]  $($failures.Count) check(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`nResolve all failures before proceeding to WS-3." -ForegroundColor Yellow
}

Disconnect-MgGraph -ErrorAction SilentlyContinue
Disconnect-PnPOnline

exit $(if ($failures.Count -eq 0) { 0 } else { 1 })

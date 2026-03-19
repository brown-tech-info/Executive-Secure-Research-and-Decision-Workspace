<#
.SYNOPSIS
    Validates that all required Entra ID security groups exist and are correctly configured.

.DESCRIPTION
    Checks for the existence of all five ExecWorkspace security groups defined in LLD Section 5.1.
    Reports missing groups and exits with code 1 if any are absent, blocking progression to WS-2.
    Also validates that ExecWorkspace-Authors is a mail-enabled security group, as required by
    the MeetingPackOpen Power Automate flow (which sends notification emails to this group).

.PARAMETER TenantId
    The Entra ID Tenant ID (GUID) of the dev M365 tenant.

.EXAMPLE
    .\02-validate-entra-groups.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.NOTES
    Requires: Microsoft.Graph module
    Required permission scope: Group.Read.All
    Run this after 01-create-security-groups.ps1 to confirm readiness for WS-2.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedGroups = @(
    "ExecWorkspace-Authors",
    "ExecWorkspace-Reviewers",
    "ExecWorkspace-Executives",
    "ExecWorkspace-Compliance",
    "ExecWorkspace-PlatformAdmins"
)

Write-Host "`nConnecting to Microsoft Graph (Tenant: $TenantId)..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes "Group.Read.All" -NoWelcome
Write-Host "Connected.`n" -ForegroundColor Green

Write-Host "--- Entra ID Group Validation ---`n" -ForegroundColor Cyan

$missing = @()

foreach ($groupName in $ExpectedGroups) {
    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ConsistencyLevel eventual -CountVariable count -ErrorAction SilentlyContinue

    if ($group) {
        Write-Host "  [OK]     Found : $groupName" -ForegroundColor Green
        Write-Host "           ID   : $($group.Id)" -ForegroundColor DarkGray

        # Extra check: ExecWorkspace-Authors must be mail-enabled for flow notifications
        if ($groupName -eq "ExecWorkspace-Authors") {
            if ($group.MailEnabled) {
                Write-Host "           Mail : Enabled (required for MeetingPackOpen notifications)" -ForegroundColor Green
            } else {
                Write-Host "           Mail : [FAIL] Not mail-enabled — MeetingPackOpen notification emails will be undeliverable." -ForegroundColor Red
                Write-Host "                  Fix: delete group and re-create via EXO New-DistributionGroup -Type Security" -ForegroundColor Yellow
                $missing += "$groupName (not mail-enabled)"
            }
        }
    }
    else {
        Write-Host "  [MISSING]       : $groupName" -ForegroundColor Red
        $missing += $groupName
    }
}

Write-Host ""

if ($missing.Count -gt 0) {
    Write-Host "[FAIL] Validation failed. Missing groups:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`nRun 01-create-security-groups.ps1 to create missing groups before proceeding." -ForegroundColor Yellow
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "[PASS] All required Entra ID groups are present." -ForegroundColor Green
Write-Host "[NEXT] Ready to proceed to WS-2 SharePoint provisioning." -ForegroundColor White

Disconnect-MgGraph -ErrorAction SilentlyContinue

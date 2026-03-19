<#
.SYNOPSIS
    Creates Conditional Access policies for the Executive Secure Research & Decision Workspace.

.DESCRIPTION
    Deploys two CA policies via Microsoft Graph (LLD Section 5.3):

        CA-ExecWorkspace-BaselineAccess
            Users  : Authors, Reviewers, Executives, Compliance
            Apps   : SharePoint Online + Office 365
            Grant  : MFA AND compliant device (both required)
            Session: Sign-in frequency 8 hours

        CA-ExecWorkspace-AdminAccess
            Users  : PlatformAdmins
            Apps   : SharePoint Online + Microsoft 365 admin portals
            Grant  : MFA AND compliant device
            Session: Sign-in frequency 4 hours

    Both policies are created in Report-only mode. Switch to Enabled after validation
    using the -Enforce switch (or call Set-MgIdentityConditionalAccessPolicy manually).

    Idempotent — policies with matching DisplayName are detected and skipped.

.PARAMETER TenantId
    Entra ID Tenant ID (GUID).

.PARAMETER Enforce
    If specified, policies are created in Enabled state rather than Report-only.
    Only use after validating Report-only results in sign-in logs.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\03-create-conditional-access.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    .\03-create-conditional-access.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Enforce

.NOTES
    Requires: Install-Module Microsoft.Graph.Identity.SignIns, Microsoft.Graph.Groups
    Required scopes: Policy.ReadWrite.ConditionalAccess, Group.Read.All
    Required role: Conditional Access Administrator or Global Administrator
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [switch]$Enforce
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Policy state: Report-only until -Enforce is passed
$PolicyState = if ($Enforce) { "enabled" } else { "enabledForReportingButNotEnforced" }

# Well-known application IDs (stable Microsoft constants — not tenant-specific)
# NOTE: "Office365" is a valid well-known application set identifier in the Graph CA policy API
#       (supported as of recent Graph API versions). It covers all Office 365 services.
# NOTE: "MicrosoftAdminPortals" is NOT a valid Graph CA API value. Use the Azure Management
#       portal resource app ID instead: 797f4846-ba00-4fd7-ba43-dac1f8f63013
$AppIds = @{
    SharePointOnline    = "00000003-0000-0ff1-ce00-000000000000"
    Office365           = "Office365"   # Valid well-known application set identifier for all O365 apps
    M365AdminPortals    = "797f4846-ba00-4fd7-ba43-dac1f8f63013"  # Azure Management portal resource app ID
}

Write-Host "`nConnecting to Microsoft Graph (Tenant: $TenantId)..." -ForegroundColor Cyan
# Use device code auth to guarantee a fresh token with the correct scopes.
# InteractiveBrowser reuses the cached MSAL token from the current Windows session.
# The CA policy API requires BOTH Policy.ReadWrite.ConditionalAccess AND Policy.Read.All.
DisConnect-WorkspaceGraph
    -NoWelcome
Write-Host "Connected.`n" -ForegroundColor Green

# --- Resolve group Object IDs ---
Write-Host "Resolving Entra ID group Object IDs..." -ForegroundColor Cyan

$groupNames = @("ExecWorkspace-Authors","ExecWorkspace-Reviewers","ExecWorkspace-Executives",
                "ExecWorkspace-Compliance","ExecWorkspace-PlatformAdmins")
$groupIds   = @{}

foreach ($name in $groupNames) {
    $group = Get-MgGroup -Filter "displayName eq '$name'" -ConsistencyLevel eventual -CountVariable count -ErrorAction SilentlyContinue
    if (-not $group) {
        Write-Host "  [FAIL]  Group not found: $name — run ws1-entra/01-create-security-groups.ps1 first." -ForegroundColor Red
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        exit 1
    }
    $groupIds[$name] = $group.Id
    Write-Host "  Resolved: $name → $($group.Id)" -ForegroundColor DarkGray
}

Write-Host ""

# --- Policy definitions ---
$Policies = @(
    @{
        DisplayName = "CA-ExecWorkspace-BaselineAccess"
        State       = $PolicyState
        Description = "Baseline CA policy for all Executive Workspace users. Enforces MFA and compliant device. LLD Section 5.3."
        Conditions  = @{
            Users        = @{
                IncludeGroups = @(
                    $groupIds["ExecWorkspace-Authors"],
                    $groupIds["ExecWorkspace-Reviewers"],
                    $groupIds["ExecWorkspace-Executives"],
                    $groupIds["ExecWorkspace-Compliance"]
                )
            }
            Applications = @{
                IncludeApplications = @(
                    $AppIds.SharePointOnline,
                    $AppIds.Office365
                )
            }
            ClientAppTypes = @("browser","mobileAppsAndDesktopClients")
        }
        GrantControls = @{
            Operator        = "AND"
            BuiltInControls = @("mfa","compliantDevice")
        }
        SessionControls = @{
            SignInFrequency = @{
                Value              = 8
                Type               = "hours"
                IsEnabled          = $true
                AuthenticationType = "primaryAndSecondaryAuthentication"
            }
        }
    },
    @{
        DisplayName = "CA-ExecWorkspace-AdminAccess"
        State       = $PolicyState
        Description = "Stricter CA policy for Platform Administrators. Enforces MFA, compliant device, and shorter session. LLD Section 5.3."
        Conditions  = @{
            Users        = @{
                IncludeGroups = @($groupIds["ExecWorkspace-PlatformAdmins"])
            }
            Applications = @{
                IncludeApplications = @(
                    $AppIds.SharePointOnline,
                    $AppIds.M365AdminPortals
                )
            }
            ClientAppTypes = @("browser","mobileAppsAndDesktopClients")
        }
        GrantControls = @{
            Operator        = "AND"
            BuiltInControls = @("mfa","compliantDevice")
        }
        SessionControls = @{
            SignInFrequency = @{
                Value              = 4
                Type               = "hours"
                IsEnabled          = $true
                AuthenticationType = "primaryAndSecondaryAuthentication"
            }
        }
    }
)

# --- Deploy policies ---
$results = @{ Created = 0; Skipped = 0; Failed = 0 }

foreach ($policy in $Policies) {
    Write-Host "Processing policy: $($policy.DisplayName)" -ForegroundColor Cyan

    # Idempotency check
    $existing = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$($policy.DisplayName)'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [SKIP]  Policy already exists: $($policy.DisplayName)" -ForegroundColor Yellow
        $results.Skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($policy.DisplayName, "Create Conditional Access policy (state: $($policy.State))")) {
        try {
            $params = @{
                DisplayName     = $policy.DisplayName
                State           = $policy.State
                Conditions      = $policy.Conditions
                GrantControls   = $policy.GrantControls
                SessionControls = $policy.SessionControls
            }

            $created = New-MgIdentityConditionalAccessPolicy -BodyParameter $params
            Write-Host "  [OK]    Created: $($policy.DisplayName) (ID: $($created.Id))" -ForegroundColor Green
            Write-Host "          State:   $($policy.State)" -ForegroundColor DarkGray
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  $($policy.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Created : $($results.Created)" -ForegroundColor Green
Write-Host "  Skipped : $($results.Skipped)" -ForegroundColor Yellow
Write-Host "  Failed  : $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

if (-not $Enforce) {
    Write-Host "`n[INFO]  Policies created in Report-only mode. Review sign-in logs in Entra ID before enforcing." -ForegroundColor Yellow
    Write-Host "        To enforce: re-run with -Enforce, or run:" -ForegroundColor White
    Write-Host "        Get-MgIdentityConditionalAccessPolicy | Where DisplayName -like 'CA-ExecWorkspace*' | ForEach { Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId `$_.Id -State 'enabled' }" -ForegroundColor DarkGray
}

Disconnect-MgGraph -ErrorAction SilentlyContinue
exit $(if ($results.Failed -gt 0) { 1 } else { 0 })

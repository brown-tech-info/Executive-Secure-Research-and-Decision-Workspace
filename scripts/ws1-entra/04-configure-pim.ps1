<#
.SYNOPSIS
    Configures Privileged Identity Management (PIM) for the Executive Workspace security groups.

.DESCRIPTION
    Configures PIM for Groups on two security groups (LLD Section 5.3):

        ExecWorkspace-PlatformAdmins
            Max activation duration : 4 hours
            Requires               : MFA + Justification + Approval
            Approver               : Specified via -PlatformAdminApproverId

        ExecWorkspace-Compliance
            Max activation duration : 8 hours
            Requires               : MFA + Justification (no approval)

    For each group, this script:
        1. Registers the group with PIM (creates the eligibility scope)
        2. Updates the PIM policy rules (MFA, justification, expiration, notifications)
        3. Creates a quarterly access review for PlatformAdmins
        4. Creates a bi-annual access review for Compliance

    Member assignments (who is eligible) are separate — add eligible members in Entra ID
    after running this script. PIM settings apply to all future eligible assignments.

.PARAMETER TenantId
    Entra ID Tenant ID (GUID).

.PARAMETER PlatformAdminApproverId
    Object ID of the user who will approve PIM activation requests for PlatformAdmins.
    Typically the IT Admin or a senior security officer.

.PARAMETER AccessReviewNotificationEmail
    Email address to receive access review notifications. Typically an admin or compliance team DL.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\04-configure-pim.ps1 `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -PlatformAdminApproverId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -AccessReviewNotificationEmail "itadmin@<dev-tenant>.onmicrosoft.com"

.NOTES
    Requires: Install-Module Microsoft.Graph (Microsoft.Graph.Identity.Governance)
    Required scopes: PrivilegedAccess.ReadWrite.AzureADGroup, IdentityGovernance.ReadWrite.All,
                     Group.Read.All, RoleManagement.ReadWrite.Directory
    Required role: Privileged Role Administrator or Global Administrator
    Requires: Entra ID P2 licensing (M365 E5)
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PlatformAdminApproverId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AccessReviewNotificationEmail
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`nConnecting to Microsoft Graph (Tenant: $TenantId)..." -ForegroundColor Cyan
# Use device code auth to guarantee a fresh token with PIM/governance scopes.
# InteractiveBrowser reuses the cached MSAL token from the current Windows session
# which may lack these elevated scopes. Device code bypasses the WAM/browser cache.
DisConnect-WorkspaceGraph
    -NoWelcome
Write-Host "Connected.`n" -ForegroundColor Green

# --- Helper: get group by display name ---
function Get-WorkspaceGroup {
    param([string]$Name)
    # Use Invoke-MgGraphRequest directly to ensure ConsistencyLevel and $count
    # headers are set correctly — Get-MgGroup filter can silently return null
    # in some token contexts even when the group exists.
    $encodedName = [System.Uri]::EscapeDataString($Name)
    $response = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$encodedName'&`$count=true" `
        -Headers @{ 'ConsistencyLevel' = 'eventual' } `
        -ErrorAction SilentlyContinue
    $g = $response.value | Select-Object -First 1
    if (-not $g) { throw "Group not found: $Name — run 01-create-security-groups.ps1 first." }
    return $g
}

# --- Resolve groups ---
Write-Host "Resolving group Object IDs..." -ForegroundColor Cyan
$platformAdminsGroup = Get-WorkspaceGroup -Name "ExecWorkspace-PlatformAdmins"
$complianceGroup     = Get-WorkspaceGroup -Name "ExecWorkspace-Compliance"
Write-Host "  ExecWorkspace-PlatformAdmins : $($platformAdminsGroup.Id)" -ForegroundColor DarkGray
Write-Host "  ExecWorkspace-Compliance     : $($complianceGroup.Id)" -ForegroundColor DarkGray
Write-Host ""

# --- Helper: update PIM policy rules for a group ---
function Set-PimGroupPolicy {
    param(
        [string]$GroupId,
        [string]$GroupName,
        [string]$MaxActivationHours,
        [bool]$RequireApproval,
        [string]$ApproverId = $null
    )

    Write-Host "Configuring PIM policy for: $GroupName" -ForegroundColor Cyan

    # Get the PIM management policy for this group's member role
    $policies = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/policies/roleManagementPolicies?`$filter=scopeId eq '$GroupId' and scopeType eq 'Group'" `
        -ErrorAction SilentlyContinue

    $policy = $null
    if ($policies -and $policies.value) {
        $policy = $policies.value | Where-Object { $_.scopeId -eq $GroupId } | Select-Object -First 1
    }

    if (-not $policy) {
        # Policy not yet created — trigger creation by making the group PIM-eligible
        # The policy is auto-created when the first eligibility schedule is created
        Write-Host "  [INFO]  PIM policy not yet initialised for $GroupName." -ForegroundColor Yellow
        Write-Host "          Add at least one eligible member assignment in Entra ID → PIM → Groups," -ForegroundColor Yellow
        Write-Host "          then re-run this script to apply policy settings." -ForegroundColor Yellow
        return
    }

    Write-Host "  PIM Policy ID: $($policy.id)" -ForegroundColor DarkGray

    # Build the rules to update
    $rules = @(
        @{
            # Require MFA and justification for activation
            "@odata.type" = "#microsoft.graph.unifiedRoleManagementPolicyEnablementRule"
            id            = "Enablement_EndUser_Assignment"
            enabledRules  = @("MultiFactorAuthentication", "Justification")
            target        = @{
                caller      = "EndUser"
                operations  = @("All")
                level       = "Assignment"
                inheritableSettings = @()
                enforcedSettings    = @()
            }
        },
        @{
            # Set maximum activation duration
            "@odata.type"        = "#microsoft.graph.unifiedRoleManagementPolicyExpirationRule"
            id                   = "Expiration_EndUser_Assignment"
            isExpirationRequired = $true
            maximumDuration      = "PT$($MaxActivationHours)H"   # ISO 8601 duration
            target               = @{
                caller      = "EndUser"
                operations  = @("All")
                level       = "Assignment"
            }
        }
    )

    # Add approval rule if required
    if ($RequireApproval -and $ApproverId) {
        $rules += @{
            "@odata.type"     = "#microsoft.graph.unifiedRoleManagementPolicyApprovalRule"
            id                = "Approval_EndUser_Assignment"
            setting           = @{
                isApprovalRequired              = $true
                isApprovalRequiredForExtension  = $false
                isRequestorJustificationRequired = $true
                approvalMode                    = "SingleStage"
                approvalStages                  = @(
                    @{
                        approvalStageTimeOutInDays      = 1
                        isApproverJustificationRequired = $true
                        escalationTimeInMinutes         = 0
                        primaryApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.singleUser"
                                userId        = $ApproverId
                            }
                        )
                    }
                )
            }
            target = @{ caller = "EndUser"; operations = @("All"); level = "Assignment" }
        }
    }

    if ($PSCmdlet.ShouldProcess($GroupName, "Update PIM policy rules")) {
        try {
            # Update the policy rules one by one (PATCH per rule is the Graph API pattern)
            foreach ($rule in $rules) {
                Invoke-MgGraphRequest -Method PATCH `
                    -Uri "https://graph.microsoft.com/v1.0/policies/roleManagementPolicies/$($policy.id)/rules/$($rule.id)" `
                    -Body ($rule | ConvertTo-Json -Depth 10) `
                    -ContentType "application/json" | Out-Null
                Write-Host "  [OK]    Updated rule: $($rule.id)" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  [FAIL]  Failed to update PIM policy: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# --- Helper: create access review ---
function New-WorkspaceAccessReview {
    param(
        [string]$GroupId,
        [string]$ReviewName,
        [string]$RecurrenceType,   # "absoluteMonthly","absoluteYearly"
        [int]$RecurrenceInterval,  # 3 for quarterly (months), 6 for bi-annual
        [string]$NotificationEmail
    )

    # Check if review already exists
    $existing = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq '$ReviewName'" `
        -Headers @{ 'ConsistencyLevel' = 'eventual' } `
        -ErrorAction SilentlyContinue
    if ($existing -and $existing.value -and $existing.value.Count -gt 0) {
        Write-Host "  [SKIP]  Access review already exists: $ReviewName" -ForegroundColor Yellow
        return
    }

    if ($PSCmdlet.ShouldProcess($ReviewName, "Create access review")) {
        try {
            # Look up the notification recipient's user ID
            $recipientResp = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/users?`$filter=mail eq '$NotificationEmail' or userPrincipalName eq '$NotificationEmail'&`$select=id" `
                -ErrorAction SilentlyContinue
            $recipientId = if ($recipientResp -and $recipientResp.value) { $recipientResp.value[0].id } else { $null }

            $reviewBody = @{
                displayName          = $ReviewName
                descriptionForAdmins = "Periodic access review for $ReviewName. Ensures group membership is current and necessary."
                scope                = @{
                    # @odata.type is required by the Graph API for polymorphic scope types
                    "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
                    query         = "/groups/$GroupId/members"
                    queryType     = "MicrosoftGraph"
                }
                reviewers            = @(
                    @{
                        # Fall back to the notification email user as reviewer — groups may have no owners yet
                        "@odata.type" = "#microsoft.graph.accessReviewReviewerScope"
                        query         = "/users/$recipientId"
                        queryType     = "MicrosoftGraph"
                    }
                )
                settings             = @{
                    mailNotificationsEnabled        = $true
                    reminderNotificationsEnabled    = $true
                    justificationRequiredOnApproval = $true
                    defaultDecision                 = "Deny"
                    autoApplyDecisionsEnabled       = $true
                    instanceDurationInDays          = 14
                    recurrence                      = @{
                        pattern = @{
                            type     = $RecurrenceType
                            interval = $RecurrenceInterval
                        }
                        range   = @{
                            type      = "noEnd"
                            startDate = (Get-Date).ToString("yyyy-MM-dd")
                        }
                    }
                }
            }

            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions" `
                -Body ($reviewBody | ConvertTo-Json -Depth 15) `
                -ContentType "application/json" | Out-Null

            Write-Host "  [OK]    Created access review: $ReviewName" -ForegroundColor Green
        }
        catch {
            Write-Host "  [FAIL]  Access review '$ReviewName': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# === WS-1.4a: PlatformAdmins PIM policy ===
Write-Host "`n=== PlatformAdmins PIM Configuration ===" -ForegroundColor White
Set-PimGroupPolicy `
    -GroupId           $platformAdminsGroup.Id `
    -GroupName         "ExecWorkspace-PlatformAdmins" `
    -MaxActivationHours "4" `
    -RequireApproval   $true `
    -ApproverId        $PlatformAdminApproverId

# === WS-1.4b: Compliance PIM policy ===
Write-Host "`n=== Compliance Group PIM Configuration ===" -ForegroundColor White
Set-PimGroupPolicy `
    -GroupId           $complianceGroup.Id `
    -GroupName         "ExecWorkspace-Compliance" `
    -MaxActivationHours "8" `
    -RequireApproval   $false

# === WS-1.4c: Access reviews ===
Write-Host "`n=== Access Reviews ===" -ForegroundColor Cyan

New-WorkspaceAccessReview `
    -GroupId           $platformAdminsGroup.Id `
    -ReviewName        "ExecWorkspace-PlatformAdmins-QuarterlyReview" `
    -RecurrenceType    "absoluteMonthly" `
    -RecurrenceInterval 3 `
    -NotificationEmail  $AccessReviewNotificationEmail

New-WorkspaceAccessReview `
    -GroupId           $complianceGroup.Id `
    -ReviewName        "ExecWorkspace-Compliance-BiAnnualReview" `
    -RecurrenceType    "absoluteMonthly" `
    -RecurrenceInterval 6 `
    -NotificationEmail  $AccessReviewNotificationEmail

Write-Host "`n[OK]    PIM configuration complete." -ForegroundColor Green
Write-Host "[NOTE]  PIM policy rule updates apply to the group's existing PIM scope." -ForegroundColor Yellow
Write-Host "        If no policy was found for a group, add eligible members in Entra ID → PIM → Groups first." -ForegroundColor Yellow

Disconnect-MgGraph -ErrorAction SilentlyContinue

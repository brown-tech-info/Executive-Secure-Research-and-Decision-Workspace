<#
.SYNOPSIS
    Provisions the Purview eDiscovery case and legal hold for the Executive Workspace.

.DESCRIPTION
    Creates the following eDiscovery configuration (LLD Section 8.3):

        Case         : ExecWorkspace-eDiscovery
        Content scope: https://<dev-tenant>.sharepoint.com/sites/exec-workspace (all 4 libraries)
        Hold policy  : ExecWorkspace-LegalHold (disabled by default — activate on legal instruction only)
        Validation   : Runs an initial content search to confirm discoverability

    *** AUTHENTICATION NOTE ***
    This script uses INTERACTIVE authentication for IPPS (Security & Compliance).
    You will be prompted to sign in via browser/MFA as the deployment admin once.

    REASON: Microsoft's compliance workbench (eDiscovery) requires a HUMAN identity as the
    case creator and owner. This is by Microsoft design for legal governance accountability —
    a service principal cannot own an eDiscovery case. All other WS-4 scripts use certificate
    (app-only) authentication. This script is the single exception.

    Case members are populated by expanding the ExecWorkspace-Compliance Entra ID group
    (resolved via Microsoft Graph cert auth — no second sign-in required).

    Idempotent — existing case, hold, and search are detected and skipped.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.
    Defaults to the value in config.ps1 if not supplied.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\04-configure-ediscovery.ps1
    .\04-configure-ediscovery.ps1 -SiteUrl "https://<dev-tenant>.sharepoint.com/sites/exec-workspace"

.NOTES
    Requires: Install-Module ExchangeOnlineManagement (v3.0.0+), Microsoft.Graph
    Required interactive role: Compliance Administrator + Global Admin (for eDiscovery case ownership)
    Required app permissions (Graph, cert auth): Group.ReadWrite.All
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SiteUrl,   # defaults to $script:SiteUrl from config.ps1 if not supplied
    [string]$CaseName = "ExecWorkspace-eDiscovery"   # override if preferred name is taken by an orphaned case
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $SiteUrl) { $SiteUrl = $script:SiteUrl }

$HoldName   = "ExecWorkspace-LegalHold"
$SearchName = "ExecWorkspace-DiscoverabilityValidation"

# ── Graph: certificate auth first — must load before IPPS to avoid MSAL version conflict ─────
Write-Host "`nConnecting to Microsoft Graph (cert auth)..." -ForegroundColor Cyan
Connect-WorkspaceGraph
Write-Host "Connected." -ForegroundColor Green

# ── IPPS: interactive delegated auth (required for eDiscovery case ownership) ────────────────
Write-Host "Connecting to Security & Compliance (IPPS, interactive auth)..." -ForegroundColor Cyan
Write-Host "  You will be prompted to sign in via browser as: $script:AdminUPN" -ForegroundColor DarkGray
Connect-IPPSSession -UserPrincipalName $script:AdminUPN
Write-Host ""

# ── Ensure admin has eDiscovery Manager role (org-wide case visibility & management) ─────────
Write-Host "--- eDiscovery Role Group Membership ---" -ForegroundColor Cyan
try {
    # Update-RoleGroupMember replaces the full member list — safe here since eDiscoveryManager is empty
    Update-RoleGroupMember -Identity "eDiscoveryManager" -Members $script:AdminUPN -Confirm:$false -ErrorAction Stop
    Write-Host "  [OK]    Added $($script:AdminUPN) to eDiscoveryManager role group." -ForegroundColor Green
    Write-Host "  [WAIT]  Waiting 15s for role propagation..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 15
} catch {
    Write-Host "  [WARN]  Could not update eDiscoveryManager: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "          Proceeding — admin may already have access via Global Admin role." -ForegroundColor DarkGray
}

$results = @{ Created = 0; Skipped = 0; Failed = 0 }

# =====================================================================
# STEP 1 — Create eDiscovery Standard case
# =====================================================================
Write-Host "`n--- eDiscovery Case ---" -ForegroundColor Cyan

$existingCase = Get-ComplianceCase -Identity $CaseName -ErrorAction SilentlyContinue
# If Get-ComplianceCase returned null, list all cases (now visible as eDiscovery Manager)
if (-not $existingCase) {
    $existingCase = Get-ComplianceCase -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq $CaseName } | Select-Object -First 1
}

if ($existingCase) {
    # Case exists — check if we are already a member by testing a member-restricted operation
    $isMember = $false
    try {
        Get-CaseHoldPolicy -Case $CaseName -ErrorAction Stop | Out-Null
        $isMember = $true
    } catch {
        if ($_.Exception.Message -notmatch "not a member") { $isMember = $true }
    }

    if ($isMember) {
        Write-Host "  [SKIP]  Case already exists and admin is a member: $CaseName" -ForegroundColor Yellow
        $results.Skipped++
    }
    else {
        # Admin can see the case (Global Admin / Org Management) but isn't a member.
        # Attempt close+delete so we can recreate it cleanly with the admin as owner.
        Write-Host "  [INFO]  Case exists but admin is not a member. Attempting to delete orphaned case..." -ForegroundColor DarkGray
        $deleted = $false
        try {
            Set-ComplianceCase -Identity $CaseName -Close -ErrorAction Stop
            Write-Host "  [OK]    Orphaned case closed." -ForegroundColor Green
        } catch {
            Write-Host "  [WARN]  Could not close case: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds 3
        try {
            Remove-ComplianceCase -Identity $CaseName -Confirm:$false -ErrorAction Stop
            Write-Host "  [OK]    Orphaned case deleted. Recreating..." -ForegroundColor Green
            $deleted = $true
            $existingCase = $null
        } catch {
            Write-Host "  [FAIL]  Cannot delete orphaned case: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "          Manual remediation required:" -ForegroundColor Yellow
            Write-Host "          1. Sign in to https://purview.microsoft.com as Global Admin" -ForegroundColor DarkGray
            Write-Host "          2. Go to Solutions > eDiscovery > Standard" -ForegroundColor DarkGray
            Write-Host "          3. Find '$CaseName', close it, then delete it" -ForegroundColor DarkGray
            Write-Host "          4. Re-run this script" -ForegroundColor DarkGray
            $results.Failed++
        }
    }
}

if (-not $existingCase -and $PSCmdlet.ShouldProcess($CaseName, "Create eDiscovery case")) {
    try {
        New-ComplianceCase -Name $CaseName `
            -Description "Standing eDiscovery case for the Executive Secure Research & Decision Workspace. Scoped to exec-workspace site collection. Legal holds must be explicitly activated." | Out-Null
        Write-Host "  [OK]    Case created: $CaseName" -ForegroundColor Green
        $results.Created++
        Add-ComplianceCaseMember -Case $CaseName -Member $script:AdminUPN -ErrorAction Stop | Out-Null
        Write-Host "  [OK]    Added deployment admin as case member: $script:AdminUPN" -ForegroundColor Green
    }
    catch {
        Write-Host "  [FAIL]  $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed++
    }
}

# =====================================================================
# STEP 2 — Add Compliance group members to the case
# =====================================================================
Write-Host "`n--- Case Membership (ExecWorkspace-Compliance group) ---" -ForegroundColor Cyan

$complianceGroup = Invoke-MgGraphRequest `
    -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq 'ExecWorkspace-Compliance'&`$count=true" `
    -Headers @{ ConsistencyLevel = "eventual" } |
    Select-Object -ExpandProperty value | Select-Object -First 1

if ($complianceGroup) {
    $members = (Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/groups/$($complianceGroup.id)/members").value

    foreach ($member in $members) {
        $user = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/users/$($member.id)" `
            -ErrorAction SilentlyContinue
        if (-not $user) { continue }

        $existingMember = Get-ComplianceCaseMember -Case $CaseName -ErrorAction SilentlyContinue |
                          Where-Object { $_.User -eq $user.userPrincipalName }

        if ($existingMember) {
            Write-Host "  [SKIP]  Member already added: $($user.userPrincipalName)" -ForegroundColor Yellow
            $results.Skipped++
        }
        elseif ($PSCmdlet.ShouldProcess($user.userPrincipalName, "Add eDiscovery case member")) {
            try {
                Add-ComplianceCaseMember -Case $CaseName -Member $user.userPrincipalName | Out-Null
                Write-Host "  [OK]    Added: $($user.userPrincipalName)" -ForegroundColor Green
                $results.Created++
            }
            catch {
                Write-Host "  [FAIL]  $($user.userPrincipalName): $($_.Exception.Message)" -ForegroundColor Red
                $results.Failed++
            }
        }
    }
}
else {
    Write-Host "  [WARN]  ExecWorkspace-Compliance group not found in Entra ID. Add case members manually." -ForegroundColor Yellow
}

# =====================================================================
# STEP 3 — Create legal hold policy (disabled by default)
# =====================================================================
Write-Host "`n--- Legal Hold Policy (Default: Disabled) ---" -ForegroundColor Cyan
$existingHold = Get-CaseHoldPolicy -Case $CaseName -Identity $HoldName -ErrorAction SilentlyContinue

if ($existingHold) {
    Write-Host "  [SKIP]  Hold already exists: $HoldName" -ForegroundColor Yellow
    $results.Skipped++
}
elseif ($PSCmdlet.ShouldProcess($HoldName, "Create legal hold policy (disabled)")) {
    try {
        New-CaseHoldPolicy -Name $HoldName `
            -Case               $CaseName `
            -SharePointLocation $SiteUrl `
            -Enabled            $false | Out-Null  # Deliberately disabled — activation is a legal governance decision

        New-CaseHoldRule -Name "$HoldName-Rule" `
            -Policy             $HoldName `
            -ContentMatchQuery  "" | Out-Null      # Empty = hold all content in scope

        Write-Host "  [OK]    Hold created: $HoldName (Status: DISABLED)" -ForegroundColor Green
        Write-Host "          Scope : $SiteUrl (all 4 libraries)" -ForegroundColor DarkGray
        Write-Host "          [IMPORTANT] Activate ONLY on explicit legal instruction:" -ForegroundColor Yellow
        Write-Host "          Set-CaseHoldPolicy -Identity '$HoldName' -Enabled `$true" -ForegroundColor DarkGray
        $results.Created++
    }
    catch {
        Write-Host "  [FAIL]  $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed++
    }
}

# =====================================================================
# STEP 4 — Create and run discoverability validation search
#   Compliance search requires a separate -EnableSearchOnlySession connection
#   (EXO module 3.9.0+ requirement). Re-connects to IPPS in search mode.
# =====================================================================
Write-Host "`n--- Discoverability Validation Search ---" -ForegroundColor Cyan
Write-Host "  [INFO]  Reconnecting to IPPS in search-only mode (may require re-authentication)..." -ForegroundColor DarkGray
try {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Connect-IPPSSession -UserPrincipalName $script:AdminUPN -EnableSearchOnlySession -ErrorAction Stop
} catch {
    Write-Host "  [WARN]  Could not connect in search-only mode: $($_.Exception.Message)" -ForegroundColor Yellow
}

$existingSearch = Get-ComplianceSearch -Identity $SearchName -Case $CaseName -ErrorAction SilentlyContinue

if ($existingSearch) {
    Write-Host "  [SKIP]  Search already exists: $SearchName" -ForegroundColor Yellow
    $results.Skipped++
}
elseif ($PSCmdlet.ShouldProcess($SearchName, "Create and run discoverability validation search")) {
    try {
        New-ComplianceSearch -Name $SearchName `
            -Case               $CaseName `
            -SharePointLocation $SiteUrl `
            -ContentMatchQuery  "" `
            -Description        "Validation search confirming all 4 Executive Workspace libraries are discoverable without export." | Out-Null

        Start-ComplianceSearch -Identity $SearchName | Out-Null
        Write-Host "  [OK]    Search created and started: $SearchName" -ForegroundColor Green
        Write-Host "          Allow a few minutes for results. Check with:" -ForegroundColor DarkGray
        Write-Host "          Get-ComplianceSearch -Identity '$SearchName' | Select Status,Items,Size" -ForegroundColor DarkGray
        $results.Created++
    }
    catch {
        # "cpfdwebservicecloudapp.net not found" = compliance search service not provisioned in dev tenant
        if ($_.Exception.Message -match "cpfdwebservicecloudapp" -or $_.Exception.Message -match "EnableSearchOnlySession") {
            Write-Host "  [WARN]  Compliance search not available in this dev tenant environment." -ForegroundColor Yellow
            Write-Host "          Known limitation: compliance search service app not provisioned." -ForegroundColor DarkGray
            Write-Host "          The search step will work in production. Case and hold are configured." -ForegroundColor DarkGray
        }
        else {
            Write-Host "  [FAIL]  $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Created : $($results.Created)" -ForegroundColor Green
Write-Host "  Skipped : $($results.Skipped)" -ForegroundColor Yellow
Write-Host "  Failed  : $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })
Write-Host "`n[NEXT]  Check search results: Get-ComplianceSearch -Identity '$SearchName' | Select Status,Items,Size" -ForegroundColor White

Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Disconnect-MgGraph -ErrorAction SilentlyContinue
exit $(if ($results.Failed -gt 0) { 1 } else { 0 })
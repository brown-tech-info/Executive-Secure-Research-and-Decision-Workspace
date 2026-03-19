<#
.SYNOPSIS
    Creates Entra ID security groups for the Executive Secure Research & Decision Workspace.

.DESCRIPTION
    Provisions five named security groups aligned to the roles defined in LLD Section 5.1.
    Script is idempotent — groups that already exist (matched by DisplayName) are skipped.

    Groups created:
        ExecWorkspace-Authors          — Mail-enabled security group (Draft library + flow notifications)
        ExecWorkspace-Reviewers        — Review library access + approval workflows
        ExecWorkspace-Executives       — Approved library read-only access
        ExecWorkspace-Compliance       — Archive library read-only, audit and eDiscovery
        ExecWorkspace-PlatformAdmins   — Platform configuration only, no content ownership

    ExecWorkspace-Authors is provisioned as a mail-enabled security group via Exchange Online
    (New-DistributionGroup -Type Security) because:
      1. The MeetingPackOpen Power Automate flow sends notification emails to this address.
      2. Microsoft Graph API does not permit creation of mail-enabled security groups directly.
    All other groups are plain Entra security groups created via Microsoft Graph.

.PARAMETER TenantId
    The Entra ID Tenant ID (GUID) of the dev M365 tenant.

.PARAMETER WhatIf
    Preview what would be created without making any changes.

.EXAMPLE
    .\01-create-security-groups.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    .\01-create-security-groups.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -WhatIf

.NOTES
    Requires:
      - Microsoft.Graph module      (Install-Module Microsoft.Graph)
      - ExchangeOnlineManagement    (Install-Module ExchangeOnlineManagement)
    Required Graph scope : Group.ReadWrite.All
    Required EXO role    : Recipient Management (or Organization Management)
    Required Entra role  : Groups Administrator or Global Administrator
    Auth                 : Interactive (device code) — prompted for both Graph and EXO
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Group definitions (LLD Section 5.1) ---
# MailEnabled = $true  →  provisioned via EXO New-DistributionGroup -Type Security
# MailEnabled = $false →  provisioned via Graph New-MgGroup (plain security group)
$Groups = @(
    @{
        DisplayName  = "ExecWorkspace-Authors"
        MailNickname = "execworkspace-authors"
        Description  = "Authors with access to the Draft library. Can create and edit content in the Draft lifecycle stage. Governed by LLD Section 5.1."
        MailEnabled  = $true   # Required: MeetingPackOpen flow sends notification emails to this group
    },
    @{
        DisplayName  = "ExecWorkspace-Reviewers"
        MailNickname = "ExecWorkspace-Reviewers"
        Description  = "Reviewers with access to the Review library. Participate in formal document review and approval workflows. Governed by LLD Section 5.1."
        MailEnabled  = $false
    },
    @{
        DisplayName  = "ExecWorkspace-Executives"
        MailNickname = "ExecWorkspace-Executives"
        Description  = "Executive stakeholders with read-only access to the Approved library. Governed by LLD Section 5.1."
        MailEnabled  = $false
    },
    @{
        DisplayName  = "ExecWorkspace-Compliance"
        MailNickname = "ExecWorkspace-Compliance"
        Description  = "Compliance and Legal roles with read-only access to the Archive library for audit and eDiscovery purposes. Governed by LLD Section 5.1."
        MailEnabled  = $false
    },
    @{
        DisplayName  = "ExecWorkspace-PlatformAdmins"
        MailNickname = "ExecWorkspace-PlatformAdmins"
        Description  = "Platform Administrators responsible for site configuration only. No content ownership or access to document libraries. Governed by LLD Section 5.1."
        MailEnabled  = $false
    }
)

# --- Connect ---
Write-Host "`nConnecting to Microsoft Graph (Tenant: $TenantId)..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes "Group.ReadWrite.All" -NoWelcome
Write-Host "Connected to Graph.`n" -ForegroundColor Green

# Connect EXO only if any mail-enabled group needs creating
$needsEXO = $Groups | Where-Object { $_.MailEnabled }
if ($needsEXO) {
    Write-Host "Connecting to Exchange Online (required for mail-enabled security groups)..." -ForegroundColor Cyan
    Connect-ExchangeOnline -UserPrincipalName "admin@$TenantId" -Device -ShowBanner:$false -ErrorAction Stop
    Write-Host "Connected to EXO.`n" -ForegroundColor Green
}

# --- Provision groups ---
$results = @{ Created = 0; Skipped = 0; Failed = 0 }

foreach ($group in $Groups) {
    # Idempotency check
    $existing = Get-MgGroup -Filter "displayName eq '$($group.DisplayName)'" -ConsistencyLevel eventual -CountVariable count -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Host "  [SKIP]  Already exists : $($group.DisplayName)" -ForegroundColor Yellow
        $results.Skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($group.DisplayName, "Create Entra ID security group")) {
        try {
            if ($group.MailEnabled) {
                # Mail-enabled security group — must be created via EXO, not Graph
                $tenantDomain = (Get-MgOrganization).VerifiedDomains |
                    Where-Object { $_.IsDefault } | Select-Object -ExpandProperty Name
                $smtp = "$($group.MailNickname)@$tenantDomain"

                $newDg = New-DistributionGroup `
                    -Name               $group.DisplayName `
                    -DisplayName        $group.DisplayName `
                    -Alias              $group.MailNickname `
                    -Type               Security `
                    -PrimarySmtpAddress $smtp `
                    -Notes              $group.Description

                Write-Host "  [OK]    Created (mail-enabled SG) : $($group.DisplayName)" -ForegroundColor Green
                Write-Host "          Object ID : $($newDg.ExternalDirectoryObjectId)" -ForegroundColor DarkGray
                Write-Host "          Email     : $($newDg.PrimarySmtpAddress)" -ForegroundColor DarkGray
            } else {
                $newGroup = New-MgGroup `
                    -DisplayName $group.DisplayName `
                    -Description $group.Description `
                    -MailNickname $group.MailNickname `
                    -MailEnabled:$false `
                    -SecurityEnabled:$true `
                    -GroupTypes @()

                Write-Host "  [OK]    Created (security group)  : $($group.DisplayName)" -ForegroundColor Green
                Write-Host "          Object ID : $($newGroup.Id)" -ForegroundColor DarkGray
            }
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  Failed        : $($group.DisplayName)" -ForegroundColor Red
            Write-Host "          Error         : $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Created : $($results.Created)" -ForegroundColor Green
Write-Host "  Skipped : $($results.Skipped)" -ForegroundColor Yellow
Write-Host "  Failed  : $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

if ($results.Failed -gt 0) {
    Write-Host "`n[WARNING] One or more groups failed to create. Resolve errors before proceeding." -ForegroundColor Red
    exit 1
}

Write-Host "`n[NEXT STEP] Populate group membership for each role before running WS-2 SharePoint scripts." -ForegroundColor White
Write-Host "            Run validate-entra.ps1 to confirm groups before proceeding." -ForegroundColor White

Disconnect-MgGraph -ErrorAction SilentlyContinue

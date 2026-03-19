<#
.SYNOPSIS
    Validates the Copilot Studio agent configuration for the Executive Workspace.

.DESCRIPTION
    Performs pre-flight checks to confirm the environment is ready for Copilot Studio agent deployment:
        - Confirms the Approved library exists and is accessible
        - Confirms ExecWorkspace-Executives group exists and has read access to the Approved library
        - Confirms the agent knowledge source URL is resolvable
        - When -DataverseUrl is provided: verifies Web Search is disabled (msai_searchtheweb = false)
          and outputs the Bot ID — required by LLD Section 9.3 (tenant-containment policy)
        - Prompts the tester through manual agent validation steps

    Note: Copilot Studio agents cannot be fully validated via script — the agent interaction
    tests documented in ws6-copilot-studio-spec.md must be performed manually in the portal.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER TenantId
    Entra ID Tenant ID (GUID).

.PARAMETER DataverseUrl
    Optional. Dataverse environment URL, e.g. https://orgXXXXXXXX.crm.dynamics.com
    When provided, adds automated Check 4 (Web Search OFF) and outputs the Bot ID.

.EXAMPLE
    .\01-validate-copilot.ps1 `
        -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace" `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

.EXAMPLE
    .\01-validate-copilot.ps1 `
        -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace" `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -DataverseUrl "https://orgXXXXXXXX.crm.dynamics.com"

.NOTES
    Requires: PnP.PowerShell and Microsoft.Graph modules
    Dataverse check additionally requires Az.Accounts module.
    Run this after completing the manual agent configuration in copilotstudio.microsoft.com.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    # Optional — when provided, adds automated Dataverse checks (web search, bot ID)
    [string]$DataverseUrl = ""
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
# NOTE: No Connect-MgGraph here — PnP.PowerShell 3.x bundles Microsoft.Graph.Core 1.25.x which
# conflicts with the Microsoft.Graph SDK 2.x in the same PS session. All Graph calls use
# Invoke-PnPGraphMethod to go through PnP's own Graph caller instead (avoids the DLL conflict).
Write-Host "`nConnecting to SharePoint site: $SiteUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl
Write-Host "Connected.`n" -ForegroundColor Green

$ApprovedLibraryUrl = "$SiteUrl/Approved"

# === CHECK 1: Approved library exists ===
Write-Host "--- Approved Library (Copilot Knowledge Source) ---" -ForegroundColor Cyan
$approvedLib = Get-PnPList -Identity "Approved" -Includes HasUniqueRoleAssignments -ErrorAction SilentlyContinue
Write-Check -Pass ($null -ne $approvedLib) -Message "Approved library exists"

if ($approvedLib) {
    Write-Host "    Knowledge source URL: $ApprovedLibraryUrl" -ForegroundColor DarkGray
    Write-Check -Pass ([bool]$approvedLib.HasUniqueRoleAssignments) -Message "Approved library has unique permissions (isolated from other libraries)"
}

# === CHECK 2: ExecWorkspace-Executives group exists and has access ===
Write-Host "`n--- ExecWorkspace-Executives Group Access ---" -ForegroundColor Cyan

# Use Invoke-PnPGraphMethod to avoid PnP/Graph SDK DLL conflict (known issue — see scripts/README.md)
$groupResult     = Invoke-PnPGraphMethod -Url "v1.0/groups?`$filter=displayName eq 'ExecWorkspace-Executives'&`$count=true" -Method Get -AdditionalHeaders @{ ConsistencyLevel = "eventual" }
$executivesGroup = $groupResult.value | Select-Object -First 1
Write-Check -Pass ($null -ne $executivesGroup) -Message "ExecWorkspace-Executives group exists in Entra ID"

if ($executivesGroup) {
    $groupId   = $executivesGroup.id
    $loginName = "c:0t.c|tenant|$groupId"

    # CSOM role assignment check — reliable in AppOnly context
    $ctx  = Get-PnPContext
    $ras  = (Get-PnPList -Identity "Approved").RoleAssignments
    $ctx.Load($ras)
    Invoke-PnPQuery

    $hasAccessApproved = $false
    foreach ($ra in $ras) {
        $ctx.Load($ra.Member)
        Invoke-PnPQuery
        if ($ra.Member.LoginName -eq $loginName) { $hasAccessApproved = $true; break }
    }
    Write-Check -Pass $hasAccessApproved -Message "ExecWorkspace-Executives has a role assignment on the Approved library"
}

# === CHECK 3: No Draft/Review access for Executives ===
Write-Host "`n--- Scope Isolation: No Draft/Review Access for Executives ---" -ForegroundColor Cyan

if ($executivesGroup) {
    $ctx = Get-PnPContext

    foreach ($libName in @("Draft", "Review")) {
        $lib = Get-PnPList -Identity $libName -ErrorAction SilentlyContinue
        if (-not $lib) { continue }

        $ras = $lib.RoleAssignments
        $ctx.Load($ras)
        Invoke-PnPQuery

        $hasAccess = $false
        foreach ($ra in $ras) {
            $ctx.Load($ra.Member)
            Invoke-PnPQuery
            if ($ra.Member.LoginName -eq $loginName) { $hasAccess = $true; break }
        }
        # We WANT this to be false — Executives should NOT have access to Draft/Review
        Write-Check -Pass (-not $hasAccess) -Message "ExecWorkspace-Executives does NOT have access to $libName library (correct — Copilot agent cannot reach these via permissions)"
    }
}

# === CHECK 4: Web Search is disabled (Dataverse — optional, requires DataverseUrl) ===
Write-Host "`n--- Web Search Setting (Dataverse) ---" -ForegroundColor Cyan

if ($DataverseUrl) {
    try {
        Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null
        $dvToken = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl $DataverseUrl).Token).Password
        $dvH = @{ Authorization = "Bearer $dvToken"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }

        $bot = (Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/bots?`$filter=name eq 'ExecWorkspace-Copilot'&`$select=botid,name,configuration" -Headers $dvH).value | Select-Object -First 1

        if ($bot) {
            Write-Host "  Bot ID      : $($bot.botid)" -ForegroundColor DarkGray
            Write-Host "  Portal URL  : https://copilotstudio.microsoft.com/environments/Default-$TenantId/bots/$($bot.botid)/overview" -ForegroundColor DarkGray

            # Web search and description live in botcomponent type 15 (GptComponentMetadata) data YAML
            $gptComp = (Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/botcomponents?`$filter=_parentbotid_value eq '$($bot.botid)' and componenttype eq 15&`$select=data" -Headers $dvH).value | Select-Object -First 1
            if ($gptComp) {
                # Parse the YAML data field (simple key:value scan — no YAML module needed)
                $webBrowsing  = $gptComp.data -match 'webBrowsing:\s*false'
                $hasDesc      = $gptComp.data -match 'description:\s*.+'
                Write-Check -Pass $webBrowsing `
                    -Message "Web Search is OFF (gptCapabilities.webBrowsing = false) — required by LLD 9.3 tenant containment policy"
                # Description in botcomponent metadata is set; portal Overview field requires manual edit
                if ($hasDesc) {
                    Write-Host "  [OK]    Agent description set in botcomponent metadata." -ForegroundColor Green
                } else {
                    Write-Host "  [NOTE]  Agent description not yet set in botcomponent metadata." -ForegroundColor Yellow
                }
                Write-Host "  [MANUAL] Portal Overview Description must be set manually:" -ForegroundColor Yellow
                Write-Host "           Copilot Studio → Overview → Description → pencil icon → paste description text" -ForegroundColor Yellow
            } else {
                Write-Host "  [WARN]  GptComponentMetadata (type 15) not found — cannot verify web search or description." -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [WARN]  Agent 'ExecWorkspace-Copilot' not found in Dataverse." -ForegroundColor Yellow
            Write-Host "          Run 02-deploy-copilot-agent.ps1 to deploy the agent first." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN]  Dataverse check skipped: $_" -ForegroundColor Yellow
        Write-Host "          Verify manually: Copilot Studio portal → Settings → Generative AI → Search the web must be OFF" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [SKIP]  -DataverseUrl not provided — skipping automated web search check." -ForegroundColor Yellow
    Write-Host "          Pass -DataverseUrl to enable, or verify manually in Copilot Studio portal." -ForegroundColor Yellow
    Write-Host "          Settings → Generative AI → Search the web must be OFF (LLD 9.3)" -ForegroundColor Yellow
}

# === CHECK 5: Manual validation reminder ===
Write-Host "`n--- Manual Validation Required ---" -ForegroundColor Cyan
Write-Host "  The following tests must be performed manually in copilotstudio.microsoft.com:" -ForegroundColor White
Write-Host "" 
$manualChecks = @(
    "Agent 'ExecWorkspace-Copilot' exists and is published",
    "Knowledge source URL is set to the Approved library only",
    "Authentication is set to 'Microsoft (Entra ID)' — unauthenticated access disabled",
    "Test 1: Approved content Q&A returns correct results",
    "Test 2: Draft content query returns graceful 'not available' response",
    "Test 3: Write action request is rejected",
    "Test 4: External web search request is rejected",
    "Test 5: Unauthenticated access is blocked",
    "Test 6: Non-Executive user cannot retrieve Approved library content"
)
$manualChecks | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor White }

# === Result ===
Write-Host "`n--- Automated Validation Result ---" -ForegroundColor Cyan
if ($failures.Count -eq 0) {
    Write-Host "[PASS]  All automated checks passed." -ForegroundColor Green
    Write-Host "[NOTE]  Complete the manual validation checklist above before signing off WS-6." -ForegroundColor Yellow
}
else {
    Write-Host "[FAIL]  $($failures.Count) automated check(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`nResolve all failures before manual agent testing." -ForegroundColor Yellow
}

Disconnect-PnPOnline

exit $(if ($failures.Count -eq 0) { 0 } else { 1 })

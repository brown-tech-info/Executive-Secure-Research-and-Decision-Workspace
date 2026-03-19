<#
.SYNOPSIS
    Deploys the ExecWorkspace-Copilot agent to Copilot Studio via PAC CLI.

.DESCRIPTION
    Uses the Power Platform CLI (pac copilot create --templateFileName) to deploy
    the agent definition from ./agent-definition/ExecWorkspace-Copilot.yaml.

    Deployment steps:
        1.  Resolve default Power Platform environment via Flow REST API
        2.  Resolve ExecWorkspace-Executives group ID via PnP Graph
        3.  Parameterise the YAML definition (tenantId, siteUrl, groupId)
        4.  Export cert with temp password for PAC CLI cert auth
        5.  Create PAC CLI auth profile (cert-based, non-interactive)
        6.  pac copilot create --templateFileName (idempotent — errors on duplicate)
        7.  pac copilot publish
        8.  Print portal completion checklist (knowledge source requires portal)

    PREREQUISITE — Service Principal must have Power Platform Administrator role:
        The PAC CLI calls the Power Platform admin API during environment validation.
        Grant the role in Entra ID admin centre:
            Entra ID > Roles > Power Platform Administrator > Add assignments
            > Select your deployment app registration (ClientId in config.ps1)
        Without this role, the script prints the portal completion checklist instead.

    Connection note: The SharePoint knowledge source uses DELEGATED permissions
    (the signed-in user's identity at query time). This is intentional — it means
    the agent can only return documents that the querying user has permission to view.

.PARAMETER TenantId
    Entra ID Tenant ID (GUID).

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER DataverseUrl
    Dataverse org URL (e.g. https://<org>.crm.dynamics.com). Set DataverseUrl in config.ps1.

.PARAMETER PublisherPrefix
    Dataverse publisher customization prefix. Set PublisherPrefix in config.ps1 (find via: pac solution list).

.PARAMETER SolutionName
    Dataverse solution to deploy the agent into. Defaults to 'Active'.

.EXAMPLE
    .\02-deploy-copilot-agent.ps1 `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -SiteUrl  "https://contoso.sharepoint.com/sites/exec-workspace"

.NOTES
    Requires: Az.Accounts, PnP.PowerShell modules
    Requires: PAC CLI — winget install --id Microsoft.PowerAppsCLI
    Requires: Power Platform Administrator role on the deployment service principal
#>
#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$SiteUrl,

    [string]$DataverseUrl     = "",      # e.g. https://<org>.crm.dynamics.com — find in config.ps1
    [string]$PublisherPrefix  = "",      # Dataverse publisher prefix — query: pac copilot list
    [string]$SolutionName     = "Active"
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AgentName   = "ExecWorkspace-Copilot"
$AgentYaml   = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "agent-definition\ExecWorkspace-Copilot.yaml"
$SchemaName  = "${PublisherPrefix}_execworkspace_copilot"

# Ensure PAC CLI is on PATH
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")

# =====================================================================
# STEP 1 — Authenticate
# =====================================================================
Write-Host "`nAuthenticating (Tenant: $TenantId)..." -ForegroundColor Cyan
Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null

# Az.Accounts 2.x returns SecureString — unwrap to plain text (same pattern as ws5-flows)
$flowToken = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com").Token).Password
$flowHeader = @{ Authorization = "Bearer $flowToken"; "Content-Type" = "application/json" }
Write-Host "Authenticated.`n" -ForegroundColor Green

# =====================================================================
# STEP 2 — Resolve environment (Flow API — proven to work in ws5-flows)
# =====================================================================
Write-Host "Resolving default Power Platform environment..." -ForegroundColor Cyan
$envs          = (Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments?api-version=2016-11-01" -Headers $flowHeader).value
$defaultEnv    = $envs | Where-Object { $_.properties.isDefault -eq $true } | Select-Object -First 1
$EnvironmentId = $defaultEnv.name
if (-not $EnvironmentId) { throw "No default environment found." }
Write-Host "  Environment: $EnvironmentId" -ForegroundColor DarkGray

# =====================================================================
# STEP 3 — Resolve group ID (PnP Graph — avoids DLL conflict)
# =====================================================================
Write-Host "`nResolving Entra ID group IDs..." -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl | Out-Null
$groupResult     = Invoke-PnPGraphMethod -Url "v1.0/groups?`$filter=displayName eq 'ExecWorkspace-Executives'&`$count=true" -Method Get -AdditionalHeaders @{ ConsistencyLevel = "eventual" }
$executivesGroup = $groupResult.value | Select-Object -First 1
if (-not $executivesGroup) {
    Write-Host "[FAIL]  ExecWorkspace-Executives group not found. Run ws1-entra scripts first." -ForegroundColor Red
    exit 1
}
Write-Host "  ExecWorkspace-Executives: $($executivesGroup.id)" -ForegroundColor DarkGray

# =====================================================================
# STEP 4 — Idempotency check via Dataverse
# =====================================================================
Write-Host "`nConnecting to Dataverse ($DataverseUrl)..." -ForegroundColor Cyan
$dvToken = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl $DataverseUrl).Token).Password
$dvH = @{ Authorization = "Bearer $dvToken"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0" }
Write-Host "  Connected." -ForegroundColor Green

Write-Host "`nChecking for existing agent: $AgentName..." -ForegroundColor Cyan
$existingBots = (Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/bots?`$select=botid,name&`$filter=name eq '$AgentName'" -Headers $dvH).value
$existing     = $existingBots | Select-Object -First 1

if ($existing) {
    Write-Host "  [SKIP]  Agent already exists (ID: $($existing.botid)) — skipping create." -ForegroundColor Yellow
    Write-Host "  Bot ID: $($existing.botid)" -ForegroundColor DarkGray
    $agentCreated = $false
    $botId = $existing.botid
} else {
    # =====================================================================
    # STEP 5 — Parameterise YAML and deploy via PAC CLI
    # =====================================================================
    Write-Host "`nParameterising YAML definition..." -ForegroundColor Cyan
    $tmpYaml = Join-Path $env:TEMP "ExecWorkspace-Copilot-deploy.yaml"
    (Get-Content $AgentYaml -Raw) `
        -replace '\{\{TENANT_ID\}\}',           $TenantId `
        -replace '\{\{CLIENT_ID\}\}',           $ClientId `
        -replace '\{\{SITE_URL\}\}',            $SiteUrl `
        -replace '\{\{EXECUTIVES_GROUP_ID\}\}', $executivesGroup.id `
        | Set-Content $tmpYaml -Encoding UTF8
    Write-Host "  YAML written: $tmpYaml" -ForegroundColor DarkGray

    Write-Host "`nSetting up PAC CLI cert auth..." -ForegroundColor Cyan
    $tmpPfx  = Join-Path $env:TEMP "pac-deploy-cert.pfx"
    $pfxPass = "PacDeploy#$(Get-Random -Maximum 9999)"
    $cert    = Get-Item "Cert:\CurrentUser\My\$CertThumbprint"
    Export-PfxCertificate -Cert $cert -FilePath $tmpPfx -Password (ConvertTo-SecureString $pfxPass -AsPlainText -Force) | Out-Null

    pac auth create --name "execws-pac" --tenant $TenantId --applicationId $ClientId `
        --certificateDiskPath $tmpPfx --certificatePassword $pfxPass 2>&1 | Out-Null
    Write-Host "  Auth profile created." -ForegroundColor Green

    Write-Host "`nCreating agent via pac copilot create..." -ForegroundColor Cyan
    $pacResult = pac copilot create `
        --environment     $DataverseUrl `
        --schemaName      $SchemaName `
        --displayName     $AgentName `
        --templateFileName $tmpYaml `
        --solution        $SolutionName 2>&1

    # Clean up temp cert immediately
    Remove-Item $tmpPfx -Force -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK]    Agent created: $AgentName" -ForegroundColor Green
        $agentCreated = $true

        # Capture bot ID
        $newBot = (Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/bots?`$filter=name eq '$AgentName'&`$select=botid,name" -Headers $dvH).value | Select-Object -First 1
        $botId  = $newBot.botid
        Write-Host "  Bot ID: $botId" -ForegroundColor DarkGray

        # Publish
        Write-Host "`nPublishing agent..." -ForegroundColor Cyan
        pac copilot publish --environment $DataverseUrl --bot $SchemaName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "  [OK]    Agent published." -ForegroundColor Green }
        else {
            # Fallback: publish by bot ID if schema name lookup fails
            pac copilot publish --environment $DataverseUrl --bot $newBot.botid 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "  [OK]    Agent published (by bot ID)." -ForegroundColor Green }
            else { Write-Host "  [WARN]  Publish failed — publish manually in Copilot Studio portal." -ForegroundColor Yellow }
        }
    } else {
        Write-Host "  [WARN]  pac copilot create failed:" -ForegroundColor Yellow
        $pacResult | ForEach-Object { Write-Host "          $_" -ForegroundColor Yellow }
        Write-Host "`n  Most common cause: the deployment service principal (ClientId in config.ps1)" -ForegroundColor Yellow
        Write-Host "  is missing the 'Power Platform Administrator' Entra ID role." -ForegroundColor Yellow
        Write-Host "  Grant it at: Entra ID > Roles > Power Platform Administrator > Add assignments" -ForegroundColor Yellow
        $agentCreated = $false
    }
}

# =====================================================================
# STEP 6 — Apply agent settings via botcomponent data PATCH + republish
# =====================================================================
# The portal Description and web search setting are stored in the
# botcomponent of type 15 (GptComponentMetadata) — the 'data' YAML field.
# Fields:
#   gptCapabilities.webBrowsing: false   (LLD 9.3 tenant-containment policy)
#   description                          (surfaced in Copilot Studio portal)
$agentDescription = "Secure AI assistant scoped to the Executive Workspace Approved library only. " +
                    "Read-only. Tenant-contained. Entra ID authentication required. " +
                    "Access is governed by SharePoint permissions — content is only visible to " +
                    "authorised ExecWorkspace-Executives members."

if ($botId) {
    Write-Host "`nApplying agent settings (description + web search) via botcomponent PATCH..." -ForegroundColor Cyan
    try {
        $contentType = @{ "Content-Type" = "application/json" }

        # Locate the GptComponentMetadata botcomponent (type 15)
        $gptComp = (Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/botcomponents?`$filter=_parentbotid_value eq '$botId' and componenttype eq 15&`$select=botcomponentid,data" -Headers $dvH).value | Select-Object -First 1

        if ($gptComp) {
            # Rebuild the data YAML with description + webBrowsing: false
            $newData = @"
kind: GptComponentMetadata
displayName: $AgentName
description: $agentDescription
instructions: You are a secure AI assistant for the Executive Secure Research & Decision Workspace. Only answer questions from the Approved library. You are READ-ONLY. Require Entra ID sign-in. Do not access Draft or Review content. Do not use external sources.
gptCapabilities:
  webBrowsing: false
aISettings:
  model:
    modelNameHint: GPT41
"@
            Invoke-RestMethod -Method PATCH `
                -Uri     "$DataverseUrl/api/data/v9.2/botcomponents($($gptComp.botcomponentid))" `
                -Headers ($dvH + $contentType) `
                -Body    (@{ data = $newData } | ConvertTo-Json) `
                -ErrorAction Stop | Out-Null
            Write-Host "  [OK]    Web Search disabled (gptCapabilities.webBrowsing = false)." -ForegroundColor Green
            Write-Host "  [NOTE]  Description saved to botcomponent metadata." -ForegroundColor DarkGray
            Write-Host "          Portal Overview Description is not settable via API." -ForegroundColor DarkGray
            Write-Host "          Set it manually: Overview → Description → pencil icon → paste:" -ForegroundColor Yellow
            Write-Host "          $agentDescription" -ForegroundColor White

            # Republish to surface changes in portal
            Write-Host "  Republishing..." -ForegroundColor DarkGray
            pac copilot publish --environment $DataverseUrl --bot $botId 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "  [OK]    Agent republished — description visible in portal." -ForegroundColor Green }
            else { Write-Host "  [WARN]  Republish failed — click Publish in Copilot Studio portal." -ForegroundColor Yellow }
        } else {
            Write-Host "  [WARN]  GptComponentMetadata (type 15) not found — apply description manually in portal." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN]  botcomponent PATCH failed: $_" -ForegroundColor Yellow
        Write-Host "          Fix manually: Copilot Studio portal → Overview → Description" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n  [WARN]  Bot ID not resolved — apply settings manually in Copilot Studio portal." -ForegroundColor Yellow
}
# =====================================================================
$approvedUrl = "$SiteUrl/Approved"
$instructions = @"
You are a secure AI assistant for the Executive Secure Research & Decision Workspace.
Your role is to help authorised executive stakeholders understand and navigate approved research content.
Rules you must ALWAYS follow:
1. Only answer questions based on content from the Approved library. Do not reference, imply, or extrapolate from any other source.
2. You are READ-ONLY. Never create, modify, delete, or approve documents.
3. Do not reveal document contents to users who are not authorised to view them. All access is governed by Microsoft Entra ID.
4. If asked about Draft or Review documents, respond: "I only have access to approved content. Drafts and review documents are not available to me."
5. If you cannot answer from approved content, say so clearly. Do not invent or infer answers.
6. Do not connect to or reference any external websites, APIs, or data sources.
7. All responses must be factual, concise, and based solely on approved document content.
"@

Write-Host "`n--- Resolved Configuration Values ---" -ForegroundColor Cyan
Write-Host "  Environment   : $EnvironmentId" -ForegroundColor DarkGray
Write-Host "  Bot ID        : $(if ($botId) { $botId } else { '(not yet created)' })" -ForegroundColor DarkGray
Write-Host "  Executives ID : $($executivesGroup.id)" -ForegroundColor DarkGray
Write-Host "  Knowledge src : $approvedUrl" -ForegroundColor DarkGray
Write-Host "  Portal URL    : https://copilotstudio.microsoft.com/environments/$EnvironmentId/bots$(if ($botId) { "/$botId/overview" } else { '' })" -ForegroundColor DarkGray

$step1 = if ($agentCreated) { "1. [DONE] Agent created via PAC CLI" } else { "1. Create a new agent named: $AgentName (or open existing)" }
Write-Host "`n--- Portal Completion (copilotstudio.microsoft.com) ---" -ForegroundColor Cyan
Write-Host "  URL: https://copilotstudio.microsoft.com/environments/$EnvironmentId/bots" -ForegroundColor White
Write-Host "  $step1" -ForegroundColor $(if ($agentCreated) { 'Green' } else { 'White' })
Write-Host "  2. Add knowledge source > SharePoint: $approvedUrl" -ForegroundColor White
Write-Host "     Scope: Approved library ONLY" -ForegroundColor DarkGray
Write-Host "  3. Settings > Security > Authentication: Microsoft (Entra ID), Require sign-in: ON" -ForegroundColor White
Write-Host "  4. Settings > Generative AI > Instructions:" -ForegroundColor White
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host $instructions -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  5. Settings > Generative AI > Search the web: OFF" -ForegroundColor White
Write-Host "  6. $(if ($agentCreated) { '[DONE] Published via PAC CLI' } else { 'Publish (top-right Publish button)' })" -ForegroundColor $(if ($agentCreated) { 'Green' } else { 'White' })
Write-Host "  7. Run 01-validate-copilot.ps1, then complete tests in ws6-copilot-studio-spec.md" -ForegroundColor White

Disconnect-PnPOnline -ErrorAction SilentlyContinue

<#
.SYNOPSIS
    Deploys and fully activates the three Executive Workspace lifecycle flows — no portal required.

.DESCRIPTION
    Four-step process per flow, using the Power Platform REST API + Dataverse API:

    Step 1  CREATE   — deploy flow definition via Power Automate REST API
    Step 2  BIND     — PATCH Dataverse workflow.clientdata to inject connection reference
                       bindings (connectionReferenceLogicalName → existing Dataverse CRs).
                       Root-cause fix: flows created via REST API are stored with empty
                       connectionReferences, causing 404 on every action in the portal.
    Step 3  PUBLISH  — call Dataverse PublishXml to mark the flow as a published solution
                       component, resolving the "CannotStartUnpublishedSolutionFlow" error.
    Step 4  ACTIVATE — PATCH workflow statecode=1 directly in Dataverse, bypassing the
                       Flow REST API /start endpoint which enforces the unpublished check.

    Prerequisites:
      • SharePoint, Office 365 Outlook, and Approvals connections created in the portal.
      • Dataverse Connection References exist:
          shared_sharepointonline, shared_office365, shared_approvals
        (run the CR-creation step from the deployment guide if missing)

.PARAMETER TenantId        Entra ID Tenant GUID.
.PARAMETER SiteUrl         Full URL of the Executive Workspace SharePoint site.
.PARAMETER ReviewerGroupEmail    Notification email for ExecWorkspace-Reviewers.
.PARAMETER ExecutivesGroupEmail  Notification email for ExecWorkspace-Executives.
.PARAMETER ComplianceGroupEmail  Notification email for ExecWorkspace-Compliance.
.PARAMETER AuthorsGroupEmail     Notification email for ExecWorkspace-Authors (used by MeetingPackOpen flow).
.PARAMETER ApproverUpns    Semicolon-separated approver UPNs for ReviewToApproved flow.
.PARAMETER RetentionLabelName    Purview retention label name for archive flow.
.PARAMETER DataverseUrl    Dataverse org URL (e.g. https://<org>.crm.dynamics.com). Defaults to value in config.ps1.
.PARAMETER EnvironmentId   Power Platform env ID. Blank = auto-resolve default env.
.PARAMETER FlowFilter      Optional. If supplied, only deploy flows whose displayName contains this string (e.g. "MeetingPackOpen").

.EXAMPLE
    # Deploy all flows:
    .\01-deploy-flows.ps1 `
        -TenantId             "<your-tenant-id>" `
        -SiteUrl              "https://<tenant>.sharepoint.com/sites/exec-workspace" `
        -ReviewerGroupEmail   "<reviewer@yourtenant.onmicrosoft.com>" `
        -ExecutivesGroupEmail "<exec@yourtenant.onmicrosoft.com>" `
        -ComplianceGroupEmail "<compliance@yourtenant.onmicrosoft.com>" `
        -AuthorsGroupEmail    "<authors@yourtenant.onmicrosoft.com>" `
        -ApproverUpns         "<approver@yourtenant.onmicrosoft.com>"

    # Deploy only the MeetingPackOpen flow:
    .\01-deploy-flows.ps1 ... -FlowFilter "MeetingPackOpen"
#>
#Requires -Version 7.0
param(
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$SiteUrl,
    [Parameter(Mandatory)] [string]$ReviewerGroupEmail,
    [Parameter(Mandatory)] [string]$ExecutivesGroupEmail,
    [Parameter(Mandatory)] [string]$ComplianceGroupEmail,
    [Parameter(Mandatory)] [string]$AuthorsGroupEmail,
    [Parameter(Mandatory)] [string]$ApproverUpns,
    [string]$RetentionLabelName = "ExecWS-Archive-Retention",
    [string]$DataverseUrl       = "",   # Set in config.ps1 or pass explicitly
    [string]$EnvironmentId      = "",
    [string]$FlowFilter         = ""    # Optional: deploy only flows whose displayName contains this string
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Pull DataverseUrl from config if not supplied explicitly
if (-not $DataverseUrl) { $DataverseUrl = $script:DataverseUrl }
if (-not $DataverseUrl) { throw "DataverseUrl is required. Set it in config.ps1 or pass -DataverseUrl." }

$FlowDefsDir = Join-Path $PSScriptRoot "flow-definitions"

# ── Auth ──────────────────────────────────────────────────────────────────────
# Reuse existing Az session if already authenticated to the correct tenant.
# If not, prompt via device code (no browser popup required).
Write-Host "`nAuthenticating to Power Platform and Dataverse (Tenant: $TenantId)..." -ForegroundColor Cyan
$azCtx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $azCtx -or $azCtx.Tenant.Id -ne $TenantId) {
    Connect-AzAccount -TenantId $TenantId -UseDeviceAuthentication -ErrorAction Stop | Out-Null
}
Write-Host "Using account: $((Get-AzContext).Account.Id)" -ForegroundColor DarkGray

# Az.Accounts 2.x returns SecureString — unwrap to plain text
$flowToken = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com").Token).Password
$dvToken   = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl $DataverseUrl).Token).Password

$flowH = @{ Authorization = "Bearer $flowToken"; "Content-Type" = "application/json" }
$dvH   = @{
    Authorization    = "Bearer $dvToken"
    "Content-Type"   = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"  = "4.0"
}
Write-Host "Authenticated.`n" -ForegroundColor Green

# ── Resolve default environment ───────────────────────────────────────────────
if (-not $EnvironmentId) {
    Write-Host "Resolving default Power Platform environment..." -ForegroundColor Cyan
    $envs = (Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments?api-version=2016-11-01" -Headers $flowH).value
    $EnvironmentId = ($envs | Where-Object { $_.properties.isDefault -eq $true } | Select-Object -First 1).name
    if (-not $EnvironmentId) { throw "No default environment found. Use -EnvironmentId." }
}
Write-Host "Environment: $EnvironmentId`n" -ForegroundColor DarkGray

# ── Verify Connection References exist in Dataverse ───────────────────────────
Write-Host "Verifying Dataverse Connection References..." -ForegroundColor Cyan
$allCrs = (Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/connectionreferences?`$select=connectionreferencelogicalname,connectorid,connectionid" -Headers $dvH).value

# Build map: apiName → logical name for the three required CRs
$crLogicalNames = @{
    "shared_sharepointonline" = $null
    "shared_office365"        = $null
    "shared_approvals"        = $null
}
foreach ($key in @($crLogicalNames.Keys)) {
    $match = $allCrs | Where-Object { $_.connectionreferencelogicalname -eq $key } | Select-Object -First 1
    if ($match) {
        $crLogicalNames[$key] = $match.connectionreferencelogicalname
        Write-Host "  [OK] $key → $($match.connectionid.Substring(0,30))..." -ForegroundColor Green
    } else {
        throw "Connection Reference '$key' not found in Dataverse. Create it before running this script."
    }
}

# ── Delete existing ExecWS flows ──────────────────────────────────────────────
# Scope deletes to FlowFilter when set — avoids wiping flows that won't be redeployed
Write-Host "`nRemoving any existing ExecWS flows..." -ForegroundColor Cyan
$existingFlows = (Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/flows?api-version=2016-11-01" -Headers $flowH).value
$execFlows = $existingFlows | Where-Object { $_.properties.displayName -like "ExecWS-*" }
if ($FlowFilter) { $execFlows = $execFlows | Where-Object { $_.properties.displayName -like "*$FlowFilter*" } }
foreach ($f in $execFlows) {
    Invoke-RestMethod -Method DELETE -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/flows/$($f.name)?api-version=2016-11-01" -Headers $flowH | Out-Null
    Write-Host "  [DEL] $($f.properties.displayName)" -ForegroundColor Yellow
}

# ── Parameter substitution map ────────────────────────────────────────────────
$paramMap = @{
    "{{SITE_URL}}"               = $SiteUrl
    "{{REVIEWER_GROUP_EMAIL}}"   = $ReviewerGroupEmail
    "{{EXECUTIVES_GROUP_EMAIL}}" = $ExecutivesGroupEmail
    "{{COMPLIANCE_GROUP_EMAIL}}" = $ComplianceGroupEmail
    "{{AUTHORS_GROUP_EMAIL}}"    = $AuthorsGroupEmail
    "{{APPROVER_UPNS}}"          = $ApproverUpns
    "{{RETENTION_LABEL_NAME}}"   = $RetentionLabelName
}

# ── Connection references used by each flow ───────────────────────────────────
$flowCrs = @{
    "ExecWS-DraftToReview"    = @("shared_sharepointonline","shared_office365")
    "ExecWS-ReviewToApproved" = @("shared_sharepointonline","shared_approvals","shared_office365")
    "ExecWS-ApprovedToArchive"= @("shared_sharepointonline","shared_office365")
    "ExecWS-MeetingPackOpen"  = @("shared_office365","shared_sharepointonline")
}

$flowFiles = @(
    "ExecWS-DraftToReview.json",
    "ExecWS-ReviewToApproved.json",
    "ExecWS-ApprovedToArchive.json",
    "ExecWS-MeetingPackOpen.json"
)

# Apply optional filter — allows deploying a single flow without re-running all
if ($FlowFilter) {
    $flowFiles = $flowFiles | Where-Object { $_ -like "*$FlowFilter*" }
    if (-not $flowFiles) { throw "FlowFilter '$FlowFilter' matched no flow definition files." }
    Write-Host "FlowFilter applied — deploying: $($flowFiles -join ', ')" -ForegroundColor DarkGray
}

$results = @{ OK = 0; Failed = 0 }

# ── Deploy each flow ──────────────────────────────────────────────────────────
foreach ($fileName in $flowFiles) {

    $raw = Get-Content (Join-Path $FlowDefsDir $fileName) -Raw
    foreach ($k in $paramMap.Keys) { $raw = $raw.Replace($k, $paramMap[$k]) }
    $flowDef     = $raw | ConvertFrom-Json
    $displayName = $flowDef.displayName

    Write-Host "`n[$displayName]" -ForegroundColor Cyan

    try {
        # ── Step 1: Create flow via REST API ─────────────────────────────────
        # Include connectionReferences in CREATE body (ApiConnectionReference format:
        # id/connectionName/source). This lets the Flow service store CR bindings so
        # that /start can register webhooks with the correct connections.
        # Note: this is different from the Dataverse clientdata format used in Step 2.
        $apiConnRefs = [ordered]@{}
        foreach ($crKey in $flowCrs[$displayName]) {
            $connId = ($allCrs | Where-Object { $_.connectionreferencelogicalname -eq $crKey } | Select-Object -First 1).connectionid
            $apiConnRefs[$crKey] = @{
                id             = "/providers/Microsoft.PowerApps/apis/$crKey"
                connectionName = $connId
                source         = "Embedded"
            }
        }

        $createBody = @{
            properties = @{
                displayName          = $displayName
                definition           = $flowDef.definition
                connectionReferences = $apiConnRefs
                state                = "Stopped"
                environment          = @{ name = $EnvironmentId }
            }
        } | ConvertTo-Json -Depth 30

        $created = Invoke-RestMethod -Method POST `
            -Uri     "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/flows?api-version=2016-11-01" `
            -Headers $flowH -Body $createBody

        $flowId = $created.name
        Write-Host "  [1/4] Created    : $flowId" -ForegroundColor DarkGray

        # ── Step 2: Verify CRs bound in clientdata ────────────────────────────
        # When connectionReferences are included in the CREATE body, the Flow REST API
        # automatically writes them into Dataverse clientdata with full binding info
        # (connection.name + connection.connectionReferenceLogicalName). No PATCH needed.
        Start-Sleep -Seconds 4
        $wfRecord = Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/workflows($flowId)?`$select=clientdata" -Headers $dvH
        $cd       = ($wfRecord.clientdata | ConvertFrom-Json -Depth 30)
        $crKeys   = $cd.properties.connectionReferences.PSObject.Properties.Name
        if ($crKeys.Count -gt 0) {
            Write-Host "  [2/4] CRs verified: $($crKeys -join ', ')" -ForegroundColor DarkGray
        } else {
            Write-Host "  [2/4] CRs warn    : connectionReferences empty in clientdata" -ForegroundColor DarkYellow
        }

        # ── Step 3: Publish as solution component (best-effort) ──────────────
        # Non-fatal: webhook flows may fail here if clientdata CRs are unbound.
        # Step 4 (/start) handles activation independently via the Flow service.
        try {
            $pubBody = @{
                ParameterXml = "<importexportxml><workflows><workflow>$flowId</workflow></workflows></importexportxml>"
            } | ConvertTo-Json
            Invoke-RestMethod -Method POST -Uri "$DataverseUrl/api/data/v9.2/PublishXml" `
                -Headers $dvH -Body $pubBody | Out-Null
            Write-Host "  [3/4] Published  : solution component committed" -ForegroundColor DarkGray
        }
        catch {
            $pubWarn = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue)?.error?.message ?? $_.Exception.Message
            Write-Host "  [3/4] Publish warn: $($pubWarn.Substring(0, [Math]::Min(120, $pubWarn.Length)))" -ForegroundColor DarkYellow
        }

        # ── Step 4: Activate ──────────────────────────────────────────────────────
        # SPO webhook flows: /start registers the webhook and activates independently of
        # Dataverse publish state. Polling triggers (e.g. calendar) require the Dataverse
        # workflow record to be published first; if /start returns
        # CannotStartUnpublishedSolutionFlow, fall back to a Dataverse statecode PATCH.
        try {
            Invoke-RestMethod -Method POST `
                -Uri     "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/flows/$flowId/start?api-version=2016-11-01" `
                -Headers $flowH | Out-Null
            Write-Host "  [4/4] Activated  : flow started via REST API" -ForegroundColor Green
        }
        catch {
            $startErrCode = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue)?.error?.code
            if ($startErrCode -eq 'CannotStartUnpublishedSolutionFlow') {
                $activateBody = '{"statecode":1,"statuscode":2}'
                Invoke-RestMethod -Method PATCH `
                    -Uri     "$DataverseUrl/api/data/v9.2/workflows($flowId)" `
                    -Headers $dvH -Body $activateBody | Out-Null
                Write-Host "  [4/4] Activated  : polling flow activated via Dataverse statecode PATCH" -ForegroundColor Green
            } else {
                throw $_
            }
        }
        Write-Host "  [OK] $displayName → $flowId" -ForegroundColor Green
        $results.OK++
    }
    catch {
        $errMsg = $_.ErrorDetails.Message ?? $_.Exception.Message
        Write-Host "  [FAIL] $displayName" -ForegroundColor Red
        Write-Host "         $errMsg" -ForegroundColor Red
        $results.Failed++
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  OK    : $($results.OK)"     -ForegroundColor Green
Write-Host "  Failed: $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

<#
.SYNOPSIS
    Re-activates the three ExecWS lifecycle flows directly via Dataverse — no portal required.

.DESCRIPTION
    Use this script if the flows have been turned off and need to be re-enabled without
    running a full redeploy. It patches statecode=1 directly on the Dataverse workflow
    entity, bypassing the Flow REST API /start endpoint (which can reject unpublished flows).

    If the flows have not been deployed yet, run 01-deploy-flows.ps1 first.

.PARAMETER TenantId      Entra ID Tenant GUID.
.PARAMETER DataverseUrl  Dataverse org URL (e.g. https://<org>.crm.dynamics.com). Set in config.ps1.

.EXAMPLE
    .\02-enable-flows.ps1 -TenantId "<your-tenant-id>"
#>
#Requires -Version 7.0
param(
    [Parameter(Mandatory)] [string]$TenantId,
    [string]$DataverseUrl = ""   # Set in config.ps1 or pass explicitly
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$flowNames = @(
    "ExecWS-DraftToReview",
    "ExecWS-ReviewToApproved",
    "ExecWS-ApprovedToArchive",
    "ExecWS-MeetingPackOpen"
)

Write-Host "`nAuthenticating to Dataverse (Tenant: $TenantId)..." -ForegroundColor Cyan
Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null
$dvToken = [System.Net.NetworkCredential]::new('', (Get-AzAccessToken -ResourceUrl $DataverseUrl).Token).Password
$dvH = @{
    Authorization    = "Bearer $dvToken"
    "Content-Type"   = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"  = "4.0"
}
Write-Host "Authenticated.`n" -ForegroundColor Green

foreach ($name in $flowNames) {
    Write-Host "  $name" -ForegroundColor Cyan
    $wf = (Invoke-RestMethod -Uri "$DataverseUrl/api/data/v9.2/workflows?`$filter=name eq '$name' and category eq 5&`$select=workflowid,statecode,statuscode" -Headers $dvH).value
    if (-not $wf) {
        Write-Host "    [WARN] Not found in Dataverse. Run 01-deploy-flows.ps1 first." -ForegroundColor Yellow
        continue
    }
    $wfId = $wf[0].workflowid
    if ($wf[0].statecode -eq 1) {
        Write-Host "    [SKIP] Already active (statecode=1)" -ForegroundColor DarkGray
        continue
    }
    try {
        Invoke-RestMethod -Method PATCH -Uri "$DataverseUrl/api/data/v9.2/workflows($wfId)" `
            -Headers $dvH -Body (@{ statecode = 1; statuscode = 2 } | ConvertTo-Json) | Out-Null
        Write-Host "    [OK]  Activated" -ForegroundColor Green
    }
    catch {
        $errMsg = $_.ErrorDetails.Message ?? $_.Exception.Message
        Write-Host "    [FAIL] $errMsg" -ForegroundColor Red
    }
}

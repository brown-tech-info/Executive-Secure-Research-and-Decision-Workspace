<#
.SYNOPSIS
    Creates meeting cadence views in the Approved document library.

.DESCRIPTION
    Provisions five named views on the Approved Library to support executive navigation
    by meeting type and cycle (LLD Section 10.1):

        Board Pack      — ExecWS_MeetingType = Board, sorted by MeetingDate DESC
        SteerCo Pack    — ExecWS_MeetingType = SteerCo, sorted by MeetingDate DESC
        ExecTeam Pack   — ExecWS_MeetingType = ExecTeam, sorted by MeetingDate DESC
        Current Cycle   — ExecWS_MeetingDate in current calendar month, sorted ASC
        By Meeting      — All documents, grouped by ExecWS_MeetingCycle, sorted DESC

    Views include the core document columns plus all meeting cadence metadata fields so
    executives can identify and open the right pack without folder navigation.

    Idempotent — existing views with the same name are deleted and recreated to ensure
    the column set and filters are always current.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\07-create-meeting-views.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace"

.NOTES
    Requires: PnP.PowerShell module
    Required role: SharePoint Administrator or Site Owner
    Run after: 04-add-metadata-columns.ps1 (meeting cadence columns must exist)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteUrl
)

. "$PSScriptRoot\..\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Library = "Approved"

# Columns displayed in all meeting views
$ViewFields = @(
    "DocIcon",
    "LinkFilename",
    "ExecWS_DocumentType",
    "ExecWS_MeetingType",
    "ExecWS_MeetingDate",
    "ExecWS_MeetingCycle",
    "ExecWS_MeetingDecisionId",
    "ExecWS_PackVersion",
    "ExecWS_LifecycleState",
    "ExecWS_DocumentOwner",
    "Modified"
)

# View definitions (LLD Section 10.1)
$Views = @(
    @{
        Name      = "Board Pack"
        Query     = "<Where><Eq><FieldRef Name='ExecWS_MeetingType'/><Value Type='Choice'>Board</Value></Eq></Where><OrderBy><FieldRef Name='ExecWS_MeetingDate' Ascending='FALSE'/></OrderBy>"
        RowLimit  = 100
        Paged     = $true
    },
    @{
        Name      = "SteerCo Pack"
        Query     = "<Where><Eq><FieldRef Name='ExecWS_MeetingType'/><Value Type='Choice'>SteerCo</Value></Eq></Where><OrderBy><FieldRef Name='ExecWS_MeetingDate' Ascending='FALSE'/></OrderBy>"
        RowLimit  = 100
        Paged     = $true
    },
    @{
        Name      = "ExecTeam Pack"
        Query     = "<Where><Eq><FieldRef Name='ExecWS_MeetingType'/><Value Type='Choice'>ExecTeam</Value></Eq></Where><OrderBy><FieldRef Name='ExecWS_MeetingDate' Ascending='FALSE'/></OrderBy>"
        RowLimit  = 100
        Paged     = $true
    },
    @{
        Name      = "Current Cycle"
        # Filter: MeetingDate >= first day of current month AND <= last day of current month
        Query     = "<Where><And><Geq><FieldRef Name='ExecWS_MeetingDate'/><Value Type='DateTime'><Month/></Value></Geq><Leq><FieldRef Name='ExecWS_MeetingDate'/><Value Type='DateTime'><Month Offset='1'/></Value></Leq></And></Where><OrderBy><FieldRef Name='ExecWS_MeetingDate' Ascending='TRUE'/></OrderBy>"
        RowLimit  = 50
        Paged     = $true
    },
    @{
        Name      = "By Meeting"
        Query     = "<OrderBy><FieldRef Name='ExecWS_MeetingDate' Ascending='FALSE'/></OrderBy>"
        RowLimit  = 100
        Paged     = $true
        GroupBy   = "ExecWS_MeetingCycle"
    }
)

Write-Host "`nConnecting to SharePoint site: $SiteUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl
Write-Host "Connected.`n" -ForegroundColor Green

$results = @{ Created = 0; Skipped = 0; Failed = 0 }

Write-Host "--- Provisioning Meeting Views on '$Library' library ---`n" -ForegroundColor Cyan

foreach ($view in $Views) {
    # Idempotent: remove existing view with same name so column set and filters stay current
    $existing = Get-PnPView -List $Library -Identity $view.Name -ErrorAction SilentlyContinue
    if ($existing) {
        if ($PSCmdlet.ShouldProcess($view.Name, "Remove existing view for recreation")) {
            Remove-PnPView -List $Library -Identity $view.Name -Force -ErrorAction SilentlyContinue
            Write-Host "  [RESET] Removed existing view: $($view.Name)" -ForegroundColor DarkGray
        }
    }

    if ($PSCmdlet.ShouldProcess($view.Name, "Create meeting view")) {
        try {
            $params = @{
                List      = $Library
                Title     = $view.Name
                Fields    = $ViewFields
                Query     = $view.Query
                RowLimit  = $view.RowLimit
                Paged     = $view.Paged
            }

            $newView = Add-PnPView @params

            # Apply grouping if specified — inject <GroupBy> into ViewQuery via CSOM
            if ($view.ContainsKey('GroupBy') -and $view.GroupBy) {
                $ctx    = Get-PnPContext
                $list   = Get-PnPList -Identity $Library
                $spView = $list.Views.GetByTitle($view.Name)
                $ctx.Load($spView)
                $ctx.ExecuteQuery()
                $groupByXml = "<GroupBy Collapse='TRUE' GroupLimit='30'><FieldRef Name='$($view.GroupBy)'/></GroupBy>"
                $spView.ViewQuery = "$groupByXml$($spView.ViewQuery)"
                $spView.Update()
                $ctx.ExecuteQuery()
                Write-Host "  [OK]    Grouped by: $($view.GroupBy)" -ForegroundColor Green
            }

            Write-Host "  [OK]    Created: $($view.Name)" -ForegroundColor Green
            $results.Created++
        }
        catch {
            Write-Host "  [FAIL]  $($view.Name): $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed++
        }
    }
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "  Created : $($results.Created)" -ForegroundColor Green
Write-Host "  Failed  : $($results.Failed)"  -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })

if ($results.Failed -gt 0) {
    Write-Host "`n[WARNING] Some views failed. Verify ExecWS_MeetingType and ExecWS_MeetingDate columns exist (run 04-add-metadata-columns.ps1 first)." -ForegroundColor Red
    Disconnect-PnPOnline
    exit 1
}

Write-Host "`n[OK]  Meeting views provisioned on the Approved library." -ForegroundColor Green
Write-Host "      Executives can now navigate packs via: Board Pack | SteerCo Pack | ExecTeam Pack | Current Cycle | By Meeting" -ForegroundColor White
Write-Host "[NEXT] Deploy the MeetingPackOpen flow (WS-5 Step 5.5) to enable calendar-triggered pack creation." -ForegroundColor White

Disconnect-PnPOnline

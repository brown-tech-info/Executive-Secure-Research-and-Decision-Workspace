<#
.SYNOPSIS
    Adds mandatory metadata columns to all four document libraries.

.DESCRIPTION
    Provisions the five mandatory metadata fields defined in LLD Section 4 on each library:

        DocumentType             — Choice (Board Pack, Research Summary, Decision Record, Meeting Minutes, Supporting Material)
        LifecycleState           — Choice (Draft, Review, Approved, Archived) — managed by Power Automate, read-only for users
        MeetingDecisionId        — Single line of text (e.g. BOARD-2025-Q1-01)
        SensitivityClassification — Choice (Confidential – Executive, Highly Confidential – Board)
        DocumentOwner            — Person or Group (single selection)

    Idempotent — existing columns are detected and skipped.

.PARAMETER SiteUrl
    Full URL of the Executive Workspace SharePoint site.

.PARAMETER WhatIf
    Preview actions without making changes.

.EXAMPLE
    .\04-add-metadata-columns.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/exec-workspace"

.NOTES
    Requires: PnP.PowerShell module
    Required role: SharePoint Administrator or Site Owner
    Run after: 02-create-libraries.ps1
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

$Libraries = @("Draft", "Review", "Approved", "Archive")

# --- Column definitions (LLD Section 4) ---
# Each column is added as a list column on each library
$Columns = @(
    @{
        Type          = "Choice"
        InternalName  = "ExecWS_DocumentType"
        DisplayName   = "Document Type"
        Required      = $true
        Choices       = @("Board Pack","Research Summary","Decision Record","Meeting Minutes","Supporting Material")
        DefaultValue  = ""
    },
    @{
        Type          = "Choice"
        InternalName  = "ExecWS_LifecycleState"
        DisplayName   = "Lifecycle State"
        Required      = $true
        Choices       = @("Draft","Review","Approved","Archived")
        DefaultValue  = "Draft"
        # Note: This field is set by Power Automate flows — users should not manually change it.
        # ReadOnly enforcement is handled in the library's default view settings.
    },
    @{
        Type          = "Text"
        InternalName  = "ExecWS_MeetingDecisionId"
        DisplayName   = "Meeting / Decision ID"
        Required      = $false
        Description   = "Pack identifier linking this document to a meeting instance. Format: [MeetingType]-[YYYY-MM]-[NNN] e.g. BOARD-2026-03-001"
    },
    @{
        Type          = "Choice"
        InternalName  = "ExecWS_SensitivityClassification"
        DisplayName   = "Sensitivity Classification"
        Required      = $true
        Choices       = @("Confidential – Executive","Highly Confidential – Board")
        DefaultValue  = "Confidential – Executive"
    },
    @{
        Type          = "User"
        InternalName  = "ExecWS_DocumentOwner"
        DisplayName   = "Document Owner"
        Required      = $true
        SelectionMode = "PeopleOnly"   # Single named user — no groups
    },
    # --- Meeting cadence fields (LLD Section 10) ---
    @{
        Type          = "Choice"
        InternalName  = "ExecWS_MeetingType"
        DisplayName   = "Meeting Type"
        Required      = $false
        Choices       = @("Board","SteerCo","ExecTeam","Ad-Hoc")
        DefaultValue  = ""
        Description   = "Type of meeting this document belongs to. Drives filtered views in the Approved library."
    },
    @{
        Type          = "DateTime"
        InternalName  = "ExecWS_MeetingDate"
        DisplayName   = "Meeting Date"
        Required      = $false
        Description   = "Date of the associated meeting. Used for sorting and the Current Cycle view."
    },
    @{
        Type          = "Text"
        InternalName  = "ExecWS_MeetingCycle"
        DisplayName   = "Meeting Cycle"
        Required      = $false
        Description   = "Derived meeting cycle label. Format: BOARD-2026-03 or STEERCO-2026-W12. Used for grouping in the By Meeting view."
    },
    @{
        Type          = "Number"
        InternalName  = "ExecWS_PackVersion"
        DisplayName   = "Pack Version"
        Required      = $false
        Description   = "Integer revision number for the meeting pack. Starts at 1; increment when a pack is revised after initial distribution."
    }
)

Write-Host "`nConnecting to SharePoint site: $SiteUrl" -ForegroundColor Cyan
Connect-WorkspacePnP -Url $SiteUrl
Write-Host "Connected.`n" -ForegroundColor Green

foreach ($lib in $Libraries) {
    Write-Host "Processing library: $lib" -ForegroundColor Cyan

    foreach ($col in $Columns) {
        # Idempotency: check if column already exists
        $existing = Get-PnPField -List $lib -Identity $col.InternalName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "  [SKIP]  Column exists: $($col.DisplayName)" -ForegroundColor Yellow
            continue
        }

        if ($PSCmdlet.ShouldProcess("$lib → $($col.DisplayName)", "Add metadata column")) {
            try {
                switch ($col.Type) {
                    "Choice" {
                        $choiceXml = "<Field Type='Choice' Name='$($col.InternalName)' DisplayName='$($col.DisplayName)' Required='$(([string]$col.Required).ToUpper())'>" +
                                     "<Default>$($col.DefaultValue)</Default>" +
                                     "<CHOICES>" +
                                     ($col.Choices | ForEach-Object { "<CHOICE>$_</CHOICE>" }) +
                                     "</CHOICES></Field>"
                        Add-PnPFieldFromXml -List $lib -FieldXml $choiceXml | Out-Null
                    }
                    "Text" {
                        Add-PnPField -List $lib `
                                     -InternalName $col.InternalName `
                                     -DisplayName  $col.DisplayName `
                                     -Type         Text `
                                     -Required:($col.Required) | Out-Null
                    }
                    "User" {
                        $userXml = "<Field Type='User' Name='$($col.InternalName)' DisplayName='$($col.DisplayName)' Required='TRUE' UserSelectionMode='$($col.SelectionMode)' Mult='FALSE' />"
                        Add-PnPFieldFromXml -List $lib -FieldXml $userXml | Out-Null
                    }
                    "DateTime" {
                        Add-PnPField -List $lib `
                                     -InternalName $col.InternalName `
                                     -DisplayName  $col.DisplayName `
                                     -Type         DateTime `
                                     -Required:($false) | Out-Null
                    }
                    "Number" {
                        Add-PnPField -List $lib `
                                     -InternalName $col.InternalName `
                                     -DisplayName  $col.DisplayName `
                                     -Type         Number `
                                     -Required:($false) | Out-Null
                    }
                }
                Write-Host "  [OK]    Added: $($col.DisplayName)" -ForegroundColor Green
            }
            catch {
                Write-Host "  [FAIL]  $($col.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

Write-Host "`n[OK]    Metadata column provisioning complete across all libraries." -ForegroundColor Green
Write-Host "[NEXT]  Run 05-configure-settings.ps1 -SiteUrl '$SiteUrl' -TenantName '<tenant>'" -ForegroundColor White

Disconnect-PnPOnline

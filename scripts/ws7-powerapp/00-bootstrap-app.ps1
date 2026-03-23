<#
.SYNOPSIS
    Bootstraps the ExecWorkspace Canvas App for PAC CLI development workflow.

.DESCRIPTION
    Creates a minimal Canvas App shell in Power Apps Studio, downloads it via PAC CLI,
    unpacks it to extract the generated configuration files (DataSources/, Connections/,
    connector schemas, GUIDs), then merges our .fx.yaml source files into the unpacked
    structure. This produces a complete PAC CLI source tree that can be packed and deployed.

    This script only needs to run ONCE per environment to establish the initial scaffold.
    After bootstrap, iterate using: edit .fx.yaml → pac canvas pack → deploy.

.PARAMETER TenantUrl
    SharePoint tenant URL (e.g., https://contoso.sharepoint.com)

.PARAMETER SiteRelativeUrl
    Site-relative URL for the workspace (default: /sites/exec-workspace)

.PARAMETER EnvironmentId
    Power Platform environment ID (from admin.powerplatform.microsoft.com)

.PARAMETER AppDisplayName
    Display name for the Canvas App (default: ExecWorkspace)

.PARAMETER WhatIf
    Preview actions without executing.

.EXAMPLE
    .\00-bootstrap-app.ps1 -TenantUrl "https://contoso.sharepoint.com" -EnvironmentId "abc-123"

.NOTES
    Prerequisites:
    - PAC CLI installed (winget install Microsoft.PowerAppsCLI)
    - Authenticated to Power Platform (pac auth create --environment <id>)
    - Power Apps Maker role in the target environment
    - SharePoint site and libraries already provisioned (WS-1 through WS-4)

    Constitutional alignment:
    - M365-native: Uses only PAC CLI and Power Apps APIs
    - Least privilege: Requires Maker role only (not Admin)
    - Auditability: All actions logged in Power Platform audit log
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://[\w-]+\.sharepoint\.com$')]
    [string]$TenantUrl,

    [string]$SiteRelativeUrl = "/sites/exec-workspace",

    [Parameter(Mandatory)]
    [string]$EnvironmentId,

    [string]$AppDisplayName = "ExecWorkspace"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = $PSScriptRoot
$SrcDir     = Join-Path $ScriptRoot "src"
$BuildDir   = Join-Path $ScriptRoot "build"
$MsappFile  = Join-Path $BuildDir "$AppDisplayName.msapp"
$UnpackDir  = Join-Path $BuildDir "unpacked"
$MergedDir  = Join-Path $BuildDir "merged"
$SiteUrl    = "$TenantUrl$SiteRelativeUrl"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "`n╔══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "║ STEP $Step │ $Message" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Assert-PacCli {
    try {
        $version = pac --version 2>&1
        Write-Host "  PAC CLI version: $version" -ForegroundColor Green
    }
    catch {
        Write-Error @"
PAC CLI not found. Install with:
  winget install Microsoft.PowerAppsCLI
Then authenticate:
  pac auth create --environment $EnvironmentId
"@
    }
}

function Assert-PacAuth {
    $authList = pac auth list 2>&1
    if ($authList -match "No profiles") {
        Write-Error @"
No PAC CLI auth profile found. Create one:
  pac auth create --environment $EnvironmentId
"@
    }
    Write-Host "  PAC CLI authentication verified." -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 0: Prerequisites
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "0" "Verifying prerequisites"
Assert-PacCli
Assert-PacAuth

if (-not (Test-Path $SrcDir)) {
    Write-Error "Source directory not found at $SrcDir — run from the ws7-powerapp/ directory."
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Create build directory
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1" "Preparing build directory"
if ($PSCmdlet.ShouldProcess($BuildDir, "Create build directory")) {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    New-Item -ItemType Directory -Path $UnpackDir -Force | Out-Null
    New-Item -ItemType Directory -Path $MergedDir -Force | Out-Null
    Write-Host "  Build directory: $BuildDir" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Create minimal Canvas App in Studio (manual step)
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2" "Canvas App shell creation"
Write-Host @"

  ┌────────────────────────────────────────────────────────────────┐
  │  MANUAL STEP REQUIRED                                         │
  │                                                                │
  │  Create a minimal Canvas App in Power Apps Studio:             │
  │                                                                │
  │  1. Go to https://make.powerapps.com                           │
  │  2. Select environment: $EnvironmentId
  │  3. Create → Canvas app → Tablet layout                        │
  │  4. Name it: $AppDisplayName
  │  5. Add connectors:                                            │
  │     • SharePoint (connect to $SiteUrl)                         │
  │       - Add all 4 libraries: Draft, Review, Approved, Archive  │
  │     • Office 365 Users                                         │
  │     • Approvals                                                │
  │     • Power Automate Management                                │
  │  6. Save the app                                               │
  │  7. Note the app name exactly as saved                         │
  │                                                                │
  │  After saving, press ENTER to continue...                      │
  └────────────────────────────────────────────────────────────────┘

"@ -ForegroundColor Yellow

if (-not $WhatIfPreference) {
    Read-Host "Press ENTER after creating the Canvas App shell in Studio"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Download the .msapp file
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "3" "Downloading Canvas App as .msapp"
if ($PSCmdlet.ShouldProcess($AppDisplayName, "Download Canvas App")) {
    Write-Host "  Downloading '$AppDisplayName' from environment..." -ForegroundColor White
    pac canvas download --name $AppDisplayName --file-name $MsappFile
    if (-not (Test-Path $MsappFile)) {
        Write-Error "Download failed — .msapp file not found at $MsappFile"
    }
    Write-Host "  Downloaded: $MsappFile" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: Unpack .msapp to get generated configs
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "4" "Unpacking .msapp to extract connector configs"
if ($PSCmdlet.ShouldProcess($MsappFile, "Unpack Canvas App")) {
    pac canvas unpack --msapp $MsappFile --sources $UnpackDir
    Write-Host "  Unpacked to: $UnpackDir" -ForegroundColor Green

    # List the generated structure
    Write-Host "`n  Generated structure:" -ForegroundColor White
    Get-ChildItem $UnpackDir -Recurse -Depth 2 | ForEach-Object {
        $indent = "    " + ("  " * ($_.FullName.Split([IO.Path]::DirectorySeparatorChar).Count - $UnpackDir.Split([IO.Path]::DirectorySeparatorChar).Count))
        Write-Host "$indent$($_.Name)" -ForegroundColor DarkGray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: Merge — Studio configs + our .fx.yaml screens
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "5" "Merging Studio configs with .fx.yaml source files"
if ($PSCmdlet.ShouldProcess($MergedDir, "Merge source files")) {
    # Copy ALL files from unpacked (Studio-generated configs)
    Copy-Item -Path "$UnpackDir\*" -Destination $MergedDir -Recurse -Force
    Write-Host "  Copied Studio configs (DataSources, Connections, manifest, entropy)" -ForegroundColor Green

    # Overwrite screen files with our .fx.yaml sources (into Src/ subdirectory)
    $fxFiles = Get-ChildItem -Path $SrcDir -Filter "*.fx.yaml" -File
    $mergedSrcDir = Join-Path $MergedDir "Src"
    foreach ($fxFile in $fxFiles) {
        $destPath = Join-Path $mergedSrcDir $fxFile.Name
        Copy-Item -Path $fxFile.FullName -Destination $destPath -Force
        Write-Host "  Merged: $($fxFile.Name)" -ForegroundColor Green
    }

    # Remove the Studio-generated Screen1 (replaced by our screens)
    $screen1Path = Join-Path $mergedSrcDir "Screen1.fx.yaml"
    if (Test-Path $screen1Path) {
        Remove-Item $screen1Path -Force
        Write-Host "  Removed: Screen1.fx.yaml (replaced by custom screens)" -ForegroundColor Yellow
    }

    # Copy CanvasManifest.json (our version with screen order)
    $manifestSrc = Join-Path $SrcDir "CanvasManifest.json"
    if (Test-Path $manifestSrc) {
        # Read our manifest and merge screen order into the Studio manifest
        $studioManifest = Join-Path $MergedDir "CanvasManifest.json"
        if (Test-Path $studioManifest) {
            $studio = Get-Content $studioManifest -Raw | ConvertFrom-Json
            $ours = Get-Content $manifestSrc -Raw | ConvertFrom-Json

            # Preserve Studio-generated IDs, merge our screen order
            $studio.ScreenOrder = $ours.ScreenOrder
            if ($ours.Properties.PSObject.Properties['AppDescription']) {
                $studio.Properties.AppDescription = $ours.Properties.AppDescription
            }
            if ($ours.Properties.PSObject.Properties['Description'] -and
                $studio.Properties.PSObject.Properties['AppDescription']) {
                $studio.Properties.AppDescription = $ours.Properties.Description
            }
            $studio | ConvertTo-Json -Depth 10 | Set-Content $studioManifest -Encoding UTF8
            Write-Host "  Merged CanvasManifest.json (preserved Studio IDs, updated screen order)" -ForegroundColor Green
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6: Replace tenant placeholder
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "6" "Replacing tenant placeholder in source files"
if ($PSCmdlet.ShouldProcess($MergedDir, "Replace tenant placeholder")) {
    $tenant = ($TenantUrl -replace 'https://', '' -replace '\.sharepoint\.com', '')
    Get-ChildItem $MergedDir -Recurse -File | ForEach-Object {
        $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -match '\{tenant\}') {
            $content = $content -replace '\{tenant\}', $tenant
            Set-Content -Path $_.FullName -Value $content -Encoding UTF8
            Write-Host "  Updated: $($_.Name)" -ForegroundColor Green
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7: Pack into .msapp
# ─────────────────────────────────────────────────────────────────────────────
Write-Step "7" "Packing merged source into .msapp"
$FinalMsapp = Join-Path $BuildDir "$AppDisplayName-v1.0.0.msapp"
if ($PSCmdlet.ShouldProcess($FinalMsapp, "Pack Canvas App")) {
    pac canvas pack --sources $MergedDir --msapp $FinalMsapp
    if (Test-Path $FinalMsapp) {
        Write-Host "  Packed: $FinalMsapp" -ForegroundColor Green
        $size = (Get-Item $FinalMsapp).Length / 1KB
        Write-Host "  Size: $([math]::Round($size, 1)) KB" -ForegroundColor Green
    }
    else {
        Write-Error "Pack failed — .msapp file not created."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n" -NoNewline
Write-Host "╔══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "║  BOOTSTRAP COMPLETE                                         " -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "║                                                              " -ForegroundColor Green
Write-Host "║  Source tree:  $MergedDir" -ForegroundColor Green
Write-Host "║  Packed .msapp: $FinalMsapp" -ForegroundColor Green
Write-Host "║                                                              " -ForegroundColor Green
Write-Host "║  Next steps:                                                 " -ForegroundColor Green
Write-Host "║  1. Upload .msapp to Studio to verify (File → Open)          " -ForegroundColor Green
Write-Host "║  2. Add Copilot Studio chatbot control manually              " -ForegroundColor Green
Write-Host "║  3. Save & publish in Studio                                 " -ForegroundColor Green
Write-Host "║  4. Or deploy via: .\01-deploy-canvas-app.ps1               " -ForegroundColor Green
Write-Host "║                                                              " -ForegroundColor Green
Write-Host "║  Iterative workflow:                                         " -ForegroundColor Green
Write-Host "║  Edit .fx.yaml → pac canvas pack → upload/deploy             " -ForegroundColor Green
Write-Host "║                                                              " -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════" -ForegroundColor Green

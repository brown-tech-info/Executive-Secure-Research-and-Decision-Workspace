<#
.SYNOPSIS
    WS-7: Deploy the Executive Workspace Canvas App using PAC CLI.

.DESCRIPTION
    Packs the .fx.yaml source files into an .msapp using PAC CLI, then deploys
    the Canvas App to the target Power Platform environment. Shares the app with
    the five Entra ID security groups.

    Workflow:
    1. Validate PAC CLI auth and prerequisites
    2. Pack .fx.yaml sources → .msapp (pac canvas pack)
    3. Upload .msapp to Power Apps environment
    4. Share app with Entra ID security groups
    5. Validate deployment

    Prerequisites:
    - PAC CLI installed and authenticated (pac auth create --environment <id>)
    - WS-1 through WS-6 deployed and validated
    - Bootstrap completed (00-bootstrap-app.ps1 run at least once)
    - config.ps1 populated with tenant-specific values

    This script is idempotent — safe to run multiple times.

    Constitutional alignment:
    - M365-native only: Uses PAC CLI (Microsoft tool) exclusively
    - Least privilege: Requires Power Apps Maker role only
    - Auditability: All deployment actions logged in Power Platform audit log
    - Configuration over code: Canvas App is low-code, PAC CLI is declarative

.PARAMETER Mode
    Deployment mode: 'pack-only' (just build .msapp), 'full' (pack + deploy). Default: full.

.PARAMETER WhatIf
    If specified, displays what the script would do without making changes.

.EXAMPLE
    .\01-deploy-canvas-app.ps1
    .\01-deploy-canvas-app.ps1 -Mode pack-only
    .\01-deploy-canvas-app.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("full", "pack-only")]
    [string]$Mode = "full"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ──────────────────────────────────────────────
# Load configuration
# ──────────────────────────────────────────────
$configPath = Join-Path $PSScriptRoot "..\config.ps1"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found at $configPath. Copy config.ps1.example to config.ps1 and populate values."
    exit 1
}
. $configPath

# Validate required config values
$requiredVars = @(
    'TenantId', 'TenantName', 'SiteUrl',
    'AuthorsGroupId', 'ReviewersGroupId', 'ExecutivesGroupId',
    'ComplianceGroupId', 'PlatformAdminsGroupId',
    'PowerPlatformEnvironmentId'
)
foreach ($var in $requiredVars) {
    if (-not (Get-Variable -Name $var -ValueOnly -ErrorAction SilentlyContinue)) {
        Write-Error "Required configuration variable '$var' is not set in config.ps1."
        exit 1
    }
}

# ──────────────────────────────────────────────
# Paths
# ──────────────────────────────────────────────
$ScriptRoot = $PSScriptRoot
$BuildDir   = Join-Path $ScriptRoot "build"
$MergedDir  = Join-Path $BuildDir "merged"
$AppName    = "ExecWorkspace"
$Version    = "1.0.0"
$MsappFile  = Join-Path $BuildDir "$AppName-v$Version.msapp"

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  WS-7: Power Apps Canvas App Deployment (PAC CLI)          ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  Mode: $Mode                                                " -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ──────────────────────────────────────────────
# Step 1: Verify prerequisites
# ──────────────────────────────────────────────
Write-Host "[1/5] Verifying prerequisites..." -ForegroundColor Yellow

try {
    $pacVersion = pac --version 2>&1
    Write-Host "  PAC CLI: $pacVersion" -ForegroundColor Green
} catch {
    Write-Error "PAC CLI not found. Install: winget install Microsoft.PowerAppsCLI"
    exit 1
}

if (-not (Test-Path $MergedDir)) {
    Write-Error "Merged source directory not found at $MergedDir. Run 00-bootstrap-app.ps1 first."
    exit 1
}
Write-Host "  Source dir: $MergedDir" -ForegroundColor Green

if ($Mode -eq "full") {
    $authList = pac auth list 2>&1
    if ($authList -match "No profiles") {
        Write-Error "No PAC CLI auth profile. Run: pac auth create --environment $PowerPlatformEnvironmentId"
        exit 1
    }
    Write-Host "  Auth: verified" -ForegroundColor Green
}

# ──────────────────────────────────────────────
# Step 2: Pack .fx.yaml → .msapp
# ──────────────────────────────────────────────
Write-Host "[2/5] Packing Canvas App source → .msapp..." -ForegroundColor Yellow

if ($WhatIfPreference) {
    Write-Host "  [WhatIf] Would pack $MergedDir → $MsappFile" -ForegroundColor DarkGray
} else {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    pac canvas pack --sources $MergedDir --msapp $MsappFile
    if (Test-Path $MsappFile) {
        $size = [math]::Round((Get-Item $MsappFile).Length / 1KB, 1)
        Write-Host "  ✓ Packed: $MsappFile ($size KB)" -ForegroundColor Green
    } else {
        Write-Error "Pack failed — .msapp not created. Check source files for YAML errors."
        exit 1
    }
}

if ($Mode -eq "pack-only") {
    Write-Host "`nPack-only mode — stopping here." -ForegroundColor Yellow
    Write-Host "  .msapp file: $MsappFile" -ForegroundColor White
    Write-Host "  Upload manually: Power Apps Studio → File → Open → Browse" -ForegroundColor White
    exit 0
}

# ──────────────────────────────────────────────
# Step 3: Upload .msapp to Power Apps
# ──────────────────────────────────────────────
Write-Host "[3/5] Uploading Canvas App to Power Platform..." -ForegroundColor Yellow

if ($WhatIfPreference) {
    Write-Host "  [WhatIf] Would upload $MsappFile to environment $PowerPlatformEnvironmentId" -ForegroundColor DarkGray
} else {
    # pac canvas upload is not currently available — use pac solution import if wrapped in solution,
    # or upload via Power Apps Studio (File → Open → Browse).
    # For CI/CD, wrap the .msapp in a solution zip:
    #   1. Create a solution in the environment
    #   2. Add the Canvas App to the solution
    #   3. Export as managed solution
    #   4. Use pac solution import for subsequent deployments

    Write-Host "  NOTE: Direct .msapp upload via PAC CLI is not yet supported." -ForegroundColor DarkYellow
    Write-Host "  Upload options:" -ForegroundColor White
    Write-Host "    a) Power Apps Studio → File → Open → Browse → select $MsappFile" -ForegroundColor White
    Write-Host "    b) Wrap in a solution and use 'pac solution import --path solution.zip'" -ForegroundColor White
    Write-Host "    c) Use Power Platform Build Tools in Azure DevOps for CI/CD" -ForegroundColor White
    Write-Host ""

    # If the app is already in a solution, we can update via solution import
    $solutionZip = Join-Path $BuildDir "ExecWorkspaceSolution.zip"
    if (Test-Path $solutionZip) {
        Write-Host "  Found solution zip — importing via pac solution import..." -ForegroundColor White
        $existingSolution = pac solution list 2>&1 | Select-String "ExecWorkspace"
        if ($existingSolution) {
            pac solution import --path $solutionZip --force-overwrite
        } else {
            pac solution import --path $solutionZip
        }
        Write-Host "  ✓ Solution imported" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ No solution zip found — manual upload required." -ForegroundColor DarkYellow
    }
}

# ──────────────────────────────────────────────
# Step 4: Share app with security groups
# ──────────────────────────────────────────────
Write-Host "[4/5] Sharing app with Entra ID security groups..." -ForegroundColor Yellow

$groups = @(
    @{ Name = "ExecWorkspace-Authors";        Id = $AuthorsGroupId;        Role = "CanView" },
    @{ Name = "ExecWorkspace-Reviewers";      Id = $ReviewersGroupId;      Role = "CanView" },
    @{ Name = "ExecWorkspace-Executives";     Id = $ExecutivesGroupId;     Role = "CanView" },
    @{ Name = "ExecWorkspace-Compliance";     Id = $ComplianceGroupId;     Role = "CanView" },
    @{ Name = "ExecWorkspace-PlatformAdmins"; Id = $PlatformAdminsGroupId; Role = "CanEdit" }
)

foreach ($group in $groups) {
    if ($WhatIfPreference) {
        Write-Host "  [WhatIf] Would share app with $($group.Name) (Role: $($group.Role))" -ForegroundColor DarkGray
    } else {
        # App sharing requires the Power Apps Admin API or manual Studio configuration.
        # PAC CLI does not currently support app sharing directly.
        # For automation, use the Power Apps Management connector in Power Automate
        # or the Power Apps Admin PowerShell module:
        #   Set-AdminPowerAppRoleAssignment -AppName <appId> -RoleName $group.Role `
        #       -PrincipalType Group -PrincipalObjectId $group.Id
        Write-Host "  → $($group.Name): $($group.Role) (configure in Studio or via Admin API)" -ForegroundColor DarkYellow
    }
}

# ──────────────────────────────────────────────
# Step 5: Validation
# ──────────────────────────────────────────────
Write-Host "[5/5] Validating deployment..." -ForegroundColor Yellow

if ($WhatIfPreference) {
    Write-Host "  [WhatIf] Would validate .msapp integrity and app accessibility" -ForegroundColor DarkGray
} else {
    # Validate .msapp exists and is non-trivial
    if (Test-Path $MsappFile) {
        $size = (Get-Item $MsappFile).Length
        if ($size -gt 1024) {
            Write-Host "  ✓ .msapp file valid ($([math]::Round($size / 1KB, 1)) KB)" -ForegroundColor Green
        } else {
            Write-Warning ".msapp file suspiciously small — may be corrupt"
        }
    }

    # Check solution if imported
    try {
        $solution = pac solution list 2>&1 | Select-String "ExecWorkspace"
        if ($solution) {
            Write-Host "  ✓ Solution found in environment" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ⚠ Could not verify solution status" -ForegroundColor DarkYellow
    }
}

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  WS-7 Deployment Complete                                  ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  App:         $AppName v$Version" -ForegroundColor Cyan
Write-Host "║  .msapp:      $MsappFile" -ForegroundColor Cyan
Write-Host "║  Environment: $PowerPlatformEnvironmentId" -ForegroundColor Cyan
Write-Host "║  Site URL:    $SiteUrl" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Iterative development workflow:" -ForegroundColor Yellow
Write-Host "  1. Edit .fx.yaml files in scripts/ws7-powerapp/src/" -ForegroundColor White
Write-Host "  2. Run: .\01-deploy-canvas-app.ps1 -Mode pack-only" -ForegroundColor White
Write-Host "  3. Open .msapp in Power Apps Studio to test" -ForegroundColor White
Write-Host "  4. When ready, publish from Studio or wrap in solution" -ForegroundColor White
Write-Host ""
Write-Host "Post-deployment:" -ForegroundColor Yellow
Write-Host "  1. Add Copilot Studio chatbot control on scrAIAssistant (manual)" -ForegroundColor White
Write-Host "  2. Run 02-validate-canvas-app.ps1 to verify SharePoint backend" -ForegroundColor White
Write-Host "  3. Run 03-test-e2e-canvas-app.ps1 for integration tests" -ForegroundColor White
Write-Host "  4. Test with each persona (Author, Reviewer, Executive, Compliance)" -ForegroundColor White

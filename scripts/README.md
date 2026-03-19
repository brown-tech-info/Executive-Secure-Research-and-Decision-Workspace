# Scripts – Executive Secure Research & Decision Workspace

## Overview

This folder contains the complete code-driven deployment suite for the Executive Secure Research & Decision Workspace. Every workstream is fully automated — there are no manual portal steps.

All scripts are:
- **Idempotent** — safe to re-run; existing resources are detected and skipped
- **`-WhatIf` capable** — pass `-WhatIf` to preview changes without making them
- **Sequenced** — each workstream depends on the previous validation checkpoint passing
- **Self-documenting** — inline comments explain the governance rationale for each action

---

## Prerequisites

### PowerShell Version

**PowerShell 7.0 or later is required.** Some scripts use null-conditional operators (`?.`) and other PS7+ syntax.

```powershell
# Check your version
$PSVersionTable.PSVersion

# Install PowerShell 7 if needed: https://aka.ms/powershell
```

### Required Modules

```powershell
# Install all required modules (run once, then they're available for all scripts)

# Microsoft Graph — Entra ID groups, Conditional Access, PIM, access reviews, Graph API calls
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# PnP PowerShell — SharePoint site, libraries, permissions, metadata, settings
Install-Module PnP.PowerShell -Scope CurrentUser -Force

# Exchange Online Management — Sensitivity labels, DLP policies, Purview, eDiscovery
# Version 3.0.0 or later required
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force

# Az.Accounts — Authentication tokens for Power Platform REST API (flows + Copilot agent)
Install-Module Az.Accounts -Scope CurrentUser -Force
```

### Required Roles

| Workstream | Script | Minimum Role |
|---|---|---|
| WS-1 | 01-create-security-groups | Groups Administrator |
| WS-1 | 03-create-conditional-access | Conditional Access Administrator |
| WS-1 | 04-configure-pim | Privileged Role Administrator |
| WS-2 | All SharePoint scripts | SharePoint Administrator |
| WS-3 | 01-create-sensitivity-labels | Compliance Administrator |
| WS-3 | 04-create-dlp-policies | Compliance Administrator |
| WS-4 | 01-configure-audit | Exchange Administrator |
| WS-4 | 02-configure-retention | Compliance Administrator |
| WS-4 | 04-configure-ediscovery | eDiscovery Manager + Compliance Administrator |
| WS-5 | 01-deploy-flows | Power Platform Administrator |
| WS-6 | 02-deploy-copilot-agent | Power Platform Administrator |

### Licensing Requirements

- Microsoft 365 E5 (or E3 + add-ons) in the dev tenant
- Required features: Purview P2 (retention, eDiscovery), Entra ID P2 (PIM, access reviews), Sensitivity labels, Copilot Studio

---

## Authentication Setup (Required Before Running Any Script)

All scripts authenticate silently using a **self-signed certificate** registered with an Entra ID app registration. No browser popups or device codes are required during deployment.

> **Why cert auth?** PnP.PowerShell 3.x deprecated the PnP Management Shell multi-tenant app (September 2024). Interactive/device code flows require a browser, which creates friction when running sequential deployment scripts and conflicts with running as a service account. Certificate-based AppOnly auth solves both problems.

### Step 1 — Set up `config.ps1`

Copy the template and fill in your tenant values:

```powershell
Copy-Item scripts\config.ps1.example scripts\config.ps1
# Now edit scripts\config.ps1 and replace all <PLACEHOLDER> values
```

`config.ps1` is gitignored — your values stay local.

### Step 2 — Register the Entra ID app

Run once per tenant. This creates an app registration with the required SharePoint and Graph delegated permissions:

```powershell
Register-PnPEntraIDAppForInteractiveLogin `
    -ApplicationName "ExecWorkspace-PnP-Admin" `
    -Tenant         "<your-tenant>.onmicrosoft.com" `
    -SharePointDelegatePermissions "AllSites.FullControl","TermStore.ReadWrite.All","User.ReadWrite.All" `
    -GraphDelegatePermissions "Group.ReadWrite.All","Directory.ReadWrite.All","User.ReadWrite.All" `
    -DeviceLogin
# Sign in as your tenant Global Admin when prompted
# Copy the returned App/Client ID to config.ps1 → $ClientId
```

Then grant admin consent via the Entra portal or this URL (sign in as Global Admin):
```
https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=<client-id>&redirect_uri=https://pnp.github.io/powershell/consent.html
```

Then grant the required **Application permissions** to the app (for AppOnly/cert auth). In Entra portal → App registrations → ExecWorkspace-PnP-Admin → API permissions, add:

| API | Permission | Type |
|---|---|---|
| Microsoft Graph | `Group.ReadWrite.All` | Application |
| Microsoft Graph | `Policy.ReadWrite.ConditionalAccess` | Application |
| Microsoft Graph | `Policy.Read.All` | Application |
| Microsoft Graph | `Application.Read.All` | Application |
| Microsoft Graph | `Directory.Read.All` | Application |
| Microsoft Graph | `RoleManagement.ReadWrite.Directory` | Application |
| Microsoft Graph | `AccessReview.ReadWrite.All` | Application |
| Microsoft Graph | `Sites.ReadWrite.All` | Application |
| Microsoft Graph | `InformationProtectionPolicy.Read.All` | Application |
| Microsoft Graph | `eDiscovery.ReadWrite.All` | Application |
| SharePoint | `Sites.FullControl.All` | Application |
| Exchange | `Exchange.ManageAsApp` | Application |

> **Note:** `Sites.ReadWrite.All` (Graph) is required for WS-3 scripts 02/03 to set default sensitivity labels on SharePoint libraries via `Invoke-PnPGraphMethod`. `Exchange.ManageAsApp` is required for IPPS/EXO cert auth. `InformationProtectionPolicy.Read.All` is required for sensitivity label operations. `eDiscovery.ReadWrite.All` is required for WS-4 eDiscovery configuration.

Grant admin consent for all permissions.

### Step 3 — Generate and register the deployment certificate

```powershell
# Generate a self-signed cert (valid 2 years) and install in local cert store
$cert = New-SelfSignedCertificate `
    -Subject "CN=ExecWorkspace-Deploy-Cert" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable -KeySpec Signature `
    -KeyLength 2048 -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(2)

Write-Host "Thumbprint: $($cert.Thumbprint)"  # Copy to config.ps1 → $CertThumbprint

# Export public key (to upload to Entra)
Export-Certificate -Cert $cert -FilePath "scripts\deploy-cert.cer" -Type CERT

# Export private key PFX (stays local — gitignored)
Export-PfxCertificate -Cert $cert -FilePath "scripts\deploy-cert.pfx" `
    -Password (ConvertTo-SecureString "YourPassword" -AsPlainText -Force)
```

Upload the cert to the app registration via the Entra portal (App registrations → ExecWorkspace-PnP-Admin → Certificates & secrets → Upload certificate) or via Graph PowerShell:

```powershell
Connect-MgGraph -TenantId "<tenant-id>" -Scopes "Application.ReadWrite.All" -UseDeviceAuthentication
$app      = Get-MgApplication -Filter "appId eq '<client-id>'"
$certBytes = [System.IO.File]::ReadAllBytes("scripts\deploy-cert.cer")
$cert2    = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("scripts\deploy-cert.cer")
$keyCred  = @{
    type          = "AsymmetricX509Cert"; usage = "Verify"
    key           = $cert2.RawData; displayName = "ExecWorkspace-Deploy-Cert"
    startDateTime = $cert2.NotBefore.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    endDateTime   = $cert2.NotAfter.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    customKeyIdentifier = [byte[]]::new(20)  # replace with SHA1 thumbprint bytes
}
Update-MgApplication -ApplicationId $app.Id -KeyCredentials @($keyCred)
```

### Step 4 — Verify silent auth works

```powershell
. .\scripts\config.ps1
Connect-WorkspacePnP -Url $SiteUrl
Write-Host (Get-PnPWeb).Title   # Should print site title with no browser prompt
Disconnect-PnPOnline

Connect-WorkspaceGraph
Write-Host (Get-MgContext).AppName   # Should print "ExecWorkspace-PnP-Admin"
Disconnect-MgGraph
```

---

## Deployment Order

**Critical:** Run workstreams in sequence. Do not proceed past a validation checkpoint that has failures.

```
WS-1 → WS-2 → WS-3 → WS-4 → WS-5 → WS-6
```

### WS-1: Entra ID & Identity Foundation

Run first — all other workstreams depend on these groups existing.

```powershell
# 1. Create the five ExecWorkspace security groups
.\ws1-entra\01-create-security-groups.ps1 -TenantId "<tenant-id>"

# 2. Validate groups exist before proceeding
.\ws1-entra\02-validate-entra-groups.ps1 -TenantId "<tenant-id>"
# Must exit 0 before continuing

# 3. Deploy Conditional Access policies (report-only mode initially)
.\ws1-entra\03-create-conditional-access.ps1 -TenantId "<tenant-id>"
# Add -Enforce after validating sign-in logs show no false blocks

# 4. Configure PIM for elevated roles
.\ws1-entra\04-configure-pim.ps1 `
    -TenantId "<tenant-id>" `
    -PlatformAdminApproverId "<approver-object-id>" `
    -AccessReviewNotificationEmail "itadmin@<tenant>.onmicrosoft.com"
```

### WS-2: SharePoint Provisioning

```powershell
# 1. Create the Communication Site
.\ws2-sharepoint\01-provision-site.ps1 -TenantName "<tenant>" -SiteOwner "admin@<tenant>.onmicrosoft.com"

# 2. Create Draft, Review, Approved, Archive libraries (inheritance broken on each)
.\ws2-sharepoint\02-create-libraries.ps1 -SiteUrl "https://<tenant>.sharepoint.com/sites/exec-workspace"

# 3. Apply Entra ID group permissions per library
.\ws2-sharepoint\03-configure-permissions.ps1 `
    -SiteUrl "https://<tenant>.sharepoint.com/sites/exec-workspace" `
    -TenantId "<tenant-id>"

# 4. Add mandatory metadata columns to all libraries
.\ws2-sharepoint\04-add-metadata-columns.ps1 -SiteUrl "https://<tenant>.sharepoint.com/sites/exec-workspace"

# 5. Configure site and library settings
.\ws2-sharepoint\05-configure-settings.ps1 `
    -SiteUrl "https://<tenant>.sharepoint.com/sites/exec-workspace" `
    -TenantName "<tenant>"

# 6. Validate (must exit 0 before WS-3)
.\ws2-sharepoint\06-validate-spo.ps1 `
    -SiteUrl "https://<tenant>.sharepoint.com/sites/exec-workspace" `
    -TenantId "<tenant-id>"
```

### WS-3: Information Protection

```powershell
# 0. Verify AIP integration is enabled (prerequisite — must run before step 1)
.\ws3-mip\00-enable-aip-integration.ps1

# 1. Create sensitivity labels (allow 24h propagation after this step)
.\ws3-mip\01-create-sensitivity-labels.ps1

# --- Wait 24 hours for label propagation before continuing ---

# 2. Apply default sensitivity labels to each library
.\ws3-mip\02-apply-sensitivity-labels.ps1 `
    -SiteUrl "https://<tenant>.sharepoint.com/sites/exec-workspace"

# 3. Validate labels applied (must exit 0 before WS-4)
.\ws3-mip\03-validate-mip.ps1 `
    -SiteUrl "https://<tenant>.sharepoint.com/sites/exec-workspace"

# 4. Create DLP policies (TestWithNotifications mode initially)
.\ws3-mip\04-create-dlp-policies.ps1 `
    -SiteUrl "https://<tenant>.sharepoint.com/sites/exec-workspace" `
    -ComplianceNotificationEmail "compliance@<tenant>.onmicrosoft.com"
# Add -Enforce after validating Activity Explorer shows no false positives
```

### WS-4: Purview Audit & Retention

```powershell
# 1. Verify/enable Unified Audit Log
.\ws4-purview\01-configure-audit.ps1 -TenantAdminEmail "admin@<tenant>.onmicrosoft.com"

# 2. Create retention labels (placeholder durations — update before production)
.\ws4-purview\02-configure-retention.ps1 `
    -TenantAdminEmail    "admin@<tenant>.onmicrosoft.com" `
    -ArchiveRetentionYears  7 `
    -ApprovedRetentionYears 3

# 3. Validate Purview configuration (must exit 0 before WS-6)
.\ws4-purview\03-validate-purview.ps1 `
    -TenantAdminEmail "admin@<tenant>.onmicrosoft.com" `
    -SiteUrl          "https://<tenant>.sharepoint.com/sites/exec-workspace"

# 4. Create eDiscovery case and legal hold (hold created disabled by default)
.\ws4-purview\04-configure-ediscovery.ps1 `
    -TenantAdminEmail "admin@<tenant>.onmicrosoft.com" `
    -SiteUrl          "https://<tenant>.sharepoint.com/sites/exec-workspace" `
    -TenantId         "<tenant-id>"
```

### WS-5: Power Automate Lifecycle Flows

```powershell
# Deploy and fully activate all three lifecycle flows in one step.
# Flows are live and running when the script exits — no portal interaction required.
.\ws5-flows\01-deploy-flows.ps1 `
    -TenantId             "<tenant-id>" `
    -SiteUrl              "https://<tenant>.sharepoint.com/sites/exec-workspace" `
    -ReviewerGroupEmail   "execws-reviewers@<tenant>.onmicrosoft.com" `
    -ExecutivesGroupEmail "execws-executives@<tenant>.onmicrosoft.com" `
    -ComplianceGroupEmail "execws-compliance@<tenant>.onmicrosoft.com" `
    -ApproverUpns         "approver@<tenant>.onmicrosoft.com"

# Optional: re-enable flows if they were turned off without a full redeploy.
.\ws5-flows\02-enable-flows.ps1 -TenantId "<tenant-id>"
```

**Flow definitions** (parameterised JSON, do not edit directly):
- `flow-definitions/ExecWS-DraftToReview.json` — polling trigger on Draft library, fires when LifecycleState = Review
- `flow-definitions/ExecWS-ReviewToApproved.json` — polling trigger on Review library, runs approval workflow
- `flow-definitions/ExecWS-ApprovedToArchive.json` — manual button trigger, moves document to Archive

**Deployment architecture** — `01-deploy-flows.ps1` runs four steps per flow:
1. **CREATE** — POST to Power Automate REST API with connection references bound inline
2. **VERIFY** — read Dataverse `workflow.clientdata` to confirm CR bindings were written automatically
3. **PUBLISH** — `PublishXml` in Dataverse to commit the flow as a solution component
4. **ACTIVATE** — call Flow REST API `/start` to put the flow into running state

### WS-6: Copilot Studio Agent

```powershell
# 1. Pre-flight checks (validates SharePoint permissions before deploying agent)
.\ws6-copilot\01-validate-copilot.ps1 `
    -SiteUrl  "https://<tenant>.sharepoint.com/sites/exec-workspace" `
    -TenantId "<tenant-id>"

# 2. Deploy the agent (creates agent, adds knowledge source, publishes)
.\ws6-copilot\02-deploy-copilot-agent.ps1 `
    -TenantId "<tenant-id>" `
    -SiteUrl  "https://<tenant>.sharepoint.com/sites/exec-workspace"
```

**Agent definition:** `agent-definition/ExecWorkspace-Copilot.yaml` — the agent specification including system instructions, knowledge scope, authentication settings, and topic configuration.

---

## Folder Structure

```
scripts/
│
├── README.md                              This file
├── config.ps1.example                     Template — copy to config.ps1 and fill in values
├── config.ps1                             Your local tenant config (gitignored — never commit)
│
├── ws1-entra/
│   ├── 01-create-security-groups.ps1      Creates 5 Entra ID security groups (Graph)
│   ├── 02-validate-entra-groups.ps1       Validates all groups exist (Graph)
│   ├── 03-create-conditional-access.ps1   Creates 2 CA policies (Graph)
│   └── 04-configure-pim.ps1               PIM policy + access reviews (Graph)
│
├── ws2-sharepoint/
│   ├── 01-provision-site.ps1              Creates Communication Site (PnP)
│   ├── 02-create-libraries.ps1            Creates 4 libraries, breaks inheritance (PnP)
│   ├── 03-configure-permissions.ps1       Applies group permissions per library (PnP + Graph)
│   ├── 04-add-metadata-columns.ps1        Adds 5 mandatory metadata columns (PnP)
│   ├── 05-configure-settings.ps1          Site + library governance settings (PnP)
│   └── 06-validate-spo.ps1                Full SharePoint validation checkpoint (PnP + Graph)
│
├── ws3-mip/
│   ├── 01-create-sensitivity-labels.ps1   Creates 2 sensitivity labels + policy (IPPS)
│   ├── 02-apply-sensitivity-labels.ps1    Sets default labels on each library (IPPS + Graph)
│   ├── 03-validate-mip.ps1                Validates labels and policies (IPPS + Graph)
│   └── 04-create-dlp-policies.ps1         Creates 2 DLP policies with 4 rules (IPPS)
│
├── ws4-purview/
│   ├── 01-configure-audit.ps1             Enables Unified Audit Log (EXO)
│   ├── 02-configure-retention.ps1         Creates retention labels + auto-apply (IPPS)
│   ├── 03-validate-purview.ps1            Validates Purview configuration (IPPS + EXO)
│   └── 04-configure-ediscovery.ps1        Creates eDiscovery case, hold, search (IPPS + Graph)
│
├── ws5-flows/
│   ├── flow-definitions/
│   │   ├── ExecWS-DraftToReview.json      Flow definition: Draft → Review transition
│   │   ├── ExecWS-ReviewToApproved.json   Flow definition: approval workflow
│   │   └── ExecWS-ApprovedToArchive.json  Flow definition: manual archive trigger
│   ├── 01-deploy-flows.ps1                Deploys flows via Power Platform REST API
│   └── 02-enable-flows.ps1                Enables deployed flows after connection validation
│
└── ws6-copilot/
    ├── agent-definition/
    │   └── ExecWorkspace-Copilot.yaml     Agent YAML: instructions, auth, knowledge, topics
    ├── 01-validate-copilot.ps1            Pre-deployment permission checks (PnP + Graph)
    └── 02-deploy-copilot-agent.ps1        Deploys agent via Power Platform REST API
```

---

## Important Notes

### Retention Periods
The retention periods in `ws4-purview/02-configure-retention.ps1` are **placeholders** (7 years archive, 3 years approved). These **must** be updated to match your organisation's governance policy before production deployment.

### Power Automate Connection References
`01-deploy-flows.ps1` binds connection references automatically during CREATE and verifies the bindings before proceeding to PUBLISH and ACTIVATE. No portal interaction is required. If you add new connections after deployment and need to re-bind, delete and redeploy using `01-deploy-flows.ps1` (idempotent — deletes existing ExecWS flows before redeploying). Use `02-enable-flows.ps1` only to re-activate flows that were manually turned off.

### Conditional Access Enforcement
CA policies are created in **Report-only** mode. Review Entra ID sign-in logs to confirm no legitimate users are blocked, then re-run `03-create-conditional-access.ps1 -Enforce` to switch to enforced mode.

### DLP Policy Enforcement
DLP policies are created in **TestWithNotifications** mode. Review Activity Explorer in Purview for false positives, then re-run `04-create-dlp-policies.ps1 -Enforce` to enable blocking.

### Sensitivity Label Propagation
Allow **up to 24 hours** after running `01-create-sensitivity-labels.ps1` before applying labels to libraries. Label propagation to SharePoint requires this time in new tenants.

---

## Known Runtime Issues and Fixes

The following issues were discovered and resolved during dev tenant deployment. They are fixed in the current script versions but documented here as reference.

| Issue | Affected scripts | Fix applied |
|---|---|---|
| `Get-MgGroup -ConsistencyLevel eventual` hangs without `-CountVariable` | WS-1 group validation, CA | Added `-CountVariable count` or replaced with `Invoke-MgGraphRequest` direct REST |
| `Set-StrictMode -Version Latest` conflicts with PS7 `?.` null-conditional | WS-1 PIM | Replaced `$x?.Prop` with explicit `if ($x) { $x.Prop }` |
| PnP + Microsoft.Graph in same PS session causes DLL version conflict | WS-2 permissions, validation | Replaced `Get-MgGroup` with `Invoke-PnPGraphMethod` in PnP scripts |
| PnP.PowerShell 3.x removed `-DisableTeamsChannelIntegration` and `-RequestAccessEmail` params | WS-2 site + settings | Removed former; replaced latter with `Invoke-PnPSPRestMethod` |
| CSOM `$ctx.Load()` + `Invoke-PnPQuery` does not reliably populate list properties | WS-2 validation | Replaced with `Get-PnPList -Includes` and `Invoke-PnPSPRestMethod` for REST-based checks |
| Access review `POST` returning `Forbidden` on first run | WS-1 PIM | Was admin consent propagation delay; re-run after ~5 minutes succeeds |
| `$varName: text` in double-quoted strings — PS treats colon as scope operator | WS-2 validation | Wrap variable in `${varName}:` before colons |
| `Connect-MgGraph` with `-Scopes` reuses WAM-cached delegated token silently | All WS-1 Graph scripts | Replaced with cert auth (`-CertificateThumbprint`) which bypasses WAM cache |
| eDiscovery case creation blocked for service principals — `GetUserNameById` fails in compliance workbench | WS-4 script 04 | Script 04 uses interactive delegated auth (`Connect-IPPSSession -UserPrincipalName`) — the only script with browser sign-in, justified by legal governance requirement |
| eDiscovery Manager role group adds user only as "Manager" (own cases only), not "Administrator" (all cases) | WS-4 script 04 | Used `Update-RoleGroupMember` to add admin; orphaned SP-created cases require manual deletion via Purview portal |
| `ExchangeOnlineManagement` 3.9.x bundles older MSAL.NET — conflicts with `Microsoft.Graph` 2.x in same PS session | WS-4 scripts 01–04 | Pin to 3.8.x via `Import-Module ExchangeOnlineManagement -MaximumVersion 3.8.99` in config.ps1 helpers |
| `PnP.PowerShell` 3.x bundles `Microsoft.Graph.Core` 1.25.x — conflicts with `Microsoft.Graph` SDK 2.x in same PS session | WS-3 scripts 02–03 | Replaced all `Invoke-MgGraphRequest` + `Connect-WorkspaceGraph` with `Invoke-PnPGraphMethod`; app must have `Sites.ReadWrite.All` Graph API permission |
| `Get-PnPSite.Id` returns empty GUID — CSOM lazy loading | WS-3 scripts 02–03 | Replaced with `Invoke-PnPGraphMethod "v1.0/sites/{host}:/{path}"` to get Graph site ID |
| Sensitivity label library assignments silently ignored by Graph API | WS-3 script 02 | **Root cause:** Labels created without `Site` and `UnifiedGroup` ContentType (Groups & sites scope). SharePoint requires these scopes before accepting `defaultSensitivityLabelForLibrary` PATCH requests — without them requests are silently ignored with no error. **Fix applied in `01-create-sensitivity-labels.ps1`:** ContentType now set to `@("File","Email","Site","UnifiedGroup")`. Post-PATCH verification reports `[WARN]` (queued) for genuine propagation delay (1–4h after label creation). |
| `New-DlpCompliancePolicy -Enabled` not a valid IPPS v3 parameter | WS-3 script 04 | Removed; policies are enabled by default on creation |
| `New-DlpComplianceRule -ContentContainsSensitivityLabel` not available in IPPS v3 REST module | WS-3 script 04 | Policy scoped to specific SP site URL; `DocumentSizeOver 10240` used as universal SharePoint predicate |
| `New-DlpComplianceRule -NotifyUserType "NotifyOnly"` not a valid value in IPPS v3 | WS-3 script 04 | Valid values: `NotSet`, `Email`, `PolicyTip` |
| `New-DlpComplianceRule -ContentIsNotLabeled` supported only for Exchange/Endpoint, not SharePoint | WS-3 script 04 | Use `DocumentSizeOver 10240` for SharePoint-scoped policies |
| `New-DlpComplianceRule -DocumentSizeOver` minimum value is 10KB (10240 bytes) | WS-3 script 04 | Use `-DocumentSizeOver 10240` |
| Compliance search (`New-ComplianceSearch`) unavailable on some dev tenants — `cpfdwebservicecloudapp.net` resource not found | WS-4 script 04 | Caught as `[WARN]` not `[FAIL]`; search definition in script is correct and will work in production tenants |
| Flows created via Power Automate REST API store `connectionReferences: {}` (empty) in Dataverse `clientdata` — causes 404 on every action in the portal | WS-5 script 01 | Include `connectionReferences` in the REST API CREATE body using `ApiConnectionReference` format (`id`, `connectionName`, `source: "Embedded"`); Flow REST API then writes full bindings into `clientdata` automatically |
| `connectionReferenceName` in action `host` resolves against Dataverse CR entity logical names (e.g., `new_sharedsharepointonline_8d48c`), not the dict key — returns null, blocking PublishXml | WS-5 flow definitions | Use `connectionName` (referencing the key in the flow's `connectionReferences` dict) instead of `connectionReferenceName` in all action hosts |
| PublishXml fails with `InvalidOpenApiConnectionWebhookOperationType` — "operation must be of type OpenApiConnection as the corresponding operation GetOnUpdatedFileItems is not a webhook" | WS-5 flow definitions | `GetOnUpdatedFileItems` is a batch/polling trigger (`x-ms-trigger: batch` in the SP connector swagger), not a webhook. Use trigger type `OpenApiConnection` with `recurrence: { frequency: "Minute", interval: 1 }` instead of `OpenApiConnectionWebhook` |
| `/start` endpoint rejects flow with `CannotStartUnpublishedSolutionFlow` | WS-5 script 01 | PublishXml must succeed before calling `/start`; the 4-step order (CREATE → VERIFY → PUBLISH → ACTIVATE) is mandatory |
| Approvals connector `StartAndWaitForAnApproval` — deprecated parameter names (`ApprovalName`, `AssignedTo`, `Details`) cause action to fail | WS-5 ReviewToApproved flow | Use current parameter names: `WebhookApprovalCreationInput/title`, `/assignedTo`, `/details`, `/itemLink`, `/itemLinkDescription` with `approvalType: "Basic"` |
| Office 365 Outlook `SendEmailV2` action — nested object for email parameters causes `InvalidTemplate` | WS-5 DraftToReview + ReviewToApproved flows | Use slash-notation parameters: `emailMessage/To`, `emailMessage/Subject`, `emailMessage/Body`, `emailMessage/Importance` |
| `pac copilot create` fails with "does not have permission to access admin/environments" | WS-6 script 02 | The deployment service principal needs the **Power Platform Administrator** Entra ID role. Grant at: Entra ID > Roles > Power Platform Administrator > Add assignments > select the app registration. Without it, the script falls back to printing portal completion steps. |
| `pac copilot create` requires an existing template — cannot create a new agent from scratch | WS-6 script 02 | `pac copilot create --templateFileName` clones from an existing template; it cannot bootstrap a brand-new agent. First-time creation must be done via the Copilot Studio portal. After creation, run `pac copilot extract-template` to capture the real template for future automated deployments. |
| Copilot Studio SharePoint knowledge source fails silently with library-level URL | WS-6 portal step | Copilot Studio only accepts site-level URLs (e.g. `https://<tenant>.sharepoint.com/sites/exec-workspace`). Library-level URLs (`.../Approved`) appear to validate but fail on save. Use the site URL; runtime governance is enforced by SharePoint permissions. |
| Service principal must be registered with Power Platform via `pac admin application register` before PAC CLI commands work | WS-6 script 02 | Even with correct roles, PAC CLI cert auth fails with "user is not a member of the organization" until the SP is registered. Run: `pac auth select --name <admin-profile>` then `pac admin application register --application-id <SP-client-id>`. |


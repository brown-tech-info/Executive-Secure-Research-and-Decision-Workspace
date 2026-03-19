# Executive Workspace — Dev Tenant Deployment Guide

This is the step-by-step runbook for deploying the Executive Secure Research & Decision Workspace to a fresh M365 dev tenant. Follow every section in order. Each workstream has a validation checkpoint before proceeding to the next.

---

## Before You Start — Fill In Your Values

Replace every placeholder below with your real dev tenant values **before running any script**. You will need these repeatedly throughout the deployment.

| Placeholder | What it is | Where to find it |
|---|---|---|
| `YOUR-TENANT-NAME` | Tenant name (e.g. `contoso`) — the part before `.onmicrosoft.com` | M365 Admin Centre → Settings → Org settings |
| `YOUR-TENANT-ID` | Entra ID Tenant ID (GUID) | Entra portal → Overview → Tenant ID |
| `admin@YOUR-TENANT.onmicrosoft.com` | Your Global Admin UPN | The account you used to set up the dev tenant |
| `YOUR-PLATFORM-ADMIN-OBJECT-ID` | Object ID of the user who will approve PIM activations | Entra portal → Users → your admin account → Object ID |
| `YOUR-APPROVER-UPN` | UPN of the flow approver (who approves doc promotions) | Any licensed user; can be your admin account |
| `YOUR-ENVIRONMENT-ID` | Power Platform environment ID | Power Platform Admin Centre → Environments → your default env → Details |

> **Site URL** (once provisioned) will be `https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace`

---

## Phase 0 — Prerequisites

### 0.1 Licensing check

Confirm your dev tenant has the following (the build requires all of these):

| Requirement | Why needed |
|---|---|
| Microsoft 365 E5 (or E3 + add-ons) | Sensitivity labels, DLP, Purview, PIM, Copilot Studio |
| Entra ID P2 | PIM for Groups, Access Reviews |
| Microsoft Copilot Studio licence | Agent deployment in WS-6 |
| Power Automate Premium or Per-flow | For SharePoint and Approval connectors |

Verify in **M365 Admin Centre → Billing → Licences**.

### 0.2 PowerShell version

All scripts require PowerShell 7.0+. Check and upgrade if needed:

```powershell
$PSVersionTable.PSVersion
# Must show Major: 7 or higher
# If not, download from: https://github.com/PowerShell/PowerShell/releases/latest
```

### 0.3 Install required modules

Run these once in an elevated PowerShell 7 session. Safe to re-run if modules are already installed.

```powershell
# Microsoft Graph (identity, CA, PIM, governance)
Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber

# PnP PowerShell (SharePoint)
Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber

# Exchange Online Management (IPPS — sensitivity labels, DLP, retention, eDiscovery)
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber

# Az.Accounts (Power Automate + Copilot Studio REST API auth)
Install-Module Az.Accounts -Scope CurrentUser -Force -AllowClobber

# Verify all installed
Get-Module Microsoft.Graph, PnP.PowerShell, ExchangeOnlineManagement, Az.Accounts -ListAvailable |
    Select-Object Name, Version
```

### 0.4 Set up silent certificate authentication

All scripts authenticate using a self-signed certificate registered with an Entra ID app — no browser popups or device codes during deployment.

**0.4a — Set up `config.ps1`:**
```powershell
Copy-Item scripts\config.ps1.example scripts\config.ps1
# Edit scripts\config.ps1 and fill in: TenantId, TenantName, ClientId, CertThumbprint
```

**0.4b — Register the Entra app** (one-time, needs device code sign-in as Global Admin):
```powershell
Register-PnPEntraIDAppForInteractiveLogin `
    -ApplicationName "ExecWorkspace-PnP-Admin" `
    -Tenant          "YOUR-TENANT.onmicrosoft.com" `
    -SharePointDelegatePermissions "AllSites.FullControl","TermStore.ReadWrite.All","User.ReadWrite.All" `
    -GraphDelegatePermissions "Group.ReadWrite.All","Directory.ReadWrite.All","User.ReadWrite.All" `
    -DeviceLogin
# Copy the returned ClientId to config.ps1
```

Then grant Application permissions in Entra portal (App registrations → ExecWorkspace-PnP-Admin → API permissions). See `scripts/README.md → Authentication Setup` for the full permissions list.

**0.4c — Generate and register the deployment certificate:**
```powershell
$cert = New-SelfSignedCertificate -Subject "CN=ExecWorkspace-Deploy-Cert" `
    -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable `
    -KeySpec Signature -KeyLength 2048 -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(2)
Write-Host "Thumbprint: $($cert.Thumbprint)"  # → config.ps1 $CertThumbprint
Export-Certificate -Cert $cert -FilePath "scripts\deploy-cert.cer"
```
Upload `deploy-cert.cer` to the app registration (Certificates & secrets) and grant admin consent.

**0.4d — Verify silent auth:**
```powershell
. .\scripts\config.ps1
Connect-WorkspaceGraph
(Get-MgContext).AppName   # Should print "ExecWorkspace-PnP-Admin" with no browser prompt
Disconnect-MgGraph
```

### 0.5 Look up your approver Object ID (for PIM)

```powershell
Connect-WorkspaceGraph
(Get-MgUser -UserId "admin@YOUR-TENANT.onmicrosoft.com").Id
Disconnect-MgGraph
```

---

## Phase 1 — Entra ID: Groups, Conditional Access, PIM

> **Role required:** Global Administrator (or: Groups Admin + CA Admin + Privileged Role Admin)
> **Navigate to:** `scripts/ws1-entra/`

### Step 1.1 — Create security groups

```powershell
cd scripts/ws1-entra

.\01-create-security-groups.ps1 -TenantId "YOUR-TENANT-ID"
```

**WhatIf dry-run first (recommended):**
```powershell
.\01-create-security-groups.ps1 -TenantId "YOUR-TENANT-ID" -WhatIf
```

**Expected output:** Five groups created:
- `ExecWorkspace-Authors` — **mail-enabled security group** (provisioned via Exchange Online)
- `ExecWorkspace-Reviewers`
- `ExecWorkspace-Executives`
- `ExecWorkspace-Compliance`
- `ExecWorkspace-PlatformAdmins`

> ⚠️ **EXO requirement:** `ExecWorkspace-Authors` is provisioned via `New-DistributionGroup -Type Security` in Exchange Online (not Graph). The account running this script must hold the **Recipient Management** EXO role (or Organization Management). The script connects to EXO via device code when a mail-enabled group needs creating. This is required because the MeetingPackOpen flow sends notification emails to `execworkspace-authors@<tenant>` and the group must be mail-enabled to receive them.

### Step 1.2 — Validate groups

```powershell
.\02-validate-entra-groups.ps1 -TenantId "YOUR-TENANT-ID"
```

**Expected output:** All five groups show `[PASS]`. Do not proceed to Step 1.3 if any show `[FAIL]`.

### Step 1.3 — Create Conditional Access policies (Report-only)

```powershell
.\03-create-conditional-access.ps1 -TenantId "YOUR-TENANT-ID"
```

This creates two policies in **Report-only mode** (safe for dev — no users are blocked yet):
- `CA-ExecWorkspace-BaselineAccess` — MFA + compliant device for all workspace users
- `CA-ExecWorkspace-AdminAccess` — MFA + compliant device for PlatformAdmins (4hr session)

**Verify in Entra portal:** Entra ID → Security → Conditional Access → Policies. Both should show **Report-only** state.

> ⚠️ Do not use `-Enforce` until after you have signed in as workspace users and verified sign-in logs show no unexpected blocks. Enforcement is a post-deployment step (Phase 8).

### Step 1.4 — Configure PIM for Groups

You need your **admin user's Object ID** and an **email for access review notifications** before running this step.

```powershell
.\04-configure-pim.ps1 `
    -TenantId                     "YOUR-TENANT-ID" `
    -PlatformAdminApproverId      "YOUR-PLATFORM-ADMIN-OBJECT-ID" `
    -AccessReviewNotificationEmail "admin@YOUR-TENANT.onmicrosoft.com"
```

**Expected output:** PIM settings applied to `ExecWorkspace-PlatformAdmins` (4hr max, MFA + approval) and `ExecWorkspace-Compliance` (8hr max, MFA + justification). Access reviews scheduled quarterly/bi-annually.

> ℹ️ This script configures PIM **settings** only. You must manually add eligible members (see Phase 8, Step 8.3).

---

## Phase 2 — SharePoint: Site and Document Libraries

> **Role required:** SharePoint Administrator
> **Navigate to:** `scripts/ws2-sharepoint/`

### Step 2.1 — Provision the Communication Site

```powershell
cd ../ws2-sharepoint

.\01-provision-site.ps1 `
    -TenantName "YOUR-TENANT-NAME" `
    -SiteOwner  "admin@YOUR-TENANT.onmicrosoft.com"
```

**WhatIf first:**
```powershell
.\01-provision-site.ps1 `
    -TenantName "YOUR-TENANT-NAME" `
    -SiteOwner  "admin@YOUR-TENANT.onmicrosoft.com" `
    -WhatIf
```

**Expected output:** Site provisioned at `https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace`

> ℹ️ Site provisioning can take 30–90 seconds. The script polls until the site is ready.

### Step 2.2 — Create document libraries

```powershell
.\02-create-libraries.ps1 -SiteUrl "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace"
```

**Expected output:** Four libraries created with broken permission inheritance:
- `Draft` — Lifecycle stage 1
- `Review` — Lifecycle stage 2
- `Approved` — Lifecycle stage 3 (Executives read here)
- `Archive` — Lifecycle stage 4 (long-term retention)

### Step 2.3 — Configure library permissions

This script looks up the Entra group Object IDs at runtime and applies them as permissions.

```powershell
.\03-configure-permissions.ps1 `
    -SiteUrl  "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace" `
    -TenantId "YOUR-TENANT-ID"
```

**Permission matrix applied:**

| Library | Authors | Reviewers | Executives | Compliance | PlatformAdmins |
|---|---|---|---|---|---|
| Draft | Contribute | Read | — | — | Full Control |
| Review | Read | Contribute | — | — | Full Control |
| Approved | — | Read | Read | Read | Full Control |
| Archive | — | — | — | Read | Full Control |

### Step 2.4 — Add metadata columns

```powershell
.\04-add-metadata-columns.ps1 -SiteUrl "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace"
```

**Expected output:** Five mandatory columns added to all libraries: `LifecycleState`, `ClassificationLevel`, `ApprovedBy`, `ReviewDueDate`, `RetentionCategory`.

### Step 2.5 — Configure governance settings

```powershell
.\05-configure-settings.ps1 `
    -SiteUrl    "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace" `
    -TenantName "YOUR-TENANT-NAME"
```

**Settings applied:** External sharing disabled, versioning enabled (major + minor), draft visibility restricted to Author, audit logging enabled, audience targeting on Approved library.

### Step 2.6 — Validate SharePoint

```powershell
.\06-validate-spo.ps1 `
    -SiteUrl  "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace" `
    -TenantId "YOUR-TENANT-ID"
```

**Expected output:** All validation checks show `[PASS]`. Do not proceed to Phase 3 if any show `[FAIL]`.

### Step 2.7 — Add meeting cadence metadata columns

```powershell
.\04-add-metadata-columns.ps1 `
    -SiteUrl "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace"
```

> ℹ️ The script is idempotent — if run previously, only the four new meeting cadence columns will be added (`ExecWS_MeetingType`, `ExecWS_MeetingDate`, `ExecWS_MeetingCycle`, `ExecWS_PackVersion`). Existing columns are skipped.

**Expected output:** Four new columns added across all libraries. Existing columns show `[SKIP]`.

### Step 2.8 — Create meeting views in the Approved library

```powershell
.\07-create-meeting-views.ps1 `
    -SiteUrl "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace"
```

**Five views created in the Approved library:**
- `Board Pack` — filtered to Board meeting type, sorted by meeting date
- `SteerCo Pack` — filtered to SteerCo meeting type
- `ExecTeam Pack` — filtered to ExecTeam meeting type
- `Current Cycle` — filtered to current calendar month
- `By Meeting` — all documents grouped by meeting cycle identifier

---

## Phase 3 — MIP Sensitivity Labels and DLP

> **Role required:** Compliance Administrator (or Global Administrator)
> **Navigate to:** `scripts/ws3-mip/`

> ⚠️ **Timing note:** Sensitivity label policies can take **up to 24 hours** to propagate to SharePoint in a new tenant. Steps 3.1 and 3.3 can run on day one. Steps 3.2 and 3.4 require propagation — run them the following day.

### Step 3.0 — Enable AIP integration (prerequisite)

> ℹ️ Run this **before** Step 3.1. It is idempotent — safe to run even if already enabled.

```powershell
.\00-enable-aip-integration.ps1
```

**What this does:** Enables `Set-PnPTenant -EnableAIPIntegration $true` — the tenant-level switch that allows SharePoint to sync sensitivity labels from Microsoft Purview into its internal label store. Without this, the Graph API silently accepts PATCH requests to set default library labels but SharePoint never writes them.

**Expected output:** `[OK] AIP integration enabled` or `[SKIP] already enabled`

> ⚠️ **If you see `[WARN] Queued:4` from `02-apply-sensitivity-labels.ps1` after 48+ hours**, the labels may have been created without the `Site` and `UnifiedGroup` content types — see the [Troubleshooting](#troubleshooting) section.

---

### Step 3.1 — Create sensitivity labels and policy

```powershell
.\01-create-sensitivity-labels.ps1
```

**WhatIf first:**
```powershell
.\01-create-sensitivity-labels.ps1 -WhatIf
```

**Expected output:** Two labels created and published via `ExecWorkspace-LabelPolicy`:
- `ExecWorkspace-Confidential` — for Draft and Review libraries
- `ExecWorkspace-HighlyConfidential` — for Approved and Archive libraries

> ⚠️ **Encryption rights note:** The labels are created without encryption rights — this is intentional as the full `EncryptionRightsDefinitions` object requires a pre-agreed rights policy. After creation, configure encryption in **Microsoft Purview portal → Information Protection → Labels → [label] → Encryption** before going to production. For dev testing, labels without encryption are sufficient.

### Step 3.2 — Apply default labels to libraries

> ⏳ **Wait at least 24 hours** after Step 3.1 before running this step (label policy must propagate to SharePoint). The script reports `[WARN] Queued` if propagation is not yet complete — re-run the following day.

> **Prerequisite:** The `ExecWorkspace-PnP-Admin` app must have `Sites.ReadWrite.All` (Microsoft Graph, Application) granted in Entra portal → API permissions.

```powershell
.\02-apply-sensitivity-labels.ps1 `
    -SiteUrl "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace"
```

**Expected output:** `Applied: 4` — `ExecWorkspace-Confidential` on Draft + Review, `ExecWorkspace-HighlyConfidential` on Approved + Archive.

### Step 3.3 — Create DLP policies (test mode)

> ℹ️ This step does **not** require label propagation — run it on day one alongside Step 3.1.

```powershell
.\04-create-dlp-policies.ps1 `
    -SiteUrl                     "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace" `
    -ComplianceNotificationEmail "admin@YOUR-TENANT.onmicrosoft.com"
```

**Two policies created in `TestWithNotifications` mode** (audit only — no blocking yet):
- `ExecWorkspace-BlockExternalSharing` — blocks external sharing of all content on the workspace site; audits content missing sensitivity labels
- `ExecWorkspace-AuditAndAlert` — generates incident reports for all document activity on the site

> ℹ️ DLP enforcement is a post-deployment step (Phase 8). Run in test mode first to review Activity Explorer before blocking.

> **Known limitation:** IPPS v3 REST module does not expose `-ContentContainsSensitivityLabel`. Policies are scoped to the specific SharePoint site URL using `DocumentSizeOver 10240` as the universal predicate. Exchange/Teams label-based coverage is a future enhancement. Site-level external sharing disabled (WS-2) is the primary control.

### Step 3.4 — Validate MIP

> ⏳ Wait until Step 3.2 reports `Applied: 4` (not `Queued`) before running this step.

```powershell
.\03-validate-mip.ps1 `
    -SiteUrl "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace"
```

**Expected output:** All label and policy checks `[PASS]`; all library default label checks `[PASS]`.

---

## Phase 4 — Purview: Audit, Retention, and eDiscovery

> **Role required:** Compliance Administrator (or Global Administrator)
> **Navigate to:** `scripts/ws4-purview/`

### Step 4.1 — Enable Unified Audit Log

```powershell
cd ../ws4-purview

.\01-configure-audit.ps1
```

**Expected output:** `[OK] Unified Audit Log is ENABLED.`

> ℹ️ In M365 E3/E5 tenants the audit log is usually already enabled. This script is idempotent — safe to run regardless.

### Step 4.2 — Configure retention labels

> ⚠️ **Placeholder retention periods** — the script uses `7 years (Archive)` and `3 years (Approved)` as defaults. Update these to match your actual governance policy before deploying to production. For dev testing, the defaults are fine.

```powershell
.\02-configure-retention.ps1
```

**Expected output:** Two retention labels created: `ExecWS-Approved-Retention` (3yr) and `ExecWS-Archive-Retention` (7yr).

### Step 4.3 — Validate Purview configuration

```powershell
.\03-validate-purview.ps1 `
    -SiteUrl "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace"
```

**Expected output:** Audit log and retention label checks show `[PASS]`.

### Step 4.4 — Configure eDiscovery case and hold

> ⚠️ **Interactive sign-in required.** This is the only script in the deployment that requires a browser sign-in. This is intentional — Microsoft's compliance workbench does not permit service principals to own eDiscovery cases (legal governance requirement: a named human must own the case).

```powershell
.\04-configure-ediscovery.ps1
```

For dev tenant (to avoid naming conflict with any orphaned case):
```powershell
.\04-configure-ediscovery.ps1 -CaseName "ExecWorkspace-eDiscovery-Dev"
```

**Expected output:** eDiscovery case `ExecWorkspace-eDiscovery` (or `-Dev` variant) created with a content hold `ExecWorkspace-LegalHold` scoped to the workspace site.

> ℹ️ **Compliance search** (`New-ComplianceSearch`) requires EXO 3.9.0+ with `-EnableSearchOnlySession` which conflicts with Microsoft.Graph 2.x in the same session. The search step is caught as `[WARN]` on dev tenants. The case and hold are the governance deliverables for this phase.

---

## Phase 5 — Power Automate: Lifecycle Flows

> **Role required:** Power Platform Environment Admin + Power Automate Premium licence
> **Navigate to:** `scripts/ws5-flows/`
> **Requires:** Az.Accounts module; `Connect-AzAccount` will be called interactively

> ⚠️ **Connection references prerequisite:** The flows reference three connectors — SharePoint, Approvals, and Office 365 Outlook. These connections must exist in your Power Platform environment **before** you deploy the flows. If you have never used Power Automate in this tenant, create them first:
>
> 1. Go to `make.powerautomate.com`
> 2. Click **Data → Connections → New connection**
> 3. Create: **SharePoint**, **Approvals**, **Office 365 Outlook**
> 4. Sign in as the admin account for each

> **One-time prerequisite — Register SP as Power Platform Management App**
> Before the first flow deployment, the service principal must be registered as a Power Platform management application and the admin user must be provisioned as an Environment Administrator. Run once as a Global Admin:
> ```powershell
> Import-Module Microsoft.PowerApps.Administration.PowerShell -RequiredVersion 2.0.214 -Force
> Add-PowerAppsAccount -TenantID '<tenant-id>' -ApplicationId '<client-id>' -CertificateThumbprint '<thumbprint>'
> New-PowerAppManagementApp -ApplicationId '<client-id>'
> ```
> This grants the SP access to Power Platform admin APIs. Without this step, `Get-AzAccessToken` calls for the Flow and Dataverse APIs will return empty environment lists.

### Step 5.1 — Get your Power Platform Environment ID

> **Interactive authentication required:** Step 5.1 uses `Connect-AzAccount -UseDeviceAuthentication`. The script will display a device code and URL — open the URL in a browser and enter the code, signing in as a tenant admin. Subsequent commands in the same PowerShell session reuse the cached token automatically.

```powershell
# In a browser: https://admin.powerplatform.microsoft.com/
# Environments → your default environment → Details → Environment ID
# OR via API:
Connect-AzAccount -UseDeviceAuthentication -TenantId "YOUR-TENANT-ID"
$token = (Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com").Token
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
(Invoke-RestMethod -Uri "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments?api-version=2016-11-01" -Headers $headers).value |
    Select-Object @{n='Name';e={$_.name}}, @{n='DisplayName';e={$_.properties.displayName}} |
    Format-Table
```

### Step 5.2 — Deploy flows

> ℹ️ **Group email note:** `ExecWorkspace-Authors` is a mail-enabled security group and can receive notification emails directly. The other four ExecWorkspace groups are plain security groups. Pass the actual group email addresses for all parameters; they will be substituted into the flow definitions at deploy time.

```powershell
cd ../ws5-flows

.\01-deploy-flows.ps1 `
    -TenantId             "YOUR-TENANT-ID" `
    -SiteUrl              "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace" `
    -ReviewerGroupEmail   "admin@YOUR-TENANT.onmicrosoft.com" `
    -ExecutivesGroupEmail "admin@YOUR-TENANT.onmicrosoft.com" `
    -ComplianceGroupEmail "admin@YOUR-TENANT.onmicrosoft.com" `
    -ApproverUpns         "admin@YOUR-TENANT.onmicrosoft.com" `
    -EnvironmentId        "YOUR-ENVIRONMENT-ID"
```

**WhatIf first:**
```powershell
.\01-deploy-flows.ps1 `
    -TenantId "YOUR-TENANT-ID" `
    -SiteUrl  "https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace" `
    -WhatIf
```

**Expected output:** Three flows deployed in **Stopped** state:
- `ExecWS-DraftToReview`
- `ExecWS-ReviewToApproved`
- `ExecWS-ApprovedToArchive`

### Step 5.3 — Verify connection references (manual step)

Before enabling the flows, verify connection references are valid:

1. Go to `make.powerautomate.com → My flows`
2. Open each of the three flows
3. If prompted **"Connection references need to be updated"**, select your existing connections
4. Save each flow after resolving all connection references

### Step 5.4 — Enable flows

```powershell
.\02-enable-flows.ps1 -TenantId "YOUR-TENANT-ID" -EnvironmentId "YOUR-ENVIRONMENT-ID"
```

**Expected output:** All three flows switched from Stopped → Running.

### Step 5.5 — Deploy meeting pack open flow

```powershell
.\01-deploy-flows.ps1 `
    -TenantId             "YOUR-TENANT-ID" `
    -SiteUrl              "https://<dev-tenant>.sharepoint.com/sites/exec-workspace" `
    -ReviewerGroupEmail   "execworkspace-reviewers@<dev-tenant>.onmicrosoft.com" `
    -ExecutivesGroupEmail "execworkspace-executives@<dev-tenant>.onmicrosoft.com" `
    -ComplianceGroupEmail "execworkspace-compliance@<dev-tenant>.onmicrosoft.com" `
    -AuthorsGroupEmail    "execworkspace-authors@<dev-tenant>.onmicrosoft.com" `
    -ApproverUpns         "approver@<dev-tenant>.onmicrosoft.com" `
    -FlowFilter           "MeetingPackOpen"
```

**What this deploys:** `ExecWS-MeetingPackOpen` — triggers on new Outlook calendar events whose subject contains a recognised meeting type keyword (Board, SteerCo, ExecTeam). Creates a pre-populated placeholder document in the Draft library and notifies the Authors group.

> ⚠️ **Prerequisite:** The shared calendar used for meeting events must be accessible to the flow's service connection. Ensure the Office 365 Outlook connection is authenticated against an account with read access to the target calendar.

> ℹ️ **Meeting type detection:** The flow parses meeting type from the event subject. Calendar events must include the meeting type keyword in the subject line (e.g. "Board Meeting — March 2026", "SteerCo — Week 12").

### Step 5.6 — Run end-to-end test

```powershell
.\03-test-e2e-meetingpackopen.ps1
```

This script validates the full MeetingPackOpen flow lifecycle:
1. Creates an Outlook calendar event with "Board Meeting" in the subject
2. Polls the Draft library every 30 s for up to 7 min for the placeholder document
3. Verifies the placeholder file (`Board-{date}-PackPlaceholder.txt`) exists in Draft
4. Verifies all 6 metadata columns are correctly populated
5. Verifies the `Notify_Authors` action executed (via flow run history or SPO evidence inference)

**Expected output:** `RESULT: ALL 9 TESTS PASSED`. Typical trigger latency ~94 seconds.

> ⚠️ **Calendar permission gap:** The `ExecWorkspace-PnP-Admin` SP lacks `Calendars.ReadWrite` (Application). The test script automatically falls back to device-code delegated auth for the calendar event creation step — you will be prompted to authenticate once as `admin@<tenant>`. To remove this prompt permanently, grant `Calendars.ReadWrite` (Application) to the SP in the Entra portal and grant admin consent.

---

## Phase 6 — Copilot Studio Agent

> **Role required:** Power Platform Administrator (Entra ID role) + Copilot Studio licence
> **Navigate to:** `scripts/ws6-copilot/`

> ℹ️ **Two deployment methods are supported.** Method A (PAC CLI) is fully automated. Method B (portal) is used when the deployment service principal lacks the Power Platform Administrator role or when PAC CLI is unavailable. Both produce an identical, working agent.

### Method A — Automated deployment (PAC CLI)

Requires: Service principal with **Power Platform Administrator** Entra ID role (grant via Entra ID admin centre → Roles → Power Platform Administrator → Add assignments) and the PAC CLI registered via `pac admin application register`.

```powershell
cd scripts/ws6-copilot

.\01-validate-copilot.ps1 `
    -SiteUrl      "https://<tenant>.sharepoint.com/sites/exec-workspace" `
    -TenantId     "<your-tenant-id>" `
    -DataverseUrl "https://<dataverse-org>.crm.dynamics.com"   # enables automated web-search check

.\02-deploy-copilot-agent.ps1 `
    -TenantId "YOUR-TENANT-ID" `
    -SiteUrl  "https://<tenant>.sharepoint.com/sites/exec-workspace"
```

The script will: create the agent via `pac copilot create`, capture the Bot ID, publish via `pac copilot publish`, **automatically disable Web Search** via a Dataverse PATCH (`msai_searchtheweb = false`), then print the portal checklist for the one remaining manual step (knowledge source — no public API).

> **Dev tenant deployed values:**
> - Bot ID: `<bot-id>`
> - Environment: `Default-<tenant-id>`
> - Dataverse: `https://<dataverse-org>.crm.dynamics.com`
> - Portal: `https://copilotstudio.microsoft.com/environments/Default-<tenant-id>/bots/<bot-id>/overview`

### Method B — Portal deployment (fallback)

If PAC CLI is unavailable or the SP lacks the required role, the script prints a pre-populated portal checklist. Complete the steps at `copilotstudio.microsoft.com`:

1. Create agent named `ExecWorkspace-Copilot`
2. **Overview → Description**: paste — *"Secure AI assistant scoped to the Executive Workspace Approved library only. Read-only. Tenant-contained. Entra ID authentication required. Access is governed by SharePoint permissions — content is only visible to authorised ExecWorkspace-Executives members."*
   > ℹ️ This field is not settable via API — it must be set manually in the portal
3. **Knowledge** → **+ Add** → **SharePoint** → enter **site URL**: `https://<tenant>.sharepoint.com/sites/exec-workspace`
   > ⚠️ Use the **site URL** — library-level URLs (`.../Approved`) are not accepted by Copilot Studio and will fail silently
4. **Settings → Security → Authentication**: Microsoft (Entra ID), Require sign-in **ON**
5. **Settings → Generative AI → Instructions**: paste the 7-rule system prompt from the script output
6. **Settings → Generative AI → Search the web**: **OFF** ← ⚠️ **CRITICAL — failure violates tenant-containment policy**
7. **Publish**

**Expected outcome:** Agent `ExecWorkspace-Copilot` live in portal. Pre-flight checks pass via `01-validate-copilot.ps1`.

**Verify in portal:** `copilotstudio.microsoft.com` → Agents → `ExecWorkspace-Copilot`

---

## Phase 7 — End-to-End Smoke Test

Once all phases are complete, run this manual smoke test before reporting the build as done.

### 7.1 Add test users to groups

In **Entra portal → Groups**, add your test accounts:
- Your admin UPN → `ExecWorkspace-Authors`
- Your admin UPN → `ExecWorkspace-Executives`

### 7.2 Test document lifecycle (manual)

1. Navigate to `https://YOUR-TENANT-NAME.sharepoint.com/sites/exec-workspace`
2. Go to the **Draft** library
3. Upload a test document
4. Set the `LifecycleState` column to `Review`
5. Confirm `ExecWS-DraftToReview` flow triggers (check Power Automate run history)
6. Go to the **Review** library and confirm the document moved
7. Approve the document via the Approvals notification
8. Confirm document moves to **Approved** library

### 7.3 Test Copilot agent

1. Open `copilotstudio.microsoft.com → ExecWorkspace-Assistant → Test`
2. Ask: `"What approved documents are available?"`
3. Confirm the agent returns content from the Approved library only
4. Confirm the agent does not surface Draft or Review content

### 7.4 Test CA policies (Report-only)

1. Sign in as an `ExecWorkspace-Authors` member
2. Open **Entra portal → Sign-in logs**
3. Filter for sign-ins to SharePoint
4. Confirm CA policies show as `Report-only: Would not apply` or `Report-only: Would apply`
5. Confirm no users were blocked

---

## Phase 8 — Post-Deployment Hardening

These steps complete the security posture. Do not skip in production.

### Step 8.1 — Enforce Conditional Access (after reviewing sign-in logs)

Once you have verified in sign-in logs that no legitimate users would be unexpectedly blocked:

```powershell
cd scripts/ws1-entra
.\03-create-conditional-access.ps1 -TenantId "YOUR-TENANT-ID" -Enforce
```

This switches both CA policies from Report-only → **Enabled**.

> ⚠️ Users without compliant devices or without MFA configured will be blocked from accessing the workspace. Ensure all workspace members have MFA enrolled and compliant devices registered before enforcing.

### Step 8.2 — Enforce DLP policies (after reviewing Activity Explorer)

Review DLP activity in **Microsoft Purview portal → Activity Explorer** first. Once satisfied:

```powershell
cd scripts/ws3-mip
.\04-create-dlp-policies.ps1 `
    -TenantAdminEmail            "admin@YOUR-TENANT.onmicrosoft.com" `
    -ComplianceNotificationEmail "admin@YOUR-TENANT.onmicrosoft.com" `
    -Enforce
```

This switches DLP policies from TestWithNotifications → **Enabled** (blocking mode).

### Step 8.3 — Add PIM eligible members

PIM group settings are configured but members must be added manually:

1. Go to **Entra portal → Identity Governance → Privileged Identity Management**
2. Click **Groups** → `ExecWorkspace-PlatformAdmins`
3. Click **Assignments → Add assignments → Eligible**
4. Add your admin account (or designated platform admins)
5. Repeat for `ExecWorkspace-Compliance`

### Step 8.4 — Configure sensitivity label encryption rights

The labels were created without encryption configuration (the full encryption API requires a pre-agreed rights definition). To add encryption:

1. Go to **Microsoft Purview portal → Information Protection → Sensitivity labels**
2. Edit `ExecWorkspace-HighlyConfidential`
3. Under **Encryption**, set:
   - Assign permissions now: Yes
   - Users/groups: `ExecWorkspace-Executives`, `ExecWorkspace-Compliance`
   - Permissions: Viewer (read-only)
4. Save and publish

### Step 8.5 — Review retention periods

The retention script uses placeholder durations (7yr archive, 3yr approved). Update to match actual governance policy before production:

```powershell
# Edit the retention values in:
scripts/ws4-purview/02-configure-retention.ps1
# Parameters: $ArchiveRetentionYears and $ApprovedRetentionYears
# Then re-run the script — it is idempotent
```

---

## Deployment Status Tracker

Use this table to track progress during the deployment session.

| Phase | Step | Description | Status |
|---|---|---|---|
| 0 | 0.1 | Licensing confirmed | ✅ |
| 0 | 0.2 | PowerShell 7.0+ confirmed | ✅ |
| 0 | 0.3 | All 4 PS modules installed | ✅ |
| 0 | 0.4 | Auth setup: Entra app + cert + config.ps1 | ✅ |
| 0 | 0.5 | Approver Object ID recorded | ✅ |
| 1 | 1.1 | Security groups created | ✅ |
| 1 | 1.2 | Groups validated | ✅ |
| 1 | 1.3 | CA policies created (Report-only) | ✅ |
| 1 | 1.4 | PIM configured | ✅ |
| 2 | 2.1 | SPO site provisioned | ✅ |
| 2 | 2.2 | Libraries created | ✅ |
| 2 | 2.3 | Permissions applied | ✅ |
| 2 | 2.4 | Metadata columns added | ✅ |
| 2 | 2.5 | Governance settings configured | ✅ |
| 2 | 2.6 | SPO validated | ✅ |
| 3 | 3.1 | Sensitivity labels created | ✅ (recreated 2026-03-16 with correct scope: File, Email, Site, UnifiedGroup) |
| 3 | 3.2 | Labels applied to libraries | ⏳ Awaiting SP propagation (~1–4h from 13:43 UTC 2026-03-16). Re-run `02-apply-sensitivity-labels.ps1` |
| 3 | 3.3 | DLP policies created (test mode) | ✅ |
| 3 | 3.4 | MIP validated | ⏳ Re-run `03-validate-mip.ps1` after 3.2 reports `Applied: 4` |
| 4 | 4.1 | Unified Audit Log enabled | ✅ |
| 4 | 4.2 | Retention labels created | ✅ |
| 4 | 4.3 | Purview validated | ✅ |
| 4 | 4.4 | eDiscovery case + hold created | ✅ |
| 5 | 5.1 | Environment ID retrieved | ☐ |
| 5 | 5.2 | Flows deployed (Stopped) | ☐ |
| 5 | 5.3 | Connection references verified | ☐ |
| 5 | 5.4 | Flows enabled (Running) | ☐ |
| 6 | 6.1 | Copilot pre-flight passed | ☐ |
| 6 | 6.2 | Copilot agent deployed | ☐ |
| 7 | 7.1 | Test users added to groups | ☐ |
| 7 | 7.2 | Document lifecycle smoke test | ☐ |
| 7 | 7.3 | Copilot agent smoke test | ☐ |
| 7 | 7.4 | CA Report-only verified | ☐ |
| 8 | 8.1 | CA policies enforced | ☐ |
| 8 | 8.2 | DLP policies enforced | ☐ |
| 8 | 8.3 | PIM eligible members added | ☐ |
| 8 | 8.4 | Label encryption rights configured | ☐ |
| 8 | 8.5 | Retention periods reviewed | ☐ |

---

## Timing Summary

| Workstream | Estimated time | Notes |
|---|---|---|
| Phase 0 — Prerequisites | 10–15 min | Module installs are the slowest part |
| Phase 1 — Entra ID | 5–10 min | PIM config needs the approver Object ID ready |
| Phase 2 — SharePoint | 10–15 min | Site provisioning may take up to 90 sec |
| Phase 3 — MIP + DLP | 5 min (create) + up to 24hr wait | Label propagation is the bottleneck |
| Phase 4 — Purview | 5–10 min | |
| Phase 5 — Power Automate | 10–15 min | Connection reference setup is manual |
| Phase 6 — Copilot Studio | 5–10 min | Preview API may require PAC CLI fallback |
| Phase 7 — Smoke test | 20–30 min | |
| Phase 8 — Hardening | 15–20 min | CA enforce requires sign-in log review |

> **Recommended approach:** Run Phases 0–3.1 on day one. Let labels propagate overnight. Complete Phases 3.2–8 on day two.

---

## Troubleshooting

### "Connect-MgGraph: Insufficient privileges"
Re-run with a Global Administrator account. Some Graph scopes (PIM, CA) require GA for a new tenant.

### "The site already exists" during SPO provisioning
The script is idempotent — it will detect the existing site and skip creation. This is expected if re-running.

### "Label not found" when running 02-apply-sensitivity-labels.ps1
Label policy has not propagated yet. Wait 1–4 hours and retry. In a brand new tenant this can take the full 24 hours.

### `02-apply-sensitivity-labels.ps1` reports `[WARN] Queued:4` even after 48+ hours

**Root cause:** The sensitivity labels were created without the `Site` and `UnifiedGroup` content types (Groups & sites scope). SharePoint's Graph API silently accepts PATCH requests to `defaultSensitivityLabelForLibrary` but never writes them if the label doesn't carry these scopes — no error is returned.

**Confirm:** Check **Purview portal → Information Protection → Sensitivity labels**. The Scope column for both ExecWorkspace labels must include `Site` (Groups & sites). If it shows only `Files & other data assets, Email`, the scope is missing.

**Fix:** Delete both labels and recreate using the corrected `01-create-sensitivity-labels.ps1` (which now uses `ContentType = @("File","Email","Site","UnifiedGroup")`). Then wait 1–4 hours before re-running `02-apply-sensitivity-labels.ps1`.

### "Flow is missing a connection reference" in Power Automate
Go to `make.powerautomate.com`, open the flow, and manually update the connection references before running `02-enable-flows.ps1`.

### "Copilot Studio API returned 404 or 400"
The preview API may not be available for your tenant tier. Use the PAC CLI fallback:
```powershell
# Install PAC CLI if not already installed:
winget install Microsoft.PowerPlatform.CLI

# Deploy from the agent YAML definition:
pac copilot create `
    --name "ExecWorkspace-Assistant" `
    --environment "YOUR-ENVIRONMENT-ID" `
    --definition "scripts/ws6-copilot/agent-definition/ExecWorkspace-Copilot.yaml"
```

### "Access is denied" on SharePoint permission scripts
Confirm you are connected as a SharePoint Administrator (not just a site owner). Run `Connect-PnPOnline -Url "https://YOUR-TENANT-NAME-admin.sharepoint.com"` with your admin account.

### PIM script exits with "No PIM policy found for group"
This is expected on first run if no eligible assignments have been created yet. Add an eligible member to the group first (Step 8.3), then re-run `04-configure-pim.ps1` to apply the policy rules.

---

*Last updated: 2026-03-12 — All scripts reviewed and corrected. Ready for dev tenant deployment.*

# WS-7: Canvas App Build Guide

## Studio Code View Paste Workflow

This guide covers building and deploying the ExecWorkspace Canvas App using **Power Apps Studio Code View** with `.fx.yaml` source files stored in `scripts/ws7-powerapp/src/`.

### Key Learning

The `.msapp` binary format is undocumented and fragile — programmatic editing is officially unsupported by Microsoft. After extensive testing (28+ .msapp variants), the validated approach is:

1. **Create a blank Canvas App** in Power Apps Studio (Tablet, 1366×768)
2. **Connect data sources first** (SharePoint libraries, Office 365 Users, Approvals)
3. **Convert `.fx.yaml` → Studio YAML** using `convert-to-studio-yaml.py`
4. **Paste into each screen's Code View** (Ctrl+A → Ctrl+V per screen)
5. **Fix formula errors** in a single pass after all screens are pasted
6. **Add navigation panel** and Copilot Studio chatbot manually

### Development Workflow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Create blank │ ──→ │  Convert     │ ──→ │  Paste into  │ ──→ │  Fix errors  │
│  app + data   │     │  .fx.yaml    │     │  Code View   │     │  + publish   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
  Studio: new app      convert-to-          Studio: Ctrl+A       Studio: App
  + add connectors     studio-yaml.py       Ctrl+V per screen    Checker → 0
```

### Helper Scripts

| Script | Purpose |
|--------|---------|
| `convert-to-studio-yaml.py` | Converts all `.fx.yaml` files to Studio Code View YAML format. Handles control type mapping, strips unsupported properties (`BorderRadius`, `PaddingLeft`), fixes invalid enum values (`FontWeight.Light`, `Icon.Group`). Output: `build/studio-yaml/*.yaml` |
| `paste-screens.py` | Interactive helper — copies each screen's YAML to clipboard one at a time, with step-by-step Studio instructions |
| `00-bootstrap-app.ps1` | *(Legacy)* Creates a shell app via PAC CLI — no longer the primary workflow |
| `01-deploy-canvas-app.ps1` | Exports app as solution, imports to target environment, shares with Entra groups |
| `02-validate-canvas-app.ps1` | Post-deployment validation (solution, connections, sharing, SPO connectivity) |
| `03-test-e2e-canvas-app.ps1` | End-to-end document lifecycle test |

### Source Files (`.fx.yaml`)

| File | Screen | Role |
|------|--------|------|
| `App.fx.yaml` | App.OnStart | Role detection, global variables |
| `scrDashboard.fx.yaml` | Dashboard (Home) | All personas — metrics, meetings, actions |
| `scrDocBrowser.fx.yaml` | Document Browser | Role-filtered galleries, filters, sorting |
| `scrDocUpload.fx.yaml` | Document Upload | Authors — metadata form, validation |
| `scrDocDetail.fx.yaml` | Document Detail | Lifecycle actions (submit/approve/archive) |
| `scrApprovals.fx.yaml` | Approvals Centre | Reviewers — inline approve/reject |
| `scrAIAssistant.fx.yaml` | AI Assistant | Executives — Copilot Studio chat |
| `scrArchiveMgmt.fx.yaml` | Archive Management | Compliance — bulk archive |
| `scrNoAccess.fx.yaml` | Access Denied | Fallback for unauthorized users |
| `cmpNavPanel.fx.yaml` | Navigation Panel | Component — role-based nav |
| `CanvasManifest.json` | App manifest | Screen order, data sources, connections |

### Key Limitation

A Canvas App **cannot be reliably created** by manually editing `.msapp` binary files. The `.msapp` format is undocumented, and controls like TextInput, DatePicker, and AttachmentControl crash Studio import in multi-screen apps. The `.fx.yaml` files serve as **design blueprints** that are converted to Studio-compatible YAML for pasting via Code View.

### Studio Code View Compatibility Notes

The converter (`convert-to-studio-yaml.py`) handles these known incompatibilities:

| PAC CLI / Design | Studio Code View | Notes |
|-----------------|-----------------|-------|
| `BorderRadius` property | *(not supported)* | Stripped by converter |
| `PaddingLeft` property | *(not supported)* | Stripped by converter |
| `FontWeight.Light` | `FontWeight.Normal` | `.Light` not a valid enum |
| `Icon.Group` | `Icon.Person` | `.Group` not recognised |
| `Icon.Calendar` | `Icon.Clock` | `.Calendar` not recognised |
| `Transparent` | `Color.Transparent` | Must use `Color.` prefix |
| `As Type:` syntax | `Control: Type@Version` | Different YAML schema |
| `>` in text strings | Causes YAML parse errors | Must avoid or quote |

---

> **Legacy reference**: The original Power Fx source files (manual copy-paste format) are archived in `docs/implementation/ws7-powerfx/`. The `.fx.yaml` files in `scripts/ws7-powerapp/src/` supersede them.

---

## Prerequisites

Before starting, confirm:

- [ ] WS-1 through WS-6 are deployed and validated on the dev tenant
- [ ] You have Power Apps Maker access in the default Power Platform environment
- [ ] You have the Entra ID Object IDs for all 5 security groups (from `scripts/config.ps1`)
- [ ] You have the ExecWS-ApprovedToArchive flow GUID
- [ ] The Copilot Studio agent `ExecWorkspace-Copilot` is deployed

---

## Phase 1: Create the App and Solution

### Step 1.1: Create a Power Platform Solution

1. Go to https://make.powerapps.com
2. Select the correct environment (dev tenant default environment)
3. Navigate to **Solutions** → **+ New solution**
4. Name: `ExecWorkspaceSolution`
5. Publisher: Select or create your org publisher
6. Save

### Step 1.2: Add Environment Variables

Inside the solution, add each environment variable:

1. **+ New** → **More** → **Environment variable**
2. Create each variable from the table below:

| Display Name | Schema Name | Type | Value |
|-------------|-------------|------|-------|
| SharePoint Site URL | `env_SharePointSiteUrl` | Text | `https://<dev-tenant>.sharepoint.com/sites/exec-workspace` |
| Draft Library | `env_DraftLibrary` | Text | `Draft` |
| Review Library | `env_ReviewLibrary` | Text | `Review` |
| Approved Library | `env_ApprovedLibrary` | Text | `Approved` |
| Archive Library | `env_ArchiveLibrary` | Text | `Archive` |
| Archive Flow ID | `env_ArchiveFlowId` | Text | `<flow-guid>` |
| Authors Group ID | `env_AuthorsGroupId` | Text | `<group-object-id>` |
| Reviewers Group ID | `env_ReviewersGroupId` | Text | `<group-object-id>` |
| Executives Group ID | `env_ExecutivesGroupId` | Text | `<group-object-id>` |
| Compliance Group ID | `env_ComplianceGroupId` | Text | `<group-object-id>` |
| Admins Group ID | `env_AdminsGroupId` | Text | `<group-object-id>` |
| Copilot Bot Schema | `env_CopilotBotSchemaName` | Text | `<bot-schema-name>` |

### Step 1.3: Create the Canvas App

1. Inside the solution, **+ New** → **App** → **Canvas app**
2. Name: `ExecWorkspace`
3. Format: **Tablet**
4. Click **Create**
5. Power Apps Studio opens

---

## Phase 2: Configure Data Sources

In Power Apps Studio:

1. **Data** panel (left sidebar) → **+ Add data**
2. Add **SharePoint** connector:
   - Enter site URL: `https://<dev-tenant>.sharepoint.com/sites/exec-workspace`
   - Select lists: `Draft`, `Review`, `Approved`, `Archive`
3. Add **Office 365 Users** connector
4. Add **Approvals** connector
5. Add **Power Automate** → connect the `ExecWS-ApprovedToArchive` flow and the `ExecWS-CheckUserRoles` flow

---

## Phase 3: Deploy the Helper Flow

Before building the app, deploy the role detection helper flow:

1. Go to https://make.powerautomate.com
2. **+ Create** → **Instant cloud flow**
3. Name: `ExecWS-CheckUserRoles`
4. Trigger: **PowerApps (V2)**
5. Build the flow matching `scripts/ws7-powerapp/flow-definitions/ExecWS-CheckUserRoles.json`
6. Or import the JSON directly via REST API (see `scripts/ws5-flows/01-deploy-flows.ps1` for the pattern)
7. Test with your own user ID to confirm it returns correct roles

---

## Phase 4: Build App.OnStart

1. In Power Apps Studio, click on **App** in the Tree view
2. Select the **OnStart** property
3. Paste the formula from `docs/implementation/ws7-powerfx/App.OnStart.fx`
4. Adapt for your environment:
   - Use Option B (helper flow) for production-ready role detection
   - Replace connector names with actual names from your Data panel
5. Test by clicking **Run OnStart** in the toolbar

---

## Phase 5: Build Component Library

### cmpNavPanel

1. **Components** tab → **+ New component**
2. Name: `cmpNavPanel`
3. Set properties:
   - Width: 220
   - Height: `App.Height`
   - Fill: `RGBA(0, 69, 120, 1)`
4. Add custom input property: `ActiveScreen` (Text)
5. Build the nav items per `docs/implementation/ws7-powerfx/cmpNavPanel_and_scrNoAccess.fx`
6. Add each nav button with conditional visibility based on role flags

### cmpLifecycleBadge

1. **+ New component** → `cmpLifecycleBadge`
2. Custom input property: `LifecycleState` (Text)
3. Add a rounded rectangle and label
4. Use the `Switch()` formula for colours from the design spec

---

## Phase 6: Build Screens (Studio Code View Paste)

### Prerequisites
- Blank Canvas App created with all data sources connected
- `convert-to-studio-yaml.py` has been run (output in `build/studio-yaml/`)

### Workflow per screen

1. In Studio: **Insert → New screen → Blank**
2. **Rename** the screen (right-click → Rename)
3. With the screen selected, open **Code View** (`</>` icon)
4. **Select all** (Ctrl+A) → **Paste** (Ctrl+V) the converted YAML
5. Verify controls appear in the tree view
6. Move to the next screen

Alternatively, run `paste-screens.py` for an interactive guided experience.

### Build order (simple → complex)

| Order | Screen | Controls | Notes |
|-------|--------|----------|-------|
| 1 | scrNoAccess | 6 | Static — no data refs, validates workflow |
| 2 | scrDashboard | 27 | Metrics cards, meetings gallery, quick actions |
| 3 | scrDocBrowser | 13 | Tabs, filter dropdowns, document gallery |
| 4 | scrDocUpload | 23 | File attachment, metadata form, validation |
| 5 | scrDocDetail | 27 | Metadata display, lifecycle action buttons |
| 6 | scrApprovals | 12 | Pending/History tabs, inline approve/reject |
| 7 | scrAIAssistant | 11 | Prompt buttons, chatbot placeholder |
| 8 | scrArchiveMgmt | 21 | Bulk archive with confirmation dialog |

### Post-paste error categories (expected)

| Error | Cause | Resolution |
|-------|-------|------------|
| Navigate to missing screens | Screens pasted in order | Self-resolves as screens are added |
| `{Name}` / `{Link}` syntax | SharePoint field references | Replace with actual column names |
| `│` in Concatenate | Unicode pipe character | Replace with `" \| "` or similar |
| `ExecWSApprovedToArchive.Run()` | Flow not connected | Connect Power Automate flow as data source |
| `ApprovalConnector` methods | Connector schema mismatch | Verify actual Approvals connector method names |
| Delegation warnings | Large list queries | Expected — not blocking |

---

## Phase 7: Apply Theme

In Power Apps Studio:

1. **Settings** → **Display** → set app dimensions to 1366×768
2. **Settings** → **Display** → enable **Scale to fit**
3. Apply the colour tokens from `docs/06-ws7-app-design.md` §3
4. Set default font to **Segoe UI** in app settings

---

## Phase 8: Test

### Per-Persona Testing

| Test | User | Steps | Expected Result |
|------|------|-------|----------------|
| T-1 | Author | Launch → Upload → Fill metadata → Submit | Doc in Draft with metadata |
| T-2 | Author | Open Draft doc → Submit for Review | LifecycleState → "Review", flow fires |
| T-3 | Reviewer | Launch → Approvals → Approve | Doc moves to Approved |
| T-4 | Reviewer | Approvals → Reject with comments | Doc returns to Draft |
| T-5 | Executive | Launch → Documents → Browse Approved | Only Approved docs visible |
| T-6 | Executive | AI Assistant → Ask question | Response from approved content |
| T-7 | Compliance | Archive Mgmt → Select → Archive | Flow triggers, doc moves |
| T-8 | No groups | Launch app | scrNoAccess shown |

### Run E2E Validation

After manual testing, run: `scripts/ws7-powerapp/03-test-e2e-canvas-app.ps1`

---

## Phase 9: Publish and Share

1. In Power Apps Studio: **File** → **Save** → **Publish**
2. **Share** the app with the five Entra ID security groups:
   - ExecWorkspace-Authors (Can use)
   - ExecWorkspace-Reviewers (Can use)
   - ExecWorkspace-Executives (Can use)
   - ExecWorkspace-Compliance (Can use)
   - ExecWorkspace-PlatformAdmins (Co-owner)
3. Users can access the app at https://apps.powerapps.com

---

## Phase 10: Export for Version Control

1. In Power Apps Studio: **File** → **Save as** → **This computer** → save `.msapp`
2. Place in `scripts/ws7-powerapp/solution/ExecWorkspace.msapp`
3. Export the solution: **Solutions** → `ExecWorkspaceSolution` → **Export** → **Managed**
4. Save as `scripts/ws7-powerapp/solution/ExecWorkspaceSolution.zip`
5. Commit both files to the repository

---

## File Reference

| File | Purpose |
|------|---------|
| `docs/implementation/ws7-powerfx/App.OnStart.fx` | Role detection and initialisation formulas |
| `docs/implementation/ws7-powerfx/scrDashboard.fx` | Dashboard screen formulas |
| `docs/implementation/ws7-powerfx/scrDocBrowser.fx` | Document browser formulas |
| `docs/implementation/ws7-powerfx/scrDocUpload.fx` | Upload screen formulas |
| `docs/implementation/ws7-powerfx/scrDocDetail.fx` | Document detail formulas |
| `docs/implementation/ws7-powerfx/scrApprovals.fx` | Approvals centre formulas |
| `docs/implementation/ws7-powerfx/scrAIAssistant.fx` | AI assistant screen formulas |
| `docs/implementation/ws7-powerfx/scrArchiveMgmt.fx` | Archive management formulas |
| `docs/implementation/ws7-powerfx/cmpNavPanel_and_scrNoAccess.fx` | Nav component + fallback screen |
| `scripts/ws7-powerapp/flow-definitions/ExecWS-CheckUserRoles.json` | Role detection helper flow |
| `docs/06-ws7-app-design.md` | Visual design spec (wireframes, colours, components) |
| `docs/05-ws7-lld.md` | Detailed technical design |

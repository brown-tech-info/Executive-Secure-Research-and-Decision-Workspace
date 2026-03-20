# Executive Secure Research & Decision Workspace
## Board-App-MVP

---

## Overview

This repository contains the architecture, design artefacts, and **fully code-driven deployment scripts** for an Executive Secure Research & Decision Workspace built entirely on native Microsoft 365 services.

The solution is designed to support highly confidential research governance, executive review, and decision-making workflows, delivering outcomes comparable to specialist board portal solutions while remaining fully contained within the Microsoft 365 tenant.

**Everything is deployed via code.** There are no manual portal steps. All configuration is implemented through PowerShell, Microsoft Graph API, Security & Compliance PowerShell, and the Power Platform REST API — making deployments reproducible, auditable, and version-controlled.

---

## Objectives

- Provide a secure, executive-grade digital workspace for sensitive research material
- Enforce clear document lifecycle governance: **Draft → Review → Approved → Archive**
- Eliminate informal data distribution and uncontrolled sharing
- Ensure full auditability, compliance, and retention
- Enable scoped, tenant-contained AI assistance over approved content only
- Demonstrate how Microsoft 365 native services can deliver board-grade governance without third-party tools

---

## Architectural Principles

| Principle | Implementation |
|---|---|
| **Microsoft 365 native only** | SharePoint, Power Automate, Entra ID, Purview, Copilot Studio |
| **Identity is the security boundary** | All access routed through Microsoft Entra ID security groups |
| **Least privilege by default** | Per-library permissions, PIM for elevated roles |
| **Configuration over custom code** | PnP PowerShell, Graph API, IPPS — no custom code in production |
| **Auditability by design** | Purview Unified Audit Log, DLP incident reports, PIM audit history |
| **AI is scoped, read-only, and tenant-contained** | Copilot Studio agent limited to Approved library, no write access |

---

## Prerequisites

### Licensing

- Microsoft 365 E5 (or E3 + appropriate add-ons) in the dev tenant
- Required for: Purview, PIM, Sensitivity Labels, Conditional Access, Copilot Studio

### PowerShell Modules

```powershell
# Required PowerShell version: 7.0+
# Install all required modules:

Install-Module Microsoft.Graph          -Scope CurrentUser -Force  # Entra ID, CA, PIM, Graph
Install-Module PnP.PowerShell           -Scope CurrentUser -Force  # SharePoint provisioning
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force  # Sensitivity labels, DLP, Purview
Install-Module Az.Accounts              -Scope CurrentUser -Force  # Power Platform auth (flows, Copilot)
```

### Required Roles (per workstream)

| Workstream | Minimum Role Required |
|---|---|
| WS-1: Entra ID groups | Groups Administrator |
| WS-1: Conditional Access | Conditional Access Administrator |
| WS-1: PIM | Privileged Role Administrator |
| WS-2: SharePoint | SharePoint Administrator |
| WS-3: Sensitivity Labels | Compliance Administrator |
| WS-3: DLP Policies | Compliance Administrator |
| WS-4: Purview audit & retention | Compliance Administrator |
| WS-4: eDiscovery | eDiscovery Manager |
| WS-5: Power Automate flows | Power Platform Administrator |
| WS-6: Copilot Studio agent | Power Platform Administrator |

### Tenant Configuration

Replace the placeholder `<dev-tenant>` in all scripts with your actual tenant name (e.g. `contoso` from `contoso.onmicrosoft.com`).

---

## Deployment Sequence

Scripts must be run in workstream order. Each workstream has a validation checkpoint that must pass before the next begins.

```
WS-1: Entra ID & Identity
  ├── 01-create-security-groups.ps1
  ├── 02-validate-entra-groups.ps1       ← validation checkpoint
  ├── 03-create-conditional-access.ps1
  └── 04-configure-pim.ps1

WS-2: SharePoint Provisioning
  ├── 01-provision-site.ps1
  ├── 02-create-libraries.ps1
  ├── 03-configure-permissions.ps1
  ├── 04-add-metadata-columns.ps1
  ├── 05-configure-settings.ps1
  ├── 06-validate-spo.ps1               ← validation checkpoint
  ├── 07-create-meeting-views.ps1       ← meeting cadence views (Approved library)

WS-3: Information Protection
  ├── 00-enable-aip-integration.ps1
  ├── 01-create-sensitivity-labels.ps1
  ├── 02-apply-sensitivity-labels.ps1
  ├── 03-validate-mip.ps1               ← validation checkpoint
  └── 04-create-dlp-policies.ps1

WS-4: Purview Audit & Retention
  ├── 01-configure-audit.ps1
  ├── 02-configure-retention.ps1
  ├── 03-validate-purview.ps1           ← validation checkpoint
  └── 04-configure-ediscovery.ps1

WS-5: Power Automate Lifecycle Flows
  ├── flow-definitions/
  │     ExecWS-DraftToReview.json
  │     ExecWS-ReviewToApproved.json
  │     ExecWS-ApprovedToArchive.json
  │     ExecWS-MeetingPackOpen.json
  ├── 01-deploy-flows.ps1
  ├── 02-enable-flows.ps1
  └── 03-test-e2e-meetingpackopen.ps1   ← E2E test: calendar event → Draft placeholder → metadata → notification

WS-6: Copilot Studio Agent
  ├── agent-definition/
  │     ExecWorkspace-Copilot.yaml
  ├── 01-validate-copilot.ps1           ← pre-flight checks
  └── 02-deploy-copilot-agent.ps1

WS-7: Power Apps Canvas App
  ├── solution/
  │     ExecWorkspaceSolution/          ← managed solution package
  ├── 01-deploy-canvas-app.ps1          ← solution import, env vars, sharing
  └── 02-validate-canvas-app.ps1        ← post-deployment validation
```

> **See `scripts/README.md`** for full script reference, parameter documentation, and module requirements.

---

## Repository Structure

```
.github/
  constitution.md              Immutable architectural and governance principles
  copilot-instructions.md      Behavioural guardrails for GitHub Copilot and Copilot CLI

docs/
  01-requirements.md           Functional and non-functional requirements
  02-hld.md                    High-Level Design: architecture and service composition
  03-lld.md                    Low-Level Design: concrete configuration and enforcement
  04-ws7-requirements.md       WS-7 Power Apps Canvas App requirements
  05-ws7-lld.md                WS-7 Canvas App low-level design (screens, connectors, formulas)
  06-ws7-app-design.md         WS-7 Canvas App design specification (wireframes, theme, components)
  deployment-guide.md          Step-by-step deployment guide for all phases
  ws6-copilot-studio-spec.md   Supplementary reference for the Copilot Studio agent design

scripts/
  README.md                    Full script reference, prerequisites, and running order
  ws1-entra/                   Entra ID groups, Conditional Access, PIM
  ws2-sharepoint/              SharePoint site, libraries, permissions, metadata
  ws3-mip/                     Sensitivity labels, label application, DLP policies
  ws4-purview/                 Audit log, retention labels, eDiscovery
  ws5-flows/                   Power Automate flow definitions and deployment
  ws6-copilot/                 Copilot Studio agent definition and deployment
  ws7-powerapp/                Power Apps Canvas App solution and deployment

readme.md                      This document
```

---

## How to Use This Repository

### First time

1. **Read `.github/constitution.md`** — understand the immutable guardrails before writing any code or configuration
2. **Review `docs/01-requirements.md`** — understand what the solution must deliver
3. **Review `docs/02-hld.md` and `docs/03-lld.md`** — understand the architecture
4. **Read `scripts/README.md`** — prerequisites, module installation, and deployment guide
5. **Deploy** — run scripts in workstream order, validating each before proceeding

### Using GitHub Copilot or Copilot CLI

All AI-assisted work must align with `.github/copilot-instructions.md`. Key constraints:
- Microsoft 365 native services only — no third-party SaaS
- Architecture must not be violated — check `docs/` before implementing
- All suggestions must be idempotent and auditable

---

## Scope

**In scope:**
- Secure executive workspace built on M365 native services
- Document lifecycle governance (Draft → Review → Approved → Archive)
- Identity-based access control via Entra ID
- Audit, compliance, and retention via Microsoft Purview
- Scoped AI assistance via Copilot Studio (Approved content only)

**Out of scope:**
- Third-party board portal SaaS platforms
- Cross-tenant data sharing
- Consumer-grade AI services
- Informal collaboration tooling

---

## Status

### Dev Tenant Deployment — <dev-tenant>

| Workstream | Status |
|---|---|
| Architecture and design artefacts | ✅ Complete |
| WS-1: Entra ID identity foundation | ✅ Deployed and validated |
| WS-2: SharePoint provisioning | ✅ Deployed and validated |
| WS-3: Information protection (MIP + DLP) | ✅ Deployed and validated — 9/9 sensitivity labels applied across all 4 libraries |
| WS-4: Purview audit, retention, eDiscovery | ✅ Deployed and validated |
| WS-5: Power Automate lifecycle flows | ✅ Deployed and live — all 4 flows active, E2E test 9/9 PASS |
| WS-6: Copilot Studio agent | ✅ Deployed — agent live, knowledge source connected, web search OFF, Entra ID auth enforced |
| WS-7: Power Apps Canvas App | 📐 Design complete — requirements, LLD, app design spec ready; implementation pending |
| Production promotion | ⏳ Pending dev validation sign-off |

---

## Guiding Principle

This project is not about recreating a product.
It is about demonstrating how Microsoft 365, when used deliberately and correctly, can deliver board-grade governance, security, and insight — without introducing unnecessary complexity, risk, or third-party dependencies.

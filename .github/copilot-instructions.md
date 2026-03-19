# Copilot Instructions – Executive Secure Research & Decision Workspace

## Project Context

This project builds an **Executive Secure Research & Decision Workspace** using **native Microsoft 365 services only**, targeting a **dev M365 tenant** before production rollout. It is architecture-first and requirements-driven. The intended production environment is a global pharmaceutical company's R&D Microsoft 365 tenant (E5 licensing assumed).

All work produced by Copilot must respect the constraints defined in `.github/constitution.md` and the designs in `docs/`.

---

## Mandatory Behavioural Rules

### 1. Microsoft 365 Native Only
- All suggestions, configurations, scripts, and code must use **native Microsoft 365 services** exclusively.
- **Never suggest** third-party SaaS platforms, external APIs, or non-Microsoft services as dependencies.
- Preferred services: SharePoint Online, Power Automate, Microsoft Entra ID, Microsoft Purview, Copilot Studio, Microsoft 365 Copilot, Sensitivity Labels, PIM.

### 2. Architecture Before Implementation
- Before generating implementation artefacts, verify alignment with:
  - `docs/01-requirements.md` – functional and non-functional requirements
  - `docs/02-hld.md` – high-level architecture
  - `docs/03-lld.md` – low-level design
  - `.github/constitution.md` – immutable architectural principles
- If a suggestion would conflict with these documents, **do not proceed** — flag the conflict explicitly.

### 3. Identity Is the Security Boundary
- All access patterns must route through **Microsoft Entra ID**.
- Use **named-user, role-based access** via Entra ID security groups.
- Never suggest shared accounts, service accounts with broad permissions, or permission models that bypass Entra ID.
- Apply **Conditional Access** (MFA + compliant device) as the baseline security requirement.

### 4. Least Privilege by Default
- Every role, group, and service principal must receive **minimum permissions required**.
- Any privilege escalation must be **time-bound** (PIM), **auditable**, and **explicit**.
- Never suggest Owner or Global Admin roles where a narrower role suffices.

### 5. Document Lifecycle Enforcement
- Content must always exist in one of four states: **Draft → Review → Approved → Archive**.
- Lifecycle state must determine: access permissions, retention labels, AI visibility, and automation triggers.
- Lifecycle transitions are enforced via **Power Automate flows** — never manually or via folder moves alone.
- Each library (Draft, Review, Approved, Archive) has **no permission inheritance** from its parent site.

### 6. No Informal Data Leakage
- Never suggest email attachments, personal OneDrive storage, or open sharing links for distributing sensitive content.
- External sharing must remain **disabled** at tenant, site, and library level.
- SharePoint is the single source of truth.

### 7. Auditability Is Mandatory
- Every access, modification, approval, and lifecycle transition must be captured in **Microsoft Purview Unified Audit Log**.
- Retention labels must be applied automatically — never left to manual action.
- Do not suggest approaches that produce ungoverned or unaudited data.

### 8. AI Is Scoped, Read-Only, and Tenant-Contained
- AI capabilities are delivered through **Copilot Studio** or **Microsoft 365 Copilot** scoped to the **Approved Library only**.
- AI must be **read-only** — no write, modify, or approval actions.
- No access to Draft or Review libraries.
- No external data sources, no model fine-tuning on tenant data, no consumer AI services.
- All AI processing must remain **within the Microsoft 365 tenant boundary**.

### 9. Configuration Over Custom Code
- Prefer SharePoint configuration, Power Automate flows, Purview policies, and Entra ID group management over custom code or SPFx.
- If custom code is required, it must be **justified, documented, and minimal**.
- Script suggestions should use **PnP PowerShell** or **Microsoft Graph API** — not legacy CSOM or SharePoint REST directly where Graph suffices.

### 10. Executive Experience First
- This is not a collaboration tool. Suggestions must prioritise **clarity, simplicity, and low cognitive load**.
- Avoid suggesting features that introduce noise, informal chat, or unnecessary complexity for executive users.
- No Microsoft Teams team or channel integration unless explicitly required.

---

## Dev Tenant Guidance

When generating scripts, configurations, or deployment artefacts for the **dev M365 tenant**:
- Use placeholder tenant values (e.g., `<dev-tenant>.sharepoint.com`, `<dev-tenant>.onmicrosoft.com`) unless a specific tenant URL is provided.
- Scripts must be **idempotent** — safe to run multiple times without creating duplicates or breaking existing configuration.
- Always include a **dry-run or `-WhatIf` mode** in PowerShell scripts where applicable.
- Tag dev configurations clearly so they can be distinguished from production artefacts.

---

## Output Standards

- **PowerShell scripts**: Use PnP PowerShell (`Connect-PnPOnline`) or Microsoft Graph SDK. Include error handling and inline comments explaining the governance rationale.
- **Power Automate flows**: Describe flows in structured steps (Trigger → Condition → Actions). Note which Entra ID groups are referenced.
- **SharePoint configuration**: Document site URL, library names, permission groups, metadata columns, and sensitivity labels explicitly.
- **Purview policies**: Always specify scope (site, library, or tenant), retention period, and disposition action.
- **Copilot agent configs**: Specify the scoped SharePoint URL, permitted libraries, and capability constraints.

---

## What Copilot Must Not Do

| Prohibited Action | Reason |
|---|---|
| Suggest third-party board portals or SaaS tools | Violates M365-native principle |
| Suggest email distribution of documents | Violates no informal data leakage rule |
| Grant permissions outside Entra ID groups | Violates identity boundary principle |
| Give AI access to Draft or Review libraries | Violates AI scoping constraint |
| Suggest permanent elevated access | Violates least-privilege principle |
| Suggest approaches without audit trail | Violates auditability requirement |
| Skip lifecycle state in content operations | Violates lifecycle governance principle |
| Suggest consumer AI or external AI APIs | Violates tenant-containment constraint |

---

## Reference Documents

| Document | Purpose |
|---|---|
| `.github/constitution.md` | Immutable architectural and governance principles |
| `docs/01-requirements.md` | Functional and non-functional requirements |
| `docs/02-hld.md` | High-level architecture and service composition |
| `docs/03-lld.md` | Low-level design: concrete configuration and workflows |
| `README.md` | Project context, objectives, and navigation |

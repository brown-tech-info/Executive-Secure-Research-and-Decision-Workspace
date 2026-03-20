# Executive Secure Research & Decision Workspace
## WS-7: Power Apps Canvas App — Requirements Document (v0.1)

---

## 1. Purpose

This document defines the functional and non-functional requirements for a **Power Apps Canvas App** that provides the executive-grade user interface for the Executive Secure Research & Decision Workspace.

The Canvas App is a pure presentation layer over the existing Microsoft 365 backbone deployed in WS-1 through WS-6. It does not introduce new data stores, modify lifecycle logic, or bypass any governance controls. All data remains in SharePoint, all automation remains in Power Automate, and all identity enforcement remains in Microsoft Entra ID.

The app addresses the gap identified in NFR-3 (Usability) of `01-requirements.md`: providing an executive-friendly experience that requires minimal training and delivers clarity, simplicity, and low cognitive load — replacing raw SharePoint library navigation.

---

## 2. Scope

**In Scope**

- Role-based Canvas App for all workspace personas
- Document upload with metadata pre-population
- Document browsing with lifecycle-state and meeting-cadence filtering
- Inline approval and rejection via the Approvals connector
- Compliance archival trigger from within the app
- Embedded Copilot Studio AI assistant
- Executive dashboard with key metrics and meeting pack status
- Desktop and tablet form factors

**Out of Scope**

- Model-Driven Apps or Dataverse data storage
- Mobile phone form factor
- Microsoft Teams embedding or distribution
- Offline document access
- Custom SPFx web parts
- New Power Automate flows (existing flows are reused)
- Changes to the SharePoint site, library, or permission model

---

## 3. Personas

The Canvas App serves all five workspace personas defined in `01-requirements.md`. Each persona sees a role-appropriate experience within a single app.

| Persona | Entra ID Group | Primary App Experience |
|---------|---------------|----------------------|
| **Content Authors** | ExecWorkspace-Authors | Upload documents to Draft, submit for review, track document progress |
| **Reviewers / Approvers** | ExecWorkspace-Reviewers | Review documents, approve or reject inline, view approval history |
| **Executive Stakeholders** | ExecWorkspace-Executives | Browse approved packs, view dashboard, query AI assistant |
| **Compliance / Legal** | ExecWorkspace-Compliance | Browse approved and archived content, trigger archival, view retention status |
| **Platform Administrators** | ExecWorkspace-PlatformAdmins | All capabilities (for troubleshooting only — not a primary user) |

Role detection is performed at app launch by resolving the signed-in user's Entra ID group memberships.

---

## 4. Functional Requirements

### FR-UI-1: Role-Based Experience

- The app must detect the signed-in user's Entra ID security group membership on launch
- The app must present screens, navigation items, and action buttons appropriate to the user's role(s)
- Users with no recognised group membership must see a read-only fallback screen with instructions to contact their administrator
- Users belonging to multiple groups must receive the union of all applicable capabilities
- Role detection must use delegated identity — the app must never hard-code user lists or bypass Entra ID

### FR-UI-2: Executive Dashboard

The home screen must provide an at-a-glance overview of workspace activity:

| Component | Data Source | Visible To |
|-----------|------------|-----------|
| Document counts by lifecycle state (Draft, Review, Approved, Archive) | SharePoint library item counts | All roles |
| Upcoming meeting packs (next 5 meetings with open or approved packs) | Approved + Draft library metadata (`ExecWS_MeetingDate`) | All roles |
| Recent approvals feed (last 10 approval outcomes) | Approvals connector history | Reviewers, Executives |
| Current meeting cycle packs (this month's Board, SteerCo, ExecTeam) | Approved library filtered by `ExecWS_MeetingCycle` | All roles |
| Quick-action: "New Document" | Navigation to Upload screen | Authors only |
| Quick-action: "Pending Reviews" | Navigation to Approvals Centre | Reviewers only |
| Quick-action: "Archive Documents" | Navigation to Archive Management | Compliance only |

### FR-UI-3: Document Browser

- Display documents from SharePoint libraries filtered by the user's role and permissions:
  - Authors: Draft (edit) and Review (read-only)
  - Reviewers: Review (edit) and Draft (read-only)
  - Executives: Approved (read-only)
  - Compliance: Approved (read-only) and Archive (read-only)
- Provide filter controls for: Meeting Type, Meeting Cycle, Document Type, Date Range
- Provide sort controls for: Meeting Date (descending, default), Modified Date, Document Name
- Support grouping by `ExecWS_MeetingCycle` to replicate the "By Meeting" view
- Tapping a document must navigate to the Document Detail screen
- Gallery must display: document name, document type, meeting type, meeting date, lifecycle state badge, document owner

### FR-UI-4: Document Upload

- Authors must be able to upload files directly to the Draft library from the app
- The upload form must collect the following metadata:
  - **Document Type** — choice dropdown (Board Pack, Research Summary, Decision Record, Meeting Minutes, Supporting Material)
  - **Meeting Type** — choice dropdown (Board, SteerCo, ExecTeam, Ad-Hoc)
  - **Meeting Date** — date picker
  - **Meeting / Decision ID** — auto-derived from Meeting Type + Date using the convention `[MeetingType]-[YYYY-MM]-[NNN]`
  - **Meeting Cycle** — auto-derived from Meeting Type + Year + Month (e.g. `BOARD-2026-03`)
  - **Sensitivity Classification** — choice dropdown (Confidential – Executive, Highly Confidential – Board)
  - **Document Owner** — auto-set to the signed-in user
  - **Lifecycle State** — auto-set to "Draft" (not user-editable)
  - **Pack Version** — defaults to 1, editable for revisions
- The app must validate that all required fields are completed before allowing upload
- The app must auto-generate a filename following the convention: `[MeetingType]-[YYYY-MM]-[DocumentType]-[ShortTitle]` where ShortTitle is provided by the user
- Upload must only be visible and accessible to users in the ExecWorkspace-Authors group
- The upload target must always be the Draft library — the app must never write directly to Review, Approved, or Archive

### FR-UI-5: Document Detail View

- Display full metadata for a selected document including all mandatory and meeting-cadence fields
- Display version history retrieved from SharePoint
- Display a lifecycle state badge with visual differentiation:
  - Draft = Blue
  - Review = Amber
  - Approved = Green
  - Archive = Grey
- Provide role-based actions:
  - **Author viewing a Draft document**: "Submit for Review" button — sets `ExecWS_LifecycleState` to "Review" (triggering the DraftToReview flow)
  - **Reviewer viewing a Review document**: "Approve" and "Reject" buttons — actions routed through the Approvals connector to maintain audit trail
  - **Compliance viewing an Approved document**: "Archive" button — triggers the ExecWS-ApprovedToArchive Power Automate flow
- Provide an "Open in SharePoint" link for full-fidelity document viewing
- Actions must be hidden (not merely disabled) for users without the appropriate role

### FR-UI-6: Approvals Centre

- Display a list of pending approval tasks assigned to the signed-in user (via the Approvals connector)
- Each pending item must show: document name, submitter, submission date, meeting pack context (Meeting Type, Meeting Cycle)
- Reviewers must be able to approve or reject directly within the app, with a mandatory comments field for rejections
- Approvals and rejections must route through the Approvals connector — the app must never modify document metadata or move files directly
- Provide a history tab showing completed approvals with: outcome (approved/rejected), approver name, timestamp, comments
- Provide filters for: Meeting Type, Date Range

### FR-UI-7: AI Assistant

- Embed the Copilot Studio agent (`ExecWorkspace-Copilot`) as an inline chat panel within the app
- Provide pre-configured prompt suggestions:
  - "Summarise the latest Board pack"
  - "What were the key decisions from the last SteerCo?"
  - "Compare Q1 and Q2 results"
  - "What documents are in the current meeting cycle?"
- The chat panel must support full-screen or side-panel toggle
- The AI assistant must only be accessible to users in the ExecWorkspace-Executives group (or above)
- The app must not attempt to bypass the agent's Approved-library-only scope or read-only constraints
- All AI interactions are logged by Copilot Studio to the Purview Unified Audit Log

### FR-UI-8: Archive Management

- Display documents in the Approved library that are eligible for archival
- Compliance users must be able to select one or more documents and trigger the ExecWS-ApprovedToArchive flow
- Provide an Archive library browser showing: document name, archive date, retention label, retention expiry date, disposition status
- Provide filters for: retention label, archive date, meeting cycle
- Archive actions must only be visible to users in the ExecWorkspace-Compliance group

---

## 5. Non-Functional Requirements

### NFR-UI-1: Security

- The app must use delegated authentication — the signed-in user's Entra ID token determines all access
- The app must inherit all Conditional Access policies (MFA, compliant device) without additional configuration
- The app must never store credentials, tokens, or sensitive data in local app variables beyond the current session
- The app must never expose actions that the user's SharePoint permissions do not allow (server-side enforcement as backstop)
- All connectors must use standard delegated connections — no service account connections

### NFR-UI-2: Compliance and Auditability

- All document operations (read, write, upload, metadata update) are audited by SharePoint's Unified Audit Log
- All approval actions are audited by the Approvals connector and Power Automate flow run history
- All AI queries are audited by Copilot Studio
- The app itself must not introduce any unaudited data paths
- The app must not store or cache document content outside of SharePoint

### NFR-UI-3: Usability

- The app must be optimised for desktop and tablet form factors (minimum 1024×768 resolution)
- Navigation must be intuitive with no more than 2 taps/clicks to reach any primary function
- Lifecycle state must be visually obvious through colour-coded badges and clear labelling
- Loading states must be shown during data retrieval and flow triggers
- Error states must provide clear, actionable messages (not raw API errors)
- The app must follow the organisation's branding guidelines where applicable

### NFR-UI-4: Performance

- Dashboard must load within 5 seconds on a standard corporate network
- Document galleries must support pagination or lazy loading for libraries with 100+ items
- Flow trigger actions must provide immediate visual feedback (spinner/toast) even though the flow executes asynchronously

### NFR-UI-5: Maintainability

- The app must use no premium connectors beyond those required for Copilot Studio embedding
- The app must not depend on Dataverse tables — all data resides in SharePoint
- Connection references must use environment variables for tenant-specific values (site URL, library names)
- The app must be exportable as a `.msapp` package for version control and promotion between environments

### NFR-UI-6: Licensing

- The app must use standard connectors (SharePoint, Office 365 Users, Power Automate, Approvals) included in Microsoft 365 E5
- Copilot Studio embedding may require Power Apps Premium or Copilot Studio licensing — this must be verified during dev tenant testing before production promotion
- No additional per-user licensing should be required beyond existing E5 entitlements where possible

---

## 6. Connectors

| Connector | Type | Purpose |
|-----------|------|---------|
| **SharePoint** | Standard | Read/write document libraries and metadata |
| **Office 365 Users** | Standard | Resolve current user profile and group membership |
| **Power Automate** | Standard | Trigger ExecWS-ApprovedToArchive flow |
| **Approvals** | Standard | Display and action pending approval tasks |
| **Copilot Studio** | Premium* | Embed AI agent as inline chat panel |

*Copilot Studio connector classification and licensing impact must be verified during dev tenant validation.

---

## 7. Assumptions and Constraints

### Assumptions

- WS-1 through WS-6 are fully deployed and validated before WS-7 development begins
- All five Entra ID security groups exist and have correct membership
- All four Power Automate flows are active and functioning correctly
- The Copilot Studio agent is deployed and has its knowledge source connected to the Approved library
- The dev tenant has Microsoft 365 E5 licensing with Power Apps capabilities enabled
- SharePoint metadata column internal names match the `ExecWS_` prefix convention used in deployment scripts

### Constraints

- The app must not introduce any third-party services or external API calls
- The app must not replicate lifecycle transition logic — flows are the single source of truth for state changes
- The app must not write directly to Review, Approved, or Archive libraries — only Draft library writes are permitted
- The app must not create alternate approval pathways — the Approvals connector integrated with Power Automate is the only approval mechanism
- The app must not store document content in Dataverse, local storage, or any location outside SharePoint
- The app distribution is standalone (Power Apps portal) — no Teams or SharePoint embedding in v1

---

## 8. Acceptance Criteria

| ID | Criterion | Validation Method |
|----|-----------|------------------|
| AC-1 | Author can upload a document to Draft with all required metadata from the app | Manual test |
| AC-2 | Author can submit a Draft document for review and the DraftToReview flow fires within 2 minutes | Manual test + flow run history |
| AC-3 | Reviewer can approve a document inline and the ReviewToApproved flow completes successfully | Manual test + flow run history |
| AC-4 | Reviewer can reject a document with comments and the document returns to Draft | Manual test + flow run history |
| AC-5 | Executive can browse approved packs filtered by meeting type | Manual test |
| AC-6 | Executive can query the AI assistant and receive a relevant response from approved content | Manual test |
| AC-7 | Compliance officer can trigger archival of an approved document | Manual test + flow run history |
| AC-8 | User with no group membership sees the fallback screen | Manual test with unassigned test user |
| AC-9 | Dashboard displays correct document counts across all four libraries | Manual test + cross-reference with SharePoint |
| AC-10 | All actions are captured in the Purview Unified Audit Log | Audit log query after test execution |
| AC-11 | App loads and is usable on desktop (1920×1080) and tablet (1024×768) | Manual test on both form factors |
| AC-12 | App is exportable as `.msapp` and re-importable to a clean environment | Export/import test |

---

## 9. Traceability

| WS-7 Requirement | Traces To |
|-------------------|-----------|
| FR-UI-1 (Role-Based Experience) | FR-1 (Secure Workspace), NFR-1 (Security), Constitution §2 (Identity) |
| FR-UI-2 (Dashboard) | FR-4 (Meeting Support), NFR-3 (Usability), Constitution §9 (Executive Experience) |
| FR-UI-3 (Document Browser) | FR-2 (Lifecycle Management), FR-3 (Controlled Distribution) |
| FR-UI-4 (Document Upload) | FR-2 (Lifecycle Management), FR-4 (Meeting Support) |
| FR-UI-5 (Document Detail) | FR-2 (Lifecycle Management), FR-5 (Approval & Sign-off) |
| FR-UI-6 (Approvals Centre) | FR-5 (Approval & Sign-off), NFR-2 (Compliance) |
| FR-UI-7 (AI Assistant) | FR-7 (AI-Assisted Insight), Constitution §7 (AI Scoped) |
| FR-UI-8 (Archive Management) | FR-6 (Audit, Compliance & Retention) |
| NFR-UI-1 (Security) | NFR-1 (Security), Constitution §2 (Identity), §3 (Least Privilege) |
| NFR-UI-2 (Auditability) | NFR-2 (Compliance), Constitution §6 (Auditability) |
| NFR-UI-3 (Usability) | NFR-3 (Usability), Constitution §9 (Executive Experience) |

Executive Secure Research & Decision Workspace
Low‑Level Design (LLD) – v0.1

1. Purpose
This document provides the low‑level technical design for the Executive Secure Research & Decision Workspace implemented within the organisation's Microsoft 365 tenant.
It describes concrete configuration choices, component designs, and enforcement mechanisms required to implement the high‑level architecture and satisfy the documented functional and non‑functional requirements.

2. SharePoint Site Configuration
2.1 Site Type

SharePoint Online Communication Site
Private site collection
No Microsoft Teams team or chat associated
External sharing disabled at site level
Audience targeting enabled

The site is intentionally configured to support focused, executive‑grade consumption rather than open collaboration.

3. Document Library Design
3.1 Libraries
Four separate document libraries are created to represent lifecycle states:
Draft Library

Purpose: Authoring and early content preparation
Access: Content authors only
External sharing: Disabled

Review Library

Purpose: Controlled review and validation
Access: Designated reviewers and approvers
External sharing: Disabled

Approved Library

Purpose: Final, authoritative content and executive packs
Access: Executive stakeholders (read‑only unless explicitly required)
External sharing: Disabled

Archive Library

Purpose: Long‑term record retention
Access: Read‑only for compliance and legal roles

Separate libraries are used rather than folders to enable strict permission boundaries, retention enforcement, and audit clarity. [microsofte...epoint.com]

4. Metadata Model

Each document includes the following mandatory and conditional metadata fields:

**Mandatory fields (all libraries):**

| Field | Type | Values |
|---|---|---|
| Document Type | Choice | Board Pack, Research Summary, Decision Record, Meeting Minutes, Supporting Material |
| Lifecycle State | Choice | Draft, Review, Approved, Archived — managed by Power Automate |
| Sensitivity Classification | Choice | Confidential – Executive, Highly Confidential – Board |
| Document Owner | Person | Single named user |

**Meeting cadence fields (required when document is part of a meeting pack):**

| Field | Type | Format / Values |
|---|---|---|
| Meeting / Decision ID | Text | Pack identifier: `[MeetingType]-[YYYY-MM]-[NNN]` e.g. `BOARD-2026-03-001` |
| Meeting Type | Choice | Board, SteerCo, ExecTeam, Ad-Hoc |
| Meeting Date | Date | Date of the associated meeting |
| Meeting Cycle | Text | Derived label: `BOARD-2026-03`, `STEERCO-2026-W12` — used for grouping and views |
| Pack Version | Number | Integer revision number — incremented when a pack is revised (1, 2, 3…) |

**Naming convention:** Documents in a meeting pack must follow the pattern:
`[MeetingType]-[YYYY-MM]-[DocumentType]-[ShortTitle]`
Example: `BOARD-2026-03-ExecSummary-Q1Results`

Metadata drives automation, auditing, compliance enforcement, and executive navigation views.

5. Identity and Access Configuration
5.1 Identity Groups
Microsoft Entra ID security groups are defined for each role:

| Group | Type | Purpose |
|---|---|---|
| ExecWorkspace-Authors | **Mail-enabled security group** | Draft library Contribute access; receives MeetingPackOpen flow notification emails |
| ExecWorkspace-Reviewers | Security group | Review library Read access; approval workflow participants |
| ExecWorkspace-Executives | Security group | Approved library Read-only access |
| ExecWorkspace-Compliance | Security group | Archive library Read-only; audit and eDiscovery |
| ExecWorkspace-PlatformAdmins | Security group | Platform configuration; no content library access |

> **Important:** `ExecWorkspace-Authors` must be a **mail-enabled security group** (not a plain security group). The `ExecWS-MeetingPackOpen` Power Automate flow sends notification emails to this group's primary SMTP address when a new meeting pack is opened. Microsoft Graph API does not permit creation of mail-enabled security groups; it must be provisioned via Exchange Online (`New-DistributionGroup -Type Security`). See `scripts/ws1-entra/01-create-security-groups.ps1`.

Group membership is tightly controlled and reviewed regularly.
5.2 Access Enforcement

No permission inheritance between libraries
Access granted only through Entra ID groups
Named‑user access only

5.3 Conditional Access
Conditional Access policies enforce:

Multi‑factor authentication
Compliant device access
Optional location‑based restrictions

Optional Privileged Identity Management (PIM) can be used to provide time‑bound access to sensitive roles or libraries.

6. Information Protection

Sensitivity labels applied at document library level
Encryption enforced for all content
Download, copy, and offline access restricted as required
External sharing blocked at tenant, site, and library level

This ensures information protection is enforced consistently and automatically. [microsofte...epoint.com]

7. Workflow and Automation Design
Power Automate is used to implement lifecycle governance and approvals. All three flows are deployed programmatically via the Power Automate REST API and Dataverse — no portal configuration required.
7.1 Draft to Review Flow
Trigger:

Polling trigger (OpenApiConnection type, recurrence every 1 minute) — SharePoint connector operation GetOnUpdatedFileItems on the Draft library, split per item. Fires when ExecWS_LifecycleState metadata is updated to “Review”.

Actions:

Document moved from Draft Library to Review Library
Permissions updated to Reviewer group
Reviewers notified by email (Office 365 Outlook SendEmailV2)


7.2 Review to Approved Flow
Trigger:

Polling trigger (OpenApiConnection type, recurrence every 1 minute) — SharePoint connector operation GetOnUpdatedFileItems on the Review library, split per item. Fires when ExecWS_LifecycleState metadata is updated to “Approved”.

Actions:

Formal approval request raised via Approvals connector (StartAndWaitForAnApproval)
Document version locked
Document moved to Approved Library
Permissions updated to Executive group
Approval metadata recorded
Stakeholders notified by email (Office 365 Outlook SendEmailV2)


7.3 Approved to Archive Flow
Trigger:

Manual button trigger (Request/Button type) — initiated explicitly by a Compliance officer.

Actions:

Document moved to Archive Library
Retention label applied
Content set to read‑only
Compliance team notified by email (Office 365 Outlook SendEmailV2)

These flows directly implement the documented process model. [microsofte...epoint.com]

7.4 Meeting Pack Open Flow
Trigger:

Polling trigger (Office 365 Outlook connector, V3, recurrence every 5 minutes) — fires when an event is created in the designated shared calendar. A condition filters events whose Subject contains one of the recognised meeting type keywords: "Board", "SteerCo", "ExecTeam".

Actions:

Parse meeting type and meeting date from the calendar event subject and start time
Derive meeting cycle identifier (e.g. BOARD-2026-03) from meeting type + year + month
Create a placeholder document in the Draft Library with the following metadata pre-populated:
  - ExecWS_DocumentType: "Board Pack"
  - ExecWS_MeetingType: (parsed from event)
  - ExecWS_MeetingDate: (from event start time)
  - ExecWS_MeetingCycle: (derived)
  - ExecWS_MeetingDecisionId: (derived pack ID)
  - ExecWS_PackVersion: 1
  - ExecWS_LifecycleState: "Draft"
Notify Authors group by email: "A new [MeetingType] pack for [MeetingCycle] is now open. Add documents to the Draft library."

Error handling:

A Handle_Failure scope monitors all three content-creation actions (Create_Pack_Placeholder, Set_Pack_Metadata, Notify_Authors). If any fail, a failure notification email is sent to the Authors group with the calendar event subject and meeting date.

Placeholder file naming convention: `[MeetingType]-[yyyy-MM-dd]-PackPlaceholder.txt` (e.g. `Board-2026-03-19-PackPlaceholder.txt`) created in the Draft library root.

This flow eliminates manual pack creation and ensures meeting metadata is consistently populated from the point of origin.

**End-to-end test:** `scripts/ws5-flows/03-test-e2e-meetingpackopen.ps1` validates the full flow lifecycle — calendar event creation, Draft library polling, all 6 metadata columns, and Notify_Authors execution. Typical trigger latency is ~94 seconds after calendar event creation (within the 5-minute polling window).

**Known SP permission gap:** The `ExecWorkspace-PnP-Admin` service principal lacks `Calendars.ReadWrite` (Application) in Microsoft Graph. The E2E test script falls back to device-code delegated auth for calendar event creation. To eliminate this requirement, grant `Calendars.ReadWrite` (Application) to the SP in the Entra portal and admin-consent it.
8.1 Audit Logging

Microsoft Purview Unified Audit Log enabled
Events captured include:

Access
Modification
Approval
Permission changes



8.2 Retention

Retention labels applied automatically
Retention aligned with the organisation's research governance policies
Records preserved without duplication

8.3 eDiscovery

Content discoverable directly from SharePoint
No export required for standard investigations

 [microsofte...epoint.com]

9. Copilot Agent Design (LLD)
9.1 Scope

Copilot agent scoped to:

Single SharePoint site
Approved Library only



9.2 Capabilities

Summarisation of approved packs
Extraction of key decisions and highlights
Question and answer over approved content

9.3 Constraints

Read‑only permissions
No access to Draft or Review libraries
No external data sources
No training or fine‑tuning on tenant data
Web Search disabled — agent cannot access the internet

9.4 Authentication

The agent requires Microsoft Entra ID authentication:
- Authentication type: Microsoft (Entra ID sign-in)
- Unauthenticated access: Disabled
- All users must sign in before querying the agent
- Access control enforced at the SharePoint permission layer — only ExecWorkspace-Executives members can retrieve Approved content

9.5 Knowledge Source Configuration

The knowledge source is scoped to the SharePoint site using the **site URL** (not a library URL):
- Correct: `https://<tenant>.sharepoint.com/sites/exec-workspace`
- The library path `/Approved` is applied as a filter in the agent configuration
- Library-level URLs (`.../Approved`) are not supported by Copilot Studio and will fail silently during creation

Governance at runtime is enforced by SharePoint's unique permissions on the Approved library — users without ExecWorkspace-Executives membership cannot retrieve content even if they access the agent.

All AI processing remains within the tenant boundary.

9.6 Deployed Agent (Dev Tenant)

| Property | Value |
|---|---|
| Agent name | `ExecWorkspace-Copilot` |
| Bot ID | `<bot-id>` |
| Power Platform Environment | `Default-<tenant-id>` |
| Dataverse | `https://<dataverse-org>.crm.dynamics.com` |
| Model | GPT-4.1 (Default — assigned by Copilot Studio) |
| Knowledge source | `https://<dev-tenant>.sharepoint.com/sites/exec-workspace` (status: Ready) |
| Web Search | **OFF** (`botcomponent GptComponentMetadata.gptCapabilities.webBrowsing = false`) — enforced by `02-deploy-copilot-agent.ps1` and verified by `01-validate-copilot.ps1` |
| Published | 14 March 2026 |
| Portal URL | `https://copilotstudio.microsoft.com/environments/Default-<tenant-id>/bots/<bot-id>/overview` |

> **Instructions note:** The portal holds a compact 6-rule instruction set (from `kickStartTemplate-1.0.0.json`, an export artifact of the deployed agent). The canonical full 8-rule instruction text is in `agent-definition/ExecWorkspace-Copilot.yaml`. These are functionally equivalent in constraint coverage.



10.1 Meeting Views (Approved Library)

Five named views are provisioned on the Approved Library to support executive navigation by meeting type and cycle:

| View Name | Filter | Sort | Grouping |
|---|---|---|---|
| Board Pack | MeetingType = Board | MeetingDate DESC | — |
| SteerCo Pack | MeetingType = SteerCo | MeetingDate DESC | — |
| ExecTeam Pack | MeetingType = ExecTeam | MeetingDate DESC | — |
| Current Cycle | MeetingDate in current month | MeetingDate ASC | — |
| By Meeting | All documents | MeetingDate DESC | MeetingCycle |

These views replace any need for folder-based navigation. Executives see only the content relevant to their next meeting without folder traversal.

10.2 Document Naming Convention

All documents in a meeting pack must follow:

    [MeetingType]-[YYYY-MM]-[DocumentType]-[ShortTitle]

Examples:
    BOARD-2026-03-ExecSummary-Q1Results
    STEERCO-2026-W12-StatusUpdate-PortfolioReview
    BOARD-2026-03-Appendix-FinancialData

The naming convention is enforced by guidance and template; it is not technically enforced at upload time. Pack IDs (ExecWS_MeetingDecisionId) follow the pattern: [MeetingType]-[YYYY-MM]-[NNN] e.g. BOARD-2026-03-001.

10.3 Meeting Type Reference

| Meeting Type | Cadence | Primary Audience | ExecWS_MeetingType value |
|---|---|---|---|
| Board | Monthly | Executives, Compliance | Board |
| SteerCo | Bi-weekly | Executives, Reviewers | SteerCo |
| ExecTeam | Weekly | Executives | ExecTeam |
| Ad-Hoc | As needed | Variable | Ad-Hoc |

11. Operational Considerations

Regular access reviews for Entra ID groups
Monitoring of audit logs for anomalous access
Periodic validation of retention and labeling policies


11. Extensibility
The low‑level design supports future enhancements, including:

Executive dashboards using SPFx
Structured agendas using Loop components
Integration with meeting notes or task tracking
Additional Copilot agent skills

All extensions must continue to comply with the security, identity, and governance controls defined in this document.
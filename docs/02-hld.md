Executive Secure Research & Decision Workspace
High‑Level Design (HLD) – v0.1

1. Purpose
This document describes the high‑level architecture for the Executive Secure Research & Decision Workspace, implemented using native Microsoft 365 services within the organisation's tenant.
The objective is to provide a secure, auditable, executive‑grade environment for confidential research governance, document review, and decision‑making, delivering outcomes comparable to specialist board portals while remaining fully contained within Microsoft 365.

2. Architectural Principles
The solution is guided by the following principles:

Microsoft 365 native services only
Identity‑centric security model
Least‑privilege access by default
Configuration over custom development
Auditability and compliance built in by design
Incremental extensibility


3. High‑Level Architecture Overview
The solution is composed of the following Microsoft 365 services:

Microsoft Entra ID for identity, authentication, Conditional Access, and privileged access management
SharePoint Online as the secure content backbone and executive workspace
Power Automate for workflow orchestration, approvals, and lifecycle automation
Microsoft Purview for audit logging, retention, and eDiscovery
Microsoft 365 Copilot / Copilot Studio for AI‑assisted summarisation and insight over approved content
Power Apps Canvas App as the executive-grade user interface across all personas

All services operate entirely within the organisation's Microsoft 365 tenant boundary. [microsofte...epoint.com]

4. Logical Architecture
The logical flow of the solution is as follows:
Executive Users
→ Power Apps Canvas App (role-based UI)
→ Microsoft Entra ID (authentication, Conditional Access, group-based role detection)
→ Secure SharePoint Workspace
→ Document Libraries (Draft, Review, Approved, Archive)
→ Power Automate Workflows (lifecycle transitions, approvals)
→ Microsoft Purview (Audit & Retention)
→ Scoped Copilot Agent (embedded in Canvas App)
This logical architecture directly maps to the document lifecycle and process flow defined in the requirements and process flow diagrams. The Canvas App is a presentation layer only — all data, governance, and automation remain in their respective M365 services. [microsofte...epoint.com]

5. Workspace Design (HLD)
5.1 Site Type

SharePoint Communication Site
Private site collection
No Microsoft Teams chat or informal collaboration features
Audience targeting enabled

This site type is intentionally chosen to support a focused, executive‑grade experience rather than open collaboration.
5.2 Content Segmentation
Content is segmented by lifecycle state using separate document libraries rather than folders. This enables:

Unique permission sets per lifecycle stage
Distinct retention and compliance policies
Clear and enforceable lifecycle transitions
Reduced risk of accidental over‑exposure of sensitive material


6. Security and Identity Model (HLD)
6.1 Identity Enforcement

All access is enforced through Microsoft Entra ID
Named‑user access only
Role‑based access via Entra ID security groups

6.2 Access Controls

No permission inheritance between document libraries
Conditional Access enforced (for example: MFA and compliant device requirements)
Optional use of Privileged Identity Management (PIM) for time‑bound access to sensitive content

6.3 Information Protection

Sensitivity labels applied at document library level
Encryption and access restrictions enforced natively
External sharing disabled


7. Process Automation (HLD)
Power Automate is used to implement and enforce the documented governance process, including:

Document lifecycle transitions (Draft → Review → Approved → Archive)
Formal approval workflows
Permission changes aligned with lifecycle state
Notifications to relevant stakeholders

This ensures that governance is applied consistently and does not rely on manual discipline. [microsofte...epoint.com]

8. AI Architecture (HLD)
8.1 AI Scope
AI capabilities are delivered through a scoped Copilot agent with access limited to:

A single SharePoint site
Approved content libraries only

8.2 AI Capabilities

Summarisation of approved packs
Extraction of key decisions and highlights
Question and answer over approved content

8.3 AI Constraints

Read‑only access
No access to Draft or Review libraries
No external data sources
No training or fine‑tuning on the organisation's data

All AI processing remains within tenant boundaries. [microsofte...epoint.com]

9. Compliance and Governance (HLD)

Microsoft Purview Unified Audit Log enabled
Automatic capture of access, modification, and approval events
Retention labels applied in line with the organisation's governance requirements
eDiscovery supported without data duplication or export

This provides defensible compliance aligned with regulatory and research governance needs. [microsofte...epoint.com]

10. Executive User Interface (HLD)

10.1 Approach
The executive user interface is delivered through a Power Apps Canvas App — a native Microsoft 365 low-code application that provides pixel-level control over the user experience. This replaces direct SharePoint library navigation with a purpose-built, role-aware application.

10.2 Design Rationale
Canvas App was selected over other options for the following reasons:

Power Apps is a native M365 service — no third-party dependency
Delegated authentication inherits the user's Entra ID identity, Conditional Access policies, and group-based permissions
Standard connectors (SharePoint, Approvals, Office 365 Users, Power Automate) are included in M365 E5 licensing
Low-code approach aligns with the "Configuration over custom code" architectural principle
Canvas Apps offer full layout control optimised for executive-grade clarity and low cognitive load

10.3 Architecture
The Canvas App connects to existing M365 services via standard connectors:

SharePoint connector — read/write document libraries and metadata
Office 365 Users connector — resolve signed-in user's group membership for role detection
Approvals connector — display and action pending approval tasks inline
Power Automate connector — trigger the ExecWS-ApprovedToArchive flow
Copilot Studio — embedded AI chat panel scoped to the Approved library

The app introduces no new data stores. SharePoint remains the single source of truth for all content and metadata.

10.4 Role-Based Experience
A single app serves all personas. On launch, the app detects the user's Entra ID security group membership and presents role-appropriate screens:

Authors — document upload, Draft library management, review submission
Reviewers — approval queue, inline approve/reject, approval history
Executives — approved pack browsing, dashboard, embedded AI assistant
Compliance — archive management, retention status, approved content browsing

10.5 Screens
The app comprises seven screens:

Dashboard (Home) — metrics, upcoming meetings, recent approvals, quick actions
Document Browser — role-filtered galleries with meeting-cadence filtering and sorting
Document Upload — file upload with metadata form, validation, and auto-naming (Authors only)
Document Detail — full metadata, version history, lifecycle actions
Approvals Centre — pending tasks, inline approve/reject, history (Reviewers)
AI Assistant — embedded Copilot Studio chat panel (Executives)
Archive Management — archival triggers, retention browser (Compliance)

10.6 Security Model
The Canvas App inherits and reinforces the existing security model:

Delegated identity — all connector calls use the signed-in user's Entra ID token
Conditional Access — MFA and compliant device requirements apply automatically
Library permissions — SharePoint enforces server-side access control; the app cannot bypass it
Approval integrity — all approvals route through the Approvals connector and Power Automate
AI scoping — the Copilot Studio agent enforces Approved-only, read-only constraints independently

10.7 Form Factors
The app is optimised for desktop (1920×1080) and tablet (1024×768) form factors. Mobile phone is out of scope for v1.

10.8 Distribution
The app is distributed as a standalone Power App accessible via the Power Apps portal (apps.powerapps.com). Teams and SharePoint embedding are deferred to a future release.

See `docs/04-ws7-requirements.md` for the full functional and non-functional requirements specification.
See `docs/05-ws7-lld.md` for the detailed low-level design.

11. Extensibility
The architecture supports future enhancements, including:

Executive dashboards using SPFx
Structured agendas using Loop components
Integration with meeting notes or task tracking tools
Additional Copilot agent skills
Teams and SharePoint embedding of the Canvas App
Mobile form factor support

All extensions must continue to adhere to the architectural principles defined in this document.

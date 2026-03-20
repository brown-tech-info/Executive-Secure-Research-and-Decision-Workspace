# Executive Secure Research & Decision Workspace
## WS-7: Power Apps Canvas App — Low-Level Design (LLD) (v0.1)

---

## 1. Purpose

This document provides the detailed low-level design for the Power Apps Canvas App that serves as the executive user interface for the Executive Secure Research & Decision Workspace. It specifies concrete screen designs, connector configurations, Power Fx formulas, role detection logic, metadata mapping, navigation model, and deployment approach.

This LLD is the implementation companion to `docs/04-ws7-requirements.md` (requirements) and `docs/02-hld.md` §10 (HLD).

---

## 2. App Configuration

### 2.1 App Properties

| Property | Value |
|----------|-------|
| **App Name** | ExecWorkspace |
| **App Type** | Canvas App |
| **Layout** | Tablet (1366×768 base, responsive) |
| **Theme** | Custom executive theme (see §11) |
| **OnStart** | Role detection, data initialisation (see §4) |
| **Environment** | Default Power Platform environment |
| **Solution** | `ExecWorkspaceSolution` (managed solution for ALM) |

### 2.2 Environment Variables

Environment variables enable promotion between dev and production tenants without modifying formulas.

| Variable | Type | Dev Value | Purpose |
|----------|------|-----------|---------|
| `env_SharePointSiteUrl` | Text | `https://<dev-tenant>.sharepoint.com/sites/exec-workspace` | SharePoint site URL |
| `env_DraftLibrary` | Text | `Draft` | Draft library display name |
| `env_ReviewLibrary` | Text | `Review` | Review library display name |
| `env_ApprovedLibrary` | Text | `Approved` | Approved library display name |
| `env_ArchiveLibrary` | Text | `Archive` | Archive library display name |
| `env_ArchiveFlowId` | Text | `<flow-guid>` | ExecWS-ApprovedToArchive flow GUID |

---

## 3. Connector Configuration

### 3.1 Connections

| Connector | Auth Type | Scope | Notes |
|-----------|-----------|-------|-------|
| **SharePoint** | Delegated (current user) | Site-level | Reads/writes all 4 libraries; permissions enforced server-side |
| **Office 365 Users** | Delegated (current user) | User.Read, GroupMember.Read.All | Profile and group membership |
| **Approvals** | Delegated (current user) | Approvals.Read.All, Approvals.ReadWrite.All | Pending tasks and action |
| **Power Automate Management** | Delegated (current user) | Flows.Read.All, Flows.Manage.All | Trigger archive flow |
| **Copilot Studio (Power Virtual Agents)** | Delegated (current user) | Bot.Read | Embedded chat panel |

### 3.2 Data Sources

| Data Source | Connector | Target | Used By |
|-------------|-----------|--------|---------|
| `DraftLib` | SharePoint | `Draft` library at `env_SharePointSiteUrl` | Upload, Browser, Dashboard |
| `ReviewLib` | SharePoint | `Review` library at `env_SharePointSiteUrl` | Browser, Approvals |
| `ApprovedLib` | SharePoint | `Approved` library at `env_SharePointSiteUrl` | Browser, Dashboard, Archive Mgmt |
| `ArchiveLib` | SharePoint | `Archive` library at `env_SharePointSiteUrl` | Archive Mgmt, Dashboard |
| `ApprovalsTable` | Approvals | Current user's approval tasks | Approvals Centre |

---

## 4. Role Detection Logic

### 4.1 App.OnStart

On app launch, the following logic executes to determine the user's role(s) and initialise global state.

```
// Power Fx — App.OnStart

// 1. Get current user profile
Set(gblCurrentUser, Office365Users.MyProfileV2());

// 2. Resolve group memberships
Set(
    gblUserGroups,
    Office365Users.GetMemberGroups(
        gblCurrentUser.id,
        { securityEnabledOnly: true }
    ).value
);

// 3. Match against known workspace groups
// Group Object IDs are stored in environment variables
Set(gblIsAuthor, gblCurrentUser.id in LookUp(
    Office365Groups.ListGroupMembers(env_AuthorsGroupId).value, id = gblCurrentUser.id
));
Set(gblIsReviewer, gblCurrentUser.id in LookUp(
    Office365Groups.ListGroupMembers(env_ReviewersGroupId).value, id = gblCurrentUser.id
));
Set(gblIsExecutive, gblCurrentUser.id in LookUp(
    Office365Groups.ListGroupMembers(env_ExecutivesGroupId).value, id = gblCurrentUser.id
));
Set(gblIsCompliance, gblCurrentUser.id in LookUp(
    Office365Groups.ListGroupMembers(env_ComplianceGroupId).value, id = gblCurrentUser.id
));
Set(gblIsAdmin, gblCurrentUser.id in LookUp(
    Office365Groups.ListGroupMembers(env_AdminsGroupId).value, id = gblCurrentUser.id
));

// 4. Determine if user has any recognised role
Set(gblHasRole, gblIsAuthor || gblIsReviewer || gblIsExecutive || gblIsCompliance || gblIsAdmin);

// 5. Initialise dashboard data
If(gblHasRole,
    // Load document counts
    Set(gblDraftCount, CountRows(DraftLib));
    Set(gblReviewCount, CountRows(ReviewLib));
    Set(gblApprovedCount, CountRows(ApprovedLib));
    Set(gblArchiveCount, CountRows(ArchiveLib));
);
```

> **Implementation note:** The group membership check above is illustrative. In practice, the most efficient approach may be to use a lightweight Power Automate flow (HTTP trigger → Graph API `checkMemberGroups`) called from `App.OnStart`, returning a JSON array of matched group names. This avoids the 2000-member limit on `ListGroupMembers` and reduces connector calls. The choice between direct connector calls and a flow-based approach should be validated during dev tenant testing.

### 4.2 Additional Environment Variables for Role Detection

| Variable | Type | Purpose |
|----------|------|---------|
| `env_AuthorsGroupId` | Text | Object ID of ExecWorkspace-Authors |
| `env_ReviewersGroupId` | Text | Object ID of ExecWorkspace-Reviewers |
| `env_ExecutivesGroupId` | Text | Object ID of ExecWorkspace-Executives |
| `env_ComplianceGroupId` | Text | Object ID of ExecWorkspace-Compliance |
| `env_AdminsGroupId` | Text | Object ID of ExecWorkspace-PlatformAdmins |

### 4.3 Fallback Behaviour

If `gblHasRole = false`, the app navigates to `scrNoAccess` — a static screen displaying:

- "You do not have access to the Executive Workspace."
- "Contact your administrator to request access."
- The signed-in user's display name and email (for troubleshooting)

---

## 5. Navigation Model

### 5.1 Navigation Component

A persistent left-side navigation panel appears on all screens (except `scrNoAccess`). Navigation items are conditionally visible based on role flags.

| Nav Item | Target Screen | Visible When |
|----------|--------------|-------------|
| **Dashboard** | `scrDashboard` | Always (if `gblHasRole`) |
| **Documents** | `scrDocBrowser` | Always (if `gblHasRole`) |
| **Upload** | `scrDocUpload` | `gblIsAuthor` |
| **Approvals** | `scrApprovals` | `gblIsReviewer` |
| **AI Assistant** | `scrAIAssistant` | `gblIsExecutive` |
| **Archive** | `scrArchiveMgmt` | `gblIsCompliance` |

### 5.2 Screen Map

| Screen Name | Purpose | Primary Persona |
|-------------|---------|----------------|
| `scrDashboard` | Home — metrics, meetings, quick actions | All |
| `scrDocBrowser` | Document gallery with filters | All |
| `scrDocUpload` | File upload with metadata form | Authors |
| `scrDocDetail` | Document detail with lifecycle actions | All (actions vary by role) |
| `scrApprovals` | Approval queue and history | Reviewers |
| `scrAIAssistant` | Embedded Copilot Studio chat | Executives |
| `scrArchiveMgmt` | Archive trigger and browse | Compliance |
| `scrNoAccess` | Fallback — no recognised role | Unrecognised users |

---

## 6. Screen Specifications

### 6.1 Dashboard (`scrDashboard`)

**Layout:**

```
┌─────────┬───────────────────────────────────────────────────┐
│         │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ │
│  N      │  │ Draft    │ │ Review   │ │ Approved │ │Archive│ │
│  A      │  │ [count]  │ │ [count]  │ │ [count]  │ │[count]│ │
│  V      │  └──────────┘ └──────────┘ └──────────┘ └──────┘ │
│         │                                                   │
│  P      │  ┌─────────────────────┐ ┌─────────────────────┐ │
│  A      │  │ Upcoming Meetings   │ │ Recent Approvals    │ │
│  N      │  │ - Board 2026-04     │ │ - Doc1: Approved ✓  │ │
│  E      │  │ - SteerCo W14       │ │ - Doc2: Rejected ✗  │ │
│  L      │  │ - ExecTeam W14      │ │ - Doc3: Approved ✓  │ │
│         │  │ ...                 │ │ ...                 │ │
│         │  └─────────────────────┘ └─────────────────────┘ │
│         │                                                   │
│         │  ┌─────────────────────────────────────────────┐ │
│         │  │ Quick Actions (role-dependent)              │ │
│         │  │ [New Document]  [Pending Reviews]  [Archive]│ │
│         │  └─────────────────────────────────────────────┘ │
└─────────┴───────────────────────────────────────────────────┘
```

**Metrics Cards:**

| Card | Formula | Colour |
|------|---------|--------|
| Draft Count | `gblDraftCount` | Blue (#0078D4) |
| Review Count | `gblReviewCount` | Amber (#FFB900) |
| Approved Count | `gblApprovedCount` | Green (#107C10) |
| Archive Count | `gblArchiveCount` | Grey (#737373) |

**Upcoming Meetings Gallery:**

```
// Power Fx — Gallery Items
SortByColumns(
    Filter(
        ApprovedLib,
        ExecWS_MeetingDate >= Today()
    ),
    "ExecWS_MeetingDate", SortOrder.Ascending
)
```

Displays: Meeting Type icon, Meeting Cycle, Meeting Date, document count per pack.

**Recent Approvals Gallery:**

```
// Power Fx — requires Approvals connector
// Display last 10 approvals for the workspace
SortByColumns(
    FirstN(
        Approvals.GetApprovals({ top: 10, filter: "properties/title eq 'ExecWS'" }),
        10
    ),
    "properties/createdDateTime", SortOrder.Descending
)
```

> **Note:** The exact Approvals connector filter syntax will be validated during dev tenant testing.

**Quick Actions:**

| Button | Visible | OnSelect |
|--------|---------|----------|
| New Document | `gblIsAuthor` | `Navigate(scrDocUpload)` |
| Pending Reviews | `gblIsReviewer` | `Navigate(scrApprovals)` |
| Archive Documents | `gblIsCompliance` | `Navigate(scrArchiveMgmt)` |

---

### 6.2 Document Browser (`scrDocBrowser`)

**Data Source Selection (role-based):**

```
// Power Fx — determine which libraries to show
Set(locBrowserSource,
    If(
        gblIsAuthor,
        // Authors see Draft (primary) + Review (secondary)
        SortByColumns(
            Filter(DraftLib, true) & Filter(ReviewLib, true),
            "Modified", SortOrder.Descending
        ),
        gblIsReviewer,
        SortByColumns(
            Filter(ReviewLib, true) & Filter(DraftLib, true),
            "Modified", SortOrder.Descending
        ),
        gblIsExecutive,
        SortByColumns(Filter(ApprovedLib, true), "ExecWS_MeetingDate", SortOrder.Descending),
        gblIsCompliance,
        SortByColumns(
            Filter(ApprovedLib, true) & Filter(ArchiveLib, true),
            "Modified", SortOrder.Descending
        )
    )
);
```

> **Implementation note:** SharePoint connector does not support cross-library union queries natively. The practical approach is to use separate galleries with a tab control (one tab per library the user can access) rather than attempting a union in Power Fx.

**Filter Bar Controls:**

| Control | Type | Values | Column |
|---------|------|--------|--------|
| Meeting Type | Dropdown | Board, SteerCo, ExecTeam, Ad-Hoc, (All) | `ExecWS_MeetingType` |
| Meeting Cycle | Dropdown | Dynamic from library | `ExecWS_MeetingCycle` |
| Document Type | Dropdown | Board Pack, Research Summary, Decision Record, Meeting Minutes, Supporting Material, (All) | `ExecWS_DocumentType` |
| Date Range | Date picker (From/To) | — | `ExecWS_MeetingDate` |

**Gallery Item Template:**

```
┌─────────────────────────────────────────────────────────┐
│ 📄 [Document Name]                     [Lifecycle Badge]│
│ Type: [DocumentType]  │  Meeting: [MeetingType]         │
│ Date: [MeetingDate]   │  Owner: [DocumentOwner]         │
│ Cycle: [MeetingCycle] │  Modified: [Modified]           │
└─────────────────────────────────────────────────────────┘
```

**Gallery OnSelect:** `Navigate(scrDocDetail, ScreenTransition.None, { locSelectedDoc: ThisItem })`

---

### 6.3 Document Upload (`scrDocUpload`)

**Visibility:** `gblIsAuthor` (entire screen hidden from other roles via navigation)

**Form Controls:**

| Control | Type | Default | Required | Column Mapping |
|---------|------|---------|----------|----------------|
| File Attachment | `AddMediaButton` + `Attachment` | — | Yes | File content |
| Document Type | Dropdown | (none) | Yes | `ExecWS_DocumentType` |
| Meeting Type | Dropdown | (none) | Yes | `ExecWS_MeetingType` |
| Meeting Date | DatePicker | `Today()` | Yes | `ExecWS_MeetingDate` |
| Short Title | TextInput | — | Yes | Used for filename generation |
| Sensitivity | Dropdown | "Confidential – Executive" | Yes | `ExecWS_SensitivityClassification` |
| Pack Version | TextInput (number) | 1 | No | `ExecWS_PackVersion` |

**Auto-Derived Fields (computed, not user-editable):**

```
// Meeting Cycle
Set(locMeetingCycle,
    If(
        drpMeetingType.Selected.Value = "Board",
        "BOARD-" & Text(dpMeetingDate.SelectedDate, "yyyy-MM"),
        drpMeetingType.Selected.Value = "SteerCo",
        "STEERCO-" & Text(dpMeetingDate.SelectedDate, "yyyy") & "-W" & Text(WeekNum(dpMeetingDate.SelectedDate)),
        drpMeetingType.Selected.Value = "ExecTeam",
        "EXECTEAM-" & Text(dpMeetingDate.SelectedDate, "yyyy") & "-W" & Text(WeekNum(dpMeetingDate.SelectedDate)),
        "ADHOC-" & Text(dpMeetingDate.SelectedDate, "yyyy-MM-dd")
    )
);

// Meeting / Decision ID
Set(locMeetingDecisionId,
    locMeetingCycle & "-001"
);
// Note: The NNN suffix should ideally be auto-incremented based on existing docs
// in the pack. A lookup query against DraftLib filtered by locMeetingCycle
// can determine the next available number.

// Auto-generated filename
Set(locFileName,
    Upper(drpMeetingType.Selected.Value) & "-" &
    Text(dpMeetingDate.SelectedDate, "yyyy-MM") & "-" &
    Substitute(drpDocumentType.Selected.Value, " ", "") & "-" &
    Substitute(txtShortTitle.Text, " ", "")
);
```

**Upload Action (Submit button OnSelect):**

```
// Power Fx — Upload document to Draft library
// Validate required fields
If(
    IsBlank(attachmentControl.Attachments) ||
    IsBlank(drpDocumentType.Selected) ||
    IsBlank(drpMeetingType.Selected) ||
    IsBlank(txtShortTitle.Text),
    Notify("Please complete all required fields", NotificationType.Error),

    // Upload file
    Set(locUploadResult,
        SharePointOnline.AddFileToLibrary(
            env_SharePointSiteUrl,
            env_DraftLibrary,
            locFileName & "." & Last(Split(First(attachmentControl.Attachments).Name, ".")).Value,
            First(attachmentControl.Attachments).Value
        )
    );

    // Set metadata on uploaded file
    Patch(
        DraftLib,
        LookUp(DraftLib, {Name: locUploadResult.Name}),
        {
            ExecWS_LifecycleState: {Value: "Draft"},
            ExecWS_DocumentType: drpDocumentType.Selected,
            ExecWS_MeetingType: drpMeetingType.Selected,
            ExecWS_MeetingDate: dpMeetingDate.SelectedDate,
            ExecWS_MeetingCycle: locMeetingCycle,
            ExecWS_MeetingDecisionId: locMeetingDecisionId,
            ExecWS_PackVersion: Value(txtPackVersion.Text),
            ExecWS_SensitivityClassification: drpSensitivity.Selected,
            ExecWS_DocumentOwner: gblCurrentUser
        }
    );

    Notify("Document uploaded successfully", NotificationType.Success);
    Navigate(scrDocBrowser);
);
```

> **Implementation note:** The exact SharePoint connector function names and parameter shapes must be validated against the connector's current API. The `Patch` approach for metadata may require the SharePoint item ID rather than a `LookUp` by name. Testing will confirm the optimal pattern.

---

### 6.4 Document Detail (`scrDocDetail`)

**Context:** Receives `locSelectedDoc` from the Document Browser gallery.

**Metadata Display:**

| Field | Display | Format |
|-------|---------|--------|
| Document Name | Header (large text) | — |
| Lifecycle State | Colour-coded badge | Blue/Amber/Green/Grey |
| Document Type | Label | — |
| Meeting Type | Label with icon | — |
| Meeting Date | Label | `dd MMM yyyy` |
| Meeting Cycle | Label | — |
| Meeting / Decision ID | Label | — |
| Pack Version | Label | `v[N]` |
| Sensitivity | Label with colour indicator | — |
| Document Owner | Label with profile picture | — |
| Created | Label | `dd MMM yyyy HH:mm` |
| Modified | Label | `dd MMM yyyy HH:mm` |

**Lifecycle State Badge:**

```
// Power Fx — Badge colour
Switch(
    locSelectedDoc.ExecWS_LifecycleState.Value,
    "Draft", RGBA(0, 120, 212, 1),      // Blue
    "Review", RGBA(255, 185, 0, 1),      // Amber
    "Approved", RGBA(16, 124, 16, 1),    // Green
    "Archive", RGBA(115, 115, 115, 1)    // Grey
)
```

**Version History:**

```
// Power Fx — Retrieve version history
// SharePoint connector GetFileVersions or REST API call
Set(locVersions,
    SharePointOnline.GetFileVersions(
        env_SharePointSiteUrl,
        locSelectedDoc.ID
    )
);
```

**Role-Based Action Buttons:**

| Button | Visible When | OnSelect |
|--------|-------------|----------|
| **Submit for Review** | `gblIsAuthor && locSelectedDoc.ExecWS_LifecycleState.Value = "Draft"` | See below |
| **Approve** | `gblIsReviewer && locSelectedDoc.ExecWS_LifecycleState.Value = "Review"` | See below |
| **Reject** | `gblIsReviewer && locSelectedDoc.ExecWS_LifecycleState.Value = "Review"` | See below |
| **Archive** | `gblIsCompliance && locSelectedDoc.ExecWS_LifecycleState.Value = "Approved"` | See below |
| **Open in SharePoint** | Always | `Launch(locSelectedDoc.{Link})` |

**Submit for Review:**

```
// Power Fx — Author submits draft for review
// This sets the LifecycleState which triggers the DraftToReview flow
Patch(
    DraftLib,
    locSelectedDoc,
    { ExecWS_LifecycleState: {Value: "Review"} }
);
Notify("Document submitted for review. It will move to the Review library shortly.", NotificationType.Success);
Navigate(scrDocBrowser);
```

**Approve / Reject:**

```
// Power Fx — Approvals handled via Approvals connector
// The ReviewToApproved flow creates an approval task via StartAndWaitForAnApproval
// The Canvas App reads and responds to that task

// Approve
Approvals.RespondToApproval(
    locSelectedApproval.id,
    { response: "Approve", comments: txtApprovalComments.Text }
);
Notify("Document approved.", NotificationType.Success);

// Reject
Approvals.RespondToApproval(
    locSelectedApproval.id,
    { response: "Reject", comments: txtRejectionComments.Text }
);
Notify("Document rejected. It will return to Draft with your comments.", NotificationType.Warning);
```

> **Note:** The reviewer must have a pending approval task for the document. The app must first check if an approval task exists for the selected document before showing approve/reject buttons.

**Archive:**

```
// Power Fx — Trigger the ApprovedToArchive flow
PowerAutomate.Run(
    env_ArchiveFlowId,
    { documentId: locSelectedDoc.ID }
);
Notify("Archive process started. The document will move to Archive shortly.", NotificationType.Success);
```

---

### 6.5 Approvals Centre (`scrApprovals`)

**Visibility:** `gblIsReviewer`

**Tabs:**
- **Pending** — approval tasks awaiting response
- **History** — completed approvals

**Pending Gallery:**

```
// Power Fx — Pending approvals assigned to current user
Filter(
    Approvals.GetApprovals({ filter: "properties/status eq 'Pending'" }),
    // Additional client-side filter for workspace-specific approvals
    StartsWith(properties.title, "ExecWS")
)
```

**Gallery Item Template:**

```
┌─────────────────────────────────────────────────────────┐
│ 📋 [Document Name]                          [PENDING]   │
│ Submitted by: [Author]  │  Date: [SubmittedDate]       │
│ Meeting: [MeetingType] - [MeetingCycle]                 │
│ [Approve ✓]  [Reject ✗]                                │
└─────────────────────────────────────────────────────────┘
```

**Approve/Reject actions** use the same `Approvals.RespondToApproval` pattern from §6.4.

**History Gallery:**

Displays: document name, outcome (Approved/Rejected), approver, timestamp, comments.

---

### 6.6 AI Assistant (`scrAIAssistant`)

**Visibility:** `gblIsExecutive`

**Copilot Studio Embedding:**

The Copilot Studio agent is embedded using the Power Virtual Agents (Copilot Studio) Canvas App component.

```
// Configuration
Bot ID:          <ExecWorkspace-Copilot bot ID from env variable>
Schema Name:     env_CopilotBotSchemaName
Authentication:  Entra ID (delegated, signed-in user)
```

**Pre-configured Prompt Buttons:**

| Button Label | Prompt Sent |
|-------------|-------------|
| "Summarise latest Board pack" | "Summarise the most recent Board meeting pack" |
| "Key SteerCo decisions" | "What were the key decisions from the latest SteerCo meeting?" |
| "Compare Q1 vs Q2" | "Compare the Q1 and Q2 results from the approved documents" |
| "Current cycle overview" | "Give me an overview of all documents in the current meeting cycle" |

**Layout:**
- Left panel: pre-configured prompts and navigation
- Right panel (or full-screen): chat interface with the Copilot Studio agent
- Toggle button to switch between side-panel and full-screen modes

---

### 6.7 Archive Management (`scrArchiveMgmt`)

**Visibility:** `gblIsCompliance`

**Two sections:**

**Section 1: Documents Eligible for Archival**

```
// Power Fx — Approved documents available for archival
SortByColumns(
    ApprovedLib,
    "ExecWS_MeetingDate", SortOrder.Descending
)
```

- Checkbox selection for bulk archival
- "Archive Selected" button triggers the ApprovedToArchive flow for each selected document
- Confirmation dialog before triggering

**Section 2: Archive Browser**

```
// Power Fx — Archive library contents
SortByColumns(
    ArchiveLib,
    "Modified", SortOrder.Descending
)
```

Displays: document name, archive date, meeting cycle, retention label, modification date.

---

## 7. Metadata Column Mapping

The following table maps SharePoint column internal names to Power Fx references. Internal names must be confirmed from the deployed SharePoint site.

| Display Name | Expected Internal Name | Power Fx Reference | Type |
|-------------|----------------------|-------------------|------|
| Lifecycle State | `ExecWS_LifecycleState` | `ExecWS_LifecycleState` | Choice |
| Document Type | `ExecWS_DocumentType` | `ExecWS_DocumentType` | Text |
| Meeting Type | `ExecWS_MeetingType` | `ExecWS_MeetingType` | Choice |
| Meeting Date | `ExecWS_MeetingDate` | `ExecWS_MeetingDate` | Date |
| Meeting Cycle | `ExecWS_MeetingCycle` | `ExecWS_MeetingCycle` | Text |
| Meeting / Decision ID | `ExecWS_MeetingDecisionId` | `ExecWS_MeetingDecisionId` | Text |
| Pack Version | `ExecWS_PackVersion` | `ExecWS_PackVersion` | Number |
| Sensitivity Classification | `ExecWS_SensitivityClassification` | `ExecWS_SensitivityClassification` | Choice |
| Document Owner | `ExecWS_DocumentOwner` | `ExecWS_DocumentOwner` | Person |

> **Validation required:** SharePoint sometimes transforms column internal names (e.g., replacing spaces with `_x0020_`). The exact internal names must be verified by querying the deployed libraries: `GET _api/web/lists/getbytitle('Draft')/fields?$filter=Group eq 'ExecWS'`.

---

## 8. Error Handling

### 8.1 Pattern

All connector calls must follow the pattern:

```
// Power Fx — Standard error handling
Set(locResult,
    IfError(
        <connector call>,
        Notify("An error occurred: " & FirstError.Message, NotificationType.Error);
        Blank()
    )
);
```

### 8.2 Specific Error Scenarios

| Scenario | User Message | Recovery |
|----------|-------------|----------|
| Upload fails | "Unable to upload document. Please try again." | Retry button |
| Metadata patch fails | "Document uploaded but metadata could not be set. Please edit in SharePoint." | Link to SharePoint |
| Approval response fails | "Unable to submit approval response. Please try via Teams or email." | Link to approval in Teams |
| Flow trigger fails | "Unable to start the archive process. Please contact your administrator." | Contact info |
| Role detection fails | "Unable to determine your access level. Please contact your administrator." | Navigate to `scrNoAccess` |
| Library query returns empty | "No documents found matching your criteria." | Adjust filters guidance |

---

## 9. Performance Optimisation

### 9.1 Delegation

SharePoint connector supports delegation for:
- `Filter` with `=`, `<>`, `<`, `>`, `<=`, `>=`, `StartsWith`
- `Sort` (single column)
- `Search`

Non-delegable operations (avoid or paginate):
- `CountRows` on large lists (use `CountIf` with a delegable filter, or a flow)
- `LookUp` with complex predicates
- `AddColumns` / `DropColumns` on the data source

### 9.2 Caching Strategy

```
// Power Fx — Cache dashboard data on App.OnStart
// Refresh only when user navigates to Dashboard or pulls to refresh
Set(gblLastRefresh, Now());

// Refresh function (attached to a Refresh button)
Set(gblDraftCount, CountRows(DraftLib));
Set(gblReviewCount, CountRows(ReviewLib));
Set(gblApprovedCount, CountRows(ApprovedLib));
Set(gblArchiveCount, CountRows(ArchiveLib));
Set(gblLastRefresh, Now());
```

### 9.3 Pagination

Document galleries must use:
- `Items` property with delegable filter/sort
- SharePoint connector's default 100-item delegation limit (configurable up to 2000 in app settings)
- Explicit "Load more" button or auto-pagination for libraries exceeding the limit

---

## 10. Security Controls

### 10.1 Defence in Depth

| Layer | Control | Enforced By |
|-------|---------|-------------|
| **Authentication** | Entra ID sign-in required | Power Apps platform |
| **Conditional Access** | MFA + compliant device | Entra ID CA policy |
| **Role detection** | Group membership check | App.OnStart logic |
| **UI enforcement** | Screens/buttons hidden by role | Power Fx `Visible` property |
| **Server-side** | SharePoint library permissions | SharePoint (authoritative backstop) |
| **Approval integrity** | Approvals connector | Power Automate flow |
| **AI scoping** | Approved-only, read-only | Copilot Studio agent configuration |
| **Audit trail** | All operations logged | Purview Unified Audit Log |

### 10.2 Security Principle

The Canvas App implements **UI-level enforcement** as a convenience layer. **SharePoint permissions are the authoritative security boundary.** Even if a user manipulated the app, SharePoint would reject unauthorised operations.

---

## 11. Visual Design

### 11.1 Theme

| Element | Value | Notes |
|---------|-------|-------|
| Primary colour | `#0078D4` (Microsoft Blue) | Navigation, primary buttons |
| Success | `#107C10` (Green) | Approved state, success toasts |
| Warning | `#FFB900` (Amber) | Review state, pending items |
| Danger | `#D13438` (Red) | Reject buttons, errors |
| Neutral | `#737373` (Grey) | Archive state, disabled items |
| Background | `#FAF9F8` (Light grey) | App background |
| Card background | `#FFFFFF` (White) | Content cards |
| Text primary | `#323130` (Dark grey) | Body text |
| Text secondary | `#605E5C` (Medium grey) | Labels, captions |
| Font | Segoe UI | Consistent with M365 |

### 11.2 Component Library

Reusable components to ensure consistency:

| Component | Usage |
|-----------|-------|
| `cmpNavPanel` | Left navigation panel (all screens) |
| `cmpLifecycleBadge` | Colour-coded lifecycle state badge |
| `cmpMetricsCard` | Dashboard metric card (count + label + colour) |
| `cmpDocGalleryItem` | Standard gallery item template for documents |
| `cmpFilterBar` | Reusable filter controls (dropdowns + date range) |
| `cmpActionButton` | Styled action button with loading state |

---

## 12. Deployment

### 12.1 Solution Structure

The Canvas App must be packaged within a Power Platform managed solution for ALM:

```
ExecWorkspaceSolution/
├── CanvasApps/
│   └── ExecWorkspace.msapp
├── ConnectionReferences/
│   ├── SharePoint_Connection
│   ├── Office365Users_Connection
│   ├── Approvals_Connection
│   ├── PowerAutomate_Connection
│   └── CopilotStudio_Connection
├── EnvironmentVariableDefinitions/
│   ├── env_SharePointSiteUrl
│   ├── env_DraftLibrary
│   ├── env_ReviewLibrary
│   ├── env_ApprovedLibrary
│   ├── env_ArchiveLibrary
│   ├── env_ArchiveFlowId
│   ├── env_AuthorsGroupId
│   ├── env_ReviewersGroupId
│   ├── env_ExecutivesGroupId
│   ├── env_ComplianceGroupId
│   ├── env_AdminsGroupId
│   └── env_CopilotBotSchemaName
└── EnvironmentVariableValues/
    └── (set per environment)
```

### 12.2 Deployment Script

`scripts/ws7-powerapp/01-deploy-canvas-app.ps1` will:

1. Authenticate to the Power Platform environment (certificate-based or interactive)
2. Import the managed solution using `pac solution import`
3. Set environment variable values from `scripts/config.ps1`
4. Configure connection references
5. Share the app with the five Entra ID security groups
6. Validate the app is accessible

The script follows the same idempotent, error-handling, and `-WhatIf` patterns established in WS-1 through WS-6.

### 12.3 Prerequisites

- Power Platform CLI (`pac`) installed
- Power Apps environment with Dataverse provisioned (for solution import — does not mean data is stored in Dataverse)
- App creator role in the target environment
- Connection references established for all five connectors

---

## 13. Testing

### 13.1 Test Scenarios

| ID | Scenario | Steps | Expected Result |
|----|----------|-------|----------------|
| T-1 | Author uploads document | Launch app as Author → Upload → Fill metadata → Submit | Document appears in Draft library with correct metadata |
| T-2 | Author submits for review | Open Draft doc → "Submit for Review" | LifecycleState set to "Review", flow triggers within 2 min |
| T-3 | Reviewer approves | Launch as Reviewer → Approvals → Approve with comments | Document moves to Approved library |
| T-4 | Reviewer rejects | Launch as Reviewer → Approvals → Reject with comments | Document returns to Draft with comments |
| T-5 | Executive browses | Launch as Executive → Document Browser | Only Approved library docs visible |
| T-6 | Executive uses AI | Launch as Executive → AI Assistant → Ask a question | Relevant response from approved content |
| T-7 | Compliance archives | Launch as Compliance → Archive Mgmt → Select → Archive | Flow triggers, doc moves to Archive |
| T-8 | No access fallback | Launch as unassigned user | `scrNoAccess` screen displayed |
| T-9 | Dashboard metrics | Launch app → Dashboard | Correct counts for all 4 libraries |
| T-10 | Cross-role user | User in Authors + Executives groups | Sees union of both role capabilities |

### 13.2 Audit Validation

After all test scenarios, query the Purview Unified Audit Log to confirm:
- All document uploads are logged
- All metadata updates are logged
- All approval actions are logged
- All flow triggers are logged
- All AI queries are logged

---

## 14. Open Items

| ID | Item | Status | Resolution |
|----|------|--------|------------|
| OI-1 | Confirm Copilot Studio embedding licensing requirements | Pending | Check dev tenant during implementation |
| OI-2 | Validate SharePoint column internal names | Pending | Query deployed site REST API |
| OI-3 | Determine optimal role detection approach (direct connector vs flow) | Pending | Prototype both, select based on performance |
| OI-4 | Confirm Approvals connector filter syntax for workspace-specific tasks | Pending | Test against live approval tasks |
| OI-5 | Validate delegation limits for document galleries | Pending | Test with 100+ documents in each library |

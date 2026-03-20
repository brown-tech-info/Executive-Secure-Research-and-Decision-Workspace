# Executive Secure Research & Decision Workspace
## WS-7: Canvas App Design Specification (v0.1)

---

## 1. Design Philosophy

The Canvas App prioritises **executive experience**: clarity, trust, and low cognitive load. Every design decision serves the principle that this is a governance tool for senior decision-makers, not a collaboration workspace.

### Design Tenets

1. **Minimal chrome** — reduce visual noise; every element must earn its place
2. **State is always visible** — lifecycle badges, role indicators, and context are never hidden
3. **2-tap rule** — any primary function reachable in ≤ 2 taps from the dashboard
4. **Consistent patterns** — galleries, filters, and actions follow identical visual patterns across screens
5. **M365 visual language** — colours, typography, and iconography align with the Microsoft Fluent Design System

---

## 2. Layout & Responsive Design

### 2.1 Base Canvas

| Property | Value |
|----------|-------|
| Base resolution | 1366 × 768 (Tablet layout) |
| Responsive scaling | Enabled — scales to fill browser/tablet viewport |
| Minimum supported | 1024 × 768 |
| Maximum tested | 1920 × 1080 |
| Orientation | Landscape only |

### 2.2 Grid System

The app uses a consistent 12-column grid with 16px gutters:

```
┌──────────────────────────────────────────────────────────────┐
│ ┌──────┐ ┌───────────────────────────────────────────────┐   │
│ │      │ │                                               │   │
│ │ NAV  │ │              CONTENT AREA                     │   │
│ │      │ │            (10 columns)                       │   │
│ │  2   │ │                                               │   │
│ │ cols │ │                                               │   │
│ │      │ │                                               │   │
│ │      │ │                                               │   │
│ └──────┘ └───────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

- **Navigation panel**: 2 columns (220px fixed width)
- **Content area**: 10 columns (remaining width, fluid)
- **Padding**: 24px outer, 16px between cards

---

## 3. Colour System

### 3.1 Primary Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `theme.primary` | `#0078D4` | Navigation active state, primary buttons, links |
| `theme.primaryDark` | `#004578` | Navigation background, header bar |
| `theme.primaryLight` | `#DEECF9` | Hover states, selected items |

### 3.2 Semantic Colours

| Token | Hex | Usage |
|-------|-----|-------|
| `lifecycle.draft` | `#0078D4` | Draft badge, Draft metrics card |
| `lifecycle.review` | `#FFB900` | Review badge, Review metrics card |
| `lifecycle.approved` | `#107C10` | Approved badge, Approved metrics card |
| `lifecycle.archive` | `#737373` | Archive badge, Archive metrics card |
| `status.success` | `#107C10` | Success toasts, approved status |
| `status.warning` | `#FFB900` | Warning toasts, pending status |
| `status.error` | `#D13438` | Error toasts, reject buttons |
| `status.info` | `#0078D4` | Info toasts, informational badges |

### 3.3 Surface Colours

| Token | Hex | Usage |
|-------|-----|-------|
| `surface.background` | `#FAF9F8` | App background |
| `surface.card` | `#FFFFFF` | Content cards, galleries |
| `surface.nav` | `#004578` | Navigation panel background |
| `surface.header` | `#FFFFFF` | Screen header bar |
| `text.primary` | `#323130` | Body text |
| `text.secondary` | `#605E5C` | Labels, captions |
| `text.onDark` | `#FFFFFF` | Text on dark backgrounds (nav) |
| `border.subtle` | `#EDEBE9` | Card borders, dividers |

---

## 4. Typography

All text uses **Segoe UI** (the M365 standard font) with the following scale:

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `type.h1` | 28px | Semibold (600) | Screen titles |
| `type.h2` | 20px | Semibold (600) | Section headers, card titles |
| `type.h3` | 16px | Semibold (600) | Subsection headers |
| `type.body` | 14px | Regular (400) | Body text, gallery items |
| `type.caption` | 12px | Regular (400) | Labels, timestamps, metadata |
| `type.badge` | 11px | Semibold (600) | Lifecycle badges, status tags |
| `type.metric` | 36px | Light (300) | Dashboard metric numbers |

---

## 5. Iconography

Icons use the **Fluent UI System Icons** set (available natively in Power Apps):

| Icon | Usage |
|------|-------|
| `Home` | Dashboard nav item |
| `DocumentMultiple` | Document Browser nav item |
| `ArrowUpload` | Upload nav item |
| `CheckmarkCircle` | Approvals nav item |
| `Bot` | AI Assistant nav item |
| `Archive` | Archive Management nav item |
| `ChevronRight` | Gallery item disclosure |
| `Filter` | Filter bar toggle |
| `ArrowSync` | Refresh button |
| `PersonCircle` | User profile / document owner |

---

## 6. Component Specifications

### 6.1 Navigation Panel (`cmpNavPanel`)

```
┌────────────────────┐
│  ┌──────────────┐  │
│  │  EXEC        │  │
│  │  WORKSPACE   │  │
│  │  [logo]      │  │
│  └──────────────┘  │
│                    │
│  ● Dashboard       │  ← Active state: white text, left border accent
│  ○ Documents       │  ← Inactive state: 70% opacity white text
│  ○ Upload          │  ← Conditionally visible (Authors only)
│  ○ Approvals       │  ← Conditionally visible (Reviewers only)
│  ○ AI Assistant    │  ← Conditionally visible (Executives only)
│  ○ Archive         │  ← Conditionally visible (Compliance only)
│                    │
│                    │
│                    │
│  ┌──────────────┐  │
│  │ [Avatar]     │  │
│  │ User Name    │  │
│  │ Role Badge   │  │
│  └──────────────┘  │
└────────────────────┘

Width: 220px
Background: #004578
Active indicator: 3px left border in #0078D4
Nav item height: 48px
Padding: 12px horizontal
```

### 6.2 Lifecycle Badge (`cmpLifecycleBadge`)

```
┌─────────────┐
│ ● DRAFT     │  ← Colour-coded dot + uppercase label
└─────────────┘

Height: 24px
Border radius: 12px (pill shape)
Padding: 4px 12px
Font: type.badge (11px Semibold)
Background: 10% opacity of lifecycle colour
Text colour: lifecycle colour at full opacity
Dot: 8px circle, lifecycle colour
```

| State | Background | Text | Dot |
|-------|-----------|------|-----|
| Draft | `rgba(0,120,212,0.1)` | `#0078D4` | `#0078D4` |
| Review | `rgba(255,185,0,0.1)` | `#986F0B` | `#FFB900` |
| Approved | `rgba(16,124,16,0.1)` | `#107C10` | `#107C10` |
| Archive | `rgba(115,115,115,0.1)` | `#737373` | `#737373` |

### 6.3 Metrics Card (`cmpMetricsCard`)

```
┌─────────────────────┐
│  Draft              │  ← type.caption, text.secondary
│                     │
│  47                 │  ← type.metric, lifecycle colour
│  documents          │  ← type.caption, text.secondary
│                     │
│  ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔  │  ← 3px bottom border in lifecycle colour
└─────────────────────┘

Width: 25% of content area (4 cards in a row)
Height: 120px
Background: surface.card
Border: 1px border.subtle
Border radius: 8px
Bottom accent: 3px solid lifecycle colour
Shadow: 0 1px 3px rgba(0,0,0,0.08)
```

### 6.4 Document Gallery Item (`cmpDocGalleryItem`)

```
┌─────────────────────────────────────────────────────────────────┐
│  📄 BOARD-2026-03-ExecSummary-Q1Results         ● DRAFT    ›   │
│  Board Pack  │  Board  │  19 Mar 2026  │  Uri Brown             │
└─────────────────────────────────────────────────────────────────┘

Height: 64px
Background: surface.card
Border: 1px border.subtle (bottom only for list style)
Padding: 12px 16px
First line: type.body Semibold (document name) + cmpLifecycleBadge (right-aligned)
Second line: type.caption text.secondary (metadata chips separated by │ divider)
Hover: surface.background
Selected: primaryLight background
```

### 6.5 Filter Bar (`cmpFilterBar`)

```
┌─────────────────────────────────────────────────────────────────┐
│  🔍 Meeting Type ▾   Meeting Cycle ▾   Doc Type ▾   Date: ▾   │
└─────────────────────────────────────────────────────────────────┘

Height: 48px
Background: surface.card
Border: 1px border.subtle (bottom)
Dropdown style: Fluent-style bordered dropdowns, 180px width each
Spacing: 12px between controls
Clear filters button: text-only link on the right
```

### 6.6 Action Button (`cmpActionButton`)

**Primary (filled):**
```
┌─────────────────────┐
│  Submit for Review   │
└─────────────────────┘
Background: theme.primary
Text: #FFFFFF, type.body Semibold
Height: 36px
Border radius: 4px
Padding: 0 16px
```

**Danger (filled):**
```
Background: status.error (#D13438)
Text: #FFFFFF
```

**Secondary (outlined):**
```
Background: transparent
Border: 1px theme.primary
Text: theme.primary
```

**Loading state:**
```
Background: 50% opacity of normal
Spinner icon replacing text
Disabled: true
```

---

## 7. Screen Wireframes

### 7.1 Dashboard

```
┌────────┬─────────────────────────────────────────────────────────────┐
│        │  Executive Workspace                         [↻ Refresh]   │
│        │                                                            │
│  NAV   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│        │  │ Draft    │ │ Review   │ │ Approved │ │ Archive  │     │
│        │  │   47     │ │   12     │ │   89     │ │   234    │     │
│        │  │ ▔▔▔▔▔▔  │ │ ▔▔▔▔▔▔  │ │ ▔▔▔▔▔▔  │ │ ▔▔▔▔▔▔  │     │
│        │  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │
│        │                                                            │
│        │  ┌──────────────────────────┐ ┌──────────────────────────┐ │
│        │  │ Upcoming Meetings        │ │ Recent Approvals         │ │
│        │  │                          │ │                          │ │
│        │  │ 📅 Board — Apr 2026     │ │ ✓ Q1 Report — Approved  │ │
│        │  │ 📅 SteerCo — W14       │ │ ✗ Budget Draft — Reject │ │
│        │  │ 📅 ExecTeam — W14      │ │ ✓ Risk Assess — Approv  │ │
│        │  │ 📅 Board — May 2026    │ │ ✓ Compliance — Approved │ │
│        │  │ 📅 SteerCo — W16       │ │ ✓ Strategy — Approved   │ │
│        │  │                          │ │                          │ │
│        │  └──────────────────────────┘ └──────────────────────────┘ │
│        │                                                            │
│        │  ┌──────────────────────────────────────────────────────┐ │
│        │  │ Quick Actions                                        │ │
│        │  │ [+ New Document]  [📋 Pending Reviews]  [📦 Archive] │ │
│        │  └──────────────────────────────────────────────────────┘ │
└────────┴─────────────────────────────────────────────────────────────┘
```

### 7.2 Document Browser

```
┌────────┬─────────────────────────────────────────────────────────────┐
│        │  Documents                                                  │
│        │                                                            │
│  NAV   │  ┌──────────────────────────────────────────────────────┐ │
│        │  │ [Draft ▾] [Review ▾]          Tabs per library       │ │
│        │  └──────────────────────────────────────────────────────┘ │
│        │                                                            │
│        │  ┌──────────────────────────────────────────────────────┐ │
│        │  │ Meeting Type ▾  Cycle ▾  Doc Type ▾  Date: ▾  Clear │ │
│        │  └──────────────────────────────────────────────────────┘ │
│        │                                                            │
│        │  ┌──────────────────────────────────────────────────────┐ │
│        │  │ 📄 BOARD-2026-03-ExecSummary-Q1        ● DRAFT   › │ │
│        │  │    Board Pack │ Board │ 19 Mar 2026 │ Uri Brown     │ │
│        │  ├──────────────────────────────────────────────────────┤ │
│        │  │ 📄 STEERCO-2026-W12-Status-Portfolio   ● DRAFT   › │ │
│        │  │    Research Summary │ SteerCo │ 15 Mar │ J. Smith    │ │
│        │  ├──────────────────────────────────────────────────────┤ │
│        │  │ 📄 BOARD-2026-03-Minutes-March         ● DRAFT   › │ │
│        │  │    Meeting Minutes │ Board │ 19 Mar │ Uri Brown     │ │
│        │  ├──────────────────────────────────────────────────────┤ │
│        │  │ ...                                                  │ │
│        │  └──────────────────────────────────────────────────────┘ │
│        │                                                            │
│        │                              Showing 1-20 of 47  [More ▾] │
└────────┴─────────────────────────────────────────────────────────────┘
```

### 7.3 Document Upload

```
┌────────┬─────────────────────────────────────────────────────────────┐
│        │  Upload Document                                           │
│        │                                                            │
│  NAV   │  ┌──────────────────────────────────────────────────────┐ │
│        │  │                                                      │ │
│        │  │         📎 Drag & drop or click to attach            │ │
│        │  │            [Choose File]                              │ │
│        │  │                                                      │ │
│        │  └──────────────────────────────────────────────────────┘ │
│        │                                                            │
│        │  ┌─────────────────────┐  ┌─────────────────────┐         │
│        │  │ Document Type    ▾  │  │ Meeting Type     ▾  │         │
│        │  └─────────────────────┘  └─────────────────────┘         │
│        │                                                            │
│        │  ┌─────────────────────┐  ┌─────────────────────┐         │
│        │  │ Meeting Date   📅   │  │ Short Title     ___  │         │
│        │  └─────────────────────┘  └─────────────────────┘         │
│        │                                                            │
│        │  ┌─────────────────────┐  ┌─────────────────────┐         │
│        │  │ Sensitivity      ▾  │  │ Pack Version   [1]  │         │
│        │  └─────────────────────┘  └─────────────────────┘         │
│        │                                                            │
│        │  Auto-generated filename:                                  │
│        │  BOARD-2026-03-ExecSummary-Q1Results.docx                 │
│        │                                                            │
│        │  Meeting Cycle: BOARD-2026-03                              │
│        │  Decision ID: BOARD-2026-03-001                            │
│        │                                                            │
│        │              [Cancel]  [Upload to Draft ↑]                 │
└────────┴─────────────────────────────────────────────────────────────┘
```

### 7.4 Document Detail

```
┌────────┬─────────────────────────────────────────────────────────────┐
│        │  ← Back                                                     │
│        │                                                            │
│  NAV   │  BOARD-2026-03-ExecSummary-Q1Results          ● DRAFT     │
│        │                                                            │
│        │  ┌──────────────────────────────────────────────────────┐ │
│        │  │ Document Type    Board Pack                          │ │
│        │  │ Meeting Type     Board                               │ │
│        │  │ Meeting Date     19 March 2026                       │ │
│        │  │ Meeting Cycle    BOARD-2026-03                       │ │
│        │  │ Decision ID      BOARD-2026-03-001                   │ │
│        │  │ Pack Version     v1                                  │ │
│        │  │ Sensitivity      Confidential – Executive            │ │
│        │  │ Owner            Uri Brown                           │ │
│        │  │ Created          19 Mar 2026 09:14                   │ │
│        │  │ Modified         20 Mar 2026 13:22                   │ │
│        │  └──────────────────────────────────────────────────────┘ │
│        │                                                            │
│        │  Version History                                           │
│        │  ┌──────────────────────────────────────────────────────┐ │
│        │  │ v2.0 │ 20 Mar 13:22 │ Uri Brown │ Updated figures   │ │
│        │  │ v1.0 │ 19 Mar 09:14 │ Uri Brown │ Initial upload    │ │
│        │  └──────────────────────────────────────────────────────┘ │
│        │                                                            │
│        │  [Open in SharePoint ↗]    [Submit for Review →]          │
└────────┴─────────────────────────────────────────────────────────────┘
```

### 7.5 Approvals Centre

```
┌────────┬─────────────────────────────────────────────────────────────┐
│        │  Approvals           [Pending]  [History]                   │
│        │                                                            │
│  NAV   │  ┌──────────────────────────────────────────────────────┐ │
│        │  │ 📋 Q1 Financial Report                   ⏳ PENDING  │ │
│        │  │    Submitted by: J. Smith │ 18 Mar 2026              │ │
│        │  │    Board │ BOARD-2026-03                              │ │
│        │  │                                                      │ │
│        │  │    Comments: ________________________________        │ │
│        │  │                                                      │ │
│        │  │    [✓ Approve]  [✗ Reject]                          │ │
│        │  ├──────────────────────────────────────────────────────┤ │
│        │  │ 📋 Risk Assessment Update                ⏳ PENDING  │ │
│        │  │    Submitted by: A. Patel │ 17 Mar 2026             │ │
│        │  │    SteerCo │ STEERCO-2026-W12                       │ │
│        │  │                                                      │ │
│        │  │    Comments: ________________________________        │ │
│        │  │                                                      │ │
│        │  │    [✓ Approve]  [✗ Reject]                          │ │
│        │  └──────────────────────────────────────────────────────┘ │
└────────┴─────────────────────────────────────────────────────────────┘
```

### 7.6 AI Assistant

```
┌────────┬─────────────────────────────────────────────────────────────┐
│        │  AI Assistant                              [⬜ Full Screen] │
│        │                                                            │
│  NAV   │  ┌─────────────────┐ ┌──────────────────────────────────┐ │
│        │  │ Suggested       │ │                                  │ │
│        │  │ Prompts         │ │   🤖 Executive Workspace         │ │
│        │  │                 │ │      Assistant                   │ │
│        │  │ [Summarise      │ │                                  │ │
│        │  │  latest Board   │ │   How can I help you today?     │ │
│        │  │  pack]          │ │                                  │ │
│        │  │                 │ │   ─────────────────────────────  │ │
│        │  │ [Key SteerCo    │ │                                  │ │
│        │  │  decisions]     │ │   You: Summarise the latest     │ │
│        │  │                 │ │   Board pack                     │ │
│        │  │ [Compare Q1     │ │                                  │ │
│        │  │  vs Q2]         │ │   🤖 The March 2026 Board pack  │ │
│        │  │                 │ │   contains 5 documents...        │ │
│        │  │ [Current cycle  │ │                                  │ │
│        │  │  overview]      │ │                                  │ │
│        │  │                 │ │   ┌────────────────────────────┐ │ │
│        │  │                 │ │   │ Type your question...   ↑  │ │ │
│        │  │                 │ │   └────────────────────────────┘ │ │
│        │  └─────────────────┘ └──────────────────────────────────┘ │
└────────┴─────────────────────────────────────────────────────────────┘
```

### 7.7 Archive Management

```
┌────────┬─────────────────────────────────────────────────────────────┐
│        │  Archive Management       [Eligible for Archival] [Archived]│
│        │                                                            │
│  NAV   │  ┌──────────────────────────────────────────────────────┐ │
│        │  │ ☐ 📄 BOARD-2025-12-Strategy-Review     ● APPROVED   │ │
│        │  │      Board Pack │ Dec 2025 │ Approved 15 Jan 2026   │ │
│        │  ├──────────────────────────────────────────────────────┤ │
│        │  │ ☐ 📄 STEERCO-2025-W48-Portfolio        ● APPROVED   │ │
│        │  │      Research Summary │ Nov 2025 │ Approved 3 Dec   │ │
│        │  ├──────────────────────────────────────────────────────┤ │
│        │  │ ☑ 📄 BOARD-2025-11-Minutes             ● APPROVED   │ │
│        │  │      Meeting Minutes │ Nov 2025 │ Approved 28 Nov   │ │
│        │  └──────────────────────────────────────────────────────┘ │
│        │                                                            │
│        │  1 document selected                                       │
│        │                                                            │
│        │  [Archive Selected (1) →]                                  │
│        │                                                            │
│        │  ⚠ Archived documents will be moved to the Archive        │
│        │    library with a 7-year retention label applied.          │
└────────┴─────────────────────────────────────────────────────────────┘
```

### 7.8 No Access (Fallback)

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│                                                                      │
│                    🔒 Access Restricted                              │
│                                                                      │
│          You do not have access to the Executive Workspace.          │
│                                                                      │
│          Signed in as: uri.brown@contoso.com                         │
│                                                                      │
│          Contact your administrator to request access.               │
│                                                                      │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 8. Interaction Patterns

### 8.1 Navigation

| Interaction | Behaviour |
|-------------|-----------|
| Nav item click | Navigate to screen, highlight active item |
| Back button (Detail screens) | Navigate to previous screen using `Back()` |
| Logo/brand click | Navigate to Dashboard |
| Quick action click | Navigate to target screen |

### 8.2 Document Gallery

| Interaction | Behaviour |
|-------------|-----------|
| Row click | Navigate to Document Detail |
| Filter change | Gallery re-filtered (delegated query) |
| Clear filters | Reset all dropdowns to "(All)" |
| Load more | Fetch next page of results |

### 8.3 Upload

| Interaction | Behaviour |
|-------------|-----------|
| File attached | Show filename and size preview |
| Metadata change | Auto-derived fields update in real-time |
| Submit (valid) | Upload file, patch metadata, navigate to Browser |
| Submit (invalid) | Highlight missing required fields, show error toast |
| Cancel | Navigate back to Browser |

### 8.4 Approvals

| Interaction | Behaviour |
|-------------|-----------|
| Approve click | Show confirmation, submit via Approvals connector, show success toast |
| Reject click | Validate comments not empty, submit rejection, show warning toast |
| Tab switch | Toggle between Pending and History galleries |

### 8.5 Toasts (Notifications)

| Type | Colour | Duration | Position |
|------|--------|----------|----------|
| Success | Green `#107C10` | 3 seconds | Top-centre |
| Warning | Amber `#FFB900` | 5 seconds | Top-centre |
| Error | Red `#D13438` | Persistent (dismiss button) | Top-centre |
| Info | Blue `#0078D4` | 3 seconds | Top-centre |

---

## 9. Accessibility

| Requirement | Implementation |
|-------------|---------------|
| Colour contrast | All text meets WCAG 2.1 AA (4.5:1 minimum) |
| Focus indicators | Visible focus ring on all interactive elements |
| Screen reader | All images have alt text; lifecycle badges have aria-labels |
| Keyboard navigation | Tab order follows logical reading order |
| Touch targets | Minimum 44×44px for all interactive elements |

---

## 10. Loading & Empty States

### 10.1 Loading

```
┌──────────────────────────────────────────┐
│                                          │
│            ◌ Loading documents...        │
│                                          │
└──────────────────────────────────────────┘

Spinner: Fluent UI spinner (20px)
Text: type.body, text.secondary
```

### 10.2 Empty Gallery

```
┌──────────────────────────────────────────┐
│                                          │
│       📄 No documents found              │
│                                          │
│    Try adjusting your filters or         │
│    check back later.                     │
│                                          │
└──────────────────────────────────────────┘

Icon: 48px, text.secondary at 50% opacity
Text: type.body, text.secondary
```

### 10.3 Empty Approvals

```
┌──────────────────────────────────────────┐
│                                          │
│       ✓ No pending approvals             │
│                                          │
│    You're all caught up!                 │
│                                          │
└──────────────────────────────────────────┘
```

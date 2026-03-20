// ═══════════════════════════════════════════════════════════════
// scrDashboard — Executive Dashboard (Home Screen)
// ═══════════════════════════════════════════════════════════════
// Visible to: All authenticated users with a recognised role
// Purpose: At-a-glance overview of workspace activity
// ═══════════════════════════════════════════════════════════════


// ─── Screen.OnVisible ────────────────────────────────────────
// Refresh data each time user navigates to Dashboard
Concurrent(
    Set(gblDraftCount, CountRows(Filter(DraftLib, ID > 0))),
    Set(gblReviewCount, CountRows(Filter(ReviewLib, ID > 0))),
    Set(gblApprovedCount, CountRows(Filter(ApprovedLib, ID > 0))),
    Set(gblArchiveCount, CountRows(Filter(ArchiveLib, ID > 0)))
);
Set(gblLastRefresh, Now());


// ─── Metrics Cards ───────────────────────────────────────────
// Four cards in a horizontal row: Draft, Review, Approved, Archive

// Card: Draft
// lblDraftCount.Text
Text(gblDraftCount)
// lblDraftLabel.Text
"Draft"
// rectDraftAccent.Fill (bottom border accent)
RGBA(0, 120, 212, 1)    // Blue

// Card: Review
// lblReviewCount.Text
Text(gblReviewCount)
// lblReviewLabel.Text
"Review"
// rectReviewAccent.Fill
RGBA(255, 185, 0, 1)    // Amber

// Card: Approved
// lblApprovedCount.Text
Text(gblApprovedCount)
// lblApprovedLabel.Text
"Approved"
// rectApprovedAccent.Fill
RGBA(16, 124, 16, 1)    // Green

// Card: Archive
// lblArchiveCount.Text
Text(gblArchiveCount)
// lblArchiveLabel.Text
"Archive"
// rectArchiveAccent.Fill
RGBA(115, 115, 115, 1)  // Grey


// ─── Upcoming Meetings Gallery ───────────────────────────────
// galUpcomingMeetings.Items
SortByColumns(
    AddColumns(
        GroupBy(
            Filter(
                ApprovedLib,
                ExecWS_MeetingDate >= Today()
            ),
            "ExecWS_MeetingCycle", "ExecWS_MeetingType", "ExecWS_MeetingDate",
            "PackDocs"
        ),
        "DocCount", CountRows(PackDocs)
    ),
    "ExecWS_MeetingDate", SortOrder.Ascending
)

// galUpcomingMeetings — Template controls:
// icoMeetingType.Icon
Switch(
    ThisItem.ExecWS_MeetingType.Value,
    "Board", Icon.People,
    "SteerCo", Icon.Waypoint,
    "ExecTeam", Icon.Group,
    Icon.Calendar
)
// lblMeetingCycle.Text
ThisItem.ExecWS_MeetingCycle
// lblMeetingDate.Text
Text(ThisItem.ExecWS_MeetingDate, "dd MMM yyyy")
// lblMeetingDocCount.Text
Concatenate(Text(ThisItem.DocCount), " docs")


// ─── Recent Approvals Gallery ────────────────────────────────
// NOTE: This gallery requires the Approvals connector.
// The exact API shape depends on the connector version available
// in your environment. The pattern below is illustrative.

// galRecentApprovals.Items
// Option 1: If Approvals connector exposes GetApprovals():
FirstN(
    SortByColumns(
        Filter(
            Approvals,
            Status <> "Pending"
        ),
        "CompletedDate", SortOrder.Descending
    ),
    10
)

// Option 2: If connector is not available, use a SharePoint list
// that the ReviewToApproved flow writes approval records to.
// This is the more reliable approach for cross-environment portability.

// galRecentApprovals — Template controls:
// icoApprovalResult.Icon
If(ThisItem.Status = "Approved", Icon.CheckMark, Icon.Cancel)
// icoApprovalResult.Color
If(ThisItem.Status = "Approved", RGBA(16, 124, 16, 1), RGBA(209, 52, 56, 1))
// lblApprovalDocName.Text
ThisItem.Title
// lblApprovalStatus.Text
ThisItem.Status
// lblApprovalDate.Text
Text(ThisItem.CompletedDate, "dd MMM yyyy")


// ─── Quick Action Buttons ────────────────────────────────────

// btnNewDocument
// .Visible
gblIsAuthor
// .OnSelect
Navigate(scrDocUpload, ScreenTransition.None)
// .Text
"+ New Document"
// .Fill
RGBA(0, 120, 212, 1)

// btnPendingReviews
// .Visible
gblIsReviewer
// .OnSelect
Navigate(scrApprovals, ScreenTransition.None)
// .Text
"Pending Reviews"
// .Fill
RGBA(255, 185, 0, 1)

// btnArchive
// .Visible
gblIsCompliance
// .OnSelect
Navigate(scrArchiveMgmt, ScreenTransition.None)
// .Text
"Archive Documents"
// .Fill
RGBA(115, 115, 115, 1)


// ─── Refresh Button ──────────────────────────────────────────
// btnRefresh.OnSelect
Concurrent(
    Set(gblDraftCount, CountRows(Filter(DraftLib, ID > 0))),
    Set(gblReviewCount, CountRows(Filter(ReviewLib, ID > 0))),
    Set(gblApprovedCount, CountRows(Filter(ApprovedLib, ID > 0))),
    Set(gblArchiveCount, CountRows(Filter(ArchiveLib, ID > 0)))
);
Set(gblLastRefresh, Now());
Notify("Dashboard refreshed", NotificationType.Information);

// lblLastRefresh.Text
Concatenate("Last updated: ", Text(gblLastRefresh, "HH:mm"))

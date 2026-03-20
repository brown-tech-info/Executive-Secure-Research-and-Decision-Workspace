// ═══════════════════════════════════════════════════════════════
// scrDocBrowser — Document Browser Screen
// ═══════════════════════════════════════════════════════════════
// Visible to: All authenticated users with a recognised role
// Purpose: Browse documents from libraries appropriate to user's role
// ═══════════════════════════════════════════════════════════════


// ─── Screen.OnVisible ────────────────────────────────────────
// Determine which library tabs to show based on role
Set(locShowDraft, gblIsAuthor || gblIsAdmin);
Set(locShowReview, gblIsReviewer || gblIsAuthor || gblIsAdmin);
Set(locShowApproved, gblIsExecutive || gblIsReviewer || gblIsCompliance || gblIsAdmin);
Set(locShowArchive, gblIsCompliance || gblIsAdmin);

// Default to the primary library for the user's role
Set(
    locActiveTab,
    If(
        gblIsAuthor, "Draft",
        gblIsReviewer, "Review",
        gblIsExecutive, "Approved",
        gblIsCompliance, "Approved",
        "Approved"
    )
);

// Reset filters
Set(locFilterMeetingType, Blank());
Set(locFilterDocType, Blank());
Set(locFilterDateFrom, Blank());
Set(locFilterDateTo, Blank());


// ─── Tab Controls ────────────────────────────────────────────
// tabDraft.Visible
locShowDraft
// tabDraft.OnSelect
Set(locActiveTab, "Draft")
// tabDraft.Fill
If(locActiveTab = "Draft", RGBA(0, 120, 212, 0.1), Transparent)
// tabDraft.Color
If(locActiveTab = "Draft", RGBA(0, 120, 212, 1), RGBA(96, 94, 92, 1))

// tabReview.Visible
locShowReview
// tabReview.OnSelect
Set(locActiveTab, "Review")

// tabApproved.Visible
locShowApproved
// tabApproved.OnSelect
Set(locActiveTab, "Approved")

// tabArchive.Visible
locShowArchive
// tabArchive.OnSelect
Set(locActiveTab, "Archive")


// ─── Filter Bar ──────────────────────────────────────────────
// drpFilterMeetingType.Items
["(All)", "Board", "SteerCo", "ExecTeam", "Ad-Hoc"]
// drpFilterMeetingType.OnChange
Set(locFilterMeetingType, If(Self.Selected.Value = "(All)", Blank(), Self.Selected.Value))

// drpFilterDocType.Items
["(All)", "Board Pack", "Research Summary", "Decision Record", "Meeting Minutes", "Supporting Material"]
// drpFilterDocType.OnChange
Set(locFilterDocType, If(Self.Selected.Value = "(All)", Blank(), Self.Selected.Value))

// dpFilterDateFrom.OnChange
Set(locFilterDateFrom, Self.SelectedDate)

// dpFilterDateTo.OnChange
Set(locFilterDateTo, Self.SelectedDate)

// btnClearFilters.OnSelect
Set(locFilterMeetingType, Blank());
Set(locFilterDocType, Blank());
Set(locFilterDateFrom, Blank());
Set(locFilterDateTo, Blank());
Reset(drpFilterMeetingType);
Reset(drpFilterDocType);
Reset(dpFilterDateFrom);
Reset(dpFilterDateTo);


// ─── Document Gallery ────────────────────────────────────────
// galDocuments.Items
// Uses delegation-safe filters for SharePoint (=, <, >, >=, <=)
With(
    {
        sourceLib:
            Switch(
                locActiveTab,
                "Draft", DraftLib,
                "Review", ReviewLib,
                "Approved", ApprovedLib,
                "Archive", ArchiveLib
            )
    },
    SortByColumns(
        Filter(
            sourceLib,
            // Meeting Type filter (delegable: equals)
            (IsBlank(locFilterMeetingType) || ExecWS_MeetingType.Value = locFilterMeetingType) &&
            // Document Type filter (delegable: equals)
            (IsBlank(locFilterDocType) || ExecWS_DocumentType = locFilterDocType) &&
            // Date range filter (delegable: >= and <=)
            (IsBlank(locFilterDateFrom) || ExecWS_MeetingDate >= locFilterDateFrom) &&
            (IsBlank(locFilterDateTo) || ExecWS_MeetingDate <= locFilterDateTo)
        ),
        "ExecWS_MeetingDate", SortOrder.Descending
    )
)


// ─── Gallery Template ────────────────────────────────────────
// Each gallery item renders the cmpDocGalleryItem pattern

// icoDocIcon.Icon
Icon.Document

// lblDocName.Text
ThisItem.{Name}

// cmpLifecycleBadge (component instance)
// Input: ThisItem.ExecWS_LifecycleState.Value
// Badge background:
Switch(
    ThisItem.ExecWS_LifecycleState.Value,
    "Draft", RGBA(0, 120, 212, 0.1),
    "Review", RGBA(255, 185, 0, 0.1),
    "Approved", RGBA(16, 124, 16, 0.1),
    "Archive", RGBA(115, 115, 115, 0.1)
)
// Badge text colour:
Switch(
    ThisItem.ExecWS_LifecycleState.Value,
    "Draft", RGBA(0, 120, 212, 1),
    "Review", RGBA(152, 111, 11, 1),
    "Approved", RGBA(16, 124, 16, 1),
    "Archive", RGBA(115, 115, 115, 1)
)

// lblDocType.Text
ThisItem.ExecWS_DocumentType

// lblDocMeetingType.Text
ThisItem.ExecWS_MeetingType.Value

// lblDocMeetingDate.Text
Text(ThisItem.ExecWS_MeetingDate, "dd MMM yyyy")

// lblDocOwner.Text
ThisItem.ExecWS_DocumentOwner.DisplayName

// icoChevron.Icon
Icon.ChevronRight


// ─── Gallery OnSelect ────────────────────────────────────────
// galDocuments.OnSelect
Set(locSelectedDoc, ThisItem);
Set(locSelectedDocLibrary, locActiveTab);
Navigate(scrDocDetail, ScreenTransition.None);


// ─── Results Count ───────────────────────────────────────────
// lblResultsCount.Text
Concatenate(
    "Showing ",
    Text(CountRows(galDocuments.AllItems)),
    " documents"
)

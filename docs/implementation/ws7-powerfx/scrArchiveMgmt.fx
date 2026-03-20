// ═══════════════════════════════════════════════════════════════
// scrArchiveMgmt — Archive Management Screen (Compliance)
// ═══════════════════════════════════════════════════════════════
// Visible to: Compliance, Admins
// Purpose: Trigger archival of approved docs, browse archive
// ═══════════════════════════════════════════════════════════════


// ─── Screen.OnVisible ────────────────────────────────────────
Set(locArchiveTab, "Eligible");
Set(locArchiveBusy, false);
Set(locSelectedForArchive, Blank());
ClearCollect(colSelectedDocs, Blank());
Clear(colSelectedDocs);


// ─── Tab Controls ────────────────────────────────────────────
// tabEligible.OnSelect
Set(locArchiveTab, "Eligible")
// tabEligible.Text
"Eligible for Archival"

// tabArchived.OnSelect
Set(locArchiveTab, "Archived")
// tabArchived.Text
"Archived"


// ─── Eligible Documents Gallery ──────────────────────────────
// galEligible.Visible
locArchiveTab = "Eligible"

// galEligible.Items
SortByColumns(
    Filter(
        ApprovedLib,
        ExecWS_LifecycleState.Value = "Approved"
    ),
    "ExecWS_MeetingDate", SortOrder.Descending
)

// galEligible — Template with checkbox selection:
// chkSelect — Checkbox control
// chkSelect.OnCheck
Collect(colSelectedDocs, ThisItem);
// chkSelect.OnUncheck
Remove(colSelectedDocs, LookUp(colSelectedDocs, ID = ThisItem.ID));

// lblEligibleDocName.Text
ThisItem.{Name}

// cmpLifecycleBadge
// Input: "Approved" (always green on this screen)

// lblEligibleDocType.Text
ThisItem.ExecWS_DocumentType

// lblEligibleMeetingInfo.Text
Concatenate(
    ThisItem.ExecWS_MeetingType.Value, " │ ",
    ThisItem.ExecWS_MeetingCycle, " │ ",
    Text(ThisItem.ExecWS_MeetingDate, "dd MMM yyyy")
)

// lblEligibleApprovedDate.Text
Concatenate("Approved: ", Text(ThisItem.Modified, "dd MMM yyyy"))


// ─── Selection Count & Archive Button ────────────────────────
// lblSelectionCount.Text
Concatenate(Text(CountRows(colSelectedDocs)), " document(s) selected")
// lblSelectionCount.Visible
CountRows(colSelectedDocs) > 0

// btnArchiveSelected.Text
Concatenate("Archive Selected (", Text(CountRows(colSelectedDocs)), ") →")
// btnArchiveSelected.Visible
CountRows(colSelectedDocs) > 0
// btnArchiveSelected.Fill
RGBA(115, 115, 115, 1)
// btnArchiveSelected.Color
RGBA(255, 255, 255, 1)
// btnArchiveSelected.DisplayMode
If(
    locArchiveBusy || CountRows(colSelectedDocs) = 0,
    DisplayMode.Disabled,
    DisplayMode.Edit
)

// btnArchiveSelected.OnSelect
// Show confirmation dialog before proceeding
Set(locShowArchiveConfirm, true);


// ─── Archive Confirmation Dialog ─────────────────────────────
// pnlArchiveConfirm.Visible
locShowArchiveConfirm

// lblConfirmTitle.Text
"Confirm Archive"

// lblConfirmMessage.Text
Concatenate(
    "You are about to archive ",
    Text(CountRows(colSelectedDocs)),
    " document(s). Archived documents will be moved to the Archive library ",
    "with a 7-year retention label applied. This action cannot be undone."
)

// btnConfirmArchive.Text
"Archive"
// btnConfirmArchive.Fill
RGBA(209, 52, 56, 1)   // Red to emphasise irreversibility

// btnConfirmArchive.OnSelect
Set(locShowArchiveConfirm, false);
Set(locArchiveBusy, true);

// Process each selected document
ForAll(
    colSelectedDocs,
    IfError(
        // Trigger the ApprovedToArchive flow for each document
        ExecWSApprovedToArchive.Run(
            {
                documentId: Text(ID),
                documentName: '{Name}'
            }
        ),
        // Log error but continue processing remaining docs
        Notify(
            Concatenate("Failed to archive '", '{Name}', "': ", FirstError.Message),
            NotificationType.Error
        );
    )
);

Set(locArchiveBusy, false);
Clear(colSelectedDocs);

Notify(
    "Archive process started for selected documents. They will move to Archive shortly.",
    NotificationType.Success
);

// Refresh the gallery
Refresh(ApprovedLib);

// btnCancelArchive.Text
"Cancel"
// btnCancelArchive.OnSelect
Set(locShowArchiveConfirm, false);


// ─── Warning Banner ──────────────────────────────────────────
// lblArchiveWarning.Text
"⚠ Archived documents will be moved to the Archive library with a 7-year retention label applied."
// lblArchiveWarning.Visible
locArchiveTab = "Eligible"
// lblArchiveWarning.Fill
RGBA(255, 244, 206, 1)  // Light amber background
// lblArchiveWarning.Color
RGBA(152, 111, 11, 1)   // Dark amber text


// ─── Archived Documents Gallery ──────────────────────────────
// galArchived.Visible
locArchiveTab = "Archived"

// galArchived.Items
SortByColumns(
    ArchiveLib,
    "Modified", SortOrder.Descending
)

// galArchived — Template (read-only, no checkboxes):
// lblArchivedDocName.Text
ThisItem.{Name}

// cmpLifecycleBadge
// Input: "Archive" (always grey)

// lblArchivedMeetingCycle.Text
ThisItem.ExecWS_MeetingCycle

// lblArchivedDate.Text
Concatenate("Archived: ", Text(ThisItem.Modified, "dd MMM yyyy"))

// lblArchivedRetention.Text
// NOTE: Retention label information is set by Purview and may not be
// directly accessible via the SharePoint connector. Display the
// standard label text based on the known policy.
"Retention: 7 years (ExecWS-Archive-7Year)"

// lblArchivedDocType.Text
ThisItem.ExecWS_DocumentType


// ─── Empty States ────────────────────────────────────────────
// lblNoEligible.Visible
locArchiveTab = "Eligible" && CountRows(galEligible.AllItems) = 0
// lblNoEligible.Text
"No documents currently eligible for archival."

// lblNoArchived.Visible
locArchiveTab = "Archived" && CountRows(galArchived.AllItems) = 0
// lblNoArchived.Text
"No archived documents found."

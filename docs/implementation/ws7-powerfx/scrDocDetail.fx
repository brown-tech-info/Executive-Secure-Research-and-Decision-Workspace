// ═══════════════════════════════════════════════════════════════
// scrDocDetail — Document Detail View
// ═══════════════════════════════════════════════════════════════
// Visible to: All authenticated users (actions vary by role)
// Purpose: Full document metadata, version history, lifecycle actions
// Context: locSelectedDoc and locSelectedDocLibrary set by scrDocBrowser
// ═══════════════════════════════════════════════════════════════


// ─── Screen.OnVisible ────────────────────────────────────────
// Determine available actions based on document state and user role
Set(
    locCanSubmitForReview,
    gblIsAuthor && locSelectedDocLibrary = "Draft" &&
    locSelectedDoc.ExecWS_LifecycleState.Value = "Draft"
);
Set(
    locCanApprove,
    gblIsReviewer && locSelectedDocLibrary = "Review" &&
    locSelectedDoc.ExecWS_LifecycleState.Value = "Review"
);
Set(
    locCanArchive,
    gblIsCompliance && locSelectedDocLibrary = "Approved" &&
    locSelectedDoc.ExecWS_LifecycleState.Value = "Approved"
);

Set(locActionBusy, false);
Set(locShowRejectComments, false);


// ─── Header ──────────────────────────────────────────────────
// lblDocTitle.Text
locSelectedDoc.{Name}

// cmpLifecycleBadge
// Input: locSelectedDoc.ExecWS_LifecycleState.Value
// (See component definition in scrDocBrowser.fx for colour logic)


// ─── Metadata Display ────────────────────────────────────────
// Two-column metadata grid

// lblMetaDocType.Text
locSelectedDoc.ExecWS_DocumentType

// lblMetaMeetingType.Text
locSelectedDoc.ExecWS_MeetingType.Value

// lblMetaMeetingDate.Text
Text(locSelectedDoc.ExecWS_MeetingDate, "dd MMM yyyy")

// lblMetaMeetingCycle.Text
locSelectedDoc.ExecWS_MeetingCycle

// lblMetaDecisionId.Text
locSelectedDoc.ExecWS_MeetingDecisionId

// lblMetaPackVersion.Text
Concatenate("v", Text(locSelectedDoc.ExecWS_PackVersion))

// lblMetaSensitivity.Text
locSelectedDoc.ExecWS_SensitivityClassification.Value

// lblMetaOwner.Text
locSelectedDoc.ExecWS_DocumentOwner.DisplayName

// lblMetaCreated.Text
Text(locSelectedDoc.Created, "dd MMM yyyy HH:mm")

// lblMetaModified.Text
Text(locSelectedDoc.Modified, "dd MMM yyyy HH:mm")


// ─── Version History Gallery ─────────────────────────────────
// galVersionHistory.Items
// NOTE: SharePoint connector's GetFileVersions may not be directly
// available in Canvas Apps. Alternative approach: use the SharePoint
// REST API via Power Automate flow, or use the built-in version
// history that SharePoint surfaces in the file's info panel.
//
// If direct access is available:
SortByColumns(
    SharePoint.GetFileVersions(
        locSelectedDoc.{Link},
        locSelectedDoc.ID
    ),
    "Created", SortOrder.Descending
)

// galVersionHistory Template:
// lblVersionNumber.Text
ThisItem.VersionLabel
// lblVersionDate.Text
Text(ThisItem.Created, "dd MMM yyyy HH:mm")
// lblVersionAuthor.Text
ThisItem.CreatedBy.DisplayName
// lblVersionComment.Text
ThisItem.CheckInComment


// ─── Action: Submit for Review ───────────────────────────────
// btnSubmitForReview.Visible
locCanSubmitForReview
// btnSubmitForReview.Text
"Submit for Review"
// btnSubmitForReview.Fill
RGBA(0, 120, 212, 1)
// btnSubmitForReview.DisplayMode
If(locActionBusy, DisplayMode.Disabled, DisplayMode.Edit)

// btnSubmitForReview.OnSelect
Set(locActionBusy, true);

IfError(
    Patch(
        DraftLib,
        locSelectedDoc,
        { ExecWS_LifecycleState: {Value: "Review"} }
    ),
    Set(locActionBusy, false);
    Notify("Failed to submit for review: " & FirstError.Message, NotificationType.Error);
);

Set(locActionBusy, false);
Notify(
    "Document submitted for review. It will move to the Review library within 2 minutes.",
    NotificationType.Success
);
Navigate(scrDocBrowser, ScreenTransition.None);


// ─── Action: Approve ─────────────────────────────────────────
// btnApprove.Visible
locCanApprove
// btnApprove.Text
"Approve"
// btnApprove.Fill
RGBA(16, 124, 16, 1)
// btnApprove.DisplayMode
If(locActionBusy, DisplayMode.Disabled, DisplayMode.Edit)

// btnApprove.OnSelect
// The approval must go through the Approvals connector to maintain audit trail.
// The ReviewToApproved flow creates an approval task. The app responds to that task.
//
// Step 1: Find the pending approval for this document
Set(
    locPendingApproval,
    LookUp(
        Filter(
            Approvals,
            Status = "Pending" && StartsWith(Title, locSelectedDoc.{Name})
        )
    )
);

If(
    IsBlank(locPendingApproval),
    Notify(
        "No pending approval task found for this document. The review flow may not have created one yet — please try again in a few minutes.",
        NotificationType.Warning
    ),

    Set(locActionBusy, true);
    IfError(
        // Respond to the approval task
        'ApprovalConnector'.RespondToApproval(
            locPendingApproval.ID,
            {
                response: "Approve",
                comments: If(IsBlank(txtApprovalComments.Text), "Approved via ExecWorkspace app", txtApprovalComments.Text)
            }
        ),
        Set(locActionBusy, false);
        Notify("Failed to submit approval: " & FirstError.Message, NotificationType.Error);
    );

    Set(locActionBusy, false);
    Notify("Document approved. It will move to the Approved library shortly.", NotificationType.Success);
    Navigate(scrDocBrowser, ScreenTransition.None);
);


// ─── Action: Reject ──────────────────────────────────────────
// btnReject.Visible
locCanApprove
// btnReject.Text
"Reject"
// btnReject.Fill
RGBA(209, 52, 56, 1)

// btnReject.OnSelect
// Show rejection comments input before submitting
Set(locShowRejectComments, true);

// btnConfirmReject.OnSelect (inside rejection panel)
If(
    IsBlank(Trim(txtRejectionComments.Text)),
    Notify("Please provide rejection comments.", NotificationType.Error),

    Set(locActionBusy, true);

    Set(
        locPendingApproval,
        LookUp(
            Filter(
                Approvals,
                Status = "Pending" && StartsWith(Title, locSelectedDoc.{Name})
            )
        )
    );

    If(
        IsBlank(locPendingApproval),
        Notify("No pending approval task found.", NotificationType.Warning),

        IfError(
            'ApprovalConnector'.RespondToApproval(
                locPendingApproval.ID,
                {
                    response: "Reject",
                    comments: txtRejectionComments.Text
                }
            ),
            Set(locActionBusy, false);
            Notify("Failed to submit rejection: " & FirstError.Message, NotificationType.Error);
        );

        Set(locActionBusy, false);
        Notify(
            "Document rejected. It will return to Draft with your comments.",
            NotificationType.Warning
        );
        Navigate(scrDocBrowser, ScreenTransition.None);
    );
);

// txtApprovalComments — optional comments for approval
// txtRejectionComments — mandatory comments for rejection
// txtRejectionComments hint text: "Explain why this document is being rejected..."

// Rejection comments panel
// pnlRejectComments.Visible
locShowRejectComments

// btnCancelReject.OnSelect
Set(locShowRejectComments, false);


// ─── Action: Archive ─────────────────────────────────────────
// btnArchive.Visible
locCanArchive
// btnArchive.Text
"Archive"
// btnArchive.Fill
RGBA(115, 115, 115, 1)

// btnArchive.OnSelect
Set(locActionBusy, true);

IfError(
    // Trigger the ExecWS-ApprovedToArchive flow via Power Automate connector
    ExecWSApprovedToArchive.Run(
        {
            documentId: Text(locSelectedDoc.ID),
            documentName: locSelectedDoc.{Name}
        }
    ),
    Set(locActionBusy, false);
    Notify("Failed to start archive process: " & FirstError.Message, NotificationType.Error);
);

Set(locActionBusy, false);
Notify(
    "Archive process started. The document will move to Archive shortly.",
    NotificationType.Success
);
Navigate(scrDocBrowser, ScreenTransition.None);


// ─── Open in SharePoint ──────────────────────────────────────
// btnOpenInSP.OnSelect
Launch(locSelectedDoc.{Link})
// btnOpenInSP.Text
"Open in SharePoint ↗"


// ─── Back Button ─────────────────────────────────────────────
// btnBack.OnSelect
Back()
// btnBack.Text
"← Back"

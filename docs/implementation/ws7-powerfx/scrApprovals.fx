// ═══════════════════════════════════════════════════════════════
// scrApprovals — Approvals Centre Screen (Reviewers)
// ═══════════════════════════════════════════════════════════════
// Visible to: Reviewers, Admins
// Purpose: View and respond to pending approval tasks, view history
// ═══════════════════════════════════════════════════════════════


// ─── Screen.OnVisible ────────────────────────────────────────
Set(locApprovalsTab, "Pending");
Set(locApprovalBusy, false);


// ─── Tab Controls ────────────────────────────────────────────
// tabPending.OnSelect
Set(locApprovalsTab, "Pending")
// tabPending.Fill
If(locApprovalsTab = "Pending", RGBA(0, 120, 212, 0.1), Transparent)

// tabHistory.OnSelect
Set(locApprovalsTab, "History")
// tabHistory.Fill
If(locApprovalsTab = "History", RGBA(0, 120, 212, 0.1), Transparent)


// ─── Pending Approvals Gallery ───────────────────────────────
// galPendingApprovals.Visible
locApprovalsTab = "Pending"

// galPendingApprovals.Items
// NOTE: The Approvals connector surface may vary by environment.
// This pattern assumes the standard Approvals connector is available.
//
// Filter for pending approvals assigned to the current user
Filter(
    Approvals,
    Status = "Pending" &&
    Responder = gblUserEmail
)

// If the Approvals connector doesn't expose a native table,
// use a Power Automate flow to fetch pending approvals:
// ExecWSGetPendingApprovals.Run(gblUserId).pendingApprovals

// galPendingApprovals — Template:
// ┌────────────────────────────────────────────────────┐
// │ 📋 [Title]                              ⏳ PENDING │
// │ Submitted by: [Requestor]  │  [RequestDate]       │
// │ Meeting: [MeetingType] - [MeetingCycle]            │
// │                                                    │
// │ Comments: [________________________]               │
// │                                                    │
// │ [✓ Approve]  [✗ Reject]                           │
// └────────────────────────────────────────────────────┘

// lblApprovalTitle.Text
ThisItem.Title

// lblApprovalRequestor.Text
Concatenate("Submitted by: ", ThisItem.Requestor.DisplayName)

// lblApprovalDate.Text
Text(ThisItem.CreatedDate, "dd MMM yyyy HH:mm")

// lblApprovalMeetingContext.Text
// Extract meeting context from the approval title or custom properties
// The ReviewToApproved flow should include meeting type/cycle in the approval title
ThisItem.Details

// txtInlineComments — text input per gallery item
// .HintText
"Add comments (required for rejection)..."

// btnInlineApprove.Text
"✓ Approve"
// btnInlineApprove.Fill
RGBA(16, 124, 16, 1)
// btnInlineApprove.Color
RGBA(255, 255, 255, 1)
// btnInlineApprove.DisplayMode
If(locApprovalBusy, DisplayMode.Disabled, DisplayMode.Edit)

// btnInlineApprove.OnSelect
Set(locApprovalBusy, true);
IfError(
    'ApprovalConnector'.RespondToApproval(
        ThisItem.ID,
        {
            response: "Approve",
            comments: If(
                IsBlank(txtInlineComments.Text),
                "Approved via ExecWorkspace app",
                txtInlineComments.Text
            )
        }
    ),
    Set(locApprovalBusy, false);
    Notify("Approval failed: " & FirstError.Message, NotificationType.Error);
);

Set(locApprovalBusy, false);
Notify(
    Concatenate("'", ThisItem.Title, "' approved successfully."),
    NotificationType.Success
);
// Refresh the gallery to remove the approved item
Refresh(Approvals);

// btnInlineReject.Text
"✗ Reject"
// btnInlineReject.Fill
RGBA(209, 52, 56, 1)
// btnInlineReject.Color
RGBA(255, 255, 255, 1)
// btnInlineReject.DisplayMode
If(locApprovalBusy, DisplayMode.Disabled, DisplayMode.Edit)

// btnInlineReject.OnSelect
If(
    IsBlank(Trim(txtInlineComments.Text)),
    Notify("Please provide rejection comments before rejecting.", NotificationType.Error),

    Set(locApprovalBusy, true);
    IfError(
        'ApprovalConnector'.RespondToApproval(
            ThisItem.ID,
            {
                response: "Reject",
                comments: txtInlineComments.Text
            }
        ),
        Set(locApprovalBusy, false);
        Notify("Rejection failed: " & FirstError.Message, NotificationType.Error);
    );

    Set(locApprovalBusy, false);
    Notify(
        Concatenate("'", ThisItem.Title, "' rejected. Comments sent to author."),
        NotificationType.Warning
    );
    Refresh(Approvals);
);


// ─── History Gallery ─────────────────────────────────────────
// galApprovalHistory.Visible
locApprovalsTab = "History"

// galApprovalHistory.Items
SortByColumns(
    Filter(
        Approvals,
        Status <> "Pending" &&
        Responder = gblUserEmail
    ),
    "CompletedDate", SortOrder.Descending
)

// galApprovalHistory — Template:
// lblHistoryTitle.Text
ThisItem.Title

// lblHistoryOutcome.Text
ThisItem.Status

// lblHistoryOutcome.Color
If(
    ThisItem.Status = "Approved",
    RGBA(16, 124, 16, 1),
    RGBA(209, 52, 56, 1)
)

// icoHistoryOutcome.Icon
If(ThisItem.Status = "Approved", Icon.CheckMark, Icon.Cancel)

// lblHistoryApprover.Text
ThisItem.Responder.DisplayName

// lblHistoryDate.Text
Text(ThisItem.CompletedDate, "dd MMM yyyy HH:mm")

// lblHistoryComments.Text
ThisItem.ResponseComments


// ─── Empty State ─────────────────────────────────────────────
// lblNoPending.Visible
locApprovalsTab = "Pending" && CountRows(galPendingApprovals.AllItems) = 0
// lblNoPending.Text
"✓ No pending approvals — you're all caught up!"

// lblNoHistory.Visible
locApprovalsTab = "History" && CountRows(galApprovalHistory.AllItems) = 0
// lblNoHistory.Text
"No approval history found."

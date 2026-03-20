// ═══════════════════════════════════════════════════════════════
// scrDocUpload — Document Upload Screen (Authors Only)
// ═══════════════════════════════════════════════════════════════
// Visible to: Authors, Admins
// Purpose: Upload documents to Draft library with metadata
// ═══════════════════════════════════════════════════════════════


// ─── Screen.OnVisible ────────────────────────────────────────
// Reset form state
Set(locUploadBusy, false);
Set(locUploadSuccess, false);
Reset(attFileUpload);
Reset(drpDocumentType);
Reset(drpMeetingType);
Reset(dpMeetingDate);
Reset(txtShortTitle);
Reset(drpSensitivity);
Set(locPackVersion, 1);
Set(locDerivedFileName, "");
Set(locDerivedMeetingCycle, "");
Set(locDerivedDecisionId, "");


// ─── File Attachment ─────────────────────────────────────────
// attFileUpload: AddMediaButton control
// attFileUpload.MaxAttachments
1
// attFileUpload.MaxAttachmentSize
25000000   // 25MB

// lblFileName.Text
If(
    CountRows(attFileUpload.Attachments) > 0,
    Concatenate(
        First(attFileUpload.Attachments).Name,
        " (",
        Text(RoundUp(First(attFileUpload.Attachments).Size / 1024 / 1024, 1)),
        " MB)"
    ),
    "No file selected"
)


// ─── Metadata Form Controls ─────────────────────────────────

// drpDocumentType.Items
["Board Pack", "Research Summary", "Decision Record", "Meeting Minutes", "Supporting Material"]

// drpMeetingType.Items
["Board", "SteerCo", "ExecTeam", "Ad-Hoc"]

// dpMeetingDate.DefaultDate
Today()

// drpSensitivity.Items
["Confidential – Executive", "Highly Confidential – Board"]
// drpSensitivity.Default
"Confidential – Executive"

// txtPackVersion.Default
"1"


// ─── Auto-Derived Fields ─────────────────────────────────────
// These update in real-time as the user fills in metadata

// lblDerivedMeetingCycle.Text — auto-computed meeting cycle
Set(
    locDerivedMeetingCycle,
    If(
        IsBlank(drpMeetingType.Selected),
        "",
        Switch(
            drpMeetingType.Selected.Value,
            "Board",
            Concatenate("BOARD-", Text(dpMeetingDate.SelectedDate, "yyyy-MM")),
            "SteerCo",
            Concatenate("STEERCO-", Text(dpMeetingDate.SelectedDate, "yyyy"), "-W", Text(WeekNum(dpMeetingDate.SelectedDate))),
            "ExecTeam",
            Concatenate("EXECTEAM-", Text(dpMeetingDate.SelectedDate, "yyyy"), "-W", Text(WeekNum(dpMeetingDate.SelectedDate))),
            "Ad-Hoc",
            Concatenate("ADHOC-", Text(dpMeetingDate.SelectedDate, "yyyy-MM-dd"))
        )
    )
);

// lblDerivedDecisionId.Text — auto-computed pack ID
// In production, query Draft library to auto-increment the NNN suffix.
// For simplicity, default to 001.
Set(
    locDerivedDecisionId,
    If(
        IsBlank(locDerivedMeetingCycle),
        "",
        With(
            {
                existingCount: CountRows(
                    Filter(
                        DraftLib,
                        ExecWS_MeetingCycle = locDerivedMeetingCycle
                    )
                )
            },
            Concatenate(
                locDerivedMeetingCycle,
                "-",
                Text(existingCount + 1, "000")
            )
        )
    )
);

// lblDerivedFileName.Text — auto-generated filename
Set(
    locDerivedFileName,
    If(
        IsBlank(drpMeetingType.Selected) || IsBlank(drpDocumentType.Selected) || IsBlank(txtShortTitle.Text),
        "(Complete the form to preview filename)",
        Concatenate(
            Upper(drpMeetingType.Selected.Value), "-",
            Text(dpMeetingDate.SelectedDate, "yyyy-MM"), "-",
            Substitute(drpDocumentType.Selected.Value, " ", ""), "-",
            Substitute(Trim(txtShortTitle.Text), " ", "")
        )
    )
);

// NOTE: Bind the above Set() calls to drpMeetingType.OnChange,
// dpMeetingDate.OnChange, drpDocumentType.OnChange, and
// txtShortTitle.OnChange for real-time updates.


// ─── Validation ──────────────────────────────────────────────
// locFormValid — computed on every change
Set(
    locFormValid,
    CountRows(attFileUpload.Attachments) > 0 &&
    !IsBlank(drpDocumentType.Selected) &&
    !IsBlank(drpMeetingType.Selected) &&
    !IsBlank(dpMeetingDate.SelectedDate) &&
    !IsBlank(Trim(txtShortTitle.Text))
);

// Validation indicators per field
// lblDocTypeError.Visible
IsBlank(drpDocumentType.Selected) && locUploadAttempted
// lblMeetingTypeError.Visible
IsBlank(drpMeetingType.Selected) && locUploadAttempted
// lblShortTitleError.Visible
IsBlank(Trim(txtShortTitle.Text)) && locUploadAttempted
// lblFileError.Visible
CountRows(attFileUpload.Attachments) = 0 && locUploadAttempted


// ─── Upload Button ───────────────────────────────────────────
// btnUpload.Text
"Upload to Draft"
// btnUpload.DisplayMode
If(locUploadBusy, DisplayMode.Disabled, DisplayMode.Edit)
// btnUpload.Fill
If(locFormValid, RGBA(0, 120, 212, 1), RGBA(200, 200, 200, 1))

// btnUpload.OnSelect
Set(locUploadAttempted, true);

If(
    !locFormValid,
    Notify("Please complete all required fields.", NotificationType.Error),

    // Begin upload
    Set(locUploadBusy, true);

    // Determine file extension from original file
    With(
        {
            fileExt: Last(Split(First(attFileUpload.Attachments).Name, ".")).Value,
            targetFileName: Concatenate(locDerivedFileName, ".", Last(Split(First(attFileUpload.Attachments).Name, ".")).Value)
        },

        // Step 1: Upload file to Draft library
        IfError(
            Set(
                locUploadedFile,
                Patch(
                    DraftLib,
                    Defaults(DraftLib),
                    {
                        '{Name}': targetFileName,
                        '{Content}': First(attFileUpload.Attachments).Value
                    }
                )
            ),
            // Upload failed
            Set(locUploadBusy, false);
            Notify(
                Concatenate("Upload failed: ", FirstError.Message),
                NotificationType.Error
            );
        );

        // Step 2: Set metadata on uploaded file
        If(
            !IsBlank(locUploadedFile),
            IfError(
                Patch(
                    DraftLib,
                    locUploadedFile,
                    {
                        ExecWS_LifecycleState: {Value: "Draft"},
                        ExecWS_DocumentType: drpDocumentType.Selected.Value,
                        ExecWS_MeetingType: drpMeetingType.Selected,
                        ExecWS_MeetingDate: dpMeetingDate.SelectedDate,
                        ExecWS_MeetingCycle: locDerivedMeetingCycle,
                        ExecWS_MeetingDecisionId: locDerivedDecisionId,
                        ExecWS_PackVersion: Value(txtPackVersion.Text),
                        ExecWS_SensitivityClassification: drpSensitivity.Selected,
                        ExecWS_DocumentOwner: {
                            '@odata.type': "#Microsoft.Azure.Connectors.SharePoint.SPListExpandedUser",
                            Claims: Concatenate("i:0#.f|membership|", gblUserEmail),
                            DisplayName: gblUserDisplayName,
                            Email: gblUserEmail
                        }
                    }
                ),
                // Metadata patch failed
                Set(locUploadBusy, false);
                Notify(
                    "Document uploaded but metadata could not be set. Please update metadata in SharePoint.",
                    NotificationType.Warning
                );
                Navigate(scrDocBrowser, ScreenTransition.None);
            );

            // Success
            Set(locUploadBusy, false);
            Notify("Document uploaded successfully to Draft library.", NotificationType.Success);
            Navigate(scrDocBrowser, ScreenTransition.None);
        );
    );
);


// ─── Cancel Button ───────────────────────────────────────────
// btnCancel.OnSelect
Navigate(scrDocBrowser, ScreenTransition.None)
// btnCancel.Text
"Cancel"

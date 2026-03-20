// ═══════════════════════════════════════════════════════════════
// ExecWorkspace Canvas App — App.OnStart (Role Detection)
// ═══════════════════════════════════════════════════════════════
// This formula executes when the app launches.
// It resolves the signed-in user's Entra ID group memberships
// and sets global role flags that control screen visibility and
// action availability throughout the app.
//
// DEPENDENCIES:
//   - Office365Users connector (delegated)
//   - Power Automate connector (for role detection flow)
//   - Environment variables for group Object IDs
//
// ALTERNATIVE APPROACHES:
//   Option A: Direct connector (below) — simpler but slower, 2000-member limit
//   Option B: Helper flow — faster, no member limit, recommended for production
// ═══════════════════════════════════════════════════════════════

// ─── Option A: Direct Connector Approach ─────────────────────
// Use this for dev tenant with small groups (<100 members).
// Performs 5 API calls on app start.

// 1. Get current user profile
Set(gblCurrentUser, Office365Users.MyProfileV2());
Set(gblUserDisplayName, gblCurrentUser.displayName);
Set(gblUserEmail, gblCurrentUser.mail);
Set(gblUserId, gblCurrentUser.id);

// 2. Check membership in each workspace group
// Uses Office365Users.CheckMemberGroups which is more efficient
// than listing all group members
Set(
    gblMembershipCheck,
    Office365Users.HttpRequest(
        Concatenate(
            "https://graph.microsoft.com/v1.0/me/checkMemberGroups"
        ),
        "POST",
        JSON(
            {
                groupIds: [
                    LookUp(EnvironmentVariableValues, SchemaName = "env_AuthorsGroupId").Value,
                    LookUp(EnvironmentVariableValues, SchemaName = "env_ReviewersGroupId").Value,
                    LookUp(EnvironmentVariableValues, SchemaName = "env_ExecutivesGroupId").Value,
                    LookUp(EnvironmentVariableValues, SchemaName = "env_ComplianceGroupId").Value,
                    LookUp(EnvironmentVariableValues, SchemaName = "env_AdminsGroupId").Value
                ]
            }
        )
    )
);

// NOTE: The HttpRequest approach above requires the Office365Users connector
// to have Group.Read.All consent. If this is unavailable, use the helper flow
// approach (Option B) instead.

// ─── Option B: Helper Flow Approach (Recommended) ────────────
// Call a lightweight Power Automate flow that checks group membership
// via Graph API and returns a JSON array of matched group names.
// This is faster (single HTTP call from app) and avoids the
// 2000-member limit on ListGroupMembers.
//
// Flow name: ExecWS-CheckUserRoles
// Input: User Object ID
// Output: JSON array of role names e.g. ["Author", "Executive"]

Set(
    gblUserRoles,
    ExecWSCheckUserRoles.Run(gblUserId).roles
);

Set(gblIsAuthor, "Author" in gblUserRoles);
Set(gblIsReviewer, "Reviewer" in gblUserRoles);
Set(gblIsExecutive, "Executive" in gblUserRoles);
Set(gblIsCompliance, "Compliance" in gblUserRoles);
Set(gblIsAdmin, "Admin" in gblUserRoles);

// 3. Determine if user has any recognised role
Set(
    gblHasRole,
    gblIsAuthor || gblIsReviewer || gblIsExecutive || gblIsCompliance || gblIsAdmin
);

// 4. Set the user's primary role (for display purposes)
Set(
    gblPrimaryRole,
    If(
        gblIsAdmin, "Platform Admin",
        gblIsExecutive, "Executive",
        gblIsReviewer, "Reviewer",
        gblIsAuthor, "Author",
        gblIsCompliance, "Compliance",
        "No Access"
    )
);

// 5. Load dashboard data if user has access
If(
    gblHasRole,

    // Document counts per library (for dashboard metrics cards)
    // Use CountRows with delegated filter for performance
    Concurrent(
        Set(gblDraftCount, CountRows(Filter(DraftLib, ID > 0))),
        Set(gblReviewCount, CountRows(Filter(ReviewLib, ID > 0))),
        Set(gblApprovedCount, CountRows(Filter(ApprovedLib, ID > 0))),
        Set(gblArchiveCount, CountRows(Filter(ArchiveLib, ID > 0))),

        // Upcoming meetings (next 5 by meeting date)
        Set(
            gblUpcomingMeetings,
            FirstN(
                SortByColumns(
                    Filter(
                        ApprovedLib,
                        ExecWS_MeetingDate >= Today()
                    ),
                    "ExecWS_MeetingDate", SortOrder.Ascending
                ),
                5
            )
        ),

        // Current month's meeting cycles
        Set(
            gblCurrentCyclePacks,
            Filter(
                ApprovedLib,
                ExecWS_MeetingDate >= DateAdd(Today(), -Day(Today()) + 1, TimeUnit.Days) &&
                ExecWS_MeetingDate < DateAdd(DateAdd(Today(), -Day(Today()) + 1, TimeUnit.Days), 1, TimeUnit.Months)
            )
        )
    );

    // Navigate to Dashboard
    Navigate(scrDashboard, ScreenTransition.None),

    // No access — show fallback screen
    Navigate(scrNoAccess, ScreenTransition.None)
);


// ═══════════════════════════════════════════════════════════════
// App.OnError — Global error handler
// ═══════════════════════════════════════════════════════════════

If(
    FirstError.Kind = ErrorKind.Network,
    Notify(
        "Network error — please check your connection and try again.",
        NotificationType.Error
    ),
    FirstError.Kind = ErrorKind.Permission,
    Notify(
        "You don't have permission to perform this action.",
        NotificationType.Error
    ),
    Notify(
        Concatenate("An error occurred: ", FirstError.Message),
        NotificationType.Error
    )
);

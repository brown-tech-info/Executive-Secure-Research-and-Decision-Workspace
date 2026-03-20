// ═══════════════════════════════════════════════════════════════
// cmpNavPanel — Reusable Navigation Panel Component
// ═══════════════════════════════════════════════════════════════
// Used on: All screens except scrNoAccess
// Purpose: Persistent left-side navigation with role-based items
// ═══════════════════════════════════════════════════════════════
//
// COMPONENT SETUP:
// In Power Apps Studio: Component Library → New Component → "cmpNavPanel"
// Custom properties:
//   - ActiveScreen (Input, Text): The name of the current screen
//   - OnNavigate (Output, Action): Navigation event


// ─── Component Properties ────────────────────────────────────
// .Width
220
// .Height
Parent.Height
// .Fill
RGBA(0, 69, 120, 1)  // #004578 — dark blue


// ─── Brand / Logo Area ───────────────────────────────────────
// rectBrandArea (Rectangle)
// .Y = 0, .Height = 80
// .Fill = RGBA(0, 53, 93, 1)  // Slightly darker for brand area

// lblBrandTitle.Text
"EXEC" & Char(10) & "WORKSPACE"
// lblBrandTitle.Color
RGBA(255, 255, 255, 1)
// lblBrandTitle.Size
16
// lblBrandTitle.FontWeight
FontWeight.Semibold
// lblBrandTitle.Y
16
// lblBrandTitle.X
16


// ─── Navigation Items ────────────────────────────────────────
// Each nav item consists of: icon + label + active indicator + touch target

// Helper function for nav item styling
// (Apply these properties to each nav button)

// TEMPLATE for each nav button:
// .Height = 48
// .Width = 220
// .PaddingLeft = 16
// .Align = Align.Left
// .Color = If(cmpNavPanel.ActiveScreen = "<screen>", RGBA(255,255,255,1), RGBA(255,255,255,0.7))
// .Fill = If(cmpNavPanel.ActiveScreen = "<screen>", RGBA(255,255,255,0.1), Transparent)
// .HoverFill = RGBA(255,255,255,0.05)

// Active indicator (thin left border per item):
// rectActiveIndicator.Visible = cmpNavPanel.ActiveScreen = "<screen>"
// rectActiveIndicator.Fill = RGBA(0, 120, 212, 1)  // theme.primary
// rectActiveIndicator.Width = 3
// rectActiveIndicator.Height = 48
// rectActiveIndicator.X = 0


// Nav Item 1: Dashboard
// btnNavDashboard.Text
"  🏠  Dashboard"
// btnNavDashboard.Visible
true
// btnNavDashboard.Y
96
// btnNavDashboard.OnSelect
Navigate(scrDashboard, ScreenTransition.None)

// Nav Item 2: Documents
// btnNavDocuments.Text
"  📄  Documents"
// btnNavDocuments.Visible
true
// btnNavDocuments.Y
144
// btnNavDocuments.OnSelect
Navigate(scrDocBrowser, ScreenTransition.None)

// Nav Item 3: Upload
// btnNavUpload.Text
"  ⬆️  Upload"
// btnNavUpload.Visible
gblIsAuthor || gblIsAdmin
// btnNavUpload.Y
192
// btnNavUpload.OnSelect
Navigate(scrDocUpload, ScreenTransition.None)

// Nav Item 4: Approvals
// btnNavApprovals.Text
"  ✅  Approvals"
// btnNavApprovals.Visible
gblIsReviewer || gblIsAdmin
// btnNavApprovals.Y
240
// btnNavApprovals.OnSelect
Navigate(scrApprovals, ScreenTransition.None)

// Nav Item 5: AI Assistant
// btnNavAI.Text
"  🤖  AI Assistant"
// btnNavAI.Visible
gblIsExecutive || gblIsAdmin
// btnNavAI.Y
288
// btnNavAI.OnSelect
Navigate(scrAIAssistant, ScreenTransition.None)

// Nav Item 6: Archive
// btnNavArchive.Text
"  📦  Archive"
// btnNavArchive.Visible
gblIsCompliance || gblIsAdmin
// btnNavArchive.Y
336
// btnNavArchive.OnSelect
Navigate(scrArchiveMgmt, ScreenTransition.None)


// ─── User Profile Area (bottom of nav) ──────────────────────
// rectUserArea (Rectangle at bottom)
// .Y = Parent.Height - 80
// .Height = 80
// .Fill = RGBA(0, 53, 93, 1)

// imgUserAvatar (Circular image)
// .Image = gblCurrentUser.photo  // or User().Image
// .Width = 36
// .Height = 36
// .BorderRadius = 18  // Circular
// .X = 16
// .Y = Parent.Height - 64

// lblUserName.Text
gblUserDisplayName
// lblUserName.Color = RGBA(255, 255, 255, 1)
// lblUserName.Size = 13
// lblUserName.FontWeight = FontWeight.Semibold
// lblUserName.X = 60
// lblUserName.Y = Parent.Height - 68

// lblUserRole.Text
gblPrimaryRole
// lblUserRole.Color = RGBA(255, 255, 255, 0.7)
// lblUserRole.Size = 11
// lblUserRole.X = 60
// lblUserRole.Y = Parent.Height - 48


// ═══════════════════════════════════════════════════════════════
// scrNoAccess — No Access Fallback Screen
// ═══════════════════════════════════════════════════════════════
// Shown when: gblHasRole = false
// Purpose: Inform user they don't have access and who to contact

// Screen.Fill
RGBA(250, 249, 248, 1)  // surface.background

// icoLock.Icon
Icon.Lock
// icoLock.Color
RGBA(96, 94, 92, 1)
// icoLock.Width = 64
// icoLock.Height = 64
// icoLock.X = (Parent.Width - 64) / 2
// icoLock.Y = Parent.Height / 2 - 120

// lblNoAccessTitle.Text
"Access Restricted"
// lblNoAccessTitle.Size = 28
// lblNoAccessTitle.FontWeight = FontWeight.Semibold
// lblNoAccessTitle.Color = RGBA(50, 49, 48, 1)
// lblNoAccessTitle.Align = Align.Center

// lblNoAccessMessage.Text
"You do not have access to the Executive Workspace."
// lblNoAccessMessage.Size = 14
// lblNoAccessMessage.Color = RGBA(96, 94, 92, 1)
// lblNoAccessMessage.Align = Align.Center

// lblNoAccessUser.Text
Concatenate("Signed in as: ", gblUserEmail)
// lblNoAccessUser.Size = 12
// lblNoAccessUser.Color = RGBA(96, 94, 92, 1)
// lblNoAccessUser.Align = Align.Center

// lblNoAccessContact.Text
"Contact your administrator to request access."
// lblNoAccessContact.Size = 14
// lblNoAccessContact.Color = RGBA(96, 94, 92, 1)
// lblNoAccessContact.Align = Align.Center

// ═══════════════════════════════════════════════════════════════
// scrAIAssistant — Embedded Copilot Studio Agent (Executives)
// ═══════════════════════════════════════════════════════════════
// Visible to: Executives, Admins
// Purpose: AI-powered Q&A over approved content
// ═══════════════════════════════════════════════════════════════


// ─── Screen.OnVisible ────────────────────────────────────────
Set(locAIFullScreen, false);
Set(locShowPromptPanel, true);


// ─── Copilot Studio Embedding ────────────────────────────────
//
// APPROACH 1: Copilot Studio (PVA) Canvas App Component
// ─────────────────────────────────────────────────────
// Power Apps supports embedding a Copilot Studio agent using the
// Chatbot control (available in Canvas Apps since 2024).
//
// Steps to add in Power Apps Studio:
// 1. Insert → AI → Chatbot
// 2. Select the ExecWorkspace-Copilot agent from your environment
// 3. Configure the control properties as below
//
// chatbotControl properties:
// .Bot
// Select "ExecWorkspace-Copilot" from the environment's bot list
// .Schema name (from Copilot Studio)
// env_CopilotBotSchemaName  // e.g. "cr8b7_execWorkspaceCopilot"
//
// .Width
If(locAIFullScreen, Parent.Width - 240, Parent.Width - 240 - 280)
// 240 = nav panel width, 280 = prompt panel width
//
// .Height
Parent.Height - 120  // Reserve space for header
//
// .X
If(locShowPromptPanel && !locAIFullScreen, 280, 0)
//
// .Y
120  // Below header
//
// .Visible
true


// APPROACH 2: Web View with Direct Line (Fallback)
// ─────────────────────────────────────────────────
// If the Chatbot control is unavailable, use an HTML text control
// with an iframe embedding the Copilot Studio web channel.
//
// htmlCopilotEmbed.HtmlText
// NOTE: This approach requires configuring the Copilot Studio web channel
// with SSO (Single Sign-On) via Entra ID authentication.
//
// "<iframe src='" & env_CopilotWebChannelUrl & "' 
//     style='width:100%; height:100%; border:none;'
//     allow='microphone'>
// </iframe>"
//
// SECURITY NOTE: The Copilot Studio agent enforces authentication
// independently. The signed-in user's Entra ID token is passed
// through. Only ExecWorkspace-Executives members can retrieve
// content from the Approved library, regardless of how the agent
// is embedded.


// ─── Suggested Prompts Panel ─────────────────────────────────
// pnlSuggestedPrompts.Visible
locShowPromptPanel && !locAIFullScreen
// pnlSuggestedPrompts.Width
280
// pnlSuggestedPrompts.X
0

// lblPromptsHeader.Text
"Suggested Prompts"

// Prompt buttons — each sends a pre-configured message to the chatbot

// btnPrompt1.Text
"Summarise the latest Board pack"
// btnPrompt1.OnSelect
// Send message to chatbot control programmatically
// NOTE: The Chatbot control may support a SendMessage property
// or an equivalent mechanism. If not, these buttons serve as
// visual suggestions that the user types manually.
Set(locSuggestedPrompt, "Summarise the most recent Board meeting pack");

// btnPrompt2.Text
"Key SteerCo decisions"
// btnPrompt2.OnSelect
Set(locSuggestedPrompt, "What were the key decisions from the latest SteerCo meeting?");

// btnPrompt3.Text
"Compare Q1 vs Q2"
// btnPrompt3.OnSelect
Set(locSuggestedPrompt, "Compare the Q1 and Q2 results from the approved documents");

// btnPrompt4.Text
"Current cycle overview"
// btnPrompt4.OnSelect
Set(locSuggestedPrompt, "Give me an overview of all documents in the current meeting cycle");

// btnPrompt5.Text
"Upcoming Board agenda"
// btnPrompt5.OnSelect
Set(locSuggestedPrompt, "What topics are covered in the upcoming Board meeting pack?");

// Each prompt button:
// .Fill — Transparent
// .BorderColor — RGBA(0, 120, 212, 0.3)
// .Color — RGBA(0, 120, 212, 1)
// .HoverFill — RGBA(0, 120, 212, 0.05)
// .Height — 64
// .Width — 248 (280 panel - 32 padding)
// .Align — Left
// .PaddingLeft — 12


// ─── Full Screen Toggle ──────────────────────────────────────
// btnToggleFullScreen.Text
If(locAIFullScreen, "⬜ Side Panel", "⬛ Full Screen")
// btnToggleFullScreen.OnSelect
Set(locAIFullScreen, !locAIFullScreen);
Set(locShowPromptPanel, !locAIFullScreen);


// ─── Header ──────────────────────────────────────────────────
// lblAIHeader.Text
"AI Assistant"
// icoAIBot.Icon
Icon.Bot
// lblAIPoweredBy.Text
"Powered by Copilot Studio • Approved content only • Read-only"
// lblAIPoweredBy.Color
RGBA(96, 94, 92, 1)  // text.secondary
// lblAIPoweredBy.Size
11  // type.caption


// ─── Security Notice ─────────────────────────────────────────
// lblSecurityNotice.Text
"This assistant can only access documents in the Approved library. All queries are logged."
// lblSecurityNotice.Visible
true
// lblSecurityNotice.Color
RGBA(96, 94, 92, 1)
// lblSecurityNotice.Y
Parent.Height - 30

# Copilot Studio Agent – Implementation Specification
## Executive Secure Research & Decision Workspace | WS-6

> **Deployment**: The agent is deployed via code using `scripts/ws6-copilot/02-deploy-copilot-agent.ps1` (Power Platform REST API) with the YAML agent definition at `scripts/ws6-copilot/agent-definition/ExecWorkspace-Copilot.yaml`. This document serves as supplementary reference for the agent's design intent and manual validation tests.

---

## Agent Overview

| Setting | Value |
|---|---|
| **Agent name** | `ExecWorkspace-Copilot` |
| **Display name** | Executive Workspace Assistant |
| **Description** | AI assistant scoped to approved Executive Workspace content. Read-only. Tenant-contained. |
| **Language** | English (en-US) |
| **Authentication** | Microsoft (Entra ID) — sign-in required |
| **Knowledge scope** | Approved library only (`https://<dev-tenant>.sharepoint.com/sites/exec-workspace/Approved`) |

---

## Prerequisites

Before building the agent, confirm:
- WS-5 Purview validation has passed
- The Approved library contains at least one test document for capability testing
- The user building the agent has access to the Approved library via `ExecWorkspace-Executives` group
- Copilot Studio licence is assigned in the dev tenant (Power Platform licence or M365 Copilot)

---

## Step 1 — Create the Agent

1. Navigate to **copilotstudio.microsoft.com**
2. Click **Create** → **New agent**
3. Choose **Skip to configure** (not the guided setup)
4. Set the following:

| Field | Value |
|---|---|
| Name | `ExecWorkspace-Copilot` |
| Description | `Secure AI assistant for the Executive Workspace. Provides summaries, key decisions, and Q&A over approved content only. Read-only.` |
| Instructions | *(See Agent Instructions below)* |

---

## Step 2 — Agent Instructions (System Prompt)

Set the following as the agent's **Instructions** in Copilot Studio:

```
You are a secure AI assistant for the Executive Secure Research & Decision Workspace.

Your role is to help authorised executive stakeholders understand and navigate approved research content.

Rules you must always follow:
1. Only answer questions based on content from the Approved library. Do not reference, imply, or extrapolate from any other source.
2. You are read-only. Never create, modify, delete, or approve documents.
3. Do not reveal document contents to users who are not authorised to view them. All access is governed by Microsoft Entra ID — you cannot override permissions.
4. If asked about documents in Draft or Review status, respond: "I only have access to approved content. Drafts and review documents are not available to me."
5. Do not accept or store any data provided by users. Your purpose is retrieval and summarisation only.
6. If you cannot answer a question from approved content, say so clearly. Do not invent or infer answers.
7. Do not connect to or reference any external websites, APIs, or data sources.
8. All responses must be factual, concise, and based solely on the approved document content available.
```

---

## Step 3 — Configure Knowledge Sources

### Add SharePoint as a knowledge source

1. In the agent editor, go to **Knowledge** → **Add knowledge**
2. Select **SharePoint**
3. Enter the **site URL** (not the library URL):
   ```
   https://<dev-tenant>.sharepoint.com/sites/exec-workspace
   ```
   > ⚠️ **Important:** Use the site URL — do NOT append `/Approved`. Copilot Studio does not accept library-level URLs and will fail silently (the knowledge source appears to add but then disappears). The `/Approved` scope is enforced at runtime by the agent's instructions and SharePoint's unique permissions on the Approved library.
4. Authenticate using your Entra ID credentials (the connection uses delegated permissions)

### Verify knowledge scope

After adding the knowledge source:
- Click the knowledge source → confirm it shows status **Ready**
- Test with a query: ask the agent about a document in the Approved library → should return results
- Test with a query about a document in Draft → should respond "not available to me"

> **Important**: Copilot Studio's SharePoint connector uses the **signed-in user's permissions** when answering questions. If a user is not a member of `ExecWorkspace-Executives`, they will not be able to retrieve content even if they access the agent. This is the correct behaviour — identity is the security boundary.

---

## Step 4 — Configure Authentication

1. In the agent editor, go to **Settings** → **Security** → **Authentication**
2. Set authentication to: **Authenticate with Microsoft**
3. This ensures:
   - Users must sign in with their Entra ID before interacting with the agent
   - The agent uses the signed-in user's permissions for all SharePoint queries
   - No unauthenticated access is possible
4. Confirm: **Allow unauthenticated users** is set to **No**

---

## Step 5 — Disable Generative Actions (Constraints)

To enforce the read-only, content-scoped constraint:

1. Go to **Settings** → **Generative AI**
2. Under **Dynamic chaining / Plugins**, ensure **no write-capable plugins** are added
3. Under **Actions**, confirm **no Power Automate flows** are connected that could trigger lifecycle changes
4. Set **Classic data connections** to disabled — no SQL, no Dataverse write access

### Topics to disable or restrict

In the **Topics** tab:
- Disable the default **Escalate** topic (no human handoff from this agent)
- Disable **Send Feedback** topic
- Keep: **Greetings**, **Goodbye**, **Thank you**, **Start Over**
- Add a custom fallback topic:

| Setting | Value |
|---|---|
| **Topic name** | `OutOfScopeResponse` |
| **Trigger phrases** | (Set as fallback — fires when no topic matches) |
| **Response** | "I can only assist with questions about approved Executive Workspace documents. If you need help with something else, please contact your workspace administrator." |

---

## Step 6 — Configure Agent Capabilities

### Supported capabilities

These capabilities are enabled via the SharePoint knowledge source:

| Capability | How configured |
|---|---|
| **Document summarisation** | Ask: "Summarise the [document name] board pack" — agent retrieves and summarises |
| **Key decision extraction** | Ask: "What were the key decisions from the Q1 research review?" |
| **Q&A over approved content** | Ask: "What does [document] say about [topic]?" |
| **Meeting pack overview** | Ask: "What is in the [meeting name] pack?" |

### Capabilities explicitly not enabled

| Capability | Reason |
|---|---|
| Web search / Bing | Not M365 native; violates tenant-containment rule |
| Document creation | Read-only constraint |
| Approval triggering | Only Power Automate flows may trigger approvals |
| Access to Draft or Review | Scoped to Approved library only |
| External API connectors | Out of scope — tenant-contained |

---

## Step 7 — Publish the Agent

1. Go to **Publish** → **Publish** (publish to the default M365 Copilot channel)
2. Share the agent:
   - Go to **Channels** → **Microsoft Teams** (optional, if Teams access is approved for this workspace)
   - Or share via **direct link** to `ExecWorkspace-Executives` group only
3. Do **not** publish to the public web or external channels

---

## Step 8 — Validation Testing

Run the following test queries to validate the agent before signoff:

### Test 1 — Approved content access (should succeed)
- Upload a test document to the Approved library with known content
- Ask the agent: "What does [test document name] contain?"
- **Expected**: Agent returns a summary of the document content

### Test 2 — Draft content rejection (should fail gracefully)
- Upload a test document to the Draft library
- Ask: "What is in the draft document [filename]?"
- **Expected**: Agent responds with "I only have access to approved content"

### Test 3 — Write action rejection (should fail gracefully)
- Ask: "Please create a document summarising today's meeting"
- **Expected**: Agent responds that it cannot create documents

### Test 4 — External data rejection (should fail gracefully)
- Ask: "Search the internet for recent company research publications"
- **Expected**: Agent responds that it can only access approved workspace content

### Test 5 — Authentication enforcement
- Access the agent in a private/incognito browser without signing in
- **Expected**: Sign-in prompt appears — no unauthenticated access

### Test 6 — Unauthenticated / wrong group rejection
- Sign in as a user who is NOT a member of `ExecWorkspace-Executives`
- **Expected**: Agent cannot retrieve documents from the Approved library (permission denied at SharePoint layer)

---

## Validation Checklist

After completing all tests:

- [ ] Agent created: `ExecWorkspace-Copilot`
- [ ] Instructions set (system prompt loaded)
- [ ] Knowledge source: Approved library URL only
- [ ] Authentication: Microsoft (Entra ID) — unauthenticated access disabled
- [ ] No write-capable plugins or actions connected
- [ ] Fallback topic configured
- [ ] Test 1–6 all pass
- [ ] Agent published to correct audience (ExecWorkspace-Executives only)
- [ ] Agent NOT accessible to external users or unauthenticated users

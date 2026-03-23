"""
Interactive helper: copies each screen YAML to clipboard one at a time.
Press Enter after pasting each one in Studio to advance to the next screen.
"""
import os
import subprocess

YAML_DIR = os.path.join(os.path.dirname(__file__), "build", "studio-yaml")

SCREENS = [
    ("scrDashboard", "Dashboard — 27 controls (metrics cards, gallery, quick actions)"),
    ("scrDocBrowser", "Document Browser — 13 controls (tabs, filters, document gallery)"),
    ("scrDocUpload", "Document Upload — 23 controls (form, dropdowns, validation)"),
    ("scrDocDetail", "Document Detail — 27 controls (metadata, lifecycle actions)"),
    ("scrApprovals", "Approvals — 12 controls (tabs, gallery with inline actions)"),
    ("scrAIAssistant", "AI Assistant — 11 controls (prompts, chatbot placeholder)"),
    ("scrArchiveMgmt", "Archive Management — 21 controls (bulk ops, confirmation dialog)"),
]


def copy_to_clipboard(text):
    process = subprocess.Popen(
        ["powershell", "-Command", "[System.Console]::InputEncoding = [System.Text.Encoding]::UTF8; $input | Set-Clipboard"],
        stdin=subprocess.PIPE,
        encoding="utf-8",
    )
    process.communicate(input=text)


def main():
    print("=" * 60)
    print("  POWER APPS STUDIO — SCREEN PASTE HELPER")
    print("=" * 60)
    print()
    print("For each screen, this script copies the YAML to clipboard.")
    print("In Studio: Add screen → Rename → View code → Select all → Paste")
    print()

    for screen_name, description in SCREENS:
        yaml_path = os.path.join(YAML_DIR, f"{screen_name}.yaml")
        if not os.path.exists(yaml_path):
            print(f"  SKIP: {yaml_path} not found")
            continue

        with open(yaml_path, "r", encoding="utf-8") as f:
            yaml_text = f.read()

        print(f"─── SCREEN: {screen_name} ───")
        print(f"  {description}")
        print()

        input(f"  Press ENTER to copy {screen_name} YAML to clipboard...")
        copy_to_clipboard(yaml_text)
        print(f"  ✓ Copied to clipboard! ({len(yaml_text)} chars)")
        print()
        print(f"  Now in Studio:")
        print(f"    1. Insert → New screen → Blank")
        print(f"    2. Rename the screen to: {screen_name}")
        print(f"    3. With the screen selected, open Code View")
        print(f"    4. Select ALL text (Ctrl+A) → Paste (Ctrl+V)")
        print(f"    5. Verify controls appear in the tree view")
        print()

        result = input(f"  Press ENTER when done (or type 'skip' to skip)... ")
        if result.strip().lower() == "skip":
            print(f"  ⏭ Skipped {screen_name}")
        else:
            print(f"  ✓ {screen_name} done!")
        print()

    print("=" * 60)
    print("  ALL SCREENS COMPLETE!")
    print("=" * 60)
    print()
    print("  Next steps:")
    print("  1. Add navigation panel controls to each screen")
    print("  2. Add Copilot Studio chatbot on scrAIAssistant")
    print("  3. Check App Checker for any formula errors")
    print("  4. Save & Publish")


if __name__ == "__main__":
    main()

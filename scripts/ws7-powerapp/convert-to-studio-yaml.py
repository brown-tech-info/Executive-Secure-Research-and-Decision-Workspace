"""
Convert PAC CLI .fx.yaml files to Power Apps Studio Code View YAML format.

PAC CLI format:  screenName As Screen: / controlName As Type: / Property: =value
Studio format:   Screens: / screenName: / Children: / - controlName: / Control: Type@Version

Usage: python convert-to-studio-yaml.py
Output: build/studio-yaml/<screenName>.yaml (one file per screen, ready to paste)
"""

import re
import os
import textwrap

SRC_DIR = os.path.join(os.path.dirname(__file__), "src")
OUT_DIR = os.path.join(os.path.dirname(__file__), "build", "studio-yaml")

# Map PAC CLI type names to Studio Control type strings
TYPE_MAP = {
    "Screen": "__SCREEN__",
    "Label": "Label@2.5.1",
    "Button": "Classic/Button@2.2.0",
    "Rectangle": "Rectangle@2.3.0",
    "icon": "Classic/Icon@2.5.0",
    "Gallery.galleryVertical": "Gallery@2.15.0",
    "DropDown": "Classic/DropDown@2.3.1",
    "CheckBox": "Classic/CheckBox@2.1.0",
    "TextInput": "Classic/TextInput@2.3.2",
    "DatePicker": "Classic/DatePicker@2.6.0",
    "AttachmentControl": "Attachments@1.0.0",
    "Image": "Image@2.2.3",
    "HtmlViewer": "Classic/HtmlViewer@1.0.0",
}

GALLERY_VARIANTS = {
    "Gallery.galleryVertical": "Vertical",
}

# Component references to skip (nav panel added separately)
SKIP_TYPES = {"cmpNavPanel"}


def parse_fx_yaml(filepath):
    """
    Parse a .fx.yaml file into a tree structure.
    Returns (screen_name, screen_props, children) where children is recursive.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Build a list of (indent_level, line_content) tuples
    parsed_lines = []
    for line in lines:
        stripped = line.rstrip("\n")
        if stripped.strip() == "":
            # Preserve blank lines for block scalars
            parsed_lines.append(("blank", 0, ""))
            continue
        indent = len(stripped) - len(stripped.lstrip())
        parsed_lines.append(("content", indent, stripped.strip()))

    return build_tree(parsed_lines, 0, 0)


def build_tree(lines, start_idx, parent_indent):
    """
    Recursively build a tree of controls and properties.
    Returns (name, type, properties, children, next_idx)
    """
    nodes = []
    i = start_idx

    while i < len(lines):
        kind, indent, content = lines[i]

        if kind == "blank":
            i += 1
            continue

        if indent <= parent_indent and i > start_idx:
            break

        # Check if this is a control definition: "name As Type:"
        as_match = re.match(r'^(\w+)\s+As\s+(.+):$', content)
        if as_match:
            ctrl_name = as_match.group(1)
            ctrl_type = as_match.group(2)
            i += 1

            # Collect properties and children at the next indent level
            props = {}
            children = []
            expected_indent = indent + 4
            current_block_prop = None

            while i < len(lines):
                ck, ci, cc = lines[i]

                if ck == "blank":
                    # Check if blank is inside a block scalar
                    if current_block_prop:
                        props[current_block_prop] += "\n"
                    i += 1
                    continue

                if ci <= indent:
                    break

                # Check if it's a child control
                child_as = re.match(r'^(\w+)\s+As\s+(.+):$', cc)
                if child_as:
                    child_name = child_as.group(1)
                    child_type = child_as.group(2)
                    i += 1
                    child_props, child_children, i = collect_control(lines, i, ci)
                    children.append({
                        "name": child_name,
                        "type": child_type,
                        "properties": child_props,
                        "children": child_children,
                    })
                    current_block_prop = None
                    continue

                # It's a property
                prop_match = re.match(r'^(\w+):\s*(.*)$', cc)
                if prop_match:
                    prop_name = prop_match.group(1)
                    prop_value = prop_match.group(2)

                    if prop_value in ("|-", "|"):
                        # Block scalar - collect continuation lines
                        current_block_prop = prop_name
                        block_lines = []
                        i += 1
                        while i < len(lines):
                            bk, bi, bc = lines[i]
                            if bk == "blank":
                                block_lines.append("")
                                i += 1
                                continue
                            if bi <= ci:
                                break
                            block_lines.append(bc)
                            i += 1
                        # Strip trailing blank lines
                        while block_lines and block_lines[-1] == "":
                            block_lines.pop()
                        props[prop_name] = "\n".join(block_lines)
                        continue
                    else:
                        props[prop_name] = prop_value
                        current_block_prop = None
                        i += 1
                        continue

                i += 1

            nodes.append({
                "name": ctrl_name,
                "type": ctrl_type,
                "properties": props,
                "children": children,
            })
            continue

        i += 1

    return nodes


current_block_prop = None


def collect_control(lines, start_idx, parent_indent):
    """Collect properties and children for a control starting at start_idx."""
    props = {}
    children = []
    i = start_idx
    block_prop = None

    while i < len(lines):
        kind, indent, content = lines[i]

        if kind == "blank":
            i += 1
            continue

        if indent <= parent_indent:
            break

        # Child control?
        child_as = re.match(r'^(\w+)\s+As\s+(.+):$', content)
        if child_as:
            child_name = child_as.group(1)
            child_type = child_as.group(2)
            i += 1
            child_props, child_children, i = collect_control(lines, i, indent)
            children.append({
                "name": child_name,
                "type": child_type,
                "properties": child_props,
                "children": child_children,
            })
            block_prop = None
            continue

        # Property
        prop_match = re.match(r'^(\w+):\s*(.*)$', content)
        if prop_match:
            prop_name = prop_match.group(1)
            prop_value = prop_match.group(2)

            if prop_value in ("|-", "|"):
                block_prop = prop_name
                block_lines = []
                i += 1
                while i < len(lines):
                    bk, bi, bc = lines[i]
                    if bk == "blank":
                        block_lines.append("")
                        i += 1
                        continue
                    if bi <= indent:
                        break
                    block_lines.append(bc)
                    i += 1
                while block_lines and block_lines[-1] == "":
                    block_lines.pop()
                props[prop_name] = "\n".join(block_lines)
                continue
            else:
                props[prop_name] = prop_value
                block_prop = None
                i += 1
                continue

        i += 1

    return props, children, i


def emit_studio_yaml(screen_node):
    """Convert a parsed screen node to Studio YAML string."""
    screen_name = screen_node["name"]
    screen_props = dict(screen_node["properties"])
    children = screen_node["children"]

    # Always include LoadingSpinnerColor
    if "LoadingSpinnerColor" not in screen_props:
        screen_props["LoadingSpinnerColor"] = "=RGBA(56, 96, 178, 1)"

    lines = []
    lines.append("Screens:")
    lines.append(f"  {screen_name}:")
    lines.append("    Properties:")

    for prop_name, prop_value in screen_props.items():
        if "\n" in prop_value:
            lines.append(f"      {prop_name}: |-")
            for vline in prop_value.split("\n"):
                lines.append(f"        {vline}")
        else:
            lines.append(f"      {prop_name}: {prop_value}")

    if children:
        lines.append("    Children:")
        for child in children:
            emit_control(lines, child, indent=6)

    return "\n".join(lines)


def emit_control(lines, node, indent):
    """Recursively emit a control in Studio YAML format."""
    ctrl_type = node["type"]
    ctrl_name = node["name"]

    # Skip component references
    if ctrl_type in SKIP_TYPES:
        return

    studio_type = TYPE_MAP.get(ctrl_type)
    if studio_type is None:
        print(f"  WARNING: Unknown type '{ctrl_type}' for control '{ctrl_name}' — skipping")
        return

    pad = " " * indent
    lines.append(f"{pad}- {ctrl_name}:")
    lines.append(f"{pad}    Control: {studio_type}")

    # Add variant for galleries
    variant = GALLERY_VARIANTS.get(ctrl_type)
    if variant:
        lines.append(f"{pad}    Variant: {variant}")

    # Properties that Studio's YAML schema does not recognise
    SKIP_PROPS = {"BorderRadius", "PaddingLeft"}

    # Property value fixups for Studio compatibility
    VALUE_FIXUPS = {
        "FontWeight": {"=FontWeight.Light": "=FontWeight.Normal"},
        "Icon": {
            "Icon.Group": "Icon.Person",
            "Icon.Calendar": "Icon.Clock",
        },
    }

    if node["properties"]:
        lines.append(f"{pad}    Properties:")
        for prop_name, prop_value in node["properties"].items():
            if prop_name in SKIP_PROPS:
                continue

            # Apply value fixups
            if prop_name in VALUE_FIXUPS:
                for old_val, new_val in VALUE_FIXUPS[prop_name].items():
                    prop_value = prop_value.replace(old_val, new_val)

            # Global fixup: Transparent → Color.Transparent
            if prop_value == "=Transparent":
                prop_value = "=Color.Transparent"

            if "\n" in prop_value:
                lines.append(f"{pad}      {prop_name}: |-")
                for vline in prop_value.split("\n"):
                    # Apply fixups to block scalar lines too
                    for fixup_prop, fixup_map in VALUE_FIXUPS.items():
                        for old_val, new_val in fixup_map.items():
                            vline = vline.replace(old_val, new_val)
                    lines.append(f"{pad}        {vline}")
            else:
                lines.append(f"{pad}      {prop_name}: {prop_value}")

    if node["children"]:
        lines.append(f"{pad}    Children:")
        for child in node["children"]:
            emit_control(lines, child, indent + 6)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    screen_files = [
        "scrDashboard.fx.yaml",
        "scrDocBrowser.fx.yaml",
        "scrDocUpload.fx.yaml",
        "scrDocDetail.fx.yaml",
        "scrApprovals.fx.yaml",
        "scrAIAssistant.fx.yaml",
        "scrArchiveMgmt.fx.yaml",
        # scrNoAccess already done manually
    ]

    for filename in screen_files:
        filepath = os.path.join(SRC_DIR, filename)
        if not os.path.exists(filepath):
            print(f"SKIP: {filename} not found")
            continue

        print(f"\nConverting {filename}...")
        nodes = parse_fx_yaml(filepath)

        if not nodes:
            print(f"  ERROR: No screen node found in {filename}")
            continue

        screen_node = nodes[0]
        studio_yaml = emit_studio_yaml(screen_node)

        out_name = filename.replace(".fx.yaml", ".yaml")
        out_path = os.path.join(OUT_DIR, out_name)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(studio_yaml)

        # Count controls (excluding skipped)
        ctrl_count = count_controls(screen_node)
        print(f"  → {out_path}")
        print(f"  → {ctrl_count} controls (nav panel excluded)")


def count_controls(node):
    count = 0
    for child in node.get("children", []):
        if child["type"] not in SKIP_TYPES:
            count += 1
            count += count_controls(child)
    return count


if __name__ == "__main__":
    main()

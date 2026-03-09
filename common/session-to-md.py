#!/usr/bin/env python3
"""
Convert a Claude Code JSONL session file to a readable Markdown document.

Usage:
    python3 session-to-md.py <session_jsonl_path> [--output <output_path>]
    python3 session-to-md.py --session-id <id> [--output <output_path>]
    python3 session-to-md.py --latest [--project <project_dir>] [--output <output_path>]
    python3 session-to-md.py --sessions-dir <dir> [--output <output_path>]

If --output is omitted, writes to <input>.md (or stdout with --latest/--session-id).
"""

import json
import sys
import os
import argparse
from datetime import datetime
from collections import Counter, OrderedDict
from pathlib import Path

# Approximate costs per million tokens (USD) as of early 2026
MODEL_COSTS = {
    "claude-opus-4-6": {"input": 15.0, "output": 75.0, "cache_read": 1.5, "cache_write": 18.75},
    "claude-opus-4-5-20250514": {"input": 15.0, "output": 75.0, "cache_read": 1.5, "cache_write": 18.75},
    "claude-sonnet-4-5-20250929": {"input": 3.0, "output": 15.0, "cache_read": 0.3, "cache_write": 3.75},
    "claude-haiku-4-5-20251001": {"input": 0.8, "output": 4.0, "cache_read": 0.08, "cache_write": 1.0},
}


def find_project_dir(cwd=None):
    """Find the project dir in ~/.claude/projects/ for the given cwd."""
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if config_dir:
        projects_dir = Path(config_dir) / "projects"
    else:
        projects_dir = Path.home() / ".claude" / "projects"

    if not projects_dir.exists():
        return None

    if cwd:
        mangled = cwd.replace("/", "-")
        candidate = projects_dir / mangled
        if candidate.exists():
            return candidate

    cwd = os.getcwd()
    mangled = cwd.replace("/", "-")
    candidate = projects_dir / mangled
    if candidate.exists():
        return candidate

    return None


def find_latest_session(project_dir=None):
    """Find the most recently modified .jsonl file."""
    if project_dir:
        search_dir = Path(project_dir)
    else:
        search_dir = find_project_dir()
        if not search_dir:
            config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
            if config_dir:
                search_dir = Path(config_dir) / "projects"
            else:
                search_dir = Path.home() / ".claude" / "projects"

    if not search_dir or not search_dir.exists():
        sys.exit("No session files found")

    jsonl_files = [f for f in search_dir.rglob("*.jsonl")
                   if not str(f).endswith("/subagents/")]
    if not jsonl_files:
        sys.exit(f"No .jsonl files found in {search_dir}")

    latest = max(jsonl_files, key=lambda f: f.stat().st_mtime)
    return str(latest)


def find_latest_in_sessions_dir(sessions_dir):
    """Find the most recent raw-*.jsonl file in a sessions directory."""
    search_dir = Path(sessions_dir)
    if not search_dir.exists():
        sys.exit(f"Sessions directory not found: {sessions_dir}")

    jsonl_files = list(search_dir.glob("raw-*.jsonl"))
    if not jsonl_files:
        sys.exit(f"No raw-*.jsonl files found in {sessions_dir}")

    latest = max(jsonl_files, key=lambda f: f.stat().st_mtime)
    return str(latest)


def find_session_by_id(session_id):
    """Find a session file by its UUID (or prefix)."""
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if config_dir:
        projects_dir = Path(config_dir) / "projects"
    else:
        projects_dir = Path.home() / ".claude" / "projects"

    if not projects_dir.exists():
        sys.exit("No projects directory found")

    for jsonl_file in projects_dir.rglob("*.jsonl"):
        if jsonl_file.stem.startswith(session_id):
            return str(jsonl_file)

    sys.exit(f"No session file found matching ID: {session_id}")


def parse_timestamp(ts_str):
    """Parse an ISO timestamp string."""
    if not ts_str:
        return None
    try:
        ts_str = ts_str.replace("Z", "+00:00")
        return datetime.fromisoformat(ts_str)
    except (ValueError, TypeError):
        return None


def format_time(dt):
    """Format datetime for display."""
    if not dt:
        return "unknown"
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def format_duration(seconds):
    """Format a duration in seconds to human-readable."""
    if seconds < 60:
        return f"{seconds:.0f}s"
    elif seconds < 3600:
        m = int(seconds // 60)
        s = int(seconds % 60)
        return f"{m}m {s}s"
    else:
        h = int(seconds // 3600)
        m = int((seconds % 3600) // 60)
        return f"{h}h {m}m"


def estimate_cost(model, input_tokens, output_tokens, cache_read, cache_write):
    """Estimate USD cost based on model pricing."""
    costs = None
    for key in MODEL_COSTS:
        if key in (model or ""):
            costs = MODEL_COSTS[key]
            break
    if not model:
        return None
    # Try prefix match
    if not costs:
        for key, val in MODEL_COSTS.items():
            if model.startswith(key.split("-20")[0]):
                costs = val
                break
    if not costs:
        return None

    total = 0.0
    total += (input_tokens / 1_000_000) * costs["input"]
    total += (output_tokens / 1_000_000) * costs["output"]
    total += (cache_read / 1_000_000) * costs["cache_read"]
    total += (cache_write / 1_000_000) * costs["cache_write"]
    return total


def extract_user_text(message):
    """Extract text content from a user message."""
    content = message.get("content", "")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    texts.append(item.get("text", ""))
        return "\n".join(texts).strip()
    return ""


def is_tool_result_only(message):
    """Check if a user message contains only tool results (no human text)."""
    content = message.get("content", "")
    if isinstance(content, str):
        return False
    if isinstance(content, list):
        has_tool_result = any(
            isinstance(c, dict) and c.get("type") == "tool_result"
            for c in content
        )
        has_text = any(
            isinstance(c, dict) and c.get("type") == "text"
            for c in content
        )
        return has_tool_result and not has_text
    return False


def summarize_tool_input(name, inp):
    """Create a one-line summary of a tool call."""
    home = str(Path.home())
    if name == "Bash":
        cmd = inp.get("command", "")
        desc = inp.get("description", "")
        first_line = cmd.split("\n")[0][:100]
        if desc:
            return f"`{first_line}` ({desc})"
        return f"`{first_line}`"
    elif name == "Read":
        fp = inp.get("file_path", "").replace(home, "~")
        return f"`{fp}`"
    elif name in ("Edit", "Write"):
        fp = inp.get("file_path", "").replace(home, "~")
        return f"`{fp}`"
    elif name == "Grep":
        pat = inp.get("pattern", "")
        path = inp.get("path", "")
        if path:
            return f'pattern: `{pat}` in `{path.replace(home, "~")}`'
        return f'pattern: `{pat}`'
    elif name == "Glob":
        return f'pattern: `{inp.get("pattern", "")}`'
    elif name == "Task":
        desc = inp.get("description", "")
        atype = inp.get("subagent_type", "")
        return f"agent={atype}: {desc}"
    elif name == "WebSearch":
        return f'query: "{inp.get("query", "")}"'
    elif name == "WebFetch":
        return f'`{inp.get("url", "")[:80]}`'
    elif name == "TaskOutput":
        tid = inp.get("task_id", "")
        return f"task_id={tid}"
    else:
        keys = list(inp.keys())[:3]
        return ", ".join(f"{k}={str(inp[k])[:40]}" for k in keys) if keys else ""


def parse_session(jsonl_path):
    """Parse a JSONL session file into structured data."""
    records = []
    with open(jsonl_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def build_conversation(records):
    """Build a structured conversation from raw records.

    Deduplicates assistant messages that share the same message.id
    (streaming produces multiple JSONL lines per API response).
    """
    session_id = None
    cwd = None
    version = None
    model = None
    git_branch = None
    slug = None
    start_time = None
    end_time = None

    # Deduplicate assistant messages by message.id
    seen_msg_ids = OrderedDict()

    turns = []
    user_prompts = []
    tool_counter = Counter()
    files_touched = set()
    total_input_tokens = 0
    total_output_tokens = 0
    total_cache_read = 0
    total_cache_write = 0
    home = str(Path.home())

    def flush_pending_assistant():
        """Flush any accumulated assistant messages into turns."""
        for _, data in seen_msg_ids.items():
            if data["texts"] or data["tool_calls"]:
                turns.append(("assistant", {
                    "texts": data["texts"],
                    "tool_calls": data["tool_calls"],
                }, data["timestamp"]))
        seen_msg_ids.clear()

    for record in records:
        rec_type = record.get("type")
        timestamp = parse_timestamp(record.get("timestamp"))

        # Skip sidechain (subagent) records for main conversation
        if record.get("isSidechain"):
            if rec_type == "assistant":
                msg = record.get("message", {})
                content = msg.get("content", [])
                if isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get("type") == "tool_use":
                            tool_counter[item.get("name", "unknown")] += 1
                            if item.get("name") in ("Edit", "Write"):
                                fp = item.get("input", {}).get("file_path", "")
                                if fp:
                                    files_touched.add((item["name"], fp.replace(home, "~")))
            continue

        # Skip progress and file-history-snapshot (noisy)
        if rec_type in ("progress", "file-history-snapshot", "queue-operation"):
            continue

        # Extract metadata
        if not session_id and record.get("sessionId"):
            session_id = record["sessionId"]
        if not cwd and record.get("cwd"):
            cwd = record["cwd"]
        if not version and record.get("version"):
            version = record["version"]
        if not git_branch and record.get("gitBranch"):
            git_branch = record["gitBranch"]
        if not slug and record.get("slug"):
            slug = record["slug"]

        if timestamp:
            if not start_time or timestamp < start_time:
                start_time = timestamp
            if not end_time or timestamp > end_time:
                end_time = timestamp

        if rec_type == "user":
            msg = record.get("message", {})
            if is_tool_result_only(msg):
                continue

            text = extract_user_text(msg)
            if text:
                flush_pending_assistant()

                turns.append(("user", text, timestamp))
                clean = text
                if clean.startswith("<task-notification>"):
                    clean = "[task notification]"
                elif clean.startswith("This session is being continued"):
                    clean = "[session continuation]"
                user_prompts.append((clean[:200], timestamp))

        elif rec_type == "assistant":
            msg = record.get("message", {})
            msg_id = msg.get("id", "")
            content = msg.get("content", [])

            # Extract model
            msg_model = msg.get("model")
            if msg_model and not model:
                model = msg_model

            # Count tokens (only from the first occurrence of each msg_id)
            usage = msg.get("usage", {})
            if msg_id and msg_id not in seen_msg_ids:
                total_input_tokens += usage.get("input_tokens", 0)
                total_cache_read += usage.get("cache_read_input_tokens", 0)
                total_cache_write += usage.get("cache_creation_input_tokens", 0)
                total_output_tokens += usage.get("output_tokens", 0)

            # Accumulate content blocks for this message
            if msg_id not in seen_msg_ids:
                seen_msg_ids[msg_id] = {
                    "texts": [],
                    "tool_calls": [],
                    "timestamp": timestamp,
                }

            entry = seen_msg_ids[msg_id]
            if isinstance(content, list):
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    itype = item.get("type")
                    if itype == "text":
                        text = item.get("text", "").strip()
                        if text and text not in entry["texts"]:
                            entry["texts"].append(text)
                    elif itype == "tool_use":
                        tc = {
                            "name": item.get("name", "unknown"),
                            "id": item.get("id", ""),
                            "input": item.get("input", {}),
                        }
                        if not any(t["id"] == tc["id"] for t in entry["tool_calls"]):
                            entry["tool_calls"].append(tc)
                            tool_counter[tc["name"]] += 1
                            if tc["name"] in ("Edit", "Write"):
                                fp = tc["input"].get("file_path", "")
                                if fp:
                                    files_touched.add((tc["name"], fp.replace(home, "~")))

    # Flush remaining assistant messages
    flush_pending_assistant()

    cost = estimate_cost(model, total_input_tokens, total_output_tokens,
                         total_cache_read, total_cache_write)

    return {
        "session_id": session_id,
        "cwd": cwd,
        "version": version,
        "model": model,
        "git_branch": git_branch,
        "slug": slug,
        "start_time": start_time,
        "end_time": end_time,
        "turns": turns,
        "user_prompts": user_prompts,
        "tool_counter": tool_counter,
        "files_touched": files_touched,
        "total_input_tokens": total_input_tokens,
        "total_output_tokens": total_output_tokens,
        "total_cache_read": total_cache_read,
        "total_cache_write": total_cache_write,
        "estimated_cost": cost,
    }


def generate_markdown(conv, include_tools=True, compact_tools=True):
    """Generate a markdown document from the conversation data."""
    lines = []
    home = str(Path.home())

    cwd_display = conv["cwd"].replace(home, "~") if conv["cwd"] else "unknown"
    lines.append("# Claude Code Session Log")
    lines.append("")

    # Metadata table
    lines.append("## Session Info")
    lines.append("")
    lines.append("| Field | Value |")
    lines.append("|-------|-------|")
    if conv["session_id"]:
        lines.append(f"| Session ID | `{conv['session_id'][:8]}` |")
    if conv["slug"]:
        lines.append(f"| Slug | {conv['slug']} |")
    lines.append(f"| Working Directory | `{cwd_display}` |")
    if conv["model"]:
        lines.append(f"| Model | {conv['model']} |")
    if conv["version"]:
        lines.append(f"| Claude Code Version | {conv['version']} |")
    if conv["git_branch"]:
        lines.append(f"| Git Branch | `{conv['git_branch']}` |")
    if conv["start_time"]:
        lines.append(f"| Started | {format_time(conv['start_time'])} |")
    if conv["end_time"]:
        lines.append(f"| Ended | {format_time(conv['end_time'])} |")
    if conv["start_time"] and conv["end_time"]:
        dur = (conv["end_time"] - conv["start_time"]).total_seconds()
        lines.append(f"| Duration | {format_duration(dur)} |")
    if conv["total_input_tokens"] or conv["total_output_tokens"]:
        lines.append(f"| Input Tokens | {conv['total_input_tokens']:,} |")
        lines.append(f"| Output Tokens | {conv['total_output_tokens']:,} |")
        if conv["total_cache_read"]:
            lines.append(f"| Cache Read Tokens | {conv['total_cache_read']:,} |")
        if conv["total_cache_write"]:
            lines.append(f"| Cache Write Tokens | {conv['total_cache_write']:,} |")
    if conv["estimated_cost"] is not None:
        lines.append(f"| Estimated Cost | ${conv['estimated_cost']:.2f} |")
    lines.append(f"| User Prompts | {len(conv['user_prompts'])} |")
    lines.append(f"| Tool Calls | {sum(conv['tool_counter'].values())} |")
    lines.append("")

    # Prompt summary
    if conv["user_prompts"]:
        lines.append("## Prompt Summary")
        lines.append("")
        for i, (prompt_text, ts) in enumerate(conv["user_prompts"], 1):
            time_str = ts.strftime("%H:%M") if ts else "?"
            display = prompt_text.replace("\n", " ").strip()
            if len(display) > 120:
                display = display[:117] + "..."
            display = display.replace("|", "\\|")
            lines.append(f"{i}. **[{time_str}]** {display}")
        lines.append("")

    # Tool usage summary
    if conv["tool_counter"]:
        lines.append("## Tool Usage")
        lines.append("")
        lines.append("| Tool | Count |")
        lines.append("|------|-------|")
        for tool, count in conv["tool_counter"].most_common():
            lines.append(f"| {tool} | {count} |")
        lines.append("")

    # Files modified
    if conv["files_touched"]:
        lines.append("## Files Modified")
        lines.append("")
        edits = sorted(set(fp for action, fp in conv["files_touched"]
                          if action in ("Edit", "Write")))
        for fp in edits:
            lines.append(f"- `{fp}`")
        lines.append("")

    # Timeline with gaps
    lines.append("## Conversation")
    lines.append("")

    prompt_num = 0
    prev_ts = None
    for turn_type, data, ts in conv["turns"]:
        time_str = ts.strftime("%H:%M:%S") if ts else ""

        # Show time gaps > 5 minutes
        if prev_ts and ts:
            gap = (ts - prev_ts).total_seconds()
            if gap > 300:
                lines.append(f"*--- {format_duration(gap)} gap ---*")
                lines.append("")
        prev_ts = ts

        if turn_type == "user":
            prompt_num += 1
            lines.append(f"### User [{time_str}] — Prompt #{prompt_num}")
            lines.append("")
            if data.startswith("<task-notification>"):
                lines.append("<details>")
                lines.append("<summary>Task notification</summary>")
                lines.append("")
                lines.append("```")
                lines.append(data[:500])
                lines.append("```")
                lines.append("</details>")
            elif data.startswith("This session is being continued"):
                lines.append("<details>")
                lines.append("<summary>Session continuation context</summary>")
                lines.append("")
                lines.append(data[:2000])
                lines.append("</details>")
            else:
                lines.append(data)
            lines.append("")

        elif turn_type == "assistant":
            texts = data["texts"]
            tool_calls = data["tool_calls"]

            lines.append(f"### Assistant [{time_str}]")
            lines.append("")

            for text in texts:
                lines.append(text)
                lines.append("")

            if include_tools and tool_calls:
                if compact_tools:
                    if len(tool_calls) == 1:
                        tc = tool_calls[0]
                        summary = summarize_tool_input(tc["name"], tc["input"])
                        lines.append(f"> **{tc['name']}**: {summary}")
                        lines.append("")
                    else:
                        lines.append("<details>")
                        lines.append(f"<summary>Tool calls ({len(tool_calls)})</summary>")
                        lines.append("")
                        for tc in tool_calls:
                            summary = summarize_tool_input(tc["name"], tc["input"])
                            lines.append(f"- **{tc['name']}**: {summary}")
                        lines.append("")
                        lines.append("</details>")
                        lines.append("")
                else:
                    for tc in tool_calls:
                        lines.append(f"**Tool: {tc['name']}**")
                        lines.append("```json")
                        lines.append(json.dumps(tc["input"], indent=2)[:500])
                        lines.append("```")
                        lines.append("")

    lines.append("---")
    lines.append(f"*Generated by session-to-md on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*")
    lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Convert Claude Code JSONL session to Markdown"
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("jsonl_path", nargs="?", help="Path to session .jsonl file")
    group.add_argument("--session-id", "-s", help="Session ID (or prefix)")
    group.add_argument("--latest", "-l", action="store_true",
                       help="Use the most recent session")
    group.add_argument("--sessions-dir", help="Find latest raw-*.jsonl in this directory")

    parser.add_argument("--output", "-o", help="Output markdown file path")
    parser.add_argument("--project", "-p", help="Project directory to search")
    parser.add_argument("--no-tools", action="store_true",
                        help="Omit tool call details")
    parser.add_argument("--verbose-tools", action="store_true",
                        help="Show full tool inputs instead of summaries")

    args = parser.parse_args()

    if args.jsonl_path:
        jsonl_path = args.jsonl_path
    elif args.session_id:
        jsonl_path = find_session_by_id(args.session_id)
    elif args.sessions_dir:
        jsonl_path = find_latest_in_sessions_dir(args.sessions_dir)
    elif args.latest:
        jsonl_path = find_latest_session(args.project)
    else:
        jsonl_path = find_latest_session()

    if not os.path.exists(jsonl_path):
        sys.exit(f"File not found: {jsonl_path}")

    records = parse_session(jsonl_path)
    conv = build_conversation(records)
    md = generate_markdown(
        conv,
        include_tools=not args.no_tools,
        compact_tools=not args.verbose_tools,
    )

    if args.output:
        out_path = args.output
    elif args.jsonl_path:
        # Default: write .md alongside the .jsonl
        out_path = args.jsonl_path.rsplit(".", 1)[0] + ".md"
    else:
        out_path = None

    if out_path:
        with open(out_path, "w") as f:
            f.write(md)
        print(f"Written to {out_path}", file=sys.stderr)
    else:
        print(md)


if __name__ == "__main__":
    main()

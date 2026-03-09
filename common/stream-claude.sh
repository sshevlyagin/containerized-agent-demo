#!/usr/bin/env bash
# common/stream-claude.sh — Shared streaming/logging library for Claude headless sessions
#
# Source this from any run-claude.sh:
#   source "$PROJECT_DIR/common/stream-claude.sh"
#
# Provides:
#   _parse_stream       — reads stream-json JSONL from stdin, displays formatted output
#   generate_session_summary — runs session-to-md.py on a JSONL file
#
# Expects PROJECT_DIR to be set before sourcing.
# Optionally set WORKSPACE_DISPLAY_PREFIX for path stripping in display.

# --- Setup ---

SESSIONS_DIR="${SESSIONS_DIR:-$PROJECT_DIR/sessions}"
mkdir -p "$SESSIONS_DIR"

# Path prefix to strip from displayed paths (for readability)
WORKSPACE_DISPLAY_PREFIX="${WORKSPACE_DISPLAY_PREFIX:-/workspace/}"

# Check for jq
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required for session streaming display."
  echo "Install it:"
  echo "  macOS:  brew install jq"
  echo "  Ubuntu: sudo apt-get install jq"
  echo "  Alpine: apk add jq"
  exit 1
fi

# --- Functions ---

_parse_stream() {
  # Reads JSONL (--output-format stream-json) from stdin.
  # Displays tool calls, thinking, and text with emoji indicators.
  # Uses jq for JSON parsing; falls back gracefully on malformed lines.
  local prefix="$WORKSPACE_DISPLAY_PREFIX"

  while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    # Try to parse as JSON; skip if not valid
    local msg_type
    msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue
    [ -z "$msg_type" ] && continue

    case "$msg_type" in
      assistant)
        # Extract content blocks from the message
        local content_types
        content_types=$(echo "$line" | jq -r '
          .message.content[]? |
          if .type == "tool_use" then
            "tool_use|\(.name // "unknown")|\(.input | tostring | .[0:200])"
          elif .type == "text" then
            "text|\(.text // "" | .[0:500])"
          elif .type == "thinking" then
            "thinking|\(.thinking // "" | .[0:200])"
          else empty end
        ' 2>/dev/null) || continue

        while IFS= read -r block; do
          [ -z "$block" ] && continue
          local btype="${block%%|*}"
          local bdata="${block#*|}"

          case "$btype" in
            tool_use)
              local tool_name="${bdata%%|*}"
              local tool_input="${bdata#*|}"
              local emoji
              case "$tool_name" in
                Read)       emoji="📖" ;;
                Edit)       emoji="✏️" ;;
                Write)      emoji="📝" ;;
                Bash)       emoji="💻" ;;
                Glob)       emoji="🔍" ;;
                Grep)       emoji="🔎" ;;
                Task)       emoji="🤖" ;;
                WebSearch)  emoji="🌐" ;;
                WebFetch)   emoji="🌍" ;;
                TodoWrite)  emoji="📋" ;;
                *)          emoji="🔧" ;;
              esac

              # Extract a one-line summary from the tool input
              local summary=""
              case "$tool_name" in
                Read|Edit|Write)
                  summary=$(echo "$tool_input" | jq -r '.file_path // empty' 2>/dev/null)
                  summary="${summary#$prefix}"
                  ;;
                Bash)
                  summary=$(echo "$tool_input" | jq -r '.command // empty' 2>/dev/null)
                  summary=$(echo "$summary" | head -1 | cut -c1-100)
                  ;;
                Grep)
                  summary=$(echo "$tool_input" | jq -r '"pattern: \(.pattern // "")"' 2>/dev/null)
                  ;;
                Glob)
                  summary=$(echo "$tool_input" | jq -r '"pattern: \(.pattern // "")"' 2>/dev/null)
                  ;;
                Task)
                  summary=$(echo "$tool_input" | jq -r '"\(.subagent_type // ""): \(.description // "")"' 2>/dev/null)
                  ;;
                *)
                  summary=$(echo "$tool_input" | cut -c1-80)
                  ;;
              esac

              echo "$emoji $tool_name: $summary"
              ;;

            thinking)
              # Show first 3 lines of thinking, capped
              local thought="${bdata#|}"
              if [ -n "$thought" ]; then
                local display
                display=$(echo "$thought" | head -3)
                echo "💭 $display"
              fi
              ;;

            text)
              local text="${bdata#|}"
              if [ -n "$text" ]; then
                echo "$text"
              fi
              ;;
          esac
        done <<< "$content_types"
        ;;

      result)
        # Session complete — show summary
        local is_error duration cost_usd
        is_error=$(echo "$line" | jq -r '.is_error // false' 2>/dev/null)
        duration=$(echo "$line" | jq -r '.duration_ms // 0' 2>/dev/null)
        cost_usd=$(echo "$line" | jq -r '.cost_usd // 0' 2>/dev/null)
        local dur_s=$((duration / 1000))

        echo ""
        if [ "$is_error" = "true" ]; then
          echo "❌ Session ended with error (${dur_s}s, \$${cost_usd})"
        else
          echo "✅ Session complete (${dur_s}s, \$${cost_usd})"
        fi
        ;;

      system)
        # System messages (session start, etc) — show briefly
        local sys_subtype
        sys_subtype=$(echo "$line" | jq -r '.subtype // empty' 2>/dev/null)
        if [ "$sys_subtype" = "init" ]; then
          local session_id model
          session_id=$(echo "$line" | jq -r '.session_id // "unknown"' 2>/dev/null)
          model=$(echo "$line" | jq -r '.model // "unknown"' 2>/dev/null)
          echo "🚀 Session started (model: $model, id: ${session_id:0:8})"
        fi
        ;;
    esac
  done
}

generate_session_summary() {
  # Generate a markdown summary from a raw JSONL session file.
  # Usage: generate_session_summary /path/to/raw-TIMESTAMP.jsonl
  local jsonl_path="$1"

  if [ ! -f "$jsonl_path" ]; then
    echo "WARNING: Session JSONL not found: $jsonl_path" >&2
    return 1
  fi

  # Check the file has content
  if [ ! -s "$jsonl_path" ]; then
    echo "WARNING: Session JSONL is empty: $jsonl_path" >&2
    return 1
  fi

  local md_path="${jsonl_path%.jsonl}.md"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if python3 "$script_dir/session-to-md.py" "$jsonl_path" --output "$md_path" 2>/dev/null; then
    echo "📄 Session summary: $md_path"
  else
    echo "WARNING: Failed to generate session summary" >&2
    return 1
  fi
}

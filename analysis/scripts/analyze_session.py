#!/usr/bin/env python3
"""
Stream/trace view of a Ralph session log.
Shows the sequence of thoughts and tool calls in chronological order.
"""
import json
import sys


def parse_event(line):
    """Parse a log line, handling malformed JSON."""
    line = line.strip()
    if not line:
        return None
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        # Try progressively stripping trailing braces for genuinely malformed lines
        for _ in range(3):
            if line.endswith('}'):
                line = line[:-1]
                try:
                    return json.loads(line)
                except json.JSONDecodeError:
                    continue
        return None


def analyze_session(file_path, verbose=False):
    print(f"Analyzing: {file_path}\n")

    with open(file_path, 'r') as f:
        lines = f.readlines()

    print(f"Total lines: {len(lines)}\n")
    print("-" * 60)

    for idx, line in enumerate(lines):
        event = parse_event(line)
        if not event:
            continue

        event_type = event.get('type')

        # Loop metadata
        if event_type == 'loop_meta':
            meta_event = event.get('event')
            data = event.get('data', {})
            ts = event.get('timestamp', '')[:19]

            if meta_event == 'iteration_start':
                print(f"\n[{ts}] === ITERATION {data.get('iteration')} START ===")
                print(f"           Mode: {data.get('mode')}, Issue: {data.get('issue_id')}")
            elif meta_event == 'iteration_end':
                print(f"\n[{ts}] === ITERATION {data.get('iteration')} END ===")
                print(f"           Duration: {data.get('duration_seconds')}s, Exit: {data.get('exit_code')}")
            continue

        # System init
        if event_type == 'system':
            subtype = event.get('subtype')
            if subtype == 'init':
                print(f"[INIT] cwd={event.get('cwd')}, model={event.get('model', 'unknown')[:30]}")
            continue

        # Assistant messages
        if event_type == 'assistant':
            message = event.get('message', {})
            content = message.get('content', [])

            if isinstance(content, list):
                for block in content:
                    block_type = block.get('type')

                    if block_type == 'thinking' and verbose:
                        thinking = block.get('thinking', '')[:150].replace('\n', ' ')
                        print(f"[{idx}] THINKING: {thinking}...")

                    elif block_type == 'text':
                        text = block.get('text', '')[:120].replace('\n', ' ')
                        print(f"[{idx}] THOUGHT: {text}...")

                    elif block_type == 'tool_use':
                        name = block.get('name')
                        inp = block.get('input', {})

                        if name == 'Bash':
                            cmd = inp.get('command', '')[:70].replace('\n', ' ')
                            print(f"[{idx}] BASH: {cmd}")
                        elif name == 'Read':
                            print(f"[{idx}] READ: {inp.get('file_path', '')}")
                        elif name == 'Edit':
                            print(f"[{idx}] EDIT: {inp.get('file_path', '')}")
                        elif name == 'Write':
                            print(f"[{idx}] WRITE: {inp.get('file_path', '')}")
                        else:
                            print(f"[{idx}] TOOL: {name} {json.dumps(inp)[:60]}")

        # User messages (tool results)
        elif event_type == 'user':
            message = event.get('message', {})
            content = message.get('content', [])

            if isinstance(content, list):
                for block in content:
                    if block.get('type') == 'tool_result':
                        is_error = block.get('is_error', False)
                        output = block.get('content', '')

                        if is_error:
                            if isinstance(output, str):
                                preview = output[:80].replace('\n', ' ')
                            else:
                                preview = "(complex output)"
                            print(f"[{idx}] ERROR: {preview}...")
                        elif verbose:
                            if isinstance(output, str):
                                preview = output[:60].replace('\n', ' ')
                            else:
                                preview = "(complex output)"
                            print(f"[{idx}] RESULT: {preview}...")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_session.py <log_file> [--verbose]")
        sys.exit(1)

    verbose = '--verbose' in sys.argv or '-v' in sys.argv
    file_path = [a for a in sys.argv[1:] if not a.startswith('-')][0]
    analyze_session(file_path, verbose)

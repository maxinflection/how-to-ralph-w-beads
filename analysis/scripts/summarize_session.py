#!/usr/bin/env python3
"""
Summarize a Ralph session log - tool usage, errors, loops, and outcomes.
"""
import json
import sys
import re
from collections import defaultdict
from datetime import datetime


def parse_event(line):
    """Parse a log line, handling malformed JSON (extra braces)."""
    line = line.strip()
    if not line:
        return None
    # Fix double }} bug in loop_meta events
    if line.endswith('}}') and '"loop_meta"' in line:
        line = line[:-1]
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        return None


def parse_timestamp(ts_str):
    """Parse ISO timestamp."""
    if not ts_str:
        return None
    try:
        # Handle both formats: with and without timezone
        ts_str = ts_str.split('.')[0].replace('+00:00', '').replace('Z', '')
        return datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None


def summarize_session(file_path):
    with open(file_path, 'r') as f:
        lines = f.readlines()

    # Collect data
    loop_meta = []
    tool_counts = defaultdict(int)
    tool_errors = defaultdict(int)
    tool_events = []
    thoughts = []
    thinking_blocks = []
    issues_worked = set()
    bd_commands = []

    for idx, line in enumerate(lines):
        event = parse_event(line)
        if not event:
            continue

        event_type = event.get('type')

        # Loop metadata
        if event_type == 'loop_meta':
            loop_meta.append(event)
            if event.get('event') == 'iteration_start':
                issue_id = event.get('data', {}).get('issue_id')
                if issue_id:
                    issues_worked.add(issue_id)
            continue

        # System init
        if event_type == 'system':
            continue

        # Assistant messages
        if event_type == 'assistant':
            message = event.get('message', {})
            content = message.get('content', [])
            if isinstance(content, list):
                for block in content:
                    block_type = block.get('type')
                    if block_type == 'thinking':
                        thinking_blocks.append({
                            'index': idx,
                            'text': block.get('thinking', '')[:200]
                        })
                    elif block_type == 'text':
                        thoughts.append({
                            'index': idx,
                            'text': block.get('text', '')
                        })
                    elif block_type == 'tool_use':
                        tool_name = block.get('name')
                        tool_input = block.get('input', {})
                        tool_counts[tool_name] += 1
                        tool_events.append({
                            'index': idx,
                            'name': tool_name,
                            'id': block.get('id'),
                            'input': tool_input
                        })
                        # Track bd commands
                        if tool_name == 'Bash':
                            cmd = tool_input.get('command', '')
                            if cmd.startswith('bd ') or ' bd ' in cmd:
                                bd_commands.append(cmd)

        # User messages (tool results)
        elif event_type == 'user':
            message = event.get('message', {})
            content = message.get('content', [])
            if isinstance(content, list):
                for block in content:
                    if block.get('type') == 'tool_result':
                        if block.get('is_error', False):
                            tool_errors['total'] += 1

    # Print summary
    print(f"{'='*60}")
    print(f"SESSION SUMMARY: {file_path}")
    print(f"{'='*60}\n")

    # Loop metadata
    if loop_meta:
        starts = [e for e in loop_meta if e.get('event') == 'iteration_start']
        ends = [e for e in loop_meta if e.get('event') == 'iteration_end']

        print(f"ITERATIONS: {len(ends)} completed")
        if ends:
            total_secs = sum(e.get('data', {}).get('duration_seconds', 0) for e in ends)
            print(f"TOTAL TIME: {total_secs:.0f}s ({total_secs/60:.1f} min)")
            exit_codes = [e.get('data', {}).get('exit_code', -1) for e in ends]
            failures = sum(1 for c in exit_codes if c != 0)
            print(f"FAILURES: {failures}/{len(ends)}")

        if issues_worked:
            print(f"ISSUES STARTED: {', '.join(sorted(issues_worked))}")
        print()

    # Tool usage
    print(f"TOOL USAGE ({sum(tool_counts.values())} total):")
    for tool, count in sorted(tool_counts.items(), key=lambda x: -x[1]):
        print(f"  {tool}: {count}")
    print(f"\nTOOL ERRORS: {tool_errors.get('total', 0)}")

    # Beads commands
    if bd_commands:
        print(f"\nBEADS COMMANDS ({len(bd_commands)}):")
        closes = [c for c in bd_commands if 'bd close' in c]
        updates = [c for c in bd_commands if 'bd update' in c]
        creates = [c for c in bd_commands if 'bd create' in c]
        print(f"  Creates: {len(creates)}, Updates: {len(updates)}, Closes: {len(closes)}")

    # Detect loops (consecutive same tool)
    print("\nPOTENTIAL LOOPS (5+ consecutive same tool):")
    consecutive_tool = None
    consecutive_count = 0
    start_index = 0
    found_loops = False

    for i, event in enumerate(tool_events):
        tool = event['name']
        if tool == consecutive_tool:
            consecutive_count += 1
        else:
            if consecutive_count >= 5:
                found_loops = True
                print(f"  {consecutive_tool} x{consecutive_count} starting at event #{start_index}")
            consecutive_tool = tool
            consecutive_count = 1
            start_index = event['index']

    if consecutive_count >= 5:
        found_loops = True
        print(f"  {consecutive_tool} x{consecutive_count} starting at event #{start_index}")

    if not found_loops:
        print("  None detected")

    # First and last thoughts
    print("\nSESSION NARRATIVE:")
    print("First thoughts:")
    for t in thoughts[:3]:
        text = t['text'][:100].replace('\n', ' ')
        print(f"  [{t['index']}] {text}...")

    print("\nFinal thoughts:")
    for t in thoughts[-3:]:
        text = t['text'][:100].replace('\n', ' ')
        print(f"  [{t['index']}] {text}...")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 summarize_session.py <log_file>")
        sys.exit(1)
    summarize_session(sys.argv[1])

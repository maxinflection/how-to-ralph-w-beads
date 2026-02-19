#!/usr/bin/env python3
"""
Analyze stuck points and workflow issues in Ralph session logs.

Detects:
- Long Bash command sequences (potential stuck loops)
- Environment/dependency issues
- Workflow escapes (TodoWrite usage when beads should be used)
- Test/build failures
"""
import json
import sys
from collections import defaultdict


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


def extract_events(file_path):
    """Load all events from log file."""
    events = []
    with open(file_path, 'r') as f:
        for line in f:
            event = parse_event(line)
            if event:
                events.append(event)
    return events


def find_tool_uses(event):
    """Extract tool use details from assistant message."""
    if event.get('type') != 'assistant':
        return []

    message = event.get('message', {})
    content = message.get('content', [])
    tools = []

    if isinstance(content, list):
        for block in content:
            if block.get('type') == 'tool_use':
                tools.append({
                    'name': block.get('name'),
                    'input': block.get('input', {}),
                    'id': block.get('id')
                })
    return tools


def find_tool_result(events, tool_use_id, start_idx):
    """Find the result for a tool_use_id."""
    for i in range(start_idx, min(start_idx + 10, len(events))):
        event = events[i]
        if event.get('type') != 'user':
            continue
        message = event.get('message', {})
        content = message.get('content', [])
        if isinstance(content, list):
            for block in content:
                if block.get('type') == 'tool_result' and block.get('tool_use_id') == tool_use_id:
                    return {
                        'content': block.get('content', ''),
                        'is_error': block.get('is_error', False)
                    }
    return None


def analyze_bash_sequences(events):
    """Find consecutive Bash command sequences (potential loops)."""
    sequences = []
    current_seq = []

    for i, event in enumerate(events):
        tools = find_tool_uses(event)
        bash_tools = [t for t in tools if t['name'] == 'Bash']

        if bash_tools:
            for tool in bash_tools:
                result = find_tool_result(events, tool['id'], i)
                current_seq.append({
                    'index': i,
                    'command': tool['input'].get('command', ''),
                    'result': result
                })
        else:
            if len(current_seq) >= 5:
                sequences.append(current_seq)
            current_seq = []

    if len(current_seq) >= 5:
        sequences.append(current_seq)

    return sequences


def analyze_workflow_escapes(events):
    """Find TodoWrite usage (workflow violations when beads should be used)."""
    escapes = []

    for i, event in enumerate(events):
        tools = find_tool_uses(event)
        for tool in tools:
            if tool['name'] == 'TodoWrite':
                escapes.append({
                    'index': i,
                    'type': 'TodoWrite',
                    'input': tool['input']
                })

    return escapes


def find_environment_issues(events):
    """Find environment-related failures."""
    issues = []
    error_patterns = [
        'command not found',
        'no module named',
        'not found',
        'permission denied',
        'cannot find',
        'missing',
        'failed to',
        'error:',
    ]

    for i, event in enumerate(events):
        tools = find_tool_uses(event)
        for tool in tools:
            if tool['name'] == 'Bash':
                cmd = tool['input'].get('command', '')
                result = find_tool_result(events, tool['id'], i)

                if not result:
                    continue

                content = result.get('content', '')
                if not isinstance(content, str):
                    continue

                content_lower = content.lower()

                if result.get('is_error'):
                    issues.append({
                        'index': i,
                        'command': cmd[:80],
                        'type': 'error',
                        'detail': content[:200]
                    })
                elif any(p in content_lower for p in error_patterns):
                    issues.append({
                        'index': i,
                        'command': cmd[:80],
                        'type': 'warning',
                        'detail': content[:200]
                    })

    return issues


def analyze_test_attempts(events):
    """Find test/build execution attempts and outcomes."""
    attempts = []
    test_patterns = ['cargo test', 'cargo build', 'npm test', 'pytest', 'jest', 'go test']

    for i, event in enumerate(events):
        tools = find_tool_uses(event)
        for tool in tools:
            if tool['name'] == 'Bash':
                cmd = tool['input'].get('command', '')
                if any(p in cmd for p in test_patterns):
                    result = find_tool_result(events, tool['id'], i)
                    output = ''
                    is_error = False

                    if result:
                        output = result.get('content', '')[:500] if isinstance(result.get('content'), str) else ''
                        is_error = result.get('is_error', False)

                    attempts.append({
                        'index': i,
                        'command': cmd[:100],
                        'is_error': is_error,
                        'output_preview': output
                    })

    return attempts


def main(file_path):
    print(f"{'='*60}")
    print(f"STUCK POINT ANALYSIS: {file_path}")
    print(f"{'='*60}\n")

    events = extract_events(file_path)
    print(f"Total events: {len(events)}\n")

    # Bash sequences
    print("-" * 40)
    print("BASH COMMAND SEQUENCES (5+ consecutive)")
    print("-" * 40)
    sequences = analyze_bash_sequences(events)
    if sequences:
        for seq_num, seq in enumerate(sequences, 1):
            print(f"\nSequence {seq_num}: {len(seq)} commands at event #{seq[0]['index']}")
            for item in seq[:8]:
                cmd = item['command'][:60].replace('\n', ' ')
                status = "ERR" if item['result'] and item['result'].get('is_error') else "OK "
                print(f"  [{status}] {cmd}")
            if len(seq) > 8:
                print(f"  ... +{len(seq) - 8} more")
    else:
        print("  None found (good - no stuck loops)")

    # Workflow escapes
    print("\n" + "-" * 40)
    print("WORKFLOW ESCAPES (TodoWrite usage)")
    print("-" * 40)
    escapes = analyze_workflow_escapes(events)
    if escapes:
        for escape in escapes:
            print(f"\n  Event #{escape['index']}: TodoWrite called")
            todos = escape['input'].get('todos', [])
            for todo in todos[:3]:
                print(f"    - {todo.get('content', '')[:50]}")
    else:
        print("  None found (good - using beads properly)")

    # Environment issues
    print("\n" + "-" * 40)
    print("ENVIRONMENT ISSUES")
    print("-" * 40)
    issues = find_environment_issues(events)
    errors = [i for i in issues if i['type'] == 'error']
    warnings = [i for i in issues if i['type'] == 'warning']

    if errors:
        print(f"\nErrors ({len(errors)}):")
        for issue in errors[:10]:
            print(f"  #{issue['index']}: {issue['command']}")
            print(f"    -> {issue['detail'][:80]}...")
    if warnings:
        print(f"\nWarnings ({len(warnings)}):")
        for issue in warnings[:5]:
            print(f"  #{issue['index']}: {issue['command']}")

    if not issues:
        print("  None found")

    # Test attempts
    print("\n" + "-" * 40)
    print("TEST/BUILD ATTEMPTS")
    print("-" * 40)
    attempts = analyze_test_attempts(events)
    if attempts:
        passed = sum(1 for a in attempts if not a['is_error'])
        failed = sum(1 for a in attempts if a['is_error'])
        print(f"  Total: {len(attempts)} (passed: {passed}, failed: {failed})")

        if failed > 0:
            print("\n  Failed attempts:")
            for a in [x for x in attempts if x['is_error']][:5]:
                print(f"    #{a['index']}: {a['command'][:60]}")
    else:
        print("  None found")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_stuck_points.py <log_file>")
        sys.exit(1)
    main(sys.argv[1])

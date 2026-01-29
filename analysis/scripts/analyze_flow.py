#!/usr/bin/env python3
"""Analyze session flow patterns."""
import json
import sys
from collections import defaultdict

def parse_event(line):
    line = line.strip()
    if not line:
        return None
    if line.endswith('}}') and '"loop_meta"' in line:
        line = line[:-1]
    try:
        return json.loads(line)
    except:
        return None

def analyze_flow(file_path):
    events = []
    with open(file_path) as f:
        for line in f:
            e = parse_event(line)
            if e:
                events.append(e)
    
    # Extract task transitions
    task_timeline = []
    current_task = None
    
    for i, event in enumerate(events):
        if event.get('type') != 'assistant':
            continue
        msg = event.get('message', {})
        content = msg.get('content', [])
        
        for block in content:
            if block.get('type') == 'tool_use' and block.get('name') == 'Bash':
                cmd = block.get('input', {}).get('command', '')
                
                # Track task transitions
                if 'bd update' in cmd and 'in_progress' in cmd:
                    task_id = cmd.split()[2] if len(cmd.split()) > 2 else 'unknown'
                    task_timeline.append(('START', task_id, i))
                elif 'bd close' in cmd:
                    task_id = cmd.split()[2] if len(cmd.split()) > 2 else 'unknown'
                    task_timeline.append(('CLOSE', task_id, i))
    
    print("TASK TIMELINE:")
    print("-" * 50)
    prev_idx = 0
    for action, task_id, idx in task_timeline:
        events_since = idx - prev_idx
        print(f"  [{idx:3}] {action:5} {task_id} (+{events_since} events)")
        prev_idx = idx
    
    # Analyze error recovery patterns
    print("\n\nERROR -> RECOVERY PATTERNS:")
    print("-" * 50)
    error_recoveries = []
    last_error_idx = None
    
    for i, event in enumerate(events):
        if event.get('type') == 'user':
            msg = event.get('message', {})
            content = msg.get('content', [])
            for block in content:
                if block.get('type') == 'tool_result' and block.get('is_error'):
                    last_error_idx = i
        
        if event.get('type') == 'assistant' and last_error_idx:
            msg = event.get('message', {})
            content = msg.get('content', [])
            for block in content:
                if block.get('type') == 'text':
                    text = block.get('text', '')[:80]
                    if any(w in text.lower() for w in ['fix', 'let me', 'try', 'install', 'check']):
                        error_recoveries.append((last_error_idx, i, text))
                        last_error_idx = None
                        break
    
    for err_idx, recov_idx, thought in error_recoveries[:10]:
        gap = recov_idx - err_idx
        print(f"  Error @{err_idx} -> Recovery @{recov_idx} (gap={gap})")
        print(f"    \"{thought[:60]}...\"")

    # Count read-before-edit patterns
    print("\n\nREAD-BEFORE-EDIT ANALYSIS:")
    print("-" * 50)
    edits = []
    reads = set()
    
    for i, event in enumerate(events):
        if event.get('type') != 'assistant':
            continue
        msg = event.get('message', {})
        content = msg.get('content', [])
        for block in content:
            if block.get('type') == 'tool_use':
                name = block.get('name')
                inp = block.get('input', {})
                if name == 'Read':
                    reads.add(inp.get('file_path', ''))
                elif name == 'Edit':
                    fp = inp.get('file_path', '')
                    had_read = fp in reads
                    edits.append((i, fp, had_read))
    
    edits_with_read = sum(1 for _, _, had in edits if had)
    print(f"  Total Edits: {len(edits)}")
    print(f"  Had prior Read: {edits_with_read}/{len(edits)}")
    
if __name__ == '__main__':
    analyze_flow(sys.argv[1])

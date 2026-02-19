#!/usr/bin/env python3
"""Analyze session efficiency."""
import json
import sys

def parse_event(line):
    line = line.strip()
    if not line:
        return None
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        for _ in range(3):
            if line.endswith('}'):
                line = line[:-1]
                try:
                    return json.loads(line)
                except json.JSONDecodeError:
                    continue
        return None

def analyze(file_path):
    events = []
    with open(file_path) as f:
        for line in f:
            e = parse_event(line)
            if e:
                events.append(e)
    
    # Categorize tool calls
    tool_categories = {
        'orientation': ['bd ready', 'bd show', 'bd list'],
        'claiming': ['bd update'],
        'reading': ['Read', 'Glob'],
        'testing': ['cargo test', 'pytest', 'npm test', 'python -m pytest'],
        'editing': ['Edit', 'Write'],
        'closing': ['bd close'],
        'git': ['git '],
        'env_setup': ['apt-get', 'dnf', 'pip', 'which', 'curl'],
    }
    
    category_counts = {k: 0 for k in tool_categories}
    category_counts['other'] = 0
    
    for event in events:
        if event.get('type') != 'assistant':
            continue
        msg = event.get('message', {})
        content = msg.get('content', [])
        for block in content:
            if block.get('type') != 'tool_use':
                continue
            name = block.get('name', '')
            inp = block.get('input', {})
            cmd = inp.get('command', '') if name == 'Bash' else name
            
            categorized = False
            for cat, patterns in tool_categories.items():
                if any(p in cmd for p in patterns):
                    category_counts[cat] += 1
                    categorized = True
                    break
            if not categorized:
                category_counts['other'] += 1
    
    print("TOOL USAGE BY CATEGORY:")
    print("-" * 50)
    total = sum(category_counts.values())
    for cat, count in sorted(category_counts.items(), key=lambda x: -x[1]):
        pct = (count / total * 100) if total else 0
        bar = '#' * int(pct / 3)
        print(f"  {cat:15} {count:3} ({pct:4.1f}%) {bar}")
    
    # Calculate "overhead" vs "productive" work
    productive = category_counts['editing'] + category_counts['testing']
    overhead = category_counts['orientation'] + category_counts['env_setup'] + category_counts['git']
    workflow = category_counts['claiming'] + category_counts['closing']
    
    print(f"\n  Productive (edit+test): {productive} ({productive/total*100:.0f}%)")
    print(f"  Overhead (orient+env+git): {overhead} ({overhead/total*100:.0f}%)")
    print(f"  Workflow (claim+close): {workflow} ({workflow/total*100:.0f}%)")

if __name__ == '__main__':
    analyze(sys.argv[1])

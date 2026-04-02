#!/usr/bin/env python3
"""
Выполняет SQL батчи через Supabase REST API (PostgREST RPC).
Использует service_role key для прямого доступа к БД.
"""

import os, json, sys, urllib.request, urllib.error, time

SQL_DIR = "/Users/jcat/Documents/Doc/Projects/cold_start2/sql_batches"
SUPABASE_URL = "https://lqgzvolirohuettizkhx.supabase.co"
SERVICE_KEY = "SUPABASE_SERVICE_KEY_REDACTED"

# Skip batch_01 user 1 (already created via MCP)
SKIP_FIRST_BLOCK = True


def execute_sql_block(sql):
    """Execute a single DO $$ block via Supabase SQL API."""
    # Use the pg/query endpoint (used by Supabase Dashboard)
    url = f"{SUPABASE_URL}/pg/query"
    data = json.dumps({"query": sql}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "apikey": SERVICE_KEY,
    })
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        result = resp.read().decode()
        return True, result
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        return False, f"HTTP {e.code}: {body}"
    except Exception as e:
        return False, str(e)


def split_do_blocks(sql_content):
    """Split SQL file into individual DO $$ blocks."""
    blocks = []
    current = []
    for line in sql_content.split('\n'):
        current.append(line)
        if line.strip() == 'END $$;':
            blocks.append('\n'.join(current))
            current = []
    return blocks


def main():
    batch_files = sorted(f for f in os.listdir(SQL_DIR) if f.endswith('.sql'))
    print(f"Found {len(batch_files)} batch files")

    total_ok = 0
    total_fail = 0
    first_block_skipped = False

    for batch_file in batch_files:
        path = os.path.join(SQL_DIR, batch_file)
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        blocks = split_do_blocks(content)
        print(f"\n{batch_file}: {len(blocks)} users")

        for i, block in enumerate(blocks):
            # Skip first user of batch_01 (already created)
            if SKIP_FIRST_BLOCK and not first_block_skipped:
                first_block_skipped = True
                total_ok += 1
                print(f"  [{i+1}] SKIP (already created)")
                continue

            # Extract user name from comment
            name = "unknown"
            for line in block.split('\n'):
                if line.startswith('-- User'):
                    name = line.split(':')[1].strip() if ':' in line else line
                    break

            ok, result = execute_sql_block(block)
            if ok:
                total_ok += 1
                print(f"  [{i+1}] OK: {name}")
            else:
                total_fail += 1
                print(f"  [{i+1}] FAIL: {name}: {result[:200]}")
                if 'duplicate key' in result.lower():
                    print(f"    (duplicate — skipping)")
                    total_ok += 1
                    total_fail -= 1
                else:
                    print("  STOPPING due to non-duplicate error")
                    print(f"\nTotal: OK={total_ok}, FAIL={total_fail}")
                    sys.exit(1)

    print(f"\n=== DONE: OK={total_ok}, FAIL={total_fail} ===")


if __name__ == '__main__':
    main()

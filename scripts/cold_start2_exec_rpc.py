#!/usr/bin/env python3
"""
Выполняет SQL батчи через Supabase RPC (cold_start_exec_sql).
Каждый DO-блок выполняется отдельно.
"""

import os, sys, json, urllib.request, urllib.error

SQL_DIR = "/Users/jcat/Documents/Doc/Projects/cold_start2/sql_batches"
SUPABASE_URL = "https://lqgzvolirohuettizkhx.supabase.co"
SERVICE_KEY = "SUPABASE_SERVICE_KEY_REDACTED"


def call_rpc(sql):
    """Execute SQL via cold_start_exec_sql RPC."""
    url = f"{SUPABASE_URL}/rest/v1/rpc/cold_start_exec_sql"
    data = json.dumps({"p_sql": sql}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={
        "Authorization": f"Bearer {SERVICE_KEY}",
        "apikey": SERVICE_KEY,
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    })
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        return True, ""
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        return False, f"HTTP {e.code}: {body[:300]}"


def split_do_blocks(sql_content):
    """Split SQL file into individual DO $$ blocks."""
    blocks = []
    current = []
    in_block = False
    for line in sql_content.split('\n'):
        if line.strip().startswith('DO $$'):
            in_block = True
            current = [line]
        elif in_block:
            current.append(line)
            if line.strip() == 'END $$;':
                blocks.append('\n'.join(current))
                current = []
                in_block = False
    return blocks


def main():
    batch_files = sorted(f for f in os.listdir(SQL_DIR) if f.endswith('.sql'))
    print(f"Found {len(batch_files)} batch files")

    total_ok = 0
    total_fail = 0

    for batch_file in batch_files:
        path = os.path.join(SQL_DIR, batch_file)
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        blocks = split_do_blocks(content)
        print(f"\n{batch_file}: {len(blocks)} users")

        for i, block in enumerate(blocks):
            ok, err = call_rpc(block)
            if ok:
                total_ok += 1
                sys.stdout.write(f".")
                sys.stdout.flush()
            else:
                if 'duplicate key' in err.lower():
                    total_ok += 1
                    sys.stdout.write("s")
                    sys.stdout.flush()
                else:
                    total_fail += 1
                    print(f"\n  [{i+1}] FAIL: {err}")
                    print("  STOPPING")
                    print(f"\nTotal: OK={total_ok}, FAIL={total_fail}")
                    sys.exit(1)

        print(f" OK ({total_ok} total)")

    print(f"\n=== DONE: OK={total_ok}, FAIL={total_fail} ===")


if __name__ == '__main__':
    main()

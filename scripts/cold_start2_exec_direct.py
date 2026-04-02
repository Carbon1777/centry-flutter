#!/usr/bin/env python3
"""
Выполняет SQL батчи напрямую через PostgreSQL connection.
"""

import os, sys, time
import psycopg2

SQL_DIR = "/Users/jcat/Documents/Doc/Projects/cold_start2/sql_batches"

# Supabase direct connection
DB_HOST = "db.lqgzvolirohuettizkhx.supabase.co"
DB_PORT = 5432
DB_NAME = "postgres"
DB_USER = "postgres"
DB_PASS = "CentryApp2026!"  # standard Supabase password - will try connection pooler format too


def get_connection():
    """Connect to Supabase PostgreSQL."""
    # Try direct connection with service_role via connection string
    conn_str = f"postgresql://postgres.lqgzvolirohuettizkhx:CentryApp2026!@aws-0-eu-central-1.pooler.supabase.com:6543/postgres"
    try:
        conn = psycopg2.connect(conn_str, connect_timeout=10)
        conn.autocommit = False
        return conn
    except Exception as e:
        print(f"Pooler connection failed: {e}")

    # Try direct
    try:
        conn = psycopg2.connect(
            host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
            user=DB_USER, password=DB_PASS,
            connect_timeout=10
        )
        conn.autocommit = False
        return conn
    except Exception as e:
        print(f"Direct connection failed: {e}")
        return None


def main():
    batch_files = sorted(f for f in os.listdir(SQL_DIR) if f.endswith('.sql'))
    print(f"Found {len(batch_files)} batch files")

    conn = get_connection()
    if not conn:
        print("Cannot connect to database. Check credentials.")
        sys.exit(1)

    print("Connected to database")
    cur = conn.cursor()

    total_ok = 0
    total_fail = 0

    for batch_file in batch_files:
        path = os.path.join(SQL_DIR, batch_file)
        with open(path, 'r', encoding='utf-8') as f:
            sql = f.read()

        print(f"  {batch_file}...", end=" ", flush=True)
        try:
            cur.execute(sql)
            conn.commit()
            total_ok += 1
            print("OK")
        except Exception as e:
            conn.rollback()
            total_fail += 1
            error_msg = str(e).split('\n')[0]
            print(f"FAIL: {error_msg}")

            if 'duplicate key' in str(e).lower():
                print("    (duplicate — already exists, continuing)")
            else:
                print("    STOPPING")
                break

    cur.close()
    conn.close()
    print(f"\n=== DONE: OK={total_ok}, FAIL={total_fail} ===")


if __name__ == '__main__':
    main()

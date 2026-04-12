#!/usr/bin/env python3
"""TZ8: Execute staging batch SQL files via supabase-py."""

import os
import glob
import sys

# Use supabase management API via subprocess + MCP is not available from python
# Instead, use postgres directly via psycopg2 or supabase-py
# Simplest: read each SQL file and POST to Supabase SQL endpoint

import urllib.request
import json

PROJECT_ID = "lqgzvolirohuettizkhx"
# We'll use the Supabase Management API
# But actually, let's use psql or the REST endpoint

# Better approach: combine all batches into fewer large SQLs
# and execute via the MCP tool from the chat

def combine_batches(batch_dir="/tmp", prefix="tz8_batch_", output="/tmp/tz8_combined"):
    files = sorted(glob.glob(f"{batch_dir}/{prefix}*.sql"),
                   key=lambda x: int(x.split("_")[-1].split(".")[0]))

    # Combine into groups of 10 batches (1000 rows each)
    group_size = 10
    groups = [files[i:i+group_size] for i in range(0, len(files), group_size)]

    combined_files = []
    for gi, group in enumerate(groups):
        combined = []
        for f in group:
            with open(f) as fh:
                combined.append(fh.read())

        outfile = f"{output}_{gi}.sql"
        with open(outfile, "w") as fh:
            fh.write("\n".join(combined))
        combined_files.append(outfile)
        print(f"Combined group {gi}: {len(group)} batches -> {outfile}")

    print(f"\nTotal: {len(combined_files)} combined files of ~{group_size * 100} rows each")
    return combined_files


if __name__ == "__main__":
    combine_batches()

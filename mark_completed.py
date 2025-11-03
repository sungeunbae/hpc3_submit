import sqlite3
import time
import argparse
from tabulate import tabulate
from datetime import datetime
import pytz

def epoch_to_nzst(epoch):
    """Convert epoch time to NZST string."""
    if epoch is None:
        return "None"
    utc_dt = datetime.utcfromtimestamp(epoch).replace(tzinfo=pytz.UTC)
    nzst_dt = utc_dt.astimezone(pytz.timezone('Pacific/Auckland'))
    return nzst_dt.strftime('%Y-%m-%d %H:%M:%S %Z')

def query_state(db_path, run_name, proc_type, job_id):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Query matching entries
    query = """
    SELECT id, run_name, proc_type, status, job_id, last_modified
    FROM state
    WHERE run_name = ? AND proc_type = ?
    ORDER BY id DESC
    """
    cursor.execute(query, (run_name, proc_type))
    rows = cursor.fetchall()
    
    if not rows:
        print("No matching entries found.")
        conn.close()
        return None, None
    
    # Check for status == 5
    for row in rows:
        if row[3] == 5:
            print("An entry already has status=5 (completed). No update needed.")
            # Convert last_modified to NZST for display
            display_row = list(row)
            display_row[5] = epoch_to_nzst(row[5])
            print(tabulate([display_row], headers=['id', 'run_name', 'proc_type', 'status', 'job_id', 'last_modified']))
            conn.close()
            return None, None
    
    # Prepare table for display
    table = []
    highlighted_row = None
    highlight_id = None
    
    for row in rows:
        # Convert last_modified to NZST for display
        display_row = list(row)
        display_row[5] = epoch_to_nzst(row[5])
        
        if job_id is not None and row[4] == job_id:
            highlighted_row = row
            highlight_id = row[0]
            table.append([f"*{r}" if r == display_row[i] else r for i, r in enumerate(display_row)])
        else:
            table.append(display_row)
    
    # If no job_id specified, highlight the highest id (first row)
    if job_id is None and rows:
        highlighted_row = rows[0]
        highlight_id = rows[0][0]
        table[0] = [f"*{r}" for r in table[0]]
    
    # Display entries
    print("Matching entries (sorted by id descending):")
    print(tabulate(table, headers=['id', 'run_name', 'proc_type', 'status', 'job_id', 'last_modified']))
    
    conn.close()
    return highlighted_row, highlight_id

def update_status(db_path, highlight_id):
    if highlight_id is None:
        print("No entry to update.")
        return
    
    # Ask for confirmation
    confirm = input(f"Update highlighted entry (id={highlight_id}) to status=5 (completed)? (y/n): ").lower()
    if confirm != 'y':
        print("Update cancelled.")
        return
    
    # Update the entry
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    current_time = int(time.time())
    cursor.execute("""
    UPDATE state
    SET status = 5, last_modified = ?
    WHERE id = ?
    """, (current_time, highlight_id))
    
    conn.commit()
    
    # Fetch and display updated entry
    cursor.execute("""
    SELECT id, run_name, proc_type, status, job_id, last_modified
    FROM state
    WHERE id = ?
    """, (highlight_id,))
    updated_row = cursor.fetchone()
    
    # Convert last_modified to NZST for display
    display_row = list(updated_row)
    display_row[5] = epoch_to_nzst(updated_row[5])
    
    print("\nUpdated entry:")
    print(tabulate([display_row], headers=['id', 'run_name', 'proc_type', 'status', 'job_id', 'last_modified']))
    
    conn.close()

def main():
    parser = argparse.ArgumentParser(description="Mark a state entry as completed in slurm_mgmt.db")
    parser.add_argument("run_name", help="Run name to match")
    parser.add_argument("proc_type", type=int, help="Process type to match")
    parser.add_argument("--job_id", type=int, default=None, help="Job ID to highlight (optional)")
    parser.add_argument("--db", default="./slurm_mgmt.db", help="Database path (default: ./slurm_mgmt.db)")
    
    args = parser.parse_args()
    
    # Query and display entries
    highlighted_row, highlight_id = query_state(args.db, args.run_name, args.proc_type, args.job_id)
    
    # Update status if applicable
    update_status(args.db, highlight_id)

if __name__ == "__main__":
    main()


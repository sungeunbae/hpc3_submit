import sqlite3
import sys

from pathlib import Path

# Assuming this is located at the personal RunFolder. eg. /nesi/nobackup/nesi00213/RunFolder/submit
root_directory = Path.cwd()

# Function to update the state table
def update_state_table(conn, run_name):
    update_query = """
        UPDATE state
        SET status = 5
        WHERE run_name = ? AND proc_type = 1
    """
    conn.cursor().execute(update_query, (run_name,))
    conn.commit()
    
def main(cs_root):
    cs_root = cs_root.resolve()
    # Connect to the database
    db_path = cs_root / "slurm_mgmt.db"
    conn = sqlite3.connect(db_path)
    
    # Traverse directories and update state table
    assert cs_root.exists()
    runs_path = cs_root / "Runs"
    assert runs_path.exists()
    fault_dirs = [x for x in runs_path.iterdir() if x.is_dir()]

    for fault_dir in fault_dirs:
        rel_dirs = [x for x in fault_dir.iterdir() if x.is_dir()]
        for rel_dir in rel_dirs:
            lf_outbin_path = rel_dir / "LF" / "OutBin"
            # assume it is all completed if OutBin folder is not empty. maybe too optimistic
            if lf_outbin_path.is_dir() and len([x for x in lf_outbin_path.iterdir()])>0:
                print(f"Updating {rel_dir.name} EMOD3D")
                update_state_table(conn, rel_dir.name)
            else:
                print(f"LF.tar not found in {rel_dir}")

    conn.close()

    # Close the database connection
    print("Status updated in slurm_mgmt.db for matching entries.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} cs_root")
        sys.exit()
    main(Path(sys.argv[1]))


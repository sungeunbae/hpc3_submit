from pathlib import Path

# Load the full list of REL_DIRs
with open("im_targets.txt") as f:
    targets = [Path(line.strip()) for line in f]

# Find all existing .csv files in IM_calc folders
existing_csvs = {
    csv_path.resolve()
    for csv_path in Path("Runs").rglob("IM_calc/*.csv")
}

# Find which REL_DIRs are missing the expected CSV
missing = []

for rel in targets:
    expected_csv = rel / "IM_calc" / f"{rel.name}.csv"
    if not expected_csv.resolve() in existing_csvs:
        missing.append(str(rel))

# Report
print(f"\nMissing CSVs for {len(missing)} out of {len(targets)} runs.\n")
for path in missing:
    print(path)


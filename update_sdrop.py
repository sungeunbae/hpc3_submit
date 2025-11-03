import os
import sys
import yaml

# Validate arguments
if len(sys.argv) != 3:
    print("Usage: python update_all_sdrop.py [base_dir] [i|s]")
    sys.exit(1)

base_dir = sys.argv[1]
event_type = sys.argv[2].lower()

# Set max sdrop based on event type
if event_type == "i":
    max_sdrop = 85.0
elif event_type == "s":
    max_sdrop = 350.0
else:
    print("Invalid type argument. Use 'i' or 's'.")
    sys.exit(1)

# Traverse the base directory
for root, _, files in os.walk(base_dir):
    if "sim_params.yaml" not in files:
        continue

    yaml_path = os.path.join(root, "sim_params.yaml")

    try:
        with open(yaml_path, "r") as f:
            sim_params = yaml.safe_load(f)
    except Exception as e:
        print(f"[ERROR] Reading {yaml_path}: {e}")
        continue

    hf = sim_params.setdefault("hf", {})
    old_sdrop = hf.get("sdrop", None)

    capped_sdrop = min(float(old_sdrop) if old_sdrop else max_sdrop, max_sdrop)
    hf["sdrop"] = capped_sdrop

    try:
        with open(yaml_path, "w") as f:
            yaml.dump(sim_params, f, sort_keys=False)
        print(f"[UPDATED] {yaml_path} — sdrop {old_sdrop} → {capped_sdrop}")
    except Exception as e:
        print(f"[ERROR] Writing {yaml_path}: {e}")


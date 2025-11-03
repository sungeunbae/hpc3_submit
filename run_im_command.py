#!/usr/bin/env python

import argparse
import os
import sys
from qcore import utils

def main():
    parser = argparse.ArgumentParser(description="Generate IM calculation command from sim_params.yaml")
    parser.add_argument("rel_dir", help="Path to REL_DIR containing sim_params.yaml")
    args = parser.parse_args()

    sim_params_path = os.path.join(args.rel_dir, "sim_params.yaml")

    try:
        params = utils.load_sim_params(sim_yaml_path=sim_params_path)
        ims = params["ims"]
        rel_name = os.path.basename(args.rel_dir)
        gmsim = os.environ["gmsim"]

        bb_bin =os.path.realpath( os.path.join(args.rel_dir, "BB", "Acc", "BB.bin"))
        im_out_dir = os.path.realpath(os.path.join(args.rel_dir, "IM_calc"))

        command = f"srun python {gmsim}/IM_calculation/IM_calculation/scripts/calculate_ims_mpi.py " \
                  f"{bb_bin} b -o {im_out_dir} -i {rel_name} -r {rel_name} -t s"

        # Add component list
        if "component" in ims:
            comp_str = " ".join(ims["component"])
            command += f" -c {comp_str}"

        # Add -e if extended_period is True
        if ims.get("extended_period", False):
            command += " -e"

        # Always add -s
        command += " -s"

        # Add pSA periods
        if "pSA_periods" in ims:
            psa_str = " ".join(map(str, ims["pSA_periods"]))
            command += f" -p {psa_str}"

        print(command)

    except Exception as e:
        print(f"Error generating IM command: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()


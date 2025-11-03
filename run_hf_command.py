import argparse
import os
import sys
from qcore import utils

BINARY_PATH="/nesi/project/nesi00213/opt/hpc3/tools"
def main():
    parser = argparse.ArgumentParser(description="Generate HF simulation command from sim_params.yaml")
    parser.add_argument("rel_dir", help="Path to REL_DIR containing sim_params.yaml")
    args = parser.parse_args()

    # Construct sim_params.yaml path
    sim_params_path = os.path.join(args.rel_dir, "sim_params.yaml")

    try:
        params = utils.load_sim_params(sim_yaml_path=sim_params_path)
        hf_params = params["hf"]
        gmsim = os.environ["gmsim"]
        command = f"srun python {gmsim}/workflow/workflow/calculation/hf_sim.py " \
                  f"{params['FD_STATLIST']} {args.rel_dir}/HF/Acc/HF.bin " \
                  f"--duration {params['sim_duration']} --dt {hf_params['dt']} " \
                  f"--sim_bin {BINARY_PATH}/hb_high_binmod_v{hf_params['version']} " \
                  f"--seed {hf_params['seed']} --version {hf_params['version']} " \
                  f"--rvfac {hf_params['rvfac']} --sdrop {hf_params['sdrop']} --path_dur {hf_params['path_dur']} " \
                  f"--kappa {hf_params['kappa']} --rayset {hf_params['rayset']} --rvfac_shal {hf_params['rvfac_shal']} " \
                  f"--rvfac_deep {hf_params['rvfac_deep']} --czero {hf_params['czero']} " \
                  f"--hf_vel_mod_1d {hf_params['hf_vel_mod_1d']}" \
                  f" --slip {hf_params['slip']}"

        if hf_params.get("site_specific", False):
            command += f" --site_specific --site_v1d_dir {hf_params['site_v1d_dir']}"

        print(command)

    except Exception as e:
        print(f"Error generating command: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()


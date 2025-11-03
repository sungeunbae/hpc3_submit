import os
import argparse
import subprocess
from qcore import srf, qclogging
from logging import Logger

SRF2STOCH = "/nesi/project/nesi00213/opt/EMOD3D_2025/tools/srf2stoch"

def create_stoch(
    srf_file: str,
    single_segment: bool = True,
    logger: Logger = qclogging.get_basic_logger(),
):
    """Generate a stoch file from a given srf file."""
    logger.debug(f"Processing SRF file: {srf_file}")

    if "/Srf/" not in srf_file:
        raise ValueError("Expected SRF file path to contain '/Srf/'")

    stoch_file = srf_file.replace("/Srf/", "/Stoch/").replace(".srf", ".stoch")
    out_dir = os.path.dirname(stoch_file)
    os.makedirs(out_dir, exist_ok=True)

    dx, dy = (2.0, 2.0) if srf.is_ff(srf_file) else srf.srf_dxy(srf_file)

    command = [
        SRF2STOCH,
        f"{'target_' if single_segment else ''}dx={dx}",
        f"{'target_' if single_segment else ''}dy={dy}",
        f"infile={srf_file}",
        f"outfile={stoch_file}",
    ]
    logger.debug(f"Creating stoch with command: {' '.join(command)}")
    proc = subprocess.run(command, stderr=subprocess.PIPE, check=True)
    logger.debug(f"{SRF2STOCH} stderr: {proc.stderr.decode()}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert SRF to stoch.")
    parser.add_argument("srf_file", type=str, help="Path to SRF file")
    args = parser.parse_args()
    create_stoch(args.srf_file)


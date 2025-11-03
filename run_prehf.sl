#!/bin/bash

# Please modify this file as needed, this is just a sample
#SBATCH --account=nesi00213
#SBATCH --job-name=gen_stoch.$JOBNAME
#SBATCH --partition=genoa
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --time=01:00:00
##SBATCH --mem=3G # maxmem 

set -eou pipefail

BASE_DIR=/nesi/nobackup/nesi00213/RunFolder/submit

for x in 20240122_01_sir_w_sd 20240122_01_sir_w_sdvr
do
  echo ${BASE_DIR}/$x
  cd ${BASE_DIR}/$x
  find -L Data -name "*.srf" -exec python ${BASE_DIR}/gen_stoch.py {} \;
  python ${BASE_DIR}/update_sdrop.py `pwd` i
 
  cd $BASE_DIR
  
done

for x in 20240121_01_ssr_w_c 20240122_01_ssr_w_sd 20240122_01_ssr_w_sdvr 20250424_01_ssr_w_sdvrqa_ba
do
  echo ${BASE_DIR}/$x
  cd ${BASE_DIR}/$x
  find -L Data -name "*.srf" -exec python ${BASE_DIR}/gen_stoch.py {} \;
  python ${BASE_DIR}/update_sdrop.py `pwd` s
 
  cd $BASE_DIR
  
done




# script to create a job with iterations to run gromacs
# Creates a slurm/sbatch script inside the domain dir that launches different srun 
# commands in many nodes, using 1 Node and 1GPU/node for each replica.
# Written by Erik Poppleton and Camilo Aponte-Santamaria

Help()
{
    echo "Create a gromacs job with multiple iterations queued as Slurm dependencies"
    echo
    echo "Syntax:"
    echo "resubmit_gromacs.sh niter time_limit job_name nnodes tpn-cpt-tpc-gpus path/to/tpr_file deffnm path/to/run_dir continuation(yes|no) submit(yes|no)"
    echo
    echo "Notes:"
    echo "task/cpu/thread/gpu allocation is a - separated list. e.g. 32-1-1-1 32 mpi processes, 1 omp thread/mpi proc, no hyperthreading, 1 gpu."
    echo "If this is a continuation, the checkpoint (.cpt
) file must be in the run directory and be named deffnm.cpt."
    echo "The continuation and submit options must be 'yes' or 'no'"
}
    
while getopts ":h" option; do
    case $option in
	h)
	    Help
	    exit;;
    esac
done

if [[ $# -ne 10 ]]; then
    echo "ERROR: Incorrect number of arguments"
    echo
    Help
    exit 1
fi

Niter=$1 # number of iterations (max 8)
wall_clock_limit=$2  # time per iteration. Format: hh:mm:ss
jobname=$3 #name in the queue
nnodes=$4
cpus=$5 #  mpi_task_per_node - cpus-per-task - task_per_core - n_gpus  (e.g. 32-1-1-1 32 mpi processes, 1 omp thread/mpi proc, total gpus, no hyperthreading  20-4-2 20 mpi processes, 4 omp threads with hyperthreading)
tpr=$6 # TPR FILE
deffnm=$7
outdir=$8 # absolute path
continuation=$9 # yes= iteration 1 starts from cpt, no= iteration 1 does not start from cpt
submit=${10} # yes or no submit the jobs or not


echo submit $submit


# === A) create gromacs commands ===
maxh=$( echo $wall_clock_limit | tr ":" " " | awk ' { print 0.99 * ( $1 + $2/60 + $3/3600)  } ' )


# cpu distribution:

tpn=$( echo $cpus | tr "-" " " | awk ' { print $1 } ' ) 
cpt=$( echo $cpus | tr "-" " " | awk ' { print $2 } ' ) 
tpc=$( echo $cpus | tr "-" " " | awk ' { print $3 } ' ) 
gpu=$( echo $cpus | tr "-" " " | awk ' { print $4 } ' )

iter=1
while [ $iter -le $Niter ]
do

cat>jobscript_$iter<<EOF
#!/bin/bash -l
# Standard output and error:
#SBATCH -o $outdir/slurm.%j.out
#SBATCH -e $outdir/slurm.%j.err

# Initial working directory:
#SBATCH -D $outdir

# Job Name:
#SBATCH -J $jobname

# Queue (Partition):
#SBATCH --partition=gpu

# Number of nodes and MPI tasks per node:
#SBATCH --nodes=$nnodes
#SBATCH --ntasks-per-node=$tpn
#SBATCH --cpus-per-task=$cpt
#SBATCH --threads-per-core=$tpc

# Request 32 GB of main Memory per node in Units of MB:
#SBATCH --mem=32000

# GPU stuff
#SBATCH --constraint="gpu"
#SBATCH --gres=gpu:$gpu

# Uncomment these lines if you want emails
##SBATCH --mail-type=ALL
##SBATCH --mail-user=youremail@email.edu

# Wall clock limit:
#SBATCH --time=$wall_clock_limit

# For pinning threads correctly:
export OMP_PLACES=cores
export GMX_ENABLE_DIRECT_GPU_COMM=1
export GMX_GPU_PME_DECOMPOSITION=1 

# Set your GROMACS version here
module load gromacs/2023.3

n_tasks=$((nnodes*tpn))

cd $outdir 
EOF

# Assume cpi file is the same name as the tpr file
# The .cpt file is not to be confused with the cpt variable...
# Which stands for "CPUs per taks"
#cpi=$( echo $tpr | tr "." " " | awk '{ print $1 ".cpt" }' )
cpi=$( echo $deffnm | awk '{ print $1 ".cpt" }' )

# complete with mdrun command
if [ $iter = 1 ] 
then
    if [ $continuation  = "no" ]
    then

	echo srun -n \$n_tasks gmx_mpi mdrun -s $tpr -maxh $maxh -pin on -bonded cpu -nb gpu -pme gpu -ntomp $cpt -deffnm $deffnm  >> jobscript_$iter

    else # it is a continuation and it should start from cpt
	echo srun -n \$n_tasks gmx_mpi mdrun -s $tpr -cpi $cpi -maxh $maxh -pin on -bonded cpu -nb gpu -pme gpu -ntomp $cpt -deffnm $deffnm  >> jobscript_$iter

    fi # continuation

else # iter>1
    echo srun -n \$n_tasks gmx_mpi mdrun -s $tpr -cpi $cpi -maxh $maxh -pin on -bonded cpu -nb gpu -pme gpu -ntomp $cpt -deffnm $deffnm  >> jobscript_$iter

fi # iter



if [ $submit = "yes" ]
then

    if [ $iter = 1 ]
    then
	JOBID=$(sbatch  jobscript_$iter  2>&1 | awk '{print $(NF)}')


    else # iter>1: runs with dependency
	JOBID=$(sbatch --dependency=afterany:${JOBID} jobscript_$iter 2>&1 | awk '{print $(NF)}')

    fi

    echo "  " ${JOBID}
fi

iter=$[iter+1]
done

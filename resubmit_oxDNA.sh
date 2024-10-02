# script to create a job with iterations to run oxDNA

Help()
{
    echo "Create an oxDNA job with multiple iterations queued as Slurm dependencies"
    echo
    echo "Syntax:"
    echo "resubmit_oxDNA.sh niter time_limit job_name input_file total_steps path/to/run_dir continuation(yes|no) submit(yes|no)"
    echo
    echo "Notes:"
    echo "If this is a continuation, the last_conf.dat file must be in the run directory and named last_conf.dat."
    echo "The continuation and submit options must be 'yes' or 'no'"
    echo "Your oxDNA binary must be at ~/software/oxDNA/build/bin/oxDNA"
}
    
while getopts ":h" option; do
    case $option in
	h)
	    Help
	    exit;;
    esac
done

if [[ $# -ne 8 ]]; then
    echo "ERROR: Incorrect number of arguments"
    echo
    Help
    exit 1
fi


Niter=$1 # number of iterations (max 8)
wall_clock_limit=$2  # time per iteration. Format: hh:mm:ss
jobname=$3 #name in the queue
input=$4 # input FILE
steps=$5 # the total number of steps the simulation should run for
outdir=$6 # absolute path
continuation=$7
submit=$8 # yes or no submit the jobs or not


echo submit $submit

iter=1
while [ $iter -le $Niter ]
do

cat>jobscript_$iter<<EOF
#!/bin/bash -l
# Standard output and error:
#SBATCH -o slurm.%j.out
#SBATCH -e slurm.%j.err

# Initial working directory:
#SBATCH -D $outdir

# Job Name:
#SBATCH -J $jobname

# Queue (Partition):
#SBATCH --partition=gpu

# Number of nodes and MPI tasks per node:
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1


# Request say 32 GB of main Memory per node in Units of MB:
#SBATCH --mem=32000

# GPU stuff
#SBATCH --constraint="gpu"
#SBATCH --gres=gpu:1

# Uncomment these lines if you want emails
##SBATCH --mail-type=ALL
##SBATCH --mail-user=youremail@email.edu

# Wall clock limit:
#SBATCH --time=$wall_clock_limit

cd $outdir 
module purge
module load gcc/10 cuda/11.4
EOF

# complete with mdrun command
if [ $iter = 1 ] 
then

    if [ $continuation  = "yes" ]
    then

	echo "sed -i '/restart_step_counter/c\restart_step_counter = 0' $input" >> jobscript_$iter
	echo "sed -i '/refresh_vel/c\refresh_vel = 0' $input" >> jobscript_$iter
	echo "sed -i '/^conf_file/c\conf_file = \$(lastconf_file)' $input " >> jobscript_$iter
	echo 'c_time=$(head -n 1 last_conf.dat | cut -d ' ' -f 3)' >> jobscript_$iter
	echo "e_time=$(grep '^steps' $input | tr -d ' ' | cut -d '=' -f2)" >> jobscript_$iter
	echo 'r_time=$(awk "BEGIN{print ($e_time - $c_time) }")' >> jobscript_$iter
	echo "sed -i \"/^steps/c\steps = \$r_time\" $input " >> jobscript_$iter 

    fi # continuation

else # iter>1
    echo "sed -i \"/restart_step_counter/c\restart_step_counter = 0\" $input" >> jobscript_$iter
    echo "sed -i \"/refresh_vel/c\refresh_vel = 0\" $input" >> jobscript_$iter
    echo "sed -i '/^conf_file/c\conf_file = \$(lastconf_file)' $input " >> jobscript_$iter
    echo 'c_time=$(head -n 1 last_conf.dat | cut -d ' ' -f 3)' >> jobscript_$iter
    echo "e_time=$(grep '^steps' $input | tr -d ' ' | cut -d '=' -f2)" >> jobscript_$iter
    echo 'r_time=$(awk "BEGIN{print ($e_time - $c_time) }")' >> jobscript_$iter
    echo "sed -i \"/^steps/c\steps = \$r_time\" $input " >> jobscript_$iter
 
fi # iter

echo srun ~/software/oxDNA/build/bin/oxDNA $input  >> jobscript_$iter

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

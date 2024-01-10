# script to create a job with iterations to run multiple oxDNA simulations on a single GPU

Help()
{
    echo "Create an oxDNA job with multiple iterations queued as Slurm dependencies"
    echo
    echo "Syntax:"
    echo "resubmit_oxDNA_mps.sh niter time_limit job_name input_file total_steps n_replicates path/to/run_dir continuation(yes|no) submit(yes|no)"
    echo
    echo "Notes:"
    echo "If this is a continuation, the last_conf.dat file must be in the run directory and named last_conf.dat."
    echo "Your input, topology and initial configuration should be in the parent directory of the replicate runs"
    echo "This script will create n_replicates directories each called run#.  If they already exist, it will still copy the input and all topology and configurations from the current directory into each run directory."
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

if [[ $# -ne 9 ]]; then
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
n_replicates=$6 # the number of replicate directories to look for
outdir=$7 # absolute path
continuation=$8
submit=$9 # yes or no submit the jobs or not


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

# Number of nodes and MPI tasks per node:
#SBATCH -N 1
#SBATCH -n $n_replicates
#SBATCH -c 1

# Request say 10 GB of main Memory per node in Units of MB:
#SBATCH --mem=10000

# GPU stuff
#SBATCH --constraint="gpu"
#SBATCH --gres=gpu:1

#
##SBATCH --mail-type=ALL
##SBATCH --mail-user=erik.poppleton@mr.mpg.de
# Wall clock limit:
#SBATCH --time=$wall_clock_limit

cd $outdir 
module purge
module load gcc/10 cuda/11.4
EOF

# Set up input files
if [ $iter = 1 ] 
then
    for i in $(seq 1 $n_replicates); do
	mkdir -p run$i
	cp $input run$i
	cp *.top run$i
	cp *.dat run$i
    done
    

    if [ $continuation  = "yes" ]
    then

	echo "for i in \$(seq 1 $n_replicates); do" >> jobscript_$iter
	echo sed -i \'/restart_step_counter/c\\restart_step_counter = 0\' run\$i\\/$input >> jobscript_$iter
	echo sed -i \'/refresh_vel/c\\refresh_vel = 0\' run\$i\\/$input >> jobscript_$iter
	echo sed -i \'/^conf_file/c\\conf_file = last_conf.dat\' run\$i\\/$input >> jobscript_$iter
	echo 'c_time=$(head -n 1 run$i\/last_conf.dat | cut -d " " -f 3)' >> jobscript_$iter
	echo e_time=$(grep '^steps' $input | tr -d ' ' | cut -d '=' -f2) >> jobscript_$iter
	echo 'r_time=$(awk "BEGIN{print ($e_time - $c_time) }")' >> jobscript_$iter
	echo sed -i \'/^steps/c\\steps = \$r_time\' run\$i\\/$input >> jobscript_$iter
	echo done

    fi # continuation

else # iter>1
    echo "for i in \$(seq 1 $n_replicates); do" >> jobscript_$iter
    echo sed -i \'/restart_step_counter/c\\restart_step_counter = 0\' run\$i\\/$input >> jobscript_$iter
    echo sed -i \'/refresh_vel/c\\refresh_vel = 0\' run\$i\\/$input >> jobscript_$iter
    echo sed -i \'/^conf_file/c\\conf_file = last_conf.dat\' run\$i\\/$input >> jobscript_$iter
    echo 'c_time=$(head -n 1 run$i\/last_conf.dat | cut -d " " -f 3)' >> jobscript_$iter
    echo e_time=$(grep '^steps' $input | tr -d ' ' | cut -d '=' -f2) >> jobscript_$iter
    echo 'r_time=$(awk "BEGIN{print ($e_time - $c_time) }")' >> jobscript_$iter
    echo sed -i \"/^steps/c\\steps = \$r_time\" run\$i\\/$input >> jobscript_$iter
    echo done >> jobscript_$iter
    
fi # iter

echo nvidia-cuda-mps-control -d >> jobscript_$iter
echo "for i in \$(seq 1 $n_replicates); do" >> jobscript_$iter
echo cd 'run$i' >> jobscript_$iter
echo timeout 23.9h ~/software/oxDNA/build/bin/oxDNA $input '&'  >> jobscript_$iter
echo cd .. >> jobscript_$iter
echo done >> jobscript_$iter
echo sleep 3 >> jobscript_$iter
echo nvidia-smi >> jobscript_$iter
echo wait >> jobscript_$iter
echo echo 'quit | nvidia-cuda-mps-control' >> jobscript_$iter

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

# resubmitters
Resubmit your MD simulations automatically

Based on a GROMACS resubmission script by Dr. Camillo Aponte-Santamaria.  These scripts will automatically queue multiple days of GROMACS or oxDNA simulations using Slurm dependencies for simulations that take longer than common 24-hour wall times.

### Resubmitting GROMACS jobs
`resubmit_gromacs.sh` has the following 10 required arguments:
```
n_iter : How many iterations to run
time_limit : Time per iteration
jobname : Name of job in the Slurm queue
n_nodes : How many nodes to request
resources : Allocations of cpus, gpus, and tasks in the format tasks_per_node-cpus_per_task-tasks_per_core-gpus (e.g. 1-18-1-1 for 1 task, 18 cpus for the task (-ntomp 18), no hyperthreading, 1 gpu).
tpr : path to your simulation .tpr file
deffnm : passed to the mdrun -deffnm parameter
outdir : Path to simulation directory
continuation : no if new simulation, yes if continuing from a .cpt file.  Your .cpt file must be named <deffnm>.cpt
submit : no to create Slurm files but not submit, yes to submit once files are created.
```
Run `resubmit_gromacs.sh -h` to print the help to the cli.

#### Notes
* The continuation and submit options must be 'yes' or 'no'.
* If continuing a simulation, your .cpt file must be named <deffnm>.cpt.
* gmx_mpi must be on your $PATH (if using just gmx or you have a path, edit the script).

### Resubmitting serial oxDNA jobs
`resubmit_oxDNA.sh` has the following 8 required arguments:
```
n_iter : How many iterations to run
time_limit : Time per iteration
jobname : Name of job in the Slurm queue
input : Path to the oxDNA input file
steps : Total number of steps the simulation should run for
outdir  Path to simulation directory
continuation : no if new simulation, yes if continuing from a lastconf file.  Your lastconf file must be named last_conf.dat
submit : no to create Slurm files but not submit, yes to submit once files are created.
```
Run `resubmit_oxDNA.sh -h` to print the help to the cli.

#### Notes
* The continuation and submit options must be 'yes' or 'no'.
* For a continuation, the lastconf file must be in the simulation directory and must be named last_conf.dat.
* Your oxDNA binary must be at `~/software/oxDNA/build/bin/oxDNA` (or edit the script).

### Resubmitting parallel oxDNA jobs
oxDNA does not use much GPU memory, job throughput can be significantly incrased using Nvidia Multiprocessing Service (see [this benchmark](https://lorenzo-rovigatti.github.io/oxDNA/scaling.html)).  This script will create `n_replicates` replicates of the specified simulation.

`resubmit_oxDNA_mps.sh` has the following 9 required arguments:
```
n_iter : How many iterations to run
time_limit : Time per iteration
jobname : Name of job in the Slurm queue
input : Path to the oxDNA input file
steps : Total number of steps the simulation should run for
n_replicates : Number of jobs to run in parallel
outdir  Path to simulation directory
continuation : no if new simulation, yes if continuing from a lastconf file.  Your lastconf file must be named last_conf.dat
submit : no to create Slurm files but not submit, yes to submit once files are created.
```
Run `resubmit_oxDNA_mps.sh -h` to print the help to the cli.

#### Notes
* The continuation and submit options must be 'yes' or 'no'.
* For a continuation, the lastconf file must be in the simulation directory and must be named last_conf.dat.
* Your oxDNA binary must be at `~/software/oxDNA/build/bin/oxDNA` (or edit the script).
* Your input, topology and initial configuration should be in the parent directory of the replicate runs.
* This script will create n_replicates directories each called run#.  If they already exist, it will still copy the input and all topology and configurations from the current directory into each run directory.

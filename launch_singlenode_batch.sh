#!/bin/bash
#SBATCH --job-name=mt-test
#SBATCH --nodes=1
#SBATCH --mem=100G
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:4
#SBATCH --cpus-per-task=8
#SBATCH --time=23:55:00
#SBATCH --partition=pli-c
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

WEIGHTD=$1

# Function to find an available port
find_free_port() {
    local port
    while true; do
        # Generate a random port number between 20000 and 65000
        port=$(shuf -i 29500-29510 -n 1)
        # Check if the port is in use
        if ! netstat -tuln | grep -q ":$port "; then
            echo "$port"
            break
        fi
    done
}

# Function to initialize the environment and print diagnostic information
# very important that this is run within srun for training to work!!!
init_env() {
    # Load necessary modules (adjust as needed for your system)
    module load anaconda3/2024.6

    # Activate your conda environment
    source $(conda info --base)/etc/profile.d/conda.sh
    conda activate halos

    echo "Running on node: $(hostname)"
    echo "Machine Rank: $SLURM_PROCID"
    
    export MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 1)
    export MASTER_PORT=$(find_free_port | tr -d '\n')
    export HF_DATASETS_OFFLINE=1
    export HF_HUB_OFFLINE=1
    
    echo "Master node: $MASTER_ADDR"
    echo "Number of nodes: $SLURM_JOB_NUM_NODES"
    echo "GPUs per node: $SLURM_GPUS_PER_NODE"
}

export -f init_env

# Run the training script using srun
srun --jobid=$SLURM_JOB_ID --nodes=$SLURM_JOB_NUM_NODES --ntasks-per-node=1 bash -c "
init_env
export MODEL_PATH=Qwen/Qwen2.5-3B-Instruct
export MODEL_ID=qwen-3b
export CKPT=/scratch/gpfs/sl2998/models/qwen2-5-3B-instruct-kto-01-${WEIGHTD}D-5e-6/FINAL

cd human-eval
python -m human_eval.batch_generation \
    --model-path \$MODEL_PATH \
    --model-id \$MODEL_ID \
    --num_samples_per_task 200 \
    --max-new-token 512 \
    --batch-size 1024
python -m human_eval.evaluate_functional_correctness data/\${MODEL_ID}_samples.jsonl

cd ../FastChat
python -m fastchat.llm_judge.gen_model_answer --model-path \$MODEL_PATH --model-id \$MODEL_ID
python -m fastchat.llm_judge.gen_judgment --model-list \$MODEL_ID --parallel 2
python -m fastchat.llm_judge.show_result --model-list \$MODEL_ID
"
##########################
BMV2_PATH=~/behavioral-model
##########################

THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )


CLI_PATH=$BMV2_PATH/targets/simple_switch/simple_switch_CLI

sudo PYTHONPATH=$PYTHONPATH:$BMV2_PATH/mininet/ python3 /home/p4/Early-Exit-P4/Topology.py \
   --behavioral-exe $BMV2_PATH/targets/simple_switch/simple_switch \
   --l2switch /home/p4/Early-Exit-P4/p4src/ee_adaptive.json \
   --cli $CLI_PATH

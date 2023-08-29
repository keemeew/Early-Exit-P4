* 터미널 1 - switch 관련
p4 코드 컴파일
p4c --target bmv2 --arch v1model --std p4-16 ~/early_exit/simulation/switches/ee.p4 -o ~/early_exit/simulation/switches/

veth 열기
sudo bash veth.sh
확인
ifconfig 

스위치 실행
sudo simple_switch -i 1@veth1 -i 2@veth3 --log-console --thrift-port 9090 ~/early_exit/simulation/switches/ee.json


* 터미널 2 - rule 적용
./behavioral-model/targets/simple_switch/simple_switch_CLI < ~/early_exit/simulation/switches/switch_commands/s1-commands.txt

* 터미널 3 - send.py 실행용
cd early_exit/add
sudo python3 send.py

* 터미널 4 - receive.py 실행용 (send보다 먼저 실행)
cd early_exit/add
sudo python3 receive.py

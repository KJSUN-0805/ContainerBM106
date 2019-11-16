#!/bin/bash

set -e

bold=$(tput bold)
normal=$(tput sgr0)

####################################
## input nfd name and manage network
####################################

function delete_pod(){
  vnf_name="$1"
  is_mode="$2"
  vnf_noise_name="$3"
  is_c_vnf=$(kubectl get pods | grep -o $vnf_name | grep -v NAME | wc -l)
  if [[ $is_c_vnf -gt 0 ]]; then
    echo ""
    echo "${bold}기존 테스트에서 사용한 $vnf_name을 삭제 합니다.${normal}"
    ips=($(kubectl exec -it $1 -- hostname -I))
	
	if [[ "$is_mode" = "user" ]]; then
      eth_1=$(kubectl exec -it $vnf_name -- bash -c 'ip -4 addr show eth0 | grep -oP "(?<=inet ).*(?=/)"')
      eth_2=$(kubectl exec -it $vnf_name -- bash -c 'ip -4 addr show tap1 | grep -oP "(?<=inet ).*(?=/)"')
    else
	  echo "kernel mode not yet"
    fi
	
    rm -f /root/.ssh/known_hosts
    ssh -o StrictHostKeyChecking=no root@bm-wk \
    export ips="'${ips[@]}'" \
    export eth_1="$eth_1" \
    export eth_2="$eth_2" \
    export vnf_name="$vnf_name" \
    export is_mode="$is_mode" \
'
if [[ "$is_mode" = "user" ]]; then	

  ## tx path (pg --> vppswitch(HundredGigabitEthernet18/0/2) --> pod(tap1))
  vppctl ip route del 48.0.0.0/16 via $eth_1 tap1 > /dev/null

  ## rx path (pod(tap1) --> vppswitch(HundredGigabitEthernet18/0/2) --> pg)
  vppctl ip route del 48.0.0.0/16 table 10 via 10.101.100.252 HundredGigabitEthernet18/10/1 > /dev/null
  
elif [[ "$is_mode" = "kernel" ]]; then
  echo "not yet"
fi
'
    kubectl delete pod $vnf_name
  fi
  
  is_c_vnf=$(kubectl get pods | grep -o $vnf_noise_name | grep -v NAME | wc -l)
  if [[ $is_c_vnf -gt 0 ]]; then
    echo ""
    echo "${bold}Noise VNF($vnf_noise_name)를 삭제 합니다.${normal}"
    kubectl delete pod $vnf_noise_name
  fi
}

function route_configuration()
{
  vnf_name="$1"
  is_mode="$2"
  vnf_status=$(kubectl get pods $vnf_name --no-headers | awk '/  / {print $3}')
  if [[ "$vnf_status" = "Running" ]]; then
    echo ""
    echo "${bold}Worker 노드에 Trex 플로우를 위한 라우팅 정보를 추가 합니다.${normal}"
    ips=($(kubectl exec -it $vnf_name -- hostname -I))
	
	if [[ "$is_mode" = "user" ]]; then
      eth_1=$(kubectl exec -it $vnf_name -- bash -c 'ip -4 addr show eth0 | grep -oP "(?<=inet ).*(?=/)"')
      eth_2=$(kubectl exec -it $vnf_name -- bash -c 'ip -4 addr show tap1 | grep -oP "(?<=inet ).*(?=/)"')
    else
	  echo "kernel mode not yet"
    fi
	
    rm -f /root/.ssh/known_hosts
    ssh -o StrictHostKeyChecking=no root@bm-wk \
    export ips="'${ips[@]}'" \
    export eth_1="$eth_1" \
    export eth_2="$eth_2" \
    export vnf_name="$vnf_name" \
    export is_mode="$is_mode" \
'
if [[ "$is_mode" = "user" ]]; then	

  ## tx path (pg --> vppswitch(HundredGigabitEthernet18/0/2) --> pod(tap1))
  vppctl ip route add 48.0.0.0/16 via $eth_1 tap1 > /dev/null
  
  ## rx path (pod(tap1) --> vppswitch(HundredGigabitEthernet18/0/2) --> pg)
  vppctl ip route add 48.0.0.0/16 table 10 via 10.101.100.252 HundredGigabitEthernet18/10/1 > /dev/null
  
elif [[ "$is_mode" = "kernel" ]]; then
  echo "not yet"
fi
'
  fi
} ## route_configuration


read -p "${bold}BM 테스트를 진행 하시겠습니까?(y[default] or n) :${normal}" is_process

if [[ -z $is_process ]]; then
  is_process='y'
fi

if [ "$is_process" == "y" -o "$is_process" == "Y" ]; then

  read -p "${bold}POD생성시 CPU Pinning을 하시겠습니까?(y[default] or n) :${normal}" is_cpupinning
  read -p "${bold}CPU core 수를 선택 하세요(max 2core)?(1[default] or 2) :${normal}" cpu_cores
  read -p "${bold}Memory 사용량을 입력해 주세요(min 256Mi)?(256 or 512[default]... or empty) :${normal}" mem_size
  read -p "${bold}Kernel or User mode 선택하세요?(kernel or user[default]) :${normal}" is_mode
  if [[ -z $is_cpupinning ]]; then
    is_cpupinning='y'
  fi
  if [[ -z $is_mode ]]; then
    is_mode='user'
  fi
  if [[ -z $cpu_cores ]]; then
      cpu_cores='1'
  fi
  if [[ -z $mem_size ]]; then
      mem_size='512'
  fi
  mem_unit='Mi'
  
  if [ "$is_cpupinning" = "y" -o "$is_cpupinning" = "Y" ]; then
    read -p "${bold}CPU Pinning을 위한 numa node를 선택 하세요?(0 or 1[default]) :${normal}" numa_node
    read -p "${bold}CPU Pinning을 위한 cpuset-pool을 선택하세요?(exclusive or shared or infra[default]) :${normal}" cpu_pool
    
    if [[ -z $numa_node ]]; then
        numa_node='0'
    fi
    if [[ -z $cpu_pool ]]; then
        cpu_pool='infra'
    fi
	IS_K8S=""
	CPU_KEY="cmk.intel.com\/exclusive-cores"
else
    IS_K8S="-k8s"
	CPU_KEY="cpu"
fi	

if [[ "$is_mode" = "user" ]]; then
  RESOURCES="resources:\n\
      requests:\n\
        $CPU_KEY: $cpu_cores\n\
        hugepages-2Mi: $mem_size$mem_unit\n\
        memory: $mem_size$mem_unit\n\
      limits:\n\
        $CPU_KEY: $cpu_cores\n\
        hugepages-2Mi: $mem_size$mem_unit\n\
        memory: $mem_size$mem_unit\
      "
else
  numa_node=""
  cpu_pool=""
  RESOURCES="resources:\n\
      requests:\n\
        $CPU_KEY: $cpu_cores\n\
        memory: $mem_size$mem_unit\n\
      limits:\n\
        $CPU_KEY: $cpu_cores\n\
        memory: $mem_size$mem_unit\
	  "
fi

## 기존 pod 삭제
vnf_name="bm-tester-rx$IS_K8S"
vnf_noise_name="bm-tester-rx-noise$IS_K8S"


delete_pod $vnf_name $is_mode $vnf_noise_name

# 01. Pod 생성을 위한 템플릿 yaml 정의
pushd /root/bm
cp pod/$is_mode/bm-tester-rx$IS_K8S.template pod/$is_mode/bm-tester-rx.yaml
sed -i "s/\%NUMA_NODE\%/$numa_node/" pod/$is_mode/bm-tester-rx.yaml
sed -i "s/\%CPU_POOL\%/$cpu_pool/" pod/$is_mode/bm-tester-rx.yaml
sed -i "s/\%RESOURCES\%/$RESOURCES/" pod/$is_mode/bm-tester-rx.yaml

echo "${bold} == Create BM Tester Pod (server mode) == ${normal}"
kubectl create -f pod/$is_mode/bm-tester-rx.yaml
    
vnf_status_pre=""
is_running=""
for i in {1..100}
do
  vnf_status=$(kubectl get pods $vnf_name --no-headers | awk '/  / {print $3}')
  if [ "$vnf_status_pre" != "$vnf_status" ]; then
    echo "vnf-name: $vnf_name, status: ${bold}$vnf_status${normal}"
  fi
  if [[ $vnf_status == "Running" ]]; then
    is_running=1
    break;
  fi
  sleep 1
  vnf_status_pre=$vnf_status
done # in {1..100}
	
if [[ "$is_running" = "1" ]]; then
  ## trex config 생성      
  route_configuration $vnf_name $is_mode
  kubectl exec -it $vnf_name -- /bin/bash -c \
'
# rx packet ==> eth0 to tap1 forwarding
ip route add 48.0.0.0/16 via 10.101.1.1 dev tap1
'
fi
	
cp pod/$is_mode/bm-tester-rx-noise$IS_K8S.template pod/$is_mode/bm-tester-rx-noise.yaml
sed -i "s/\%NUMA_NODE\%/$numa_node/" pod/$is_mode/bm-tester-rx-noise.yaml
sed -i "s/\%CPU_POOL\%/$cpu_pool/" pod/$is_mode/bm-tester-rx-noise.yaml
sed -i "s/\%RESOURCES\%/$RESOURCES/" pod/$is_mode/bm-tester-rx-noise.yaml
kubectl create -f pod/$is_mode/bm-tester-rx-noise.yaml
	
popd

fi

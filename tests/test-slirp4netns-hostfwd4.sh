#!/bin/bash
set -xeuo pipefail

. $(dirname $0)/common.sh

host_port=8080
guest_port=1080

unshare -r -n socat tcp-listen:$guest_port,reuseaddr,fork exec:cat,nofork &
child=$!

wait_for_network_namespace $child

tmpdir=$(mktemp -d /tmp/slirp4netns-bench.XXXXXXXXXX)
apisocket=${tmpdir}/slirp4netns.sock

slirp4netns -c $child --api-socket $apisocket tun11 &
slirp_pid=$!

wait_for_network_device $child tun11

function cleanup() {
	kill -9 $child $slirp_pid
	rm -rf $tmpdir
}
trap cleanup EXIT

set +e
result=$(cat /dev/zero | ncat -U $apisocket || true)
set set -e
echo $result | jq .error.desc | grep "bad request: too large message"

set -e
result=$(echo '{"execute": "add_hostfwd", "arguments":{"proto": "tcp","host_port":'$host_port',"guest_port":'$guest_port'}}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]
id=$(echo $result | jq .return.id)
[[ $id == 1 ]]

result=$(echo '{"execute": "list_hostfwd"}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]
[[ $(echo $result | jq .entries[0].id) == $id ]]
[[ $(echo $result | jq .entries[0].proto) == '"tcp"' ]]
[[ $(echo $result | jq .entries[0].host_addr) == '"0.0.0.0"' ]]
[[ $(echo $result | jq .entries[0].host_addr6) == null ]]
[[ $(echo $result | jq .entries[0].host_port) == $host_port ]]
[[ $(echo $result | jq .entries[0].guest_addr) == '"10.0.2.100"' ]]
[[ $(echo $result | jq .entries[0].guest_addr6) == null ]]
[[ $(echo $result | jq .entries[0].guest_port) == $guest_port ]]

result=$(echo works | nc -w 10 localhost $host_port)
[[ "$result" == "works" ]]

result=$(echo works | nc -w 10 localhost6 $host_port || true)
[[ "$result" != "works" ]]

result=$(echo '{"execute": "remove_hostfwd", "arguments":{"id": 1}}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]

result=$(echo '{"execute": "add_hostfwd", "arguments":{"proto": "tcp","host_addr":"127.0.0.1","host_port":'$host_port',"guest_port":'$guest_port'}}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]
id=$(echo $result | jq .return.id)
[[ $id == 2 ]]

result=$(echo '{"execute": "list_hostfwd"}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]
[[ $(echo $result | jq .entries[0].id) == $id ]]
[[ $(echo $result | jq .entries[0].proto) == '"tcp"' ]]
[[ $(echo $result | jq .entries[0].host_addr) == '"127.0.0.1"' ]]
[[ $(echo $result | jq .entries[0].host_addr6) == null ]]
[[ $(echo $result | jq .entries[0].host_port) == $host_port ]]
[[ $(echo $result | jq .entries[0].guest_addr) == '"10.0.2.100"' ]]
[[ $(echo $result | jq .entries[0].guest_addr6) == null ]]
[[ $(echo $result | jq .entries[0].guest_port) == $guest_port ]]

result=$(echo works | nc -w 10 localhost $host_port)
[[ "$result" == "works" ]]

result=$(echo works | nc -w 10 localhost6 $host_port || true)
[[ "$result" != "works" ]]

result=$(echo '{"execute": "remove_hostfwd", "arguments":{"id": 2}}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]

result=$(echo '{"execute": "add_hostfwd", "arguments":{"proto": "tcp6","host_port":'$host_port',"guest_port":'$guest_port'}}' | ncat -U $apisocket || true)
echo $result | jq .error.desc | grep "bad arguments.proto"

result=$(echo '{"execute": "add_hostfwd", "arguments":{"proto": "tcp","host_addr":"::1","host_port":'$host_port',"guest_port":'$guest_port'}}' | ncat -U $apisocket || true)
echo $result | jq .error.desc | grep "bad arguments.host_addr"

# see also: benchmarks/benchmark-iperf3-reverse.sh

#!/bin/bash
set -xeuo pipefail

. $(dirname $0)/common.sh

unshare -r -n sleep infinity &
child=$!

wait_for_network_namespace $child

tmpdir=$(mktemp -d /tmp/slirp4netns-bench.XXXXXXXXXX)
apisocket=${tmpdir}/slirp4netns.sock

slirp4netns -c $child --enable-ipv6 --cidr6=fd00:fb14:63ee:b::/64 --api-socket $apisocket tun11 &
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
result=$(echo '{"execute": "add_hostfwd", "arguments":{"proto": "tcp","host_port":8080,"guest_port":80}}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]
id=$(echo $result | jq .return.id)
[[ $id == 1 ]]

result=$(echo '{"execute": "list_hostfwd"}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]
[[ $(echo $result | jq .entries[0].id) == $id ]]
[[ $(echo $result | jq .entries[0].proto) == '"tcp"' ]]
[[ $(echo $result | jq .entries[0].host_addr) == '"0.0.0.0"' ]]
[[ $(echo $result | jq .entries[0].host_addr6) == '"::"' ]]
[[ $(echo $result | jq .entries[0].host_port) == 8080 ]]
[[ $(echo $result | jq .entries[0].guest_addr) == '"10.0.2.100"' ]]
[[ $(echo $result | jq .entries[0].guest_addr6) == '"fd00:fb14:63ee:b::100"' ]]
[[ $(echo $result | jq .entries[0].guest_port) == 80 ]]

result=$(echo '{"execute": "remove_hostfwd", "arguments":{"id": 1}}' | ncat -U $apisocket)
[[ $(echo $result | jq .error) == null ]]

# see also: benchmarks/benchmark-iperf3-reverse.sh

#!/bin/bash

# get host
# shellcheck disable=SC1091
source /etc/environment

# get netstat
ss -tna > /tmp/netstat-paas

# get deis services
etcdctl --no-sync ls /deis/services > /tmp/netstat-services

# clean etcd
etcdctl	--no-sync ls /deis-netstat || etcdctl --no-sync mkdir /deis-netstat
for d in $(etcdctl --no-sync ls /deis-netstat/);
do
	etcdctl --no-sync get "/deis/router/hosts/$(echo "$d"|cut -d/ -f3)" || etcdctl --no-sync rm "$d" --recursive;
done

# clean files
echo  > /tmp/netstat-paas-edges-json
echo "{ data: { id: 'all', name : 'all' , fillcolor : 'gray' , line : '#888', color : 'white', href: '' } }," > /tmp/netstat-paas-nodes-json


for d in $(cat /tmp/netstat-services);
do

	APP=$(echo "$d"|cut -d/ -f4)

	HOST=$COREOS_PRIVATE_IPV4
	EDGE_HOST="{ data: { source: '$HOST', target: '$HOST-ntop', href: '' } },"
        EDGE_HOST_NTOP="{ data: { source: '$HOST-ntop', target: '$APP', href: '' } },"

	for i in $(etcdctl --no-sync ls "$d");
	do
		IPPORT=$(etcdctl --no-sync get "$i");
		UNITTMP=$(echo "$i"|sed 's/\/deis\/services\///'|sed 's/\//\ /');
		UNIT=$(echo "$UNITTMP"|cut -d\  -f2)

		EDGE_APP="{ data: { source: '$APP', target: '$UNIT' } },"


		[ "$IPPORT" ] || continue
		IFS=$'\n'
		for z in $(grep "$IPPORT" /tmp/netstat-paas|awk '{print $1}'| grep -E 'ESTAB|TIME-WAIT|SYN-SENT' | sed -E 's/-[0-9]//g'|sort|uniq -c);
		do
			CONQT=$(echo "$z"|awk '{print $1}')

			if [ "$CONQT" -gt 10000 ]
			then
				CONCOLOR='red'

			elif [ "$CONQT" -gt 5000 ]
			then
				CONCOLOR='orange'

			elif [ "$CONQT" -gt 1000 ]
			then
				CONCOLOR='yellow'

			else
				CONCOLOR='green'
			fi

			CONTYPE=$(echo "$z"|awk '{print $2}')

			TYPECOLOR="gray"

			if [ "$CONTYPE" = "ESTAB" ]
			then
				TYPECOLOR="black"
			fi

			if [ "$CONTYPE" = "SYN-SENT" ]
			then
				TYPECOLOR="red"
			fi


			# get veth name to link to ntopng
			#IP=$(echo "$IPPORT"|cut -d: -f1)
			PORT=$(echo "$IPPORT"|cut -d: -f2)
                        INTIP=$(docker inspect -f '{{.NetworkSettings.IPAddress}}' "$UNIT")
			LINKUNIT="http://$HOST:3000/lua/port_details.lua?port=$PORT"
			LINKUNITIP="http://$HOST:3000/lua/host_details.lua?host=$INTIP"



			# { data: { id: 'j', name: 'Jerry' } },
			# /lua/port_details.lua?port=44408
			# /lua/host_details.lua?host=172.17.0.68

			(
				echo "$EDGE_HOST";
				echo "$EDGE_HOST_NTOP";
				echo "$EDGE_APP";
				echo "{ data: { source: '$UNIT', target: '$UNIT-ntop-ip'} },";
				echo "{ data: { source: '$UNIT-ntop-ip', target: '$UNIT-ntop-port'} },";
				echo "{ data: { source: '$UNIT-ntop-port', target: '$UNIT-$CONTYPE'} },";
                                echo "{ data: { source: '$UNIT-$CONTYPE', target: '$UNIT-$CONTYPE-$CONQT'} },";
				echo "{ data: { source: '$UNIT-$CONTYPE-$CONQT', target: 'all'} },";
			) >> /tmp/netstat-paas-edges-json


			(
				echo "{ data: { id: '$HOST', name: '$HOST', fillcolor: 'blue', line: 'red', color: 'white', href: '' } },";
				echo "{ data: { id: '$HOST-ntop', name: 'ntop', fillcolor: 'blue', line: 'red', color: 'white', href: 'http://$HOST:3000/?page=TopPorts' } },";

				echo "{ data: { id: '$APP', name: '$APP', fillcolor: '#00AAFF', line: '#33CC66', color: '#ff2366', href: '' } },";
        	                echo "{ data: { id: '$UNIT', name: '$UNIT' , fillcolor: '#33CC66' , line: '#ff2366', color: '#00AAFF', href: '' } },";
                                echo "{ data: { id: '$UNIT-ntop-port', name: 'ntop-port' , fillcolor: 'orange' , line: '$TYPECOLOR', color: 'white', href: '$LINKUNIT' } },";
                                echo "{ data: { id: '$UNIT-ntop-ip', name: 'ntop-ip' , fillcolor: 'orange' , line: '$TYPECOLOR', color: 'white', href: '$LINKUNITIP' } },";
				echo "{ data: { id: '$UNIT-$CONTYPE', name: '$CONTYPE' , fillcolor: '$TYPECOLOR' , line: '$TYPECOLOR', color: 'white', href: '' } },";
                        	echo "{ data: { id: '$UNIT-$CONTYPE-$CONQT', name : '$CONQT' , fillcolor : '$CONCOLOR' , line : '#888', color : 'white', href: '' } },"
			) >> /tmp/netstat-paas-nodes-json

		done
	done
done

sort < /tmp/netstat-paas-edges-json | uniq | etcdctl --no-sync set "/deis-netstat/$HOST/edges" > /dev/null
etcdctl --no-sync set "/deis-netstat/$HOST/nodes" < /tmp/netstat-paas-nodes-json > /dev/null

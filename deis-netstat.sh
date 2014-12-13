#!/bin/bash

# get host
source /etc/environment

# get netstat
netstat -tpano > /tmp/netstat-paas

# get macadress
brctl showmacs docker0 |awk '{print $1 " " $3 " " $2}' |sort > /tmp/netstat-docker-macs

# get veth names
for d in `ls /sys/class/net/|grep veth`; do echo -n "$d  "; cat /sys/class/net/$d/address ; done > /tmp/netstat-veth-mac

# get deis services
etcdctl --no-sync ls /deis/services > /tmp/netstat-services

# clean etcd
etcdctl	--no-sync ls /deis-netstat || etcdctl --no-sync mkdir /deis-netstat
for d in `etcdctl --no-sync ls /deis-netstat/`;
do
	etcdctl --no-sync get /deis/router/hosts/`echo $d|cut -d/ -f3`|| etcdctl --no-sync rm $d --recursive;
done

# get ntopng interfaces index
curl -s --max-time 1 http://localhost:3000/lua/about.lua |grep set_active_interface.lua|sed 's/.*<li><a href="//'|sed 's/<\/li>//'|sed 's/">/\ /'|sed 's/<\/a>//' > /tmp/netstat-ntop-ifaces

# clean files
echo  > /tmp/netstat-paas-edges-json
echo "{ data: { id: 'all', name : 'all' , fillcolor : 'gray' , line : '#888', color : 'white', href: '' } }," > /tmp/netstat-paas-nodes-json


for d in `cat /tmp/netstat-services`;
do

	APP=`echo $d|cut -d/ -f4`

	HOST=$COREOS_PRIVATE_IPV4
	EDGE_HOST="{ data: { source: '$COREOS_PRIVATE_IPV4', target: '$APP' } },"

	for i in `etcdctl --no-sync ls $d`;
	do
		IPPORT=`etcdctl --no-sync get $i`;
		UNITTMP=`echo $i|sed 's/\/deis\/services\///'|sed 's/\//\ /'` ;
		UNIT=`echo $UNITTMP|cut -d\  -f2`

		EDGE_APP="{ data: { source: '$APP', target: '$UNIT' } },"


		[ $IPPORT ] || continue
		IFS=$'\n'
		for z in `grep $IPPORT /tmp/netstat-paas|awk '{print $6}'|sort|uniq -c `;
		do
			CONQT=`echo $z|awk '{print $1}'`

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

			CONTYPE=`echo $z|awk '{print $2}'`


			if [ "$CONTYPE" = "ESTABLISHED" ]
			then
				TYPECOLOR="black"
			else
				TYPECOLOR="gray"
			fi


			# get veth name to link to ntopng
			INTMAC=`docker inspect --format '{{ .NetworkSettings.MacAddress }}' $UNIT`
			[ -n $INTMAC ] && INTMACINDEX=`grep $INTMAC /tmp/netstat-docker-macs |awk '{print $1}'`
			[ -n $INTMACINDEX ] && EXTMAC=`grep "^$INTMACINDEX yes" /tmp/netstat-docker-macs |awk '{print $3}'`
			[ -n $EXTMAC ] && VETH=`grep "$EXTMAC" /tmp/netstat-veth-mac |awk '{print $1}'`
			[ -n $VETH ] && SETIFACE=`grep "$VETH" /tmp/netstat-ntop-ifaces |awk '{print $1}'`
			[ -n $VETH ] && LINKUNIT="http://$HOST:3000$SETIFACE"

			# { data: { id: 'j', name: 'Jerry' } },
			(
				echo $EDGE_HOST;
				echo $EDGE_APP;
				echo "{ data: { source: '$UNIT', target: '$UNIT-$CONTYPE'} },";
                                echo "{ data: { source: '$UNIT-$CONTYPE', target: '$UNIT-$CONTYPE-$CONQT'} },";
				echo "{ data: { source: '$UNIT-$CONTYPE-$CONQT', target: 'all'} },";
			) >> /tmp/netstat-paas-edges-json


			(
				echo "{ data: { id: '$HOST', name: '$HOST', fillcolor: 'blue', line: 'red', color: 'white', href: 'http://$HOST:3000' } },";
				echo "{ data: { id: '$APP', name: '$APP', fillcolor: '#00AAFF', line: '#33CC66', color: '#ff2366', href: '$LINKUNIT' } },";
        	                echo "{ data: { id: '$UNIT', name: '$UNIT' , fillcolor: '#33CC66' , line: '#ff2366', color: '#00AAFF', href: '$LINKUNIT' } },";
				echo "{ data: { id: '$UNIT-$CONTYPE', name: '$CONTYPE' , fillcolor: '$TYPECOLOR' , line: '$TYPECOLOR', color: 'white', href: '$LINKUNIT' } },";
                        	echo "{ data: { id: '$UNIT-$CONTYPE-$CONQT', name : '$CONQT' , fillcolor : '$CONCOLOR' , line : '#888', color : 'white', href: '$LINKUNIT' } },"
			) >> /tmp/netstat-paas-nodes-json

		done
	done
done

cat /tmp/netstat-paas-edges-json |sort|uniq| etcdctl --no-sync set /deis-netstat/$HOST/edges
cat /tmp/netstat-paas-nodes-json | etcdctl --no-sync set /deis-netstat/$HOST/nodes

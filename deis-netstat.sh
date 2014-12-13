#!/bin/bash

# get host
source /etc/environment

# get netstat
netstat -tupano > /tmp/netstat-paas

# get deis services
etcdctl --no-sync ls /deis/services > /tmp/netstat-services

# clean etcd
etcdctl	--no-sync ls /deis-mon || etcdctl --no-sync mkdir /deis-mon
for d in `etcdctl --no-sync ls /deis-mon/`;
do
	etcdctl --no-sync get /deis/router/hosts/`echo $d|cut -d/ -f3`|| etcdctl --no-sync rm $d --recursive;
done

# clean files
echo  > /tmp/netstat-paas-edges-json
echo "{ data: { id: 'all', name : 'all' , fillcolor : 'gray' , line : '#888', color : 'white' } }," > /tmp/netstat-paas-nodes-json


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

			# { data: { id: 'j', name: 'Jerry' } },
			(
				echo $EDGE_HOST;
				echo $EDGE_APP;
				echo "{ data: { source: '$UNIT', target: '$UNIT-$CONTYPE'} },";
                                echo "{ data: { source: '$UNIT-$CONTYPE', target: '$UNIT-$CONTYPE-$CONQT'} },";
				echo "{ data: { source: '$UNIT-$CONTYPE-$CONQT', target: 'all'} },";
			) >> /tmp/netstat-paas-edges-json


			(
				echo "{ data: { id: '$HOST', name : '$HOST' , fillcolor : 'blue' , line : 'red', color : 'white' } },";
				echo "{ data: { id: '$APP', name : '$APP' , fillcolor : '#00AAFF' , line : '#33CC66', color : '#ff2366' } },";
        	                echo "{ data: { id: '$UNIT', name : '$UNIT' , fillcolor : '#33CC66' , line : '#ff2366', color : '#00AAFF' } },";
				echo "{ data: { id: '$UNIT-$CONTYPE', name : '$CONTYPE' , fillcolor : '$TYPECOLOR' , line : '$TYPECOLOR', color : 'white' } },";
                        	echo "{ data: { id: '$UNIT-$CONTYPE-$CONQT', name : '$CONQT' , fillcolor : '$CONCOLOR' , line : '#888', color : 'white' } },"
			) >> /tmp/netstat-paas-nodes-json

		done
	done
done

cat /tmp/netstat-paas-edges-json |sort|uniq| etcdctl --no-sync set /deis-mon/$HOST/edges
cat /tmp/netstat-paas-nodes-json | etcdctl --no-sync set /deis-mon/$HOST/nodes

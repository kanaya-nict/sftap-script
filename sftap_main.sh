#!/usr/bin/env bash

ETH_INTERFACE=enp1s0f1
#DATA_DIR=/work1/data/sf-tap
# DATA_DIR=/work3/datavlan/sf-tap
DATA_DIR=/mnt/dss00_data/stardust/sftap_vlan
BIN_DIR=/usr/local/bin
SFTAP_CONFIG=/usr/local/etc/fabs.yaml
SFTAP_CONFIG_TCP=/usr/local/etc/fabs_tcp.yaml
SUFFIX=`date '+%Y%m%d%H%M%S'`

sleep 10
case $1 in
    "dns")
	PIDFile=/var/run/sftap_dns.pid
	${BIN_DIR}/sftap_dns| tee ${DATA_DIR}/dns_query/raw/rawdata${SUFFIX}.json|perl -I${BIN_DIR} ${BIN_DIR}/dns_list_vlan.pl ${DATA_DIR}/dns_query/data >& ${DATA_DIR}/log/dns_log${SUFFIX}.log & 
	;;
    "http")
	PIDFile=/var/run/sftap_http.pid
	python3.4 ${BIN_DIR}/sftap_http.py| tee ${DATA_DIR}/http/raw/rawdata${SUFFIX}.json|perl -I${BIN_DIR} ${BIN_DIR}/sftap_divide.pl -d ${DATA_DIR}/http/data http >& ${DATA_DIR}/log/http_log${SUFFIX}.log &
	;;
    "http_proxy")
	PIDFile=/var/run/sftap_http_proxy.pid
	python3.4 ${BIN_DIR}/sftap_http.py /tmp/sf-tap/tcp/http_proxy nobody|perl -I${BIN_DIR} ${BIN_DIR}/sftap_divide.pl -d ${DATA_DIR}/http_proxy/data http_proxy >& ${DATA_DIR}/log/http_proxy_log${SUFFIX}.log &
	;;
    "syslog")
	PIDFile=/var/run/sftap_syslog.pid
	perl -I${BIN_DIR} ${BIN_DIR}/sftap_syslog_divide.pl ${DATA_DIR}/syslog/data >& ${DATA_DIR}/log/syslog${SUFFIX}.log &
	;;
    "yarai")
	PIDFile=/var/run/sftap_yarai.pid
	perl -I${BIN_DIR} ${BIN_DIR}/parse_yarai.pl ${DATA_DIR}/yarai/data >& ${DATA_DIR}/log/yarai${SUFFIX}.log &
	;;
    "trans_yarai")
	echo "start trans yarai"
	PIDFile=/var/run/sftap_trans_yarai.pid
	perl -I${BIN_DIR} ${BIN_DIR}/trans_yarai.pl >& ${DATA_DIR}/log/trans_yarai${SUFFIX}.log &
	;;
    "icmp")
	echo "start icmp"
	PIDFile=/var/run/sftap_icmp.pid
	${BIN_DIR}/sftap_icmp|perl -I${BIN_DIR} ${BIN_DIR}/sftap_divide.pl ${DATA_DIR}/icmp/data  >& ${DATA_DIR}/log/icmp${SUFFIX}.log &
	;;
    "tcp")
	echo "start tcp"
	PIDFile=/var/run/sftap_tcp.pid
	perl -I${BIN_DIR} ${BIN_DIR}/parse_tcp.pl ${DATA_DIR}/tcp/data >& ${DATA_DIR}/log/tcp${SUFFIX}.log &
	;;
    "tcp_main")
	echo "start tcp"
	PIDFile=/var/run/sftap_tcp_main.pid
	${BIN_DIR}/sftap_fabs -i ${ETH_INTERFACE} -c ${SFTAP_CONFIG_TCP}  >&${DATA_DIR}/log/tcp_main_log${SUFFIX}.log &
	;;
    "webdav")
	echo "start webdav"
	PIDFile=/var/run/sftap_webdav.pid
	perl -I${BIN_DIR} ${BIN_DIR}/parse_webdav.pl ${DATA_DIR}/webdav/data >& ${DATA_DIR}/log/webdav${SUFFIX}.log &
	;;
    *)
	PIDFile=/var/run/sftap_main.pid
	${BIN_DIR}/sftap_fabs -i ${ETH_INTERFACE} -c ${SFTAP_CONFIG}  >&${DATA_DIR}/log/log${SUFFIX}.log &
	;;
esac
MAIN_PID=$!
echo $MAIN_PID   >${PIDFile}

sleep 10
exit 0;


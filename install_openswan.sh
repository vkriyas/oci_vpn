#!/bin/bash
#
# install_openswan_vpn.sh
#
#   NAME
#      install_openswan_vpn.sh
#
#   DESCRIPTION
#      This script will setup openswan vpn
#
#   BUG REPORT
#      riyas.vattakkandy@oracle.com
#
#
#
#



# Sorround each param with quotes so we can handle arguments with
# whitespaces as well.
#
unset PARAMS
for i in "$@"
do
 # echo ${i}
 PARAMS="$PARAMS \"${i}\""
done

# Initial settings
_sbinDir=/sbin
_binDir=/bin
_usrBinDir=/usr/bin

function usage
{

cat  << EOF

Before you begin, you need to setup VPNaaS on the desired IP network from OCI console and obtain the opc_public_ip and secret_key

    Usage:
        # install_openswan_vpn.sh --my_public_ip --opc_public_ip --opc_subnet --secret_key

    if you want to specify additional parameters:
        # install_openswan_vpn.sh --my_public_ip --my_private_ip --my_subnet --opc_public_ip --opc_subnet --secret_key"

EOF
}

if [ "$1" == "" ]; then
usage
exit 1
fi

# MAIN
while [ "$1" != "" ]; do
    case $1 in
         --my_public_ip )       shift
                                MY_PUBLIC_IP=$1
                                ;;

        --my_private_ip )       shift
                                MY_PRIVATE_IP=$1
                                ;;

        --my_subnet )           shift
                                MY_SUBNET=$1
                                ;;
        --opc_public_ip )       shift
                                OPC_PUBLIC_IP=$1
                                ;;
        --opc_subnet )          shift
                                OPC_SUBNET=$1
                                ;;

        --secret_key )          shift
                                SECRET_KEY=$1
                                ;;
        -h | --help )           usage
                                exit 1
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done


if [ "$MY_PUBLIC_IP" == "" ]; then
echo -e "\n Error: --my_public_ip must be specified\n"
usage
exit 1
fi

if [ "$MY_PRIVATE_IP" == "" ]; then
MY_PRIVATE_IP=`ip a show eth0| awk '/eth0/{sub(/\/.*$/,"",$2); print $2}'|grep -v eth0`
fi

if [ "$MY_SUBNET" == "" ]; then
eval $(ipcalc -np $( ip -o -f inet addr show | grep eth0 |  awk '/scope global/ {print $4}'))
MY_SUBNET=$NETWORK/$PREFIX
fi

if [ "$OPC_PUBLIC_IP" == "" ]; then
echo -e "\n Error: --opc_public_ip must be specified\n"
usage
exit 1
fi

if [ "$OPC_SUBNET" == "" ]; then
echo -e "\n Error: --opc_subnet must be specified\n"
usage
exit 1
fi

if [ "$SECRET_KEY" == "" ]; then
echo -e "\n Error: --secret_key must be specified\n"
usage
exit 1
fi

echo "Installing openswan.."

yum install -y openswan

if rpm -q openswan | rpm -q libreswan ; then
        echo "ERROR: failed to install openswan"
fi

echo "Configuring system paramters .."

echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf


for interface in `ls /proc/sys/net/ipv4/conf/`
do
        echo net.ipv4.conf.$interface.accept_redirects = 0 >> /etc/sysctl.conf
        echo net.ipv4.conf.$interface.send_redirects = 0 >> /etc/sysctl.conf

        echo net.ipv4.conf.$interface.rp_filter = 2 >> /etc/sysctl.conf

done

sysctl -p
iptables -F
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

service iptables save

echo "Configuring openswan .."

mv /etc/ipsec.conf /etc/ipsec.conf.bak
cat <<EOF >> /etc/ipsec.conf
config setup
        plutodebug=all
        plutostderrlog=/var/log/pluto.log
        protostack=netkey
        nat_traversal=yes
        virtual_private=%v4:$MY_SUBNET
        # OE is now off by default. Uncomment and change to on, to enable.
        oe=off
conn mysubnet
        also=myvpn
        leftsubnet=$MY_SUBNET
        rightsubnet=$OPC_SUBNET
conn myvpn
        authby=secret
        auto=start
        pfs=yes
        left=$MY_PRIVATE_IP
        leftid=$MY_PUBLIC_IP
        right=$OPC_PUBLIC_IP
        rightid=$OPC_PUBLIC_IP
        ike=aes256-sha1;modp1024
        phase2alg=aes256-sha1;modp1024
EOF

cat <<EOF >> /etc/ipsec.secrets
$MY_PUBLIC_IP $OPC_PUBLIC_IP : PSK "$SECRET_KEY"
EOF
echo "starting openswan.."

service ipsec restart

echo "verifying ipsec .."

ipsec verify

ipsec  auto status

echo "Done"

#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
ln -fs /usr/share/zoneinfo/UTC /etc/localtime
echo "UTC" > /etc/timezone

apt-get update
apt-get install -y sudo apache2 apache2-utils curl wget net-tools tzdata nano fontconfig gnupg1 gnupg2 gnupg pacemaker corosync pcs resource-agents iputils-ping iproute2 netcat systemd openssh-client openssh-server crmsh cron

debconf-set-selections <<< 'tzdata tzdata/Areas select Etc'
debconf-set-selections <<< 'tzdata tzdata/Zones/Etc select UTC'
apt-get install -y --reinstall tzdata

service cron start

service apache2 stop
update-rc.d apache2 disable

tee -a /etc/hosts << 'EOF'
172.20.0.102    webz-001
172.20.0.103    webz-002
172.20.0.104    webz-003
172.20.0.105    jenkins
EOF

cat /shared/totem.conf  > /etc/corosync/corosync.conf

echo "Creating Apache homepage..."
mkdir -p /var/www/html

# VIP_NODE=$(crm status | grep "vip.*Started" | awk '{print $NF}')
# echo "Junior DevOps Engineer - Home Task on $VIP_NODE" > /var/www/html/index.html

echo "Configuring Apache..."
sed -i 's/Listen 80/Listen 0.0.0.0:80/' /etc/apache2/ports.conf

service corosync start
service pacemaker start


# --- Cluster Configuration ---
if [ "$(hostname)" == "webz-001" ]; then
  echo "This is webz-001. Waiting for cluster to stabilize before configuration..."
  for i in {1..12}; do
    if crm status | grep -q "Online: \[ webz-001 webz-002 webz-003 \]"; then
      echo "All nodes are online."
      break
    fi
    echo "Waiting for all nodes to come online... (attempt $i/12)"
    sleep 10
  done

  echo "Running initial cluster configuration..."

  crm configure property stonith-enabled=false >/dev/null 2>&1
  crm configure property no-quorum-policy=ignore >/dev/null 2>&1

  echo "Ensuring primitive 'vip' is configured correctly..."
  crm configure primitive vip ocf:heartbeat:IPaddr2 params ip="172.20.0.100" nic="eth0" cidr_netmask="16" op monitor interval="10s"

  echo "Ensuring primitive 'webserver' is configured correctly..."
  crm configure primitive webserver ocf:heartbeat:apache op monitor interval="10s"

  echo "Ensuring group 'vip_group' is configured correctly..."
  crm configure group vip_group vip webserver

  echo "Cluster configuration complete."
else
  echo "This is not webz-001. Skipping cluster configuration."
fi

cat << 'EOF' > /usr/local/bin/update_vip_node.sh
#!/bin/bash
VIP_NODE=$(/usr/sbin/crm status | grep "vip.*Started" | awk '{print $NF}')
echo "Junior DevOps Engineer - Home Task on $VIP_NODE" > /var/www/html/index.html
EOF

chmod +x /usr/local/bin/update_vip_node.sh

(crontab -l 2>/dev/null; echo '* * * * * /usr/local/bin/update_vip_node.sh') | crontab -
# echo "Junior DevOps Engineer - Home Task on $(crm status | grep "vip.*Started" | awk '{print $NF}')" > /var/www/html/index.html'


echo "=== Cluster node setup completed on $(hostname) ==="
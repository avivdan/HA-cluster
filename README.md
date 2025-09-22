# Project Overview: HA Web Cluster + Jenkins Monitoring

This project is a Docker-based lab that demonstrates a highly-available web service using Pacemaker/Corosync across three Ubuntu nodes, plus a Jenkins controller for simple health checks and observability. It’s useful for learning cluster concepts, testing failover, and showcasing resource management.

## Contents

- `docker-compose.yaml`: Defines three Ubuntu nodes (`webz-001..003`) and a `jenkins` service on a bridged network (`172.20.0.0/16`).
- `shared/cluster_install.sh`: Bootstraps each Ubuntu node with Apache, Corosync, Pacemaker, and configures the cluster.
- `shared/totem.conf`: Corosync configuration used by all nodes.
- `jenkins_script.groovy`: Example Jenkins job step that curls the cluster VIP and logs to `crl.log` in the Jenkins home.

## What gets set up

- Three nodes: `webz-001` (172.20.0.102), `webz-002` (172.20.0.103), `webz-003` (172.20.0.104)
- Jenkins: `jenkins` (172.20.0.105), exposed on host: `http://localhost:8081`
- Apache on all nodes, managed by Pacemaker
- Corosync/Pacemaker cluster with:
  - VIP primitive: `172.20.0.100/16` on `eth0`
  - Apache primitive: `ocf:heartbeat:apache`
  - Group `vip_group`: `vip + webserver`
  - Cluster properties: `stonith-enabled=false`

Note: The VIP (`172.20.0.100`) exists inside the compose network and is not published to the host. Access it from within the containers or via the Jenkins container.

## Usage

From this `test` directory:

```bash
docker compose up -d
```

Wait ~1–2 minutes for the cluster to stabilize. You can then:

- Open Jenkins UI: `http://localhost:8081`
- Inspect cluster status:

```bash
docker exec -it webz-001 crm status | cat
```

- Curl the VIP from within a node (expected to return the demo index page):

```bash
docker exec -it webz-001 bash -lc "curl -s 172.20.0.100"
```

- See Corosync logs:

```bash
docker exec -it webz-001 bash -lc "tail -n 100 /var/log/corosync/corosync.log"
```

To stop and clean up:

```bash
docker compose down
```

Jenkins data is stored on the host under `./jenkins_home` (bind mount). Remove this directory manually if you want a fresh Jenkins home.

## Jenkins note

The Jenkins container uses the official LTS image with JDK 17. The sample `jenkins_script.groovy` shows how to curl the VIP and append a timestamped line into `/var/jenkins_home/crl.log`. Create a Freestyle job (or a Pipeline) with an Execute Shell step using that example to observe which node serves the VIP during failover.

## Troubleshooting

- If `crm status` does not show all three nodes online, wait a bit longer or check services:

```bash
docker exec -it webz-001 bash -lc "service corosync status && service pacemaker status"
```

- Review cluster config applied on `webz-001` in `shared/cluster_install.sh`.
- Verify `/etc/hosts` inside nodes includes all cluster hostnames (`webz-001..003`, `jenkins`).
- Confirm `apache2` is not bound to host-only addresses (`ports.conf` is updated to `0.0.0.0:80` by the script).

## Notes

- Base images are `ubuntu:18.04` for the cluster nodes; package downloads occur on first boot.
- The VIP is internal to the Docker network; it is not reachable from the host without additional routing.

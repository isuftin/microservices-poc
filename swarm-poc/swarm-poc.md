## Creating Docker master and worker machines

#### Network interface

On MacOS (and probably other OS using VirtualBox), I tend to create docker machine
VMs using `--virtualbox-hostonly-nictype Am79C973`. [More info here.](https://github.com/docker/machine/issues/1942)
This seems to resolve a issues I see in downloads stalling when grabbing Docker images.

I also make sure to allocate a gigabyte of memory to each machine for the purposes
of this POC.

- `docker-machine create -d virtualbox --virtualbox-memory "1024" --virtualbox-hostonly-nictype Am79C973 <machine name>`

#### SSL Certificate

Once the machines are created, I want to put the DOI root certificate on them so
that they are able to pull Docker images from DockerHub. This is only needed when
on a network with SSL interception happening.

I have the root certificate sitting in the same directory I am running the command
to copy it into the machine. It is named root.crt. The certificate is not included
in this repository.

```bash
echo "sudo mkdir -p /var/lib/boot2docker/certs; \
echo "\""$(cat root.crt)"\"" | \
sudo tee -a /var/lib/boot2docker/certs/root.crt" | \
docker-machine ssh <machine name> && docker-machine restart <machine name>
```

When broken down, what this command set does is execute a few commands on the actual
Docker Machine VM. It does so by encapsulating the commands within an echo statement
and pipes that through to `docker-machine ssh` which performs remote execution via
SSH on the guest.

The commands are:
- `sudo mkdir -p /var/lib/boot2docker/certs` This creates the `/var/lib/boot2docker/certs`
directory in the guest. This is a special directory for Docker Machine. Any SSL certificates
in that directory will be incorporated into the system root SSL upon reboot. The
Docker engine on the guest uses that to verify HTTPS connections which it uses
to pull images from DockerHub
- `echo "\""$(cat root.crt)"\""` This command actually reads the certificate from the
host system and puts the file contents into an echo command on the guest
- `sudo tee -a /var/lib/boot2docker/certs/root.crt` - This command takes the contents
of the echo command above and appends it to a file at `/var/lib/boot2docker/certs/root.crt`.
On a new machine, that file does not exit until this command is run.
- `docker-machine ssh <machine name>` - This command takes the entire echo statement and
performs the execution of the contents on the guest.
- `docker-machine restart <machine name>` - Restarts the guest

#### Machine creation

Because I want to create multiple machines and send the certificate to all of them,
it would be tedious to do this multiple times. I can just run a script to do this.

The [following script](./multi-create.sh) creates four machines named `master1`, `worker1`, `worker2`
and `worker3`

```bash

#!/bin/bash

array=( manager1 worker1 worker2 worker3 )
for machine in "${array[@]}"
do
	echo "Creating Docker machine '$machine'"
	docker-machine create -d virtualbox --virtualbox-memory "1024" --virtualbox-hostonly-nictype Am79C973 $machine

	echo "Adding certificate to machine '$machine'"
	echo "sudo mkdir -p /var/lib/boot2docker/certs; \
	echo "\""$(cat root.crt)"\"" | \
	sudo tee -a /var/lib/boot2docker/certs/root.crt" | \
	docker-machine ssh $machine

	echo "Restarting machine '$machine'"
	docker-machine restart $machine
done

```

This is an example of what you should see:

```

Creating Docker machine 'worker3'
Running pre-create checks...
Creating machine...
(worker3) Copying /Users/your_user/.docker/machine/cache/boot2docker.iso to /Users/your_user/.docker/machine/machines/worker3/boot2docker.iso...
(worker3) Creating VirtualBox VM...
(worker3) Creating SSH key...
(worker3) Starting the VM...
(worker3) Check network to re-create if needed...
(worker3) Waiting for an IP...
Waiting for machine to be running, this may take a few minutes...
Detecting operating system of created instance...
Waiting for SSH to be available...
Detecting the provisioner...
Provisioning with boot2docker...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Checking connection to Docker...
Docker is up and running!
To see how to connect your Docker Client to the Docker Engine running on this virtual machine, run: docker-machine env worker3
Adding certificate to machine 'worker3'
Boot2Docker version 17.05.0-ce, build HEAD : 5ed2840 - Fri May  5 21:04:09 UTC 2017
Docker version 17.05.0-ce, build 89658be
-----BEGIN CERTIFICATE-----
MIIJ...
...cUw=
-----END CERTIFICATE-----
Restarting machine 'worker3'
Restarting "worker3"...
(worker3) Check network to re-create if needed...
(worker3) Waiting for an IP...
Waiting for SSH to be available...
Detecting the provisioner...
Restarted machines may have new IP addresses. You may need to re-run the `docker-machine env` command.

```

#### Communicating with machines

Once a Docker machine is live, your Docker client on your host still needs to
have certain environment variables set in order to communicate to the Docker engine
running on the guest. Without taking this step, your Docker client doesn't know how
to communicate to the Docker engine on the guest.

```bash

$ docker ps
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?

```

Docker Machine makes the fix pretty simple. You can just run the following command:

```bash

$ eval $(docker-machine env manager1)
$ docker version
Client:
 Version:      17.05.0-ce
 API version:  1.29
 Go version:   go1.8.1
 Git commit:   89658be
 Built:
 OS/Arch:      darwin/amd64

Server:
 Version:      17.05.0-ce
 API version:  1.29 (minimum version 1.12)
 Go version:   go1.7.5
 Git commit:   89658be
 Built:        Thu May  4 21:43:09 2017
 OS/Arch:      linux/amd64
 Experimental: false

```

Notice that this points to only one machine (`manager1`). Each shell session may only point to
one machine at a time because the Docker client cannot communicate to more than
one machine at a time. One solution is to run multiple terminals or run screen, tmux
or byobu to have a setup to communicate to multiple machines.

A function that I use in my .bashrc file is the following:

```bash

dminitfunc() {
        eval $(docker-machine env $1)
}
alias dminit=dminitfunc

```

This is a convenience method which allows me to simply type `dminit <machine name>`
in order to perform the same command as `eval $(docker-machine env <machine name>)`.
This is shorter and easier to remember.

#### Creating the swarm manager

In order to create a swam on each machine, we will need to execute commands within
the machine to initiate it.

For the manager machine, first find the IP of the guest by issuing:

```bash

$ docker-machine ip manager1
192.168.99.100

```  

Your IP results may vary. Once you have the IP, ssh into the guest and initiate
the Docker engine to act as a swarm manager node:

```bash

$ docker-machine ssh manager1
Boot2Docker version 17.05.0-ce, build HEAD : 5ed2840 - Fri May  5 21:04:09 UTC 2017
Docker version 17.05.0-ce, build 89658be

$ docker swarm init --advertise-addr 192.168.99.100
Swarm initialized: current node (m6w5n499uj2ysz2ydi8bh6z0b) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join \
    --token SWMTKN-1-1txpd8f1zng0hjrk2s5cp6ad582cjmkrda68h71r8hz2at8ws7-b49qu52qohlo00wjv27e8saso \
    192.168.99.100:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```

This can also be done in one line:

`$ docker-machine ip manager1 | docker-machine ssh manager1 xargs docker swarm init --advertise-addr`

The reason that the advertise address is added is because other nodes will need to
connect to the manager node at the external address for the node. Note that the
initialization cause the node to automatically be registered as a manager. This is
the default behavior in initializing a Docker node into a swarm. Any workers will
be initialized in a different way as we will see later.

Back on the host, we can begin looking at swarm information to verify that we do
have at least a manager.

```bash

$ docker-machine ssh manager1 docker info
[...]
Swarm: active
 NodeID: m6w5n499uj2ysz2ydi8bh6z0b
 Is Manager: true
 ClusterID: 9477wo0nani9o2hmexx761ica
 Managers: 1
 Nodes: 1
 Orchestration:
 Task History Retention Limit: 5
Raft:
 Snapshot Interval: 10000
 Number of Old Snapshots to Retain: 0
 Heartbeat Tick: 1
 Election Tick: 3
Dispatcher:
 Heartbeat Period: 5 seconds
CA Configuration:
 Expiry Duration: 3 months
Node Address: 192.168.99.100
Manager Addresses:
 192.168.99.100:2377
[...]

```

#### Creating the swarm workers

Now that there's a manager available, I can begin adding workers to the swarm.

Using the join token I attained when creating the master node, I initialize each
worker node into the swarm and use the join token with the master node's IP address.
If you ever forget the worker join token, you can get it by executing
`docker swarm join-token -q worker` on the manager guest:

```bash

$ docker-machine ssh manager1 docker swarm join-token -q worker
SWMTKN-1-1txpd8f1zng0hjrk2s5cp6ad582cjmkrda68h71r8hz2at8ws7-2uajx9n7md4cx0njncir5g7ns

```

If you want the full usage, drop the -q flag:

```bash

$ docker-machine ssh manager1 docker swarm join-token worker
To add a manager to this swarm, run the following command:

    docker swarm join \
    --token SWMTKN-1-1txpd8f1zng0hjrk2s5cp6ad582cjmkrda68h71r8hz2at8ws7-2uajx9n7md4cx0njncir5g7ns \
    192.168.99.100:2377

```
Remember that this should be done in a different terminal that was initialized with
the environment variables pointing to worker1:

```bash

$ docker-machine ssh worker1
Boot2Docker version 17.05.0-ce, build HEAD : 5ed2840 - Fri May  5 21:04:09 UTC 2017
Docker version 17.05.0-ce, build 89658be
docker@worker1:~$ docker swarm join \
>     --token SWMTKN-1-1txpd8f1zng0hjrk2s5cp6ad582cjmkrda68h71r8hz2at8ws7-b49qu52qohlo00wjv27e8saso \
>     192.168.99.100:2377
This node joined a swarm as a worker.

```

This should be done on all available workers.

This process can be sped up by running the [following script](./multi-worker-join.sh) in a new terminal:
```bash

#!/bin/bash

master_ip=$(docker-machine ip manager1)
join_token=$(docker-machine ssh manager1 docker swarm join-token -q worker)
join_command="docker swarm join --token ${join_token} ${master_ip}:2377"
array=( worker1 worker2 worker3 )
for machine in "${array[@]}"
do
	docker-machine ssh $machine $join_command
done

```

This is an example of what you should see:

```

This node joined a swarm as a worker.
This node joined a swarm as a worker.
This node joined a swarm as a worker.

```

Now that I have a cluster of one manager and three workers, I can SSH into the
manager node and ensure that that's the case by using the `docker node ls` command.
Note that this command only works on manager nodes:

```bash

$ docker-machine ssh manager1
Boot2Docker version 17.05.0-ce, build HEAD : 5ed2840 - Fri May  5 21:04:09 UTC 2017
Docker version 17.05.0-ce, build 89658be
docker@manager1:~$ docker node ls
ID                            HOSTNAME            STATUS              AVAILABILITY        MANAGER STATUS
0gsvorsgdh78a3ubhjhafwuf9 *   manager1            Ready               Active              Leader
97x97mm7404wdsji2byjz90pr     worker1             Ready               Active
h1xuci8a9w39pe4j8epr4wknr     worker3             Ready               Active
kc1em7wydv9d8fzoz11pc14lm     worker2             Ready               Active
```

Note that the single manager has been automatically elected as a leader.

### Deploying a service to the swarm

Now that I have a swarm, I want to create the simplest service possible. I will
log into my manager1 guest and create a service:

```
$ docker-machine ssh manager1
Boot2Docker version 17.05.0-ce, build HEAD : 5ed2840 - Fri May  5 21:04:09 UTC 2017
Docker version 17.05.0-ce, build 89658be
$ docker service create --replicas 1 --name helloping alpine ping docker.com
l0ewxfdek3cl8z6ceo2znj5no
```

Note that I added a name for the service by using the `--name` flag. I also specified
how many replicas (count of the type of service) I want running. I set this to 1
using the `--replicas` flag.

Being that the alpine image does not have any functions that it runs as a daemon
either via `CMD` or `ENTRYPOINT`, I also tell the service what the command I wish
to run is. Performing the ping command leaves my service running so I can play
with it.

Now I can look to see what services I have running:

```
$ docker service ls
ID                  NAME                MODE                REPLICAS            IMAGE               PORTS
l0ewxfdek3cl        helloping           replicated          1/1                 alpine:latest
```

### Inspecting swarm services

While still on the manager node, I can inspect a service in human readable format:

```
$ docker service inspect --pretty helloping

ID:             l0ewxfdek3cl8z6ceo2znj5no
Name:           helloping
Service Mode:   Replicated
 Replicas:      1
Placement:
UpdateConfig:
 Parallelism:   1
 On failure:    pause
 Monitoring Period: 5s
 Max failure ratio: 0
 Update order:      stop-first
RollbackConfig:
 Parallelism:   1
 On failure:    pause
 Monitoring Period: 5s
 Max failure ratio: 0
 Rollback order:    stop-first
ContainerSpec:
 Image:         alpine:latest@sha256:c0537ff6a5218ef531ece93d4984efc99bbf3f7497c0a7726c88e2bb7584dc96
 Args:          ping docker.com
Resources:
Endpoint Mode:  vip
```

I could have made the output machine readable in JSON by not providing the `--pretty` flag.

I can also get a list of nodes where my service is running by issuing:

```
$ docker service ps helloping
ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE           ERROR               PORTS
6evig1m1a7a2        helloping.1         alpine:latest       worker1             Running             Running 9 minutes ago
```

Now I see that the service is running on worker1. If I wanted, I could perform
`docker ps` on worker1 to verify:

```
$ docker-machine ssh worker1 docker ps -a
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
640538a0c18c        alpine:latest       "ping docker.com"   11 minutes ago      Up 11 minutes                           helloping.1.6evig1m1a7a2skvmtk1af6ef6
```

### Scaling a service

Now that I have a single worker running a service, I may want to scale that service
out to multiple nodes. This is done using the `docker service scale` command. When
I am logged into the manager1 guest, I can scale and then use `docker service ps`
to see the status pf my scaled out service:

```
$ docker service scale helloping=10
helloping scaled to 10

$ docker service ps helloping
ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE            ERROR               PORTS
6evig1m1a7a2        helloping.1         alpine:latest       worker1             Running             Running 18 minutes ago
3ctgqpbl4s1r        helloping.2         alpine:latest       manager1            Running             Running 4 minutes ago
qoqfeuxn8vtz        helloping.3         alpine:latest       worker1             Running             Running 4 minutes ago
qps4q9q1twlc        helloping.4         alpine:latest       worker3             Running             Running 4 minutes ago
rexsnew7sa8l        helloping.5         alpine:latest       manager1            Running             Running 4 minutes ago
5ygix67eyl8p        helloping.6         alpine:latest       worker2             Running             Running 4 minutes ago
pdnsn36n8a4i        helloping.7         alpine:latest       worker2             Running             Running 4 minutes ago
28aanmyk1fj7        helloping.8         alpine:latest       worker1             Running             Running 4 minutes ago
l1ss1hzaiaru        helloping.9         alpine:latest       worker3             Running             Running 4 minutes ago
mi2l7ghvunbl        helloping.10        alpine:latest       worker3             Running             Running 4 minutes ago
```

Now I can see that the swarm has scaled out my ping service to all the workers. I
see that worker1 is running the 3 containers with the helloping service. Worker2
is running the service in 2 containers and worker3 is running it in 3 containers.
I also notice that manager1 is running the service twice. Remember that a manager
node is still considered a worker node so it is a valid target for scaling. In practice.
this should be avoided. A manager node should only serve as an orchestrator. This
can be accomplished by limiting the amount of services a node can contain.

I can do this now by issuing an update to the manager node, forcing the node to
drain all services:

```
$ docker node update --availability drain manager1
manager1

$ docker service ps helloping
ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE             ERROR               PORTS
6evig1m1a7a2        helloping.1         alpine:latest       worker1             Running             Running 26 minutes ago
09dylzxvphpq        helloping.2         alpine:latest       worker2             Running             Running 30 seconds ago
3ctgqpbl4s1r         \_ helloping.2     alpine:latest       manager1            Shutdown            Shutdown 31 seconds ago
qoqfeuxn8vtz        helloping.3         alpine:latest       worker1             Running             Running 12 minutes ago
qps4q9q1twlc        helloping.4         alpine:latest       worker3             Running             Running 12 minutes ago
lm09zlbc0fcu        helloping.5         alpine:latest       worker2             Running             Running 30 seconds ago
rexsnew7sa8l         \_ helloping.5     alpine:latest       manager1            Shutdown            Shutdown 31 seconds ago
5ygix67eyl8p        helloping.6         alpine:latest       worker2             Running             Running 12 minutes ago
pdnsn36n8a4i        helloping.7         alpine:latest       worker2             Running             Running 12 minutes ago
28aanmyk1fj7        helloping.8         alpine:latest       worker1             Running             Running 12 minutes ago
l1ss1hzaiaru        helloping.9         alpine:latest       worker3             Running             Running 12 minutes ago
mi2l7ghvunbl        helloping.10        alpine:latest       worker3             Running             Running 12 minutes ago
```

Once I issue the `drain` command, I then see via the `ps` command that the manager1
node is no longer running the helloping service and it shows the service in a shutdown
state on that node. I also see that the other workers have picked up the slack to
maintain a scale level of 10.

### Deleting the service

It's just as easy to remove a service from the cluster.  On the manager node, I
can simply issue:

```
$ docker service rm helloping
helloping

$ docker service ps helloping
no such services: helloping
```

My cluster is now not running the helloping service.

### Rolling service updates through a cluster

In a clustered environment, I want to be able to roll my updates throughout the
cluster. In my case,

```
$ docker service create --replicas 10 --name nginx --update-delay 10s -p "80:80" nginx:1.12-alpine
lhednpnk4tq4iru0ne0fxfe9e
```

Once the service is up and running, we can check verify the version of the NGINX
container by issuing:

```
$ curl "http://$(docker-machine ip worker1)/" -sI | grep -Fi Server
Server: nginx/1.12.0.
$ curl "http://$(docker-machine ip worker2)/" -sI | grep -Fi Server
Server: nginx/1.12.0
$ curl "http://$(docker-machine ip worker3)/" -sI | grep -Fi Server
Server: nginx/1.12.0
$ curl "http://$(docker-machine ip manager1)/" -sI | grep -Fi Server
Server: nginx/1.12.0
```

### A brief talk about networking in Swarm...

One thing to note here. Remember that the manager1 node does not run the service.

```
$ docker service ps nginx
ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE           ERROR               PORTS
jbdus0hvdv7t        nginx.1             nginx:1.12-alpine   worker1             Running             Running 8 minutes ago
yl4aad1noobz        nginx.2             nginx:1.12-alpine   worker2             Running             Running 8 minutes ago
9y7i23q37lk9        nginx.3             nginx:1.12-alpine   worker2             Running             Running 8 minutes ago
ygb3e9foctmq        nginx.4             nginx:1.12-alpine   worker2             Running             Running 8 minutes ago
xc02uh0iscf2        nginx.5             nginx:1.12-alpine   worker3             Running             Running 8 minutes ago
2pcedpg2uxn8        nginx.6             nginx:1.12-alpine   worker1             Running             Running 8 minutes ago
zb942xp4po3q        nginx.7             nginx:1.12-alpine   worker2             Running             Running 8 minutes ago
l8vya9gppcv3        nginx.8             nginx:1.12-alpine   worker3             Running             Running 8 minutes ago
1qrbvbnfvttw        nginx.9             nginx:1.12-alpine   worker3             Running             Running 8 minutes ago
obmyjdft0ifg        nginx.10            nginx:1.12-alpine   worker1             Running             Running 8 minutes ago
```

So why does the guest machine come back with a valid response to our HTTP query?
The answer is that Docker Swarm creates a [mesh routing network](https://docs.docker.com/engine/swarm/ingress/) that has the benefit
where a call to a port on any valid node is automatically routed to a container.
As a client, we have no idea which of our containers are answering the call. In
a true microservice world, we also shouldn't care. The following example shows the
random routing happening. On a new terminal, I issue a command that will perform a
curl 10 times against the manager1 node (that isn't running the service).

```
$ for i in {1..10}; do curl "http://$(docker-machine ip manager1)/" -sI | grep -Fi Server;done
Server: nginx/1.12.0
Server: nginx/1.12.0
Server: nginx/1.12.0
Server: nginx/1.12.0
Server: nginx/1.12.0
Server: nginx/1.12.0
Server: nginx/1.12.0
Server: nginx/1.12.0
Server: nginx/1.12.0
Server: nginx/1.12.0
```

Each time I see I got a proper response back. Now, back on the manager1 node, I
check the logs from the service.
This command gives me the composed service logs from every node currently running
the service:

```
$ docker service logs nginx
nginx.2.mrcmkeezmy0w@worker3     | 10.255.0.2 - - [19/May/2017:18:59:24 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.7.tz9layqee5za@worker3     | 10.255.0.2 - - [19/May/2017:18:59:24 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.5.vhvfo487m82b@worker3     | 10.255.0.2 - - [19/May/2017:18:59:24 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.1.i8xyux2c7ngs@worker1     | 10.255.0.2 - - [19/May/2017:18:59:23 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.10.t98r04ctgs9e@worker1    | 10.255.0.2 - - [19/May/2017:18:59:23 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.9.lgowrypx7sgl@worker1     | 10.255.0.2 - - [19/May/2017:18:59:23 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.8.c0x9x8hyfpiv@worker2     | 10.255.0.2 - - [19/May/2017:18:59:24 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.6.xznry1pbzcj4@worker2     | 10.255.0.2 - - [19/May/2017:18:59:23 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.3.tltx3efgpj81@worker2     | 10.255.0.2 - - [19/May/2017:18:59:22 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-"
nginx.4.kw0z2pi9y8kg@worker2     | 10.255.0.2 - - [19/May/2017:18:59:22 +0000] "HEAD / HTTP/1.1" 200 0 "-" "curl/7.53.1" "-
```

Note that the HTTP request went to random workers in the swarm and never hit the
manager1 node.

### Back to rolling updates

Now that I know my service is running and is testable that it's serving version
1.12.0 of NGINX, I can begin updating. I want to update the NGINX server that's being
served by the nginx service to 1.13.0. That's as easy as:

```
$ docker service update --image nginx:1.13-alpine nginx
nginx
```

If I quickly inspect the nginx service, I see that the update is in progress:

```
$ docker service inspect --pretty nginx

ID:             04nmpgm4ap1u820rb1wyp86nm
Name:           nginx
Service Mode:   Replicated
 Replicas:      10
UpdateStatus:
 State:         updating
 Started:       18 seconds
 Message:       update in progress
Placement:
UpdateConfig:
 Parallelism:   1
 Delay:         10s
 On failure:    pause
 Monitoring Period: 5s
 Max failure ratio: 0
 Update order:      stop-first
RollbackConfig:
 Parallelism:   1
 On failure:    pause
 Monitoring Period: 5s
 Max failure ratio: 0
 Rollback order:    stop-first
ContainerSpec:
 Image:         nginx:1.13-alpine@sha256:33eb1ed1e802d4f71e52421f56af028cdf12bb3bfff5affeaf5bf0e328ffa1bc
Resources:
Endpoint Mode:  vip
Ports:
 PublishedPort = 80
  Protocol = tcp
  TargetPort = 80
  PublishMode = ingress
```

Now remember that when I created the service initially, I used the `--update-delay`
flag. This dictates the length of time that services will wait between updates.

Eventually, I can see that all of the nodes are running the updated version of the
service:

```
$ docker service ps nginx
ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE            ERROR               PORTS
05r26zditm03        nginx.1             nginx:1.13-alpine   worker2             Running             Running 5 minutes ago
i8xyux2c7ngs         \_ nginx.1         nginx:1.12-alpine   worker1             Shutdown            Shutdown 5 minutes ago
w3dnl8gsepas        nginx.2             nginx:1.13-alpine   worker1             Running             Running 6 minutes ago
mrcmkeezmy0w         \_ nginx.2         nginx:1.12-alpine   worker3             Shutdown            Shutdown 6 minutes ago
t6bg7qmrzkg0        nginx.3             nginx:1.13-alpine   worker2             Running             Running 5 minutes ago
tltx3efgpj81         \_ nginx.3         nginx:1.12-alpine   worker2             Shutdown            Shutdown 5 minutes ago
nw7gm8ovu691        nginx.4             nginx:1.13-alpine   worker3             Running             Running 6 minutes ago
kw0z2pi9y8kg         \_ nginx.4         nginx:1.12-alpine   worker2             Shutdown            Shutdown 6 minutes ago
i56k5hodxdqe        nginx.5             nginx:1.13-alpine   worker3             Running             Running 4 minutes ago
vhvfo487m82b         \_ nginx.5         nginx:1.12-alpine   worker3             Shutdown            Shutdown 4 minutes ago
ybnpkfkzsdss        nginx.6             nginx:1.13-alpine   worker1             Running             Running 4 minutes ago
xznry1pbzcj4         \_ nginx.6         nginx:1.12-alpine   worker2             Shutdown            Shutdown 4 minutes ago
xkzxq67yteby        nginx.7             nginx:1.13-alpine   worker3             Running             Running 5 minutes ago
tz9layqee5za         \_ nginx.7         nginx:1.12-alpine   worker3             Shutdown            Shutdown 5 minutes ago
q2t2u5a78h8r        nginx.8             nginx:1.13-alpine   worker2             Running             Running 5 minutes ago
c0x9x8hyfpiv         \_ nginx.8         nginx:1.12-alpine   worker2             Shutdown            Shutdown 5 minutes ago
k2blbat37hco        nginx.9             nginx:1.13-alpine   worker1             Running             Running 4 minutes ago
lgowrypx7sgl         \_ nginx.9         nginx:1.12-alpine   worker1             Shutdown            Shutdown 4 minutes ago
lc1fuhnfx5o1        nginx.10            nginx:1.13-alpine   worker1             Running             Running 5 minutes ago
t98r04ctgs9e         \_ nginx.10        nginx:1.12-alpine   worker1             Shutdown            Shutdown 5 minutes ago
```

This shows the history of the service as the service with NGINX 1.12 service shuts
down and the 1.13 version came up. Also i can now see that the service UpdateStatus
is in a completed state:

```
$ docker service inspect --pretty nginx

ID:             04nmpgm4ap1u820rb1wyp86nm
Name:           nginx
Service Mode:   Replicated
 Replicas:      10
UpdateStatus:
 State:         completed
 Started:       7 minutes
 Completed:     5 minutes
 Message:       update completed
Placement:
UpdateConfig:
 Parallelism:   1
 Delay:         10s
 On failure:    pause
 Monitoring Period: 5s
 Max failure ratio: 0
 Update order:      stop-first
RollbackConfig:
 Parallelism:   1
 On failure:    pause
 Monitoring Period: 5s
 Max failure ratio: 0
 Rollback order:    stop-first
ContainerSpec:
 Image:         nginx:1.13-alpine@sha256:33eb1ed1e802d4f71e52421f56af028cdf12bb3bfff5affeaf5bf0e328ffa1bc
Resources:
Endpoint Mode:  vip
Ports:
 PublishedPort = 80
  Protocol = tcp
  TargetPort = 80
  PublishMode = ingress
```

Finally, I run the curl test again from another terminal:

```
$ for i in {1..10}; do curl "http://$(docker-machine ip manager1)/" -sI | grep -Fi Server;done
Server: nginx/1.13.0
Server: nginx/1.13.0
Server: nginx/1.13.0
Server: nginx/1.13.0
Server: nginx/1.13.0
Server: nginx/1.13.0
Server: nginx/1.13.0
Server: nginx/1.13.0
Server: nginx/1.13.0
Server: nginx/1.13.0
```

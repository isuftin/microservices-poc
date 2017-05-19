#!/bin/bash

master_ip=$(docker-machine ip manager1)
join_token=$(docker-machine ssh manager1 docker swarm join-token -q worker)
join_command="docker swarm join --token ${join_token} ${master_ip}:2377"
array=( worker1 worker2 worker3 )
for machine in "${array[@]}"
do
	docker-machine ssh $machine $join_command
done

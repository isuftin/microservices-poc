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

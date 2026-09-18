.PHONY: help image run shell root host-setup lint

help:
	@echo "make image       Build the Docker image (./create-image.sh)"
	@echo "make run         Start the ISE GUI"
	@echo "make shell       Start a shell in the container"
	@echo "make root        Start a root shell in the container"
	@echo "make host-setup  Install cable firmware + udev rules on the host"
	@echo "make lint        Run shellcheck and hadolint"

image:
	./create-image.sh

run:
	./run-docker.sh

shell:
	./run-docker.sh --bash

root:
	./run-docker.sh --root --bash

host-setup:
	./setup-host.sh

lint:
	shellcheck create-image.sh run-docker.sh setup-host.sh firmware-load.sh
	hadolint Dockerfile

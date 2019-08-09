.ONESHELL:
.SHELL := /usr/bin/bash
PWD=$(shell pwd)
BOLD=$(shell tput bold)
RED=$(shell tput setaf 1)
GREEN=$(shell tput setaf 2)
YELLOW=$(shell tput setaf 3)
RESET=$(shell tput sgr0)

help:
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}'

step-0: ## Setup nfs server and kubernetes cluster
	@cd $(PWD)/nfsserver && vagrant up; \
	cd $(PWD)/vagrant-provisioning && vagrant up

step-1: ## Setup ssh-key to kmaster and copy kubeconfig file
	@sshpass -p vagrant ssh-copy-id vagrant@kmaster; \
	sshpass -p vagrant ssh-copy-id vagrant@nfsserver; \
	ssh vagrant@kmaster "sudo cp -a /home/vagrant/.ssh /root/; sudo chown -R root:root /root/.ssh;"; \
	scp root@kmaster:/etc/kubernetes/admin.conf ~/.kube/config

step-2: ## Check cluster
	kubectl cluster-info; \
	kubectl get nodes; \
	kubectl version --short

step-3: ## Deploy nfs-client-provisioner as default(!) persistant storage provider
	@kubectl create -f $(PWD)/yamls/nfs-provisioner/rbac.yaml \
		-f $(PWD)/yamls/nfs-provisioner/default-sc.yaml \
		-f $(PWD)/yamls/nfs-provisioner/deployment.yaml; \
	kubectl get storageclass,all \

step-4: ## Setup tiller
	@kubectl -n kube-system create serviceaccount tiller && \
	kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller; \
	helm init --service-account tiller; \
	kubectl -n kube-system get pods

step-5: ## helm list should be empty but no errors
	@helm list

step-6: ## Install prometheus and export to nodePort:32322 (open another window and watch with: kubectl get all -n prometheus)
	@helm install stable/prometheus --namespace prometheus --set alertmanager.service.type=NodePort --set alertmanager.service.nodePort=30903 --set server.service.type=NodePort --set server.service.nodePort=32322 --name prometheus

step-7: ## Verify with firefox and check nfs
	@open http://kworker1:32322; \
	sshpass -p vagrant ssh vagrant@nfsserver "ls -ltr /srv/nfs/kubedata"

step-9: ## Install Grafana and expose to nodePort: 32333
	@helm install stable/grafana --name grafana --namespace grafana --set service.type=NodePort \
		--set service.nodePort=32333 --set adminPassword=asdflkj --set persistence.enabled=true

step-10: ## Test grafana with dashboard 8588
	@open http://kworker1:32333; \
	sshpass -p vagrant ssh vagrant@nfsserver "ls -ltr /srv/nfs/kubedata"

clean-grafana: ## Delete grafana
	@helm delete grafana --purge

clean-prometheus: ## Delete Prometheus
	@helm delete prometheus --purge

clean:  ## Destroy nfs server and Kubernetes cluster
	@cd $(PWD)/nfsserver && vagrant destroy -f; \
	cd $(PWD)/vagrant-provisioning && vagrant destroy -f

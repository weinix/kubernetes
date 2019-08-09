.ONESHELL:
.SHELL := /usr/bin/bash
PWD=$(shell pwd)
BOLD=$(shell tput bold)
RED=$(shell tput setaf 1)
GREEN=$(shell tput setaf 2)
YELLOW=$(shell tput setaf 3)
RESET=$(shell tput sgr0)

help:
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

s0: ## Setup nfs server and kubernetes cluster (8-10 min)
	@cd $(PWD)/nfsserver && vagrant up; \
	cd $(PWD)/vagrant-provisioning && vagrant up

s1: ## Setup ssh-key to kmaster and copy kubeconfig file
	@sshpass -p vagrant ssh-copy-id vagrant@kmaster > /dev/null 2>&1; \
	sshpass -p vagrant ssh-copy-id vagrant@nfsserver > /dev/null 2>&1; \
	ssh vagrant@kmaster "sudo cp -a /home/vagrant/.ssh /root/; sudo chown -R root:root /root/.ssh;"; \
	scp root@kmaster:/etc/kubernetes/admin.conf ~/.kube/config > /dev/null 2>&1; \
	echo kubectl is ready

s2: ## Check cluster status
	@echo kubectl cluster-info; \
	kubectl cluster-info; \
	echo; echo kubectl get nodes; \
	kubectl get nodes; \
	echo; echo kubectl get cs; \
	kubectl get cs; \
	echo; echo kubectl version --short; \
	kubectl version --short

s3: ## Deploy nfs-client-provisioner as default(!) persistant storage provider
	@kubectl create -f $(PWD)/yamls/nfs-provisioner/rbac.yaml \
		-f $(PWD)/yamls/nfs-provisioner/default-sc.yaml \
		-f $(PWD)/yamls/nfs-provisioner/deployment.yaml; \
	kubectl get storageclass,all \

s4: ## Setup tiller
	@kubectl -n kube-system create serviceaccount tiller && \
	kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller; \
	helm init --service-account tiller; \
	kubectl -n kube-system get pods

s5: ## helm list should be empty but no errors
	@echo helm list should be empty but no errors; \
	helm list

s6: ## Install prometheus and export to nodePort:32322 (open another window and watch with: kubectl get all -n prometheus)
	@helm install stable/prometheus --namespace prometheus --set alertmanager.service.type=NodePort \
		--set alertmanager.service.nodePort=30903 --set server.service.type=NodePort \
		--set server.service.nodePort=32322 --name prometheus; \
	echo "Wait for 2-3 minutes before perform s7"

s7: ## Verify prometheus with browser and check nfs
	@open http://kworker1:32322; \
	sshpass -p vagrant ssh vagrant@nfsserver "ls -ltr /srv/nfs/kubedata"

s8: ## Install Grafana and expose to nodePort: 32333
	@helm install stable/grafana --name grafana --namespace grafana --set service.type=NodePort \
		--set service.nodePort=32333 --set adminPassword=asdflkj --set persistence.enabled=true

s9: ## Test grafana with dashboard 8588
	@open http://kworker1:32333; \
	sshpass -p vagrant ssh vagrant@nfsserver "ls -ltr /srv/nfs/kubedata"

clean-grafana: ## Delete grafana
	@helm delete grafana --purge

clean-prometheus: ## Delete Prometheus
	@helm delete prometheus --purge

clean:  ## Destroy nfs server and Kubernetes cluster
	@cd $(PWD)/nfsserver && vagrant destroy -f; \
	cd $(PWD)/vagrant-provisioning && vagrant destroy -f


#
## https://itnext.io/kubernetes-monitoring-with-prometheus-in-15-minutes-8e54d1de2e13
sb-2: ## Install prmotheus operator
	@echo Install prometheus operator; \
	 helm install stable/prometheus-operator --name prometheus-operator --namespace monitoring

sb-3: ## Forward operator port to localhost:9090
	@echo "Forward operator port to localhost 9090"; \
	kubectl port-forward -n monitoring prometheus-prometheus-operator-prometheus-0 9090 > /dev/null 2>&1 & 

sb-4: ## Forward operator port to localhost:3000
	@echo "Forward operator port to localhost 3000"; \
	kubectl port-forward $(shell kubectl get  pods --selector=app=grafana -n  monitoring --output=jsonpath="{.items..metadata.name}") -n monitoring  3000 > /dev/null 2>&1 &

sb-5: ## Kill kubectl forwarding process
	@echo Kill kubectl forwarding; \
	kill -9 $(shell ps -ef | grep "kubectl port-forward" | grep -v grep | awk 'BEGIN{ORS=" "} /kubectl/{print $$2}')
sb-6: ## Test with broswer admin/prom-operator
	@open http://localhost:3000

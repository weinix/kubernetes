.ONESHELL:
.SHELL := /bin/bash
PWD=$(shell pwd)
BOLD=$(shell tput bold)
RED=$(shell tput setaf 1)
GREEN=$(shell tput setaf 2)
YELLOW=$(shell tput setaf 3)
RESET=$(shell tput sgr0)

define INFO
    echo "$(BOLD)$(GREEN)- INFO: $(1)$(RESET)" 
endef

define ERR
    echo "$(BOLD)$(RED)- INFO:  $(1)$(RESET)" 
endef

define WAITPODS
	/bin/echo -n "==> Wait for pods coming up..."; \
	n=1;\
	while true; \
	do \
		sleep 1 ; \
		/bin/echo -n "."; \
	    kubectl get pod --all-namespaces | awk '{print $$3}' | grep -q "0" || break; \
	done; \
	echo ; \
	kubectl get pod --all-namespaces
endef


help:
	@grep -E '^[0-9#a-z A-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

waitpods: 
	$(call WAITPODS)

nfs-up: ##Setup nfs server (2 min)
	@$(call INFO, "Setup nfs server"); \
	cd $(PWD)/nfsserver && vagrant up

k8-up: ##Setup kubernetes cluster (6-8 min)
	@$(call INFO, "Setup k8s"); \
	cd $(PWD)/vagrant-provisioning && vagrant up; \
	sleep 11

nfs-ssh-key: ##Setup ssh-key to nfs server
	@$(call INFO, "Setup ssh-key to nfs server"); \
	sshpass -p vagrant ssh-copy-id vagrant@nfsserver > /dev/null 2>&1; \

k8-ssh-key: ##Setup ssh-key to kmaster and copy kubeconfig file
	@$(call INFO, "Setup ssh-key to kmaster and copy kubeconfig file")
	@sshpass -p vagrant ssh-copy-id vagrant@kmaster > /dev/null 2>&1; \
	ssh vagrant@kmaster "sudo cp -a /home/vagrant/.ssh /root/; sudo chown -R root:root /root/.ssh;"; \
	scp root@kmaster:/etc/kubernetes/admin.conf ~/.kube/config > /dev/null 2>&1; \
	$(call INFO, "kubectl is ready")

k8-status: waitpods ##Check cluster status
	@$(call INFO, "Check cluster status"); \
	echo kubectl cluster-info; \
	kubectl cluster-info; \
	echo; echo kubectl get nodes; \
	kubectl get nodes; \
	echo; echo kubectl get cs; \
	kubectl get cs; \
	echo; echo kubectl version --short; \
	kubectl version --short

deploy-nfs-client-provisioner: ##Deploy nfs-client-provisioner as default(!) persistant storage provider
	@$(call INFO, "Deploy nfs-client-provisioner as DEFAULT persistant storage provider"); \
	kubectl create -f $(PWD)/yamls/nfs-provisioner/rbac.yaml \
		-f $(PWD)/yamls/nfs-provisioner/default-sc.yaml \
		-f $(PWD)/yamls/nfs-provisioner/deployment.yaml > /dev/null 2>&1; \
	sleep 5; \
	kubectl get storageclass,all \

deploy-tiller: waitpods ##Setup tiller
	@$(call INFO, "setup tiller"); \
	kubectl -n kube-system create serviceaccount tiller && \
	kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller; \
	helm init --service-account tiller > /dev/null 2>&1; \
	kubectl wait --for=condition=Ready pod/$(kubectl get  pods --selector=name=tiller -n  kube-system --output=jsonpath="{.items..metadata.name}") -n kube-system; \
	sleep 40; \
	$(call INFO, "Tiller is up"); \

helm-list: waitpods ##helm list should be empty but no errors
	@$(call INFO, "helm list should be empty but no errors") \
	helm list

deploy-prometheus: waitpods ##Install prometheus and export to nodePort:32322 (open another window and watch with: kubectl get all -n prometheus)
	@$(call INFO, "Install prometheus and export to nodePort:32322"); \
	$(call INFO, "    Do: watch kubectl get all -n prometheus"); \
	helm install stable/prometheus --namespace prometheus --set alertmanager.service.type=NodePort \
		--set alertmanager.service.nodePort=30903 --set server.service.type=NodePort \
		--set server.service.nodePort=32322 --name prometheus  > /dev/null 2>&1; \
	sleep 20

deploy-grafana: ##Install Grafana and expose to nodePort: 32334
	@$(call INFO, "Install Grafana and expose to nodePort: 32333"); \
	helm install stable/grafana --name grafana --namespace grafana --set service.type=NodePort \
		--set service.nodePort=32333 --set adminPassword=asdflkj --set persistence.enabled=true > /dev/null 2>&1; \
	sleep 15 

check-nfs: ##Test grafana with dashboard 8588
	@$(call INFO, "Check nfs server"); \
	ssh vagrant@nfsserver "ls -ltr /srv/nfs/kubedata"

test1: waitpods ##Test grafana with dashboard 8588
	@$(call INFO, "Test grafana with dashboard 8588"); \
	open http://kworker1:32322 http://kworker1:32333; \
	sshpass -p vagrant ssh vagrant@nfsserver "ls -ltr /srv/nfs/kubedata"

clean-grafana: ##Delete grafana
	@$(call INFO, "Delete grafana deployment"); \
	helm delete grafana --purge

clean-prometheus: ##Delete Prometheus
	@$(call INFO, "Delete prometheus deployment"); \
	helm delete prometheus --purge

clean-nfs:  ##Destroy nfs server vagrant box
	@$(call INFO, "Destroy nfs server vagrant box"); \
	cd $(PWD)/nfsserver && vagrant destroy -f

clean-k8:  ##Destroy Kubernetes vagrant boxes
	@$(call INFO, "Destroy Kubernetes vagrant boxes"); \
	cd $(PWD)/vagrant-provisioning && vagrant destroy -f

############################################################################
##########           Playbook1 Prometheus Grafana with persistane storage: ## .
############################################################################
1-all: 1-1 1-2 1-3 1-test ## Full automated 
1-1: nfs-up k8-up nfs-ssh-key k8-ssh-key k8-status ## Setup K8s and NFS server (8-10 min)
1-2: deploy-nfs-client-provisioner deploy-tiller helm-list ## Setup nfs-client-provisioner and tiller
1-3: deploy-prometheus deploy-grafana ## Install prometheus and grafana 
1-test: test1 ## Test with broswer 
	@open http://kworker1:32322 http://kworker1:32333; \
	sshpass -p vagrant ssh vagrant@nfsserver "ls -ltr /srv/nfs/kubedata"
1-clean: clean-prometheus clean-grafana ## Clean playbook 1 pods




############################################################################
##########           Playbook2 Prometheus and Grafana with operator: ## .
############################################################################
## https://itnext.io/kubernetes-monitoring-with-prometheus-in-15-minutes-8e54d1de2e13

2-all: 2-1 2-2 2-3 2-4 2-test ## Full automated 
2-1: k8-up k8-ssh-key k8-status ## Setup K8s and NFS server (8-10 min)
2-2: deploy-tiller helm-list ## Setup tiller
3-3: ## Install prmotheus operator
	@$(call INFO, "Install prometheus operator"); \
	 helm install stable/prometheus-operator --name prometheus-operator --namespace monitoring

2-4: forward-pro forward-grafana forward-alert-mgr ## Forward ports
	@echo 

forward-pro: ##Forward prometheus port to localhost:9090
	@$(call INFO, "Forward prometheus port to localhost 9090"); \
	kubectl port-forward -n monitoring prometheus-prometheus-operator-prometheus-0 9090 > /dev/null 2>&1 & 

forward-grafana: ##Forward grafana port to localhost 3000
	@$(call INFO, "Forward grafana port to localhost 3000"); \
	kubectl port-forward $(shell kubectl get  pods --selector=app=grafana -n  monitoring --output=jsonpath="{.items..metadata.name}") -n monitoring  3000 > /dev/null 2>&1 &

forward-alert-mgr: ##Forward alerting manager port to localhost:9093
	@$(call INFO, "Forward grafana port to localhost 9093"); \
	kubectl port-forward -n monitoring alertmanager-prometheus-operator-alertmanager-0 9093 > /dev/null 2>&1 &

kill-forwarding: ##Kill kubectl forwarding process
	@$(call INFO, "Kill kubectl forwarding"); \
	kill -9 $(shell ps -ef | grep "kubectl port-forward" | grep -v grep | awk 'BEGIN{ORS=" "} /kubectl/{print $$2}')

2-test: ## Test with broswer admin/prom-operator
	@$(call INFO, "Test account admin/prom-operator"); \
	open http://localhost:9090 http://localhost:9093 http://localhost:3000

2-clean: ## clean playbook 2 pods
##########           House keeping: ## .
clean-all: clean-k8 clean-nfs ## Clean everything!
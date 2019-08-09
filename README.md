# kubernetes
Kubernetes playground

## Prometheus and grafana for K8s 

Use make command to follow below steps

```
$ make
step-0               Setup nfs server and kubernetes cluster
step-1               Setup ssh-key to kmaster and copy kubeconfig file
step-2               Check cluster
step-3               Deploy nfs-client-provisioner as default(!) persistant storage provider
step-4               Setup tiller
step-5               helm list should be empty but no errors
step-6               Install prometheus and export to nodePort:32322 (open another window and watch with: kubectl get all -n prometheus)
step-7               Verify with firefox and check nfs
step-9               Install Grafana and expose to nodePort: 32333
step-10              Test grafana with dashboard 8588
clean-grafana        Delete grafana
clean-prometheus     Delete Prometheus
clean                Destroy nfs server and Kubernetes cluster
````

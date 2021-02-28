docker pull xianyanglin/kube:dashboard
docker pull xianyanglin/kube:metrics-scraper
docker pull xianyanglin/kube:kube-controller-manager
docker pull xianyanglin/kube:kube-apiserver
docker pull xianyanglin/kube:kube-proxy
docker pull xianyanglin/kube:kube-scheduler
docker pull xianyanglin/kube:node
docker pull xianyanglin/kube:cni
docker pull xianyanglin/kube:kube-controllers
docker pull xianyanglin/kube:pod2daemon-flexvol
docker pull xianyanglin/kube:coredns

docker tag xianyanglin/kube:dashboard kubernetesui/dashboard:v2.0.0-rc5
docker tag xianyanglin/kube:metrics-scraper kubernetesui/metrics-scraper:v1.0.3
docker tag xianyanglin/kube:kube-controller-manager k8s.gcr.io/kube-controller-manager:v1.17.1
docker tag xianyanglin/kube:kube-apiserver k8s.gcr.io/kube-apiserver:v1.17.1
docker tag xianyanglin/kube:kube-proxy k8s.gcr.io/kube-proxy:v1.17.1
docker tag xianyanglin/kube:kube-scheduler k8s.gcr.io/kube-scheduler:v1.17.1
docker tag xianyanglin/kube:node calico/node:v3.10.3
docker tag xianyanglin/kube:cni calico/cni:v3.10.3
docker tag xianyanglin/kube:kube-controllers calico/kube-controllers:v3.10.3
docker tag xianyanglin/kube:pod2daemon-flexvol calico/pod2daemon-flexvol:v3.10.3
docker tag xianyanglin/kube:coredns k8s.gcr.io/coredns:1.6.5


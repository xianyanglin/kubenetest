## kubenetest部署(非高可用篇)

### 机器准备
* 三台Centos7的Linux机器

### 三台机器同步进行以下安装前的准备工作
* 设置Host文件
```
xx.xx.x.xxx  k8s-master   //三台机器确保访问互通
xx.xx.x.xxx  k8s-slave01
xx.xx.x.xxx  k8s-slave02
```

* 三台分别设置各自的系统名

```
hostnamectl set-hostname k8s-master
hostnamectl set-hostname k8s-slave01
hostnamectl set-hostname k8s-slave02
```

* 升级系统内核，需要4.0以上的版本，目前我使用的版本是4.4
``` shell
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
yum --enablerepo=elrepo-kernel install -y kernel-lt
# 设置开机从新内核启动
grub2-set-default "CentOS linux (4.4.229-1.el7.elrepo.x86_64) 7 (Core)"
```

* 重启```reboot```

* 安装系统依赖包
```
yum install -y conntrack ntpdate ntp ipvsadm ipset jq iptables curl sysstat libseccomp wget vim net-tools git
```

* 设置防火墙为IPtables并设置空规则
```
systemctl stop firewalld && systemctl disable firewalld
yum -y install iptables-services && systemctl start iptables && systemctl enable iptables && iptables -F && service iptables save
```

* 调整k8s的内核参数
```
cat >/etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0 #禁止使用swap空间，即不允许在虚拟内存上允许pod,只有当OOM时才允许使用它
vm.overcommit_memory=1 #不检查物理内存是否够用
vm.panic_on_oom=0 #开启OOM
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF

sysctl -p /etc/sysctl.d/kubernetes.conf
```
* 调整系统时区

```
timedatectl set-timezone Asia/Shanghai
# 将当前的UTC时间写入硬件时钟
timedatectl set-local-rtc 0
# 重启依赖于系统时间的服务
systemctl restart rsyslog
systemctl restart crond
```
* 关闭系统不需要的服务
```
systemctl stop postfix && systemctl disable postfix
```

* 设置rsyslogd和systemd journald日志模式
```
mkdir /var/log/journal #持久化保存日志的目录
mkdir /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-prophet.conf <<EOF
# 持久化保存到磁盘
Storage=persistent

# 压缩历史日志
Compress=yes
SyncIntervalSec=5m
SyncIntervalSec=10s
RateLimitInterval=30s
RateLimitBurst=1000
# 最大占用空间为10G
SystemMaxUse=10G
# 单文件最大200M
SystemMaxFileSize=200M

#日志保存时间为两周
MaxRetentionSec=2week

# 不将日志转发到syslog
ForwardToSyslog=no
EOF

systemctl restart systemd-journald
```
* kube-proxy开启ipvs的前置条件
```
modprobe br_netfilter
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#! /bin/bash
modprobe -- ipvs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF

chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules &&
lsmod | grep -e ip_vs -e nf_conntrack_ipv4
```
```如果modprobe命令不存在，则是系统内核版本太低，可参考第三步的操作升级为4.4```

* 安装Docker软件

```
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum update -y && yum install -y docker-ce
```

* 配置Docker配置文件，在配置之前需要通过``` df -h|head```命令查看当前系统磁盘哪个适合作为Docker的工作盘
```
mkdir /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
      "exec-opts": ["native.cgroupdriver=systemd"],
      "log-driver": "json-file",
      "log-opts": {
          "max-size": "100m"
    },
      "data-root": "/data/docker"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload && systemctl restart docker && systemctl enable docker
```

* 安装Kubeadm
```
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

yum -y install kubeadm-1.17.1 kubectl-1.17.1 kubelet-1.17.1
systemctl enable kubelet.service
```
至此，以上的所有步骤需要在所有机器上都执行.

### 准备镜像
由于有些镜像需要科学上网才可下载，所以本人已将需要的镜像搬至[Docker hub](https://hub.docker.com/repository/docker/xianyanglin/kube),需要自取
[脚本于此](scripts/download-images.sh)

### Master节点操作
* 生成初始化主节点默认配置
```
kubeadm config print init-defaults >kubeadm-config.yaml
```
生成的```kubeadm-config.yaml```文件需要做些改动，如下:

* 设置Master的节点IP
```
localAPIEndpoint:
  advertiseAddress: xxx.xxx.xxx.xxx
```
* 设置```flannel```网络组件的IP
```
networking:
  podSubnet: "10.244.0.0/16" #flannel默认设置的pod的IP地址
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12  
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: kubeProxyConfiguration
featureGates:
  SupportIPVSProxyMode: true
mode: ipvs
```

完整的```kubeadm-config.yaml```如下：
```
apiVersion: kubeadm.k8s.io/v1beta2
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: xx.xx.x.xxx #你的Master的主节点
  bindPort: 6443
nodeRegistration:
  criSocket: /var/run/dockershim.sock
  name: k8s-master
  taints:
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta2
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: k8s.gcr.io
kind: ClusterConfiguration
kubernetesVersion: v1.17.1    #设置为你kubernetes的版本
networking:
  podSubnet: "10.244.0.0/16"
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
scheduler: {}
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: kubeProxyConfiguration
featureGates:
  SupportIPVSProxyMode: true
mode: ipvs

```
* 初始化主节点
```
kubeadm init --config=kubeadm-config.yaml --upload-certs | tee kubeadm-init.log
```
* 查看```kubeadm-init.log```,按照指令运行
```
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

### 从节点操作
* 根据```kubeadm-init.log```将从节点加入Master
```
kubeadm join xx.xx.x.xxx:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:1ce54d0cd190913ca095533b0c44ce35a3e6a9860ef95217ed0b40d846406669 
```

### 部署网络
tips:```所有节点都必须存在flannel镜像```

* 在Master上执行

```
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

kubectl apply -f kube-flannel.yml
kubectl get pod -n kube-system
```

至此，所有安装已经完毕，可在master通过命令```kubectl get nodes```和```kubectl get pod -n kube-system```查看节点信息




### 爬坑
安装过程中遇到什么问题，可通过```journalctl```命令进行查看
```
journalctl -xeu kubelet
或者
journalctl -f -u kubelet.service
```

* 坑一
```
error: failed to run Kubelet: failed to create kubelet: misconfiguration: kubelet cgroup driver: "systemd" is different from docker cgroup driver: "cgroupfs"
```
问题：docker的磁盘驱动与kubelet指定的不一致
处理:
```
vi /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=systemd"
```
```docker```的配置```/etc/docker/daemon.json```也需要设置为```["native.cgroupdriver=systemd"]```


* 坑二
```
kubelet: Failed to start ContainerManager Cannot set property TasksAccounting, or unknown property
```

处理:升级systemd组件
```
yum update systemd
```

### Dashboard安装
Master安装dashboard，国内可以使用别的yaml源
```
# 安装dashboard，国内可以使用别的yaml源
wget   https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
```

* 修改node为NodePort模式
```
kind: Service
apiVersion: v1
metadata:
  labels:
    k8s-app: kubernetes-dashboard
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
spec:
  ports:
    - port: 443
      targetPort: 8443
      nodePort: 30001
  selector:
    k8s-app: kubernetes-dashboard
  type:
    NodePort
```
* 里面的镜像地址可以改为
```
registry.aliyuncs.com/google_containers/kubernetes-dashboard-amd64:v1.10.1
```
* 执行生成dashboard
```
kubectl apply -f kubernetes-dashboard.yaml
```
* 查看服务(得知dashboard运行在443:32383/TCP端口)
```
kubectl get svc -n kube-system 
```
* 生成Token
```
kubectl describe secret -n kube-system dashboard-admin-token
```

### 常用命令
```
#删除节点
kubectl delete node k8s-slave01

#卸载服务
kubeadm reset

#删除容器及镜像
docker images -qa|xargs docker rmi -f

查看kubelet状态
systemctl status kubelet

查看kubelet日志
journalctl -xeu kubelet
journalctl -f -u kubelet.service

升级systemd组件
yum update systemd

重启系统命令
systemctl daemon-reload
systemctl daemon-reload && service kubelet restart

卸载旧版本
yum remove -y kubelet kubeadm kubectl

```
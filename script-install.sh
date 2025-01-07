#!/bin/bash

# Update and upgrade yum packages
sudo yum update -y
sudo yum upgrade -y

# Install required packages
sudo yum install -y curl wget openssl git unzip docker sed

# Install k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --https-listen-port 6550" sh -

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Create .kube directory
rm -rf /home/ec2-user/.kube 2>/dev/null
mkdir /home/ec2-user/.kube

# Copy k3s config to user kube config
sudo cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
sudo chown ec2-user:ec2-user /home/ec2-user/.kube/config

# Define KUBECONFIG
export KUBECONFIG=/home/ec2-user/.kube/config
echo "export KUBECONFIG=/home/ec2-user/.kube/config" >> /home/ec2-user/.bashrc

# Add Helm repositories
helm repo add metallb https://metallb.github.io/metallb
helm repo add kong https://charts.konghq.com
helm repo add veecode-platform https://veecode-platform.github.io/public-charts/
helm repo update

# Wait for 5 seconds
sleep 5

# Install MetalLB
helm upgrade --install metallb metallb/metallb --create-namespace -n metallb-system --wait

# Apply MetalLB IPAddressPool
cat <<EOF > metallb-ipaddresspool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
    - $EC2_PUBLIC_IP/32
EOF
kubectl apply -f metallb-ipaddresspool.yaml

# Install Kong
helm upgrade --install kong kong/kong --version 2.42.0 \
  --set env.database="off" \
  --set manager.enabled=false \
  --set proxy.enabled=true \
  --set proxy.http.containerPort=8000 \
  --set proxy.http.enabled=true \
  --set proxy.http.servicePort=80 \
  --set proxy.tls.containerPort=8443 \
  --set proxy.tls.enabled=true \
  --set proxy.tls.servicePort=443 \
  --set proxy.type=LoadBalancer

# Install DevPortal Admin UI
helm upgrade --install devportal-admin-ui --wait --timeout 8m veecode-platform/devportal-admin-ui --version $ADMIN_UI_CHART_VERSION --create-namespace -n platform \
  --set "serviceAccount.create=true" \
  --set "ingress.enabled=true" \
  --set "ingress.className=kong" \
  --set "ingress.hosts[0].paths[0].path=/admin-ui,ingress.hosts[0].paths[0].pathType=Prefix" \
  --set "ingress.annotations.konghq\.com/strip-path=\"true\"" \
  --set "appConfig.chartValuesFileName=current.yaml" \
  --set "appConfig.filePath=./platform/admin-ui" \
  --set "appConfig.baseURL=http://localhost:3000/admin-ui" \
  --set "appConfig.sslProduction=false" \
  --set "readinessProbe.exec.command[0]=cat" \
  --set "readinessProbe.exec.command[1]=/tmp/healthy" \
  --set "readinessProbe.initialDelaySeconds=5" \
  --set "readinessProbe.periodSeconds=5" \
  --set "livenessProbe.exec.command[0]=cat" \
  --set "livenessProbe.exec.command[1]=/tmp/healthy" \
  --set "livenessProbe.initialDelaySeconds=5" \
  --set "livenessProbe.periodSeconds=5" \
  --set "persistence.enabled=true" \
  --set "persistence.storageClassName=manual" \
  --set "persistence.accessModes[0]=ReadWriteOnce" \
  --set "persistence.size=1Gi" \
  --set "persistence.hostPath=/platform-volume/admin-ui" \
  --set "persistentVolumeClaim.enabled=true" \
  --set "persistentVolumeClaim.storageClassName=manual" \
  --set "persistentVolumeClaim.accessModes[0]=ReadWriteOnce" \
  --set "persistentVolumeClaim.resources.requests.storage=1Gi"

# Install Platform DevPortal
helm upgrade platform-devportal --install --wait --timeout 10m veecode-platform/devportal --create-namespace --version $DEVPORTAL_CHART_VERSION  -n platform \
  --set "platform.behaviour.mode=demo" \
  --set "appConfig.app.baseUrl=http://localhost:7007" \
  --set "appConfig.backend.baseUrl=http://localhost:7007" \
  --set "ingress.enabled=true" \
  --set "ingress.className=kong" \
  --set "ingress.host=" \
  --set "locations[0].type=url,locations[0].target=https://github.com/veecode-platform/demo-catalog/blob/main/catalog-info.yaml"


# Get EC2 public IP
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
EC2_PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
echo "IP_EC2 = $EC2_PUBLIC_IP"

# Update kube config with EC2 public IP
sed -i 's/certificate-authority-data:.*/insecure-skip-tls-verify: true/' /home/ec2-user/.kube/config
sed -i "s/127.0.0.1/$EC2_PUBLIC_IP/" /home/ec2-user/.kube/config

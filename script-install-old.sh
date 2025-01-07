#!/bin/bash

set -e
#Update and install necessary packages
sudo yum update && sudo yum upgrade
sudo yum install -y curl-minimal wget openssl git unzip docker
sudo systemctl start docker && sudo systemctl enable docker
sudo usermod -aG docker "$(whoami)"
newgrp docker
sudo chmod 666 /var/run/docker.sock

#Installing K8S tools
curl -sS https://webinstall.dev/k9s | bash
# wget https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_Linux_amd64.tar.gz && \
#     tar -xvf k9s_Linux_amd64.tar.gz && \
#     sudo mv k9s /usr/bin && \
#     sudo chmod +x  /usr/bin/k9s && \
#     rm k9s_Linux_amd64.tar.gz LICENSE README.md
curl -sS https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
curl -sS https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash
sudo wget "https://dl.k8s.io/release/v1.29.4/bin/linux/amd64/kubectl" -O /usr/bin/kubectl && sudo chmod +x /usr/bin/kubectl
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq

#Configuring helm chart repositories
helm repo add kong https://charts.konghq.com
helm repo add veecode-platform https://veecode-platform.github.io/public-charts/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

#Starting k3d cluster
sudo mkdir -p /platform-volume/postgres
sudo mkdir -p /platform-volume/admin-ui
sudo chown 1000:1000 /platform-volume/*

k3d cluster create platform-cluster --servers 1 \
  --volume /platform-volume/admin-ui:/platform-volume/admin-ui \
  --volume /platform-volume/postgres:/platform-volume/postgres \
  -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:*" 

kubectl create namespace platform

#Setting versions from our installation:
sudo mkdir -p /platform-volume/admin-ui/settings
sudo touch /platform-volume/admin-ui/settings/versions.yaml
sudo touch /platform-volume/admin-ui/settings/settings.yaml

#If you want to change the versions, you can do it at variable.pkr.hcl file
sudo yq e ".devportal.helm.version=\"$DEVPORTAL_CHART_VERSION\" |
      .admin-ui.helm.version=\"$ADMIN_UI_CHART_VERSION\" |
      .keycloak.helm.version=\"$KEYCLOAK_CHART_VERSION\" |
      .kong.helm.version=\"$KONG_CHART_VERSION\" |
      .postgresql.helm.version=\"$POSTGRES_CHART_VERSION\"" -i /platform-volume/admin-ui/settings/versions.yaml

#installing metrics-server
# kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-volume
  namespace: platform
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 3Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/platform-volume/postgres"
" | kubectl apply -f -

echo "
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-volume-claim
  namespace: platform
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 3Gi
" | kubectl apply -f -

#Installing postgresql
#Doc: https://artifacthub.io/packages/helm/bitnami/postgresql
helm upgrade --install --create-namespace --wait --timeout 5m postgresql bitnami/postgresql --version $POSTGRES_CHART_VERSION -n platform \
--set "fullnameOverride=postgres-postgresql" \
--set "global.postgresql.auth.database=postgres" \
--set "global.postgresql.auth.postgresPassword=$POSTGRES_ADMIN_PASSWORD" \
--set "volumePermissions.enabled=true" \
--set "primary.persistence.size=3Gi" \
--set "primary.persistence.existingClaim=postgres-volume-claim"

#Create a database and user for kong
kubectl exec postgres-postgresql-0 -n platform -- env PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -U postgres -c "CREATE USER $KONG_DATABASE_USERNAME WITH ENCRYPTED PASSWORD '$KONG_DATABASE_PASSWORD';";
kubectl exec postgres-postgresql-0 -n platform -- env PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -U postgres -c "CREATE DATABASE kong OWNER $KONG_DATABASE_USERNAME;";

#Installing kong ingress controller
#DOC: https://artifacthub.io/packages/helm/kong/kong
helm upgrade --install --create-namespace --wait --timeout 5m kong-ingress kong/kong --version $KONG_CHART_VERSION -n kong \
--set "image.tag=3.4" \
--set "customEnv.KONG_LUA_SSL_TRUSTED_CERTIFICATE=system" \
--set "ingressController.enabled=true" \
--set "admin.enabled=true" \
--set "admin.http.enabled=true" \
--set "admin.http.servicePort=8001" \
--set "admin.http.containerPort=8001" \
--set "prefix=/kong_prefix/" \
--set "env.database=postgres" \
--set "env.pg_ssl=off" \
--set "env.pg_database=kong" \
--set "env.pg_host=postgres-postgresql.platform" \
--set "env.pg_password=$KONG_DATABASE_PASSWORD" \
--set "env.pg_port=5432" \
--set "env.pg_user=$KONG_DATABASE_USERNAME";

#Create a database and user for keycloak
kubectl exec postgres-postgresql-0 -n platform -- env PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -U postgres -c "CREATE USER $KEYCLOAK_DATABASE_USERNAME WITH ENCRYPTED PASSWORD '$KEYCLOAK_DATABASE_PASSWORD';"
kubectl exec postgres-postgresql-0 -n platform -- env PGPASSWORD=$POSTGRES_ADMIN_PASSWORD psql -U postgres -c "CREATE DATABASE keycloak OWNER $KEYCLOAK_DATABASE_USERNAME;"

#Creating a configmap from the realm to import into keycloak
curl -Os https://raw.githubusercontent.com/veecode-platform/support/gh-pages/references/devportal/realm-platform-devportal.json && \
kubectl create configmap realm-platform-devportal --from-file=realm-platform-devportal.json -n platform && \
rm realm-platform-devportal.json

#Installing keycloak
#DOC: https://artifacthub.io/packages/helm/bitnami/keycloak
helm upgrade --install --create-namespace --wait --timeout 10m keycloak bitnami/keycloak --version $KEYCLOAK_CHART_VERSION -n platform \
--set "auth.adminPassword=admin" \
--set "auth.adminUser=admin" \
--set "auth.managementPassword=senha" \
--set "containerPorts.http=8080" \
--set "containerPorts.https=8443" \
--set "ingress.enabled=true" \
--set "ingress.hostname=keycloak.homolog.platform.vee.codes" \
--set "ingress.ingressClassName="kong"" \
--set "ingress.path=/auth/" \
--set "ingress.tls=false" \
--set "ingress.annotations.konghq\.com/strip-path=\"true\"" \
--set "postgresql.enabled=false" \
--set "externalDatabase.host=postgres-postgresql.platform" \
--set "externalDatabase.port=5432" \
--set "externalDatabase.user=$KEYCLOAK_DATABASE_USERNAME" \
--set "externalDatabase.password=$KEYCLOAK_DATABASE_PASSWORD" \
--set "externalDatabase.database=keycloak" \
--set "externalDatabase.schema=public" \
--set "extraVolumes[0].name=realm-import-config,extraVolumes[0].configMap.name=realm-platform-devportal" \
--set "extraVolumeMounts[0].name=realm-import-config,extraVolumeMounts[0].mountPath=/opt/bitnami/keycloak/data/import/" \
--set "extraStartupArgs=--db=postgres --spi-login-protocol-openid-connect-legacy-logout-redirect-uri=true --import-realm" \
--set "httpRelativePath=/auth/"

kubectl get ingress keycloak -n platform -o yaml | \
  yq e 'del(.spec.rules[0].host)' | kubectl apply -f -

sleep 5;

export KEYCLOAK_ADDRESS=$(kubectl get ingress keycloak -o jsonpath='{.status.loadBalancer.ingress[0].ip}' -n platform)

echo "KEYCLOAK_ADDRESS >>>> $KEYCLOAK_ADDRESS"

export ACCESS_TOKEN=$(curl -sX POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    -d "username=admin" \
    -d "password=admin" \
    "http://$KEYCLOAK_ADDRESS/auth/realms/master/protocol/openid-connect/token" | jq -r '.access_token')

export NEW_USER_JSON='{
  "username": "admin",
  "enabled": true,
  "emailVerified": false,
  "attributes": {
    "createDate": [
      "'$(date +%s)'"
    ]
  },
  "credentials": [
    {
      "type": "password",
      "value": "admin",
      "temporary": false
    }
  ]
}'
  
curl -sX POST "http://$KEYCLOAK_ADDRESS/auth/admin/realms/veecode-platform/users" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$NEW_USER_JSON"

export USER_ID=$(curl -sX GET "http://$KEYCLOAK_ADDRESS/auth/admin/realms/veecode-platform/users" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  | jq -r '.[] | select(.username == "admin") | .id')

export GROUP_ID=$(curl -sX GET "http://$KEYCLOAK_ADDRESS/auth/admin/realms/veecode-platform/groups" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  | jq -r '.[] | select(.name == "platform-admin") | .id')


curl -X PUT "http://$KEYCLOAK_ADDRESS/auth/admin/realms/veecode-platform/users/$USER_ID/groups/$GROUP_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

#Setting Kubernetes scale to 0
kubectl scale --replicas=0 statefulsets/keycloak -n platform

#Installing devportal
#DOC: https://artifacthub.io/packages/helm/veecode-platform/devportal
helm upgrade platform-devportal --install --wait --timeout 10m veecode-platform/devportal --create-namespace --version "$DEVPORTAL_CHART_VERSION" -n platform \
  --set "platform.behaviour.mode=demo" \
  --set "appConfig.app.baseUrl=http://localhost:7007" \
  --set "appConfig.backend.baseUrl=http://localhost:7007" \
  --set "ingress.enabled=true" \
  --set "ingress.className=kong" \
  --set "ingress.host=" \
  --set "locations[0].type=url,locations[0].target=https://github.com/veecode-platform/demo-catalog/blob/main/catalog-info.yaml"

#Installing devportal-admin-ui
#DOC: https://artifacthub.io/packages/helm/veecode-platform/devportal-admin-ui
helm upgrade --install devportal-admin-ui --wait --timeout 8m veecode-platform/devportal-admin-ui --create-namespace -n platform \
  --set "serviceAccount.create=true" \
  --set "ingress.enabled=true" \
  --set "ingress.className=kong" \
  --set "ingress.hosts[0].paths[0].path=/admin-ui,ingress.hosts[0].paths[0].pathType=Prefix" \
  --set "ingress.annotations.konghq\.com/strip-path=\"true\"" \
  --set "appConfig.chartValuesFileName=current.yaml" \
  --set "appConfig.filePath=./platform/admin-ui" \
  --set "appConfig.baseURL=http://localhost:3000/admin-ui" \
  --set "appConfig.sslProduction=false" \
  --set "installationMode=embedded" \
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
  --set "persistentVolumeClaim.resources.requests.storage=1Gi" \
  --version "$ADMIN_UI_CHART_VERSION"

#Configure PermitRootLogin without-password
sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin without-password/' /etc/ssh/sshd_config

#Remove authorized_keys
echo "Removing authorized_keys...."
sudo rm /home/ec2-user/.ssh/authorized_keys
sudo rm /root/.ssh/authorized_keys
echo "authorized_keys removed successfully"

sudo chmod 660 /var/run/docker.sock

echo "OS_VERSION=$(grep -E -w 'PRETTY_NAME' /etc/os-release | sed -E 's/.*"Amazon Linux ([^"]+)".*/\1/')"

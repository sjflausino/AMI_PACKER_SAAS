#!/bin/bash

# Check if password was supplied
if [ -z "$1" ]; then
    echo "Usage: $0 <password>"
    exit 1
fi

# Define the secret name and namespace
secret_name="devportal-admin-ui-credential"
namespace="vkpr"

# Check if the secret exists
if kubectl get secret $secret_name -n $namespace > /dev/null 2>&1; then
    # Create a base64 encoded version of the password
    password_base64=$(echo -n "$1" | base64)
    # Update the secret
    kubectl patch secret $secret_name -n $namespace -p="{\"data\":{\"password\": \"$password_base64\"}}"
else
    # Create the secret
    kubectl create secret generic $secret_name -n $namespace \
  --from-literal=kongCredType=basic-auth \
  --from-literal=username=admin \
  --from-literal=password=$1
fi
echo "Password updated"


kubectl create secret generic devportal-admin-ui-credential -n vkpr \
  --from-literal=kongCredType=basic-auth \
  --from-literal=username=admin \
  --from-literal=password=admin
#get the password
kubectl get secret devportal-admin-ui-credential -n vkpr -o jsonpath="{.data.password}" | base64 --decode
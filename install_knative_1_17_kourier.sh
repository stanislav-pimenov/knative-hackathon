#!/bin/bash
set -euo pipefail

echo "[Step 1] Installing required CLI tools (kubectl)"

# Detect architecture (Intel vs Apple Silicon)
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
  KUBECTL_URL="https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"
else
  KUBECTL_URL="https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
fi

# Install kubectl
if ! command -v kubectl &> /dev/null; then
  echo "Installing kubectl..."
  curl -LO "$KUBECTL_URL"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
else
  echo "kubectl already installed"
fi

echo "[Step 2] Installing Knative Serving v1.17"
KNATIVE_VERSION="knative-v1.17.0"

echo "[Step 2] Pulling images of Knative Serving v1.17"
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/activator@sha256:cd4bb3af998f4199ea760718a309f50d1bcc9d5c4a1c5446684a6a0115a7aad5
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler@sha256:ac1a83ba7c278ce9482b7bbfffe00e266f657b7d2356daed88ffe666bc68978e
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/controller@sha256:df24c6d3e20bc22a691fcd8db6df25a66c67498abd38a8a56e8847cb6bfb875b
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/webhook@sha256:d842f05a1b05b1805021b9c0657783b4721e79dc96c5b58dc206998c7062d9d9

kubectl apply -f https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-core.yaml

echo "[Step 3] Installing/Updating Kourier ingress"
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.17.0/kourier.yaml

# Set ingress class to Kourier (idempotent)
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress.class":"kourier.ingress.networking.knative.dev"}}'

echo "[Step 4] Waiting for Knative Serving and Kourier deployments to become ready"
kubectl wait deployment --all --timeout=300s --for=condition=Available -n knative-serving
kubectl wait deployment --all --timeout=300s --for=condition=Available -n kourier-system

echo "[Step 5] Deploying/replacing sample echo service"
cat <<EOF | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: echo
  namespace: default
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: "5"
        autoscaling.knative.dev/target: "50"
        autoscaling.knative.dev/class: "kpa.autoscaling.knative.dev"
        autoscaling.knative.dev/metric: "rps"
        networking.knative.dev/ingress.class: "kourier.ingress.networking.knative.dev"
    spec:
      containers:
        - image: ealen/echo-server:latest
          ports:
            - containerPort: 80
          env:
            - name: EXAMPLE_ENV
              value: "value"
EOF

echo "[Step 6] Waiting for echo service to be ready"
kubectl wait ksvc echo --all --timeout=300s --for=condition=Ready

echo "[Step 7] Patch confi-domain with domain knative.demo.com"
kubectl patch configmap/config-domain --namespace knative-serving --type merge --patch "{\"data\":{\"knative.demo.com\":\"\"}}"

echo '[Step 8] curl -H "Host: echo.default.knative.demo.com" '\''http://localhost:80/api/v1?param=value'\'''
curl -H "Host: echo.default.knative.demo.com" 'http://localhost:80/api/v1/metrics?param=value'



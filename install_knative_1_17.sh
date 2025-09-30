#!/bin/bash
set -euo pipefail

echo "[Step 0] Installing required CLI tools (kubectl & istioctl)"

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

# Install istioctl (1.25.x is safe for Knative 1.17)
if ! command -v istioctl &> /dev/null; then
  echo "Installing istioctl..."
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.25.0 sh -
  cd istio-1.25.*
  export PATH=$PWD/bin:$PATH
  sudo cp bin/istioctl /usr/local/bin/
  cd ..
else
  echo "istioctl already installed"
fi

echo "[Step 1] Installing Istio (profile=demo)"
istioctl install --set profile=demo -y
kubectl label namespace default istio-injection=enabled --overwrite

echo "[Step 2] Installing Knative Serving v1.17 + Istio integration"
KNATIVE_VERSION="knative-v1.17.0"


echo "[Step 2] Pulling images of Knative Serving v1.17"
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/activator@sha256:cd4bb3af998f4199ea760718a309f50d1bcc9d5c4a1c5446684a6a0115a7aad5
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler@sha256:ac1a83ba7c278ce9482b7bbfffe00e266f657b7d2356daed88ffe666bc68978e
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/controller@sha256:df24c6d3e20bc22a691fcd8db6df25a66c67498abd38a8a56e8847cb6bfb875b
docker pull gcr.io/knative-releases/knative.dev/net-istio/cmd/controller@sha256:781a242ee3f5fcf79264b98c65aff8185427404c51ab8ff723e2ebfaf085c593
docker pull gcr.io/knative-releases/knative.dev/net-istio/cmd/webhook@sha256:846e3e40ac21966cbaa4e2aeaa856f0faa8fb26cfaf8e23baada1bad4087be8e
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/webhook@sha256:d842f05a1b05b1805021b9c0657783b4721e79dc96c5b58dc206998c7062d9d9

kubectl label namespace knative-serving istio-injection=enabled

kubectl apply -f https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-core.yaml
kubectl apply -f https://github.com/knative/net-istio/releases/download/${KNATIVE_VERSION}/net-istio.yaml

echo "[Step 3] Deploying sample Knative Service (nginx)"
cat <<EOF | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: helloworld
  namespace: default
  annotations:
    sidecar.istio.io/rewriteAppHTTPProbers: "true"
    proxy.istio.io/config: '{ "holdApplicationUntilProxyStarts": true }'
spec:
  template:
    spec:
      containers:
        - image: ealen/echo-server:latest
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /
              port: 8080
EOF

echo "[Step 4] Waiting for service to be ready..."
kubectl wait ksvc helloworld --for=condition=Ready --timeout=180s

echo "[Step 5] Calling helloworld URL"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: curl-test
spec:
  containers:
  - name: curl
    image: curlimages/curl:8.16.0
    command: ["sleep", "3600"]
  restartPolicy: Never
EOF
kubectl exec -it curl-test -- curl "http://helloworld.default.svc.cluster.local/path?param=value"

cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: my-gateway
  namespace: default
spec:
  selector:
    istio: ingressgateway  # must match the Istio ingress gateway pod labels
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*"
EOF

cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-virtualservice
  namespace: default
spec:
  hosts:
    - "*"
  gateways:
    - my-gateway
  http:
    - match:
        - uri:
            prefix: /myapp
      route:
        - destination:
            host: helloworld.default.svc.cluster.local
            port:
              number: 8080
EOF
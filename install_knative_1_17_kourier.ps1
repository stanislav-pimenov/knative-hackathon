#Requires -Version 5.0
$ErrorActionPreference = "Stop"

Write-Output "[Step 1] Installing required CLI tools (kubectl)"

# Detect architecture
$arch = $env:PROCESSOR_ARCHITECTURE
switch ($arch.ToLower()) {
    "amd64" { $arch = "amd64" }
    "arm64" { $arch = "arm64" }
    default { Write-Error "Unsupported architecture: $arch"; exit 1 }
}

# Install kubectl if not installed
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Output "Installing kubectl..."
    $kubectlVersion = (Invoke-RestMethod -Uri "https://dl.k8s.io/release/stable.txt").Trim()
    $kubectlUrl = "https://dl.k8s.io/release/$kubectlVersion/bin/windows/$arch/kubectl.exe"
    Invoke-WebRequest -Uri $kubectlUrl -OutFile "kubectl.exe"
    Move-Item "kubectl.exe" "C:\Windows\System32\" -Force
} else {
    Write-Output "kubectl already installed"
}

Write-Output "[Step 2] Installing Knative Serving v1.17"
$knativeVersion = "knative-v1.17.0"

Write-Output "[Step 2] Pulling images of Knative Serving v1.17"
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/activator@sha256:cd4bb3af998f4199ea760718a309f50d1bcc9d5c4a1c5446684a6a0115a7aad5
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler@sha256:ac1a83ba7c278ce9482b7bbfffe00e266f657b7d2356daed88ffe666bc68978e
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/controller@sha256:df24c6d3e20bc22a691fcd8db6df25a66c67498abd38a8a56e8847cb6bfb875b
docker pull gcr.io/knative-releases/knative.dev/serving/cmd/webhook@sha256:d842f05a1b05b1805021b9c0657783b4721e79dc96c5b58dc206998c7062d9d9

kubectl apply -f "https://github.com/knative/serving/releases/download/$knativeVersion/serving-crds.yaml"
kubectl apply -f "https://github.com/knative/serving/releases/download/$knativeVersion/serving-core.yaml"

Write-Output "[Step 3] Installing/Updating Kourier ingress"
kubectl apply -f "https://github.com/knative/net-kourier/releases/download/$knativeVersion/kourier.yaml"

# Set ingress class to Kourier
kubectl patch configmap/config-network `
  --namespace knative-serving `
  --type merge `
  --patch '{"data":{"ingress.class":"kourier.ingress.networking.knative.dev"}}'

Write-Output "[Step 4] Waiting for Knative Serving and Kourier deployments to become ready"
kubectl wait deployment --all --timeout=300s --for=condition=Available -n knative-serving
kubectl wait deployment --all --timeout=300s --for=condition=Available -n kourier-system

Write-Output "[Step 5] Deploying/replacing sample echo service"
@"
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
"@ | kubectl apply -f -

Write-Output "[Step 6] Waiting for echo service to be ready"
kubectl wait ksvc echo --all --timeout=300s --for=condition=Ready

Write-Output "[Step 7] Patch config-domain with domain knative.demo.com"
kubectl patch configmap/config-domain `
  --namespace knative-serving `
  --type merge `
  --patch '{"data":{"knative.demo.com":""}}'

Write-Output "[Step 8] curl test request"
curl.exe -H "Host: echo.default.knative.demo.com" "http://localhost:80/api/v1/metrics?param=value"

Write-Output "Done!"

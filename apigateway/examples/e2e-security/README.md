# End-to-End TLS Security Example

This example demonstrates how to deploy API Gateway with full TLS encryption for all communication between components using cert-manager for automated certificate management.

## Overview

This configuration provides end-to-end TLS security with:
- **Elasticsearch**: HTTPS-only communication
- **Kibana**: HTTPS-only communication
- **API Gateway**: Secure connections to both Elasticsearch and Kibana using truststores
- **Certificate Management**: Automated certificate issuance and renewal via cert-manager

## Prerequisites

1. **Kubernetes cluster** (v1.19+)

2. **kubectl** configured with cluster access

3. **Helm 3** installed

4. **webMethods Helm repository** added
   ```bash
   helm repo add webmethods https://staillanibm.github.io/webmethods-helm-charts/charts
   helm repo update
   ```

5. **cert-manager** installed and running
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
   ```

6. **Elastic Cloud on Kubernetes (ECK)** operator installed
   ```bash
   helm repo add elastic https://helm.elastic.co
   helm repo update
   helm install elastic-operator elastic/eck-operator -n elastic-system --create-namespace
   ```

7. **Container Registry Access** - You need credentials to pull webMethods images from the IBM container registry


## Components

### 1. certificates.yaml
Defines cert-manager resources:
- **Self-signed Issuer**: Bootstraps the certificate chain
- **IWHI Root CA**: Organization root certificate authority
- **CA Issuer**: Issues certificates signed by the root CA
- **Elasticsearch Certificate**: Generates keystore and truststore
- **Kibana Certificate**: Generates keystore for Kibana HTTPS server

### 2. secrets.yaml
Contains:
- **cert-secret**: Single password for all keystores (default: `changeit`)
- **Truststore/Keystore password secrets**: References to the main password

### 3. values.yaml
Helm values file configuring:
- Elasticsearch with TLS enabled
- Kibana with TLS enabled
- API Gateway with secure connections to both services
- Proper truststore and keystore mounting
- TLS verification settings

## Deployment

### Step 1: Create Namespace

```bash
kubectl create namespace apigateway
```

### Step 2: Create Image Pull Secret

Create a secret to pull images from the webMethods container registry:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=${WM_CR_SERVER} \
  --docker-username=${WM_CR_USERNAME} \
  --docker-password=${WM_CR_PASSWORD} \
  -n apigateway
```

Replace the environment variables with your actual credentials:
- `WM_CR_SERVER`: Container registry server (e.g., `ibmwebmethods.azurecr.io`)
- `WM_CR_USERNAME`: Your registry username
- `WM_CR_PASSWORD`: Your registry password

### Step 3: Create TLS Secret for Ingresses

Create a TLS secret for the certificate exposed by the ingresses:

```bash
kubectl create secret tls tls-cert \
  --key="${TLS_PRIVATEKEY_FILE_PATH}" \
  --cert="${TLS_PUBLICKEY_FILE_PATH}" \
  -n apigateway
```

This secret is referenced in the ingresses configuration in `values.yaml`.  

Note: this secret could also be generated using cert manager.

### Step 4: Customize values.yaml (Optional)

Before deploying, you may want to customize the `values.yaml` file:

- **Ingress Hostnames**: Update the `ingresses.*.defaultHost` values to match your domain:
  ```yaml
  ingresses:
    ui:
      defaultHost: "apigateway-ui.yourdomain.com"
    rt:
      defaultHost: "apigateway-rt.yourdomain.com"
    admin:
      defaultHost: "apigateway-admin.yourdomain.com"
  ```

- **Image Repository**: If using a different container registry, update:
  ```yaml
  image:
    repository: your-registry.com/apigateway-minimal
    tag: "11.1.0.7"
  ```

- **Resource Limits**: Adjust CPU and memory based on your requirements:
  ```yaml
  resources:
    apigwContainer:
      requests:
        cpu: 500m
        memory: 4Gi
      limits:
        cpu: 2
        memory: 8Gi
  ```

- **Storage Class**: Change Elasticsearch storage class if needed:
  ```yaml
  elasticsearch:
    storageClassName: "your-storage-class"
  ```

### Step 5: Apply Certificate Keystore Password Secrets

```bash
kubectl apply -f secrets.yaml -n apigateway
```

This creates the password secret that cert-manager will use for keystores.

### Step 6: Apply Certificates

```bash
kubectl apply -f certificates.yaml -n apigateway
```

Wait for certificates to be ready:
```bash
kubectl get certificates -n apigateway -w
```

You should see:
```
NAME                READY   SECRET                            AGE
elasticsearch-tls   True    gw-apigateway-es-tls-secret       10s
iwhi-root-ca        True    iwhi-root-ca-secret               10s
kibana-tls          True    gw-apigateway-kb-tls-secret       10s
```

### Step 7: Install API Gateway

```bash
helm install gw ../../helm -f values.yaml -n apigateway
```

Or if using the webMethods Helm repository:
```bash
helm install gw webmethods/apigateway -f values.yaml -n apigateway
```

Note: the chart looks for secrets that are named according to the Helm release. If you change the release name (gw here), you also need to change the secret names in the certificates.yaml and secrets.yaml files.  

### Step 8: Wait for Pods

```bash
kubectl get pods -n apigateway -w
```

All pods should reach `Running` status:
- `gw-*`: API Gateway pod
- `gw-es-default-0`: Elasticsearch pod
- `gw-kb-*`: Kibana pod


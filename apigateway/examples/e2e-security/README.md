# End-to-End TLS Security Example

This example demonstrates how to deploy API Gateway with full TLS encryption for all communication between components using cert-manager for automated certificate management.

## Overview

This configuration provides end-to-end TLS security with:
- **Elasticsearch**: HTTPS-only communication (port 9200)
- **Kibana**: HTTPS-only communication (port 5601)
- **API Gateway**: Secure connections to both Elasticsearch and Kibana using truststores
- **API Gateway UI**: HTTPS endpoint with custom certificate (port 9073)
- **API Gateway Admin**: HTTPS endpoint with default Integration Server certificate (port 5543)
- **Ingress**: TLS termination with backend HTTPS verification
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

5. **cert-manager** installed and running (v1.15+ required for JKS alias support)
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
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
- **Elasticsearch Certificate**: Generates JKS keystore and truststore for Elasticsearch HTTPS (port 9200)
- **Kibana Certificate**: Generates PKCS12 keystore for Kibana HTTPS server (port 5601)
- **UI Certificate**: Generates JKS keystore for API Gateway UI HTTPS endpoint (port 9073)

### 2. secrets.yaml
Contains:
- **cert-secret**: Password for Elasticsearch and Kibana keystores (default: `changeit`)
- **gw-apigateway-es-keystore-secret**: Elasticsearch keystore password
- **gw-apigateway-es-truststore-secret**: Elasticsearch truststore password
- **gw-apigateway-ui-keystore-secret**: API Gateway UI keystore password

### 3. values.yaml
Helm values file configuring:
- **Elasticsearch**: TLS enabled with certificate verification
- **Kibana**: TLS enabled with HTTPS endpoint
- **API Gateway**:
  - Secure connections to Elasticsearch and Kibana using mounted truststores/keystores
  - UI HTTPS port (9073) with custom certificate via environment variables
  - Admin HTTPS port (5543) using default Integration Server certificate
- **Ingresses**:
  - UI ingress with backend HTTPS and SSL verification enabled
  - Admin ingress with backend HTTPS (SSL verification disabled for default cert)
  - RT ingress for API runtime traffic
- **Volumes and Mounts**: Keystores and truststores mounted at appropriate paths
- **Environment Variables**: TLS configuration for Elasticsearch datastore and UI HTTPS

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
apigateway-ui-tls   True    gw-apigateway-ui-tls-secret       10s
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
- `gw-apigateway-*`: API Gateway pod
- `gw-apigateway-es-default-0`: Elasticsearch pod
- `gw-apigateway-kb-*`: Kibana pod

### Step 9: Access the UI

Access the API Gateway UI via the ingress hostname configured in `values.yaml`:

```
https://apigateway-ui.sttlab.local
```

## Architecture

### TLS Communication Flow

1. **Ingress → Services**: TLS termination at ingress, backend HTTPS to services
2. **API Gateway → Elasticsearch**: HTTPS with certificate verification
3. **API Gateway → Kibana**: HTTPS communication
4. **API Gateway UI**: HTTPS on port 9073 with custom certificate
5. **API Gateway Admin**: HTTPS on port 5543 with default Integration Server certificate

### Port Summary

| Component | HTTP Port | HTTPS Port | Certificate |
|-----------|-----------|------------|-------------|
| UI | 9072 | 9073 | Custom (cert-manager) |
| Admin | 5555 | 5543 | Default IS |
| Runtime | 5556 | - | - |
| Elasticsearch | - | 9200 | Custom (cert-manager) |
| Kibana | - | 5601 | Custom (cert-manager) |

## Cleanup

To remove the deployment:

```bash
helm uninstall gw -n apigateway
kubectl delete -f certificates.yaml -n apigateway
kubectl delete -f secrets.yaml -n apigateway
kubectl delete namespace apigateway
```

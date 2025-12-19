# End-to-End TLS Security Example

This example demonstrates how to deploy webMethods Developer Portal with full TLS encryption for Elasticsearch communication using cert-manager for automated certificate management.

## Overview

This configuration provides end-to-end TLS security with:
- **Elasticsearch**: HTTPS-only communication with TLS enabled
- **Developer Portal**: Secure connections to Elasticsearch using JKS truststore
- **UI Server HTTPS**: Developer Portal UI exposed via HTTPS (port 8443)
- **API Gateway** (optional): Secure connections to API Gateway using JKS truststore
- **Ingress**: Backend SSL verification with CA trust
- **Certificate Management**: Automated certificate issuance and renewal via cert-manager
- **Dynamic Configuration**: Runtime wrapper.conf generation with TLS properties

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
- **Elasticsearch Certificate**: Generates both JKS and PKCS12 keystores/truststores
- **UI Server Certificate**: JKS keystore for Developer Portal HTTPS server

The Elasticsearch certificate includes:
- `tls.crt`, `tls.key`: PEM format certificates
- `ca.crt`: Root CA certificate
- `keystore.jks`, `truststore.jks`: Java keystores for Developer Portal
- `keystore.p12`: PKCS12 format for Elasticsearch

The UI Server certificate includes:
- `keystore.jks`: JKS keystore for HTTPS server
- Certificate alias: `certificate` (default from cert-manager)

### 2. secrets.yaml
Contains:
- **cert-secret**: Password for all JKS keystores (default: `changeit`)

**IMPORTANT**: Change the password for production environments and consider using a secret management solution like sealed-secrets or external-secrets.

### 3. values-tls.yaml
Helm values file configuring:
- Developer Portal v11.1.0.9 image
- Port 8080 (HTTP) for internal health checks and metrics
- Port 8443 (HTTPS) for external UI access
- Elasticsearch 8.12.2 with TLS enabled
- TLS truststore mounting at `/certs/es`
- UI Server keystore mounting at `/certs/ui`
- Dynamic wrapper.conf generation via initContainer
- Ingress with TLS termination and backend SSL verification
- Health probes using HTTP port (8080)
- Prometheus scraping on HTTP port (8080)

## Deployment

### Step 1: Create Namespace

```bash
kubectl create namespace devportal
```

### Step 2: Create Image Pull Secret

Create a secret to pull images from the webMethods container registry:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=${WM_CR_SERVER} \
  --docker-username=${WM_CR_USERNAME} \
  --docker-password=${WM_CR_PASSWORD} \
  -n devportal
```

Replace the environment variables with your actual credentials:
- `WM_CR_SERVER`: Container registry server (e.g., `ibmwebmethods.azurecr.io`)
- `WM_CR_USERNAME`: Your registry username
- `WM_CR_PASSWORD`: Your registry password

### Step 3: Create TLS Secret for Ingress

Create a TLS secret for the certificate exposed by the ingress:

```bash
kubectl create secret tls tls-cert \
  --key="${TLS_PRIVATEKEY_FILE_PATH}" \
  --cert="${TLS_PUBLICKEY_FILE_PATH}" \
  -n devportal
```

This secret is referenced in the ingress configuration in `values-tls.yaml`.

Note: This secret could also be generated using cert-manager.

### Step 4: Customize values-tls.yaml (Optional)

Before deploying, you may want to customize the `values-tls.yaml` file:

- **Ingress Hostname**: Update the `defaultHostname` to match your domain:
  ```yaml
  ingress:
    defaultHostname: devportal.yourdomain.com
    tls:
      - secretName: tls-cert
        hosts:
          - devportal.yourdomain.com
  ```

- **Image Repository**: If using a different container registry, update:
  ```yaml
  image:
    repository: your-registry.com/devportal
    tag: "11.1.0.9"
  ```

- **Resource Limits**: Adjust CPU and memory based on your requirements:
  ```yaml
  resources:
    devportalContainer:
      requests:
        cpu: 1
        memory: 1Gi
      limits:
        cpu: 1
        memory: 4Gi
  ```

- **Elasticsearch Version**: Change if needed:
  ```yaml
  elasticsearch:
    version: 8.12.2
  ```

- **API Gateway TLS** (optional): If Developer Portal needs to connect to API Gateway with TLS, enable:
  ```yaml
  devportal:
    tls:
      apigw:
        enabled: true
        truststoreSecret: "apigw-tls-secret"
        truststorePasswordSecret: "cert-secret"
        truststorePasswordKey: "password"
        truststorePath: "/certs/apigw/truststore.jks"
  ```

  This will:
  - Mount the API Gateway truststore at `/certs/apigw`
  - Add wrapper properties: `javax.net.ssl.apigateway.trustStore` and `javax.net.ssl.apigateway.trustStorePassword`
  - Require a Kubernetes secret containing the API Gateway JKS truststore

### Step 5: Create API Gateway Truststore Secret (Optional)

If you need Developer Portal to connect to API Gateway with TLS, create a secret containing the API Gateway JKS truststore:

```bash
kubectl create secret generic apigw-tls-secret \
  --from-file=truststore.jks=/path/to/apigw-truststore.jks \
  -n devportal
```

This truststore should contain the API Gateway's CA certificate or server certificate. You can:

**Option 1: Export from existing API Gateway deployment** (if both are in the same cluster and using cert-manager):
```bash
# If API Gateway is also using cert-manager with the same CA
kubectl get secret -n apigateway gw-apigateway-es-tls-secret -o jsonpath='{.data.truststore\.jks}' | base64 -d > apigw-truststore.jks
kubectl create secret generic apigw-tls-secret --from-file=truststore.jks=apigw-truststore.jks -n devportal
```

**Option 2: Use the same CA certificate** (if both use the same root CA):
```bash
# Copy the same truststore since they share the same CA
kubectl get secret -n devportal devportal-developerportal-es-tls-secret -o yaml | \
  sed 's/name: devportal-developerportal-es-tls-secret/name: apigw-tls-secret/' | \
  kubectl apply -n devportal -f -
```

**Option 3: Import existing truststore** from your organization's PKI:
```bash
kubectl create secret generic apigw-tls-secret --from-file=truststore.jks=/path/to/apigw-truststore.jks -n devportal
```

To enable API Gateway TLS in `values-tls.yaml`, uncomment and configure the `devportal.tls.apigw` section.

### Step 6: Configure UI Server HTTPS (Recommended)

The example enables HTTPS for the Developer Portal UI server, providing end-to-end encryption from the internet to the pod:

```yaml
devportal:
  tls:
    ui:
      enabled: true
      port: 8443
      keystoreSecret: "devportal-developerportal-ui-tls-secret"
      keystorePasswordSecret: "cert-secret"
      keystorePasswordKey: "password"
      keystorePath: "/certs/ui/keystore.jks"
      keyAlias: "certificate"  # Default alias used by cert-manager
```

This configuration:
- Enables HTTPS on port 8443 for the UI server
- Mounts the UI keystore at `/certs/ui`
- Adds wrapper properties for server SSL configuration
- Keeps HTTP port 8080 available for internal health checks and Prometheus metrics

**Ingress Backend SSL Verification**:

The ingress is configured to verify the backend certificate:
```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/proxy-ssl-verify: "on"
    nginx.ingress.kubernetes.io/proxy-ssl-secret: "devportal/iwhi-root-ca-secret"
    nginx.ingress.kubernetes.io/proxy-ssl-name: "devportal-developerportal.devportal.svc.cluster.local"
```

This ensures:
- Ingress connects to backend via HTTPS (not just HTTP)
- Backend certificate is verified against the IWHI Root CA
- Prevents man-in-the-middle attacks between ingress and pod
- Complete end-to-end encryption chain

**Port Usage**:
- **Port 8080 (HTTP)**: Internal traffic (health checks, metrics)
- **Port 8443 (HTTPS)**: External traffic via ingress

This architecture provides security where it matters (external connections) while keeping internal operations simple.

### Step 7: Apply Certificate Keystore Password Secret

```bash
kubectl apply -f secrets.yaml -n devportal
```

This creates the password secret that cert-manager will use for JKS keystores.

### Step 8: Apply Certificates

```bash
kubectl apply -f certificates.yaml -n devportal
```

Wait for certificates to be ready:
```bash
kubectl get certificates -n devportal -w
```

You should see:
```
NAME                READY   SECRET                                        AGE
devportal-ui-tls    True    devportal-developerportal-ui-tls-secret      10s
elasticsearch-tls   True    devportal-developerportal-es-tls-secret      10s
iwhi-root-ca        True    iwhi-root-ca-secret                           10s
```

### Step 9: Install Developer Portal

```bash
helm install devportal ../../helm -f values-tls.yaml -n devportal
```

Or if using the webMethods Helm repository:
```bash
helm install devportal webmethods/developerportal -f values-tls.yaml -n devportal
```

**Note**: The chart looks for secrets that are named according to the Helm release. If you change the release name (devportal here), you also need to change the secret names in `certificates.yaml` to match:
```yaml
# In certificates.yaml, change:
secretName: devportal-developerportal-es-tls-secret
# To:
secretName: <your-release-name>-developerportal-es-tls-secret
```

### Step 10: Wait for Pods

```bash
kubectl get pods -n devportal -w
```

All pods should reach `Running` status:
- `devportal-developerportal-0`: Developer Portal StatefulSet pod (exposing both ports 8080 and 8443)
- `devportal-developerportal-es-default-0`: Elasticsearch pod

The Developer Portal pod will show `0/1` initially while the initContainer generates the wrapper.conf, then `1/1` once ready.

## Verification

### Check HTTPS Access

Access the Developer Portal via HTTPS through the ingress:

```bash
curl -k https://devportal.sttlab.local/portal
```

You should see a redirect to the login page.

### Verify Port Configuration

Check that the pod exposes both ports:

```bash
kubectl get pod devportal-developerportal-0 -n devportal -o jsonpath='{.spec.containers[0].ports}' | jq .
```

Expected output:
```json
[
  {
    "containerPort": 8080,
    "name": "ui-http",
    "protocol": "TCP"
  },
  {
    "containerPort": 8443,
    "name": "ui-https",
    "protocol": "TCP"
  }
]
```

### Verify Backend SSL Verification

Check that nginx is verifying the backend certificate:

```bash
kubectl get ingress devportal-developerportal -n devportal -o yaml | grep proxy-ssl
```

You should see the three annotations:
- `nginx.ingress.kubernetes.io/proxy-ssl-verify: "on"`
- `nginx.ingress.kubernetes.io/proxy-ssl-secret: devportal/iwhi-root-ca-secret`
- `nginx.ingress.kubernetes.io/proxy-ssl-name: devportal-developerportal.devportal.svc.cluster.local`

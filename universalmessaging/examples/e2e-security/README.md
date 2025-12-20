# End-to-End TLS Security Example

This example demonstrates how to deploy Universal Messaging with full TLS encryption using cert-manager for automated certificate management.

## Overview

This configuration provides end-to-end TLS security with:
- **NSP (19100)**: Native Socket Protocol (TCP, non-encrypted)
- **NSPS (19443)**: Native Socket Protocol over TLS with configurable mutual TLS
- **NHP (9000)**: Native HTTP Protocol (for health probes)
- **NHPS (19001)**: Native HTTP Protocol over TLS (HTTPS) with configurable mutual TLS
- **Certificate Management**: Automated certificate issuance and renewal via cert-manager
- **Startup Automation**: Automatic interface creation/update via startup script with server readiness check
- **Service Exposure**: All ports exposed via Kubernetes Service
- **Ingress**: TLS passthrough support for external HTTPS access

## Prerequisites

1. **Kubernetes cluster** (v1.19+)

2. **kubectl** configured with cluster access

3. **Helm 3** installed

4. **webMethods Helm repository** added
   ```bash
   helm repo add webmethods https://ibm.github.io/webmethods-helm-charts/charts
   helm repo update
   ```

5. **cert-manager** installed and running (v1.15+ required for JKS keystore support)
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
   ```

   Verify installation:
   ```bash
   kubectl get pods -n cert-manager
   ```

   All pods should be Running:
   - cert-manager
   - cert-manager-cainjector
   - cert-manager-webhook

6. **Container Registry Access** - You need credentials to pull webMethods images from the IBM container registry

7. **(Optional) nginx ingress controller** with TLS passthrough enabled if using it at ingress level
   ```bash
   # Enable SSL passthrough in nginx ingress controller
   --enable-ssl-passthrough
   ```

## Components

### 1. certificates.yaml
Defines cert-manager resources:
- **Self-signed Issuer**: Bootstraps the certificate chain
- **IWHI Root CA**: Organization root certificate authority
- **CA Issuer**: Issues certificates signed by the root CA
- **UM Server Certificate**: Generates JKS keystore and truststore with:
  - Service DNS names for internal cluster communication
  - Ingress hostname (`um.sttlab.local`) for external TLS passthrough
  - Localhost for internal connections

### 2. secrets.yaml
Contains password secrets for the keystores:
- **um-keystore-password**: Password for keystore.jks (default: `changeit`)
- **um-truststore-password**: Password for truststore.jks (default: `changeit`)

**IMPORTANT**: In production, use stronger passwords and consider using external secret management solutions like:
- Kubernetes External Secrets Operator
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault

### 3. values.yaml
Helm values file configuring:
- **TLS Environment Variables**:
  - Keystore and truststore paths
  - Passwords retrieved from Kubernetes secrets
  - mTLS configuration (client certificate required: false by default)
- **Startup Script**:
  - Waits for UM server to be ready (max 30s)
  - Creates interfaces idempotently (NSP, NSPS, NHPS)
  - Supports configurable mTLS per interface
- **Service Configuration**: Exposes all ports (9000, 9200, 19100, 19443, 19001)
- **Ingress Configuration** (optional):
  - TLS passthrough to NHPS port (19001)
  - No TLS termination at ingress
  - Backend HTTPS protocol
- **Health Probes**: Use default NHP port (9000)

## Deployment

### Step 1: Create Namespace

```bash
kubectl create namespace integration
```

### Step 2: Create Image Pull Secret

Create a secret to pull images from the webMethods container registry:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=${WM_CR_SERVER} \
  --docker-username=${WM_CR_USERNAME} \
  --docker-password=${WM_CR_PASSWORD} \
  -n integration
```

Replace the environment variables with your actual credentials:
- `WM_CR_SERVER`: Container registry server (e.g., `ibmwebmethods.azurecr.io`)
- `WM_CR_USERNAME`: Your registry username
- `WM_CR_PASSWORD`: Your registry password

### Step 3: Customize Certificates (Optional)

Before deploying, you may want to customize the `certificates.yaml` file:

- **Ingress Hostname**: Update the ingress hostname in the `dnsNames` section if using a different domain:
  ```yaml
  dnsNames:
    - um.sttlab.local  # Change this to your domain
    - universalmessaging-0
    # ...
  ```

- **Multiple Replicas**: If using `replicaCount > 1`, add additional DNS names for each replica:
  ```yaml
  dnsNames:
    - um.sttlab.local # Change this to your domain
    - universalmessaging-0
    - universalmessaging-0.integration.svc.cluster.local
    - universalmessaging-1  # Add for replica 1
    - universalmessaging-1.integration.svc.cluster.local
  ```

### Step 4: Apply Certificate Keystore Password Secrets

```bash
kubectl apply -f secrets.yaml -n integration
```

This creates the password secrets that cert-manager will use when generating keystores.

### Step 5: Apply Certificates

```bash
kubectl apply -f certificates.yaml -n integration
```

Wait for certificates to be ready:
```bash
kubectl get certificates -n integration -w
```

You should see:
```
NAME                     READY   SECRET                         AGE
iwhi-root-ca             True    iwhi-root-ca-secret            10s
universalmessaging-tls   True    universalmessaging-tls-certs   10s
```

Verify the secret contains JKS files:
```bash
kubectl describe secret universalmessaging-tls-certs -n integration
```

You should see (size of these file might differ):
```
Data
====
ca.crt:          1704 bytes
keystore.jks:    3891 bytes
tls.crt:         1704 bytes
tls.key:         3243 bytes
truststore.jks:  1373 bytes
```

### Step 6: Customize values.yaml (Optional)

Before deploying, you may want to customize the `values.yaml` file:

- **mTLS Configuration**: Enable or disable client certificate authentication:
  ```yaml
  extraEnvs:
    NSPS_CLIENT_CERT_REQUIRED: "true"   # Require client certs for NSPS
    NHPS_CLIENT_CERT_REQUIRED: "false"  # Allow connections without client certs for NHPS
  ```

- **Ingress**: Enable ingress for external access via TLS passthrough:
  ```yaml
  ingress:
    enabled: true
    defaultHostname: um.yourdomain.com  # Must match certificate dnsNames
  ```

  **IMPORTANT**: With TLS passthrough, the ingress hostname must be included in the certificate's Subject Alternative Names (SANs). See certificates.yaml.

- **Image Repository**: If using a different container registry, update:
  ```yaml
  image:
    repository: your-registry.com/universalmessaging-server
    tag: "11.1.3"
  ```

- **Resource Limits**: Adjust CPU and memory based on your requirements:
  ```yaml
  resources:
    limits:
      cpu: 2
      memory: 4Gi
    requests:
      cpu: 500m
      memory: 2Gi
  ```

### Step 7: Install Universal Messaging

```bash
helm install universalmessaging ../../helm -f values.yaml -n integration
```

Or if using the webMethods Helm repository:
```bash
helm install universalmessaging webmethods/universalmessaging -f values.yaml -n integration
```

### Step 8: Wait for Pods

```bash
kubectl get pods -n integration -w
```

The pod should reach `1/1 Running` status:
```
NAME                   READY   STATUS    RESTARTS   AGE
universalmessaging-0   1/1     Running   0          2m
```

### Step 9: Verify Interfaces

Check the pod logs to verify the startup script execution and interface creation:

```bash
kubectl logs universalmessaging-0 -n integration | grep -A 10 "Universal Messaging Startup Initialization"
```

You should see:
```
===================================================================
Universal Messaging Startup Initialization
===================================================================
Waiting for UM server to be ready...
UM server is ready!
===================================================================
Configuring Universal Messaging Interfaces
===================================================================
-------------------------------------------------------------------
Configuring NSP (Socket) interface on port 19100...
NSP interface on port 19100 already exists, skipping
-------------------------------------------------------------------
Configuring NSPS (SSL Socket) interface on port 19443...
  Client Certificate Required: false
NSPS interface created successfully
-------------------------------------------------------------------
Configuring NHPS (HTTPS) interface on port 19001...
  Client Certificate Required: false
NHPS interface created successfully
===================================================================
```

List all interfaces:
```bash
kubectl exec universalmessaging-0 -n integration -- runUMTool.sh ListInterfaces -rname=nsp://localhost:9000
```

Expected output:
```
name=nsp0, protocol=nsp, port=19100, adapter=0.0.0.0, status=Running
name=nhp0, protocol=nhp, port=9000, adapter=0.0.0.0, status=Running
name=nhps0, protocol=nhps, port=19001, adapter=0.0.0.0, status=Running
name=nsps0, protocol=nsps, port=19443, adapter=0.0.0.0, status=Running
```

### Step 10: Verify Service Exposure

Check that all ports are exposed via the Kubernetes Service:

```bash
kubectl get svc universalmessaging-0 -n integration
```

Expected output:
```
NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                           AGE
universalmessaging-0   ClusterIP   192.168.x.x     <none>        9000/TCP,9200/TCP,19100/TCP,19443/TCP,19001/TCP   5m
```

### Step 11: Test Connectivity (Optional)

Port-forward to test the interfaces:

```bash
# NHP (non-TLS HTTP) - for health checks
kubectl port-forward universalmessaging-0 9000:9000 -n integration
curl http://localhost:9000/health/

# NHPS (HTTPS with TLS)
kubectl port-forward universalmessaging-0 19001:19001 -n integration
curl -k https://localhost:19001/health/
```
Note: this would usually return an empty server response.

### Step 12: Access via Ingress (Optional)

If ingress is enabled, access UM via the configured hostname:

```
https://um.sttlab.local/health/
```

**Note**: With TLS passthrough, the TLS connection goes directly to the UM server. The certificate presented will be the one managed by cert-manager.

## Architecture

### TLS Communication Flow

1. **Internal Cluster Access**:
   - Services can connect to any port via the ClusterIP service
   - TLS verification uses the CA certificate from cert-manager

2. **External Access via Ingress** (if enabled):
   - TLS passthrough: Client → Ingress (passthrough) → NHPS:19001
   - No TLS termination at ingress
   - UM server presents certificate directly to client

3. **Health Probes**:
   - Kubernetes probes use NHP port 9000 (non-TLS)
   - Internal HTTP health endpoint

### Port Summary

| Interface | Port | Protocol | TLS | mTLS | Exposed via Service | Ingress Support |
|-----------|------|----------|-----|------|---------------------|-----------------|
| NHP | 9000 | HTTP | ❌ | ❌ | ✅ | ❌ (health probes only) |
| Metrics | 9200 | HTTP | ❌ | ❌ | ✅ | ❌ |
| NSP | 19100 | TCP Socket | ❌ | ❌ | ✅ | ❌ |
| NSPS | 19443 | TCP Socket | ✅ | Configurable | ✅ | ❌ (TCP not supported) |
| NHPS | 19001 | HTTPS | ✅ | Configurable | ✅ | ✅ (TLS passthrough) |

### Startup Script Features

The `startup.sh` script (mounted via ConfigMap) provides:

1. **Server Readiness Check**: Waits up to 30 seconds for UM server to be ready
2. **Idempotent Interface Creation**: Checks if interface exists before creating
3. **Configurable mTLS**: Uses environment variables for client certificate requirements
4. **Error Handling**: Continues on failure with warning messages
5. **Logging**: Detailed output for troubleshooting

## Certificate Management

### How cert-manager Works

1. **Certificate Request**: The Certificate resource requests a certificate from cert-manager
2. **Issuer Validation**: cert-manager validates the request with the configured Issuer
3. **Private Key Generation**: cert-manager generates a private key
4. **Certificate Signing**: The certificate is signed by the CA Issuer
5. **Keystore Creation**: cert-manager automatically creates JKS keystores from the certificate
6. **Secret Creation**: All artifacts are stored in the Kubernetes Secret:
   - `tls.crt`: PEM certificate
   - `tls.key`: PEM private key
   - `ca.crt`: PEM CA certificate
   - `keystore.jks`: Java KeyStore with private key
   - `truststore.jks`: Java KeyStore with CA certificate
7. **Mount in Pod**: The Secret is mounted into the UM pod via `extraVolumes`/`extraVolumeMounts`
8. **Password Injection**: Passwords are injected as environment variables from Kubernetes secrets

### Certificate Renewal

cert-manager automatically renews certificates before they expire:
- **Duration**: 10 years (87600h) as configured
- **Renew Before**: 30 days (720h) before expiration
- **Automatic**: No manual intervention required

Monitor certificate status:
```bash
kubectl get certificate universalmessaging-tls -n integration -o jsonpath='{.status.renewalTime}'
```

## Mutual TLS (mTLS) Configuration

By default, the TLS interfaces (NSPS and NHPS) do **not** require client certificates. This allows clients to connect using server-side TLS only.

### Enable mTLS

To require client certificates, update the `values.yaml`:

```yaml
extraEnvs:
  NSPS_CLIENT_CERT_REQUIRED: "true"   # Require client certs for NSPS
  NHPS_CLIENT_CERT_REQUIRED: "true"   # Require client certs for NHPS
```

Then delete the interfaces and restart the pod to recreate them with the new configuration:

```bash
# Delete existing interfaces
kubectl exec universalmessaging-0 -n integration -- runUMTool.sh DeleteInterface -rname=nsp://localhost:9000 -interface=nsps0
kubectl exec universalmessaging-0 -n integration -- runUMTool.sh DeleteInterface -rname=nsp://localhost:9000 -interface=nhps0

# Restart the pod
kubectl delete pod universalmessaging-0 -n integration

# The startup script will recreate interfaces with mTLS enabled
```

### Client Certificate Requirements

When mTLS is enabled (`clientcertrequired=true`):
- Clients must present a valid certificate signed by a trusted CA
- The truststore on the UM server determines which CAs are trusted
- Client connections without a valid certificate will be rejected

When mTLS is disabled (`clientcertrequired=false`):
- Server presents its certificate to clients
- Server authenticates clients via other means (username/password, etc.)
- Clients can verify server certificate but don't need to present their own

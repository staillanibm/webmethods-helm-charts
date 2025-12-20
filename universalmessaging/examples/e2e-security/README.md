# Universal Messaging with cert-manager SSL Certificates

This example demonstrates how to deploy Universal Messaging with automated SSL certificate management using cert-manager.

## Overview

This configuration provides SSL support for all Universal Messaging interfaces:
- **NSP (9000)**: Native Socket Protocol
- **NSPS (9001)**: Native Socket Protocol over SSL
- **NHP (19000)**: Native HTTP Protocol
- **NHPS (19001)**: Native HTTP Protocol over SSL

Certificate management is fully automated through cert-manager, which:
- Generates JKS keystores and truststores automatically
- Handles certificate renewals before expiration
- Stores certificates securely in Kubernetes Secrets

## Prerequisites

### 1. Kubernetes Cluster
- Kubernetes v1.19 or later
- kubectl configured with cluster access

### 2. Helm 3
```bash
helm version
```

### 3. cert-manager v1.15+
cert-manager v1.15 or later is required for JKS keystore support.

Install cert-manager:
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

### 4. Container Registry Access
You need credentials to pull webMethods images from the IBM container registry.

## Files

### 1. certificates.yaml
Defines cert-manager resources:
- **Self-signed Issuer**: Bootstraps the certificate chain
- **UM Root CA**: Organization root certificate authority
- **CA Issuer**: Issues certificates signed by the root CA
- **UM Server Certificate**: Generates JKS keystore and truststore with proper DNS names and IPs

### 2. secrets.yaml
Contains password secrets for the keystores:
- **um-keystore-password**: Password for keystore.jks (default: `changeit`)
- **um-truststore-password**: Password for truststore.jks (default: `changeit`)

**IMPORTANT**: In production, use strong passwords and consider external secret management:
- Kubernetes External Secrets Operator
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault

### 3. values.yaml (to be created)
Example Helm values file for deploying with cert-manager.

## Deployment Steps

### Step 1: Create Namespace

```bash
kubectl create namespace obstest
```

### Step 2: Create Image Pull Secret

Create a secret to pull images from the webMethods container registry:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=ibmwebmethods.azurecr.io \
  --docker-username=<your-username> \
  --docker-password=<your-password> \
  -n obstest
```

### Step 3: Apply Password Secrets

```bash
kubectl apply -f secrets.yaml -n obstest
```

This creates the password secrets that cert-manager will use when generating keystores.

### Step 4: Apply Certificates

```bash
kubectl apply -f certificates.yaml -n obstest
```

Wait for certificates to be ready:
```bash
kubectl get certificates -n obstest -w
```

You should see:
```
NAME                      READY   SECRET                         AGE
um-root-ca                True    um-root-ca-secret              10s
universalmessaging-tls    True    universalmessaging-ssl-certs   10s
```

Verify the secret contains JKS files:
```bash
kubectl describe secret universalmessaging-ssl-certs -n obstest
```

You should see:
```
Data
====
ca.crt:          1704 bytes
keystore.jks:    3891 bytes
tls.crt:         1704 bytes
tls.key:         3243 bytes
truststore.jks:  1373 bytes
```

### Step 5: Create Helm Values File

Create a `values.yaml` file to enable cert-manager:

```yaml
ssl:
  useCertManager: true
  keystorePasswordSecret: "um-keystore-password"
  truststorePasswordSecret: "um-truststore-password"

# Update SSL environment variables to reference cert-manager secrets
extraEnvs:
  SSL_KEYSTORE: "/opt/softwareag/common/conf/keystore.jks"
  SSL_KEYSTORE_PASS: "changeit"
  SSL_TRUSTSTORE: "/opt/softwareag/common/conf/truststore.jks"
  SSL_TRUSTSTORE_PASS: "changeit"
```

### Step 6: Install Universal Messaging

```bash
helm install universalmessaging ../../helm -f values.yaml -n obstest
```

Or using a Helm repository:
```bash
helm repo add webmethods https://ibm.github.io/webmethods-helm-charts/charts
helm repo update
helm install universalmessaging webmethods/universalmessaging -f values.yaml -n obstest
```

### Step 7: Wait for Pods

```bash
kubectl get pods -n obstest -w
```

The pod should reach `1/1 Running` status:
```
NAME                     READY   STATUS    RESTARTS   AGE
universalmessaging-0     1/1     Running   0          2m
```

### Step 8: Verify Interfaces

Check the pod logs to verify all 4 interfaces are running:

```bash
kubectl logs universalmessaging-0 -n obstest | grep "Interfaces Running" -A 5
```

You should see:
```
Interfaces Running:
  0) nsp0: nsp://0.0.0.0:9000 Running
  1) nhps0: nhps://0.0.0.0:19001 Running
  2) nhp1: nhp://0.0.0.0:19000 Running
  3) nsps0: nsps://0.0.0.0:9001 Running
```

### Step 9: Test Connectivity

Port-forward to test the interfaces:

```bash
# NSP (non-SSL)
kubectl port-forward universalmessaging-0 9000:9000 -n obstest

# NHP (non-SSL HTTP)
kubectl port-forward universalmessaging-0 19000:19000 -n obstest

# Test health endpoint
curl http://localhost:19000/health/
```

## How cert-manager Works

1. **Certificate Request**: The Certificate resource requests a certificate from cert-manager
2. **Issuer Validation**: cert-manager validates the request with the configured Issuer (CA or self-signed)
3. **Private Key Generation**: cert-manager generates a private key
4. **Certificate Signing**: The certificate is signed by the Issuer
5. **Keystore Creation**: cert-manager automatically creates JKS keystores from the certificate
6. **Secret Creation**: All artifacts are stored in a Kubernetes Secret:
   - `tls.crt`: PEM certificate
   - `tls.key`: PEM private key
   - `ca.crt`: PEM CA certificate
   - `keystore.jks`: Java KeyStore with private key
   - `truststore.jks`: Java KeyStore with CA certificate
7. **Mount in Pod**: The Secret is mounted into the UM pod at `/opt/softwareag/common/conf/`

## Certificate Renewal

cert-manager automatically renews certificates before they expire:
- **Duration**: 10 years (87600h) as configured
- **Renew Before**: 30 days (720h) before expiration
- **Automatic**: No manual intervention required

Monitor certificate status:
```bash
kubectl get certificate universalmessaging-tls -n obstest -o jsonpath='{.status.renewalTime}'
```

## Customization

### DNS Names

Update the `dnsNames` section in [certificates.yaml](certificates.yaml) to match your environment:

```yaml
dnsNames:
  - universalmessaging-0
  - universalmessaging-0.your-namespace
  - universalmessaging-0.your-namespace.svc
  - universalmessaging-0.your-namespace.svc.cluster.local
  - your-custom-domain.com
```

### Multiple Replicas

If using `replicaCount > 1`, add additional DNS names for each replica:

```yaml
dnsNames:
  # Replica 0
  - universalmessaging-0
  - universalmessaging-0.obstest.svc.cluster.local
  # Replica 1
  - universalmessaging-1
  - universalmessaging-1.obstest.svc.cluster.local
  # Add more as needed
```

### Production CA

For production, replace the self-signed issuer with a trusted CA:

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

Then reference it in the Certificate:
```yaml
issuerRef:
  name: letsencrypt-prod
  kind: Issuer
```

## Troubleshooting

### Certificate Not Ready

Check certificate status:
```bash
kubectl describe certificate universalmessaging-tls -n obstest
```

Check cert-manager logs:
```bash
kubectl logs -n cert-manager deployment/cert-manager
```

### JKS Files Not Created

Verify cert-manager version is v1.15+:
```bash
kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}'
```

JKS keystore support was added in cert-manager v1.15.

### Pod Cannot Mount Secret

Verify secret exists:
```bash
kubectl get secret universalmessaging-ssl-certs -n obstest
```

Verify secret contains JKS files:
```bash
kubectl get secret universalmessaging-ssl-certs -n obstest -o jsonpath='{.data.keystore\.jks}' | base64 -d | file -
```

Should output: `Java KeyStore`

### Password Mismatch

Ensure the password in `secrets.yaml` matches the password used in values.yaml `SSL_KEYSTORE_PASS` and `SSL_TRUSTSTORE_PASS`.

## Cleanup

To remove the deployment:

```bash
helm uninstall universalmessaging -n obstest
kubectl delete -f certificates.yaml -n obstest
kubectl delete -f secrets.yaml -n obstest
kubectl delete namespace obstest
```

## Comparison: cert-manager vs Manual Keystores

| Feature | cert-manager | Manual Keystores |
|---------|-------------|------------------|
| **Certificate Generation** | Automatic | Manual with keytool |
| **Renewal** | Automatic before expiry | Manual intervention required |
| **Security** | Kubernetes-native secrets | Files in source control |
| **Multiple Environments** | Easy to replicate | Copy files manually |
| **Production Ready** | Yes, with CA integration | Requires CA process |
| **DNS Names** | Configured in Certificate | Hardcoded in certificate |
| **Complexity** | Initial setup required | Simple for dev/test |

## Best Practices

1. **Production**: Always use cert-manager with a trusted CA issuer
2. **Secrets**: Never commit password secrets to source control in production
3. **RBAC**: Limit access to certificate secrets using Kubernetes RBAC
4. **Monitoring**: Set up alerts for certificate expiry (though renewal is automatic)
5. **Backup**: Back up the root CA secret for disaster recovery
6. **Testing**: Test certificate renewal by setting short durations in dev/test

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [cert-manager JKS Keystores](https://cert-manager.io/docs/reference/api-docs/#cert-manager.io/v1.JKSKeystore)
- [Universal Messaging SSL Configuration](https://www.ibm.com/docs/en/webmethods-integration/wm-universal-messaging/11.1.0)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

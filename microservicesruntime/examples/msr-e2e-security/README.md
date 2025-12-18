# MSR End-to-End Security Example

This example demonstrates a complete end-to-end security setup for webMethods Microservices Runtime (MSR) including:

- Secure admin port (5543) with custom TLS certificate
- Secure custom port (api port - 6643) with custom TLS certificate, with TLS termination at Ingress level
- Integration with Universal Messaging over secure TLS connection
- Integration with Apache Kafka (Event Streams) over secure TLS connection

## Architecture

```
Internet
  │
  ├─> Ingress (nginx) ──[TLS Termination]──> MSR Admin Port (5543 HTTPS)
  │                                            └─> Keystore: admin-port-tls
  │
  └─> Ingress (nginx) ──[TLS Termination]──> MSR API Port (6643 HTTPS)
                                                └─> Keystore: api-port-tls

MSR Integrations:
  ├─> Universal Messaging (nsps://... over TLS)
  │    └─> Truststore: um-nhps-tls
  │
  └─> Apache Kafka / Event Streams (TLS)
       └─> Truststore: event-streams-tls
```

## Prerequisites

1. **Kubernetes cluster** with:
   - cert-manager installed and configured
   - nginx-ingress-controller installed
   - A ClusterIssuer named `selfsigned-issuer` (or update certificates.yaml)

2. **External services**:
   - Universal Messaging server with TLS enabled
   - Apache Kafka / Event Streams with TLS enabled

3. **TLS certificates**:
   - UM truststore certificate (JKS format)
   - Kafka/Event Streams certificate (PKCS12 format used here, but JKS also possible)

## Setup Instructions

### 1. Create the Universal Messaging truststore secret

```bash
kubectl create secret generic um-nhps-tls \
  --from-file=truststore.jks=path/to/um-truststore.jks \
  --namespace=your-namespace
```

### 2. Update and apply secrets

Edit `secrets.yaml` and replace placeholder values:
- MSR admin password
- UM connection details (URL, username, password)
- Kafka connection details (bootstrap URL, username, password)
- Base64-encoded Kafka certificate

```bash
# Encode your Kafka certificate
base64 -i your-kafka-cert.p12 | tr -d '\n'

# Apply secrets
kubectl apply -f secrets.yaml -n your-namespace
```

### 3. Apply cert-manager certificates

This creates JKS keystores for both admin and API ports:

```bash
kubectl apply -f certificates.yaml -n your-namespace
```

Wait for certificates to be ready:

```bash
kubectl get certificate -n your-namespace
```

### 4. Deploy MSR with Helm

```bash
helm install msr ../../helm \
  -f values.yaml \
  -n your-namespace
```

## Configuration Details

### TLS Certificates (cert-manager)

Two certificates are automatically created with JKS keystores:

1. **admin-port-tls**: For admin port (5543)
   - Keystore alias: `ssos`
   - Mounted at: `/opt/softwareag/common/conf/keystore.jks`

2. **api-port-tls**: For API port (6643)
   - Keystore alias: `api-port-tls`
   - Mounted at: `/certs/api-port/keystore.jks`

### Extra Services

An additional ClusterIP service exposes the API port:

```yaml
extraServices:
  - name: api-port
    type: ClusterIP
    ports:
      - port: 6643
        targetPort: api-port
```

### Extra Ingresses

A dedicated ingress with TLS termination

```yaml
extraIngresses:
  - name: api-port
    enabled: true
    tlsMode: termination
    backendCaSecret: api-port-tls  # Validates backend certificate
```

### Integration Server Configuration

The `values.yaml` configures:

- **Keystores**: DEFAULT_IS_KEYSTORE (admin), API_PORT_KEYSTORE (API)
- **Truststores**: UM_TRUSTSTORE, ES_TRUSTSTORE
- **JNDI**: Connection to Universal Messaging
- **JMS**: JMS connection with automatic UM admin object creation
- **Messaging**: UM messaging connection with CSQ disabled


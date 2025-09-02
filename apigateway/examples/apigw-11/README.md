# API Gateway 11.x sample configuration

Use the values.yaml file to run a API Gateway Minimal 11.x version. Note that for version 11.x, no license keys are required. Please also check the documentation at: https://www.ibm.com/docs/en/wam/wm-api-gateway/11.1.0.

```
image:
  tag: "11.1"

appVersion: "11.1"

apigw:
  isHomeDir: /opt/softwareag/IntegrationServer

# License Key is not required for 11.x
skipLicenseKey: "true"

elasticsearch:
  version: "8.17.3"

kibana:
  version: "8.17.3"

```
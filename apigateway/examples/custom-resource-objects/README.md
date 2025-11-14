# Deploying Custom Resource Objects

If your Kubernetes has an own Custom Resource Definition (CRD), you can create objects in `values.yaml` during the deployment. For example, you have the Citrix ADC with CRD `rewritepolicy`, you can create an object with using `customResourceObjects` ...

```
...
customResourceObjects:
- apiVersion: citrix.com/v1
  kind: rewritepolicy
  metadata:
   name: "{{ include \"common.names.fullname\" . }}-rewrite-query-wsdl"
  spec:
   rewrite-policies:
     - servicenames:
         - "{{ include \"common.names.fullname\" . }}-rt"
       rewrite-policy:
         operation: replace
         target: http.req.url
...
```
Each `customResourceObjects` member will be generated (including `tpl` function) as an object ...

```
...
---
# Source: apigateway/templates/cro.yaml
apiVersion: citrix.com/v1
kind: rewritepolicy
metadata:
  name: 'apigw-default-apigateway-rewrite-query-wsdl'
spec:
  rewrite-policies:
  - servicenames:
    - 'apigw-default-apigateway-rt'
    rewrite-policy:
      operation: replace
      target: http.req.url
...
```
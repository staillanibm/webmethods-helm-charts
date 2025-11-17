# Schedule a Deployment Restart

Add folloging values in your `values.yaml` to schedule a restart of the MSR deployment ...

* Create a Service Account with changing the defaults ...

```
...
serviceAccount:
  create: true
...
```

* Add a Cron Job in `jobs` ...

```
# Schedule a restart
jobs:
- name: restart-deployment
  image:
    repository: bitnami/kubectl
    tag: latest
  imagePullPolicy: IfNotPresent
  restartPolicy: Never
  successfulJobsHistoryLimit: 1
  extraSpec:
    backoffLimit: 0
  serviceAccount:
    name: "{{ include \"common.names.serviceAccountName\" . }}"
  # -- Schedule job every week on Monday ...
  schedule: "0 2 * * 0"
  command: ["/bin/sh"] 
  args:
    - -c
    - >-
        echo Restart [${DEPLOYMENT}] ... &&
        kubectl rollout restart deployment/${DEPLOYMENT}
```

Add Role and Role Binding objects as `customResourceObjects` to allow the `kubectl` execute the command ...

```
customResourceObjects:
# Allow getting status and patching only the one deployment you want to restart
- apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    name: "{{ include \"common.names.fullname\" . }}-deployment-restart"
  rules:
    - apiGroups: ["apps", "extensions"]
      resources: ["deployments"]
      resourceNames: ["msr-sam-microservicesruntime"]
      verbs: ["get", "patch", "list", "watch"]

# Bind the role to the service account
- apiVersion: rbac.authorization.k8s.io/v1
  kind: RoleBinding
  metadata:
    name: "{{ include \"common.names.fullname\" . }}-deployment-restart"
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: Role
    name: "{{ include \"common.names.fullname\" . }}-deployment-restart"
  subjects:
    - kind: ServiceAccount
      name: "{{ include \"common.names.serviceAccountName\" . }}"
      namespace: "{{ include \"common.names.namespace\" . }}"
```
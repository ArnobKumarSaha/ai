---
name: helm-chart-creator
description: >
  Create a new Helm chart for specified Kubernetes resources.
  Use this skill when the user says "create a helm chart for ...", "make a helm chart with ...",
  "new helm chart for ...", or lists K8s resource types they want in a chart
  (e.g. "serviceaccount & configmap", "deployment and service", "cronjob yaml").
  Triggers on: "helm chart", "create chart", "new chart", chart + any K8s resource name.
---

# Helm Chart Creator

Creates a Helm chart scaffold in `~/yamls/<chart-name>/`, generates templates only for the
requested K8s resources, and wires all configurable fields into `values.yaml`.

## Prerequisites

- `helm` must be available in PATH.

## Workflow

### Step 1: Parse the request

Extract from the user's message:
- **chart name**: use a short kebab-case name derived from the resource list, or whatever
  the user specifies (e.g. "sa-configmap", "my-app"). Default to `my-chart` if unclear.
- **resource list**: the K8s kinds requested (ServiceAccount, ConfigMap, Deployment,
  Service, Secret, Ingress, CronJob, Job, PersistentVolumeClaim, Role, RoleBinding,
  ClusterRole, ClusterRoleBinding, HorizontalPodAutoscaler, etc.)

If the chart name or resource list is ambiguous, ask before proceeding.

### Step 2: Create the chart

```bash
cd ~/yamls
helm create <chart-name>
```

### Step 3: Clean up default scaffolding

Remove everything helm generates that we don't need. Delete `_helpers.tpl` and `values.yaml`
so they can be written fresh (avoids Read-before-Write requirement).

```bash
CHART=~/yamls/<chart-name>

# Remove all default templates (including any extras helm may generate like httproute.yaml)
rm -f "$CHART/templates/"*.yaml "$CHART/templates/"*.txt
rm -rf "$CHART/templates/tests"

# Remove values.yaml and _helpers.tpl so they can be created fresh
rm -f "$CHART/values.yaml" "$CHART/templates/_helpers.tpl"
```

### Step 4: Write `_helpers.tpl`

Only the fullname helper — no labels helper.

```yaml
{{- define "<chart-name>.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
```

### Step 5: Generate templates

For each requested resource, create `templates/<kind>.yaml` using the patterns below.
**No labels or annotations** in any `metadata` section.
Gate every resource with an `enabled` flag from values.

#### ServiceAccount

```yaml
{{- if .Values.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
{{- end }}
```

#### ConfigMap

```yaml
{{- if .Values.configMap.create }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
data:
  {{- toYaml .Values.configMap.data | nindent 2 }}
{{- end }}
```

#### Secret

```yaml
{{- if .Values.secret.create }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
type: {{ .Values.secret.type | default "Opaque" }}
data:
  {{- toYaml .Values.secret.data | nindent 2 }}
{{- end }}
```

#### Deployment

Selector and pod template labels are required for K8s — use a minimal inline label only there.

```yaml
{{- if .Values.deployment.create }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  replicas: {{ .Values.deployment.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "<chart-name>.fullname" . }}
  template:
    metadata:
      labels:
        app: {{ include "<chart-name>.fullname" . }}
    spec:
      {{- if .Values.serviceAccount.create }}
      serviceAccountName: {{ include "<chart-name>.fullname" . }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.deployment.image.repository }}:{{ .Values.deployment.image.tag }}"
          imagePullPolicy: {{ .Values.deployment.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.deployment.containerPort }}
          {{- with .Values.deployment.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
{{- end }}
```

#### Service

```yaml
{{- if .Values.service.create }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
  selector:
    app: {{ include "<chart-name>.fullname" . }}
{{- end }}
```

#### Role

```yaml
{{- if .Values.role.create }}
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
rules:
  {{- toYaml .Values.role.rules | nindent 2 }}
{{- end }}
```

#### RoleBinding

```yaml
{{- if .Values.roleBinding.create }}
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "<chart-name>.fullname" . }}
subjects:
  - kind: ServiceAccount
    name: {{ include "<chart-name>.fullname" . }}
    namespace: {{ .Release.Namespace }}
{{- end }}
```

#### ClusterRole

```yaml
{{- if .Values.clusterRole.create }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ include "<chart-name>.fullname" . }}
rules:
  {{- toYaml .Values.clusterRole.rules | nindent 2 }}
{{- end }}
```

#### ClusterRoleBinding

```yaml
{{- if .Values.clusterRoleBinding.create }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "<chart-name>.fullname" . }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "<chart-name>.fullname" . }}
subjects:
  - kind: ServiceAccount
    name: {{ include "<chart-name>.fullname" . }}
    namespace: {{ .Values.clusterRoleBinding.subjectNamespace | default "default" }}
{{- end }}
```

#### CronJob

```yaml
{{- if .Values.cronJob.create }}
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  schedule: {{ .Values.cronJob.schedule | quote }}
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: {{ .Values.cronJob.restartPolicy | default "OnFailure" }}
          containers:
            - name: {{ .Chart.Name }}
              image: "{{ .Values.cronJob.image.repository }}:{{ .Values.cronJob.image.tag }}"
              imagePullPolicy: {{ .Values.cronJob.image.pullPolicy }}
              {{- with .Values.cronJob.command }}
              command:
                {{- toYaml . | nindent 16 }}
              {{- end }}
{{- end }}
```

#### PersistentVolumeClaim

```yaml
{{- if .Values.pvc.create }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "<chart-name>.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  accessModes:
    {{- toYaml .Values.pvc.accessModes | nindent 4 }}
  resources:
    requests:
      storage: {{ .Values.pvc.storage }}
  {{- with .Values.pvc.storageClassName }}
  storageClassName: {{ . }}
  {{- end }}
{{- end }}
```

### Step 6: Write `values.yaml`

Only include sections for the resources that were requested. Use sensible defaults.
No `annotations` fields.

Example for a ServiceAccount + ConfigMap chart:

```yaml
serviceAccount:
  create: true

configMap:
  create: true
  data:
    key: value
```

Example for a Deployment + Service + ServiceAccount chart:

```yaml
serviceAccount:
  create: true

deployment:
  create: true
  replicaCount: 1
  image:
    repository: nginx
    tag: latest
    pullPolicy: IfNotPresent
  containerPort: 80
  resources: {}

service:
  create: true
  type: ClusterIP
  port: 80
  targetPort: 80
```

### Step 7: Validate the chart

```bash
helm lint ~/yamls/<chart-name>
helm template ~/yamls/<chart-name> | head -60
```

If lint fails, fix the errors before reporting done.

### Step 8: Report to user

Show:
- Chart path
- Files created (templates + values.yaml)
- A sample `helm install` command

## Rules

- **No labels or annotations** in any `metadata` section. Exception: Deployment/Service
  require `app: <fullname>` in `spec.selector` and `spec.template.metadata.labels` only.
- **Only generate templates for requested resources** — no extras.
- **values.yaml must only contain keys used in templates** — no dead values, no `annotations`.
- **Every resource must have an `enabled`/`create` gate** in values.
- **No comments** in generated YAML unless logic is non-obvious.
- **Always run `helm lint`** before reporting done. Fix any errors.
- If the user provides a chart name explicitly, use it exactly.

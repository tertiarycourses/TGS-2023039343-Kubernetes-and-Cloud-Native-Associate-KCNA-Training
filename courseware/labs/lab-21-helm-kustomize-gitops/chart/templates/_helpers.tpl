{{/*
Lab 21 — chart helpers.

Files whose name starts with an underscore are NOT rendered into Kubernetes
objects. They exist to define named templates that other templates include.
This is how a chart avoids repeating the same label block six times.
*/}}

{{/*
Chart name, overridable. `trunc 63 | trimSuffix "-"` is not decoration: 63 is
the maximum length of a Kubernetes label value and of a DNS-1123 label, and a
name may not end in a hyphen.
*/}}
{{- define "tracklane.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified name: <release>-<chart>, collapsed to <release> when the
release name already contains the chart name. This is the standard Helm
idiom and is why `helm install tracklane ./chart` yields `tracklane` rather
than `tracklane-tracklane`.
*/}}
{{- define "tracklane.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart identifier for the helm.sh/chart label: "<name>-<version>" with any "+"
replaced, because "+" is not legal in a label value.
*/}}
{{- define "tracklane.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
SELECTOR labels. These go into Deployment.spec.selector.matchLabels, which is
IMMUTABLE after creation — so this set must stay minimal and must never
include anything that changes between releases (no version, no chart version).
Getting this wrong is the single most common cause of a chart that cannot be
upgraded in place.
*/}}
{{- define "tracklane.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tracklane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: web
{{- end -}}

{{/*
FULL labels: the selector labels plus descriptive metadata that is allowed to
change. Applied to metadata.labels, never to a selector.
*/}}
{{- define "tracklane.labels" -}}
helm.sh/chart: {{ include "tracklane.chart" . }}
{{ include "tracklane.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: tracklane
app.kubernetes.io/managed-by: {{ .Release.Service }}
tracklane.kallangfreight.sg/environment: {{ .Values.environment | quote }}
{{- end -}}

{{/*
Fail fast on values that must not be wrong. `required` and `fail` turn a
silent misconfiguration into a render-time error, which is exactly what you
want in CI.
*/}}
{{- define "tracklane.validateImage" -}}
{{- $tag := required "image.tag is required and must be pinned" .Values.image.tag -}}
{{- if eq $tag "latest" -}}
{{- fail "image.tag must not be 'latest' — pin an immutable tag or a digest" -}}
{{- end -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}

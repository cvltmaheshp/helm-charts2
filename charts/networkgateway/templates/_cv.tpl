{{/*
_cv.tpl is the same for all commvault components. Any change in this file should be copied to the _cv.tpl in all the components.
*/}}




{{- define "cv.image" }}
{{- $defaults := (fromYaml (.Files.Get "defaults.yaml")) }}
{{- $registry := (or (.Values.image).registry ((.Values.global).image).registry "")  }}
{{- if ne $registry "" -}}
{{- if ne (hasSuffix "/" $registry) true -}}
{{- $registry = print $registry "/" -}}
{{- end -}}
{{- end -}}
    {{- $registry }}
    {{- or (.Values.image).namespace ((.Values.global).image).namespace ($defaults.image).namespace }}/
    {{- or (.Values.image).repository ((.Values.global).image).repository ($defaults.image).repository }}:
    {{- required "image.tag or global.image.tag is required" (or (.Values.image).tag ((.Values.global).image).tag) }}
{{- end }}

{{- define "cv.metadataname" -}}
{{- if .Values.clientName -}}
 {{(.Values.global).appname}}{{ tpl .Values.clientName . | lower }}
{{- else -}}
{{- required "clientName is required" "" -}}
{{- end -}}
{{- end -}}

{{- define "cv.hostname" }}
{{- if .Values.clientHostName }}
{{- .Values.clientHostName }}
{{- else }}
{{- include "cv.metadataname" . }}.{{ or (.Values.global).namespace "default" }}.{{ or (.Values.global).clusterDomain "svc.cluster.local" }}
{{- end }}
{{- end -}}

{{- define "cv.imagePullSecret" }}
{{- if or (.Values.image).pullSecret ((.Values.global).image).pullSecret }}
      imagePullSecrets: 
      - name: {{(.Values.global).appname}}{{or (.Values.image).pullSecret ((.Values.global).image).pullSecret}}
{{- end }}
{{- end }}



{{/*
cv.deploymentannotations is a function that allows the user to specify deployment annotations
Use "deploymentannotations" as the section name. deploymentannotations can be specified at both global and local values
and will be merged to provide a single set of deployment annotations that will be added into the final deployment
*/}}
{{- define "cv.deploymentannotations" }}
{{- if or (.Values.global).deploymentannotations .Values.deploymentannotations }}
{{ "annotations:" | indent 2 -}}
{{- include "cv.utils.getCombinedYaml" (list .Values.deploymentannotations (.Values.global).deploymentannotations $ 4 true) }}
{{- end -}}
{{ end }}

{{/*
cv.serviceannotations is a function that allows the user to specify service annotations, e.g service.beta.kubernetes.io/azure-dns-label-name
Use "serviceannotations" as the section name. serviceannotations can be specified at both global and local values
and will be merged to provide a single set of service annotations that will be added into the final service specification
*/}}
{{- define "cv.serviceannotations" }}
{{- if or (.Values.global).serviceannotations .Values.serviceannotations }}
{{ "annotations:" | indent 2 -}}
{{- include "cv.utils.getCombinedYaml" (list .Values.serviceannotations (.Values.global).serviceannotations $ 4 true ) }}
{{- end -}}
{{ end }}


{{/*
cv.additionalPodspecs is a function that allows the user to specify additional pod specifications that are not mentioned in the deployment templates
Use "additionalPodspecs" as the section name to enter the additional pod specifications. pod specifications can be specified at both global and local values
and will be merged to provide a single set of additional pod specifications that will be added to the final deployment
There is also a provision to have chart level defaults which can be specified by having a defaults.yaml in chart directory.
Values in defaults.yaml gets the last priority
*/}}
{{- define "cv.additionalPodspecs" }}
{{- $defaults := (fromYaml (.Files.Get "defaults.yaml")) }}
{{- if or (.Values.global).additionalPodspecs .Values.additionalPodspecs $defaults.additionalPodspecs }}
{{- $combinedYaml := fromYaml ((include "cv.utils.getCombinedYaml" (list (.Values.global).additionalPodspecs $defaults.additionalPodspecs $ 6 false ))) }}
{{- include "cv.utils.getCombinedYaml" (list .Values.additionalPodspecs $combinedYaml $ 6 false ) }}
{{- end -}}
{{- end }}

{{/*
cv.commonContainerSpecs adds container specifications that are common for all commvault images
*/}}
{{- define "cv.commonContainerSpecs" }}
{{- if and (eq (include "cv.utils.isMinVersion" (list . 11 32)) "true") (ne (.Values.pause |default false) true) }}
        startupProbe:
            httpGet:
                path: /startupstatus
                port: 6688
                scheme: HTTP
            initialDelaySeconds: 2
            timeoutSeconds: 600
            periodSeconds: 2
            failureThreshold: 7
{{- end }}
{{- end }}

{{/*
cv.resources is a function that allows the user to specify pod resource requests and limits
Pod resource specifications can be specified at both global and local values
and will be merged to provide a single set of resource specification that will be added to the final deployment
There is also a provision to have chart level defaults which can be specified by having a defaults.yaml in chart directory.
Values in defaults.yaml gets the last priority
*/}}
{{- define "cv.resources" }}
{{- $defaults := (fromYaml (.Files.Get "defaults.yaml")) }}
{{- if or (.Values.global).resources .Values.resources $defaults.resources }}
{{ "resources:" | indent 8 -}}
{{- $combinedYaml := fromYaml ((include "cv.utils.getCombinedYaml" (list (.Values.global).resources $defaults.resources $ 10 false ))) }}
{{- include "cv.utils.getCombinedYaml" (list .Values.resources $combinedYaml $ 10 false ) }}
{{- end -}}
{{ end }}

{{/*
cv.commonenv creates environment variables that are common to all deployments
*/}}
{{- define "cv.commonenv" }}
{{- $statefulset := or .Values.statefulset .Values.global.statefulset }}
{{- $objectname := include "cv.metadataname" . }}
        {{- if $statefulset }}
        # client display name
        - name: CV_CLIENT_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: CV_CLIENT_HOSTNAME
          # pod ip will be used for statefulset
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: CV_IS_STATEFULSET  
          value: 'true'
        - name: CV_DNS_SUFFIX
          # dns suffix of the client
          value: {{ .Values.serviceName | default $objectname }}.{{ or (.Values.global).namespace "default" }}.{{ or (.Values.global).clusterDomain "svc.cluster.local" }}
        {{- else }}
        - name: CV_CLIENT_NAME
          # client display name
          value: {{ tpl .Values.clientName . }}
        - name: CV_CLIENT_HOSTNAME
          # hostname of the client should match the service name.
          value: {{ include "cv.hostname" . }}
        - name: CV_DNS_SUFFIX
          # dns suffix of the client
          value: {{ or (.Values.global).namespace "default" }}.{{ or (.Values.global).clusterDomain "svc.cluster.local" }}
        {{- end }}
        {{- if .Values.pause }}
        - name: CV_PAUSE
          value: 'true'
        {{- end }}
        - name: CV_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: CV_POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace   
{{- end -}}


{{/*
cv.commondeploymentpecs creates pod specifications that are common to all deployments
*/}}
{{- define "cv.commondeploymentspecs" }}
{{- $objectname := include "cv.metadataname" . }}
{{- $statefulset := or .Values.statefulset .Values.global.statefulset }}
  {{- if $statefulset }}
  serviceName: {{ .Values.serviceName | default $objectname }}
  {{- if .Values.replicas }}
  replicas: {{.Values.replicas}}
  {{- end }}
  updateStrategy:
    type: RollingUpdate
  {{- else }}
  replicas: 1  
  strategy:
    type: Recreate
  {{- end }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ $objectname }}
{{- end -}}


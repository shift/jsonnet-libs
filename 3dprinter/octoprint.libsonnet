(import 'ksonnet-util/kausal.libsonnet')
{

  _config+:: {
    namespace: 'octoprint',

    versions+:: {
      octoprint: '1.4.2',
    },

    imageRepos+:: {
      octoprint: 'shift/octoprint',
    },

    octoprint+:: {
      port: 5000,
      labels: {
        'app.kubernetes.io/name': 'octoprint',
        'app.kubernetes.io/version': $._config.versions.octoprint,
      },
      selectorLabels: {
        [labelName]: $._config.octoprint.labels[labelName]
        for labelName in std.objectFields($._config.octoprint.labels)
        if !std.setMember(labelName, ['app.kubernetes.io/version'])
      },
    },
  },
  octoprint+: {
    podSecurityPolicy:
      local policy = $.policy.v1beta1.podSecurityPolicy;

      policy.new() +
      policy.mixin.metadata.withName('psp-octoprint') +
      policy.mixin.metadata.withLabels({ app: 'octoprint' }) +
      policy.mixin.spec.withPrivileged(true) +
      policy.mixin.spec.withVolumes(['hostPath', 'configMap', 'emptyDir', 'projected', 'secret', 'downwardAPI', 'persistentVolumeClaim']) +
      policy.mixin.spec.withHostNetwork(false) +
      policy.mixin.spec.withHostIpc(false) +
      policy.mixin.spec.withHostPid(false) +
      policy.mixin.spec.runAsUser.withRule('RunAsAny') +
      policy.mixin.spec.seLinux.withRule('RunAsAny') +
      policy.mixin.spec.supplementalGroups.withRule('RunAsAny') +
      policy.mixin.spec.supplementalGroups.withRanges({ min: 0, max: 65535 }) +
      policy.mixin.spec.fsGroup.withRule('RunAsAny') +
      policy.mixin.spec.fsGroup.withRanges({ min: 0, max: 65535 }) +
      policy.mixin.spec.withReadOnlyRootFilesystem(false),

    clusterRoleBinding:
      local clusterRoleBinding = $.rbac.v1.clusterRoleBinding;

      clusterRoleBinding.new() +
      clusterRoleBinding.mixin.metadata.withName('octoprint') +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withName('octoprint') +
      clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
      clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'octoprint', namespace: $._config.namespace }]),

    clusterRole:
      local clusterRole = $.rbac.v1.clusterRole;
      local policyRule = clusterRole.rulesType;
      local podSecurityRole = policyRule.new() +
                              policyRule.withApiGroups(['extensions']) +
                              policyRule.withResourceNames(['psp-octoprint']) +
                              policyRule.withResources([
                                'podsecuritypolicies',
                              ]) +
                              policyRule.withVerbs(['use']);
      local rules = [podSecurityRole];

      clusterRole.new() +
      clusterRole.mixin.metadata.withName('octoprint') +
      clusterRole.withRules(rules),

    serviceAccount:
      local serviceAccount = $.core.v1.serviceAccount;

      serviceAccount.new('octoprint') +
      serviceAccount.mixin.metadata.withNamespace($._config.namespace),

    deployment:
      local container = $.apps.v1.deployment.mixin.spec.template.spec.containersType;
      local volume = $.apps.v1.deployment.mixin.spec.template.spec.volumesType;
      local containerPort = $.core.v1.containerPort;
      local containerVolumeMount = container.volumeMountsType;
      local podSelector = $.apps.v1.deployment.mixin.spec.template.spec.selectorType;
      local toleration = $.apps.v1.deployment.mixin.spec.template.spec.tolerationsType;
      local containerEnv = container.envType;

      local podLabels = $._config.octoprint.labels;
      local selectorLabels = $._config.octoprint.selectorLabels;

      local existsToleration = toleration.new() +
                               toleration.withOperator('Exists');

      local octoprint =
        $.core.v1.container.new(
          name='octoprint',
          image='shift/octoprint:' + $._config.versions.octoprint,
        ).withPorts(containerPort.new(name='http', port=$._config.octoprint.port)) +

        $.core.v1.container.mixin.securityContext.withPrivileged(true);
      //      local socat = $.core.v1.container.new(
      //                      name='socat',
      //                      image='shift/octoprint:' + $._config.versions.octoprint,
      //                    ).withCommand('/usr/bin/socat').withArgs(['-dddd', 'pty,link=/tmp/printer,waitslave,raw,user=root,group=dialout,mode=777', 'tcp:10.43.58.246:3333']) +
      //                    $.core.v1.container.mixin.securityContext.withPrivileged(true);

      local c = [octoprint];

      $.apps.v1.deployment.new(name='octoprint', replicas=1, containers=c) +
      $.apps.v1.deployment.mixin.metadata.withNamespace($._config.namespace) +
      $.apps.v1.deployment.mixin.metadata.withLabels(podLabels) +
      $.apps.v1.deployment.mixin.spec.selector.withMatchLabels(selectorLabels) +
      $.apps.v1.deployment.mixin.spec.template.metadata.withLabels(podLabels) +
      $.apps.v1.deployment.mixin.spec.template.spec.withTolerations([existsToleration]) +
      $.apps.v1.deployment.mixin.spec.template.spec.withNodeSelector({ 'kubernetes.io/hostname': 'khadas' }) +
      $.apps.v1.deployment.mixin.spec.template.spec.securityContext.withRunAsNonRoot(false) +
      $.apps.v1.deployment.mixin.spec.template.spec.securityContext.withRunAsUser(0) +
      $.apps.v1.deployment.mixin.spec.template.spec.withServiceAccountName('octoprint'),

    service:
      local service = $.core.v1.service;
      local servicePort = $.core.v1.service.mixin.spec.portsType;

      local octoprintPort = servicePort.newNamed('http', 5000, 'http');

      service.new('print', $.octoprint.deployment.spec.selector.matchLabels, octoprintPort) +
      service.mixin.metadata.withNamespace($._config.namespace) +
      service.mixin.metadata.withLabels({ app: 'octoprint' }),
  },
}

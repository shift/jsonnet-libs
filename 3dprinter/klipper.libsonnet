(import 'ksonnet-util/kausal.libsonnet')
{

  _config+:: {
    namespace: 'octoprint',

    versions+:: {
      klipper: 'bc904dd431eafb2593c6bbd9cb0ba735c74e2124',
    },

    imageRepos+:: {
      klipper: 'shift/klipper',
    },

    klipper+:: {
      port: 3333,
      labels: {
        'app.kubernetes.io/name': 'klipper',
        'app.kubernetes.io/version': $._config.versions.klipper,
      },
      selectorLabels: {
        [labelName]: $._config.klipper.labels[labelName]
        for labelName in std.objectFields($._config.klipper.labels)
        if !std.setMember(labelName, ['app.kubernetes.io/version'])
      },
    },
  },
  klipper+: {
    podSecurityPolicy:
      local policy = $.policy.v1beta1.podSecurityPolicy;

      policy.new() +
      policy.mixin.metadata.withName('psp-klipper') +
      policy.mixin.metadata.withLabels({ app: 'klipper' }) +
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
      clusterRoleBinding.mixin.metadata.withName('klipper') +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withName('klipper') +
      clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
      clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'klipper', namespace: $._config.namespace }]),

    clusterRole:
      local clusterRole = $.rbac.v1.clusterRole;
      local policyRule = clusterRole.rulesType;
      local podSecurityRole = policyRule.new() +
                              policyRule.withApiGroups(['extensions']) +
                              policyRule.withResourceNames(['psp-klipper']) +
                              policyRule.withResources([
                                'podsecuritypolicies',
                              ]) +
                              policyRule.withVerbs(['use']);
      local rules = [podSecurityRole];

      clusterRole.new() +
      clusterRole.mixin.metadata.withName('klipper') +
      clusterRole.withRules(rules),

    serviceAccount:
      local serviceAccount = $.core.v1.serviceAccount;

      serviceAccount.new('klipper') +
      serviceAccount.mixin.metadata.withNamespace($._config.namespace),

    klipper_cfg: $.core.v1.configMap.new(name='klipper-cfg')
                 + $.core.v1.configMap.withData({
                   'printer.cfg': importstr 'klipper/printer.cfg',
                   'printer_macros.cfg': importstr 'klipper/printer_macros.cfg',
                 }),
    deployment:
      local container = $.apps.v1.deployment.mixin.spec.template.spec.containersType;
      local volume = $.apps.v1.deployment.mixin.spec.template.spec.volumesType;
      local containerPort = $.core.v1.containerPort;
      local containerVolumeMount = container.volumeMountsType;
      local podSelector = $.apps.v1.deployment.mixin.spec.template.spec.selectorType;
      local toleration = $.apps.v1.deployment.mixin.spec.template.spec.tolerationsType;
      local containerEnv = container.envType;

      local podLabels = $._config.klipper.labels;
      local selectorLabels = $._config.klipper.selectorLabels;

      local existsToleration = toleration.new() +
                               toleration.withOperator('Exists');
      local devVolumeName = 'dev';
      local devVolume = volume.fromHostPath(devVolumeName, '/dev');
      local devVolumeMount = containerVolumeMount.new(devVolumeName, '/host/dev');

      local klipper =
        $.core.v1.container.new(
          name='klipper',
          image='shift/klipper:%s' % $._config.versions.klipper,
        ).withPorts(containerPort.new(name='ser2net', port=$._config.klipper.port)) +
        $.core.v1.container.mixin.securityContext.withPrivileged(true);
      //      local ser2net = $.core.v1.container.new(
      //                        name='ser2net',
      //                        image='shift/klipper:%s' % $._config.versions.klipper,
      //                      ).withCommand('/usr/sbin/ser2net').withArgs(['-d', '-u']).withPorts(containerPort.new(name='ser2net', port=$._config.klipper.port)) +
      //                      $.core.v1.container.mixin.securityContext.withPrivileged(true);
      local c = [klipper];

      $.apps.v1.deployment.new(name='klipper', replicas=1, containers=c) +
      $.apps.v1.deployment.mixin.metadata.withNamespace($._config.namespace) +
      $.apps.v1.deployment.mixin.metadata.withLabels(podLabels) +
      $.apps.v1.deployment.mixin.spec.selector.withMatchLabels(selectorLabels) +
      $.apps.v1.deployment.mixin.spec.template.metadata.withLabels(podLabels) +
      $.apps.v1.deployment.mixin.spec.template.spec.withTolerations([existsToleration]) +
      $.apps.v1.deployment.mixin.spec.template.spec.withNodeSelector({ 'kubernetes.io/hostname': 'khadas' }) +
      $.apps.v1.deployment.mixin.spec.template.spec.withVolumes([devVolume]) +
      $.apps.v1.deployment.mixin.spec.template.spec.securityContext.withRunAsNonRoot(true) +
      $.apps.v1.deployment.mixin.spec.template.spec.securityContext.withRunAsUser(65534) +
      $.apps.v1.deployment.mixin.spec.template.spec.withServiceAccountName('klipper') +
      $.util.configVolumeMount('klipper-cfg', '/opt') +
      $.util.hostVolumeMount('dev', '/dev', '/host/dev'),

    service:
      local service = $.core.v1.service;
      local servicePort = $.core.v1.service.mixin.spec.portsType;

      local klipperPort = servicePort.newNamed('ser2net', $._config.klipper.port, 'ser2net');

      service.new('klipper', $._config.klipper.selectorLabels, klipperPort) +
      service.mixin.metadata.withNamespace($._config.namespace) +
      service.mixin.metadata.withLabels($._config.klipper.labels),
  },
}

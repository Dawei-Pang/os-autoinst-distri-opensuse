{
  user: {
    fullName: 'Bernhard M. Wiedemann',
    password: '$6$vYbbuJ9WMriFxGHY$gQ7shLw9ZBsRcPgo6/8KmfDvQ/lCqxW8/WnMoLCoWGdHO6Touush1nhegYfdBbXRpsQuy/FTZZeg7gQL50IbA/',
    hashedPassword: true,
    userName: 'bernhard',
  },
  root: {
    password: '$6$vYbbuJ9WMriFxGHY$gQ7shLw9ZBsRcPgo6/8KmfDvQ/lCqxW8/WnMoLCoWGdHO6Touush1nhegYfdBbXRpsQuy/FTZZeg7gQL50IbA/',
    hashedPassword: true,
    sshPublicKey: 'enable ssh',
  },
  software: {
    patterns: ['sles_sap_HADB', 'sles_sap_HAAPP', 'sles_sap_DB', 'sles_sap_APP'],
  },
  product: {
    id: '{{AGAMA_PRODUCT_ID}}',
  },
  storage: {
    drives: [
      {
        search: '/dev/disk/by-id/{{OSDISK}}',
        partitions: [
          { search: '*', delete: true },
          { generate: 'default' },
        ],
      },
    ],
  },
  localization: {
    language: 'en_US.UTF-8',
    keyboard: 'us',
    timezone: 'Asia/Shanghai',
  },
  scripts: {
    post: [
      {
        name: 'enable root login',
        chroot: true,
        content: |||
          #!/usr/bin/env bash
          echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/root.conf
        |||,
      },
    ],
  },
}

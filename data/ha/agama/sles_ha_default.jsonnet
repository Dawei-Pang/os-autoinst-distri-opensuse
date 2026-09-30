{
  product: {
    id: '{{AGAMA_PRODUCT_ID}}',
    registrationCode: '{{SCC_REGCODE}}',
    addons: [
      {
        id: 'sle-ha',
        registrationCode: '{{SCC_REGCODE_HA}}',
      },
    ],
  },
  bootloader: {
    stopOnBootMenu: true,
  },
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
    patterns: {
      add: ['ha_sles'],
    },
    extraRepositories: [
      {
        alias: '8316HAWKAPI',
        url: 'http://dist.suse.de/ibs/SUSE:/SLFO:/1.2:/PullRequest:/8316:/SLES/product/repo/SLES-HA-16.0-x86_64/',
        name: '8316HAWKAPI',
        allowUnsigned: true,
        enabled: true,
      },
      {
        alias: '8318HAWK2',
        url: 'http://dist.suse.de/ibs/SUSE:/SLFO:/1.2:/PullRequest:/8318:/SLES/product/repo/SLES-HA-16.0-x86_64/',
        name: '8318HAWK2',
        allowUnsigned: true,
        enabled: true,
      },
    ],
  },
  questions: {
    policy: 'auto',
    answers: [
      {
        class: 'software.import_gpg',
        answer: 'Trust',
      },
    ],
  },
  scripts: {
    post: [
      {
        name: 'enable sshd',
        chroot: true,
        content: |||
          #!/usr/bin/env bash
          echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/root.conf
          systemctl enable sshd
        |||,
      },
    ],
  },
}

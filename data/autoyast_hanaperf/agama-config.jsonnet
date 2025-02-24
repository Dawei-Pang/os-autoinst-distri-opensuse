{
  "user": {
    "fullName": "Test",
    "password": "$6$vYbbuJ9WMriFxGHY$gQ7shLw9ZBsRcPgo6/8KmfDvQ/lCqxW8/WnMoLCoWGdHO6Touush1nhegYfdBbXRpsQuy/FTZZeg7gQL50IbA/",
    "hashedPassword": true,
    "userName": "test"
  },
  "root": {
    "password": "$6$vYbbuJ9WMriFxGHY$gQ7shLw9ZBsRcPgo6/8KmfDvQ/lCqxW8/WnMoLCoWGdHO6Touush1nhegYfdBbXRpsQuy/FTZZeg7gQL50IbA/",
    "hashedPassword": true
  },
  "software": {
    "patterns": []
  },
  product: {
    id: '{{AGAMA_PRODUCT_ID}}',
    registrationCode: '{{SCC_REGCODE_SLES4SAP}}'
  },
  "storage": {
    "drives": [
      {
        search: '/dev/disk/by-id/{{HANA_PERF_OS_DISK}}',
        "partitions": [
          { "search": "*", "delete": true },
          { "generate": "default" }
        ]
      }
    ]
  },  
  "network": {
    "connections": [
      {
        "id": "Wired Connection",
        "method4": "auto",
        "method6": "auto",
        "ignoreAutoDns": false,
        "status": "up"
      }
    ]
  },
  "localization": {
    "language": "en_US.UTF-8",
    "keyboard": "us",
    "timezone": "Asia/Shanghai"
  },
  scripts: {
    pre: [
      {
        name: 'wipefs',
        body: |||
          #!/usr/bin/env bash
          for i in `lsblk -n -l -o NAME -d -e 7,11,254`
              do wipefs -af /dev/$i
              sleep 1
              sync
          done
        |||
      }
    ],
    post: [
      {
        name: "enable root login",
        chroot: true,
        body: |||
          #!/usr/bin/env bash
          echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/root.conf
        |||
      }
    ]
  }
}

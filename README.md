# vsftp-rootless-podman
##The secure &amp; safe FTP server

###Decription
A rootless Podman deployment of vsftpd + MariaDB + PAM authentication, designed to provide FTPS-only access without running Podman or systemd services as root.

###Architecture
- rootless Podman
- a dedicated Podman pod
- vsftpd with implicit FTPS on TCP/990
- passive FTPS on TCP/21100-21110
- MariaDB as the virtual-user authentication database
- libpam-mysql for PAM authentication
- Podman secrets for passwords and the TLS private key
- per-user FTP directories
- systemd user services with loginctl enable-linger

                         Host
                          │
                  rootless systemd user
                          │
                    Podman pod
                          │
              ┌───────────┴───────────┐
              │                       │
        MariaDB container       vsftpd container
              │                       │
       ftp.ftp_users             PAM / libpam-mysql
              │                       │
              └──────── 127.0.0.1 ────┘

Both containers share the pod network namespace. MariaDB therefore listens only on 127.0.0.1:3306, and vsftpd reaches it through the same network namespace.

###How to add a new FTP user
- Login to container shell: `podman exec -i container-name /bin/bash`
- Login to MariaDB CLI: `mysql -D ftp -p`
- Execute the query: `INSERT INTO ftp_users(username, password_hash) VALUES ('new_ftp_username', paste ./hash_password.sh output here);

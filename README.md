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
- In the host's `ftp` folder, create the read-only (i.e. 0555) container-root-owned folder with the name of the user's login, and then create another folder `data` inside of it. The `data` folder must be owned by the `ftpuser` (9898 in the `Containerfile_vsftpd`). You may get the host-mapped ownership UID and GID values for your case, in the output of `make build` or `make directories` receipies.

###How to verify the TLS certificate
- If your FTP server's passive IP address (the one clients use to discover it on the Internet) is assigned a hostname (in `/etc/hosts`, for example), then you may fully validate the TLS certificate like this: `openssl s_client -connect 127.0.0.1:990 -servername ftp.your-ftp-host.com -CAfile cert/ca.crt`

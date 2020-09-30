# ocis traefik deployment scenario

## Overview
ocis running on a hcloud node behind traefik as reverse proxy
* Cloudflare DNS is resolving the domain
* Letsencrypt is providing a valid ssl certificate for the domain
* Traefik docker container terminates ssl and forwards https requests to ocis
* ocis docker container serves owncloud backend and delivers phoenix client

## Node

### Requirements
* Server running Ubuntu 20.04 is public availible with a static ip address
* A A-record for domain is pointing on the servers ip address
* Create user `$sudo adduser username`
* Add user to sudo group `$sudo usermod -aG sudo username`
* Add users pub key to `~/.ssh/authorized_keys`
* Setup sshd to forbid root access and permit authorisation only by ssh key
* Install docker `$sudo apt install docker.io`
* Add user to docker group `$sudo usermod -aG docker username`
* Install docker-compose via `$ sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose` (docker compose version 1.27.4 as of today)
* Make docker-compose executable `$ sudo chmod +x /usr/local/bin/docker-compose`
* Environment variables for OCIS Stack
  * `$ export OCIS_DOMAIN=your.domain.com`

### Stack
The application stack contains two containers. The first one is traefik which is terminating https requests and forwards the requests to the internal docker network. Additional, traefik is creating a certificate that is stored in `acme.json` in the folder `letsencrypt` of the users home directory.
The second one is ocis which is exposing the webservice on port 9200 to traefic.

### Config
Edit docker-compose.yml file to fit your domain setup
```
...
  traefik:
    image: "traefik:v2.2"
    ...
    labels:
      ...
      # Email address is neccesary for certificate creation
      - "--certificatesresolvers.ocisresolver.acme.email=username@${OCIS_DOMAIN}"
...
```

```
  ocis:
    container_name: ocis
    ...
    labels:
      ...
      # This is the domain for which traefik is creating the certificate from letsencrypt
      - "traefik.http.routers.ocis.rule=Host(`${OCIS_DOMAIN}`)"
      ...
```
A folder for letsencypt to store the certificate needs to be created
`$ mkdir ~/letsencrypt`
This folder is bind to the docker container and the certificate is persistently stored into it.

in this examnple, ssl shall be terminated from traefik and inside of the docker network, the services shall comunicate via http. For this `PROXY_TLS: "false"` as environment parameter for ocis has to be set.

For ocis to work properly it's neccesary to provide 2 config files.
Those files are delivered in the folder `config` of this repository which is bind into the ocis container.

Changes need to be done in identifier-registration.yml to match your domain

```
---
# OpenID Connect client registry.
clients:
  - id: phoenix
    name: OCIS
    application_type: web
    insecure: yes
    trusted: yes
    redirect_uris:
      - http://your.domain.com
      - http://your.domain.com/oidc-callback.html
      - https://your.domain.com/
      - https://your.domain.com/oidc-callback.html
    origins:
      - http://your.domain.com
      - https://your.domain.com
```
To provide the file to ocis container the following two lines are needed in the compose file. It's important that the ports match.
```
    ...
    volumes:
      - ./config:/etc/ocis
    environment:
      ...
      KONNECTD_IDENTIFIER_REGISTRATION_CONF: "/etc/ocis/identifier-registration.yml"
      ...
```
The second file is the proxy-config.json which configures the ocis internal service proxy. No changes in this setup are needed but the file needs to be provided as follows.
```
    ...
    volumes:
      - ./config:/etc/ocis
    environment:
      ...
      OCIS_CONFIG_FILE: "/etc/ocis/proxy-config.json"
      ...
```
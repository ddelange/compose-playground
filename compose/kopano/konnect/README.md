Setup the domain name in /etc/hosts - assuming you are on linux:

```
127.0.0.1 konnect.docker-playground.local
127.0.0.1 owncloud.docker-playground.local
```

Then use the following command to
start an ownCloud instance with a Kopano IDP:


```console
export KOPANO_KONNECT_DOMAIN=konnect.docker-playground.local
export OWNCLOUD_DOMAIN=owncloud.docker-playground.local
echo >> /etc/hosts 127.0.0.1 $KOPANO_KONNECT_DOMAIN
echo >> /etc/hosts 127.0.0.1 $OWNCLOUD_DOMAIN

docker system prune -f
docker volume prune -f

docker-compose \
    -f owncloud-base.yml \
    -f owncloud-official.yml \
    -f cache/redis.yml \
    -f database/mariadb.yml \
    -f ldap/openldap.yml \
    -f ldap/openldap-mount-ldif.yml \
    -f owncloud-exported-ports.yml \
    -f ldap/openldap-autoconfig-base.yml \
    -f kopano/konnect/docker-compose.yml \
    up
```

Then manually sync LDAP users

```
docker exec compose_owncloud_1 occ user:sync --missing-account-action=disable 'OCA\User_LDAP\User_Proxy'
docker exec compose_owncloud_1 occ app:list openidconnect
```

Confirm that the openidconnect app is enabled. If not, do

```
occ app:enable openidconnect
```

Go to owncloud: http://owncloud.docker-playground.local:9680
Click the alternative login button 'Kopano'
On the login of kopano konnect use aaliyah_abernathy / secret to login

Local administrator user: admin / admin

This is the well-known address to be used for OpenID Connect (must be available in the owncloud domain!):
https://konnect.docker-playground.local/.well-known/openid-configuration
https://owncloud.docker-playground.local/.well-known/openid-configuration


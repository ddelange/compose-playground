#!/bin/bash
#
# see also:
#  https://github.com/owncloud-docker/compose-playground/issues/6
#  https://github.com/owncloud-docker/compose-playground/pull/51 	pmaier-fixes
#  https://github.com/owncloud-docker/compose-playground/blob/master/compose/kopano/konnect/README.md
#  https://doc.owncloud.com/server/10.5/admin_manual/configuration/user/oidc/
#
# CAUTION: https://github.com/owncloud/openidconnect/ has a README.md
#		- some concepts there are correct, e.g. index.php/apps/openidconnect/config rewrite
#		- some other parts may need verification.
#
# 2020-10-16, jw@owncloud.com
# 2020-11-20, jw@owncloud.com
#

echo "Estimated setup time: 8 minutes ..."

vers=1.0.0RC5
oauth2_vers=0.4.4RC1
d_vers=$(echo $vers  | tr '[A-Z]' '[a-z]' | tr . -)-$(date +%Y%m%d)
source ./make_machine.sh -u openidconnect-$d_vers-test -p git,screen,docker.io,docker-compose

comp_yml=kopano/konnect/docker-compose.yml
reg_yml=kopano/konnect/konnectd-identifier-registration.yaml
openidconnect_url=https://github.com/owncloud/openidconnect/releases/download/v$vers/openidconnect-$vers.tar.gz
oauth2_url=https://github.com/owncloud/oauth2/releases/download/v$oauth2_vers/oauth2-$oauth2_vers.tar.gz

OWNCLOUD_RELEASE_DOCKER_TAG=10.5.0	# found on https://hub.docker.com/r/owncloud/server/tags/

## choose with or without version numbers and timestamps, in case we want multiple systems.
KOPANO_KONNECT_DOMAIN=konnect.oidc-$d_vers.jw-qa.owncloud.works
OWNCLOUD_DOMAIN=oc-10-5-0.oidc-$d_vers.jw-qa.owncloud.works
# KOPANO_KONNECT_DOMAIN=konnect.oidc-jw-qa.owncloud.works
# OWNCLOUD_DOMAIN=owncloud.oidc-jw-qa.owncloud.works

## if you cannot work with cloudflare, you may try an /etc/hosts setup using:
# KOPANO_KONNECT_DOMAIN=konnect.docker-playground.local
# OWNCLOUD_DOMAIN=owncloud.docker-playground.local

LOAD_SCRIPT << EOF
  git clone https://github.com/owncloud-docker/compose-playground.git
  cd compose-playground/compose
  # git checkout pmaier-fixes || true
  git branch -a

  # allow switch back and forth
  sed -i -e 's@OWNCLOUD_APPS_INSTALL=.*@OWNCLOUD_APPS_INSTALL=$openidconnect_url $oauth2_url@g' $comp_yml
  grep OWNCLOUD_APPS_ $comp_yml

#  We often see networks disappear after a day or two. Maybe that is related to disabling ipv6?
#  # disable ipv6, to not confuse ocis server:
#  echo >> /etc/sysctl.conf "net.ipv6.conf.all.disable_ipv6 = 1"
#  echo >> /etc/sysctl.conf "net.ipv6.conf.default.disable_ipv6 = 1"
#  echo >> /etc/sysctl.conf "net.ipv6.conf.lo.disable_ipv6 = 1"
#  echo >> /etc/sysctl.conf "net.ipv6.conf.eth0.disable_ipv6 = 1"
#  sysctl -p

  # cleanup orphaned volumes!
  docker system prune -f
  docker volume prune -f

  export KOPANO_KONNECT_DOMAIN=$KOPANO_KONNECT_DOMAIN
  export OWNCLOUD_DOMAIN=$OWNCLOUD_DOMAIN
  echo >> /etc/hosts 127.0.0.1 $KOPANO_KONNECT_DOMAIN
  echo >> /etc/hosts 127.0.0.1 $OWNCLOUD_DOMAIN

  export OWNCLOUD_RELEASE_DOCKER_TAG=$OWNCLOUD_RELEASE_DOCKER_TAG
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
    config > merged.yml
  docker-compose -f merged.yml up -d

  while ! docker exec compose_owncloud_1 occ status 2>/dev/null| grep 'installed: true'; do
     echo "Waiting for ownCloud to become ready ..."
     sleep 5
  done
  docker exec compose_owncloud_1 occ app:list 'openidconnect|oauth2' && echo OWNCLOUD IS READY

  while ! docker exec compose_owncloud_1 occ user:sync -l 2>/dev/null | grep 'User_LDAP'; do
    echo "Waiting for user_ldap to be come ready ..."
    sleep 5;
  done
  docker exec compose_owncloud_1 occ user:sync --missing-account-action=disable 'OCA\User_LDAP\User_Proxy' || echo "user:sync failed"

  cat <<EOM
---------------------------------------------
# start a screen session, watch the logs with
	docker-compose -f merged.yml logs -f

# you may now first need to add the DNS entries at https://dash.cloudflare.com
	$IPADDR $KOPANO_KONNECT_DOMAIN
	$IPADDR $OWNCLOUD_DOMAIN

# wait 10 min or restart caddy (as often as needed)
	docker-compose -f merged.yml restart caddy

# until you see log messages like
	caddy_1           | 2020/10/07 00:22:01 [INFO] [konnect-1-0-0rc4.oidc-jw-qa.owncloud.works] Server responded with a certificate.
	caddy_1           | 2020/10/07 00:22:04 [INFO] [owncloud-1-0-0rc4.oidc-jw-qa.owncloud.works] Server responded with a certificate.

# to start a migration from oauth to openidconnect:
	a) docker exec compose_owncloud_1 occ app:enable oauth2
	b) docker exec compose_owncloud_1 occ app:disable openidconnect

# then connect from remote (certs must be good!):
	curl https://$OWNCLOUD_DOMAIN/.well-known/openid-configuration	# if oauht2: 302 to /login page. if openidconnect: json config
	curl http://$IPADDR:9680/status.php
	firefox https://$OWNCLOUD_DOMAIN

# login via 'Kopano' with user: aaliyah_abernathy pass: secret

# you may first need to add the DNS entries to cloudflare or to your local hosts file
	echo $IPADDR $KOPANO_KONNECT_DOMAIN  | sudo tee -a /etc/hosts
  	echo $IPADDR $OWNCLOUD_DOMAIN | sudo tee -a /etc/hosts
---------------------------------------------
EOM
EOF

RUN_SCRIPT

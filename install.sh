#!/bin/bash

function show_syntax {
	echo "Syntax: $0 [options]"
	echo "Options:
	*full
	ldapclient
	nsspam
	*clientcache
	*restore
	*restorepam
	purgeall
	"
	echo "Note: options with * are not implemented yet"
}

# Makes a backup of original config files
function backup_config {
	cp /etc/ldap/ldap.conf /etc/ldap/ldap.conf.save
	cp /etc/libnss-ldap.conf /etc/libnss-ldap.conf.save
	cp /etc/pam_ldap.conf /etc/pam_ldap.conf.save
	cp /etc/hosts /etc/hosts.save
	cp /etc/nsswitch.conf /etc/nsswitch.conf.save
	cp /etc/pam.d/common-auth /etc/pam.d/common-auth.save
	cp /etc/pam.d/common-account /etc/pam.d/common-account
	cp /etc/pam.d/common-session /etc/pam.d/common-session.save
	cp /etc/pam.d/common-password /etc/pam.d/common-password.save

	# create a tarball just in case of disaster...
	filename="install_config_$(date +%Y%m%d%H%M%S)"
	tar -cf $filename /etc/ldap/ldap.conf /etc/libnss-ldap.conf /etc/pam_ldap.conf /etc/hosts /etc/nsswitch.conf /etc/pam.d/common-*
}

# Restores backup config files to its original status
function restore_config {
	mv /etc/ldap/ldap.conf.save /etc/ldap/ldap.conf
	mv /etc/libnss-ldap.conf.save /etc/libnss-ldap.conf
	mv /etc/pam_ldap.conf.save /etc/pam_ldap.conf
	mv /etc/hosts.save /etc/hosts
	mv /etc/nsswitch.conf.save /etc/nsswitch.conf
}

# Restores backup PAM stack config files to its original status
function restore_pam {
	# editing pam stack is always critical...
	xterm -e "sudo su" &
	mv /etc/pam.d/common-auth.save /etc/pam.d/common-auth
	mv /etc/pam.d/common-account /etc/pam.d/common-account
	mv /etc/pam.d/common-session.save /etc/pam.d/common-session
	mv /etc/pam.d/common-password.save /etc/pam.d/common-password
}

# Installs and configures libnss-ldap and libpam-ldap
function install_nsspam {
	apt-get install libnss-ldap libpam-ldap

	# specific config details
	sed 's/pam_ldap.so use_authtok try_first_pass/pam_ldap.so try_first_pass/' /etc/pam.d/common-password > /tmp/common-password && mv /tmp/common-password /etc/pam.d/common-password
	echo "session required        pam_mkhomedir.so skel=/etc/skel umask=0022" >> /etc/pam.d/common-session
	dpkg-reconfigure libnss-ldap libpam-ldap
}

# Installs and configures nss_updatedb and libpam-ccreds
function install_clientcache {
	apt-get install libnss-db nss-updatedb
	nss_updatedb ldap
	apt-get install libpam-ccreds
	sed -e '/pam_unix\.so/s/success=2/success=1/' -e '/pam_ldap\.so/s/success=1/success=ok/' -e '/^account.*requisite.*pam_deny.so/s//#account requisite pam_deny.so/' /etc/pam.d/common-account > /tmp/common-account && mv /tmp/common-account /etc/pam.d/common-account
	sed -e 's/files ldap/files db ldap/' /etc/nsswitch.conf > /tmp/nsswitch.conf && mv /etc/nsswitch.conf /etc/nsswitch.conf.save && mv /tmp/nsswitch.conf /etc/nsswitch.conf
	ln -s /usr/sbin/nss_updatedb /usr/bin/nss_updatedb
	echo "Remeber, you must update crontab hourly, so execute crontab -e and add this line:"
	echo "1	*	*	*	*	/usr/bin/nss_updatedb ldap"
}

# Removes all installed packets
function purge_all {
	apt-get purge ldap-utils libnss-ldap libpam-ldap libnss-db nss-updatedb
	pam-auth-update --force
}

#########
### Begin
#########
# This script...
# 1) places CA certificate to the right place
# 2) backup original ldap.conf
# 3) writes new ldap.conf

if [ $# -gt 1 ]; then
	show_syntax
fi

if [ "$EUID" -ne "0" ]; then
	echo "Not sufficient permissions"
	exit 10
fi

# Cover back
backup_config

if [ "$1" == "ldapclient" ]; then
	# Install ldap-utils
	installUtils=$(dpkg -s ldap-utils | grep -c 'install ok')

	if [ "$installUtils" -eq "0" ]; then
		apt-get install ldap-utils
	else
		echo "Packet 'ldap-utils' already installed."
	fi

	# Copy CA cert
	if [ -f "./ca.example.com.cert.pem" ] && [ ! -f "/etc/ssl/certs/ca.example.com.cert.pem" ]; then
		cp ./ca.example.com.cert.pem /etc/ssl/certs/ca.example.com.cert.pem
		echo "Example CA public certificate copied."
	fi

	# Update /etc/ldap/ldap.conf
	mv /etc/ldap/ldap.conf /etc/ldap/ldap.conf.save

	sed 's/^\(.*\)$/#\1/' /etc/ldap/ldap.conf.save > /etc/ldap/ldap.conf

	echo "
# Example LDAP Server
BASE	dc=example,dc=com
URI	ldaps://ldap-1.example.com
TLS_CACERT	/etc/ssl/certs/ca.example.com.cert.pem
TLS_REQCERT allow
	" >> /etc/ldap/ldap.conf
	echo "New ldap client configuration (ldap.conf) written."

	# Update /etc/hosts
	cp /etc/hosts /etc/hosts.save
	echo "1.2.3.4	ldap-1.example.com	ldap-1" >> /etc/hosts
	echo "File /etc/hosts updated."

elif [ "$1" == "nsspam" ]; then
	install_nsspam

elif [ "$1" == "clientcache" ]; then
	install_clientcache

elif [ "$1" == "restore" ]; then
	#echo 'Restore config...'
	#restore_config
	echo "Restore: not implemented yet"

elif [ "$1" == "restorepam" ]; then
	#echo 'Restore PAM config...'
	#restore_pam
	echo "Restore PAM: not implemented yet"

elif [ "$1" == "purgeall" ]; then
	purge_all

else
	show_syntax
	exit 99
fi

echo 'Done.'
exit 0

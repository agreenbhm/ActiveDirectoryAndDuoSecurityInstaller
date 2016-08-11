#!/bin/bash
#For CentOS 7
#By Drew Green (agreenbhm)

#Make sure you add the Duo IKEY and API Host URL below.
duoikey=
duoapiurl=

#SKEY is read from the CLI at runtime to protect secret key
#If you want to fully automate the install, remove the 'echo' and 'read' lines above below comment, and uncomment the 'duoskey=' line below, then add your SKEY.
#duoskey=
echo -n Duo SKEY:
read duoskey


yum install realmd samba samba-common oddjob oddjob-mkhomedir sssd ntp ntpdate gcc NetworkManager-tui -y

#Replace the 'echo' and 'read' lines below with 'domain=' and then your domain name, if you wish to automate.
#domain=
echo -n Domain Name:
read  domain

ntpdate $domain

systemctl enable ntpd.service

systemctl start ntpd.service

#Replace the 'echo' and 'read' lines below with 'domuser=' and then your domain username (without the domain; so everything before the '@'), if you wish to automate.
#domuser=
echo -n Username without domain:
read domuser

realm join --user=$domuser@$domain $domain

realm list

realm deny -R $domain -a

realm permit -R $domain -g Domain\ Admins

echo "%domain\ admins@$domain ALL=(ALL:ALL) ALL" >> /etc/sudoers

#Begin 'switch root SSH key to other admin section
#This will prep to copy the SSH key from the root account to an account specified; Helpful if you currently have direct SSH capabilities to root and wish to replace it with an [existing] local admin
#Comment out the next 4 lines if you don't want to do this.
echo -n Local Admin:
read admin
su $admin -c "if ! test -d ~/.ssh ; then mkdir ~/.ssh; fi"
su $admin -c "touch ~/.ssh/authorized_keys"
#End 'switch root...'

#Begin 'install SSH key for domain user'
#You'll be prompted for an SSH key for the domain user you specified earlier.  Comment out the 'echo' and 'read' lines below and make a 'domuserssh=' (with the SSH key following) instead if you wish to fully automate this.
#If you use 'domuserssh=', you probably want to enclose the string in quotes.
#domuserssh=
su $domuser@$domain -c "if ! test -d ~/.ssh; then mkdir ~/.ssh; fi"
su $domuser@$domain -c "touch ~/.ssh/authorized_keys"
echo -n Domain User SSH Key:
read domuserssh
su $domuser@$domain -c "echo $domuserssh > ~/.ssh/authorized_keys"
#End 'install SSH key for domain user'

sed -i '/PermitRootLogin/c\' /etc/ssh/sshd_config
sed -i '/PasswordAuthentication/c\' /etc/ssh/sshd_config
echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config

#Copies root SSH keys to the local admin specified before.  Comment out the next 2 lines if you don't want to do this.
#NOTE: It also removes the '.ssh' directory for the root account, so you won't be able to login directly as root.
#Comment the 'rm -rf' line out if you don't wish to remove the root .ssh directory.
cat /root/.ssh/authorized_keys >> /home/$admin/.ssh/authorized_keys
rm -rf /root/.ssh

#Begin Duo install

yum install openssl-devel pam-devel make gcc policycoreutils-python -y

cd ~

curl -L -O -C - https://dl.duosecurity.com/duo_unix-latest.tar.gz

tar xzvf duo_unix*

cd duo_unix*

./configure --with-pam --prefix=/usr && make && sudo make install

make -C pam_duo semodule

echo Installing selinux module...
semodule -i pam_duo/authlogin_duo.pp
echo Done
echo Enabling selinux module...
semodule -e authlogin_duo
echo Done
#To fix bug in selinux Duo module
setsebool -P authlogin_yubikey=1


echo "[duo]
; Duo integration key
ikey = $duoikey
; Duo secret key
skey = $duoskey
; Duo API host
host = $duoapiurl
; Send command for Duo Push authentication
pushinfo = yes

failmode = safe

autopush = yes

prompts = 1" > /etc/duo/pam_duo.conf

	
sed -i '/PubkeyAuthentication/c\' /etc/ssh/sshd_config
sed -i '/AuthenticationMethods/c\' /etc/ssh/sshd_config
sed -i '/UseDNS/c\' /etc/ssh/sshd_config
sed -i '/UsePAM/c\' /etc/ssh/sshd_config
sed -i '/ChallengeResponseAuthentication/c\' /etc/ssh/sshd_config
echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
echo 'AuthenticationMethods publickey,keyboard-interactive' >> /etc/ssh/sshd_config
echo 'UseDNS no' >> /etc/ssh/sshd_config
echo 'UsePAM yes' >> /etc/ssh/sshd_config
echo 'ChallengeResponseAuthentication yes' >> /etc/ssh/sshd_config

	
echo '#%PAM-1.0
auth       required     pam_sepermit.so
auth       substack     password-auth

auth  required pam_env.so
auth  sufficient pam_duo.so
auth  required pam_deny.so

auth       include      postlogin
# Used with polkit to reauthorize users in remote sessions
-auth      optional     pam_reauthorize.so prepare
account    required     pam_nologin.so
account    include      password-auth
password   include      password-auth
# pam_selinux.so close should be the first session rule
session    required     pam_selinux.so close
session    required     pam_loginuid.so
# pam_selinux.so open should only be followed by sessions to be executed in the user context
session    required     pam_selinux.so open env_params
session    required     pam_namespace.so
session    optional     pam_keyinit.so force revoke
session    include      password-auth
session    include      postlogin
# Used with polkit to reauthorize users in remote sessions
-session   optional     pam_reauthorize.so prepare' > /etc/pam.d/sshd



echo '#%PAM-1.0
# This file is auto-generated.
# User changes will be destroyed the next time authconfig is run.
auth        required      pam_env.so
auth        sufficient    pam_unix.so nullok try_first_pass
auth  sufficient pam_duo.so


auth        requisite     pam_succeed_if.so uid >= 1000 quiet_success
auth        sufficient    pam_sss.so use_first_pass

auth        required      pam_deny.so

account     required      pam_unix.so
account     sufficient    pam_localuser.so
account     sufficient    pam_succeed_if.so uid < 1000 quiet
account     [default=bad success=ok user_unknown=ignore] pam_sss.so
account     required      pam_permit.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password    sufficient    pam_unix.so sha512 shadow nullok try_first_pass use_authtok
password    sufficient    pam_sss.so use_authtok
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session     optional      pam_systemd.so
session     optional      pam_oddjob_mkhomedir.so umask=0077
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
session     optional      pam_sss.so' > /etc/pam.d/system-auth


	
echo '#%PAM-1.0
# This file is auto-generated.
# User changes will be destroyed the next time authconfig is run.
auth        required      pam_env.so
auth        sufficient    pam_unix.so nullok try_first_pass

auth        requisite     pam_succeed_if.so uid >= 1000 quiet_success
auth        sufficient    pam_sss.so use_first_pass
auth        required      pam_deny.so

account     required      pam_unix.so
account     sufficient    pam_localuser.so
account     sufficient    pam_succeed_if.so uid < 1000 quiet
account     [default=bad success=ok user_unknown=ignore] pam_sss.so
account     required      pam_permit.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password    sufficient    pam_unix.so sha512 shadow nullok try_first_pass use_authtok
password    sufficient    pam_sss.so use_authtok
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session     optional      pam_systemd.so
session     optional      pam_oddjob_mkhomedir.so umask=0077
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
session     optional      pam_sss.so

session    optional     pam_keyinit.so revoke
session    required     pam_limits.so' >  /etc/pam.d/sudo

systemctl restart sssd
systemctl restart sshd

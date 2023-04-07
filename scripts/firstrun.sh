#!/bin/bash
#
# Copyright (c) 2023, The beep-projects contributors
# this file originated from https://github.com/beep-projects
# Do not remove the lines above.
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see https://www.gnu.org/licenses/
#
# This file is inspired by the firstrun.sh, generated by the Raspberry Pi Imager https://www.raspberrypi.org/software/
#
# This file will setup a raspberrypi with wifi, timezone and keyboard configured
# and sets up the secondrun.service to be started after the next boot.
# At the second boot, networking should be configured
# so that the system can be updated and new software can be downloaded and installed
# For a full description see https://github.com/beep-projects/VASpberryPi/readme.md
#
# This script is run as root, no need for sudo

# redirect output to 'firstrun.log':
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>/boot/firstrun.log 2>&1

echo "START firstrun.sh"

#-------------------------------------------------------------------------------
#----------------------- START OF CONFIGURATION --------------------------------
#-------------------------------------------------------------------------------

# which hostname do you want to give your raspberry pi?
HOSTNAME=vaspberrypi
# username: beep, password: projects
# you can change the password if you want and generate a new password with
# Linux: mkpasswd --method=SHA-256
# Windows: you can use an online generator like https://www.dcode.fr/crypt-hasing-function
USERNAME=beep
# shellcheck disable=SC2016
PASSWD='$5$oLShbrSnGq$nrbeFyt99o2jOsBe1XRNqev5sWccQw8Uvyt8jK9mFR9' #keep single quote to avoid expansion of $
# configure the wifi connection
# the example WPA_PASSPHRASE is generated via
#     wpa_passphrase MY_WIFI passphrase
# but you also can enter your passphrase as plain text, if you accept the potential insecurity of that approach
SSID=MY_WIFI
WPA_PASSPHRASE=3755b1112a687d1d37973547f94d218e6673f99f73346967a6a11f4ce386e41e
# set your locale, get all available: cat /usr/share/i18n/SUPPORTED
LOCALE="de_DE.UTF-8"
# configure your timezone and key board settings
TIMEZONE="Europe/Berlin"
COUNTRY="DE"
XKBMODEL="pc105"
XKBLAYOUT=$COUNTRY
XKBVARIANT=""
XKBOPTIONS=""

#-------------------------------------------------------------------------------
#------------------------ END OF CONFIGURATION ---------------------------------
#-------------------------------------------------------------------------------

#---- things moved from secondrun.sh ------------------------------------------
# configure youre locale
sudo update-locale LANG="$LOCALE"
# things that require user $USERNAME to exist are move to the end of the script
#-------------------------------------------------------------------------------

# copy the USERNAME into secondrun.sh 
sed -i "s/^USERNAME=.*/USERNAME=${USERNAME}/" /boot/secondrun.sh

# set hostname and username
CURRENT_HOSTNAME=$( </etc/hostname tr -d " \t\n\r" )
echo "set hostname to ${HOSTNAME} (was ${CURRENT_HOSTNAME})"
echo $HOSTNAME >/etc/hostname
sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$HOSTNAME/g" /etc/hosts

FIRSTUSER=$( getent passwd 1000 | cut -d: -f1 )
echo "set default user to ${USERNAME} (was ${FIRSTUSER})"
if [ -f /usr/lib/userconf-pi/userconf ]; then
   echo "/usr/lib/userconf-pi/userconf ${USERNAME} ${PASSWD}"
   /usr/lib/userconf-pi/userconf "${USERNAME}" "${PASSWD}"
else
   echo "setting ${USERNAME}:${PASSWD} the non-Pi-way"
   echo "${FIRSTUSER}:${PASSWD}" | chpasswd -e
   if [ "${FIRSTUSER}" != "${USERNAME}" ]; then
      usermod -l "${USERNAME}" "${FIRSTUSER}"
      usermod -m -d "/home/${USERNAME}" "${USERNAME}"
      groupmod -n "${USERNAME}" "${FIRSTUSER}"
      if grep -q "^autologin-user=" /etc/lightdm/lightdm.conf ; then
         sed /etc/lightdm/lightdm.conf -i -e "s/^autologin-user=.*/autologin-user=${USERNAME}/"
      fi
      if [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
         sed /etc/systemd/system/getty@tty1.service.d/autologin.conf -i -e "s/${FIRSTUSER}/${USERNAME}/"
      fi
      if [ -f /etc/sudoers.d/010_pi-nopasswd ]; then
         sed -i "s/^${FIRSTUSER} /${USERNAME} /" /etc/sudoers.d/010_pi-nopasswd
      fi
   fi
fi

echo "setting network options"
sed -i "s/^REGDOMAIN=.*/REGDOMAIN=${COUNTRY}/" /etc/default/crda

systemctl enable ssh
cat >/etc/wpa_supplicant/wpa_supplicant.conf <<WPAEOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
country=$COUNTRY
#ap_scan=1
update_config=1
network={
	ssid="$SSID"
	psk=$WPA_PASSPHRASE
}

WPAEOF
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
rfkill unblock wifi
for filename in /var/lib/systemd/rfkill/*:wlan ; do
  echo 0 > "${filename}"
done
rm -f /etc/xdg/autostart/piwiz.desktop
rm -f /etc/localtime

echo "setting timezone and keyboard layout"
echo $TIMEZONE >/etc/timezone
dpkg-reconfigure -f noninteractive tzdata
cat >/etc/default/keyboard <<KBEOF
XKBMODEL=$XKBMODEL
XKBLAYOUT=$XKBLAYOUT
XKBVARIANT=$XKBVARIANT
XKBOPTIONS=$XKBOPTIONS
KBEOF
dpkg-reconfigure -f noninteractive keyboard-configuration

#---- things moved from secondrun.sh ------------------------------------------
# Creating a gvm system user and group
sudo useradd -r -M -U -G sudo -s /usr/sbin/nologin gvm
# Add user $USERNAME to gvm group, this requires a reboot to be active
sudo usermod -aG gvm "$USERNAME"
#------------------------------------------------------------------------------

#clean up
#echo "removing firstrun.sh from the system"
#rm -f /boot/firstrun.sh
sed -i "s| systemd.run.*||g" /boot/cmdline.txt

echo "installing secondrun.service"
# make sure secondrun.sh is executed at next boot. 
# we will need network up and running, so we install the script as a service that depends on network
cat <<EOF >/etc/systemd/system/secondrun.service
[Unit]
Description=SecondRun
After=network.target
Before=rc-local.service
ConditionFileNotEmpty=/boot/secondrun.sh

[Service]
User=$USERNAME
WorkingDirectory=/home/$USERNAME
ExecStart=/boot/secondrun.sh
Type=oneshot
RemainAfterExit=no

[Install]
WantedBy=multi-user.target

EOF
#reload systemd to make the daemon aware of the new configuration
systemctl --system daemon-reload
#enable service
systemctl enable secondrun.service
echo "DONE firstrun.sh"

exit 0

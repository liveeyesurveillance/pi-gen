#!/bin/bash -e

install -m 755 files/resize2fs_once	"${ROOTFS_DIR}/etc/init.d/"

install -d				"${ROOTFS_DIR}/etc/systemd/system/rc-local.service.d"
install -m 644 files/ttyoutput.conf	"${ROOTFS_DIR}/etc/systemd/system/rc-local.service.d/"

install -m 644 files/50raspi		"${ROOTFS_DIR}/etc/apt/apt.conf.d/"

install -m 644 files/console-setup   	"${ROOTFS_DIR}/etc/default/"

install -m 755 files/rc.local		"${ROOTFS_DIR}/etc/"

if [ -n "${PUBKEY_SSH_FIRST_USER}" ]; then
	install -v -m 0700 -o 1000 -g 1000 -d "${ROOTFS_DIR}"/home/"${FIRST_USER_NAME}"/.ssh
	echo "${PUBKEY_SSH_FIRST_USER}" >"${ROOTFS_DIR}"/home/"${FIRST_USER_NAME}"/.ssh/authorized_keys
	chown 1000:1000 "${ROOTFS_DIR}"/home/"${FIRST_USER_NAME}"/.ssh/authorized_keys
	chmod 0600 "${ROOTFS_DIR}"/home/"${FIRST_USER_NAME}"/.ssh/authorized_keys
fi

if [ "${PUBKEY_ONLY_SSH}" = "1" ]; then
	sed -i -Ee 's/^#?[[:blank:]]*PubkeyAuthentication[[:blank:]]*no[[:blank:]]*$/PubkeyAuthentication yes/
s/^#?[[:blank:]]*PasswordAuthentication[[:blank:]]*yes[[:blank:]]*$/PasswordAuthentication no/' "${ROOTFS_DIR}"/etc/ssh/sshd_config
fi

on_chroot << EOF
systemctl disable hwclock.sh
systemctl disable nfs-common
systemctl disable rpcbind
if [ "${ENABLE_SSH}" == "1" ]; then
	systemctl enable ssh
else
	systemctl disable ssh
fi
systemctl enable regenerate_ssh_host_keys
EOF

if [ "${USE_QEMU}" = "1" ]; then
	echo "enter QEMU mode"
	install -m 644 files/90-qemu.rules "${ROOTFS_DIR}/etc/udev/rules.d/"
	on_chroot << EOF
systemctl disable resize2fs_once
EOF
	echo "leaving QEMU mode"
else
	on_chroot << EOF
systemctl enable resize2fs_once
EOF
fi

on_chroot <<EOF
for GRP in input spi i2c gpio; do
	groupadd -f -r "\$GRP"
done
for GRP in adm dialout cdrom audio users sudo video games plugdev input gpio spi i2c netdev render; do
  adduser $FIRST_USER_NAME \$GRP
done
EOF

if [ -f "${ROOTFS_DIR}/etc/sudoers.d/010_pi-nopasswd" ]; then
  sed -i "s/^pi /$FIRST_USER_NAME /" "${ROOTFS_DIR}/etc/sudoers.d/010_pi-nopasswd"
fi

on_chroot << EOF
setupcon --force --save-only -v
EOF

on_chroot << EOF
usermod --pass='*' root
EOF

rm -f "${ROOTFS_DIR}/etc/ssh/"ssh_host_*_key*

# Install Node.js version 11.14.0
on_chroot << EOF
curl -o /home/nymea/node-v11.14.0-linux-armv6l.tar.gz https://nodejs.org/download/release/v11.14.0/node-v11.14.0-linux-armv6l.tar.gz -k
tar -xzf /home/nymea/node-v11.14.0-linux-armv6l.tar.gz -C /home/nymea/
sudo cp -r /home/nymea/node-v11.14.0-linux-armv6l/* /usr/local/
EOF


# Install the custom package from Git
on_chroot << EOF
git clone https://nitish-liveeye:XXXXXXXXXXXXX@github.com/liveeyesurveillance/data-capture-server.git
EOF

# Install dependencies for the custom package
on_chroot << EOF
cd /home/nymea/data-capture-server
npm install
EOF

# Copy the file to the system directory for it to run as a service
on_chroot << EOF
cp /home/nymea/data-capture-server/LiveEyeDataCapture.service ${ROOTFS_DIR}/etc/systemd/system
sudo systemctl enable LiveEyeDataCapture.service
EOF

# Load the watchdog module
on_chroot << EOF
modprobe bcm2835_wdt
echo "bcm2835_wdt" >> /etc/modules
echo "watchdog-device = /dev/watchdog" >> /etc/watchdog.conf
echo "watchdog-timeout = 60" >> /etc/watchdog.conf
systemctl start watchdog
EOF

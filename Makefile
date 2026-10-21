# Kbuild part (also used by DKMS: make -C <kernel> M=<dir> modules)
obj-m := src/linuwu_sense.o

ifeq ($(KERNELRELEASE),)

KVER  ?= $(shell uname -r)
KDIR  := /lib/modules/$(KVER)/build
PWD   := $(shell pwd)

MDIR  := /lib/modules/$(KVER)/kernel/drivers/platform/x86
MODNAME := linuwu_sense
REAL_USER := $(shell echo $${SUDO_USER:-$$(whoami)})
VERSION := $(shell sed -n 's/^\#define DRIVER_VERSION "\(.*\)"/\1/p' src/$(MODNAME).c)
UDEV_RULE := 99-linuwu-sense.rules
UDEV_DIR := /etc/udev/rules.d

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

# Best effort: every step runs even if a previous one failed.
uninstall:
	-@sudo rm -f /etc/modules-load.d/$(MODNAME).conf
	-@sudo rm -f /etc/modprobe.d/blacklist-acer_wmi.conf
	-@sudo systemctl stop linuwu_sense.service
	-@sudo systemctl disable linuwu_sense.service
	-@sudo rm -f /etc/systemd/system/linuwu_sense.service
	-@sudo systemctl daemon-reload
	-@sudo rmmod $(MODNAME) 2>/dev/null || true
	-@sudo modprobe acer_wmi
	-@echo "Removing current user from linuwu_sense group if exists..."
	-@if getent group linuwu_sense >/dev/null; then \
		sudo gpasswd -d $(REAL_USER) linuwu_sense || true; \
		sudo groupdel linuwu_sense || true; \
	else \
		echo "Group linuwu_sense does not exist."; \
	fi
	-@sudo rm -f /etc/tmpfiles.d/$(MODNAME).conf
	-@sudo rm -f $(UDEV_DIR)/$(UDEV_RULE)
	-@sudo udevadm control --reload-rules
	-@sudo rm -f $(MDIR)/$(MODNAME).ko
	-@sudo depmod -a
	@echo "Uninstalled $(MODNAME) and cleaned up related configuration."

install: all
	@test -f linuwu_sense.service || { echo "linuwu_sense.service not found in $(PWD)"; exit 1; }
	@test -f $(UDEV_RULE) || { echo "$(UDEV_RULE) not found in $(PWD)"; exit 1; }
	@echo "Setting up group and permissions..."
	@echo "Detected user: $(REAL_USER)"
	@if ! getent group linuwu_sense >/dev/null; then \
		sudo groupadd linuwu_sense; \
	fi
	sudo usermod -aG linuwu_sense $(REAL_USER)
	@# Permissions are now applied by a udev rule when the driver binds; the old
	@# tmpfiles entries ran at boot before the module was loaded and failed.
	-@sudo rm -f /etc/tmpfiles.d/$(MODNAME).conf
	sudo install -m 644 $(UDEV_RULE) $(UDEV_DIR)/$(UDEV_RULE)
	-@sudo udevadm control --reload-rules
	@sudo rmmod acer_wmi 2>/dev/null || true
	@echo "blacklist acer_wmi" | sudo tee /etc/modprobe.d/blacklist-acer_wmi.conf > /dev/null
	sudo install -d $(MDIR)
	sudo install -m 644 src/$(MODNAME).ko $(MDIR)
	sudo depmod -a
	@echo "$(MODNAME)" | sudo tee /etc/modules-load.d/$(MODNAME).conf > /dev/null
	sudo modprobe $(MODNAME)
	@# Apply the rule now in case the module was already loaded
	-@sudo udevadm trigger --action=bind --subsystem-match=platform --sysname-match=acer-wmi
	-@sudo udevadm settle
	sudo install -m 644 linuwu_sense.service /etc/systemd/system/linuwu_sense.service
	@sudo systemctl daemon-reload
	@sudo systemctl enable linuwu_sense.service
	@sudo systemctl start linuwu_sense.service
	@echo "Module $(MODNAME) $(VERSION) installed and configured to load at boot."
	@echo "Log out and back in for the linuwu_sense group membership to take effect."

# DKMS install (survives kernel updates). The package version is DRIVER_VERSION.
dkms-install:
	@grep -q '^PACKAGE_VERSION="$(VERSION)"' dkms.conf || { echo "dkms.conf PACKAGE_VERSION does not match DRIVER_VERSION ($(VERSION))"; exit 1; }
	-sudo dkms remove linuwu-sense/$(VERSION) --all 2>/dev/null
	sudo rm -rf /usr/src/linuwu-sense-$(VERSION)
	sudo install -d /usr/src/linuwu-sense-$(VERSION)/src
	sudo install -m 644 Makefile dkms.conf /usr/src/linuwu-sense-$(VERSION)/
	sudo install -m 644 src/$(MODNAME).c /usr/src/linuwu-sense-$(VERSION)/src/
	sudo dkms install linuwu-sense/$(VERSION)

.PHONY: all clean install uninstall dkms-install

endif

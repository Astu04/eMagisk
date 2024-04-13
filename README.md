!!! THERE IS NO SUPPORT FOR THIS. IT WORKS FOR ME... MOSTLY. DON'T DM ME ABOUT THIS ASKING FOR SUPPORT !!! 

# eMagisk

Installs binaries and scripts for QoL. Also runs a sh that tries to recover the MITM when stuff goes wrong.

---

## Installation

1. Download the latest release (check tags)
2. adb push the magisk module into the device (or wget/curl)
3. `magisk --install-module magiskmodule.zip`
4. copy `emagisk.config` from `https://github.com/Astu04/eMagisk/blob/master/emagisk.config` into `/data/local/tmp` of your device
5. **Edit the file to match your config** (If you don't use RDM, leave the values under `rdm_user`, `rdm_password` and `rdm_backendURL` **blank**)
6. `reboot`

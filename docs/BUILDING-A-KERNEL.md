# Building and installing a patched kernel for the 6T (what worked for us)

Read `RECOVERY.md` first and make the undo copy. This is the recipe that worked repeatedly, on a PC
(Debian/Ubuntu), for the postmarketOS `linux-postmarketos-qcom-sdm845` kernel 7.1-rc1.

## Facts

- Source: `https://gitlab.com/sdm845-mainline/linux`, tag `sdm845-7.1-rc1-r0`. postmarketOS' recipe is
  `device/community/linux-postmarketos-qcom-sdm845/APKBUILD` in pmaports.
- Config: take the running phone's own `/proc/config.gz` (CFI, shadow call stack and BTI are on).
  **Build with clang (`LLVM=1`), not gcc.** Ubuntu's clang 18 built a kernel that boots fine.
- The boot image is an Android boot.img (header v0, page size 4096) with the device tree appended to
  the kernel. pmOS's `boot-deploy` builds it from `/boot` and **flashes `boot_a` automatically** when
  you `apk add` a kernel package.
- No module versioning and no module signing, so a single module can be rebuilt and copied.

## Steps

```
sudo apt-get install clang lld llvm libssl-dev libelf-dev bc flex bison   # once
cd linux-sdm845-7.1-rc1-r0                                                # unpacked tag
patch -p1 --forward < ../the-fix.patch                                    # or git am
cp ../phone.config .config && make ARCH=arm64 LLVM=1 olddefconfig         # diff with phone.config should be empty
nice make -j$(nproc) ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=N-postmarketos-qcom-sdm845 > ../build.log 2>&1
cat include/config/kernel.release     # must equal the phone's `uname -r`, or modules will not load
```

`KBUILD_BUILD_VERSION` is the `#N` in `uname -v`; bump it every build so you can tell which kernel
booted. About 9 minutes with 16 jobs.

Stage it like the pmOS package (kernel as `linux.efi`/`vmlinuz`, `modules_install` with
`INSTALL_MOD_STRIP=1`, dtbs under `boot/dtbs/qcom/`) and wrap it in an apk with `abuild` on the phone
(source = your tarball, `package()` = `mkdir -p "$pkgdir"; cp -a boot usr`, options
`!check !strip !tracedeps !fhs`). Compare the file list with
`apk info -L linux-postmarketos-qcom-sdm845` before installing.

Install: `sudo apk add --allow-untrusted ./linux-...-rN.apk` (this flashes `boot_a`), then reboot and verify:
`uptime` (did it really reboot?), `uname -v` (the new `#N`), the feature itself, `dmesg -l err,crit`.

**Try before you flash:** build the boot image and run `fastboot boot img` from the PC (RAM only).

## Pitfalls that cost us hours

- **Initramfs modules must match the kernel version string.** If `uname -r` changes (we used a `-hfp`
  suffix for a test kernel), the modules inside the initramfs still belong to the old name, so
  `libcomposite` silently fails to load: no USB gadget, no pmOS USB networking, and no obvious error.
  Rebuild the initramfs (mkinitfs) for the new release.
- **A kernel package upgrade from pmOS replaces your kernel** and any module you copied by hand. Keep the
  patches, re-apply on every kernel update. If you do not want pmOS to flash `boot_a` on its own, set
  `deviceinfo_flash_kernel_on_update="false"` in `/etc/deviceinfo` (then you flash by hand).
- **A module you replace live is not re-registered by rmmod/modprobe** for the SLIMbus codecs: just reboot.
- **Built-in drivers (`=y`) need a full kernel and a flash**; modules can be swapped alone.
- **Never unbind a serial/BT driver while Bluetooth is powered** (kernel oops). See fix 04.
- The PC's front/hub USB ports stalled long copies; a direct rear port did not. Copy in chunks with
  checksums.
- The phone shell is busybox `ash`: no `${PIPESTATUS}`.

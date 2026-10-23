# AppArmor

The kernel only runs AppArmor when the `lsm=` kernel parameter lists it. `modules/grub-multiboot` adds that parameter once the `apparmor` package is installed. A machine whose GRUB entry boots a unified kernel image (a mkinitcpio preset with `*_uki=`, such as kirito's `/boot/EFI/Linux/arch-linux.efi`) ignores GRUB's command line, so it also gets the parameter in `/etc/kernel/cmdline` and the images are rebuilt with `mkinitcpio -P`. It keeps the LSMs the kernel already runs and puts `apparmor` before `bpf`. `apparmor.service` loads the profiles from `/etc/apparmor.d` on the next boot after that.

Before rebooting, check that GRUB got the parameter:
```
grep CMDLINE_LINUX_DEFAULT /etc/default/grub
```
It should end with `lsm=…,apparmor,bpf`. On a unified kernel image machine, `cat /etc/kernel/cmdline` should too.

## What it can break

Only programs with an enforcing profile. Arch ships few, and its browser, Steam and Discord profiles are unconfined, so those run as before. Snaps become confined through `snapd.apparmor.service`.

libvirt may confine each VM with a generated profile once it sees AppArmor. If a VM fails to start with a permission error, that's the likely cause.

## After the reboot

```
sudo aa-status                                  # loaded profiles and confined processes
journalctl -k -b | grep 'apparmor="DENIED"'     # anything AppArmor blocked this boot
```

## When something is blocked

- Make one profile log instead of block:
  ```
  sudo aa-complain /etc/apparmor.d/<profile>
  ```
- Boot once without AppArmor: press `e` on the GRUB entry and delete `lsm=…` from the `linux` line. A unified kernel image entry has no such line, and its fallback image carries the same command line; undo it for good instead (below).
- Turn it off for good:
  1. Remove `apparmor` from `profiles/security/packages.list` and `module apparmor` from `profiles/security/profile.conf`.
  2. Take `lsm=` out of `/etc/default/grub`, or restore it from the run receipt's backup (`~/.local/state/dotfiles/runs/<run>/backups/system/etc/default/grub`).
  3. `sudo grub-mkconfig -o /boot/grub/grub.cfg`.
  4. On a unified kernel image machine, take `lsm=` out of `/etc/kernel/cmdline` too and run `sudo mkinitcpio -P`.

  grub-multiboot stops adding `lsm=` once `apparmor_parser` is gone.

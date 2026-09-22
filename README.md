# Jalea

<img src="docs/jalea.png" align="right" width="420" alt="A plate of jalea: fried seafood under pickled red onions">

An immutable Debian, built with [mkosi](https://github.com/systemd/mkosi),
with [Nix](https://nixos.org/) for everything that changes after that.

> **Disclaimer: proof of concept. Not safe for human consumption.**
>
> Jalea exists to demonstrate an idea. It has not been reviewed, hardened,
> or tested beyond QEMU VMs and a single Intel NUC 13 Pro. It repartitions
> disks, encrypts them with keys sealed to a TPM, and replaces its own
> operating system over the network. Any of that can destroy data, brick a
> machine, or lock you out of your files, and the author takes no
> responsibility for what happens with Jalea. Use it on hardware and data
> you can afford to lose.

Debian's package manager needs a writable root file system. Seal the root
and apt stops working, which is the wall every immutable Debian hits. Jalea
goes around it: the base is built once with mkosi and frozen (apt is not even
installed), and Nix, which keeps everything in a content-addressed
`/nix/store` and never needs a writable root, manages everything on top.

* **Debian 13 (trixie)** in a read-only erofs `/usr`, protected by dm-verity
  and booted as a unified kernel image.
* **All user data**, including `/etc`, `/var`, `/home` and `/nix`, on one
  **LUKS2 volume** whose key is sealed to the TPM2 with systemd-cryptenroll's
  token format. It unlocks itself at boot and is never touched by updates.
* **Nix** from Debian's own archive as the seed; it then installs the current
  Nix from nixpkgs and runs on that.
* **A/B updates with [RAUC](https://rauc.io/)**: two complete slot groups,
  a daily check that streams a new GitHub Release straight into the idle
  group with adaptive block-level downloads, no reboot until you choose,
  and a firmware-level fallback if the new group fails to boot.
* **Zsh** as the login shell and **[Helix](https://helix-editor.com/)** as
  the editor, out of the box.
* **[Tailscale](https://tailscale.com/)** built in: one `tailscale up` and
  the machine is on your tailnet.
* A **USB installer** for real hardware, and `jalea-boot-stick` to reboot a
  running Jalea straight into it. Developed on an Intel NUC 13 Pro; anything
  that boots UEFI with a TPM2 should work.

Jalea is a Peruvian platter of fried seafood. The word "jalea" means "jelly"
in Spanish. Tastes better than it sounds.

## Disk layout

| Partition  | Type          | Contents                                              |
|------------|---------------|-------------------------------------------------------|
| `esp_a`    | ESP           | UKI `EFI/Linux/jalea.efi`, systemd-boot as fallback   |
| `verity_a` | usr-verity    | dm-verity hash tree                                   |
| `usr_a`    | usr           | Debian, erofs, read-only                              |
| `esp_b`    | ESP           | slot group B, empty until the first update            |
| `verity_b` | usr-verity    |                                                       |
| `usr_b`    | usr           |                                                       |
| `data`     | root          | LUKS2 + btrfs: `/`, with `/var` `/home` `/nix` subvolumes |

The UKI's command line carries `usrhash=`, the verity root hash. systemd
derives the GPT UUIDs of the usr and verity partitions from that hash, so a
UKI only ever boots the `/usr` it was built with. The root partition is not
named at all: systemd-gpt-auto-generator finds the LUKS partition on the boot
disk and unlocks it with the TPM2.

`/etc` starts empty. On every boot systemd-tmpfiles merges Debian's factory
`/etc`, captured at build time, into it without overwriting existing files.
Your edits persist; new defaults from a new image version appear on their own.
Accounts that Debian packages created at build time are re-created by
systemd-sysusers from a generated `sysusers.d` file, with the same IDs.

snapper keeps btrfs snapshots of `/` (so `/etc`) and `/home`: one at every
boot, one every hour, thinned to a day of hourlies, a week of dailies and a
month of weeklies. `/var` and `/nix` are not snapshotted.

```sh
sudo snapper -c root list                    # snapshots of / (root config)
sudo snapper -c root status 3..0             # what changed since snapshot 3
sudo snapper -c root diff 3..0 /etc/hostname # the change itself
sudo snapper -c root undochange 3..0 /etc/hostname
sudo snapper -c home list                    # same for /home (home config)
```

## Build

You need mkosi 27 or newer. Upstream's recommended way:

```sh
git clone https://github.com/systemd/mkosi ~/mkosi
git -C ~/mkosi checkout v27
ln -s ~/mkosi/bin/mkosi ~/.local/bin/mkosi
```

mkosi builds its own tools tree, so the host needs only Python, a package
manager it knows (dnf, apt, pacman, zypper) and user namespaces.

```sh
./scripts/gen-dev-keys.sh   # once: throwaway signing keys in keys/
mkosi build                 # release-shaped image
mkosi --profile=dev build   # same, plus SSH over vsock for `mkosi ssh`
```

This produces, in `mkosi.output/`:

* `jalea_<version>.raw`, the disk image (slot group A populated, B empty,
  no root partition yet).
* `jalea_<version>.esp.raw`, `.usr.raw`, `.verity.raw`, the split partitions.
* `jalea.efi`, the UKI.

### Try it in a VM

```sh
mkosi vm
```

The VM gets a virtual TPM and a disk grown to 16 GB. On first boot
systemd-repart creates the encrypted root, then you land on a serial console
as user `jalea` (password `jalea`, member of `sudo` and `nix-users`). Those
credentials come from `mkosi.credentials/` and exist only in the VM. With the
`dev` profile, `mkosi ssh` gets you a shell over vsock. To leave the console,
press Ctrl-] three times within a second.

The first boot comes through the firmware's fallback loader path, so RAUC
sees no boot entry of its own; `jalea-efi-entries.service` creates entries
`A` and `B` and points the next boot at `A`.

### Build the update bundle

```sh
./scripts/build-bundle.sh
```

writes `mkosi.output/jalea_<version>.raucb`: verity format, adaptive
block-hash index for the usr and verity images, signed with `keys/rauc.key`.

## Install on hardware

You need a machine that boots UEFI and has a TPM2, a disk on it you can
wipe, and a USB stick of 8 GB or more. Everything on the stick is erased.

### Flash release image to USB stick

Download `jalea_<version>.raw.zst` and `SHA256SUMS` from the
[latest release](https://github.com/fvasquez/jalea/releases/latest), check
the download and write it to the stick (`/dev/sdX` below):

```sh
sha256sum -c --ignore-missing SHA256SUMS
zstd -dc jalea_<version>.raw.zst | sudo dd of=/dev/sdX bs=4M status=progress oflag=direct
```

### Flash dev image to USB stick

Write a local build instead:

```sh
mkosi burn /dev/sdX          # or: dd if=mkosi.output/jalea_<version>.raw of=/dev/sdX bs=4M
```

### Boot the stick

Boot the stick with Secure Boot disabled. systemd-boot shows its menu for
ten seconds; pick **Install Jalea to a disk**. The installer asks for

* the **target disk**, from a list of every disk but the stick, with the
  first NVMe as the default,
* a **hostname** (default `jalea`),
* a **username** and a **password**,
* optionally a **Wi-Fi network** (SSID) and its **passphrase**; leave the
  network empty for none,
* a typed `yes` before it touches the disk,

then

1. partitions the disk with systemd-repart, block-copying the ESP, usr and
   verity partitions it booted from into slot group A and leaving B empty,
2. creates the LUKS2 root, enrolled to the TPM2 (PCR 7), formats it btrfs
   with subvolumes for `/var`, `/home` and `/nix`,
3. drops the hostname and the account (as systemd credentials that
   systemd-sysusers consumes on first boot) onto the new root, plus an iwd
   profile for the Wi-Fi network if you gave one, so the machine is online
   on its first boot,
4. creates firmware boot entries `A` and `B` pointing at the two UKIs.

The installer powers the machine off. Remove the stick and power it on. The
first boot is an ordinary boot: log in on
the console or over SSH with the account you created. `sudo` works. The
login shell is zsh, with a starter `~/.zshrc` from `/etc/skel`; bash is
there too.

Networking is systemd-networkd with DHCP on wired and wireless interfaces
and iwd for Wi-Fi. To join another network later, use `iwctl`; iwd remembers
it under `/var/lib/iwd`, which is on the encrypted volume.

Tailscale is installed and its daemon runs from the first boot. The account
the installer created may drive it without `sudo`. Join your tailnet once
with `tailscale up`; the node key lives in `/var/lib/tailscale`, on the
encrypted volume, so it survives updates.

If you let the stick's default entry boot instead, you get a live Jalea
whose encrypted root is created *on the stick*. That is a feature, not an
accident.

### Reinstall from a running Jalea

No firmware hotkeys needed. Insert the stick and run:

```sh
sudo jalea-boot-stick --installer
```

`jalea-boot-stick` finds the stick, makes sure the firmware has a boot entry
for its ESP, sets `BootNext` to it and reboots. `--installer` also tells
systemd-boot on the stick to start the installer instead of showing its
menu; leave it off to land in the menu. Both are one-shot, so the boot
after that follows `BootOrder` again. `--no-reboot` sets everything up and
leaves the reboot to you.

The installer, the first boot of the installed disk (TPM2 unlock included),
an update streamed from a GitHub Release and a reinstall over an existing
Jalea have all been exercised on an Intel NUC 13 Pro. In QEMU the installer
can only be followed up to the creation of the firmware entries: a `mkosi
vm` session gets a fresh virtual TPM each time and OVMF does not enumerate a
second virtio disk the way real firmware enumerates an NVMe.

## Updates

Updates are automatic. Once a day `jalea-update.timer` asks GitHub for the
latest release and, if it is newer than the running image, streams its
bundle into the inactive slot group. Nothing reboots: RAUC has already
pointed the firmware at the new group, so it takes effect on the next
reboot, and the login banner says so until then.

```sh
jalea-update --check                      # is there a newer release?
sudo jalea-update                         # install it now, into the idle group
sudo rauc status                          # which group is booted, which is next
sudo reboot                               # switch to the new group
sudo systemctl mask --now jalea-update.timer   # turn the daily check off
```

`systemctl disable` would not stick: the factory `/etc` merge re-enables
the timer at the next boot, so masking is the way to turn it off.

Local builds go the same way by hand: serve `mkosi.output/` over HTTP (with
range requests; Python's `http.server` lacks them) or copy the bundle over.

```sh
sudo rauc install http://build-host:8000/jalea_0.1.7-3-gabc1234.raucb
sudo rauc install /home/jalea/jalea_0.1.7-3-gabc1234.raucb
sudo reboot
```

If the new group fails to boot, the firmware falls back to the previous one
on its own. Nothing in `data` is part of a bundle: `/etc`, `/home` and the
Nix store stay exactly as they were, whichever group boots. The mechanics
are in [How updates work](#how-updates-work).

## Nix

Debian's `nix-bin` and `nix-setup-systemd` packages provide the daemon and
the build users. On the first boot with network, `nix-upgrade.service` runs

```sh
nix profile install nixpkgs#nix
```

into the system profile and restarts the daemon on the result, so the daemon
you talk to is current Nix, not the one Debian froze. From then on:

```sh
nix profile install nixpkgs#htop
nix run nixpkgs#cowsay -- hello
nix shell nixpkgs#python3Packages.requests
```

Flakes and `nix-command` are enabled in `/etc/nix/nix.conf`. Members of
`sudo` are trusted users. Debian's package restricts the daemon socket to the
`nix-users` group; the installer puts the first user in it.

## Signing keys and releases

Bundles are signed with an X.509 key. Locally, `scripts/gen-dev-keys.sh`
makes a self-signed pair in `keys/`, and that certificate is baked into the
image as `/etc/rauc/keyring.pem`. If `keys/release.crt` is present as well
(the certificate attached to every GitHub Release), it is added to the
keyring, so a locally built device also accepts published bundles.

CI uses the `RAUC_KEY` repository secret (private key, PEM) and the
`RAUC_CERT` repository variable (certificate, PEM). A push of a `v*` tag
builds the image and bundle and attaches them, plus the UKI, the certificate
and checksums, to a GitHub Release.

## Layout of this repository

```
mkosi.conf              image definition
mkosi.repart/           partition table of the built image (A populated, B empty)
mkosi.uki-profiles/     the "Install" boot entry
mkosi.profiles/dev/     SSH over vsock for development VMs
mkosi.sandbox/          Tailscale's apt repository and key, for the build only
mkosi.credentials/      dev VM account and autologin (never in the image)
mkosi.prepare           installs Helix, the default editor, from upstream
mkosi.finalize          captures the factory /etc, generates sysusers.d
mkosi.postinst          bakes the RAUC certificate into the image
mkosi.extra/            files added to the image
  usr/lib/repart.d/     the encrypted root, created on the device
  usr/bin/              jalea-boot-stick, jalea-update
  usr/lib/jalea/        installer, boot-entry repair, RAUC backend, nix-daemon wrapper, snapper and tailscale setup
  usr/share/factory/etc RAUC, Nix and zsh configuration
rauc/                   bundle manifest template and install hook
scripts/                dev keys, bundle build
.github/workflows/      CI and releases
```

## How updates work

RAUC streams the bundle over HTTPS (no local copy), and with the block-hash
index it fetches only blocks that differ from the running slot group. The
images land in the inactive group; a post-install hook stamps the partition
UUIDs derived from the new root hash so the new UKI can find them. RAUC then
sets the firmware's `BootNext` to the new group. If that boot succeeds,
`jalea-mark-good.service` moves it to the front of `BootOrder`; if it does
not, the firmware falls back to the previous group by itself.

RAUC's slot switching goes through `/usr/lib/jalea/rauc-bootloader`, a small
custom backend with the same BootNext/BootOrder semantics as RAUC's built-in
EFI backend. The difference is how it tells which group is running: from the
ESP that systemd-stub reports it was loaded from (`LoaderDevicePartUUID`),
which works even when the firmware booted via the fallback loader and
`BootCurrent` names no slot.

That booted ESP also defines the *system disk*, and everything that names a
slot partition is scoped to it. The installer stick is the same image as an
installed system, so it carries the same partition labels, and when it holds
the build that is running, the same usr/verity partition UUIDs. A udev rule
(`61-jalea-system-disk.rules`, in the initrd too) gives the system disk's
partitions priority for the `/dev/disk/by-partlabel` and `by-partuuid`
symlinks, so RAUC's slots and the initrd's `/usr` lookup resolve to the
right disk even with a stick inserted; `/usr/lib/jalea/system-disk` is the
helper behind it. Still, take the stick out when you are not installing.

If the new group cannot boot, the firmware falls back on its own: a UKI it
cannot load is skipped for the next entry in `BootOrder`, and a UKI that
loads but whose `/usr` fails verification makes the initrd reboot after
systemd's 90-second device timeout (a drop-in in `mkosi.initrd.conf/`), with
the same result. Both paths have been exercised in the VM.

Nothing in `data` is part of a bundle. Rolling back to the previous group
keeps your `/etc`, `/home` and Nix store exactly as they were; the store is
content-addressed, so a base rollback cannot invalidate it.

## Status

Early. Secure Boot with self-enrolled keys, which would let the TPM policy
cover the boot chain, is planned but not required. Contributions welcome.

## License

MIT, see `LICENSE`.

#!/usr/bin/python3 -I
"""abtest - test kernels on the OnePlus 6T's spare slot (b) without ever marking it "successful".

Idea: the everyday kernel lives on the HOME slot (a, /etc/ab-home-slot) and only the home slot is
ever marked "successful" at boot (the qbootctl.service drop-in runs `abtest mark-if-home`). A test kernel goes to
boot_b and gets ONE boot attempt (qbootctl -s b writes retry=1, successful=0). Because nothing marks b successful,
ANY later restart (planned, crash, watchdog, 10 s power hold) makes the bootloader (ABL) mark b unbootable and switch
back to a by itself. The home slot is therefore always the place the phone comes back to.

Commands (run as root, re-execs itself with sudo):
  status            slots, images, boot LUN, verdict
  flash IMG         write a boot image to boot_b (test slot) and verify it
  go [--no-reboot]  arm ONE boot of slot b and restart into it
  rearm             while on b: give b one more boot (so a planned restart stays on b)
  home              back to the home slot now (bootloader fallback when b is used up, else qbootctl -s a)
  promote           keep the kernel that is on b: copy boot_b -> boot_a (boot_a backed up first)
  mark-if-home      (systemd) mark the running slot successful ONLY if it is the home slot

Log: /var/log/abtest.log
"""
import datetime
import glob
import hashlib
import os
import struct
import subprocess
import sys
import time
import uuid
import zlib

HOME_FILE = '/etc/ab-home-slot'
LOG = '/var/log/abtest.log'
BACKUP_DIR = '/var/lib/abtest/backups'
FIXED_SHA_FILE = '/usr/local/lib/abtest/qbootctl-fixed.sha256'
MARKER = uuid.UUID('77036cd4-03d5-42bb-8ed1-37e5a88baa34')  # type GUID ABL gives every INACTIVE slot partition
BYPART = '/dev/disk/by-partlabel'
LUN_ATTR = glob.glob('/sys/bus/platform/drivers/ufshcd-qcom/*/attributes/boot_lun_enabled')
BOOT_PART_BYTES = 64 * 1024 * 1024
SLOTS = ('a', 'b')


def log(msg):
    line = f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S} {msg}"
    print(line)
    try:
        with open(LOG, 'a') as f:
            f.write(line + '\n')
    except OSError:
        pass


def die(msg, code=1):
    log('ABORT: ' + msg)
    sys.exit(code)


def run(cmd, check=True):
    log('run: ' + ' '.join(cmd))
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out = p.stdout.strip()
    if out:
        for l in out.splitlines():
            log('  | ' + l)
    if check and p.returncode != 0:
        die(f"{cmd[0]} failed (exit {p.returncode})")
    return p.returncode, out


# ---------------------------------------------------------------- state readers (all read-only)
def home_slot():
    try:
        s = open(HOME_FILE).read().strip().lstrip('_')
    except OSError:
        s = 'a'
    return s if s in SLOTS else 'a'


def other(slot):
    return 'b' if slot == 'a' else 'a'


def current_slot():
    for tok in open('/proc/cmdline').read().split():
        if tok.startswith('androidboot.slot_suffix='):
            return tok.split('=', 1)[1].lstrip('_')
    die('no androidboot.slot_suffix in /proc/cmdline')


def part_dev(name):
    return os.path.realpath(os.path.join(BYPART, name))


def disk_of(partdev):
    return partdev.rstrip('0123456789')


def boot_lun():
    if not LUN_ATTR:
        return None
    return int(open(LUN_ATTR[0]).read().strip(), 0)


def _hdr(b):
    f = struct.unpack('<8sIIIIQQQQ16sQIII', b[:92])
    if f[0] != b'EFI PART':
        return None
    return dict(cur=f[5], bak=f[6], pe_lba=f[10], npe=f[11], pesz=f[12], pecrc=f[13])


def _table(f, bs, h):
    f.seek(h['pe_lba'] * bs)
    blob = f.read(h['npe'] * h['pesz'])
    ents = {}
    for i in range(h['npe']):
        e = blob[i * h['pesz']:(i + 1) * h['pesz']]
        if e == bytes(len(e)):
            continue
        name = e[56:128].decode('utf-16-le').rstrip('\0')
        ents[name] = (uuid.UUID(bytes_le=e[:16]), struct.unpack('<Q', e[48:56])[0])
    return ents, (zlib.crc32(blob) & 0xffffffff) == h['pecrc']


def gpt_entries(disk):
    """-> (primary entries, backup entries, primary crc ok, backup crc ok)"""
    with open(disk, 'rb') as f:
        bs = 4096
        f.seek(bs)
        p = _hdr(f.read(bs))
        if not p:
            bs = 512
            f.seek(bs)
            p = _hdr(f.read(bs))
        if not p:
            die(f'{disk}: no GPT')
        P, pok = _table(f, bs, p)
        f.seek(p['bak'] * bs)
        b = _hdr(f.read(bs))
        B, bok = _table(f, bs, b) if b else ({}, False)
    return P, B, pok, bok


def slot_state():
    """A/B state of the boot_a/boot_b entries (ABL decides slots from these)."""
    disk = disk_of(part_dev('boot_a'))
    P, B, pok, bok = gpt_entries(disk)
    st = {'disk': disk, 'crc_ok': pok and bok, 'backup_matches': P == B, 'lun': boot_lun()}
    for s in SLOTS:
        t, a = P['boot_' + s]
        ab = (a >> 48) & 0xff
        st[s] = dict(real_guid=(t != MARKER), pri=ab & 3, act=(ab >> 2) & 1, retry=(ab >> 3) & 7,
                     succ=(ab >> 6) & 1, unboot=(ab >> 7) & 1)
    return st


def img_sha(name, nbytes=BOOT_PART_BYTES):
    h = hashlib.sha256()
    with open(part_dev(name), 'rb') as f:
        left = nbytes
        while left > 0:
            chunk = f.read(min(1 << 20, left))
            if not chunk:
                break
            h.update(chunk)
            left -= len(chunk)
    return h.hexdigest()


def has_boot_magic(name):
    with open(part_dev(name), 'rb') as f:
        return f.read(8) == b'ANDROID!'


def qbootctl_path():
    for p in ('/usr/local/bin/qbootctl', '/usr/bin/qbootctl'):
        if os.path.exists(p):
            return p
    die('qbootctl not installed')


def qbootctl_is_fixed():
    try:
        want = open(FIXED_SHA_FILE).read().split()[0]
    except (OSError, IndexError):
        return None
    return hashlib.sha256(open(qbootctl_path(), 'rb').read()).hexdigest() == want


def fmt_slot(s, d):
    role = 'real GUIDs' if d['real_guid'] else 'inactive marker'
    return (f"slot {s}: active={d['act']} successful={d['succ']} tries_left={d['retry']} unbootable={d['unboot']} "
            f"priority={d['pri']} ({role})")


# ---------------------------------------------------------------- checks
def expect(st, slot, **want):
    """-> list of mismatches for slot against want (keys of the slot dict, plus lun / real_guid)."""
    bad = []
    for k, v in want.items():
        got = st['lun'] if k == 'lun' else st[slot][k]
        if got != v:
            bad.append(f"{slot}.{k}={got} (wanted {v})")
    return bad


def preflight_switch_tools():
    fixed = qbootctl_is_fixed()
    if fixed is False:
        die('qbootctl is NOT the fixed build (an apk upgrade put the buggy one back?). The stock one bricks the '
            'phone on -s. Reinstall: sudo install -m755 /path/to/your/fixed/qbootctl /usr/bin/qbootctl')
    if fixed is None:
        log(f'warning: {FIXED_SHA_FILE} missing, cannot prove qbootctl is the fixed build')
    if not os.path.exists('/dev/bsg/ufs-bsg0'):
        die('/dev/bsg/ufs-bsg0 missing: this kernel cannot switch the UFS boot LUN (CONFIG_SCSI_UFS_BSG); a slot '
            'switch from Linux would be half done. Use fastboot --set-active from the PC instead.')


def settle():
    subprocess.run(['udevadm', 'settle', '-t', '30'])
    for _ in range(30):
        if all(os.path.exists('/dev/disk/by-partlabel/' + n + '_' + x) for n in ('tz', 'boot', 'abl') for x in 'ab'):
            return
        time.sleep(1)
    die('partition links /dev/disk/by-partlabel/*_a/_b missing after 30 s; not switching')


def switch_to(slot):
    """qbootctl -s SLOT, then prove the GPT shows exactly what ABL would have written."""
    preflight_switch_tools()
    # 2026-10-28: a write to boot_b (abtest flash) makes udev rebuild the LUN-4 by-partlabel links; qbootctl run
    # inside that window failed at tz_a after swapping half the pairs. Wait for udev, and never die before verifying.
    settle()
    rc, _ = run([qbootctl_path(), '-s', slot], check=False)
    settle()
    st = slot_state()
    bad = [f'qbootctl -s {slot} exit {rc}'] if rc else []
    bad += expect(st, slot, real_guid=True, act=1, succ=0, retry=1, unboot=0, lun=1 if slot == 'a' else 2)
    bad += expect(st, other(slot), real_guid=False, act=0)
    if not st['crc_ok']:
        bad.append('GPT CRC bad')
    if not st['backup_matches']:
        bad.append('backup GPT differs from primary')
    return st, bad


def verify_or_revert(slot, st, bad):
    if not bad:
        return st
    log('switch verification FAILED: ' + '; '.join(bad))
    back = current_slot()
    if slot != back:
        log(f'trying to put the tables back to slot {back} ...')
        st2, bad2 = switch_to(back)
        if bad2:
            die('tables still inconsistent after revert: ' + '; '.join(bad2) +
                '\nDO NOT REBOOT. Fix from the PC: fastboot --set-active=' + back + ' or the EDL GPT repair.')
        die(f'reverted, still on slot {back}; nothing changed. Investigate before trying again.')
    die('DO NOT REBOOT until the tables are repaired (fastboot --set-active / EDL GPT repair).')


def reboot(why):
    log('rebooting: ' + why)
    sys.stdout.flush()
    os.execvp('systemctl', ['systemctl', 'reboot'])


# ---------------------------------------------------------------- commands
def cmd_status(_args):
    cur, home = current_slot(), home_slot()
    st = slot_state()
    print(f"running on slot {cur}, home slot {home}, UFS boot LUN {st['lun']} "
          f"({'slot a' if st['lun'] == 1 else 'slot b' if st['lun'] == 2 else '?'})")
    print(fmt_slot('a', st['a']))
    print(fmt_slot('b', st['b']))
    sa, sb = img_sha('boot_a'), img_sha('boot_b')
    print(f"boot_a image {sa[:16]}  boot_b image {sb[:16]}  -> {'SAME image' if sa == sb else 'DIFFERENT images'}")
    fixed = qbootctl_is_fixed()
    print(f"qbootctl: {qbootctl_path()} {'fixed build' if fixed else 'UNVERIFIED' if fixed is None else 'BUGGY STOCK BUILD'}"
          f", ufs-bsg {'present' if os.path.exists('/dev/bsg/ufs-bsg0') else 'MISSING'}")
    if not st['crc_ok'] or not st['backup_matches']:
        print('WARNING: GPT tables inconsistent (CRC or backup mismatch)')
    test = other(home)
    warn = []
    if st[home]['succ'] != 1:
        warn.append(f"home slot {home} is NOT marked successful; run: abtest mark-if-home (while on {home})")
    if st[test]['succ'] == 1:
        warn.append(f"test slot {test} is marked successful (a dead kernel there would boot forever); "
                    f"the next 'abtest go' clears it - until then never let the bootloader fall back to {test}")
    if fixed is False:
        warn.append('qbootctl is the buggy stock build; never run -s with it')
    for w in warn:
        print('WARNING: ' + w)
    if not warn:
        if cur == home:
            how = ('parked (unbootable)' if st[test]['unboot'] else
                   f"armed for {st[test]['retry']} boot(s)" if st[test]['retry'] else 'used up (not bootable)')
            print(f"OK: home slot {home} is successful; test slot {test} is {how}.")
        else:
            left = st[cur]['retry']
            print(f"OK: on the TEST slot {cur}. Tries left {left}: "
                  + ("the next restart (or a 10 s power hold) returns to slot " + home + " by itself."
                     if left == 0 else f"the next restart stays on {cur}; after that it returns to {home}."))


def cmd_flash(args):
    if not args:
        die('usage: abtest flash IMG')
    img = args[0]
    home = home_slot()
    test = other(home)
    try:
        data = open(img, 'rb').read()
    except OSError as e:
        die(f'cannot read {img}: {e}')
    if data[:8] != b'ANDROID!':
        die(f'{img} is not an Android boot image (no ANDROID! magic)')
    if len(data) > BOOT_PART_BYTES:
        die(f'{img} is {len(data)} bytes, bigger than the boot partition ({BOOT_PART_BYTES})')
    want = hashlib.sha256(data).hexdigest()
    before = img_sha('boot_' + test)
    log(f'flashing {img} ({len(data)} bytes, sha256 {want[:16]}) to boot_{test} (was {before[:16]})')
    dev = part_dev('boot_' + test)
    with open(dev, 'r+b') as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    got = img_sha('boot_' + test, len(data))
    if got != want:
        die(f'read-back mismatch on {dev}: {got[:16]} != {want[:16]} - do NOT boot slot {test}')
    settle()
    log(f'boot_{test} verified. Next: abtest go  (one boot of slot {test}; any restart returns to {home})')
    print('reminder: the rootfs is shared, so this kernel needs its modules under /lib/modules/<its version>')


def cmd_go(args):
    cur, home = current_slot(), home_slot()
    test = other(home)
    if cur != home:
        die(f'you are on {cur}, not the home slot {home}. Use "abtest rearm" to boot {test} once more, '
            f'or "abtest home" first.')
    st = slot_state()
    if st[home]['succ'] != 1:
        log(f'home slot {home} not marked successful yet; marking it now (we are running it)')
        run([qbootctl_path(), '-m', home])
        st = slot_state()
        if st[home]['succ'] != 1:
            die(f'could not mark {home} successful; no safety net, not switching')
    if not has_boot_magic('boot_' + test):
        die(f'boot_{test} holds no boot image; abtest flash IMG first')
    if not st[home]['real_guid'] or st[test]['real_guid']:
        die('GPT type GUIDs do not match the running slot; not touching anything (check with the PC tools)')
    st, bad = switch_to(test)
    st = verify_or_revert(test, st, bad)
    log(f'slot {test} armed for ONE boot (successful=0, tries=1); slot {home} stays successful as the fallback')
    if '--no-reboot' in args:
        log('not rebooting (--no-reboot). The next restart boots ' + test + ' once.')
        return
    reboot(f'one try of slot {test}')


def cmd_rearm(args):
    cur, home = current_slot(), home_slot()
    if cur == home:
        die(f'you are on the home slot {home}; "abtest go" is the command to try {other(home)}')
    st, bad = switch_to(cur)
    verify_or_revert(cur, st, bad)
    log(f'slot {cur} re-armed: the next restart stays on {cur} (one more try); after that it returns to {home}')


def cmd_home(args):
    cur, home = current_slot(), home_slot()
    if cur == home:
        log(f'already on the home slot {home}')
        return
    st = slot_state()
    if st[home]['succ'] != 1 and st[home]['retry'] == 0:
        die(f'home slot {home} is neither successful nor has tries left; fix from the PC (fastboot --set-active={home})')
    if st[cur]['succ'] == 0 and st[cur]['retry'] == 0:
        log(f'slot {cur} is used up: the bootloader itself will mark it unbootable and switch back to {home}')
        if '--no-reboot' in args:
            return
        reboot(f'bootloader fallback {cur} -> {home}')
    st, bad = switch_to(home)
    verify_or_revert(home, st, bad)
    log(f'switched to {home} (one try, it gets marked successful again once it is up)')
    if '--no-reboot' in args:
        return
    reboot(f'back to home slot {home}')


def cmd_promote(_args):
    home = home_slot()
    test = other(home)
    sa, sb = img_sha('boot_a'), img_sha('boot_b')
    if sa == sb:
        die('boot_a and boot_b already hold the same image; nothing to promote')
    if not has_boot_magic('boot_' + test):
        die(f'boot_{test} holds no boot image')
    os.makedirs(BACKUP_DIR, exist_ok=True)
    bak = os.path.join(BACKUP_DIR, f"boot_{home}-{datetime.datetime.now():%Y%m%d-%H%M%S}.img")
    with open(part_dev('boot_' + home), 'rb') as f, open(bak, 'wb') as o:
        o.write(f.read(BOOT_PART_BYTES))
    log(f'boot_{home} backed up to {bak}')
    src = open(part_dev('boot_' + test), 'rb').read(BOOT_PART_BYTES)
    with open(part_dev('boot_' + home), 'r+b') as f:
        f.write(src)
        f.flush()
        os.fsync(f.fileno())
    if img_sha('boot_' + home) != hashlib.sha256(src).hexdigest():
        die(f'read-back mismatch on boot_{home}! Restore: dd if={bak} of={part_dev("boot_" + home)} bs=1M conv=fsync')
    log(f'boot_{home} now holds the kernel from boot_{test}. Undo: dd if={bak} of={part_dev("boot_" + home)} bs=1M conv=fsync')
    if current_slot() != home:
        print(f'next: abtest home  (back to {home}, now running the promoted kernel)')


def cmd_mark_if_home(_args):
    cur, home = current_slot(), home_slot()
    if cur != home:
        log(f'on TEST slot {cur}: NOT marking it successful (home is {home}). '
            f'A restart or a 10 s power hold returns to {home}. "abtest rearm" = one more boot here.')
        return
    rc, _ = run([qbootctl_path(), '-m', cur], check=False)
    sys.exit(rc)


CMDS = {'status': cmd_status, 'flash': cmd_flash, 'go': cmd_go, 'rearm': cmd_rearm, 'home': cmd_home,
        'promote': cmd_promote, 'mark-if-home': cmd_mark_if_home}


def main():
    argv = sys.argv[1:]
    cmd = argv[0] if argv else 'status'
    if cmd in ('-h', '--help', 'help'):
        print(__doc__)
        return
    if cmd not in CMDS:
        die(f'unknown command {cmd}; see abtest help')
    if os.geteuid() != 0:
        os.execvp('sudo', ['sudo', sys.executable, '-I', os.path.realpath(__file__)] + argv)
    CMDS[cmd](argv[1:])


if __name__ == '__main__':
    main()

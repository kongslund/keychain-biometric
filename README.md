# keychain-biometric

A TouchID-gated alternative to the macOS `security` CLI — read, write, delete, and list Keychain passwords with mandatory biometric authentication.


## Motivation

macOS ships with a `security` command-line tool that can read and write Keychain items from scripts. Passwords created with it can be read again by it with no authentication requirement. This means that a script (or any process running as you) can use `security` to retrieve a stored password silently, with no prompt at all.

`keychain-biometric` is a drop-in replacement that closes that gap. Every operation — read, write, delete, list — requires you to authenticate via TouchID, with automatic fallback to your macOS login password when biometrics are unavailable. No password leaves the tool until authentication succeeds.

```
$ keychain-biometric read --service myservice --account user@example.org
TouchID — "read password for 'myservice' (user@example.org)"
[✓ authenticated]
hunter2
```


## Installation

**macOS 13 Ventura or later** and Xcode command-line tools (`xcode-select --install`) are required.

```bash
git clone https://github.com/kongslund/keychain-biometric.git
cd keychain-biometric
make build
make install      # installs to /usr/local/bin using sudo
```

`make install` copies the binary, sets ownership to `root:wheel`, and marks it system-immutable with `chflags schg` — see [Security](#security) for why.

To remove:

```bash
make uninstall
```


## Quick start

Store a password:

```bash
keychain-biometric write --service myservice --account user@example.org
# TouchID prompt appears, then:
# Password: ████████
# Password saved to keychain.
```

Retrieve it:

```bash
keychain-biometric read --service myservice --account user@example.org
# TouchID prompt appears, then the password is printed to stdout (no newline)
```


## Commands

### `read`

Retrieve a password and print it to stdout (no trailing newline).

```bash
keychain-biometric read --service <service> --account <account>
```

### `write`

Store or update a password. Reads from stdin if piped; prompts interactively otherwise. Authentication happens first, then the password is read.

```bash
# Interactive (hidden prompt)
keychain-biometric write --service <service> --account <account>

# Piped
echo 'secret' | keychain-biometric write --service <service> --account <account>

# With a custom label (shown in Keychain Access.app)
keychain-biometric write --service myservice --account user@example.org \
  --label "My service password for user@example.org"
```

### `delete`

Remove a password from the Keychain.

```bash
keychain-biometric delete --service <service> --account <account>
```

### `list`

List stored entries (service and account only — no passwords).

```bash
keychain-biometric list
keychain-biometric list --service myservice
```

Output is tab-separated `service<TAB>account`, one entry per line.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Authentication failed or cancelled |
| 2 | Keychain item not found |
| 3 | Keychain operation error |
| 4 | Invalid arguments |

All error messages go to **stderr**. Stdout is reserved for password output (`read`) and entry listing (`list`).

## Use Case Example: OfflineIMAP

[OfflineIMAP](https://github.com/OfflineIMAP/offlineimap3) reads/syncs your IMAP mailboxes.

Here's how to configure OfflineIMAP to retrieve an account password using keychain-biometric:

1. Create the Python file `~/.offlineimap.py`. It defines a `get_password` function that uses `keychain-biometric`.
   ```python
   import subprocess
   
   def get_password(account):
       return subprocess.check_output(
           ["/usr/local/bin/keychain-biometric", "read", "--service", "offlineimap", "--account", account],
           encoding='utf-8'
       ).strip()
   ```
2. Create `~/.offlineimaprc`. Notice that `pythonfile` points to the Python file, and that `remotepasseval` calls the `get_password` function.
   ```ini
   [general]
   pythonfile = ~/.offlineimap.py
   accounts = MyAccount
   
   [Account MyAccount]
   localrepository = MyAccount_Local
   remoterepository = MyAccount_Remote
   
   [Repository MyAccount_Local]
   type = Maildir
   localfolders = ~/MailBackup/MyAccount
   
   [Repository MyAccount_Remote]
   type = IMAP
   remotehost = imap.example.org
   remoteuser = user@example.org
   remotepasseval = get_password("user@example.org")
   sslcacertfile = OS-DEFAULT
   ```
3. Store the password once for the `user@example.org` account:
   ```bash
   keychain-biometric write --service offlineimap --account user@example.org
   ```
4. From that point on, every `offlineimap` run will trigger a TouchID prompt before syncing.

## Use Case Example: Rclone

[Rclone](https://rclone.org) is a command-line program to manage files on cloud storage.

Rclone supports [configuration encryption](https://rclone.org/docs/#configuration-encryption). Without it, your cloud service credentials sit in a plaintext config file. With encryption enabled, you need a password on every run — and keychain-biometric lets you store that password securely and gate access behind TouchID instead of keeping it in plaintext in your shell config.

Here's how to enable configuration encryption and retrieve the password using keychain-biometric:

1. Enable configuration encryption. If your config is already encrypted (`rclone config show` will prompt for a password if so), skip to step 2.
   
   Run `rclone config`.
   ```
   $ rclone config
   Current remotes:
   
   e) Edit existing remote
   n) New remote
   d) Delete remote
   s) Set configuration password
   q) Quit config
   e/n/d/s/q>
   ```
   Press `s` to Set configuration password

   ```
   e/n/d/s/q> s
   Your configuration is not encrypted.
   If you add a password, you will protect your login information to cloud services.
   a) Add Password
   q) Quit to main menu
   a/q> a
   Enter NEW configuration password:
   password:
   Confirm NEW password:
   password:
   Password set
   Your configuration is encrypted.
   c) Change Password
   u) Unencrypt configuration
   q) Quit to main menu
   c/u/q>
   ```
2. Store the configuration password using keychain-biometric:
   ```bash
   keychain-biometric write --service rclone --account myaccount
   ```
3. Instruct Rclone to use keychain-biometric to read the password:

   ```bash
   export RCLONE_PASSWORD_COMMAND="keychain-biometric read --service rclone --account myaccount"
   ```
   Tip: you can add this line to your shell config, e.g. `~/.zshrc`.

From that point on, every `rclone` command that requires the config password will trigger a TouchID prompt before accessing your cloud storage.

## Security

**Authentication model.** TouchID (or macOS login password) is enforced by this tool at the application layer using `LAContext`. It is not enforced by the Keychain itself — no `SecAccessControl` biometric policy is attached to the stored items, because that would require Apple code signing.

In practice this means:

- Only `keychain-biometric` is in the item's Keychain access control list (ACL). Another process trying to read the item directly would get a macOS permission dialog (or be denied silently in a non-interactive context).
- The biometric gate is this binary. If an attacker could replace it with a trojaned version that skips authentication, they could retrieve passwords silently. `make install` therefore marks the binary **system-immutable** (`chflags schg`), preventing non-root processes from replacing or deleting it.
- Items are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: they are never synced to iCloud Keychain and are not migrated to a new device via encrypted backup.

**Password output.** The password is printed to stdout with no trailing newline and never touches stderr. Error messages never appear on stdout.

**Memory.** Password `Data` buffers are zeroed immediately after use.

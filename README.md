# macos-emudhra-fix

eMudhra's intermediate CAs were compromised. [Apple blocked the 12 certificates](https://support.apple.com/en-us/149555) in Safari, Mail and anything on its frameworks — but **not** in `curl`, `git`, `python3`, `ruby`, `perl` or `openssl`. Those validate against `/etc/ssl/cert.pem`, which has no block list and no revocation checking. Apple will fix it "in a future macOS update"; no date.

Until then, remove the roots yourself. Every command below is copied verbatim from Apple's advisory, **[About the compromised eMudhra intermediate CAs](https://support.apple.com/en-us/149555)** (23 Oct 2026) — read it first if you'd rather not take this repo's word for anything.

## 1. Are you affected?

```bash
openssl crl2pkcs7 -nocrl -certfile /etc/ssl/cert.pem | openssl pkcs7 -print_certs -noout | grep -E 'emSign ECC Root CA - G3|AAA Certificate Services'
```

*Reads every certificate in the system bundle and prints just their names — `crl2pkcs7` wraps the file into a container `openssl` can enumerate, `-noout` suppresses the certificate bodies so you get names only, and `grep` keeps the two you care about. Nothing is modified.*

**Nothing printed** = already clean, stop here. Otherwise keep going.

## 2. Back up

```bash
[ -e /etc/ssl/cert.pem.orig ] || sudo cp -p /etc/ssl/cert.pem /etc/ssl/cert.pem.orig
```

*Copies the bundle to `cert.pem.orig`, preserving permissions and timestamps (`-p`). The `[ -e … ] ||` guard means it only copies when no backup exists — so re-running this later can't overwrite your pristine backup with an already-edited file.*

## 3. Remove `emSign ECC Root CA - G3`

```bash
t=$(mktemp) && awk -v s='=== /C=IN/OU=emSign PKI/O=eMudhra Technologies Limited/CN=emSign ECC Root CA - G3' '/^(===|###) /{skip=0} $0==s{skip=1} !skip' /etc/ssl/cert.pem > "$t" && [ -s "$t" ] && sudo install -m 0644 -o root -g wheel "$t" /etc/ssl/cert.pem; rm -f "$t"
```

*The bundle is a flat list where each certificate is introduced by a `===` header line naming its subject. `awk` copies it to a scratch file, flipping `skip` on when it hits the header matching that exact subject and off again at the next header — so the one certificate is dropped and everything else passes through. `[ -s "$t" ]` refuses to continue if the result came out empty, then `install` replaces the original atomically with correct ownership (`root:wheel`, `0644`). The scratch file is deleted either way. `install` rather than `cp` because it writes a temp file and renames it over the target — no process can catch the trust store half-written.*

**Silence means it worked.**

## 4. Optional: remove `AAA Certificate Services`

Six of the 12 blocked intermediates are Sectigo cross-signed and chain here instead, so step 3 alone doesn't stop them. But this is the legacy Comodo root, still a valid anchor for plenty of unrelated sites — removing it may break them in these tools until Apple's update lands. Your call; step 6 undoes it.

```bash
t=$(mktemp) && awk -v s='=== /C=GB/ST=Greater Manchester/L=Salford/O=Comodo CA Limited/CN=AAA Certificate Services' '/^(===|###) /{skip=0} $0==s{skip=1} !skip' /etc/ssl/cert.pem > "$t" && [ -s "$t" ] && sudo install -m 0644 -o root -g wheel "$t" /etc/ssl/cert.pem; rm -f "$t"
```

*Identical to step 3 — only the subject it matches differs.*

## 5. Verify

```bash
openssl crl2pkcs7 -nocrl -certfile /etc/ssl/cert.pem | openssl pkcs7 -print_certs -noout | grep -E 'emSign ECC Root CA - G3|AAA Certificate Services'
```

*Step 1 again, now as a check on your work: it lists whichever root is still present.*

**Nothing printed** = done. If it errors instead, the file is damaged — restore the backup (step 6) and start over.

## 6. Undo

```bash
sudo cp -p /etc/ssl/cert.pem.orig /etc/ssl/cert.pem
```

*Copies your step 2 backup back over the live bundle, restoring both roots. A plain `cp` is fine here where step 3 used `install`: the backup already carries `root:wheel` and `0644` (so `-p` propagates them, no flags needed), and this is a manual recovery rather than a live swap, so `install`'s write-then-rename atomicity buys nothing.*

---

**Re-run step 1 after a macOS update.** An update can replace `cert.pem` with Apple's current version and put the roots back. If it does, `sudo rm /etc/ssl/cert.pem.orig` and repeat from step 2. Once the update carrying Apple's own fix lands, you're done for good.

Note that Apple's fix will almost certainly drop `emSign ECC Root CA - G3` but **keep** `AAA Certificate Services` — it anchors too much of the public web to remove. If you did step 4, expect that root to come back and stay back; that's Apple's call, not a regression.

**Homebrew, certifi, Node and Go carry their own bundles** that `/etc/ssl/cert.pem` doesn't touch. Homebrew's is already clean; for anything else, ask the vendor.

Source: [Apple, 23 Oct 2026](https://support.apple.com/en-us/149555). If we disagree, Apple wins. [MIT](LICENSE) — no warranty, read commands before running them.

# macos-emudhra-fix

Eight eMudhra intermediate CAs have private keys anyone can compute. [Apple blocked the resulting 12 certificates](https://support.apple.com/en-us/149555) in Safari, Mail and anything on its frameworks — but **not** in `curl`, `git`, `python3`, `ruby`, `perl` or `openssl`. Those validate against `/etc/ssl/cert.pem`, which carries no block list and no revocation checking. Apple will fix it "in a future macOS update"; no date.

Until then, remove both roots yourself (steps 3 and 4). Every command below is copied verbatim from Apple's advisory, **[About the compromised eMudhra intermediate CAs](https://support.apple.com/en-us/149555)** (23 Oct 2026) — read it first if you'd rather not take this repo's word for anything.

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

*The bundle is a flat list where each certificate is introduced by a `===` header line naming its subject. `awk` copies it to a scratch file, flipping `skip` on when it hits the header matching that exact subject and off again at the next header — so the one certificate is dropped and everything else passes through. `[ -s "$t" ]` refuses to continue if the result came out empty, then `install` replaces the original with correct ownership (`root:wheel`, `0644`) — `install` rather than `cp` because it writes a temp file and renames it over the target, so no process can catch the trust store half-written. The scratch file is deleted either way.*

**Silence means it worked.**

## 4. Recommended: remove `AAA Certificate Services`

Six of the 12 blocked intermediates are Sectigo cross-signed and chain here instead, so **step 3 alone leaves half the problem in place**.

Apple labels this optional and leaves it to administrators. This repo recommends doing it: Chrome and Firefox dropped this root's TLS trust in April 2025, Ubuntu and `certifi` have removed it over this incident, and testing found nothing that breaks — [details below](#is-removing-aaa-certificate-services-safe). Skip it only if you have a specific legacy dependency on that root.

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

*Copies your step 2 backup back over the live bundle, restoring both roots. A plain `cp` is fine here where step 3 used `install`: the backup already carries `root:wheel` and `0644` (so `-p` propagates them), and this is a manual recovery rather than a live swap, so write-then-rename atomicity buys nothing.*

---

**Re-run step 1 after a macOS update** — an update can replace `cert.pem` with Apple's current version and put the roots back. If it does, `sudo rm /etc/ssl/cert.pem.orig` and repeat from step 2.

For machines you won't be watching, [`watcher/`](watcher/) has an optional LaunchAgent that checks daily and notifies you. Read-only, no `sudo`, and it only looks for the unambiguous root — see its README for why.

<details>
<summary><b>What actually happened</b></summary>

<br>

The keys weren't leaked — they were **computable**. Eight eMudhra intermediates generated in an April 2025 key ceremony have P-384 private keys that are integers below 256, derivable by anyone holding the public certificate. Six issue TLS certificates and two sign code; Sectigo cross-signed all eight, so 16 certificates are affected and Apple blocked the 12 TLS ones.

| | |
|---|---|
| 30 Apr 2025 | eMudhra generates the eight intermediates in a *key ceremony* — the audited, witnessed, HSM-based procedure whose entire purpose is to guarantee the private key is unguessable |
| 17 Oct 2026 | Researcher reports it |
| 18 Oct 2026 | eMudhra revokes all eight |
| 19 Oct 2026 | Sectigo revokes the cross-signs |
| 20 Oct 2026 | Mozilla emergency-distrusts `emSign ECC Root CA - G3` |
| 23 Oct 2026 | Apple publishes its advisory |

No certificate from these intermediates was ever logged to Certificate Transparency — so no CT-enforcing client could have been attacked. eMudhra has since announced it is leaving the global TLS business.

Revocation already happened — and doesn't help here. None of these tools check revocation against this bundle, which is the whole reason the file needs editing. The two code-signing intermediates are outside `cert.pem`'s scope entirely.

</details>

<details>
<summary><b>Is removing <code>AAA Certificate Services</code> safe?</b></summary>

<br>

Safer than Apple's cautious wording implies. **Chrome and Firefox removed this root's TLS trust on 15 April 2025**, under policy capping root lifetime at 15 years past key generation. Apple is the outlier — it still shipped the root in its December 2025 list. Ubuntu removed it over this incident, and `certifi` dropped it in 2025.4.26. Step 4 brings your bundle in line with where the rest of the ecosystem already is.

Its only remaining job is cross-signing the **USERTrust** roots for very old clients (iOS 3, macOS 10.4, Android 2.3, Firefox 1). `USERTrust RSA` and `USERTrust ECC` are independent anchors already in your bundle, so modern Sectigo chains terminate there and never consult AAA — and nothing else in the bundle is anchored to it.

Spot-checked against Sectigo-served sites with `/usr/bin/curl` and `/usr/bin/python3` using an AAA-less bundle: no failures. Residual risk is a server offering only a chain ending at AAA — rare, and that root expires 2028-12-31 regardless. Step 6 undoes it.

</details>

<details>
<summary><b>Can I tell whether these certificates were used against me?</b></summary>

<br>

**Partly — and the global answer is reassuring.** No certificate from the six TLS intermediates was ever logged to Certificate Transparency, going back to their creation in April 2025. CT-enforcing clients — Chrome, Firefox, Edge, Safari — reject certificates without SCTs, so they could not have been attacked. For browser traffic the question is settled.

**For the tools this repo is about, it isn't.** `curl`, `git` and `python3` don't enforce CT, so a certificate minted from a computable key and never submitted to a log would work against them and leave no trace. That gap is the same one that makes revocation useless here.

**And nothing local will tell you.** macOS keeps no record of which CA validated a past connection. `trustd` logs signature verifications with no certificate identity attached — and `trustd` is the Apple-framework path, which was never the exposed one. The exposed path logs nothing at all. There is no artifact to go looking for.

What the empty CT log does do is bound the risk: an attacker would have needed to find the weak keys independently before the 17 October disclosure, confine themselves to non-CT clients to stay invisible, and hold network position over your traffic. The alarming part of this incident is how trivially the keys fall out, not evidence that anyone used them.

</details>

<details>
<summary><b>What Apple's eventual fix will change</b></summary>

<br>

It will certainly drop `emSign ECC Root CA - G3`. Whether it also drops `AAA Certificate Services` is genuinely unclear — Apple kept that root months after Chrome and Mozilla dropped it, but this incident is new pressure. If it reappears after an update, that's Apple's call rather than a regression; re-apply step 4 if you still want it gone.

Once the update carrying Apple's own fix lands, you're done — no need to keep re-checking.

</details>

<details>
<summary><b>Other trust stores this doesn't touch</b></summary>

<br>

`/etc/ssl/cert.pem` only governs the tools shipped with macOS and the Xcode Command Line Tools. Homebrew formulas use `/opt/homebrew/etc/ca-certificates/cert.pem` (already clean, since it tracks Mozilla). Python's `requests` uses `certifi`, Node compiles its own root list, and Go carries another. Each needs updating on its own terms — for anything with a bundled trust store, Apple's advice is to ask the vendor.

</details>

---

Sources: [Apple advisory](https://support.apple.com/en-us/149555) (23 Oct 2026) — if anything here contradicts it, follow the page. Also [Sectigo](https://www.sectigo.com/resource-library/advisory-on-compromised-emudhra-intermediate-certificates), [Ubuntu](https://ubuntu.com/blog/emudhra-ca-compromise-fixes-available), [Sectigo on the AAA root](https://www.sectigo.com/resource-library/changes-to-root-ca-hierarchies-and-trust-status).

[MIT](LICENSE) — no warranty, read commands before running them.

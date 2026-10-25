#!/bin/sh
# Checks whether emSign ECC Root CA - G3 has reappeared in the system trust
# bundle, which happens when a macOS update replaces /etc/ssl/cert.pem with
# Apple's version. Read-only: it never modifies anything.
#
# Only this one root is checked, deliberately. See README.md.

BUNDLE="${EMUDHRA_BUNDLE:-/etc/ssl/cert.pem}"
ROOT='emSign ECC Root CA - G3'

found=$(openssl crl2pkcs7 -nocrl -certfile "$BUNDLE" 2>/dev/null \
        | openssl pkcs7 -print_certs -noout 2>/dev/null \
        | grep -c "$ROOT")

[ "$found" -eq 0 ] && exit 0

# A modal alert, not `display notification`: notifications from osascript are
# attributed to Script Editor and are silently dropped unless the user has
# granted it notification permission — osascript still exits 0, so the check
# would appear to succeed while telling you nothing.
osascript -e 'display alert "eMudhra cert watch" message "emSign ECC Root CA - G3 is back in /etc/ssl/cert.pem — a macOS update undid the fix.

github.com/mklasen/macos-emudhra-fix" as critical' >/dev/null 2>&1
exit 0

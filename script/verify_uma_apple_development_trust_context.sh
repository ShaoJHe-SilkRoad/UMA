#!/usr/bin/env bash
# Fails before package/install mutation when the executing process cannot use
# the exact Apple Development trust context required by the UMA Test channel.
set -euo pipefail
umask 077

readonly EXPECTED_IDENTITY="Apple Development: SHAOTING HE (5BN4FAQSUF)"
readonly EXPECTED_IDENTITY_SHA1="969A4720CA5D01F9B638233A2CD8A14736285397"
readonly EXPECTED_LEAF_SHA256="530C76742575129DF3F6C5571842337E6323042E51D91685E05D291D1861E200"
readonly EXPECTED_TEAM="C6TUZVJ6SJ"

mode=""
artifact=""
profiles=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) mode="${2:-}"; shift 2 ;;
        --artifact) artifact="${2:-}"; shift 2 ;;
        --profile) profiles+=("${2:-}"); shift 2 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done
[[ "$mode" == signing || "$mode" == verification ]] || exit 2
if [[ "$mode" == verification ]]; then
    [[ -d "$artifact" && ! -L "$artifact" ]] || exit 2
    for profile in ${profiles[@]+"${profiles[@]}"}; do
        [[ -f "$profile" && ! -L "$profile" ]] || exit 2
    done
else
    [[ -z "$artifact" && ${#profiles[@]} -eq 0 ]] || exit 2
fi

fail_context() {
    printf '%s\n' APPLE_SIGNING_TRUST_CONTEXT_UNAVAILABLE >&2
    exit 1
}

readonly uid="$(/usr/bin/id -u)"
readonly login_keychain="$HOME/Library/Keychains/login.keychain-db"
[[ "$uid" != 0 && -d "$HOME" && ! -L "$HOME" \
    && "$(/usr/bin/stat -f %u "$HOME")" == "$uid" ]] || fail_context

keychains="$(/usr/bin/security list-keychains -d user 2>/dev/null)" || fail_context
printf '%s\n' "$keychains" \
    | /usr/bin/tr -d '"' \
    | /usr/bin/sed 's/^[[:space:]]*//' \
    | /usr/bin/grep -Fx -q "$login_keychain" || fail_context

identities="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null)" || fail_context
identity_count="$(printf '%s\n' "$identities" \
    | /usr/bin/grep -F -c "\"$EXPECTED_IDENTITY\"" || true)"
[[ "$identity_count" == 1 ]] || fail_context
printf '%s\n' "$identities" \
    | /usr/bin/grep -F "\"$EXPECTED_IDENTITY\"" \
    | /usr/bin/grep -F -q "$EXPECTED_IDENTITY_SHA1" || fail_context

scratch="$(/usr/bin/mktemp -d /private/tmp/uma-apple-development-trust.XXXXXX)"
cleanup() { /bin/rm -rf -- "$scratch"; }
trap cleanup EXIT HUP INT TERM
readonly leaf="$scratch/apple-development.pem"
/usr/bin/security find-certificate -c "$EXPECTED_IDENTITY" -p > "$leaf" 2>/dev/null \
    || fail_context
[[ -s "$leaf" ]] || fail_context

leaf_fingerprint="$(/usr/bin/openssl x509 -in "$leaf" -noout -fingerprint -sha256 \
    | /usr/bin/awk -F= '{print $2}' | /usr/bin/tr -d ':' | /usr/bin/tr '[:lower:]' '[:upper:]')"
[[ "$leaf_fingerprint" == "$EXPECTED_LEAF_SHA256" ]] || {
    printf '%s\n' APPLE_SIGNING_IDENTITY_MISMATCH >&2
    exit 1
}
certificate_subject="$(/usr/bin/openssl x509 -in "$leaf" -noout -subject -nameopt RFC2253)"
certificate_issuer="$(/usr/bin/openssl x509 -in "$leaf" -noout -issuer -nameopt RFC2253)"
printf '%s\n' "$certificate_subject" | /usr/bin/grep -F -q "OU=$EXPECTED_TEAM" || {
    printf '%s\n' APPLE_SIGNING_IDENTITY_MISMATCH >&2
    exit 1
}
printf '%s\n' "$certificate_issuer" \
    | /usr/bin/grep -F -q 'CN=Apple Worldwide Developer Relations Certification Authority' \
    && printf '%s\n' "$certificate_issuer" | /usr/bin/grep -F -q 'OU=G3' \
    && printf '%s\n' "$certificate_issuer" | /usr/bin/grep -F -q 'O=Apple Inc.' \
    || {
        printf '%s\n' APPLE_SIGNING_CERTIFICATE_CHAIN_INVALID >&2
        exit 1
    }
/usr/bin/security verify-cert -c "$leaf" -p codeSign >/dev/null 2>&1 || {
    printf '%s\n' APPLE_SIGNING_CERTIFICATE_CHAIN_INVALID >&2
    exit 1
}

certificate_sha256() {
    local certificate="$1" format="${2:-DER}"
    /usr/bin/openssl x509 -inform "$format" -in "$certificate" \
        -noout -fingerprint -sha256 2>/dev/null \
        | /usr/bin/awk -F= '{print $2}' \
        | /usr/bin/tr -d ':' \
        | /usr/bin/tr '[:lower:]' '[:upper:]'
}

verify_signed_artifact_identity() {
    local target="$1" label="$2" signing authority signer_sha
    signing="$(/usr/bin/codesign -d --verbose=4 "$target" 2>&1)" || return 1
    authority="$(printf '%s\n' "$signing" \
        | /usr/bin/awk -F= '/^Authority=/{print $2; exit}')"
    [[ "$authority" == "$EXPECTED_IDENTITY" ]] || {
        printf '%s\n' APPLE_SIGNED_ARTIFACT_IDENTITY_MISMATCH >&2
        exit 1
    }
    /bin/rm -f -- "$scratch/$label-cert"* 2>/dev/null || true
    /usr/bin/codesign -d --extract-certificates="$scratch/$label-cert" \
        "$target" >/dev/null 2>&1 || return 1
    [[ -f "$scratch/$label-cert0" ]] || return 1
    signer_sha="$(certificate_sha256 "$scratch/$label-cert0")"
    [[ "$signer_sha" == "$EXPECTED_LEAF_SHA256" ]] || {
        printf '%s\n' APPLE_SIGNED_ARTIFACT_IDENTITY_MISMATCH >&2
        exit 1
    }
}

verify_profile_signer_membership() {
    local profile="$1" label="$2" decoded index certificate found=false fingerprint
    decoded="$scratch/$label-profile.plist"
    /usr/bin/security cms -D -i "$profile" > "$decoded" 2>/dev/null || return 1
    for index in $(/usr/bin/seq 0 15); do
        certificate="$scratch/$label-profile-cert-$index.der"
        if ! /usr/libexec/PlistBuddy -c "Print :DeveloperCertificates:$index" \
            "$decoded" > "$certificate" 2>/dev/null; then
            /bin/rm -f -- "$certificate"
            break
        fi
        fingerprint="$(certificate_sha256 "$certificate")"
        if [[ "$fingerprint" == "$EXPECTED_LEAF_SHA256" ]]; then found=true; fi
    done
    [[ "$found" == true ]] || {
        printf '%s\n' APPLE_PROFILE_SIGNER_MISMATCH >&2
        exit 1
    }
}

if [[ "$mode" == signing ]]; then
    smoke="$scratch/UMASigningTrustSmoke.app"
    /bin/mkdir -p "$smoke/Contents/MacOS"
    /bin/cp /usr/bin/true "$smoke/Contents/MacOS/UMASigningTrustSmoke"
    /bin/chmod 755 "$smoke/Contents/MacOS/UMASigningTrustSmoke"
    /usr/bin/plutil -create xml1 "$smoke/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleIdentifier -string com.silkrd.uma.test.signingtrustsmoke \
        "$smoke/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleExecutable -string UMASigningTrustSmoke \
        "$smoke/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundlePackageType -string APPL "$smoke/Contents/Info.plist"
    /usr/bin/plutil -insert CFBundleVersion -string 1 "$smoke/Contents/Info.plist"
    sign_output="$(/usr/bin/codesign --force --sign "$EXPECTED_IDENTITY" \
        --options runtime --timestamp=none "$smoke" 2>&1)" || fail_context
    verify_output="$(/usr/bin/codesign --verify --deep --strict --verbose=4 \
        "$smoke" 2>&1)" || {
        if printf '%s\n' "$verify_output" | /usr/bin/grep -F -q CSSMERR_TP_NOT_TRUSTED; then
            fail_context
        fi
        printf '%s\n' APPLE_SIGNING_SMOKE_VERIFICATION_FAILED >&2
        exit 1
    }
    verify_signed_artifact_identity "$smoke" smoke || {
        printf '%s\n' APPLE_SIGNING_SMOKE_VERIFICATION_FAILED >&2
        exit 1
    }
else
    verify_output="$(/usr/bin/codesign --verify --deep --strict --verbose=4 \
        "$artifact" 2>&1)" || {
        if printf '%s\n' "$verify_output" | /usr/bin/grep -F -q CSSMERR_TP_NOT_TRUSTED; then
            fail_context
        fi
        printf '%s\n' APPLE_SIGNATURE_VERIFICATION_FAILED >&2
        exit 1
    }
    verify_signed_artifact_identity "$artifact" artifact || {
        printf '%s\n' APPLE_SIGNATURE_VERIFICATION_FAILED >&2
        exit 1
    }
    profile_index=0
    for profile in ${profiles[@]+"${profiles[@]}"}; do
        verify_profile_signer_membership "$profile" "profile-$profile_index" || {
            printf '%s\n' APPLE_PROFILE_SIGNER_MISMATCH >&2
            exit 1
        }
        profile_index=$((profile_index + 1))
    done
fi

printf 'APPLE_DEVELOPMENT_TRUST_READY mode=%s uid=%s team=%s leaf_sha256=%s wwdr=G3\n' \
    "$mode" "$uid" "$EXPECTED_TEAM" "$EXPECTED_LEAF_SHA256"

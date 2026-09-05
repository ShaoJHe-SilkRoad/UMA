# UMA 0.14 M5-C SDK link configuration repair

## Authority and invalidation

Founder explicitly authorized the consolidated M5-C human qualification gate for
build 2026090501. Sections 13B and 15 require a new clean candidate if the SDK
discrepancy is an actual build configuration defect.

Starting source: `b72d666f28d06514bcf8c94c17ed6b9db385aacd`, tree
`a691497aad8c6baffdd74a5a1f78d9c88df7c355`, canonical branch
`codex/uma-0.14-surface-rebuild`. DEV_APFS and the clean source/index were verified.
All frozen RC file hashes, the exact entry set, and protected artifact manifests
matched before qualification. No app/provider/Host launch or Accuracy Sync occurred.

The original candidate is invalidated for release readiness. Its package remains
unchanged at `/Volumes/HE/DEV/UMA/Packages/uma-0.14-rc-20260905T001607Z`.
Original executable SHA-256:
`a6311ac4b797a6572c4a71b40d635404594356021019ec601f456efbd5f3101d`.
Original relay SHA-256:
`d98336bce57b6481dbd6c58c85ddb3d7c7ab81428f1d0b40feb4b789ef4b33e2`.

## Reproduced defect

Recorded compiler input uses MacOSX27.0.sdk, and intermediate objects record SDK
27.0. The actual native SwiftBuild link task instead passes SDK 14.0 to the linker
with minimum OS 14.0, producing the observed LC_BUILD_VERSION fields. This is not
an otool interpretation issue or a package-time binary rewrite. The retained build
products and packaged executables are byte-identical.

Independent scratch probes reproduce the difference between native task execution
and a direct replay. The native task omits SDKROOT/DEVELOPER_DIR from its environment;
the Clang link frontend's SDK selection therefore differs despite its --sysroot
argument. A direct replay inheriting SDKROOT concealed that difference. A shell
wrapper captures the actual unset environment; a Python wrapper itself acquired
SDKROOT and is not evidence of the native task's environment. The reproducible-link
flag alone does not cause it.

## Narrow repair

Pass the already discovered SDK path explicitly to Clang's link frontend using
Swift driver's `-Xclang-linker -isysroot` forwarding. This preserves the native
build backend, deployment target and release compilation. A separate minimal
native SwiftBuild probe verifies the actual linker invocation and resulting
minOS14 / SDK27 load command; it is not UMA live qualification.

The packager must reject a final executable whose actual SDK or minimum OS does
not match the selected SDK and canonical minimum system version. The checks
apply independently to the main app and relay before issuing the RC manifest.
The selected SDK/version and actual Mach-O values remain separate recorded facts.
No post-link binary rewriting or signing workaround is used.

Evidence lives outside frozen source/package under
`/Volumes/HE/DEV/UMA/Build/uma014-m5c/human-qualification/sdk-audit`.
The final repair, independent review, focused verification and replacement package
identity are recorded in that shared qualification evidence after convergence.

## Qualification boundaries

The next canonical RC build is 2026090502, selected only through
`Configuration/UMAProductVersion.plist`. No accepted product surface, provider
algorithm, preference/consent model or runtime lifecycle is redesigned.

Every byte-dependent gate must bind to the replacement candidate's new commit,
tree, package and executable hashes. The old candidate has no live evidence to
carry forward. Synthetic fixture/source analysis may be reused only when explicitly
classified as such.

The test account was absent and macOS required Founder-controlled administrator
authentication. Preparation does not establish a logged-in isolated GUI session,
install, migration, rollback, provider freshness, visual acceptance or soak PASS.
The once-only Accuracy Sync allowance remains unused. Passwords are never recorded.

No protected artifact mutation, production preference migration, Developer ID
signing, Keychain mutation, notarization, stapling, push or publication is authorized
by this repair. This record is not release acceptance.

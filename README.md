# 🥭 Mango Signer for iOS

The on-device version of [Mango Signer](https://github.com/MangoMods-code/Mango-Signer): sign and install iOS apps right on your iPhone with your own certificate.

## Status
Early development. Builds are made automatically by GitHub Actions on every push and posted under **Releases** as an unsigned `.ipa`. Sign it once with your certificate (for example with your Mango Signer server) and install it.

## What works now
- Add `.ipa` files from Files or "Open in Mango Signer"
- Add certificates (`.p12` + `.mobileprovision`); passwords are kept in the iPhone's Keychain
- Sign on the iPhone with zsign: change name, bundle ID and version, inject `.dylib` tweaks, remove extensions or device limits, enable Files app access
- Share signed `.ipa` files

## Building
The project is described in `project.yml` ([XcodeGen](https://github.com/yonaskolb/XcodeGen)). `.github/workflows/build.yml` generates the Xcode project, builds it unsigned on a macOS runner and publishes the `.ipa`.

## Credits
- [zsign](https://github.com/zhlynn/zsign) by zhlynn, MIT License (`ThirdParty/zsign/LICENSE`), lightly patched to run inside an app
- [OpenSSL](https://www.openssl.org) via [krzyzanowskim/OpenSSL](https://github.com/krzyzanowskim/OpenSSL), Apache License 2.0

## License
© 2026 MangoMods. **All rights reserved.** See [LICENSE](LICENSE). Third-party code keeps its own license.

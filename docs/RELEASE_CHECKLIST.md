# Release status / 发布状态

Version: **1.0.0 (22)** · tag **v1.0.0** · repository **jaysoncbh/MilkFamily**.

## Scope / 范围

- Public source, bilingual README, product screenshots and existing action previews.
- Separate release downloads for the arm64 app, test app, runtime pack and source ZIP.
- Source/documentation: MIT. Media: separate asset-rights policy; no third-party rights are claimed by the source license.
- Owner explicitly requested this public upload and the 1.0 release on 2026-10-19.

## Verification / 验证

- [x] Clean source boundary without development Git history, saves, usage logs or generation provenance.
- [x] All 32 character names and 34 action labels checked in both languages.
- [x] Existing gameplay, usage, recovery and runtime checks are available in `scripts/check.sh`.
- [x] Every packaged resource is validated by byte count and SHA-256 before signing.
- [x] Installation instructions identify the actual ad-hoc signature and Apple-supported per-app confirmation.
- Hosted CI: [macOS checks](https://github.com/jaysoncbh/MilkFamily/actions/workflows/checks.yml), tied to the actual release commit.
- Public output: [README](https://github.com/jaysoncbh/MilkFamily) and [v1.0.0 assets](https://github.com/jaysoncbh/MilkFamily/releases/tag/v1.0.0). Browser verification is recorded after upload.

## Remaining distribution work / 后续分发工作

- [ ] Developer ID signing, notarization and stapling. **1.0.0 is currently ad-hoc signed, not notarized.**
- [ ] Independent browser-download test on a clean Mac/account and the minimum supported OS.
- [ ] Intel build and hardware testing; current download is arm64 only.
- [ ] Physical multi-display hot-plug, full keyboard and screen-reader acceptance.
- [ ] Ongoing review of display/distribution permissions for individual media designs; replace/remove designs if their rights cannot be cleared.

本机检查、用户授权发布和Apple公证是不同状态。发布不会把未完成项自动标记通过，也不把源码MIT扩大为第三方素材授权。

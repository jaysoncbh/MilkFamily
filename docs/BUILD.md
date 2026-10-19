# Build / 构建

## Requirements / 环境

- macOS 14 or later; Apple Silicon is the locally checked architecture.
- Swift 6.0+ via Xcode Command Line Tools or Xcode. Local checks used Swift 6.2.3.
- Python 3.9+, macOS `codesign`, `iconutil` and `ditto`.
- No third-party Swift packages, API credentials or paid image service are needed.

## Source checks / 无素材源码检查

From the repository root / 在仓库根目录运行：

```sh
./scripts/check.sh
```

This builds debug and release, runs save recovery, local-usage and history checks, checks all 32 character names and the action translations, validates the runtime packer with fixtures, and checks release metadata and documentation links. It does not read your real usage logs or saves.

## Runtime assets / 运行素材

The source repository does not contain the full runtime artwork. Obtain an authorized runtime pack separately and extract it into `Resources/`, with `运行资源清单.json` directly inside. Alternatively set `NAIJIA_ASSET_ROOT` to its absolute root. Keep all relative paths inside the pack unchanged.

源码不包含完整美术。将另行提供且具备相应分发授权的运行包解压到 `Resources/`，使 `运行资源清单.json` 位于该目录第一层；也可使用下面的环境变量指向素材根目录。请勿改动素材包内部相对路径。

```sh
export NAIJIA_ASSET_ROOT="/absolute/path/to/authorized-runtime-assets"
./scripts/check.sh --with-assets
./scripts/build.sh release
```

For both regular and test editions / 同时构建正式版与测试版：

```sh
./scripts/build.sh all
```

Outputs go to ignored `dist/`: a ZIP containing a standalone `.app` and a package verification report for each edition. Every runtime file is checked by byte count and SHA-256 before packaging. Sources compile in a temporary directory; build-only debug paths are removed from exported binaries. The app contains its own runtime assets; the source workspace is not needed to run it.

输出位于被 Git 忽略的 `dist/`，包含内置独立 App 的 ZIP 和资源核对报告。打包前逐文件核对大小与 SHA-256。应用资源随包携带，运行时不依赖源码目录。

The packaging scripts **do not install, launch or quit apps, read or reset saves, or change preferences**. Generated apps use local ad-hoc signatures, not Developer ID notarization. The 1.0.0 download uses this ad-hoc signing method and is not notarized. See INSTALL.md for the per-app confirmation supported by macOS; no global security setting needs to be disabled.

脚本不会安装、打开或退出应用，不读写存档或偏好设置。1.0.0使用临时签名，未公证；首次打开方式与剩余发行验收见安装说明和发布检查表。

## Data isolation / 数据隔离

Regular edition: bundle `local.naijia.family`, data `~/Library/Application Support/奶家族/`.

Test edition: bundle `local.naijia.live`, data `~/Library/Application Support/奶家/`. Debug-only tools use a separate development save. Test Tokens never enter the real usage chart. Do not launch a build against your existing save merely to run checks; the automated checks use temporary fixtures.

## Version / 版本

`VERSION.json` is the version source for exported packages: **1.0.0, build 22**. The public release tag is `v1.0.0`. App Store distribution, Intel compatibility and notarization have not been certified by this preparation.

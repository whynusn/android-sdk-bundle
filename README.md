# android-sdk-bundle

受限网络环境的 Android 构建工具链镜像（Linux x86_64）。清单目标：补齐 APK 完整构建链路（资源编译 → dex → 对齐 → 签名）。

## 下载（raw 直链，无需登录）

```
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/OpenJDK17.tar.gz.part-00
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/OpenJDK17.tar.gz.part-01
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/OpenJDK17.tar.gz.part-02
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/build-tools_r34-linux.zip
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/build-tools_r36.1_linux.zip
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/platform-34_r03.zip
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/platform-37.0_r02.zip
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/platform-tools_r35.0.2-linux.zip
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/SHA256SUMS.txt
https://raw.githubusercontent.com/whynusn/android-sdk-bundle/main/SHA256SUMS-parts.txt
```

若 `raw.githubusercontent.com` 不可用，可用等价形式 `https://github.com/whynusn/android-sdk-bundle/raw/main/<文件名>`（301 跳转到 raw）。

## 校验与重组

```bash
sha256sum -c SHA256SUMS-parts.txt          # 校验 3 个 JDK 分片
cat OpenJDK17.tar.gz.part-00 OpenJDK17.tar.gz.part-01 OpenJDK17.tar.gz.part-02 > OpenJDK17.tar.gz
sha256sum -c SHA256SUMS.txt                # 校验全部成品（含重组后的 JDK）
```

重组后的 `OpenJDK17.tar.gz` 应为 193252603 字节，sha256 `3808d1d15e3ec6bd5b84057fb5d84c33d8a1536a258146bcea2e603fc726e08e`。

## 内容与解压摆放

| 文件 | 内容 | 解压后顶层目录 | 摆放位置 |
|---|---|---|---|
| OpenJDK17.tar.gz（3 分片） | Temurin JDK 17.0.20.1+1（含 javac） | `jdk-17.0.20.1+1/` | 任意目录，`JAVA_HOME` 指向它 |
| build-tools_r34-linux.zip | aapt2 / d8 / zipalign / apksigner | `android-14/` | 改名为 `<sdk>/build-tools/34.0.0/` |
| build-tools_r36.1_linux.zip | 同上，新版本（配 compileSdk 36/37） | `android-16/` | 改名为 `<sdk>/build-tools/36.1.0/` |
| platform-34_r03.zip | android.jar + framework.aidl | `android-34/` | `<sdk>/platforms/android-34/` |
| platform-37.0_r02.zip | android.jar + framework.aidl（compileSdk 37.0） | `android-37.0/` | `<sdk>/platforms/android-37.0/` |
| platform-tools_r35.0.2-linux.zip | adb / fastboot | `platform-tools/` | `<sdk>/platform-tools/` |

注意：build-tools 官方 zip 解压顶层目录名是内部代号（`android-14` / `android-16`），放入 SDK 时**必须改名**为版本号目录，AGP 才能识别。

## 摘要

- AGP 8.x 强制 JDK 17+：本包为 17.0.20.1+1，Gradle 8.5+ / 9.x 均可运行
- compileSdk 34 场景：build-tools_r34 + platform-34 即可出 APK
- compileSdk 37 场景（AGP 8.11+）：build-tools_r36.1 + platform-37.0
- cmdline-tools（sdkmanager）未包含：它需要联网到 dl.google.com 拉组件，在受限环境无用
- platform-tools 在容器内无法连接真机，仅用于构建链完整性

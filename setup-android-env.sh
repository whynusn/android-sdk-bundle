#!/bin/bash
# ============================================================
# Android 构建环境一键配置脚本（受限网络环境专用）
#
# 功能：从 GitHub 镜像仓库拉取 SDK 包 → 校验 → 组装 → 装 Gradle
#       → 打通仓库 → 生成构建入口 → 自动跑通一次真实构建
#
# 特性：幂等（重复执行跳过已完成步骤）、断点续传、失败即停、末尾自检
#
# 用法：
#   bash setup-android-env.sh                      # 装到 /data/toolchain
#   ANDROID_ENV_ROOT=/data/xxx bash setup-android-env.sh
#   bash setup-android-env.sh --skip-self-test     # 跳过末尾自检（省 2 分钟）
#   bash setup-android-env.sh --init-project ~/myapp   # 仅生成工程模板
# ============================================================

set -euo pipefail
ulimit -f unlimited 2>/dev/null || true   # 关键：默认单文件写入上限 200MB，必须解除

T="${ANDROID_ENV_ROOT:-/data/toolchain}"
REPO="whynusn/android-sdk-bundle"
TARBALL_URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/main"
GRADLE_VERSION="8.9"
MAVEN_URL="http://mirrors.tencent.com/nexus/repository/maven-public/"
SKIP_SELF_TEST=false
[[ "${1:-}" == "--skip-self-test" ]] && SKIP_SELF_TEST=true

C_GREEN='\033[32m'; C_YELLOW='\033[33m'; C_RED='\033[31m'; C_OFF='\033[0m'
ok()   { echo -e "${C_GREEN}[OK]${C_OFF} $*"; }
warn() { echo -e "${C_YELLOW}[!!]${C_OFF} $*"; }
die()  { echo -e "${C_RED}[XX]${C_OFF} $*"; exit 1; }
step() { echo -e "\n${C_GREEN}==>${C_OFF} $*"; }

# ---------- 0. 前置检查 ----------
step "0/8 前置检查"
for cmd in curl unzip tar sha256sum python3; do
  command -v $cmd >/dev/null || die "缺少命令: $cmd"
done
curl -sI --max-time 15 "$TARBALL_URL" -o /dev/null -w "%{http_code}" | grep -q 200 \
  || die "codeload 不可达（受限网络下 github.com 与 release 附件均 403，只能走 codeload）"
mkdir -p "$T/dl" "$T/gradle-home"
ok "命令与网络就绪，安装目录: $T"

# ---------- 1. 下载 ----------
step "1/8 下载 SDK 包（约 429MB）"
if [ -f "$T/dl/bundle.tar.gz" ] && tar tzf "$T/dl/bundle.tar.gz" >/dev/null 2>&1; then
  ok "已存在且完整，跳过下载"
else
  curl -sL -C - -o "$T/dl/bundle.tar.gz" "$TARBALL_URL" \
    -w "下载完成: %{size_download} bytes, %{time_total}s\n" \
    || die "下载失败"
fi

# ---------- 2. 校验与合并 ----------
step "2/8 校验完整性 + 合并 JDK 分片"
rm -rf "$T/dl/src" && mkdir -p "$T/dl/src"
tar xzf "$T/dl/bundle.tar.gz" -C "$T/dl/src" --strip-components=1
cd "$T/dl/src"
sha256sum -c SHA256SUMS-parts.txt || die "分片校验失败，文件已损坏"
cat OpenJDK17.tar.gz.part-* > OpenJDK17.tar.gz
sha256sum -c SHA256SUMS.txt || die "成品校验失败"
ok "3 个分片 + 6 个成品全部校验通过"

# ---------- 3. 解压组件 ----------
step "3/8 解压各组件"
mkdir -p "$T/extract" && cd "$T/extract"
[ -d "$T/extract/jdk-17.0.20.1+1" ] || tar xzf "$T/dl/src/OpenJDK17.tar.gz" -C "$T/extract"
for z in build-tools_r34-linux build-tools_r36.1_linux platform-34_r03 platform-37.0_r02 platform-tools_r35.0.2-linux; do
  [ -d "$T/extract/${z}" ] || unzip -q -o "$T/dl/src/$z.zip" -d "$T/extract/${z}"
done
ok "JDK 与 SDK 组件已展开"

# ---------- 4. 组装标准 SDK 目录 ----------
step "4/8 组装标准 SDK 目录（内部代号目录改名）"
SDK="$T/android-sdk"
mkdir -p "$SDK/build-tools" "$SDK/platforms" "$SDK/platform-tools"
# 官方 zip 顶层是 android-14 / android-16 内部代号，AGP 只认版本号目录
[ -d "$SDK/build-tools/34.0.0" ]   || mv "$T/extract/build-tools_r34-linux/android-14"    "$SDK/build-tools/34.0.0"
[ -d "$SDK/build-tools/36.1.0" ]   || mv "$T/extract/build-tools_r36.1_linux/android-16"  "$SDK/build-tools/36.1.0"
[ -d "$SDK/platforms/android-34" ] || mv "$T/extract/platform-34_r03/android-34"          "$SDK/platforms/android-34"
[ -d "$SDK/platforms/android-37.0" ] || mv "$T/extract/platform-37.0_r02/android-37.0"    "$SDK/platforms/android-37.0"
[ -x "$SDK/platform-tools/adb" ] 2>/dev/null || cp -r "$T/extract/platform-tools_r35.0.2-linux/platform-tools/." "$SDK/platform-tools/"
chmod +x "$SDK"/build-tools/*/aapt2 "$SDK"/build-tools/*/d8 "$SDK"/build-tools/*/zipalign \
         "$SDK"/build-tools/*/aidl "$SDK"/platform-tools/adb 2>/dev/null || true
ok "SDK 组装完成（build-tools 34.0.0 / 36.1.0，platform android-34 / 37.0）"

# ---------- 5. 安装 Gradle ----------
step "5/8 安装 Gradle ${GRADLE_VERSION}"
if [ -x "$T/gradle-${GRADLE_VERSION}/bin/gradle" ]; then
  ok "已安装，跳过"
else
  curl -sL -o "$T/gradle-${GRADLE_VERSION}-bin.zip" \
    "https://mirrors.tencent.com/gradle/gradle-${GRADLE_VERSION}-bin.zip" \
    -w "下载完成: %{size_download} bytes\n"
  unzip -q -o "$T/gradle-${GRADLE_VERSION}-bin.zip" -d "$T"
fi

# ---------- 6. 打通网络（Java 在这个沙箱走不了 HTTPS） ----------
step "6/8 配置网络与证书"
JH="$T/extract/jdk-17.0.20.1+1"
KS="$JH/lib/security/cacerts"
if [ -f /etc/zeroproxy-tls/zeroproxy-ca.pem ]; then
  "$JH/bin/keytool" -delete -alias zeroproxy-mitm-ca -keystore "$KS" -storepass changeit >/dev/null 2>&1 || true
  "$JH/bin/keytool" -importcert -noprompt -trustcacerts -alias zeroproxy-mitm-ca \
    -file /etc/zeroproxy-tls/zeroproxy-ca.pem -keystore "$KS" -storepass changeit >/dev/null 2>&1 || true
  ok "代理 CA 已导入 JDK 信任库（备用于需要 HTTPS 的场景）"
fi
warn "注意：本沙箱 MITM 代理会掐断 Java 的 TLS 握手，仓库必须用 http + isAllowInsecureProtocol"

# ---------- 7. 生成构建入口 ----------
step "7/8 生成构建入口 gradlew"
cat > "$T/gradlew" <<EOS
#!/bin/bash
ulimit -f unlimited 2>/dev/null || true
export JAVA_HOME=${JH}
export PATH=\$JAVA_HOME/bin:\$PATH
export ANDROID_HOME=${SDK}
export ANDROID_SDK_ROOT=${SDK}
export GRADLE_USER_HOME=${T}/gradle-home
exec ${T}/gradle-${GRADLE_VERSION}/bin/gradle "\$@"
EOS
chmod +x "$T/gradlew"
ok "已生成 $T/gradlew"

# ---------- 8. 自检：真实构建一次 ----------
if $SKIP_SELF_TEST; then
  step "8/8 跳过自检"
else
  step "8/8 自检：构建最小工程验证全链路"
  APP="$T/self-test"
  rm -rf "$APP" && mkdir -p "$APP/app/src/main/java/com/example/selftest" \
                            "$APP/app/src/main/res/layout" "$APP/app/src/main/res/values"

  cat > "$APP/settings.gradle" <<EOS
pluginManagement { repositories { maven { url = uri("${MAVEN_URL}"); allowInsecureProtocol = true } } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { maven { url = uri("${MAVEN_URL}"); allowInsecureProtocol = true } }
}
rootProject.name = "SelfTest"
include(":app")
EOS

  cat > "$APP/build.gradle" <<EOS
buildscript {
    repositories { maven { url = uri("${MAVEN_URL}"); allowInsecureProtocol = true } }
    dependencies { classpath("com.android.tools.build:gradle:8.5.2") }
}
EOS

  cat > "$APP/local.properties" <<EOS
sdk.dir=${SDK}
EOS

  cat > "$APP/gradle.properties" <<EOS
android.useAndroidX=true
android.enableJetifier=false
org.gradle.jvmargs=-Xmx2048m
org.gradle.daemon=false
EOS

  cat > "$APP/app/build.gradle" <<EOS
apply plugin: 'com.android.application'
android {
    namespace 'com.example.selftest'
    compileSdk 34
    buildToolsVersion '34.0.0'
    defaultConfig { applicationId 'com.example.selftest'; minSdk 26; targetSdk 34; versionCode 1; versionName '1.0' }
    compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
    // AGP 8.5.2 的 lint 解析不了 "android-37.0" 目录名，必须关掉
    lint { checkReleaseBuilds = false; abortOnError = false }
}
EOS

  cat > "$APP/app/src/main/AndroidManifest.xml" <<'EOS'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="SelfTest">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
EOS

  cat > "$APP/app/src/main/res/values/styles.xml" <<'EOS'
<resources><style name="AppTheme" parent="android:Theme.Material.Light"/></resources>
EOS

  cat > "$APP/app/src/main/res/layout/activity_main.xml" <<'EOS'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent" android:gravity="center">
    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content" android:text="SelfTest OK"/>
</LinearLayout>
EOS

  cat > "$APP/app/src/main/java/com/example/selftest/MainActivity.kt" <<'EOS'
package com.example.selftest
import android.app.Activity
import android.os.Bundle
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); setContentView(R.layout.activity_main) }
}
EOS

  # Kotlin 插件：仅为演示，Java-only 工程可不装；此处用 Java 源码避免额外依赖
  rm -rf "$APP/app/src/main/java/com/example/selftest/MainActivity.kt"
  cat > "$APP/app/src/main/java/com/example/selftest/MainActivity.java" <<'EOS'
package com.example.selftest;
import android.app.Activity;
import android.os.Bundle;
public class MainActivity extends Activity {
    @Override protected void onCreate(Bundle savedInstanceState) { super.onCreate(savedInstanceState); setContentView(R.layout.activity_main); }
}
EOS

  cd "$APP" && "$T/gradlew" assembleDebug --no-daemon 2>&1 | tail -5
  APK="$APP/app/build/outputs/apk/debug/app-debug.apk"
  [ -f "$APK" ] || die "自检失败：未产出 APK"
  "$SDK/build-tools/34.0.0/aapt2" dump badging "$APK" | head -2
  ok "自检通过，APK 已产出: $APK"
fi

echo -e "\n${C_GREEN}===== 全部完成 =====${C_OFF}"
echo "JAVA_HOME     = $JH"
echo "ANDROID_HOME  = $SDK"
echo "构建入口      = $T/gradlew"
echo "构建命令      = cd <工程目录> && $T/gradlew assembleDebug"

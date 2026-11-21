# iOS 16 / TrollStore 适配

基于上游 `my-name-is-alan/iDuanJu` 提交 `a13daac58a53bf750befd7d0b25c4b1fa9e8bc63`。
目标设备为已安装 TrollStore 的 iOS 16.6；工程最低系统版本设为 iOS 16.0。

## 修改

- 移除 AetherEngine 包、引擎适配器、专用 TDLib IOReader 和软件画中画代理，统一使用 AVPlayer。
- 保留系统画中画、倍速、进度恢复、音轨/字幕、AES 资源加载器、CENC 解密和 Telegram 本地流代理。
- 将 Observation 换成 Perception 1.6.0，并为视图与延迟执行的视图构建闭包添加观察范围，支持 iOS 16 的界面更新。
- 将 iOS 17/18 纵向翻页改为 UICollectionView 分页；滚动位置通过 UIKit 委托和 SwiftUI 几何偏好跟踪。
- 兼容 onChange、空状态、缩放手势、单独圆角、工具栏位置、滚动回弹与弹窗外观 API。
- QuickJS 的最低系统版本降至 16；TDLibKit 固定版本不变。
- iOS 16 每个插件使用独立、可复用的非持久 WebKit 数据存储，避免插件间 Cookie 混用。WebKit 会话在退出 App 后不保留；插件自己的 Cookie 导入仍保留原流程。

## 播放格式限制

AVPlayer 的容器、编码、音轨和字幕支持范围由 iOS 与设备决定。本分支不再附带 FFmpeg，不能承诺播放原引擎支持的全部 MKV、FLV、AVI 或软件解码格式。

## GitHub Actions

1. 将本分支推送到自己的 GitHub 仓库，分支名为 `ios16-trollstore`；也可在 Actions 中手动运行 **iOS 16 TrollStore IPA**。
2. 流程使用 `macos-15`、Xcode 16.4 和 XcodeGen 构建 arm64 真机 Release 包。
3. 自动检查主程序及嵌入二进制的最低 iOS 版本、平台、架构、加密标志和旧引擎动态依赖，然后运行选定的播放测试。
4. 成功后下载 `iDuanJu-iOS16-TrollStore` artifact，解压得到 `iDuanJu-iOS16-TrollStore.ipa`、对应源码 ZIP 与 SHA-256。
5. 将 IPA 传到已安装 TrollStore 的设备，在 TrollStore 中选择安装。

CI 的播放测试使用 runner 已安装的 iOS 18 模拟器，不能代替 iOS 16.6 实机验证。
TrollStore 适配指普通 iOS 真机包由 TrollStore 重新签名安装；本 App 无需 root、私有权限、JIT 或 Apple 开发者证书。

## Mac 本地构建

安装 Xcode 16.4、完成其首次运行设置，然后执行：

```bash
brew install xcodegen
bash scripts/package-trollstore.sh "$PWD/dist"
```

结果：`dist/iDuanJu-iOS16-TrollStore.ipa`。Windows 本身无法运行此 Xcode 构建过程。

## 验证状态

- 已完成本地源码静态解析对比：未发现新增解析错误。这不是 Swift 编译或类型检查。
- 已通过打包校验器 6 项单元测试。
- Xcode 构建、Swift 单元测试与真机安装播放尚待执行；在完成这些步骤前，源码不能视为已验证可运行的 IPA。

## 许可

沿用上游 GPL-3.0 和相关版权声明，Perception 为 MIT。分发修改后的二进制时一并提供对应源码。

# i短剧 (iDuanJu)

> **本项目完全免费、开源，禁止任何形式的付费分发 / 售卖。**
> 本项目以 **GPL-3.0** 协议发布：任何使用、修改、衍生本项目代码的作品，都必须同样以 GPL-3.0 开源并公开完整源代码。
> 如果你是花钱买到本 App 或本代码的，你被骗了，请举报卖家。

## 下载

请前往 [Releases 页面](https://github.com/my-name-is-alan/iDuanJu/releases) 下载。

## iOS 16 / TrollStore 分支

此分支移除 AetherEngine，统一使用兼容 iOS 16 的系统 AVPlayer，并回移新版 SwiftUI API。
目标设备：iOS 16.6，已安装 TrollStore。原有 FFmpeg 专属格式支持不再保留。

构建流程、限制和验证状态见 [iOS 16 构建说明](docs/IOS16-TROLLSTORE.md)。
GitHub Actions 工作流：**iOS 16 TrollStore IPA**；产物：`iDuanJu-iOS16-TrollStore.ipa`。

注意：下方上游 Releases 中的原版 IPA 不包含本分支修改。

## 免责声明

- 本项目仅供个人学习、研究 iOS / Swift / 网络协议使用，**不提供、不存储、不分发**任何视频、图片或漫画内容。
- 所有内容版权归原站点和权利人所有。使用时请遵守各站点的服务条款及你所在地的法律法规，由此产生的一切后果由使用者自行承担。
- 项目中对第三方接口的适配仅用于互通性研究，与相关平台无任何关联。如有权利人认为侵权，请提 issue 联系处理。

## 许可证

[GPL-3.0](LICENSE)。第三方组件及其许可见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

**禁止付费分发**：本项目是免费软件，作者不授权任何人以收费方式出售、分发本 App 或其代码。任何衍生作品都必须以 GPL-3.0 公开源代码。

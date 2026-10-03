[English](README.md) | **简体中文**

# Compositor

Adobe Photoshop 太贵，而 GIMP 这类工具我用起来又不够顺手，难以保持连贯的节奏——这就是我做 Compositor 的原因。

目标是做一个功能完整、完全免费开源的图像编辑器。我以前用 Photoshop 做合成和后期，所以 Compositor 就是围绕这套工作流打造的：把最终画面做到像素级精准所需要的那些工具。

因为它是开源的，你可以直接下载 Xcode 工程，按自己的工作流增加、删除或改写任何功能。

## 安装

### 下载

**简体中文构建（本仓库）**：从 [GitHub Releases](https://github.com/vipliujunjie/Compositor/releases/latest) 下载 `Compositor-<版本>-zh.dmg`，双击打开，把 `Compositor-zh.app` 拖入「应用程序」。该安装包已用 Developer ID 签名并完成 Apple 公证，首次打开不会出现安全警告。

**上游官方发布**：也可以从 [robbietilton.com/compositor](https://robbietilton.com/compositor) 或上游的 [GitHub Releases](https://github.com/robbietilton/Compositor/releases/latest) 获取原版；它同样支持中文界面，只是安装包按上游命名。

### Homebrew

```sh
brew install --cask robbietilton-compositor
```

（这是上游的 cask；本仓库的 `-zh` 构建请用上面的下载方式。）

## 功能

### 图层

- 图层与图层组，带不透明度，以及 Photoshop 全套混合模式（顺序与 Photoshop 一致）——图层组的不透明度会整体压暗组内所有内容
- 图层蒙版：可以在画布任意位置绘制、填充、反相、模糊和羽化，不受图层自身像素范围限制；可链接或取消链接，让蒙版单独参与变换
- 剪贴蒙版与图层组蒙版
- 调整图层：色相/饱和度、色阶、曲线、曝光度、渐变映射、颗粒、黑白、色彩平衡、反相、高斯模糊、动感模糊和杂色
- 图层效果：描边、投影、颜色叠加、内阴影、外发光和内发光，由 GPU 渲染，随时可编辑
- 向下合并、合并图层、合并图层组（⌘E）
- 复制、就地重命名、拖放调整顺序与嵌套；按住 Option 拖动即复制；图层面板内有右键菜单
- 未建立选区时，用 ⌘C/⌘V 复制粘贴整个图层或图层组——工程内、跨工程，或直接把图层拖到另一个工程

### 变换

- 非破坏性的移动、缩放、旋转和翻转——无论缩到多小，图层都保留原始分辨率
- 自由变形（⌘ 拖动控制柄），按住 Shift 锁定到某一轴
- 多个图层，或整个图层组，一起变换
- 吸附到画布与图层的边缘和中心，并显示参考线
- 位置、大小、缩放和角度的精确数值，可用方向键步进
- 翻转图层与翻转画布（水平、垂直）

### 选区

- 矩形与椭圆选框、手绘套索与多边形套索，以及魔棒类工具——魔棒按颜色选择，「对象」沿着你点按的轮廓描边（Tab 切换）
- 选择主体，以及对任意选区执行扩展、收缩和羽化
- 向选区添加或减去、移动选区轮廓，或移动与复制选区内的像素
- 把图层的像素或蒙版载入为选区
- 内容识别填充，也可以用它把图像扩展到画布边界之外

### 绘画与修饰

- 画笔：大小、硬度、不透明度和平滑，可在绘画或擦除模式间切换（B 与 E），按住 Shift 画直线
- 污点修复画笔（内容识别）
- 仿制图章：对齐或不对齐，可取样单个图层或所有图层
- 模糊工具，可用于像素或蒙版
- 渐变工具与形状工具（矩形、圆角矩形、椭圆和直线），保持可编辑，而不是被栅格化
- 文字工具（T）：在可拖动、可缩放的段落框内就地多行编辑；字体、字号、颜色、对齐与间距都在工具选项栏；文字可变换，也可当作剪贴蒙版使用
- 吸管与完整的拾色器

### 调整与滤镜

- Camera Raw 滤镜：光线、颜色、曲线、混色器、颜色分级、细节、光学和几何，面板位于画布旁
- 色阶（带自动）、曲线、色相/饱和度、曝光度、渐变映射、颗粒、黑白、色彩平衡和反相
- 高斯模糊与动感模糊，可溢出图层边缘
- 添加杂色、晕影、泛光/发光、色调对比、镜头校正和移除背景
- 实时预览；存在选区时，预览限制在选区内

### 画布与文件

- 多工程标签页
- 标尺（⌘R）、从标尺拖出的参考线、可调间距与细分的布局网格，以及「对齐到」参考线、网格、图层和文档边界
- 带吸附的裁剪，包含 3:4、9:16 等比例，按住 Option 对称裁剪；存在选区时，从选区开始裁剪
- 画布大小、图像大小和裁切
- 缩小时锐利的高质量下采样，放大时显示像素网格
- 导入 JPEG、PNG、HEIC、TIFF、SVG、相机 RAW（先经过显影步骤），以及 Photoshop PSD 与 PSB（8 位 RGB，不支持 CMYK）。Photoshop 的图层组、蒙版、混合模式、填充矩形/椭圆和简单横排文字保持可编辑；其它矢量与竖排文字会转为像素。应用之前会先显示一份转换报告。
- 大文档：内存预算随你的 Mac 伸缩；过大的 Photoshop 文件打不开时，改为把它的图层裁到画布大小
- 导出 JPEG（带实时预览，⇧⌥⌘S）；合并拷贝
- 工程保存时仍可继续工作
- 全流程 Photoshop 风格快捷键，可在「编辑 > 键盘快捷键」中重新映射
- 像 Photoshop 一样，拖动数字标签即可调整数值
- 自动更新，已签名并公证

### 与 AI agent 协作

- AI agent 和脚本可以直接创建、编辑工程：`.comp` 就是一个装着 PNG 图层和一个清单文件的文件夹，工程打开时随写随更新。见[编写 Compositor 工程](docs/writing-comp-files.md)

### 语言

- 界面提供英文与简体中文，跟随 Mac 的语言；也可以在「系统设置 › 语言与地区 › 应用程序」里单独为 Compositor 指定。译文存放在 `Compositor/Localizable.xcstrings`——要添加其它语言见[本地化](docs/localization.md)。

## 系统要求

- macOS 26.0 或更高版本，Apple 芯片的 Mac
- Xcode 26 或更高版本（从源码构建时需要）

## 构建

打开 `Compositor.xcodeproj`，运行 **Compositor** scheme。

## 打包发布

`scripts/release.sh` 会构建 Release 版本、用 Developer ID 签名、提交 Apple 公证并装订公证票，最后打包为 `dist/Compositor-<版本>-zh.dmg`（`SUFFIX` 默认为 `-zh`）。

需要以下条件，且都保存在本仓库之外：

- 登录钥匙串里的一张 **Developer ID Application** 证书
- 用 `xcrun notarytool store-credentials "compositor-notary" …` 保存的公证凭据
- [`create-dmg`](https://github.com/create-dmg/create-dmg)（`brew install create-dmg`）

本仓库的团队 ID 与上游不同，用 `TEAM_ID` 覆盖即可：

```sh
TEAM_ID=F5H454WZXZ ./scripts/release.sh             # 产出 dist/Compositor-<版本>-zh.dmg
SUFFIX="" TEAM_ID=F5H454WZXZ ./scripts/release.sh   # 需要上游命名时
SKIP_NOTARIZATION=1 ./scripts/release.sh            # 只验证产物，不提交公证
```

## 许可证

MIT —— 见 [LICENSE](LICENSE)。

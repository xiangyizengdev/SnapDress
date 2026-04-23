<div align="center">

<img src="screenshots/editor.png" width="720" alt="SnapDress 预览" />

# SnapDress

**一个常驻菜单栏的 macOS 截图美化小工具 —— 一个快捷键，一步到位。**

[![Release](https://img.shields.io/github/v/release/xiangyizengdev/SnapDress?color=brightgreen)](https://github.com/xiangyizengdev/SnapDress/releases/latest)
[![License](https://img.shields.io/github/license/xiangyizengdev/SnapDress)](./LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
[![Downloads](https://img.shields.io/github/downloads/xiangyizengdev/SnapDress/total?color=orange)](https://github.com/xiangyizengdev/SnapDress/releases)

[**下载**](https://github.com/xiangyizengdev/SnapDress/releases/latest) · [功能](#功能) · [安装](#安装) · [从源码构建](#从源码构建) · [English](./README.md)

</div>

> 把它想象成 **Xnapper × 微信截图** —— 为每天都在按 `⌘⇧2` 的人做的。
>
> 选区、标注、一键美化 —— 自带圆角、阴影和好看的背景，完成即复制到剪贴板。

<!-- TODO: 录完 v1.1.0 演示 GIF 后替换这里 -->

## 为什么做 SnapDress

市面上的截图工具大多停在"截到了"这一步。SnapDress 想做的是**一键就能用的那张图**：

- **微信风格选区** —— 冻屏 + 像素放大镜 + 拖拽微调，让你**第一次就选到想要的区域**
- **标注不用切工具** —— 矩形、圆、箭头、马赛克一键即用
- **自动美化** —— 圆角、阴影、留白、18+ 背景预设，出厂即最佳参数
- **完成即复制** —— 粘贴到哪都是一张漂亮图，不用存盘不用弹窗
- **没有 Dock 图标** —— 静静待在菜单栏，召之即来挥之即去

## 功能

### 截图体验

- 全局快捷键（默认 `⌘⇧2`，可自定义）
- **冻屏模式** —— 开始选区的那一刻屏幕就冻住，窗口跳动不会打断你（设置里可关）
- **像素级放大镜** —— 选区时鼠标旁跟随 5 倍放大窗口，边界对齐再也不用肉眼凑
- **选完能微调** —— 选完后整块拖动，方向键每次移 1 像素，`Shift+方向键` 每次 10 像素
- **微信风格绿色选框** —— 粗描边、8 个拉伸手柄、实时像素尺寸提示

### 标注工具

- 矩形、圆、箭头、马赛克（用来遮敏感信息）
- 移动选区时，标注会**一起跟着动**

### 美化

- 圆角、阴影（含透明度和偏移）、外边距、内留白
- **18+ 背景预设** —— 渐变、毛玻璃（用原图的模糊版做背景）、纯色、透明
- **自定义背景** —— 任选两个颜色做渐变，或者塞一张自己的图
- **Retina (HiDPI) 导出**（可选，默认关）—— 把导出图标记为 `@2x`，粘到 Figma、Sketch、Keynote 里依然清晰

### 工作流

- 完成即复制到剪贴板（无对话框、无保存询问）
- 悬浮预览气泡 —— 鼠标悬停暂停倒计时，点击打开完整编辑器
- 菜单栏弹窗，保留**最近 10 张**截图快速访问
- 截完可进完整编辑器调参

## 预览

<details>
<summary>更多截图</summary>

**编辑器**

<img src="screenshots/editor.png" width="720" />

**标注工具栏**

<img src="screenshots/annotation-toolbar.png" width="720" />

</details>

## 安装

### DMG 安装（推荐）

1. 从 [Releases](https://github.com/xiangyizengdev/SnapDress/releases/latest) 下载最新的 `SnapDress-1.1.0.dmg`
2. 打开 DMG，把 `SnapDress` 拖到 `Applications`
3. 启动 App，首次运行时在 **系统设置 → 隐私与安全性 → 屏幕录制** 授予权限

需要 **macOS 14.0 (Sonoma) 或更新版本**。

> App 还没做公证。首次启动如果被 macOS 拦截，右键 App → **打开** → **仍然打开**。或者运行 `xattr -cr /Applications/SnapDress.app`。

### 从源码构建

```bash
git clone https://github.com/xiangyizengdev/SnapDress.git
cd SnapDress
bash scripts/bundle.sh        # 编译并安装到 /Applications
# 或：
bash scripts/make-dmg.sh      # 打一个可分发的 .dmg
```

## 使用

1. 按 `⌘⇧2`（或你自定义的快捷键）进入选区模式
2. 拖选一块区域 —— 下方会浮出标注工具栏
3. 需要的话加几个标注，然后点 ✓ 确认
4. 美化后的截图已经在你的剪贴板里了，屏幕角落会弹一个预览气泡
5. 点击预览气泡进入完整编辑器微调

任何时候按 `ESC` 取消。

## 支持这个项目

SnapDress 免费 + MIT 开源。如果它帮你省了时间，可以这样支持：

- [**购买 Supporter Edition — $4.99**](#) —— 一封感谢信 + 新功能抢先试用 + 进 supporter 名单 *（商店还在准备，敬请期待）*
- [**给仓库点个 Star**](https://github.com/xiangyizengdev/SnapDress) —— 不花钱，但帮别人发现这个项目
- [**提个 Issue**](https://github.com/xiangyizengdev/SnapDress/issues) —— 报 bug 或提新功能都欢迎

你的每一点支持，都是下一个快捷键的动力。

## 路线图

- [ ] OCR（从截图复制文字）
- [ ] 长截图 / 滚动截图
- [ ] iCloud 历史同步
- [ ] 公证 + 上架 Mac App Store
- [ ] 更多主题和背景包

有想法？[开个 Issue](https://github.com/xiangyizengdev/SnapDress/issues) 告诉我你想要什么。

## 技术栈

- Swift + SwiftUI + Swift Package Manager
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) 做屏幕捕获
- CoreGraphics + CoreImage 做图像处理
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 做全局快捷键

## 致谢

由 [@xiangyizengdev](https://github.com/xiangyizengdev) 开发。灵感来自 Xnapper、CleanShot X，以及每天都在用的微信截图。

## 协议

[MIT](./LICENSE) —— 随便用，出事别怪我。

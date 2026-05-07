# Lumia 开发全记录

## 这是什么

Lumia 是一款 macOS 屏幕录制工具，核心功能是把摄像头画面实时合成进录屏视频——就是你在很多教程视频里看到的那种右下角圆形人脸气泡。整个项目从零开始，用 Swift + SwiftUI + 苹果原生框架构建，没有依赖任何第三方库。

---

## 第一步：搭骨架

从一个空的 Xcode 项目开始。第一件事不是写功能，而是把数据模型定义清楚——`RecordingState`，用 Swift 5.9 的 `@Observable` 宏管理录制状态（空闲 / 录制中 / 暂停）、覆盖层位置、圆圈大小、缩放比例这几个核心字段。状态机先行，所有 UI 和录制逻辑都只是对它的响应。

---

## 第二步：接通摄像头

用 `AVCaptureSession` 驱动摄像头和麦克风。摄像头输出走 `AVCaptureVideoDataOutput`，像素格式统一成 `kCVPixelFormatType_32BGRA`；麦克风走 `AVCaptureAudioDataOutput`。每一帧 CVPixelBuffer 用 `NSLock` 保护存起来，任何时候都可以读到最新一帧。

摄像头在 app 启动时就开始跑，这样打开 app 马上能看到自己的脸，不用等到点录制。

---

## 第三步：捕获屏幕

用苹果的 `ScreenCaptureKit` 框架（macOS 12.3+）捕获屏幕。它比老的 `CGWindowListCreateImage` 强很多：支持排除特定窗口（把 Lumia 自己的控制栏和摄像头预览窗口排除掉，不录进去）、性能更好、权限申请更规范。

配置为 30fps、BGRA 格式，和摄像头保持一致。

---

## 第四步：把两路画面合成一帧

这是整个项目最核心也最折腾的部分——`FrameCompositor`。

**思路很简单**：每来一帧屏幕画面，把摄像头画面叠在右下角，输出一个新的 CVPixelBuffer 给编码器。

**实际踩了很多坑**：

- **第一版用 CGContext**：写了 y-flip 变换想修正坐标系，结果在 macOS 26 上画面上下颠倒——因为 Bitmap CGContext 已经是上左原点，再 flip 就翻了两次。
- **第二版加了诊断日志**：发现摄像头数据是有的（`webcam=valid`），但 overlayRect 坐标完全在帧边界外面（x=3664，但帧宽只有 2056）——所以 blit 函数的 guard 直接 return，什么都没画。
- **根本原因**：`SCStream` 的回调线程和主线程调用同一个 `CVPixelBufferGetWidth` 在 Retina 屏上返回值不一样（一个是物理像素，一个是逻辑像素），坐标算出来就越界了。
- **最终方案**：彻底放弃 CGContext，用逐行 `memcpy` 复制屏幕帧，用像素级直接写入做摄像头叠加，坐标全部在 FrameCompositor 内部用实际 buffer 尺寸计算，不依赖任何外部传入的坐标。同时加上圆形蒙版（按距圆心距离判断是否写入）和中心裁切（把 16:9 的摄像头画面裁成正方形再缩放，避免变形）。

---

## 第五步：写入 MP4 文件

用 `AVAssetWriter` 把合成好的帧编码成 H.264 视频，同时把麦克风采集的 AAC 音频轨道一起写进去。时间戳用系统时钟（`CMClockGetHostTimeClock`）保证连续性。文件自动保存到桌面的 Lumia 文件夹，文件名带时间戳。

---

## 第六步：浮动控制栏

做了一个悬浮在所有窗口之上的 HUD 控制栏，用 `NSPanel` + SwiftUI 实现。三个按钮：开始 / 暂停 / 停止。实时显示录制时长。控制栏本身不会被录进屏幕里（ScreenCaptureKit 过滤掉了）。

同时加了全局快捷键：`⌘⇧R` 开始/停止，`⌘⇧P` 暂停/继续，即使 Lumia 不在前台也能触发。

---

## 第七步：摄像头预览窗口 + 右键菜单

摄像头预览是一个圆形浮动窗口，用 `AVCaptureVideoPreviewLayer` 直接渲染，实时显示。

右键点击预览圆圈弹出菜单，可以调：
- **位置**：左上 / 右上 / 左下 / 右下四个角，选完预览窗口跟着跳
- **圆圈大小**：大 / 超大 / 特大三档
- **画面缩放**：1× / 1.2× / 1.5×，控制摄像头画面裁切范围

调整大小时用 `CATransaction.setDisableActions(true)` 禁掉 Core Animation 隐式动画，避免切换时出现菱形过渡帧。

---

## 第八步：权限处理

启动时依次申请摄像头权限和屏幕录制权限，给出中文提示和跳转系统设置的快捷按钮。

---

## 最终架构

```
摄像头 ──▶ CameraCapture ──▶ currentFrame()
                                    │
屏幕  ──▶ ScreenCapture  ──────────▼
                          RecordingController
                                    │
                          FrameCompositor
                          (memcpy屏幕 + 圆形叠加)
                                    │
                          MovieWriter (H.264 + AAC)
                                    │
                              桌面/Lumia/*.mp4
```

---

## 技术选型总结

| 需求 | 框架 |
|------|------|
| 屏幕捕获 | ScreenCaptureKit |
| 摄像头/麦克风 | AVFoundation |
| 帧合成 | 纯 CoreVideo + memcpy |
| 视频编码 | AVAssetWriter (H.264) |
| UI | SwiftUI + AppKit (NSPanel) |
| 状态管理 | Swift @Observable |

整个项目约 600 行 Swift，无第三方依赖。

# zxc

~~智能~~<ruby>低配置<rt>减少非直观配置</rt></ruby>视频压缩工具。

基于 `libsvtav1` 和 `libopus` 编码，支持通过灵活的命令行参数控制压缩质量与体积。输出文件会自动添加 `!` 前缀及配置后缀，并保留原始扩展名。

## 用法

```bash
zxc [ :key1=value1[:key2=value2...]: ] <视频1> [视频2 ...]
```

**示例：**

```bash
zxc :mode=b:preset=4:bitrate=2M: video.mkv
```

## 参数说明

参数需以冒号 `:` 包裹的键值对形式传入。

| 参数 | 别名 | 说明 | 默认值 |
| :--- | :--- | :--- | :--- |
| `mode` | `m` | 编码模式：`q` (1-pass CRF 质量优先) 或 `b` (2-pass ABR 码率优先) | `q` |
| `preset` | `p` | SVT-AV1 预设 (0-13，值越小越慢/质量越好) | `6` |
| `quality` | `q` | CRF 值 (0-63，越小质量越好，仅质量模式生效) | `40` |
| `bitrate` | `vb`, `b` | 视频目标码率 (仅码率模式生效) | `3M` |
| `audio-bitrate`| `ab`, `B`| 音频目标码率 (两种模式均生效) | `76.8K` |
| `tune` | `t` | SVT-AV1 tune 参数 | 质量模式 `5`，码率模式 `0` |

## 自定义构建

本项目支持将特定的音频空间滤波配置（`.sofa` 文件）打包进脚本中，生成独立可执行的自定义版本。

**关于 SOFA 数据：**
SOFA（空间声学格式）脉冲响应数据可从 [SOFA Conventions](https://www.sofaconventions.org/mediawiki/index.php/Files) 官方资源库获取。推荐使用 [Club Fritz 数据库](https://sofacoustics.org/data/database/clubfritz/) 中的数据文件。

### 构建步骤

1. 确保当前目录下存在模板文件 `zxc.sh` 和你想嵌入的 `.sofa` 配置文件（如 `ClubFritz4.sofa`）。
2. 直接运行构建脚本：

   ```bash
   ./build.sh
   ```

### 构建原理

脚本会自动完成以下操作：
1. 提取 `zxc.sh` 中 `#@DEFAULT_SOFA@` 占位符之前的脚本逻辑。
2. 将指定的 `.sofa` 文件进行 Base64 编码，并追加到脚本末尾。
3. 为生成的文件赋予执行权限，并输出至 `~/.local/bin/zxc`。

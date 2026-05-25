# ScreenshotOCR — Linux 区域截图 → OCR → 翻译工具

纯 bash 实现，方便设置快捷键一键调用。

## 系统要求

- Linux 桌面环境（Wayland 或 X11）
- 以下依赖（安装脚本时会自动检查）

## 快速安装

```bash
# 1. 安装依赖
sudo apt install grim slurp curl jq wl-clipboard openssl python3
#   X11 用户还需: sudo apt install maim scrot

# 2. 拷贝脚本到可执行路径
cp screenshot-ocr ~/.local/bin/
cp screenshot-ocr.conf ~/.config/
chmod +x ~/.local/bin/screenshot-ocr

# 3. 配置 API Key（必填）
nano ~/.config/screenshot-ocr.conf
#    填入百度 OCR 的 API Key 和 Secret Key
```

## 获取 API Key

### 百度 OCR（必填）
1. 打开 https://console.bce.baidu.com/ai/#/ai/ocr/overview/index
2. 创建应用 → 选择「文字识别」服务
3. 获取 API Key 和 Secret Key，填入配置文件

### 百度翻译（可选）
1. 打开 https://console.bce.baidu.com/ai/#/ai/machinetranslation/overview/index
2. 创建应用 → 开通「机器翻译」服务
3. 获取独立的 API Key 和 Secret Key，填入配置文件

## 使用方法

```bash
screenshot-ocr               # 截图 → OCR，结果自动复制到剪贴板
screenshot-ocr -t            # 截图 → OCR → 翻译为中文
screenshot-ocr -t en         # 截图 → OCR → 翻译为英文
screenshot-ocr -h            # 显示帮助
```

## 设置快捷键（GNOME）

1. 系统设置 → 键盘 → 键盘快捷键 → +
2. 名称: `截图OCR`  命令: `~/.local/bin/screenshot-ocr`  快捷键: `Ctrl+Shift+Z`
3. 名称: `截图OCR+翻译`  命令: `~/.local/bin/screenshot-ocr -t`  快捷键: `Ctrl+Shift+X`

## 文件说明

| 文件 | 说明 |
|------|------|
| `screenshot-ocr` | 主脚本（核心程序） |
| `screenshot-ocr.conf` | 配置文件（填 API Key） |
| `README.md` | 本教程 |

## 卸载

```bash
rm ~/.local/bin/screenshot-ocr
rm ~/.config/screenshot-ocr.conf
```

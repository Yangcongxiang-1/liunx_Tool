# Header Editor 解决 Google reCAPTCHA 加载问题教程

适用于 Edge 浏览器，解决国外网站 Google 人机验证（reCAPTCHA）加载不出来、转圈、白屏的问题。

---

## 第一步：安装 Header Editor 扩展

1. 打开 Edge 浏览器
2. 访问扩展安装地址：
   ```
   https://microsoftedge.microsoft.com/addons/detail/header-editor/afopnekiinpekooejpchnkgfffaeceko
   ```
3. 点击 **"获取"** → 弹出提示点 **"添加扩展"**

---

## 第二步：导入规则配置

1. 点击 Edge 右上角的 **拼图图标**（扩展管理），找到 **Header Editor**，点击打开

   ![](https://cdn.jsdelivr.net/gh/FirefoxBar/HeaderEditor@master/readme/icon-128.png)

2. 进入管理页面后，点击左侧 **"导入和导出"**

3. 在 **"导入规则"** 区域：
   - 点击 **"选择文件"**
   - 选择桌面上保存的 `header-editor-recaptcha-rules.json` 文件
   - 点击 **"确认"**

4. 导入成功后，回到 **"请求规则"** 和 **"响应规则"** 标签页，确认能看到对应的两条规则已启用（开关为蓝色）

   | 规则类型 | 规则名 | 状态 |
   |---------|--------|------|
   | 请求规则 | reCaptcha 重定向 | ✅ 已启用 |
   | 请求规则 | Google APIs 反代 | ✅ 已启用 |
   | 响应规则 | CSP 头修改 | ✅ 已启用 |

---

## 第三步：验证是否生效

1. 随便打开一个使用了 reCAPTCHA 的国外网站（例如 freepik.com 的注册页面）
2. 如果之前是白屏/转圈，现在应该能正常显示 **"我不是机器人"** 复选框
3. 点击验证，能正常弹出图片选择挑战即表示成功

---

## 工作原理（简单说明）

| 原始请求 | → | 重定向到 |
|---------|---|---------|
| `google.com/recaptcha/*` | → | `recaptcha.net/recaptcha/*` |
| `ajax.googleapis.com/*` | → | `gapis.geekzu.org/ajax/*` |

recaptcha.net 是 Google 官方的备用域名，在国内网络环境下可正常访问。

同时规则会修改网页的 CSP（内容安全策略）头，防止浏览器因为安全策略拦截反代过来的资源。

---

## 常见问题

**Q: 导入规则后没有生效？**
A: 检查三条规则的开关是否都是蓝色（启用状态），然后刷新页面重试。

**Q: 有些网站还是不行？**
A: 少数网站硬编码了 Google 域名，可以尝试在 Header Editor 中再加一条规则，把所有 `google.com` 相关的 JS 请求也反代。如果仍不行，说明该网站用了其他验证方式（如 hCaptcha）。

**Q: 不想用了怎么删除？**
A: 打开 Header Editor → 选中规则 → 点击删除按钮，或直接禁用该扩展。

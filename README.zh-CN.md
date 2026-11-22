# Auralis Download Manager

[English](README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt-BR.md) · [简体中文](README.zh-CN.md)

Auralis 是适用于 Windows x64 的免费开源下载管理器，提供玻璃风格界面、详细的传输控制和浏览器扩展。它是 [Mister Download Manager](https://github.com/anefzaoui/misterdownloadmanager) 的独立 GPL-3.0 分支，并非官方版本。

[下载最新 Windows 版本](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) · [浏览器扩展](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest) · [版本说明](CHANGELOG.md)

## 界面截图

### 下载管理器

![下载管理器](docs/images/auralis/user-picture-1.png)

### 正在下载

![正在下载](docs/images/auralis/user-picture-2.png)

### 下载文件信息

![下载文件信息](docs/images/auralis/user-picture-3.png)

### 下载完成

![下载完成](docs/images/auralis/user-picture-4.png)

### 外观设置

![外观设置](docs/images/auralis/user-picture-5.png)


## 功能

- 多连接下载、暂停与恢复、队列、速度限制和实时传输图表。
- 浏览器扩展可发送下载和受支持的媒体链接。发行文件包含 Chromium 和 Firefox 扩展，需分别安装并授予权限。
- 独立的下载、文件信息、完成和设置窗口，材质、颜色与指示器可分别配置。
- 系统托盘控制、可选的随 Windows 启动及隐藏下载窗口的独立托盘图标。
- 通过 yt-dlp 查询视频和音频质量；网站支持时可使用浏览器会话或手动 Cookie 文件。
- 应用内更新通知和更新，以及偏好设置备份与恢复。
- 下载器在 Auralis 内运行；浏览器通过小型本机消息助手与应用通信。
- 可添加 HTTP、HTTPS 或 FTP 链接，也可从浏览器发送；下载窗口显示速度、连接和剩余时间。能否续传取决于来源，磁盘刷新或校验也可能耗时。
- 支持使用服务器提供的完整文件校验值。可添加种子或磁力链接、检查文件与目标位置，并使用种子哈希重新校验分片。某些音视频合并需要 FFmpeg。
- 主题导出包含调色板、材质、字体和指示器设置，但不包含壁纸文件。详见[主题格式](docs/auralis-theme-format.md)。

偏好设置备份不含密码、账户凭据或浏览器 Cookie；新系统上可能需要重新登录。浏览器和网站限制可能影响视频查询。

## 指南与恢复

查看多语言[使用指南](docs/auralis-guide-drafts/zh-CN.md)；指南仍在随应用更新。

普通分段下载会将数据直接写入同一个临时文件的正确位置。保存过哈希的块可检查后续变化；修复依赖兼容服务器，无法强制服务器支持字节范围。对于停止的直接下载，可比较种子或磁力链接，也可请求搜索 Internet Archive。已匹配的分片不能证明其余内容一致；恢复需要对等节点并保留原始部分文件。自动恢复仍在开发。

可导出和导入包含指示器设置的可编辑 JSON 主题。偏好设置备份目前不包含已下载文件、部分文件或下载历史；完整备份仍在开发。

## 安装

从[最新版本](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest)下载并运行 Windows x64 安装程序。安装相应浏览器扩展，并按**设置 → 浏览器集成**中的说明操作。

## 许可与致谢

Auralis 采用 [GNU GPL v3](LICENSE) 许可，是 Ahmed Nefzaoui 和贡献者的 Mister Download Manager 的分支；详见[致谢](ATTRIBUTION.md)与[上游项目](https://github.com/anefzaoui/misterdownloadmanager)。

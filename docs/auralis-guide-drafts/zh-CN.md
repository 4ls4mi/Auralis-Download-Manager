# Auralis Download Manager 功能指南（草稿）

这是下一版本的草稿。发布前应根据该版本的发行说明确认功能。

- **安装：**从[发行页面](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest)安装 Windows x64 版本。在 **Settings → Browser Integration** 中选择 **Set up everything**，并在浏览器中安装扩展。
- **下载：**点击 **Add URL**，输入 HTTP、HTTPS 或 FTP 地址并选择保存位置。浏览器扩展也可以发送支持的链接。打开下载窗口可查看进度、连接和速度。
- **续传：**使用 **Pause** 和 **Resume**。链接过期时，暂停下载，通过 **Refresh download address** 输入指向同一文件的新链接。能否续传取决于服务器。普通分段在下载过程中写入同一个临时文件；最后的磁盘写入和校验仍可能需要时间。
- **队列和限速：**选择文件后使用 **Add to queue**。在 **Scheduler** 中设置时间，在下载窗口的 **Speed Limiter** 中限制单个任务的速度。
- **视频和音频：**配置扩展及 yt-dlp 后，打开受支持的视频页面并选择清晰度和字幕。只有来源提供大小时才会显示；某些格式需要 FFmpeg 合并视频和音频。
- **种子：**使用 **Add Torrent** 打开 `.torrent` 文件或粘贴磁力链接，检查文件和保存位置。可用性取决于其他节点。
- **外观：**在 **Settings → Appearance** 中选择颜色和材质；在 **Indicators** 中分别设置进度条、连接和图表。使用 **Export editable material** 导出 JSON 材质，编辑后用 **Import material** 导入。参见[材质格式](../auralis-material-format.md)。
- **偏好设置备份：**在 **Settings → General → Preferences backup** 中使用 **Save backup** 和 **Restore backup**。当前版本保存偏好设置和材质，但不包含已下载文件、未完成文件、下载历史、密码或 Cookie。在新电脑上检查保存路径。完整文件备份仍在开发中。
- **启动和更新：**在 **Settings → General** 中设置随 Windows 启动，在 **Advanced → Updates** 中设置更新通知。

本地哈希可以发现保存后的变化，但不能单独证明原始数据真实可靠。自动查找替代种子和修复损坏区段的功能仍在开发中。

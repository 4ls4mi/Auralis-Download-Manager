# Auralis Download Manager 功能指南（草稿）

这是下一版本的草稿。发布前应根据该版本的发行说明确认功能。

- **安装：**从[发行页面](https://github.com/4ls4mi/Auralis-Download-Manager/releases/latest)安装 Windows x64 版本。在 **Settings → Browser Integration** 中选择 **Set up everything**，并在浏览器中安装扩展。
- **下载：**点击 **Add URL**，输入 HTTP、HTTPS 或 FTP 地址并选择保存位置。浏览器扩展也可以发送支持的链接。打开下载窗口可查看进度、连接和速度。
- **续传：**使用 **Pause** 和 **Resume**。链接过期时，暂停下载，通过 **Refresh download address** 输入指向同一文件的新链接。能否续传取决于服务器。普通分段在下载过程中写入同一个临时文件；最后的磁盘写入和校验仍可能需要时间。
- **队列和限速：**选择文件后使用 **Add to queue**。在 **Scheduler** 中设置时间，在下载窗口的 **Speed Limiter** 中限制单个任务的速度。
- **视频和音频：**配置扩展及 yt-dlp 后，打开受支持的视频页面并选择清晰度和字幕。只有来源提供大小时才会显示；某些格式需要 FFmpeg 合并视频和音频。
- **种子：**使用 **Add Torrent** 打开 `.torrent` 文件或粘贴磁力链接，检查文件和保存位置。可用性取决于其他节点。
- **外观：**在 **Settings → Appearance** 中选择颜色和材质；在 **Indicators** 中分别设置进度条、连接和图表。使用 **Export current theme…** 导出 JSON 材质，编辑后用 **Import theme…** 导入。参见[材质格式](../auralis-material-format.md)。
- 要备份或恢复下载，请先停止传输、校验和队列。在 **Settings → General → Download backup** 中选择 **Back up downloads…**，保存设置、历史记录、队列、支持的文件及已保存的进度。在新安装中选择 **Restore downloads…**，再选择备份归档和目标文件夹。**Preferences backup** 可将设置单独保存为 JSON。备份不包含密码或 Cookie。
- **启动和更新：**在 **Settings → General** 中设置随 Windows 启动，在 **Advanced → Updates** 中设置更新通知。

本地哈希可以发现保存后的变化，但不能单独证明原始数据真实可靠。下载窗口中的 **Check saved data** 检查已保存哈希的区块；如果 HTTP 服务器兼容，**Check source and repair** 可以准备重新下载受损区段。

在即将发布的 Windows 版本中，可以在 **Settings → Torrents** 中启用自动恢复。符合条件的直连下载用尽重试次数后，Auralis 会使用文件名中的词语在 Internet Archive 中搜索。你可以先检查匹配结果，也可以在仅有一个匹配项、至少两个已保存的分片通过验证且所有候选项均已成功检查时让 Auralis 自动继续。私密下载及带有预期整文件校验和的下载不在此功能范围内。

在下载窗口中，也可以通过 **Find a torrent for recovery** 检查本地种子文件、磁力链接或指向种子文件的公开 HTTP(S) 链接。Auralis 会将通过验证的分片复制到新的恢复文件夹，保留原始未完成文件，并从 BitTorrent 节点获取剩余分片。下载窗口会显示详细状态，列表中已恢复的下载则会标记为 **Direct → Torrent**。

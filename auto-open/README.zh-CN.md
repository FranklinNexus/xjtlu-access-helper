# 自动进入隔离环境

这个可选功能让你继续在普通 Edge/Chrome 地址栏输入学校网址。扩展识别到支持的学校域名后，会把这次导航交给 XJTLU Access Helper，在独立浏览器配置中打开。

它只匹配以下入口：

- `www.learningmall.cn`、`core.xjtlu.edu.cn`、`uim.xjtlu.edu.cn`
- `mail.xjtlu.edu.cn`
- `www.xjtlu.edu.cn`

其他网站保持原样。隔离浏览器仍然禁用扩展和同步，普通浏览器的 Cookie、代理和其他设置不会被修改。

## 一次性安装

1. 双击 `Install-AutoOpen.cmd`，脚本只写入当前 Windows 用户的 `HKCU\Software\Classes` 协议注册，并打开 Edge 扩展页面。
2. 在 Edge 打开“开发人员模式”。
3. 选择“加载解压缩的扩展”，选中本目录下的 `extension` 文件夹。
4. 把扩展固定到工具栏。点击图标可以在 `ON/OFF` 之间切换自动接管。

之后直接在普通浏览器输入学校网址即可。扩展会调用固定的本地协议，协议处理器再启动独立浏览器；不会把账号、密码、Cookie 或当前网址内容发送到第三方。

## 卸载

先在 `edge://extensions/` 移除扩展，再双击 `Uninstall-AutoOpen.cmd` 删除三个协议注册。卸载不会删除隔离浏览器的登录状态；如需清理，使用主工具菜单中的 Reset。

## 当前边界

- 这是 Windows + Edge/Chrome/Brave 的本地集成，扩展需要在你使用的普通浏览器中加载一次。
- 自动入口使用每项服务的固定官方入口，不保留地址栏中的查询参数，避免把 OAuth/SAML 参数带入启动器。
- 如果学校增加了新的官方域名，需要同时更新 `routes.json` 和扩展路由后再重新加载扩展。

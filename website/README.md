# NeoBili 产品介绍页

白底极简风格，纯静态 HTML / CSS，无运行时依赖。图片、字体样式均使用本地资源，无外部字体请求。

## 预览与部署

执行 `npm run dev` 后打开 `http://127.0.0.1:4173`。

执行 `npm run build`，把 `dist/` 中的内容复制到博客的子目录，例如 `/neobili/`。保留 `index.html`、`styles.css` 和 `assets/` 的相对目录关系即可，无需 Node 服务，也不需要配置 SPA 路由。访问子目录时保留结尾斜杠。

也可以不构建，直接部署 `index.html`、`styles.css` 和 `assets/`。

## 替换产品截图

当前使用用户提供的真实产品截图：`assets/home.jpg`（推荐）、`assets/following.jpg`（关注）、`assets/mine.jpg`（我的）。细节区域复用关注页截图。

替换图片时同步更新 `index.html` 中对应的 `src`、尺寸和 `alt`。手机截图保持自然比例，细节区域使用 `object-fit: cover`。

品牌粉色、文字颜色、内容宽度均在 `styles.css` 的 `:root` 中配置。更新版本时同步修改下载区版本、体积、IPA 链接及 Release 链接。

站点预览托管配置位于 `.openai/hosting.json`，博客部署不需要此文件。

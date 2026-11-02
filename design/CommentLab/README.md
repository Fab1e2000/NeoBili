# 评论区原生交互稿

独立 SwiftUI 示例应用，用于比较评论区方案；正式界面采用已选定的 A 轻量方案。无第三方依赖，使用本地示例评论、头像和矢量配图，不请求网络、不读取账号。

## 运行

在此目录运行 `xcodegen generate`，打开 `CommentLab.xcodeproj`，选择 `CommentLab` scheme 和 iPhone Simulator。
应用标识为 `com.elsterlee.NeoBili.CommentLab`，不覆盖日常 NeoBili 或回归应用。

## 比较与交互

- 左上角切换 A 轻量、B 紧凑、C 醒目；右上角打开完整对比设置。
- A 使用描边 UP 标识、菜单排序和原生长按菜单。
- B 使用浅色 UP 标识、文字排序切换和原生底部操作列表。
- C 使用实色 UP 标识、置顶浅色背景和原生分段排序。
- 对比设置可切换视频／动态、深浅色、大字号，并模拟删除失败、恢复全部示例。
- 点击头像、昵称进入示例主页；「查看全部回复」打开回复详情。返回保留列表和草稿。
- 长按评论或单条预览回复可复制全文；自己的评论显示删除入口，确认后只删除本地示例。
- 下拉刷新、点赞、回复输入、示例发送、正文展开、时间戳和图片查看均可操作。
- 播放区是本地静态画面，暂停按钮和时间戳用于演示状态；不实际播放媒体。
- UP 主互动标记为固定示例值；切换排序只对本地数据排序。正式界面使用独立的服务端排序、分页和账号会话校验。

截图与编译产物保存在仓库忽略的 `DerivedData/Validation/CommentLab/` 和 `DerivedData/CommentLab/`。
对比设置可整套选择，也可在反馈中指定不同方案的组件组合。

## 可重复预览

支持启动参数：`--variant A|B|C`、`--dark`、`--large`、`--dynamic`、`--thread 2`、`--delete-fails`。
每次重新启动均恢复固定示例，不将选择或删除写入持久存储。

## 交互检查

`CommentLabUITests` 使用本地示例验证主页返回与草稿、主评论及楼中楼长按、复制反馈、删除成功／失败、排序、图片查看和下拉刷新；并采集三套方案的浅色、深色及大字号截图。
在 Xcode 选择独占的 Simulator 后运行 `⌘U`。也可以在此目录明确指定设备：

```sh
xcodebuild test -project CommentLab.xcodeproj -scheme CommentLab \
  -destination "platform=iOS Simulator,id=$NEOBILI_SIMULATOR_ID" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

这些检查仅验证交互稿；正式评论服务、播放器手势及账号状态的回归属于选定方案后的集成阶段。

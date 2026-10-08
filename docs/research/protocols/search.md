# 搜索请求与查询会话

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 搜索请求与查询会话

BBHD2PhoneSearchResultVM.querySearchResult:focusUpdate:...（0x10de96570）对空查询、
loading、分页结束设入口检查，维护 latestQuery/source/is_org_query、offsetPage，
并按 searchType 分派综合/分类搜索；tryAv 分支还支持将编号查询转入视频入口。
搜索历史写入发生在请求成功之前，不能从本地历史条目推断搜索请求成功。
并发取消的回调防串扰属运行期对象生命周期，静态不可定；UI 提交来源、分类枚举与编号识别
（tryAv）入口已锚定在0x10de96570，下一步 disassemble.py 0x10de96570 0x10de96a4c 与
query_index.py '*BBHD2PhoneSearchResultVM*' 30 逐方法核对。

综合 searchAll（0x10de97108）先查 useGrpcSearchAPI；helper 0x112758504 使用
实验键 search_grpc_pagination_hd、presetHitValue=0。命中则转 grpcSearchAll，
否则创建 BBHD2PhoneSearchApiV2，赋值 page=offsetPage、pageSize=20、keyword、
order、type、duration、rid、fromSource、recommend=true、is_org_query。
local_time 由 localTimeZone.secondsFromGMT 整数除以 3600 得到，非完整时区标识。
offsetPage==1 时用 NSUUID.UUIDString 更新 VM.qv_id，其他页复用 VM.qv_id，
再赋给本次 API。因此 qv_id 是查询分页层的会话，不能用 App Session_ID 替代。

ApiV2.params（0x10de728a0）先 mutableCopy preloadUrlParams，再覆盖 11 个字段：
keyword（nil→空）、pn、ps、duration、order、rid、from_source（nil→空）、
highlight=`1`、recommend、is_org_query、local_time；整数/布尔经 NSNumber.stringValue。
order 直接索引 `[default, view, pubdate, danmaku]`，未在此 getter 看到边界 clamp。
qv_id.length>0 时再加入 qv_id。预加载参数来源见前节，不能默认全为固定值。

addToQueueAsync（0x10de7309c）以 `https://app.bilibili.com/x/v2/search` 创建
BFCApiOptions，设置 modelDescriptions/params、completion、可选 customResponseAfterRequest、
cachedHandler 与 errorHandler，然后 BFCApiRequest.requestAsync；此层未显式改 method，
零初始化 method=0 进入公共 builder 默认 GET 构造路径；customRequest/
requestInjection 仍可修改。缓存触发见公共层，具体业务配置仍需核对。成功桥接 block
（0x10de73244）从模型路径取 nav、season2/movie2/archive/upper/operation/
suggest_keyword、item、trackid、exp_str、easter_egg、ogv_card、esport 等结果。
旧模型数组与新接口返回的分页游标不能混用。

grpcSearchAll（0x10de96a4c）在已有 dataSource 的后续页调用 nextPageWithCompletion；
初次创建 BBListSearchMainDataService，传 keyword、from、extraInfo.from_trackid、
isOriginalSearch，并将 forcedChatCard 设假。首次 update 另传 order、duration/rid
数组及 pull-refresh 信息。Swift service 会读取 BAPIPolymerAppSearchV1SearchAllResponse
的 pagination.next 更新状态。

实际 SearchAllRequest 创建段 0x1036d0888→0x1036d08c4、发送段 0x1036d1cb8
调用 Search.searchAllWithRequest:handler:。描述符（0x113da34fc）有 24 项：

| 字段号 | 字段 |
| --- | --- |
| 1–6 | keyword、order、tidList、durationList、extraWord、fromSource |
| 7–12 | isOrgQuery、localTime、adExtra、pagination、playerArgs、fromExtra |
| 13–18 | forcedDisplayChatCard、isRefresh、refreshTimes、since、pubTimeBeginS、pubTimeEndS |
| 19–24 | allDoubleColumn、userAct、needOgvExtraWord、filterMap、foldable、isWideScreen |

创建段已核对：fromSource/keyword 来自 service 实例；order 优先 sortRawValue，否则
sort 枚举，有 Int32 转换溢出检查；isOrgQuery/forcedDisplayChatCard 来自初始化状态；
adExtra 取 BBAdReport.requestAdExtra；localTime 为当前时区偏移小时；playerArgs
由 preloadUrlParams 映射；userAct 向用户行为服务取值。durationList、tidList 经字符串
数组以逗号拼接；duration 有 rawValue 优先和枚举转换路径，不能按字段名推断其单位。
isRefresh/refreshTimes/extraWord/fromExtra/filterMap 向各自实例状态取值，refreshTimes
也做 Int32 转换检查。allDoubleColumn 只在对应实例开关为真时显式置 1。
此段未见给 needOgvExtraWord/foldable/isWideScreen 赋值，但**不能据此判为"静态可证否定"**：
`setNeedOgvExtraWord:` 无专用 msgSend stub，其 selRef 0x11f787d88 在全镜像仍有 **8 处** ADRP+LDR
引用（`find_pointer_refs.py 0x11f787d88` 实测），属主为
-[HalfPanelHandler.PanelNavigationBar_.cxx_destruct] 5 处（0x1009ff648）、
-[ResultViewController collectionView:willDisplayCell:forItemAtIndexPath:] 2 处（0x100a6c258）、
-[BBListSearchChildDataService cancel] 1 处（0x1036cf2d4）；后两处经 `j__objc_msgSend` 动态派发
（0x100a6f364 载入该 selRef，实参为 0 / bool），接收者是 Swift 返回值、静态未定，故该字段
**可能在别处被赋值**。`setFoldable:`/`setIsWideScreen:` 确实连 selRef 都不存在，这一半仍是强否定。
阳性对照为同描述符相邻字段 setIsRefresh 等有 stub 且在创建段赋值。
结论：本字段属"本段未赋值 + 他处动态可能赋值"，最终归属需运行期取值或抓包；运行期拼 selector
/chained-fixup 亦不可静态排除。

日期筛选builder局部已独立闭合：service.since OptionalString非nil才
setSince（0x1036d0d80–0x1036d0dbc），没有length>0门禁，空String仍可设置。
随后独立读取customDateRange（ivar0x120421038），Optional无值则跳过日期两项
（0x1036d0e28–0x1036d0e44），不由since是否存在决定。存在时取range起点，
Calendar.current.startOfDay（0x1036d0e74）→timeIntervalSince1970
（0x1036d0e98），检查有限及Int64转换范围后FCVTZS截断写pubTimeBeginS
（0x1036d0ee4–0x1036d0ef4）。终点经helper0x1036d15cc：使用当前Calendar的
startOfDay（0x1036d1724），再date(byAdding:day,value:1,wrapping:false)
（0x1036d1728–0x1036d1758），成功取下一天起点减1秒
（0x1036d17c0–0x1036d17d8）；若calendar加一天返回nil，则用输入终点原始
epoch秒（0x1036d1798–0x1036d17a0）。外层同样有限/Int64边界检查后截断写
pubTimeEndS（0x1036d0f04–0x1036d0f4c）。这不是UTC固定起点+86400秒，
也没有在该body交换起止/清since的分支；实际UI输入、时区变化及日期范围写入
仍须沿consumer核实，不据可选字段存在宣称每次搜索都带日期。

BBListSearchMainDataService自身的实现选择另有process-once flag，不能直接视为
外层每次searchAll的实验查询。initializer0x1036cb0b8对bfc_isIPad=true才读
search_grpc_pagination_hd/preset0（0x1036cb0e0–0x1036cb104），phone分支固定1
（0x1036cb118），保存0x120420e28；once token0x120420e20。
nextPageWithCompletion0x1036cb8b8将空附加参数map传helper0x1036cb598，flag
恰1才用grpcService，否则httpService（0x1036cb618/0x1036cb750）；选中service
nil直接退出0x1036cb880，该body没有转另一个service的fallback。
grpc分支记录requestDidStartTimestamp，并把isPullRefresh附加参数值与String
"1"比较后更新service布尔；附加map空/该key缺失时走0x1036cb808，未在此明确
重置旧isPullRefresh。其generic send结果closure0x1036ce964→0x1036cee3c拆
pointer/tag，实际captured callback0x1036ce954→0x1036cb944。后者weak main
service存在时先写requestDidEndTimestamp；error-tag分支直接交错误callback，
不更新hasMoreData。success且weak service存在时要求response.pagination与next
非nil（nil各到BRK 0x1036cbba4/0x1036cbba8），按next String是否非空写
hasMoreData（0x1036cbaec–0x1036cbb20），再交业务callback
（0x1036cbb60）。没有以返回卡数代替游标判据；weak service失效仍可交结果。
这段callback未见查询/账号generation比较，不能据现对象存在推断旧回执属于
最新query；外层取消隔离由运行期对象生命周期决定，静态不可另证，且本service公开cancel
0x1036cc8d8已闭合为无操作，残余仅能以真机快速翻页抓包验证回执归属。
公开BBListSearchMainDataService.cancel:0x1036cc8d8本体仅检查上述once token，
未初始化时tail swift_once初始化flag（0x1036cc8ec–0x1036cc8fc），已初始化则直接
ret；没有读取httpService/grpcService/currentRequest、调用cancel、清游标或增加
generation。仅调用这个selector不能视为已中止底层或已过滤旧回执；其他UI/
外层VM取消链需分开审计。该结论限定当前样本方法体，不推广到其他搜索service。

通用分页请求段0x1036d6d28创建BAPIPaginationPagination，pageSize和next分别
由service witness+0x40/+0x28取得（0x1036d6db8–0x1036d6dd8），不是仅据属性名
断言读取maxLength。当前All binding witness0x120421820的+0x40实际
0x1036d29e8固定返回20；constructor0x1036d0644的maxLength+0x28实际来自
list.search_word_max_length/default150（0x1036d0698–0x1036d06d8），不能把该
值当pagination.pageSize。+0x28→0x1036d4f70→0x1036d44f8读取实例+0x10的
OptionalString nextToken。构造中next nil传nil，非nil（包括空String）bridge后
setNext（0x1036d6e18–0x1036d6e4c），没有空游标拒发门禁。request getter
witness+0x48→0x1036d29f0→0x1036d083c创建上述SearchAllRequest，随后关联
pagination，再通过send闭包witness+0x50→0x1036d2a14。日期筛选的
since/customDateRange UI来源、完整 PlayerArgs 默认值、空游标结束判断、HTTP 回退
条件属运行期UI状态与process-once flag，静态不可穷尽。空游标结束判断已闭合：hasMoreData
仅由pagination.next是否为空String决定（0x1036cbaec–0x1036cbb20）。服务端搜索链行为属
9.13抓包事项，静态不可验（POST /polymer/app/search/v1/searchAll）。

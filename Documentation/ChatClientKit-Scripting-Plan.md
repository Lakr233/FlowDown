# ChatClientKit Scripting — Implementation Plan

> 目标 reviewer:Codex。
> 本文档同时承载 **设计理念**(Why)与 **实施计划**(How),便于在不丢失上下文的前提下做代码审查。

---

## 0. 背景与目标

FlowDown 通过 `ChatClientKit` 对接各类 LLM provider(OpenAI Chat Completions、OpenAI Responses、OpenRouter、各家 OEM 兼容端)。随着 provider 行为分化加剧:

- 有的需要在 header 里做请求签名,且对 **顺序敏感**;
- 有的把 reasoning chain 加密 + 签名后回传,要求下一轮原样带回(防止抽取思维链);
- 有的 SSE 格式跟 OpenAI 不兼容,需要自定义解包;
- 客户端发版周期长,而 provider 改协议是高频事件 —— 不希望每次都发 app 更新。

为此我们引入 **可由开发者动态注入的脚本钩子**,让 ChatClientKit 在请求发出前与响应返回时可执行一段开发者编写的 JavaScript。

### 关键约束(产品/合规)

1. **脚本不允许在 app 内编辑**。任何编辑入口都会让 Apple Review 看到 JS 注入能力,带来审核风险。脚本只通过 **plist 编辑器** 写入,跟随导入/导出走。
2. **脚本来源可信**。脚本由 FlowDown 开发者(或受信开发者)写好,经 plist 配置打包/导入。不存在终端用户编写脚本的入口。
3. **崩溃优于挂死**。脚本如果死循环或长耗时,客户端宁可 `fatalError` 也不要静默卡住 —— 因为脚本由开发者负责,bug 必须被立刻发现。

---

## 1. 设计理念(必读)

以下原则在评审时若需偏离,请在 PR 描述里显式说明并征求维护者意见:

### 1.1 Storage:additive only,永不 rename
- 历史上 rename 字段引发过生产事故。新增字段使用 **通用容器**(`ext_data: ExtensionDictionary`),内部用字符串 key 隔离不同模块的扩展数据。
- 容器一旦定型,**字段名 `ext_data` 永不 rename**,内部保留 key 名(如 `chat_client_kit_scripts`)也 **永不 rename**。

### 1.2 强类型 I/O 边界
- 脚本是动态世界,Swift 是静态世界。两个世界的交界处必须用 **强类型 struct** 表达(`PreProcessOutput` / `PostProcessOutput` 等),不允许出现 "拿一个 `Any` 在 Swift 里到处传" 的写法。
- 强类型结构内部 **允许** 出现一个 `AnyCodingValue` 字段用来承载真正自由的 JSON(例如 `body`)—— 但这个口子必须被结构包裹起来。

### 1.3 端到端走 streaming
- 经讨论确认:**所有路径统一走 SSE streaming**。`chat()` 不再独立实现,而是消费 streaming 后聚合成 `ChatResponse`。
- 好处:post_process 只需处理一种数据形态(行/字节),不再做"流 vs 非流"的双向兼容。

### 1.4 saveContext 同步落盘
- 数据正确性优先于性能。脚本调 `cck.saveContext(value)` 时:Swift 同步写 WCDB → 写完再让 JS 返回 → 再让网络 IO 继续。
- 我们已经接受了 JavaScriptCore 的性能开销,这一点点同步写盘对体感无影响,换来的是**不丢上下文**。

### 1.5 全量 chat session 传入,不做按需访问
- 整个 `ChatRequestBody`(包含图片 base64 在内)序列化后注入 JS。
- 不做"按需拉取"的 API,因为 provider 脚本既然要处理这些数据,内存已经不可避免要承载 —— 加一层懒接口只会让脚本编写变复杂,不会节省真实内存。

### 1.6 header 顺序:best-effort,不承诺 wire order
- **修正(Round 1)**:`URLRequest.allHTTPHeaderFields` 是 Dictionary,URLSession + HTTP/2 不承诺 on-the-wire header 顺序。计划之前"100% 顺序保留"的 claim 是错的。
- 我们 **按 JS 给出的顺序逐个 `setValue`**,这只能保证 URLRequest 内部 storage 的插入顺序;实际发包顺序由 CFNetwork / HTTP2 stack 决定,未文档化。
- **结论**:对于"签名依赖 header 发送顺序"的 provider —— **不支持**。脚本作者应当选择 canonical-header 签名方案(如 AWS SigV4:按字典序拼接 canonical headers,顺序无关)。计划文档要明确写"header order is best-effort, not a contract"。
- 大小写:URLSession 对部分保留 header 会规整(如 `Authorization`),其余通常保留。同样 best-effort。

### 1.7 SSE 行剥离:由 `ServerSentEvent.parse` 唯一负责
- **Round 1 fix**:`Frameworks/ChatClientKit/Sources/ServerEvent/ServerEvent.swift` 的 `ServerSentEvent.parse` 已经按 SSE 规范剥掉 `data:` 前缀和最多一个空格。
- **不**新增计划里之前的 `sseStripDataPrefix` helper(那会 double strip,吃掉 payload 真实前导空格)。`event.data` 直接喂 JS。
- 如果未来需要 "未 strip 的 raw line",必须在 `ServerSentEvent.parse` 调用 **之前** 接入,而不是之后再 strip。

### 1.8 fatalError on script timeout(实现限制重新表述)
- 5 秒硬超时(超时即 `fatalError`)。开发者负责把脚本写明确。
- **修正(Round 1)**:JavaScriptCore **不支持 preemption**。`DispatchSemaphore` 超时只让 Swift 一侧放弃等待,JS 仍占用 ScriptRunner 的 dedicated queue 直至自然结束 —— 因此 `fatalError` 之后整个进程立刻终止是必要的,不能"降级 throw"。
- **测试模式不再尝试在 in-process 真实跑死循环**。Runner 内部不再提供 `onTimeout` 闭包(否则单测会被永远卡住的 JS 拖死)。timeout 路径的测试改为:
  - **单元测试**:抽象 `ScriptExecutor` 协议,Runner 是其默认实现;timeout 行为通过 mock executor + 注入"假装 timeout"路径覆盖;不真跑死循环 JS。
  - **集成测试(可选)**:跑一个 `XCTest` subprocess,在子进程里跑真死循环 JS,父进程断言子进程在 ~5s 内以非零状态退出(fatalError)。

### 1.9 JavaScriptCore-only
- 自带、签名审核无风险、跨 iOS/macOS 一致。不引入 QuickJS / V8 / Hermes —— 那些都需要 ship 二进制,过 review 时风险大。

### 1.10 token 脱敏:白名单 + 卫生措施,不是安全边界
- `manifest` 注入脚本时 **走白名单**:adapter 显式列出可导出字段(`objectId / name / model_identifier / endpoint / headers / bodyFields / capabilities / context / response_format / comment`),其余 **一律不导出**。
- **诚实说明**:在 `inherit=true` 模式下,脚本能从 headers 数组里读到 `Authorization: Bearer sk-...` 明文。因此 manifest 的脱敏 **不是安全边界**,只是减少无意暴露面。
- **白名单选择动因(Round 2 codex HIGH #11)**:黑名单做法(`token / apiKey / api_key` 这种)经不起 CloudModel 后续新增字段(新加敏感字段会自动漏)。白名单则要求"新加字段时主动 review 是否值得放进 manifest",符合 default-deny 原则。
- 安全模型前提:**脚本来源是可信开发者**(见 §0 关键约束),已经隐含 trust 凭据。如果哪天放开终端用户脚本,这个 trust 假设就崩了,需要重新设计(那是另一项目)。

### 1.11 ScriptRunner per-invoke 开销
- **Round 1 fix**:`manifest` 和 `chatSession` 在 **ScriptRunner.init** 时通过 `JSContext.setObject` + JS `deepFreeze` 注册为全局只读对象,生命周期 = 整个请求。每次 invoke 只传入 **chunk-local** 输入。
- 脚本里依然能直接读 `manifest` / `chatSession` 全局符号,语义等价。
- **遗留性能开销(Round 2 codex MED #10)**:每次 invoke 仍需 `JSContext.setObject(bindings)` + `evaluateScript` 包一层 IIFE + `JSON.stringify(__result)` + Swift `JSONDecoder`。1000-chunk 的长 stream × 这条链路在低端 iOS 设备上仍可能感知到延迟。
- **缓解(本期不做,作为 follow-up)**:
  - 把脚本预编译成 JS function(`JSContext.evaluateScript("(function(line){ ...user script... })")` 一次,后续 `JSValue.call(withArguments:)` 跳过 parse),避免每次 invoke 重新 parse 用户脚本。
  - 跳过空 `data:` 行不调用 JS。
  - 这些优化作为 follow-up issue 列在 §11 中,本期发版不强制。

---

## 2. 数据流总览

```
                                       ┌─────────────────────────────┐
                                       │ CloudModel.ext_data         │ ExtensionDictionary
                                       │   ["chat_client_kit_scripts"│  ([String:String])
                                       │     ] = "<plist string>"    │
                                       └──────────────┬──────────────┘
                                                      │ decode plist
                                                      ▼
                                       ┌─────────────────────────────┐
                                       │ ChatClientKitScriptConfig   │
                                       │   pre_process { inherit,src}│
                                       │   post_process{ inherit,src}│
                                       └──────────────┬──────────────┘
                                                      │
┌──────────────────┐    inject    ┌──────────────────▼─────────────────┐
│ Conversation     │─────────────►│  ChatScriptingHandle               │
│  .ext_data       │  closures    │  - conversationId                  │
│  ["chat_client_  │◄────────────►│  - config                          │
│    kit"] = "..." │  read/write  │  - manifest (token redacted)       │
│                  │  (sync I/O)  │  - readContext / writeContext      │
└──────────────────┘              └────────────────┬───────────────────┘
                                                   │
                                                   ▼
                                       ┌──────────────────────────────┐
                                       │ ScriptRunner (per request)   │
                                       │  - JSContext on dedicated thr│
                                       │  - shared `context` object   │
                                       │  - 5s timeout → fatalError   │
                                       └──┬─────────────────────────┬─┘
                                          │                         │
                                  pre_process                 post_process
                                          │                         │
        ────────────────────────────────────────────────────────────────────
        STAGE 1: PRE                                STAGE 2: POST (N times)
        ────────────────────────────────────────────────────────────────────
        ChatRequestBody built                       URLSession streams SSE
                  │                                            │
       inherit == true ?                           inherit == true ?
       ┌──── yes ────┴── no ────┐                  ┌── yes ────┴─── no ────┐
       │                        │                  │                       │
   we build:                JS builds from scratch  we decode line:        we trim line per
   - URL/auth/CT          (URL still ours)         {reasoning,            §1.7 rule and feed
   - default headers       JS gets:                content, tool_calls}   raw STRING to JS
   - body = JSON()           headers: []           feed obj to JS
   JS gets:                  body:    {}
   headers: [{name,value}]  manifest, context,    JS may mutate ctx,
   body: AnyCodingValue     chatSession           call cck.saveContext()
   manifest, context,
   chatSession
       └──────────┬─────────────┘                  └──────────┬────────────┘
                  ▼                                            ▼
        JS returns                                  JS returns
        { headers: [...], body: ... }                { reasoning?, content?,
                  │                                    tool_calls?: [...] }
        request.allHTTPHeaderFields = nil                     │
        for entry in out.headers: setValue                    ▼
                  ▼                                  yield ChatResponseChunk
        URLSession.dataTask → SSE
                  │
                  └──────────────► STAGE 2 loops

        ────────────────────────────────────────────────────────────────────
        STAGE 3: STREAM CLOSE
        ────────────────────────────────────────────────────────────────────
        - cck.saveContext(value) 已经在脚本执行期间同步落过盘。
        - ScriptRunner 在 stream 结束时丢弃 JSContext。
```

---

## 3. Storage 层

### 3.1 新类型:`ExtensionDictionary`

**新文件**:`Frameworks/Storage/Sources/Storage/Tables/Extensions/ExtensionDictionary.swift`

```swift
/// 通用的 per-record 扩展数据容器。每张表只允许出现一个此字段。
/// 字段名为 `ext_data`(避开 Swift 关键字 `extension`,Round 1 codex 提醒)。
/// **永不 rename**。
public struct ExtensionDictionary: Codable, Equatable, Hashable, Sendable {
    public private(set) var storage: [String: String]

    public init(_ storage: [String: String] = [:]) { self.storage = storage }

    public subscript(key: String) -> String? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
}

extension ExtensionDictionary: ColumnCodable {
    public static let columnType: ColumnType = .text
    public init?(with value: Value) {
        let data = Data(value.stringValue.utf8)
        guard !data.isEmpty else { self = .init(); return }
        if let decoded = try? PropertyListDecoder().decode([String: String].self, from: data) {
            self = .init(decoded); return
        }
        self = .init()   // fail-safe: 老库无数据 / 损坏 → 空 dict
    }
    public func archivedValue() -> Value {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml   // 显式 XML;binary plist 走 TEXT 列会丢数据(Round 1 codex)
        guard let data = try? encoder.encode(storage),
              let str  = String(data: data, encoding: .utf8) else { return .init("") }
        return .init(str)
    }
}
```

> **Round 1 fix**:codex 指出 `PropertyListEncoder` 默认其实是 XML(不是 binary,我之前担心错了),但仍显式 `outputFormat = .xml`,避免未来变更默认值踩坑。

### 3.2 保留 key 常量

**新文件**:`Frameworks/Storage/Sources/Storage/Tables/Extensions/ExtensionKey.swift`

```swift
public enum ExtensionKey {
    /// CloudModel.ext_data 里挂的脚本配置(plist-encoded ChatClientKitScriptConfig)
    public static let chatClientKitScripts = "chat_client_kit_scripts"
    /// Conversation.ext_data 里挂的脚本运行时上下文(脚本通过 saveContext 写入的字符串)
    public static let chatClientKit = "chat_client_kit"
}
```

### 3.3 `CloudModel.swift` 改动

```swift
public package(set) var ext_data: ExtensionDictionary = .init()

// 在 TableBinding 中:
BindColumnConstraint(ext_data, isNotNull: true, defaultTo: ExtensionDictionary())

// CodingKeys: 增加 case ext_data
// init(from:): 增加 `ext_data = try container.decodeIfPresent(...) ?? .init()`
// hash(into:):增加 hasher.combine(ext_data)
// 平等 / Hashable / 显式 init 同步更新。
```

> **Round 1 fix**:字段名从 `extension` 改为 `ext_data` —— Swift 关键字反引号传播全代码会噪;同时避开 WCDB TableBinding KeyPath 反射的潜在坑(codex HIGH)。

### 3.4 `Conversation.swift` 改动

完全对称,加同名 `ext_data: ExtensionDictionary = .init()`。

### 3.5 Migration:必须显式新增版本(Round 1 BLOCKER)

**修改文件**:`Frameworks/Storage/Sources/Storage/Storage/DBVersion.swift` —— 加 `case Version7 = 7`,把它加进 migrations 链与 `allowedVersions`。

**新增文件**:`Frameworks/Storage/Sources/Storage/Storage/Migrations/MigrationV6ToV7.swift`

```swift
struct MigrationV6ToV7: DBMigration {
    let fromVersion: DBVersion = .Version6
    let toVersion:   DBVersion = .Version7
    let requiresDataMigration: Bool = false

    func migrate(db: Database) throws {
        let start = Date.now
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) begin")

        // ext_data 列加到 CloudModel / Conversation。WCDB 的 db.create(table:of:)
        // 对已存在表等价于 schema 对齐(补缺失列),与 V3ToV4 加 bodyFields、
        // V2ToV3 加 Message 字段的既有模式一致。
        try db.create(table: CloudModel.tableName,   of: CloudModel.self)
        try db.create(table: Conversation.tableName, of: Conversation.self)

        try db.exec(StatementPragma().pragma(.userVersion).to(toVersion.rawValue))

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) end elapsed \(Int(elapsed))ms")
    }
}
```

migration runner 注册 `MigrationV6ToV7()`,`.Version7` 加入 `allowedVersions`。

具体落点(`Frameworks/Storage/Sources/Storage/Storage/Storage.swift`):
- Storage 有 **两条** migrations 数组 —— 一条用于 existing DB 升级(老库逐版本升),一条用于 new DB 初始化(从 0 跳到最新)。两条都要追加 `MigrationV6ToV7()`(`requiresDataMigration` 参数本 migration 不需要,沿用默认 `false`)。
- `DBVersion` 已经是 `CaseIterable`,所以 `allowedVersions = DBVersion.allCases` 自动包含 `.Version7`。新增 enum case 之外不必另开 allow-list。

> **Round 1 fix**:codex 确认 WCDB **不会**自动 ALTER。每次加列必须 versioned migration + bump userVersion,与已有 V2→V3、V3→V4 同一模式。计划之前"自动 ALTER"的说法是错的。

### 3.6 Storage 公开 mutation API(Round 3 codex BLOCKER #9 → Round 4 修订)

`CloudModel.ext_data` / `Conversation.ext_data` 是 `public package(set)`,**app target 只能读不能写**。adapter 写 context 必须通过 Storage 包提供的显式 API。

**Round 4 codex BLOCKER #1 / #2 / HIGH #3**:
- 现有 `Storage+Conversation.swift` 只有 `conversationWith(identifier:)` / `conversationUpdate(object:)`,**没有** handle 重载。
- 现有 `conversationUpdate(objects:)` 用 `try? runTransaction`,会吞掉所有 WCDB 写入错误 —— saveContext 同步语义要求"失败要可见",不能静默。
- 现有 `conversationUpdate` 不会自动 `markModified`;`diffSyncable` 比较 `modified`,不 bump 就被判定为无变化,upload queue 不会同步。

**对应改动**:

1. 在 `Storage+Conversation.swift` **新增** throws 版本 `conversationUpdateThrowing(objects:)`,跟现有 `conversationUpdate(objects:)` 逻辑一致但用 `try runTransaction` 而非 `try? runTransaction`,把错误抛出来:
   ```swift
   public extension Storage {
       func conversationUpdateThrowing(object: Conversation) throws {
           try conversationUpdateThrowing(objects: [object])
       }
       func conversationUpdateThrowing(objects: [Conversation]) throws {
           guard !objects.isEmpty else { return }
           let modified = Date.now
           try runTransaction { [weak self] handle in
               guard let self else { return }
               let diff = try diffSyncable(objects: objects, handle: handle)
               guard !diff.isEmpty else { return }
               diff.insert.forEach { $0.markModified($0.creation) }
               try handle.insertOrReplace(diff.insertOrReplace(),
                                          intoTable: Conversation.tableName)
               // deleted 分支:跟现有 conversationUpdate(objects:) 一致,不偷懒省略(Round 5 codex MED #1)
               if !diff.deleted.isEmpty {
                   let deletedIds = diff.deleted.map(\.objectId)
                   let update = StatementUpdate().update(table: Conversation.tableName)
                       .set(Conversation.Properties.removed).to(true)
                       .set(Conversation.Properties.modified).to(modified)
                       .where(Conversation.Properties.objectId.in(deletedIds))
                   try handle.exec(update)
               }
               var changes = diff.insert.map { ($0, UploadQueue.Changes.insert) }
                           + diff.updated.map { ($0, UploadQueue.Changes.update) }
                           + diff.deleted.map { ($0, UploadQueue.Changes.delete) }
               changes.sort { $0.0.modified < $1.0.modified }
               try self.pendingUploadEnqueue(sources: changes, handle: handle)
           }
           Task { try? await syncEngine?.sendChanges() }
       }
   }
   ```

2. `conversationExtDataPut` 用上面那个 throws 变体,**而且写 ext_data 后必须 `markModified()`**(否则 diffSyncable 判无变化、不上同步队列):
   ```swift
   public extension Storage {
       /// 写 Conversation.ext_data[key]。失败抛错(不像 conversationUpdate 那样 try? 吞)。
       func conversationExtDataPut(
           id:    Conversation.ID,
           key:   String,
           value: String?
       ) throws {
           guard let conv = conversationWith(identifier: id) else {
               throw StorageError.conversationNotFound(id)
           }
           var ext = conv.ext_data
           ext[key] = value
           conv.ext_data = ext      // package 包内可写
           conv.markModified()       // 强制 bump modified → diffSyncable 看到变化 → upload queue 入队
           try conversationUpdateThrowing(object: conv)
       }
   }
   ```

3. `StorageError.conversationNotFound(id)` 加到 Storage 的 `enum StorageError`(若没有就新建)。

4. 对称地为 `Storage+CloudModel.swift` 加 `cloudModelExtDataPut(id:key:value:) throws`(本期 adapter 暂不调用,但留接口对称便于未来其他模块用)。

### 3.7 Storage 测试

**新文件**:`Frameworks/Storage/Tests/StorageTests/ExtensionFieldTests.swift`
- 默认值为空 dict
- 从 V6 schema 升 V7:先用 V6 schema 写一条 CloudModel / Conversation 进去,跑 `MigrationV6ToV7`,断言 `ext_data` 列存在且为空 dict
- `conversationExtDataPut` round-trip(set → fetch → 再 set 覆盖 → fetch 验证)
- `conversationExtDataPut(value: nil)` 删除 key 行为
- 损坏数据(写一段非 plist 的 garbage 进 TEXT 列)→ `ColumnCodable.init?(with:)` 回退空 dict 不抛
- migrations 数组:验证 `Storage.swift` 里 existing-DB 与 new-DB 两条迁移链都包含 `MigrationV6ToV7()`

---

## 4. ChatClientKit 脚本运行时

### 4.1 配置结构

**新文件**:`Frameworks/ChatClientKit/Sources/ChatClientKit/Scripting/ChatClientKitScriptConfig.swift`

```swift
public struct ChatClientKitScriptConfig: Codable, Sendable, Equatable {
    public struct Stage: Codable, Sendable, Equatable {
        public var inherit: Bool
        public var script: String
        public init(inherit: Bool, script: String) {
            self.inherit = inherit; self.script = script
        }
    }
    public var preProcess: Stage?
    public var postProcess: Stage?

    enum CodingKeys: String, CodingKey {
        case preProcess  = "pre_process"
        case postProcess = "post_process"
    }
}

public extension ChatClientKitScriptConfig {
    /// 从 plist 字符串解码;失败回退 nil(等价于"未启用脚本")
    static func decodePList(_ string: String) -> Self? {
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        return try? PropertyListDecoder().decode(Self.self, from: data)
    }
}
```

### 4.2 强类型 I/O

**新文件**:`Frameworks/ChatClientKit/Sources/ChatClientKit/Scripting/ScriptIO.swift`

```swift
/// 注入给 pre_process 的 headers,顺序敏感
public struct ScriptHeaderList: Codable, Sendable {
    public struct Entry: Codable, Sendable { public var name: String; public var value: String }
    public var entries: [Entry]
}

public struct PreProcessOutput: Codable, Sendable {
    public var headers: ScriptHeaderList
    public var body:    AnyCodingValue
}

public struct PostProcessOutput: Codable, Sendable {
    public struct ToolCall: Codable, Sendable {
        public var id: String
        public var name: String
        public var args: String   // JSON string,跟 ToolRequest 对齐
    }
    public var reasoning:  String?
    public var content:    String?
    public var toolCalls:  [ToolCall]?

    enum CodingKeys: String, CodingKey {
        case reasoning, content
        case toolCalls = "tool_calls"
    }
}

/// 整个 ChatRequestBody 的脚本镜像(包含 image base64)
public struct ChatSessionSnapshot: Codable, Sendable {
    public var model: String?
    public var messages: [AnyCodingValue]
    public var tools: [AnyCodingValue]?
    public var stream: Bool?
    public var temperature: Double?
    public var maxCompletionTokens: Int?
}

/// 不在 ChatClientKit 里手写枚举 CloudModel 字段,而是接受 app-layer
/// 编完的不透明 dict —— 这样新加字段时 ChatClientKit 不用改。
/// 由 FlowDown app 的 adapter 层(见 §8)负责从 CloudModel 编码而来。
public struct ManifestSnapshot: Codable, Sendable {
    /// app-layer 序列化后的 CloudModel snapshot。
    /// 适配层应已用 redacted 替换敏感字段(详见 §1.10 安全模型)。
    public var payload: AnyCodingValue
}
```

> **Round 1 fix**(codex MED #7、MED #10):
> - 不在 ChatClientKit 里手写 `ManifestSnapshot` 半个 CloudModel 镜像(漏字段、新增字段要双改);ChatClientKit 也不能 `import Storage`。
> - DTO 留在 ChatClientKit(`ManifestSnapshot { payload: AnyCodingValue }`),mapper 放 **FlowDown app/adapter 层**,从 `CloudModel` → JSON dict → `AnyCodingValue` 后塞进 `payload`;app 层负责脱敏字段。
> - 在 ChatClientKit 里 redact 不可行,因为它不知道哪个字段是 token。

### 4.3 `ScriptRunner`

**新文件**:`Frameworks/ChatClientKit/Sources/ChatClientKit/Scripting/ScriptRunner.swift`

```swift
import JavaScriptCore

final class ScriptRunner: @unchecked Sendable {
    private let queue: DispatchQueue
    private let ctx: JSContext
    private let bridge: ScriptBridge

    init(
        initialContextJSON: String,
        manifest: ManifestSnapshot,
        session:  ChatSessionSnapshot,
        bridge:   ScriptBridge
    ) throws {
        queue  = DispatchQueue(label: "cck.script.\(UUID().uuidString)", qos: .userInitiated)
        ctx    = JSContext()!
        self.bridge = bridge

        // toJSObject 在 queue.sync 之外执行 —— init 是 throws,但 queue.sync 闭包里 try 不能向 init 传播,
        // 必须先在外层算好结果(Round 3 codex BLOCKER #4)。
        let manifestObject = try Self.toJSObject(manifest)
        let sessionObject  = try Self.toJSObject(session)

        queue.sync {
            // cck.* bridge
            ctx.setObject(bridge, forKeyedSubscript: "cck" as NSString)

            // 安全注入 helper:不拼字符串进 JS 源,改为 setObject + 一次性 JS function 调用,
            // 避免 manifest/session/context 里有 `</script>`、反引号、`" "` 等导致语法注入。
            // (Round 2 codex HIGH #4)
            installSafeImmutableGlobal("manifest",    object: manifestObject)
            installSafeImmutableGlobal("chatSession", object: sessionObject)

            // context 起点:DB 字符串走 JS 端 JSON.parse + 严格类型校验。
            // JSON.parse 可能返回 array / null / scalar / string;脚本里的 `context.foo = ...`
            // 在这些类型上会爆。所以必须是 plain object,否则回退 `{}`(Round 3 codex MED #5)。
            ctx.setObject(initialContextJSON, forKeyedSubscript: "__contextJSON" as NSString)
            ctx.evaluateScript("""
            var context = (function() {
              try {
                if (typeof __contextJSON !== "string" || __contextJSON.length === 0) return {};
                var v = JSON.parse(__contextJSON);
                if (typeof v === "object" && v !== null && !Array.isArray(v)) return v;
                return {};
              } catch (e) { return {}; }
            })();
            delete globalThis.__contextJSON;
            """)
        }
    }

    /// 把 Codable 值转成 JSValue:走 Foundation JSON 再交给 JSContext,
    /// 避开"拼字符串进 evaluateScript"的注入风险。
    private static func toJSObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func installSafeImmutableGlobal(_ name: String, object: Any) {
        // 1. 用 setObject 注入,不拼字符串
        ctx.setObject(object, forKeyedSubscript: name as NSString)
        // 2. 一次性 deep-freeze,防止脚本无意修改"只读"对象
        ctx.evaluateScript("""
        (function deepFreeze(o) {
          if (o === null || typeof o !== "object") return;
          Object.freeze(o);
          for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) deepFreeze(o[k]);
        })(globalThis["\(name)"]);
        """)
    }

    /// Per-invoke 调用。bindings 只承载 chunk-local 输入(headers/body, line, parsed)。
    /// manifest / chatSession / context / cck 已经常驻全局。
    func invoke<Output: Decodable>(
        script: String,
        bindings: [String: Any],
        decoding _: Output.Type = Output.self
    ) throws -> Output {
        let sem = DispatchSemaphore(value: 0)
        var jsonResult: String?
        var jsError: String?

        queue.async { [self] in
            for (k, v) in bindings {
                ctx.setObject(v, forKeyedSubscript: k as NSString)
            }
            // 约定:脚本必须给 globalThis.__result 赋值,然后由 wrapper JSON.stringify。
            let wrapped = """
            (function() {
              var __result = undefined;
              \(script)
              ;return JSON.stringify(__result);
            })()
            """
            if let value = ctx.evaluateScript(wrapped), !value.isUndefined {
                jsonResult = value.toString()
            }
            if let exception = ctx.exception {
                jsError = exception.toString()
                ctx.exception = nil
            }
            sem.signal()
        }

        if sem.wait(timeout: .now() + 5) == .timedOut {
            // Round 1 fix: 不再支持 onTimeout 闭包注入。
            // JSCore 无 preemption,JS 仍占着 queue;只有进程死才能释放。
            fatalError("ChatClientKit script exceeded 5s budget — developer must fix the script. Process is doomed.")
        }

        if let err = jsError { throw ScriptError.jsException(err) }
        guard let json = jsonResult,
              let data = json.data(using: .utf8) else { throw ScriptError.noOutput }
        return try JSONDecoder().decode(Output.self, from: data)
    }

    enum ScriptError: Error { case jsException(String), noOutput }
}
```

> **Round 1 fixes**(codex BLOCKER #4 + HIGH #6):
> - **大对象一次性绑定**:`manifest` 和 `chatSession`(含图片 base64)在 init 时 `Object.freeze` 为全局。N 个 chunk 的 stream 不再重复桥接 GB 级数据。
> - **去掉 `onTimeout` 闭包**:`(String) -> Never` 闭包根本无法 `throw`;且 JSCore 无 preemption,死循环 JS 还占着 queue,测试模式硬注入 fatalError 替身只会让单测 hang。timeout 路径只能 `fatalError`(进程终结 = 唯一释放方式)。
> - **`context` 改为 JS 全局 var** 而不是 `sharedContext` Swift 持有的 `JSValue`:消除"脚本重新赋值 `context = {...}` 后下次 invoke 读不到"的歧义,JS 直接读写 `globalThis.context`。
>
> **Timeout 测试策略**(参见 §7 测试):不在 in-process 单测里跑真死循环。改用:
> 1. **抽象 `ScriptExecutor` 协议** + Mock 实现,单测路径覆盖 "假装 timeout";
> 2. **可选 subprocess 集成测试**:子进程跑真死循环 JS,父进程断言 ~5s 内子进程以非零状态退出。

### 4.4 `ScriptBridge`(暴露给 JS 的 `cck.*`)

**新文件**:`Frameworks/ChatClientKit/Sources/ChatClientKit/Scripting/ScriptBridge.swift`

```swift
import JavaScriptCore
import CommonCrypto

@objc protocol ScriptBridgeExports: JSExport {
    func saveContext(_ value: JSValue)
    func log(_ message: String)
    func base64Encode(_ s: String) -> String
    func base64Decode(_ s: String) -> String
    func sha256(_ s: String) -> String
    func hmacSHA256(_ key: String, message: String) -> String
}

final class ScriptBridge: NSObject, ScriptBridgeExports, @unchecked Sendable {
    /// 同步写盘闭包。Bridge 调用即落盘,落盘完毕才让 JS 返回。
    /// **约束(Round 1 codex HIGH #5)**:onWriteContext 必须自包含,
    /// 不允许嵌套在调用方持有的 WCDB transaction / 锁里。
    /// **Round 4 codex HIGH #3**:throws 版本 —— 失败必须可见,不允许吞错。
    let onWriteContext: (String) throws -> Void
    init(onWriteContext: @escaping (String) throws -> Void) { self.onWriteContext = onWriteContext }

    @objc func saveContext(_ value: JSValue) {
        guard let ctx = value.context,
              let stringifier = ctx.evaluateScript("JSON.stringify"),
              let json = stringifier.call(withArguments: [value]).toString()
        else {
            let ctx = JSContext.current() ?? value.context
            ctx?.exception = JSValue(
                newErrorFromMessage: "saveContext: value is not JSON-serializable",
                in: ctx
            )
            return
        }
        // 5s watchdog:跨 queue 调 onWriteContext;超时直接 fatalError(对称 §1.8 / §8.4)
        let sem = DispatchSemaphore(value: 0)
        var caught: Error?
        DispatchQueue.global(qos: .userInitiated).async {
            do { try self.onWriteContext(json) }
            catch { caught = error }
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            fatalError("[CCK] saveContext write blocked > 5s — likely WCDB lock inversion in caller chain")
        }
        if let err = caught {
            let ctx = JSContext.current() ?? value.context
            ctx?.exception = JSValue(
                newErrorFromMessage: "saveContext failed: \(err)",
                in: ctx
            )
        }
    }
    @objc func log(_ message: String) { /* logger.info("[script] \(message)") */ }
    @objc func base64Encode(_ s: String) -> String { ... }
    @objc func base64Decode(_ s: String) -> String { ... }
    @objc func sha256(_ s: String) -> String { ... }       // hex
    @objc func hmacSHA256(_ key: String, message: String) -> String { ... } // hex
}
```

> **Round 1 fix(锁反转,codex HIGH #5)**:
> - **禁止**在 WCDB transaction 中间调用脚本(`streamingChat(scripting:)` 不能被嵌在更大的 `db.run(transaction:)` 里)。这一条作为 adapter 层(§8)的硬约束写进 README。
> - `onWriteContext` 实现必须自己开短事务、写完即释放,**不持有任何调用方锁**。否则就和 streaming 调用链外的 DB 操作互相等待 deadlock。
> - 集成测试新增 "脚本 saveContext 时外层无 DB transaction" 重入断言(参见 §7 测试)。

### 4.5 测试

**新文件**:`Frameworks/ChatClientKit/Tests/ChatClientKitTests/Scripting/ScriptRunnerTests.swift`

In-process 单测(快、跑在 CI 上的标准 swift test):
- 跑通一段简单 JS,decode 出 `PreProcessOutput`
- 跨多次 invoke 在同一 ScriptRunner 实例上 `context.foo = 1` → 下一次 invoke 读得到 `context.foo === 1`(覆盖 deepFreeze 不冻 `context` 的契约)
- `chatSession.messages` 在 JS 端 `Object.isFrozen(chatSession.messages)` === true(deepFreeze 生效)
- 一段 JS 试图改 manifest 的属性,断言 strict mode 抛 / 静默丢弃(JSCore 行为为准)
- `cck.saveContext(...)` 在 JS 同步返回前已经触发了 Swift 写盘闭包(用 spy)
- `cck.sha256` / `hmacSHA256` 输出对得上参考向量(RFC 4231 test vectors)
- **Timeout 路径不在 in-process 测**(Round 2 codex MED #12)。

子进程集成测试(可选,不进默认 CI matrix):
- `ScriptRunnerTimeoutSubprocessTests.swift`:fork 一个 XCTest helper 子进程,在子进程里跑死循环 JS,父进程等待 ≤ 7 秒,断言子进程退出码非零、stderr 含 "ChatClientKit script exceeded 5s budget"。
- 不让这个 case 在 PR CI matrix 默认跑(开销大、可能 flake),但放在专用 nightly job。

---

## 5. `ChatService` API 扩展

**改文件**:`Frameworks/ChatClientKit/Sources/ChatClientKit/ChatService.swift`

```swift
public struct ChatScriptingHandle: Sendable {
    public let conversationId: String
    public let config: ChatClientKitScriptConfig
    public let manifest: ManifestSnapshot
    public let readContext:  @Sendable () -> String
    public let writeContext: @Sendable (String) throws -> Void   // 同步落盘语义 + 失败可见(Round 4)
    public init(...)
}

public protocol ChatService: AnyObject, Sendable {
    var errorCollector: ErrorCollector { get }
    /// 唯一 conformer 必须实现的方法。chat(...) 系列由 protocol extension 聚合。
    func streamingChat(body: ChatRequestBody, scripting: ChatScriptingHandle?) async throws -> AnyAsyncSequence<ChatResponseChunk>
}

public extension ChatService {
    // 旧入口(无 scripting)保留,wrapper 即可
    func streamingChat(body: ChatRequestBody) async throws -> AnyAsyncSequence<ChatResponseChunk> {
        try await streamingChat(body: body, scripting: nil)
    }
    func chat(body: ChatRequestBody) async throws -> ChatResponse {
        try await chat(body: body, scripting: nil)
    }
    func chat(body: ChatRequestBody, scripting: ChatScriptingHandle?) async throws -> ChatResponse {
        let chunks = try await chatChunks(body: body, scripting: scripting)
        return ChatResponse(chunks: chunks)
    }
    func chatChunks(body: ChatRequestBody, scripting: ChatScriptingHandle?) async throws -> [ChatResponseChunk] {
        var chunks: [ChatResponseChunk] = []
        for try await chunk in try await streamingChat(body: body, scripting: scripting) {
            chunks.append(chunk)
        }
        return chunks
    }
}
```

> **Round 2 fix(codex BLOCKER #6)**:`chat(body:scripting:)` 不再作为 protocol 必需方法 —— 只在 extension 里给默认实现(聚合 streaming chunks)。
> - 唯一**必需**的 conformer 方法 = `streamingChat(body:scripting:)`。
> - 这样 MLX / AppleIntelligence / Remote* 都只需要实现一个方法,不会因为协议变化导致 4 个 conformer 都要补 `chat(body:scripting:)` 而连环 break。

**Round 1 fix(codex HIGH #12)**:协议加新方法 = 所有 conformer 必须显式实现,否则编译失败。具体步骤:

- `RemoteCompletionsChatClient` / `RemoteResponsesChatClient`(`Frameworks/ChatClientKit/Sources/ChatClientKit/.../*ChatClient.swift`):
  把现有 `streamingChat(body:)` 改名 / 实现成 `streamingChat(body:scripting:)`,旧形态变成 `extension` 里的 wrapper(`{ try await streamingChat(body:body, scripting: nil) }`)。
- `MLXChatClient`(`Frameworks/ChatClientKit/Sources/ChatClientKit/MLXClient/MLXChatClient.swift`):
  实现 `streamingChat(body:scripting:)` —— body 直接调旧逻辑,scripting 参数忽略并加注释说明"MLX 跑本地推理,无网络请求,scripting 钩子不适用"。
- `AppleIntelligenceChatClient`(`Frameworks/ChatClientKit/Sources/ChatClientKit/FoundationModels/AppleIntelligenceChatClient.swift`):
  同 MLX,scripting 参数忽略 + 注释。
- `chat(body:scripting:)` 的默认实现已在 protocol extension 里(消费 streaming 后聚合);conformer **不必**单独实现。
- 编译验证:`swift build` 在 ChatClientKit 包内必须过;`swift build` 在 FlowDown app 整工程也要过。

---

## 6. Pre-processor 集成

**改文件**:
- `Frameworks/ChatClientKit/Sources/ChatClientKit/RemoteCompletionsChatClient/RemoteCompletionsChatRequestBuilder.swift`
- `Frameworks/ChatClientKit/Sources/ChatClientKit/RemoteResponsesChatClient/RemoteResponsesChatRequestBuilder.swift`

新签名:

```swift
func makeRequest(
    body: ChatRequestBody,
    additionalField: [String: Any],
    scripting: ChatScriptingHandle?,
    runner: ScriptRunner?
) throws -> URLRequest
```

流程:

1. 先按现状构造 baseRequest(URL、Authorization、Content-Type、additionalHeaders、JSON body、additionalField merge)。
2. 若 `scripting?.config.preProcess` 存在:
   - `inherit == true` → baseRequest 用现状,把它的 headers/body 注入 JS。
   - `inherit == false` → baseRequest 只保留 URL/method,headers = `[]`,body = `{}` 注入 JS。
3. 调 `runner.invoke(PreProcessOutput.self, ...)`,per-invoke bindings **仅** 包含 chunk-local 输入:
   - `headers`: `ScriptHeaderList.entries` 序列化
   - `body`: `AnyCodingValue`
   - **不**重传 `manifest` / `chatSession` —— 它们在 `ScriptRunner.init` 时已经 deepFreeze 成全局,脚本里直接读全局变量(Round 3 codex MED #12)。
   - `context` 与 `cck` 同样在 init 时一次性注入,见 §4.3。
4. 把 baseRequest header 清空,按 `out.headers.entries` 顺序 set:
   ```swift
   baseRequest.allHTTPHeaderFields = nil
   for entry in out.headers.entries {
       baseRequest.setValue(entry.value, forHTTPHeaderField: entry.name)
   }
   ```
5. `baseRequest.httpBody = try JSONEncoder().encode(out.body)`。

---

## 7. Post-processor 集成

### 7.1 SSE 行处理 —— **不引入新 helper**(Round 1 fix)

**Round 1 codex HIGH #11**:`Frameworks/ChatClientKit/Sources/ServerEvent/ServerEvent.swift` 的 `ServerSentEvent.parse` 已经按 SSE 规范剥掉 `data:` 前缀和最多一个空格。计划之前要新增的 `sseStripDataPrefix` helper 会 **double strip**,吃掉 payload 真实前导空格。

**决定**:
- **不**新增 helper。
- `event.data`(由 EventParser/ServerSentEvent 产出)直接喂给 JS(inherit=false 模式)即可。
- 验证 `ServerEvent.swift` 已丢弃 `:` 开头的 comment line(SSE keep-alive);若发现没做,这是 EventParser 本身的 bug,**在这个 PR 之外** 修。
- 写一个 unit test 覆盖以下输入并断言喂进 JS 的字符串:`"hello"`(`data: hello`)、`" hello"`(`data:  hello`,两个空格)、`"hello"`(`data:hello`,无空格)、`": ping"` 不出现。

### 7.2 `PostProcessor`

**新文件**:`Frameworks/ChatClientKit/Sources/ChatClientKit/Scripting/PostProcessor.swift`

```swift
struct PostProcessor {
    let runner: ScriptRunner
    let stage:  ChatClientKitScriptConfig.Stage
    let manifest: ManifestSnapshot
    let session:  ChatSessionSnapshot

    func processParsedChunk(_ chunk: ChatCompletionChunk) throws -> PostProcessOutput {
        // inherit=true: 我们先把 chunk 拆成 reasoning/content/tool_calls 然后喂 JS
        ...
    }
    func processRawLine(_ line: String) throws -> PostProcessOutput {
        // inherit=false: line 来自 ServerSentEvent.parse(已剥 `data:` 前缀 + 最多一个空格)。
        // 不再二次 strip;manifest / chatSession 已经在 ScriptRunner.init 时常驻全局,
        // 这里只传 chunk-local 输入(Round 1 codex HIGH #6)。
        try runner.invoke(script: stage.script, bindings: [
            "line": line,
        ])
    }
}
```

### 7.3 StreamProcessor 接入

**改文件**:
- `Frameworks/ChatClientKit/Sources/ChatClientKit/RemoteCompletionsChatClient/RemoteCompletionsChatStreamProcessor.swift`
- `Frameworks/ChatClientKit/Sources/ChatClientKit/RemoteResponsesChatClient/RemoteResponsesChatStreamProcessor.swift`

在 `Task.detached` 闭包的 stream 消费 loop 入口前(`for await event in streamTask.events()` 之外、之前一行),声明:

```swift
// 顺序消费,单一 task,不需要原子;event-driven 故每次 await 之间局部状态稳定
var consecutivePostProcessFailures = 0
```

在 `for await event in streamTask.events()` 的 `.event` 分支:

```swift
guard let line = event.data else { continue }    // 已由 ServerSentEvent.parse 剥过

if let post = scripting?.config.postProcess, let pp = postProcessor {
    let out: PostProcessOutput
    do {
        if post.inherit {
            let chunk = try chunkDecoder.decode(ChatCompletionChunk.self, from: Data(line.utf8))
            out = try pp.processParsedChunk(chunk)
        } else {
            out = try pp.processRawLine(line)
        }
    } catch {
        // Round 2 codex HIGH #7 / Round 3 codex MED #11:`ChatResponseChunk` 没有 .error case。
        // 策略:把 error 累加到 `errorCollector`(调用方通过 `client.collectedErrors` 拿到),
        // 同时计入 consecutive failure counter。
        // - 偶发(< 阈值):log + skip + collectError,stream 继续。
        // - 连续 ≥ N(默认 3)次失败:`continuation.finish(throwing: error)` 中止 stream,
        //   避免用户看到"成功 stream 但内容全空"。
        await collectError(error)
        consecutivePostProcessFailures += 1
        if consecutivePostProcessFailures >= 3 {
            continuation.finish(throwing: error)
            return
        }
        continue
    }
    // 任何一次成功 invoke,counter 归零
    consecutivePostProcessFailures = 0
    if let r = out.reasoning { continuation.yield(.reasoning(r)) }
    if let c = out.content   { continuation.yield(.text(c)) }
    for t in out.toolCalls ?? [] {
        continuation.yield(.tool(ToolRequest(id: t.id, name: t.name, args: t.args)))
    }
} else {
    // 走原有逻辑
    ...
}
```

### 7.4 测试

**新文件**:`Frameworks/ChatClientKit/Tests/ChatClientKitTests/Scripting/PostProcessTests.swift`
- inherit=true:固定 chunk → 验 PostProcessOutput
- inherit=false:`"data: hello"` → JS 拿到 `"hello"`;`"data:  hello"`(两个空格) → JS 拿到 `" hello"`(保留第二个空格)
- keep-alive comment line(`: ping`)不触发 JS
- 多次 invoke 之间 `context` 累积

---

## 8. FlowDown 主工程接线(adapter 层)

> ChatClientKit 是独立 SwiftPM 包,**不**依赖 Storage。CloudModel → ManifestSnapshot 的 mapping 必须放在 FlowDown app(可以 import 两者的位置)—— 这一层称作 **adapter**。

### 8.1 Adapter 新文件

**新文件**:`FlowDown/Backend/Scripting/ChatScriptingAdapter.swift`(放 app target,不放任何 SwiftPM 包内)

```swift
import ChatClientKit
import Storage   // app target 可以同时 import 两者

enum ChatScriptingAdapter {

    /// 从 CloudModel 编出 ManifestSnapshot。
    /// **白名单策略**(Round 2 codex HIGH #11):只导出明确列出的字段,
    /// 任何 CloudModel 未来新加的字段默认 **不会** 出现在 manifest 里。
    /// 这样杜绝"新增敏感字段忘记脱敏"的回归。
    static func makeManifest(from model: CloudModel) -> ManifestSnapshot {
        // 用强类型 AnyCodingValue 字典字面量直接构造(Round 3 codex HIGH #10:
        // AnyCodingValue 没有 [String: Any] 初始化器,只有
        // ExpressibleByDictionaryLiteral / ArrayLiteral / 各种 scalar literal)。
        let safe: AnyCodingValue = .object([
            "objectId":         .string(model.objectId),
            "name":             .string(model.name),
            "model_identifier": .string(model.model_identifier),
            "endpoint":         .string(model.endpoint),
            "comment":          .string(model.comment),
            "headers":          .object(model.headers.mapValues { .string($0) }),
            "bodyFields":       .string(model.bodyFields),
            "capabilities":     .array(Array(model.capabilities).map { .string($0.rawValue) }),
            "context":          .int(model.context.rawValue),
            "response_format":  .string(model.response_format.rawValue),
            // token / api 凭据类:绝不导出。脚本如果 inherit=true 仍可从 headers 数组
            // 读到已构造的 Authorization,但 manifest 这一层是干净的。
        ])
        return ManifestSnapshot(payload: safe)
    }

    /// 构造 handle。**约束**:本方法的调用者 **绝不** 能持有 WCDB transaction(否则
    /// saveContext 同步落盘会和外层锁反转;codex HIGH #5)。
    static func makeHandle(
        model: CloudModel,
        conversation: Conversation,
        config: ChatClientKitScriptConfig
    ) -> ChatScriptingHandle {
        let convId = conversation.objectId
        return ChatScriptingHandle(
            conversationId: convId,
            config: config,
            manifest: makeManifest(from: model),
            readContext: {
                // 走 sdb.conversationWith(identifier:)(只读)拿最新一份;
                // 不持有任何外层 WCDB transaction。
                sdb.conversationWith(identifier: convId)?
                    .ext_data[ExtensionKey.chatClientKit] ?? ""
            },
            writeContext: { json in
                // Round 4 fix:`conversationExtDataPut` 是 throws 版本(failures 不静默);
                // 这里捕错后通过 logger + 上抛到 ScriptBridge,JS 端的 cck.saveContext
                // 会因此抛 exception,脚本作者能看到。
                do {
                    try sdb.conversationExtDataPut(
                        id:    convId,
                        key:   ExtensionKey.chatClientKit,
                        value: json
                    )
                } catch {
                    logger.error("[CCK] saveContext write failed: \(error)")
                    // 重抛会被 ScriptBridge 抓到并 throwToJS(详见 §4.4 修订)
                    throw error
                }
            }
        )
    }
}
```

### 8.2 ChatService 调用现场

```swift
let scriptCfg = ChatClientKitScriptConfig.decodePList(
    model.ext_data[ExtensionKey.chatClientKitScripts] ?? ""
)
let handle = scriptCfg.map { cfg in
    ChatScriptingAdapter.makeHandle(model: model, conversation: conv, config: cfg)
}
let stream = try await client.streamingChat(body: body, scripting: handle)
```

### 8.3 模块边界 invariants

- `ChatClientKit/Sources/` 任何文件 **不能** `import Storage`(`grep -r "import Storage" Frameworks/ChatClientKit/Sources/` 必须为空)
- `Storage/Sources/` 任何文件 **不能** `import ChatClientKit`
- 所有 `CloudModel → ManifestSnapshot` / `Conversation → context closures` 的转换 **只能** 出现在 `FlowDown/` app target 下
- CI 加 lint 一行 `grep` 防回归

### 8.4 锁反转防御:为什么没有可靠的 runtime 检测,以及替代方案

**Round 3 codex HIGH #6** 指出:thread-local depth counter 在我们的真实环境里 **不可靠**。原因:
- `saveContext` 在 ScriptRunner 的 **dedicated DispatchQueue** 上跑,这条 queue 不是发起 `streamingChat` 的调用线程
- 外层 WCDB transaction(如果有)持有的锁在调用方线程上,跟脚本线程是两条不同线程
- thread-local 检测不到跨线程锁反转
- async/await 的 cooperative thread 不稳定,thread-local 在 `await` 后线程切换会丢失/错配

**因此放弃 runtime tx-depth 兜底**,改用三层防御:

1. **文档硬约束(本期落地)**:
   - `ChatScriptingAdapter.makeHandle(...)` 文档明确写:**caller 必须不持有任何 WCDB transaction**
   - `ChatService.streamingChat(body:scripting:)` 文档明确写:**不允许在 `runTransaction` 闭包内调用**

2. **生产 watchdog:saveContext 写入本身有硬超时**(Round 5 codex HIGH #4):
   - 我们的原则是"崩溃优于挂死"(§1.8 / §0)。光靠文档约束不够 —— 违规真发生时进程会卡住。
   - `ScriptBridge.saveContext` 调 `onWriteContext` 时,**Swift 端**用 `DispatchSemaphore.wait(timeout:)` 给 **5 秒预算**;超时 → `fatalError("[CCK] saveContext write blocked > 5s — likely WCDB lock inversion in caller chain")`。
   - 这跟脚本超时(§4.3)对称:JS 5s budget / DB 写 5s budget。两条都是产品决策性的"硬上限",违反就让进程死,不让用户体验挂屏。
   - 实现要点:onWriteContext 在另一个 DispatchQueue 上跑(脚本 queue **不**能等自己),Swift 主线沿 `DispatchSemaphore` 同步;watchdog timeout = `fatalError`。

```swift
// ScriptBridge.swift 内部:
@objc func saveContext(_ value: JSValue) {
    // (...stringify 同前...)
    let sem = DispatchSemaphore(value: 0)
    var caught: Error?
    DispatchQueue.global(qos: .userInitiated).async {
        do { try self.onWriteContext(json) }
        catch { caught = error }
        sem.signal()
    }
    if sem.wait(timeout: .now() + 5) == .timedOut {
        fatalError("[CCK] saveContext write blocked > 5s — likely WCDB lock inversion in caller chain")
    }
    if let err = caught {
        let ctx = JSContext.current() ?? value.context
        ctx?.exception = JSValue(newErrorFromMessage: "saveContext failed: \(err)", in: ctx)
    }
}
```

3. **测试 watchdog 兜底**(本期落地):
   - 集成测试人为构造"在 transaction 内调 streamingChat"这一禁止场景,test runner 用 `XCTWaiter` / `DispatchSourceTimer` 在 7 秒后强制 `XCTFail("deadlock — forbidden invocation pattern")` —— 给生产 watchdog 留 5 秒 + 余量。
   - 之前版本声称"WCDB 自身 transaction timeout 兜底"是未证实假设(`grep -r busyTimeout|setTimeout|busy_timeout` 仓库无配置)—— Round 4 删除该 claim。

4. **代码审查 checklist**:`grep -r "streamingChat" FlowDown/` 时人工核对每一处调用都不在 transaction 里。

> 不做"完美 runtime guard",因为它在我们的并发模型下不可靠;做不到不如不做,免得给开发者错误的安全感。

---

## 9. PR 拆分

| PR | 内容 | 依赖 |
|---|---|---|
| #1 | §3 全部:Storage `ExtensionDictionary` + 两张表新增 `ext_data` 列 + `MigrationV6ToV7` + ExtensionKey + 测试 | 独立 |
| #2 | §4 全部:ScriptRunner / ScriptBridge / I/O 类型 + 单测 | 独立(可与 #1 并行) |
| #3 | §5 + §6:ChatService 扩展 API + Pre-processor 接入(Completions + Responses) | #2 |
| #4 | §7:Post-processor 接入(两个 StreamProcessor)。**不**新增 SSE helper —— event.data 已由 ServerSentEvent.parse 唯一负责剥(Round 2 fix) | #2 |
| #5 | §8:FlowDown 主工程接线 + manifest 脱敏 | #1 #3 #4 |
| #6 | 端到端集成测试 + 内部开发者文档 | #5 |

---

## 10. 评审 checklist(给 Codex 用 / Round 1 已应用)

- [ ] CloudModel / Conversation 新列名 = `ext_data`(避 Swift 关键字),已写显式 MigrationV6ToV7 + bump DBVersion.Version7
- [ ] `Storage.swift` 内 existing-DB 升级链 **和** new-DB 初始化链 两条 migrations 数组都追加 `MigrationV6ToV7()`
- [ ] `StorageError` 本期新建:`public enum StorageError: Error, LocalizedError { case conversationNotFound(String) ... }`,有对应单测验证 `conversationExtDataPut` 在不存在 id 时正确抛错
- [ ] `ExtensionDictionary.ColumnCodable.archivedValue()` 显式 `outputFormat = .xml`
- [ ] `ExtensionDictionary.init?(with:)` 损坏/缺失数据回退空 dict 不抛
- [ ] `ExtensionKey` 常量集中,任何新保留 key 必须登记
- [ ] 强类型 I/O struct 无裸 `Any`,只在受控位置出现 `AnyCodingValue`
- [ ] `ManifestSnapshot` 只有 `payload: AnyCodingValue` —— ChatClientKit 不知 CloudModel 字段
- [ ] CloudModel → ManifestSnapshot mapper 在 `FlowDown/Backend/Scripting/ChatScriptingAdapter.swift`(app target),不在 ChatClientKit / Storage 包内
- [ ] `grep -r "import Storage" Frameworks/ChatClientKit/Sources/` = 空
- [ ] `grep -r "import ChatClientKit" Frameworks/Storage/Sources/` = 空
- [ ] ScriptRunner.init 一次性把 manifest / chatSession `Object.freeze` 成全局,后续 invoke 不重绑
- [ ] `context` 是 JS 全局 `var`,Swift 侧不持有 `JSValue`,允许脚本 reassign
- [ ] 5s 超时分支 = `fatalError`,无 `onTimeout` 闭包注入
- [ ] Timeout 测试不在 in-process 单测里跑;改 subprocess 集成测试,放 nightly job
- [ ] `manifest` 与 `chatSession` 用 `setObject` + JS `deepFreeze` 注入,**不**字符串拼 JS source
- [ ] 起始 `context` 用 JSON.parse 解析,失败回退 `{}`
- [ ] `manifest` adapter 走**白名单**,非白名单字段绝不导出
- [ ] `streamingChat(body:scripting:)` 是 protocol **唯一**必需方法,`chat(...)` 系列在 extension 给默认实现
- [ ] post_process 连续 N(=3)次 JS 失败 → `continuation.finish(throwing:)`,否则 log + skip + collectError
- [ ] adapter 用 `sdb.conversationExtDataPut(id:key:value:) throws`(新增 Storage API),不直接写 `conv.ext_data`(因为 `package(set)` 跨 target 不可写)
- [ ] `conversationExtDataPut` 内部 `markModified()` 之后再 update,保证 `diffSyncable` 识别变化、upload queue 入队
- [ ] `conversationUpdateThrowing(...)` 为 throws 版本,**不**用 `try?` 吞错;`saveContext` 错误通过 `JSContext.exception` 翻给 JS
- [ ] **没有** runtime tx-depth guard(thread-local 不可靠);锁反转防御 = 文档约束 + saveContext 写盘 5s watchdog(超时 fatalError)+ 集成 test 内 7s XCTFail + code review
- [ ] `ScriptBridge.saveContext` 用 `DispatchSemaphore.wait(timeout:)` 5s 兜底,超时 fatalError;失败错误用 `JSValue(newErrorFromMessage:in:)` 翻给 JS,JS try/catch 能抓到 — 有专门单测覆盖
- [ ] ScriptRunner 每次 `streamingChat` 新建一个实例;N 个并发 streamingChat = N 个 runner;stream 结束即丢弃
- [ ] `cck.saveContext(...)` 同步语义;`onWriteContext` 实现自包含,不持有外层锁
- [ ] `streamingChat(scripting:)` **不**允许被嵌在 WCDB transaction 内
- [ ] header `setValue` 按 JS 顺序注入;**计划文档明确**: wire order 是 best-effort 不承诺
- [ ] 不新增 `sseStripDataPrefix` helper;`event.data` 由 ServerSentEvent.parse 唯一负责剥
- [ ] post_process JS 抛错/无法 decode 时:偶发 log + 跳过该 chunk + `collectError`;**连续 ≥ 3 次** 失败 → `continuation.finish(throwing:)` 终止 stream
- [ ] 所有 ChatService conformer(`RemoteCompletions` / `RemoteResponses` / `MLX` / `AppleIntelligence`)显式实现 `streamingChat(body:scripting:)`
- [ ] 所有路径走 streaming,`chat(body:scripting:)` 由默认实现聚合
- [ ] CI 加 lint 行禁止 cross-module import 回归
- [ ] 没有在 app 内暴露任何脚本编辑入口

---

## 11. 已被否决 / 不做的事

记录下来防止未来 reviewer 反复提出:

- ❌ 不重新引入 chat() 非 streaming 路径(全部走 streaming 后聚合)
- ❌ 不在 manifest 里传明文 token
- ❌ 不引入 V8 / QuickJS / Hermes,JavaScriptCore-only
- ❌ 不在 ChatClientKit 内直接依赖 Storage(通过闭包桥接)
- ❌ 不暴露脚本编辑 UI(合规)
- ❌ 脚本超时不降级为抛 error,继续 fatalError
- ❌ `cck.saveContext` 不做异步落盘
- ❌ chatSession 不做按需访问 API
- ❌ 不为 1% 的 URLSession header 大小写 normalize 引入 URLProtocol 劫持
- ❌ 不在 cck.* 里加 AES/RSA(可审计性 / 攻击面)
- ❌ 不 rename 任何字段;有需求只能加新字段
- ❌ "header send-on-wire 顺序敏感"不作为承诺(URLSession + HTTP/2 不文档化)
- ❌ ManifestSnapshot 不做"完整 CloudModel 镜像";走白名单只导出明确字段

## 12. Follow-up(本期不做)

- 把脚本预编译成 JS function 缓存,后续 invoke 走 `JSValue.call`(消除每次 `evaluateScript` 重 parse)
- 跳过空 `data:` 行不触发 JS
- 把 `cck.*` 工具函数挪到 native plug-in,减少 evaluateScript 桥接成本
- 若发现 provider 真的需要 wire-order header 签名,再评估 URLProtocol 劫持(目前认定 0 用户场景)
- **性能基线**(Round 3 codex LOW #14):写一个 micro-benchmark target,对 ScriptRunner 在 100 / 500 / 1000 chunk 长度下测 p50 / p95 延迟。若 p95 在低端设备 > 50ms / chunk,把"预编译 JS function"从 follow-up 提前到本期

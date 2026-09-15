# FaultCanvas 设计说明

## 目标

FaultCanvas 是一个以 MoonBit 实现的可编程故障代理与状态化服务虚拟化网关。它运行在被测客户端与真实上游之间，在不修改客户端代码的情况下，按请求和场景状态执行透传、固定响应、延迟、连接中断与响应损坏，并生成可审阅的运行证据。

项目不重复建设 OpenAPI 契约工具、HTTP cassette 库或离散事件模拟器。MoonContract 负责规范驱动的 Mock，MoonVCR 负责显式 transport 的录制回放，moonsim 负责模型层确定性模拟；FaultCanvas 负责真实网络边界上的故障执行。

## 需求

### 功能需求

- 作为独立进程监听 HTTP/1.1 请求并转发到配置的上游。
- 通过 JSON 场景配置匹配 method、path、query、header 和 body。
- 支持 passthrough、stub、delay、abort、truncate、corrupt 和 status override。
- 支持按命中次数和状态转换驱动场景，例如前两次返回 503，第三次透传。
- 记录每次交互的规则、阶段、耗时、结果和错误，输出文本与 JSON 报告。
- 提供可嵌入的纯 MoonBit 规则引擎、CLI、示例与测试。

### 非功能需求

- 默认只监听 127.0.0.1，避免意外暴露。
- 配置解析失败时拒绝启动，不进行部分加载。
- 请求体、响应体与事件数量具有明确上限。
- 相同配置和请求序列得到相同的规则选择和状态转换。
- 核心包不依赖网络，可在 MoonBit 多后端执行测试；网络适配层以 native 为主。
- API 按 core、matcher、scenario、fault、report、runtime 分层，便于赛后增加 WebSocket/TCP 适配器。

## 备选方案

### A. 独立真实网络代理（采用）

优点是差异化明确、演示直观，并能直接测试任意语言客户端。代价是需要处理 HTTP I/O、资源限制和连接失败。通过只支持 HTTP/1.1、默认 loopback、限制 body 大小来控制复杂度。

### B. OpenAPI 驱动 Mock Server

配置体验成熟，但 MoonContract 已经提供 OpenAPI 校验、确定性 Mock 和 `serve`，重复风险高，因此不采用。

### C. 进程内录制回放库

实现成本低，但 MoonVCR 已覆盖 cassette、匹配、脱敏与离线回放，且要求调用方封装 transport，因此不采用。

## 架构

```text
Client
  |
  v
HTTP Listener -> Request Normalizer -> Rule Matcher -> Scenario Machine
                                              |              |
                                              |              v
                                              |        Fault Decision
                                              |              |
                          +-------------------+--------------+
                          |                   |              |
                       Stub              Passthrough      Abort/Delay/
                          |                   |           Corrupt/Truncate
                          +-------------------+--------------+
                                              |
                                              v
                                       Event Journal
                                              |
                                      Text / JSON report
```

核心规则引擎接收规范化请求与当前场景状态，返回不可变的 `Decision`。native 运行时只负责把真实请求转换为核心模型、执行 Decision 并记录 Outcome。这样大部分行为可以在无网络测试中覆盖。

## 主要模块

- `core`：HTTP 请求/响应、限制、错误和决策模型。
- `matcher`：确定性请求匹配、优先级和诊断。
- `scenario`：命中计数、阶段转换和状态存储。
- `fault`：故障动作校验与执行计划。
- `config`：版本化 JSON 配置解析和语义检查。
- `runtime`：组合匹配器、状态机、故障计划和事件日志。
- `report`：稳定文本/JSON 报告。
- `native`：HTTP listener、上游 client 和连接级故障执行。
- `cmd/faultcanvas`：`check`、`serve`、`simulate`、`report` 命令。

## 错误处理和安全

- 所有可预期错误使用带上下文的错误值，不依赖 panic。
- 未匹配请求默认返回 502，除非显式配置 passthrough fallback。
- 默认清除日志中的 Authorization、Proxy-Authorization、Cookie 与 Set-Cookie。
- 限制请求体、响应体、header 数量、单规则命中次数和内存事件数。
- 上游只允许 `http://`；比赛版不实现 TLS MITM。
- 配置中的 host 默认必须是 loopback；显式 `--allow-public-listen` 才能覆盖。

## 测试策略

- matcher、状态转换、故障计划和配置解析使用单元测试。
- 相同输入重复执行的报告使用快照/确定性测试。
- native 集成测试启动本地假上游与 FaultCanvas，验证真实透传、stub、delay 和错误路径。
- CLI 使用 smoke tests 验证退出码与 JSON 输出。
- CI 执行格式检查、`moon check`、`moon build`、`moon test` 和示例验证。

## 比赛版边界

支持 HTTP/1.1、JSON 配置、单进程、文件报告。明确不做 HTTPS MITM、HTTP/2、gRPC、WebSocket、生产网关能力、分布式控制面和浏览器 UI。


## 1. 项目名称
**FaultCanvas：MoonBit 真实网络故障代理与服务虚拟化平台**

## 2. 项目简介
FaultCanvas 是一个使用 MoonBit 编写的 HTTP/1.1 故障代理。它运行在客户端和真实上游服务之间，在不修改客户端代码的情况下，按 JSON 配置注入延迟、固定响应、错误状态、连接中断、响应截断和内容损坏，用于验证重试、超时、降级和熔断逻辑。项目提供可复用 Library、native CLI、真实 loopback 代理、报告统计、安全脱敏、示例配置和自动化测试。

## 3. 项目方向、通用性说明
项目属于 Web 与网络基础设施、开发者测试工具方向。它不依赖某个业务系统或模型服务，适用于支付、订单、用户认证、第三方 API、微服务和跨语言 HTTP 客户端的故障测试。核心规则引擎与网络适配器分层，后续可以扩展 TCP、WebSocket 或其他协议。

## 4. 预期使用场景
1. **支付重试**：同一订单前两次请求返回延迟 503，第三次切换到健康阶段并透传到真实沙箱上游，验证客户端重试是否正确。
2. **用户会话隔离**：通过 `X-Checkout-Id` 等 session header 为不同用户维护独立命中次数，验证状态不会串扰。
3. **第三方 API 故障**：将上游响应改为 429、500、截断响应或损坏内容，验证 SDK 的降级、告警和错误解析。
4. **黑盒 CLI/SDK 测试**：不修改被测程序代码，只把请求指向 FaultCanvas，即可测试任意语言客户端的网络异常处理。

## 5. 拟实现的核心功能
- 请求按 method、path、query、header、body、优先级和当前阶段匹配。
- 支持 passthrough、stub、delay、abort、status override、truncate 和 corrupt。
- 支持 session 状态、命中次数、阶段转换和确定性决策。
- 提供 `check`、`simulate`、`serve`、`report`、`stats`、`redact`、`verify` CLI；`verify` 可按请求序列检查规则、阶段切换、故障结果与会话隔离。
- 默认只监听本机，限制 Header/body/journal 大小并脱敏 Token、Cookie 等敏感信息。
- 提供 MoonBit Library、native 集成测试、示例、README、CI 和 Mooncakes 发布准备。

## 6. 项目来源说明
本项目为原创 MoonBit 项目，不是已有项目的简单拆分、改名或重复提交。设计参考了 Toxiproxy、WireMock、MockServer 等成熟工具解决的真实网络测试需求，但核心代码、配置模型、状态机、MoonBit 包结构和 native 适配器均独立实现。

## 7. 移植来源与许可证
本项目不是移植项目，因此无需要声明的原项目名称、来源链接或移植许可证。项目自身采用 Apache-2.0 许可证；外部工具仅作为设计参考，不复制其代码，第三方说明见仓库 `THIRD_PARTY.md`。

## 8. GitHub 仓库与开发记录
- GitHub 仓库：<https://github.com/zkc-long/FaultCanvas>
- 仓库公开，当前已有 **22 个有效 commit**
- 提交记录覆盖核心规则库、状态机、native proxy、配置、安全策略、报告统计、CLI、测试、文档和 CI；不存在为满足数量而进行的空提交、无意义拆分或重复提交。
- 当前工程约 3670 行 MoonBit 代码，新增确定性验收回放包与 36 项便携测试；GitHub Actions 将覆盖其可移植测试、native proxy 和 CLI 验收回放。

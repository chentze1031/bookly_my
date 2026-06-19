# Play Console「数据安全 (Data Safety)」填写指引 — Bookly MY

> 在 Play Console → 应用内容 (App content) → 数据安全。照下面勾。
> 总原则：**Encrypted in transit = 是**（全程 HTTPS）；**用户可请求删除 = 是**（邮件删号）。
> 注：信用卡/银行卡号由 Google Play 处理，**App 不接触**，所以「Payment info」不勾。

---

## 第 1 步：总体问题
- **App 是否收集或分享用户数据？** → **是 (Yes)**
- 传输中是否加密？ → **是**
- 是否提供删除数据的途径？ → **是**（隐私政策里写了邮件删号）

---

## 第 2 步：逐类数据（Collected 收集 / Shared 分享）

「Shared 分享」= 数据给了第三方处理（Supabase 存储、Google 登录/广告/Gemini、RevenueCat、LHDN）。
这些是**服务处理方**，按 Google 定义通常算「Collected」且部分「Shared」。保守起见按下表勾。

| 数据类型 (Play 分类) | 收集 | 分享 | 用途 (Purpose) |
|---|---|---|---|
| **Personal info → Name** | ✅ | ✅ | App 功能（账号、客户/员工资料）|
| **Personal info → Email address** | ✅ | ✅ | 账号管理、App 功能 |
| **Personal info → User IDs** | ✅ | ✅ | App 功能、账号管理 |
| **Personal info → Phone number** | ✅ | ✅ | App 功能（客户/员工资料）|
| **Personal info → Address** | ✅ | ✅ | App 功能（发票/客户）|
| **Personal info → 其他信息 (NRIC/TIN 等)** | ✅ | ✅ | App 功能（税务/发票合规）|
| **Financial info → Purchase history** | ✅ | ✅ | 账号管理（订阅状态）|
| **Financial info → 其他财务信息**（账目/发票金额）| ✅ | ✅ | App 功能（记账核心）|
| **Photos and videos → Photos**（logo/签名/对账单）| ✅ | ✅ | App 功能 |
| **Files and docs**（对账单/导出 PDF）| ✅ | ✅ | App 功能、AI 导入 |
| **App activity → 其他动作**（用量）| 可选 ✅ | — | 分析/App 功能 |
| **App info & performance → Crash logs** | ✅ | — | 稳定性 |
| **App info & performance → Diagnostics** | ✅ | — | 稳定性 |
| **Device or other IDs**（广告 ID）| ✅（若开广告）| ✅ | 广告（仅免费版）|

> 若你**决定不放广告**（现在是占位符 ID，不显示），则「Device or other IDs / 广告」可不勾。

---

## 第 3 步：每类数据要回答的三问（统一答法）

对上面每一项，Play 会追问：
1. **是否加密传输？** → **是**
2. **是否必需还是可选？**
   - 账号/账目/客户数据 → **必需 (Required)**
   - 照片、对账单、广告 ID → **可选 (Optional)**
3. **用户能否请求删除？** → **是**（隐私政策第 7 条：邮件删号）

---

## 第 4 步：用途选项（Purposes）速查

勾这些就够：
- **App functionality**（几乎所有数据都勾这个）
- **Account management**（Email / User ID / Purchase history）
- **Analytics**（Crash / Diagnostics / App activity）
- **Advertising or marketing**（仅当开广告时，给广告 ID 勾）

⚠️ **不要勾**：
- 「Fraud prevention」「Personalization」等你没做的
- 「Data sold to third parties / 出售数据」→ **否**（我们不卖）

---

## 第 5 步：其它「App content」必填项（顺带做了）
- **隐私政策 URL**：把 `PRIVACY_POLICY.md` 托管成网页（GitHub Pages / 你的网站），填那个 URL
- **广告声明 (Ads)**：有广告就声明「Yes, contains ads」；不放就「No」
- **内容分级问卷**：选 Business/Finance 工具，按实际答（无暴力/赌博等）
- **目标受众**：18+ 或 13+（商业工具，非儿童向）
- **数据安全表**：本指引

---

## 关键提醒
- **信用卡/银行卡号**：App 不收集（Google Play 处理支付）→ Payment info **不勾**
- **数字签名私钥**：只存设备本地、从不上传 → 不算「收集/分享」给我们
- 全程 HTTPS → 所有项「加密传输 = 是」

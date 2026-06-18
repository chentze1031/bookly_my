# MyInvois 生产数字证书申请清单 (Production Digital Certificate Checklist)

> 沙盒已端到端验证：未签名 v1.0 提交，B2C 合并发票与 B2B 单张发票都能 **Validated**；
> 设备端签名代码也已被 LHDN **Step08 验签流程**确认结构正确（能解析签名、提取证书）。
> 剩下唯一门槛：**正式环境每张 e-Invoice 必须用真·数字证书签名 (v1.1)**。

---

## 1. 证书必须满足的条件（来自 LHDN 沙盒 DS 校验实测）

用自签测试证书提交，LHDN 明确列出了真证书必须满足的要求：

| 要求 | LHDN 码 | 说明 |
|---|---|---|
| **机构证书**（Organisation，非个人 Personal）| DS309 | ERP/API 提交**只能用机构证书**，个人证书会被拒 |
| **受信任 CA 签发** | DS329 | 必须来自 LHDN/MCMC 认可的马来西亚 CA；自签 / 非认可 CA 无效（沙盒也验信任链）|
| 证书含 **OI**（Organisation Identifier）| DS307 / DS311 | 证书里的 OI 必须 = 你的 **TIN** |
| 证书 subject 含 **SERIALNUMBER** | DS306 / DS312 | 必须 = 你的 **BRN / 业务登记号** |
| **X509IssuerName 格式** | DS326 | App 端写入的 IssuerName 需按真证书的实际格式对齐一次（见第 5 步）|

---

## 2. 去哪申请（MCMC 认可的 CA）

- **Pos Digicert** — https://www.posdigicert.com.my/digital-certificate-for-einvoice
- **MSC Trustgate** — https://www.msctrustgate.com
- 申请类型：**e-Invoice / Document Signing 的 Organisation（机构）软证书 (soft cert, .p12/.pfx)**
- 有效期：通常 **3 年**

---

## 3. ⚠️ 个人 / 独资经营者特别注意

你目前是**个人身份（IG… TIN，无 SSM 登记号）**。但机构证书要求证书里带 **SERIALNUMBER = BRN（业务登记号）**。所以：

- **先到 SSM 注册独资/合伙业务**（Borang A / 业务登记），拿到 **业务登记号 (BRN)**；
- CA 会把这个 BRN 写进证书的 SERIALNUMBER，把你的 TIN 写进 OI；
- 没有 BRN，机构证书无法正确签发 → 无法做正式 ERP 报税。

> 如果只想继续用**未签名沙盒**测试 / 演示，则不需要证书。正式对外开 e-Invoice 才需要走这一步。

---

## 4. 申请时通常要准备

- 业务 **TIN**（写进证书 OI）
- **SSM 业务登记号 BRN**（写进证书 SERIALNUMBER）
- 授权签署人身份证件 (MyKad)
- 公司 / 业务资料、联系方式
- （各 CA 材料清单略有差异，以其官网 / 客服为准）

---

## 5. 拿到证书后在 App 里的步骤

1. 若证书是 `.p12`/`.pfx` 且用 AES 加密（App 的纯 Dart 解析器读不了），先转 PEM：
   ```
   openssl pkcs12 -in cert.p12 -nodes -out cert.pem
   ```
2. App → 设置 → 🧾 MyInvois → **数字证书 → Import** → 选 `.p12`（输密码）或 `cert.pem`
3. 环境切到 **Production**，填**生产**的 client_id / client_secret（沙盒和生产是两套独立凭证，需在正式 MyInvois 门户重新 Register ERP 取得）
4. 提交一张真发票 → 若报 **DS326（X509IssuerName 不匹配）**，把报错原文发给开发者，按真证书的 issuer DN 实际格式调一次 `lib/services/myinvois_signer.dart` 的 DN 写法（这是唯一需要代码微调的点，必须有真证书才能对准）
5. 走到 **Validated** → 正式上线可用

---

## 6. 沙盒 vs 生产 对照

| | 沙盒 (Sandbox / Preprod) | 生产 (Production) |
|---|---|---|
| 门户 | preprod-mytax.hasil.gov.my | mytax.hasil.gov.my |
| API | preprod-api.myinvois.hasil.gov.my | api.myinvois.hasil.gov.my |
| 签名 | 可未签名 v1.0 测字段 | **必须真证书签名 v1.1** |
| 凭证 | 沙盒 client_id/secret | 生产 client_id/secret（另取）|
| 状态 | ✅ 已端到端验证 | 待真证书 |

---

## 7. 当前进度

- ✅ B2C 合并发票（一般公众）— 沙盒 Validated
- ✅ B2B 单张发票（真实买方）— 沙盒 Validated
- ✅ 设备端数字签名代码 — LHDN Step08 验签结构正确
- ⏳ 正式签名 — 等真·机构证书（本清单）

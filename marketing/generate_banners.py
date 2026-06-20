"""
Bookly MY — Marketing Banner Generator
Generates 6 promotional images for social media / app store use.
"""

from PIL import Image, ImageDraw, ImageFont
import os

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR  = os.path.join(BASE_DIR, "banners")
os.makedirs(OUT_DIR, exist_ok=True)

FONT_CN  = "/home/user/bookly_my/assets/fonts/NotoSansSC-Regular.ttf"
FONT_EN  = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"

# ── Design tokens ────────────────────────────────────────────────────────────
W, H = 1080, 1080          # square for Instagram / Facebook

TEAL     = (32, 178, 170)
DARK     = (15, 23, 42)
DARKER   = (8, 12, 28)
WHITE    = (255, 255, 255)
ACCENT   = (94, 234, 212)   # light teal
GOLD     = (251, 191, 36)
SOFT     = (148, 163, 184)  # muted text
GRAD_TOP = (15, 23, 42)
GRAD_BOT = (4, 47, 46)

# ── Helpers ──────────────────────────────────────────────────────────────────

def load(path, size):
    return ImageFont.truetype(path, size)

def vgradient(img: Image.Image, top_c, bot_c):
    """Vertical gradient fill."""
    d = ImageDraw.Draw(img)
    for y in range(img.height):
        t = y / img.height
        r = int(top_c[0] + (bot_c[0] - top_c[0]) * t)
        g = int(top_c[1] + (bot_c[1] - top_c[1]) * t)
        b = int(top_c[2] + (bot_c[2] - top_c[2]) * t)
        d.line([(0, y), (img.width, y)], fill=(r, g, b))

def centered_text(draw, text, y, font, color=WHITE, img_w=W):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((img_w - tw) / 2, y), text, font=font, fill=color)

def wrap_text(draw, text, font, max_w):
    """Simple word-wrap returning list of lines."""
    words = text.split()
    lines, line = [], ""
    for w in words:
        test = (line + " " + w).strip()
        bbox = draw.textbbox((0, 0), test, font=font)
        if bbox[2] - bbox[0] <= max_w:
            line = test
        else:
            if line:
                lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines

def rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill)

def tag_pill(draw, text, cx, cy, font, bg=TEAL, fg=WHITE):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    pw, ph = tw + 32, th + 14
    draw.rounded_rectangle([cx - pw//2, cy - ph//2, cx + pw//2, cy + ph//2],
                           radius=ph//2, fill=bg)
    draw.text((cx - tw//2, cy - th//2 - 2), text, font=font, fill=fg)

def decor_dots(draw, x, y, color, n=5, step=18):
    for i in range(n):
        draw.ellipse([x + i*step, y, x + i*step + 8, y + 8], fill=color)

def corner_bracket(draw, x, y, size, color, corner="tl"):
    lw = 4
    if corner == "tl":
        draw.rectangle([x, y, x+size, y+lw], fill=color)
        draw.rectangle([x, y, x+lw, y+size], fill=color)
    elif corner == "tr":
        draw.rectangle([x-size, y, x, y+lw], fill=color)
        draw.rectangle([x-lw, y, x, y+size], fill=color)
    elif corner == "bl":
        draw.rectangle([x, y-size, x+size, y], fill=color)
        draw.rectangle([x, y-size, x+lw, y], fill=color)
    elif corner == "br":
        draw.rectangle([x-size, y-size, x, y], fill=color)
        draw.rectangle([x-lw, y-size, x, y], fill=color)

# ── Card 1: Hero / Dashboard ─────────────────────────────────────────────────

def card_hero():
    img = Image.new("RGB", (W, H))
    vgradient(img, (12, 20, 40), (4, 50, 48))
    d = ImageDraw.Draw(img)

    # diagonal accent strip
    for i in range(6):
        alpha = 15 - i * 2
        d.polygon([(0, 300+i*40), (W, 180+i*40), (W, 200+i*40), (0, 320+i*40)],
                  fill=(32, 178, 170, 0))

    # top label
    f_sm  = load(FONT_EN, 28)
    f_tag = load(FONT_EN, 32)
    f_h1  = load(FONT_CN, 72)
    f_h2  = load(FONT_CN, 48)
    f_body= load(FONT_CN, 34)
    f_cta = load(FONT_EN, 30)

    d.text((60, 60), "BOOKLY MY", font=load(FONT_EN, 34), fill=ACCENT)
    d.text((60, 102), "马来西亚中小企业记账神器", font=load(FONT_CN, 26), fill=SOFT)

    # divider line
    d.rectangle([60, 148, W-60, 151], fill=TEAL)

    # headline
    centered_text(d, "生意好管，记账更轻松", 200, load(FONT_CN, 68), WHITE)
    centered_text(d, "Your Business, Under Control", 285, load(FONT_EN, 30), ACCENT)

    # feature cards
    cards = [
        ("免费开发票", "Tax Invoice"),
        ("SST自动报表", "Auto SST"),
        ("EPF薪资计算", "Payroll"),
        ("17种货币", "Multi-FX"),
        ("中英双语", "Bilingual"),
        ("AI智能分类", "AI Pro"),
    ]
    cx, cy = 90, 400
    cw, ch = 280, 120
    gap = 20
    for i, (cn, en) in enumerate(cards):
        col = i % 3
        row = i // 3
        x = cx + col * (cw + gap)
        y = cy + row * (ch + gap)
        rounded_rect(d, [x, y, x+cw, y+ch], 16, (255, 255, 255, 0))
        d.rounded_rectangle([x, y, x+cw, y+ch], radius=16,
                            fill=(255, 255, 255, 15), outline=TEAL, width=1)
        d.text((x+18, y+18), cn, font=load(FONT_CN, 32), fill=WHITE)
        d.text((x+18, y+62), en, font=load(FONT_EN, 24), fill=SOFT)
        # dot accent
        d.ellipse([x+cw-28, y+18, x+cw-12, y+34], fill=TEAL)

    # CTA
    cta_y = 800
    rounded_rect(d, [120, cta_y, W-120, cta_y+80], 40, TEAL)
    centered_text(d, "Google Play 免费下载", cta_y + 20, load(FONT_CN, 36), DARK)

    # bottom badge
    tag_pill(d, "核心功能 永久免费", W//2, 940, load(FONT_CN, 28), GOLD, DARK)

    decor_dots(d, 60, H-60, TEAL)
    decor_dots(d, W-150, 30, ACCENT)

    img.save(os.path.join(OUT_DIR, "01_hero.png"))
    print("✓ 01_hero.png")

# ── Card 2: Invoice ───────────────────────────────────────────────────────────

def card_invoice():
    img = Image.new("RGB", (W, H))
    vgradient(img, (10, 15, 35), (20, 60, 55))
    d = ImageDraw.Draw(img)

    f_big  = load(FONT_CN, 80)
    f_mid  = load(FONT_CN, 42)
    f_sm   = load(FONT_CN, 30)
    f_en   = load(FONT_EN, 28)

    # top accent bar
    d.rectangle([0, 0, W, 8], fill=TEAL)

    d.text((60, 48), "INVOICE", font=load(FONT_EN, 22), fill=TEAL)

    centered_text(d, "30秒", 120, load(FONT_EN, 110), ACCENT)
    centered_text(d, "生成专业税务发票", 250, f_big, WHITE)
    centered_text(d, "Professional Tax Invoice in Seconds", 350, f_en, SOFT)

    # mock invoice card
    ix, iy, iw, ih = 80, 430, W-80, 760
    d.rounded_rectangle([ix, iy, iw, ih], radius=20,
                        fill=(255,255,255,0), outline=(255,255,255,30), width=1)
    # header row
    d.rounded_rectangle([ix, iy, iw, iy+60], radius=20, fill=(32,178,170,60))
    d.text((ix+24, iy+14), "TAX INVOICE", font=load(FONT_EN,26), fill=WHITE)
    d.text((iw-200, iy+14), "INV-2024-001", font=load(FONT_EN,22), fill=ACCENT)

    rows = [
        ("客户 / Customer", "ABC Trading Sdn Bhd"),
        ("日期 / Date", "20 June 2026"),
        ("小计 / Subtotal", "RM 1,000.00"),
        ("SST 8%", "RM 80.00"),
        ("总计 / Total", "RM 1,080.00"),
    ]
    for i, (label, value) in enumerate(rows):
        ry = iy + 80 + i * 54
        d.text((ix+24, ry), label, font=load(FONT_CN,24), fill=SOFT)
        d.text((iw-250, ry), value, font=load(FONT_EN,24), fill=WHITE)
        if i < len(rows)-1:
            d.line([(ix+20, ry+44), (iw-20, ry+44)], fill=(255,255,255,15), width=1)

    # total highlight
    d.rounded_rectangle([ix+16, iy+78+4*54, iw-16, iy+78+4*54+50],
                        radius=8, fill=(32,178,170,40))

    # CTA bottom
    tag_pill(d, "支持公司Logo · 电子签名 · SST税率", W//2, 850, load(FONT_CN,28), DARK, ACCENT)
    centered_text(d, "还可导出 PDF · Excel · 邮件分享", 920, load(FONT_CN, 30), SOFT)

    decor_dots(d, 60, H-50, TEAL)
    img.save(os.path.join(OUT_DIR, "02_invoice.png"))
    print("✓ 02_invoice.png")

# ── Card 3: SST Report ────────────────────────────────────────────────────────

def card_sst():
    img = Image.new("RGB", (W, H))
    vgradient(img, (8, 18, 38), (2, 40, 36))
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, W, 8], fill=GOLD)

    d.text((60, 48), "SST REPORT", font=load(FONT_EN, 22), fill=GOLD)

    centered_text(d, "SST报税", 110, load(FONT_CN, 90), WHITE)
    centered_text(d, "一键搞定，从此不用发愁", 215, load(FONT_CN, 46), ACCENT)
    centered_text(d, "Auto-generate SST report for LHDN filing", 280, load(FONT_EN,26), SOFT)

    # SST rate pills row
    rates = ["Sales Tax 5%", "Sales Tax 10%", "Service Tax 6%", "Service Tax 8%"]
    pill_y = 360
    total_w = sum([len(r)*14+40 for r in rates]) + 30*3
    sx = (W - total_w) // 2
    for r in rates:
        bbox = d.textbbox((0,0), r, font=load(FONT_EN, 24))
        tw = bbox[2]-bbox[0]
        pw = tw + 40
        d.rounded_rectangle([sx, pill_y, sx+pw, pill_y+44], radius=22, fill=TEAL)
        d.text((sx+20, pill_y+8), r, font=load(FONT_EN,24), fill=WHITE)
        sx += pw + 16

    # report summary mock
    mx, my = 80, 440
    mw, mh = W-80, 770
    d.rounded_rectangle([mx, my, mw, mh], radius=20, fill=(255,255,255,8),
                        outline=(255,255,255,25), width=1)
    d.text((mx+24, my+20), "2026年6月  SST摘要", font=load(FONT_CN,30), fill=ACCENT)
    d.line([(mx+20, my+62), (mw-20, my+62)], fill=TEAL, width=2)

    months = [
        ("应税销售额 Taxable Sales", "RM 28,500"),
        ("应缴销售税 Sales Tax Due", "RM 2,850"),
        ("应税服务额 Taxable Services", "RM 12,000"),
        ("应缴服务税 Service Tax Due", "RM 720"),
        ("本月合计 Total Payable", "RM 3,570"),
    ]
    for i, (label, val) in enumerate(months):
        ry = my + 84 + i * 56
        d.text((mx+24, ry), label, font=load(FONT_CN,24), fill=SOFT)
        col = GOLD if i == len(months)-1 else WHITE
        d.text((mw-200, ry), val, font=load(FONT_EN,24), fill=col)
        if i < len(months)-1:
            d.line([(mx+20, ry+46), (mw-20, ry+46)], fill=(255,255,255,12))

    tag_pill(d, "支持导出给会计师  无需额外软件", W//2, 870, load(FONT_CN,28), DARK, GOLD)
    centered_text(d, "FREE for all Bookly MY users", 940, load(FONT_EN,26), SOFT)

    img.save(os.path.join(OUT_DIR, "03_sst.png"))
    print("✓ 03_sst.png")

# ── Card 4: Payroll ───────────────────────────────────────────────────────────

def card_payroll():
    img = Image.new("RGB", (W, H))
    vgradient(img, (10, 16, 38), (30, 12, 50))
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, W, 8], fill=(167, 139, 250))  # purple accent

    PURPLE = (167, 139, 250)
    LPURPLE = (196, 181, 253)

    d.text((60, 48), "PAYROLL", font=load(FONT_EN, 22), fill=PURPLE)
    centered_text(d, "薪资计算", 100, load(FONT_CN, 90), WHITE)
    centered_text(d, "EPF · SOCSO · EIS 自动搞定", 205, load(FONT_CN, 44), PURPLE)
    centered_text(d, "2026 Latest Rates — No Calculator Needed", 265, load(FONT_EN,24), SOFT)

    # rate table
    tx, ty = 80, 350
    tw = W - 80
    d.rounded_rectangle([tx, ty, tw, ty+320], radius=20, fill=(255,255,255,8),
                        outline=(167,139,250,60), width=1)

    headers = ["项目", "雇员", "雇主"]
    hx = [tx+24, tx+280, tx+520]
    d.text((hx[0], ty+16), headers[0], font=load(FONT_CN,26), fill=LPURPLE)
    d.text((hx[1], ty+16), headers[1], font=load(FONT_CN,26), fill=LPURPLE)
    d.text((hx[2], ty+16), headers[2], font=load(FONT_CN,26), fill=LPURPLE)
    d.line([(tx+16, ty+56), (tw-16, ty+56)], fill=PURPLE, width=2)

    rows = [
        ("EPF 公积金", "11%", "12-13%"),
        ("SOCSO 社保", "0.5%", "1.75%"),
        ("EIS 就业险", "0.2%", "0.4%"),
    ]
    icons = ["💼", "🛡", "📋"]
    for i, (item, emp, er) in enumerate(rows):
        ry = ty + 76 + i * 72
        bg = (167,139,250,20) if i % 2 == 0 else (255,255,255,5)
        d.rounded_rectangle([tx+8, ry-8, tw-8, ry+58], radius=10, fill=bg)
        d.text((hx[0], ry), item, font=load(FONT_CN,28), fill=WHITE)
        d.text((hx[1], ry), emp, font=load(FONT_EN,28), fill=ACCENT)
        d.text((hx[2], ry), er,  font=load(FONT_EN,28), fill=ACCENT)

    # payslip mock
    px, py = 80, 720
    pw = W - 80
    d.rounded_rectangle([px, py, pw, py+170], radius=16, fill=(255,255,255,8),
                        outline=(255,255,255,20), width=1)
    d.text((px+20, py+14), "员工工资单  Payslip Preview", font=load(FONT_CN,26), fill=LPURPLE)
    d.text((px+20, py+58), "基本薪资  RM 3,000", font=load(FONT_CN,26), fill=WHITE)
    d.text((px+20, py+96), "EPF扣除   RM 330", font=load(FONT_CN,26), fill=SOFT)
    d.text((px+400, py+58), "实领  RM 2,520", font=load(FONT_CN,26), fill=ACCENT)

    centered_text(d, "一键生成工资单  自动计算所有扣项", 930, load(FONT_CN,30), SOFT)

    img.save(os.path.join(OUT_DIR, "04_payroll.png"))
    print("✓ 04_payroll.png")

# ── Card 5: AI Pro ────────────────────────────────────────────────────────────

def card_ai():
    img = Image.new("RGB", (W, H))
    vgradient(img, (5, 10, 30), (0, 35, 60))
    d = ImageDraw.Draw(img)

    CYAN = (34, 211, 238)
    d.rectangle([0, 0, W, 8], fill=CYAN)

    d.text((60, 48), "AI PRO", font=load(FONT_EN, 22), fill=CYAN)

    centered_text(d, "AI智能助手", 100, load(FONT_CN, 84), WHITE)
    centered_text(d, "让AI帮你整理所有流水账", 200, load(FONT_CN, 44), CYAN)
    centered_text(d, "Auto-categorize · Bank Import · Cash Flow Forecast", 264, load(FONT_EN,22), SOFT)

    # feature boxes
    feats = [
        ("🤖 自动分类", "AI自动识别收支类别\n无需手动选择"),
        ("🏦 银行账单导入", "上传PDF，AI自动读取\n告别手动录入"),
        ("📈 现金流预测", "智能分析历史数据\n预测未来现金流"),
    ]
    bx = 60
    bw = (W - 60*2 - 24) // 3
    by = 360
    bh = 280
    for i, (title, desc) in enumerate(feats):
        x0 = bx + i * (bw + 12)
        d.rounded_rectangle([x0, by, x0+bw, by+bh], radius=16,
                            fill=(255,255,255,8), outline=CYAN, width=1)
        # top teal bar
        d.rounded_rectangle([x0, by, x0+bw, by+6], radius=3, fill=CYAN)
        d.text((x0+16, by+24), title, font=load(FONT_CN,26), fill=CYAN)
        desc_lines = desc.split("\n")
        for j, line in enumerate(desc_lines):
            d.text((x0+16, by+70+j*38), line, font=load(FONT_CN,24), fill=SOFT)

    # pricing card
    pc_x, pc_y = 120, 700
    pc_w, pc_h = W-120, 900
    d.rounded_rectangle([pc_x, pc_y, pc_w, pc_h], radius=20,
                        fill=(34,211,238,20), outline=CYAN, width=2)
    centered_text(d, "PRO 版价格", pc_y+20, load(FONT_CN,32), CYAN)
    d.line([(pc_x+20, pc_y+62), (pc_w-20, pc_y+62)], fill=CYAN, width=1)

    centered_text(d, "RM 9.90 /月", pc_y+82, load(FONT_EN,42), WHITE)
    centered_text(d, "或 RM 49.90 /年（省 RM 69）", pc_y+138, load(FONT_CN,28), ACCENT)

    tag_pill(d, "免费用户也可看3个广告解锁24小时Pro", W//2, 960, load(FONT_CN,26), DARK, CYAN)

    img.save(os.path.join(OUT_DIR, "05_ai_pro.png"))
    print("✓ 05_ai_pro.png")

# ── Card 6: Multi-Currency ───────────────────────────────────────────────────

def card_multicurrency():
    img = Image.new("RGB", (W, H))
    vgradient(img, (8, 20, 45), (5, 45, 35))
    d = ImageDraw.Draw(img)

    ORANGE = (251, 146, 60)
    d.rectangle([0, 0, W, 8], fill=ORANGE)

    d.text((60, 48), "MULTI-CURRENCY", font=load(FONT_EN, 22), fill=ORANGE)

    centered_text(d, "17种货币", 100, load(FONT_CN, 90), WHITE)
    centered_text(d, "实时汇率，跨境生意不烦恼", 205, load(FONT_CN, 44), ORANGE)
    centered_text(d, "Live FX Rates · Perfect for Import/Export", 268, load(FONT_EN,26), SOFT)

    # currency grid
    currencies = [
        ("MYR", "马币", "RM"),
        ("USD", "美元", "$"),
        ("SGD", "新币", "S$"),
        ("CNY", "人民币", "¥"),
        ("EUR", "欧元", "€"),
        ("GBP", "英镑", "£"),
        ("JPY", "日元", "¥"),
        ("AUD", "澳元", "A$"),
        ("HKD", "港币", "HK$"),
        ("THB", "泰铢", "฿"),
        ("IDR", "印尼盾", "Rp"),
        ("KRW", "韩元", "₩"),
    ]
    cols = 4
    cw = (W - 80) // cols
    ch = 100
    cx, cy = 40, 370
    for i, (code, name, sym) in enumerate(currencies):
        col = i % cols
        row = i // cols
        x = cx + col * cw
        y = cy + row * (ch + 8)
        bg = (251,146,60,25) if code == "MYR" else (255,255,255,8)
        bdr = ORANGE if code == "MYR" else (255,255,255,20)
        d.rounded_rectangle([x+4, y, x+cw-4, y+ch], radius=12, fill=bg, outline=bdr, width=1)
        d.text((x+16, y+10), sym, font=load(FONT_EN,30), fill=ORANGE if code=="MYR" else ACCENT)
        d.text((x+16, y+46), code, font=load(FONT_EN,22), fill=WHITE)
        d.text((x+16, y+72), name, font=load(FONT_CN,20), fill=SOFT)

    # "+" more tag
    x = cx + (len(currencies) % cols) * cw
    y = cy + (len(currencies) // cols) * (ch + 8)
    d.rounded_rectangle([x+4, y, x+cw-4, y+ch], radius=12, fill=(255,255,255,5))
    centered_text(d, "+5 More", y + 30, load(FONT_EN,28), SOFT, cw)

    tag_pill(d, "实时汇率  自动换算  支持库存多币种", W//2, 920, load(FONT_CN,28), DARK, ORANGE)
    centered_text(d, "进出口、网店卖家最佳选择", 970, load(FONT_CN,30), SOFT)

    img.save(os.path.join(OUT_DIR, "06_multicurrency.png"))
    print("✓ 06_multicurrency.png")

# ── Run all ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("Generating Bookly MY banners…")
    card_hero()
    card_invoice()
    card_sst()
    card_payroll()
    card_ai()
    card_multicurrency()
    print(f"\nDone! Saved to: {OUT_DIR}/")

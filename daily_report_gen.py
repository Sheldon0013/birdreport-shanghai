#!/usr/bin/env python3
"""Daily bird report generator - called by launchd at 8:00 AM"""
import json,re,smtplib,ssl,os,subprocess,sys
from datetime import datetime,timedelta
from email.mime.image import MIMEImage
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import Header

# Yesterday's date
yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
month = int((datetime.now() - timedelta(days=1)).strftime('%-m'))
date_display = (datetime.now() - timedelta(days=1)).strftime('%Y年%-m月%-d日')

# Season detection
if 3 <= month <= 5:
    season, term = '春', '春日'
    css = '--g950:#3d0009;--g900:#7f0013;--g700:#e50022;--g500:#ff3251;--g200:#ff99a8;--g100:#fed6dc;--g50:#ffeaed'
    hs, ds, fs = '#3d0009', '#e50022', '#ff3251'
elif 6 <= month <= 8:
    season, term = '夏', '夏日'
    css = '--g950:#0f2d19;--g900:#205e35;--g700:#3baa60;--g500:#67ca89;--g200:#b3e4c4;--g100:#e0f4e7;--g50:#eff9f3'
    hs, ds, fs = '#0f2d19', '#3baa60', '#67ca89'
elif 9 <= month <= 11:
    season, term = '秋', '秋日'
    css = '--g950:#3d1f00;--g900:#7f4100;--g700:#e57600;--g500:#ff9b32;--g200:#ffcd99;--g100:#feebd6;--g50:#fff5ea'
    hs, ds, fs = '#3d1f00', '#e57600', '#ff9b32'
else:
    season, term = '冬', '冬日'
    css = '--g950:#00283d;--g900:#00537f;--g700:#0096e5;--g500:#32b8ff;--g200:#99dbff;--g100:#d6f0fe;--g50:#eaf7ff'
    hs, ds, fs = '#00283d', '#0096e5', '#32b8ff'

# Seasonal narratives
stories = {
    '春': f'{{reports}} 份观鸟报告记录了早春时节申城的鸟类活动。候鸟开始北迁，鸻鹬类在沿海滩涂集结，柳莺类在林间穿梭。{{species}} 种鸟类为这一年拉开了序幕。',
    '夏': f'{{reports}} 份观鸟报告记录了盛夏时节申城的鸟类活动。白鹭、夜鹭在湿地间穿行，留鸟在城市的角落中安静栖息。{{species}} 种鸟类的每一份记录都见证着生命的韧性。',
    '秋': f'{{reports}} 份观鸟报告记录了深秋时节申城的鸟类活动。候鸟南迁接近尾声，雁鸭类开始抵达越冬地。秋风萧瑟中，{{species}} 种鸟类在申城留下了它们的踪迹。',
    '冬': f'{{reports}} 份观鸟报告记录了冬季申城的鸟类活动。雁鸭类在崇明东滩越冬，银鸥在黄浦江面翱翔。{{species}} 种留鸟与越冬候鸟共同构成了申城最寂静也最坚韧的生命图景。',
}

# Load checklist - track previous entry for subspecies fallback
LABEL = {'R':'留鸟','S':'夏候','W':'冬候','V':'迷鸟','Mp':'迁徙','Mv':'迁徙迷鸟','↓':'迁徙','WS':'冬夏候','MpS':'迁徙夏候','MpW':'迁徙冬候','WMp':'冬候迁徙','W*':'冬候','Mp*':'迁徙','Mv*':'迁徙迷鸟'}
lookup = {}; latin_lookup = {}
prev_cn = None
# Read file, skip everything before the actual checklist starts
raw = open(os.path.expanduser('~/Library/上海市鸟类名录2025.txt')).read()
checklist_start = raw.find('The Checklist of the Birds of Shanghai')
if checklist_start > 0:
    raw = raw[checklist_start:]
lines = raw.split(chr(10))
# Original code had: lines = open(os.path.expanduser('~/Library/上海市鸟类名录2025.txt')).readlines()
for idx, line in enumerate(lines):
    # Check for subspecies line
    if line.startswith('亚种'):
        parts = line.split()
        if len(parts) >= 2 and prev_cn and prev_cn in lookup and not lookup[prev_cn].get('residency'):
            ss_res = parts[2] if len(parts) >= 3 else (parts[1] if len(parts) >= 2 else '')
            # Strip parentheses/notes from residency code
            valid_rc_codes = {'R','S','W','V','Mp','Mv','↓','WS','SW','W/S','S/W','MpS','MpW','WMp','W*','Mp*','Mv*','Mp/S','Mp/W','W/Mp','R?','—'}
            if ss_res in valid_rc_codes:
                lookup[prev_cn]['residency'] = ss_res
        continue
    
    m = re.match(r'^(\d{3})([A-F])\s+(.+?)\s+([A-Z][a-z]+)', line)
    m = re.match(r'^(\d{3})([A-F])\s+(.+?)\s+([A-Z][a-z]+)', line)
    if not m: continue
    cn = m.group(3).strip()
    order_num = int(m.group(1))
    parts = line.split()
    for i, p in enumerate(parts):
        if p in ('c', 'uc', 'r') and i > 0:
            rc = parts[i-1]
            # Validate residency code: skip Latin species epithets
            valid_rc_codes = {'R','S','W','V','Mp','Mv','↓','WS','SW','W/S','S/W','MpS','MpW','WMp','W*','Mp*','Mv*','Mp/S','Mp/W','W/Mp','R?','—'}
            if rc in valid_rc_codes or (len(rc) == 1 and rc.isupper()):
                pass  # valid residency code
            else:
                rc = ''  # Not a residency code, leave empty for subspecies fallback
            if True:  # Always process
                # Extract Latin name: scan backwards from residency code to find Genus species
                # Genus starts with uppercase, species with lowercase, both before residency
                latin = ''
                for j in range(i-1, 1, -1):
                    if parts[j][0].isupper() and parts[j-1][0].islower():
                        latin = f'{parts[j]} {parts[j-1]}'  # wrong order
                        break
                # Actually: the genus is uppercase, species is lowercase. Look for: [lowercase, UPPERCASE] before residency
                for j in range(i-1, 1, -1):
                    if parts[j][0].islower() and parts[j-1][0].isupper():
                        latin = f'{parts[j-1]} {parts[j]}'
                        break
                entry = {'r': p, 'p': parts[i+1] if i+1 < len(parts) and parts[i+1] in ('1','2') else None,
                         'residency': rc, 'latin': latin, 'order': order_num}
                lookup[cn] = entry
                if latin:
                    latin_lookup[latin] = entry
            prev_cn = cn

# === Add species without rarity codes ===
_no_rarity = {
    "Sterna hirundo": {"r": None, "p": None, "residency": "↓", "order": 159},
    "Anas crecca": {"r": None, "p": None, "residency": "↓", "order": 38},
    "Pluvialis apricaria": {"r": None, "p": None, "residency": "V", "order": 87},
    "Ixobrychus flavicollis": {"r": "r", "p": None, "residency": "S", "order": 204},  # = Botaurus flavicollis (黑鳽)
    "Ixobrychus sinensis": {"r": "r", "p": None, "residency": "S", "order": 207},  # = Botaurus sinensis (黄苇鳽)
    "Saxicola stejnegeri": {"r": None, "p": None, "residency": "", "order": 99998},  # subspecies of Saxicola maurus
}
for _latin, _entry in _no_rarity.items():
    if _latin not in latin_lookup:
        latin_lookup[_latin] = _entry

# Load today's query data
data = json.load(open('/tmp/bird_daily.json'))
species = data['species']

# Apply checklist data - use Latin name as primary key for exact matching
order_map = {}  # Chinese name → checklist order number
for s in species:
    info = latin_lookup.get(s['l'], {})
    if not info:
        info = lookup.get(s['n'], {})
    if not info and ' ' in s['l']:
        # Fallback: match by species epithet, but require same genus initial
        parts = s['l'].split()
        if len(parts) >= 2:
            epithet = parts[1]
            genus_initial = parts[0][0] if parts[0] else ''
            for latin, entry in latin_lookup.items():
                lp = latin.split()
                if len(lp) >= 2 and lp[1] == epithet and lp[0][0] == genus_initial:
                    info = entry
                    break
    s['rarity'] = info.get('r')
    s['protection'] = info.get('p')
    s['residency_code'] = info.get('residency', '')
    s['order_idx'] = info.get('order', 99999)
    rc = s.get('residency_code','')
    if rc == 'V': r_sc = 300
    elif rc == 'Mv': r_sc = 280
    else: r_sc = 200 if s.get('rarity') == 'r' else (100 if s.get('rarity') == 'uc' else 0)
    p_sc = 20 if s.get('protection') == '1' else (10 if s.get('protection') == '2' else 0)
    s['score'] = r_sc + p_sc
    # Add residency-based tiebreaker for rare birds: V highest, then Mv, then Mp>S>W>R
    rc = s.get('residency_code','')
    if rc == 'V': s['score'] += 30
    elif rc == 'Mv': s['score'] += 25
    elif 'Mp' in str(rc): s['score'] += 4
    elif 'S' in str(rc): s['score'] += 3
    elif 'W' in str(rc): s['score'] += 2
    elif rc == 'R': s['score'] += 1

# Sort by checklist order
species.sort(key=lambda x: x['order_idx'])

# Find top 6 rare birds
candidates = [s for s in species if s['score'] > 0]
candidates.sort(key=lambda x: x['score'], reverse=True)
top6 = candidates[:min(6, len(candidates))]

total = sum(s['c'] for s in species)
orders = len(set(s['o'] for s in species))

# Bird icon SVGs
ICONS = [
    '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" style="margin-bottom:12px;opacity:0.3"><g stroke="#182418" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 7h.01M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/><path d="m20 7 2 .5-2 .5M10 18v3m4-3.25V21m-7-3a6 6 0 0 0 3.84-10.61"/></g></svg>',
    '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" style="margin-bottom:12px;opacity:0.3"><g fill="#182418"><path d="m12.594 23.258l-.012.002l-.071.035l-.02.004l-.014-.004l-.071-.036q-.016-.004-.024.006l-.004.01l-.017.428l.005.02l.01.013l.104.074l.015.004l.012-.004l.104-.074l.012-.016l.004-.017l-.017-.427q-.004-.016-.016-.018m.264-.113l-.014.002l-.184.093l-.01.01l-.003.011l.018.43l.005.012l.008.008l.201.092q.019.005.029-.008l.004-.014l-.034-.614q-.005-.019-.02-.022m-.715.002a.02.02 0 0 0-.027.006l-.006.014l-.034.614q.001.018.017.024l.015-.002l.201-.093l.01-.008l.003-.011l.018-.43l-.003-.012l-.01-.01z"/><path fill="#182418" d="M15 2a5 5 0 0 1 4.49 2.799l.094.201H21a1 1 0 0 1 .9 1.436l-.068.119l-1.552 2.327a1 1 0 0 0-.166.606l.014.128l.141.774c.989 5.438-3.108 10.451-8.593 10.606l-.262.004H3a1 1 0 0 1-.832-1.555l3.992-6.01l2.012-2.995l1.441-2.163A2.3 2.3 0 0 0 10 7a5 5 0 0 1 5-5m0 2a3 3 0 0 0-2.995 2.824L12 7a4.3 4.3 0 0 1-.493 2A3.5 3.5 0 0 1 15 12.5c0 1.368-.675 2.43-1.582 3.227c-.889.78-2.051 1.356-3.2 1.806c-.826.323-1.686.596-2.489.835l-1.945.565L5.56 19h5.853c4.368 0 7.669-3.955 6.887-8.252l-.14-.774a3 3 0 0 1 .455-2.201L19.131 7c-.54 0-1.072-.154-1.226-.75A3 3 0 0 0 15 4m-3.5 7c-.271 0-.663.07-1.036.209c-.375.14-.582.295-.654.378l-3.384 5.077c.998-.287 2.065-.603 3.063-.994c1.067-.417 1.978-.892 2.609-1.446c.612-.537.902-1.092.902-1.724a1.5 1.5 0 0 0-1.5-1.5M15 6a1 1 0 1 1 0 2a1 1 0 0 1 0-2"/></g></svg>',
    '<svg width="32" height="32" viewBox="0 0 48 48" fill="none" style="margin-bottom:12px;opacity:0.3"><g stroke="#182418" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="m9 14l-5 6.07S5.85 27.035 11 32c9.89 9.533 24.334 3.303 30-1c5.357-4.37 2.717-5.332 1-5l-5 1c9.065-14.301 6.575-15.828 4-15l-9 4c-5.769 3.177-8.5 1.5-10 0l-3-3c-4.5-4-8.97-.16-10 1"/><circle cx="14" cy="20" r="2" fill="#182418"/></g></svg>',
    '<svg width="32" height="32" viewBox="0 0 48 48" fill="none" style="margin-bottom:12px;opacity:0.3"><g stroke="#182418" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M6 23c-4.04-7.043 3.624-11.136 8-12c14.541-12.844 26.485-.287 28 8c1.514 8.287 1.158 14.893 2 18c-6.463-8.7-10.877-7.158-12-5c-2.02 4.144-5.314 4.252-7 3c-4.04-3.314-10.476 3.202-13 7c4.847-8.7 5.505-14.273 5-16c-2.02-8.286-8.307-5.416-11-3"/><circle cx="23" cy="16" r="2" fill="#182418"/></g></svg>',
    '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" style="margin-bottom:12px;opacity:0.3"><g stroke="#182418" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="9" rx="8" ry="7"/><path d="M12 9a4 4 0 1 1 8 0v12h-4C9.4 21 4 15.6 4 9a4 4 0 1 1 8 0v1M8 9h.01M16 9h.01"/><path d="M20 21a3.9 3.9 0 1 1 0-7.8m-10 6.2V22m4-1.15V22"/></g></svg>',
    '<svg width="32" height="32" viewBox="0 0 32 32" fill="none" style="margin-bottom:12px;opacity:0.3"><path fill="#182418" d="m9.844 1.664l-1.16.387c-1.625.543-2.707 1.258-3.34 2.148c-.637.89-.739 1.922-.574 2.746c.148.746.488 1.336.8 1.813c-.285.168-.351.11-.652.41c-.813.812-1.473 2.332-.867 4.148a3.86 3.86 0 0 0 2.379 2.422c.242.086.246.035.46.075c-.062.347-.132.39-.124.874c.02 1.114.414 2.622 1.816 3.528c.738.476 1.563.719 2.371.848L5.418 28.44l1.21.485c5.47 2.191 11.688.023 11.688.023l.684-.23V24.87c.773-.113 1.86-.324 3.2-.887c2.116-.886 4.507-2.699 4.796-5.894c.113-1.238-.176-2.543-.465-3.602c-.074-.277-.082-.254-.156-.488h3.285l-.777-1.469s-.524-1.027-.797-1.59c.781-1.742.215-3.64-1.227-4.441a3.25 3.25 0 0 0-1.324-.398c-1.418-.122-3.058.601-4.332 2.296c-.129.172-.664.805-.969 1.172a9 9 0 0 1-.308-.691C19.48 7.758 19 5.89 19 3V2h-1c-1.168 0-2.11.305-2.781.844s-1.028 1.261-1.188 1.914c-.226.894-.078 1.27 0 1.707c-.351.16-.601.191-1.113.703a3.8 3.8 0 0 0-.79 1.184a11.9 11.9 0 0 1-2.136-5.477zm7.261 2.574c.125 2.371.5 4.219.97 5.383c.28.703.585 1.223.823 1.57c-.691.825-.878 1.059-1.414 1.684c-.71-.344-2.144-1.145-3.609-2.523c-.215-.926.066-1.38.457-1.77c.438-.437.984-.633.984-.633l.88-.293l-.227-.898s-.172-.82 0-1.516c.09-.347.234-.625.5-.836c.11-.09.449-.097.636-.168m-8.761.301c.668 2.875 2.136 5.074 3.687 6.695l.02.082l.043-.015a17.3 17.3 0 0 0 4.492 3.347l1.176 1s4.074-4.77 5.035-6.046h.004c1.3-1.735 2.445-1.707 3.09-1.352c.64.355 1.02 1.078.277 2.195l-.297.446l.207.492c.082.203.172.344.309.617H23.53l.535 1.363s.278.707.54 1.653c.257.945.468 2.14.398 2.894c-.211 2.305-1.82 3.492-3.578 4.23s-3.492.86-3.492.86l-.934.063v4.125c-.863.25-4.484 1.113-8.273.175l4.648-6.191a16 16 0 0 0 1.813-.188l-.376-1.968s-.863.168-1.98.175c-1.113.012-2.422-.175-3.164-.656c-.723-.469-.89-1.148-.902-1.879a4.6 4.6 0 0 1 .183-1.34l.465-1.394L7.945 14s-.383.02-.843-.145c-.465-.168-.903-.425-1.153-1.171c-.394-1.184-.054-1.664.383-2.102c.438-.437.984-.633.984-.633l1.536-.511l-1.145-1.145s-.809-.89-.977-1.738c-.085-.426-.062-.77.239-1.192c.18-.246.879-.539 1.375-.824"/></svg>',
]

# Build rare cards HTML
rare_html = ''
for i, s in enumerate(top6):
    prot = f'<div class="tag">国家{"一级" if s["protection"]=="1" else "二级"}保护</div>' if s.get('protection') else ''
    rare_html += f'''<div class="rare-card">{ICONS[i]}<div class="rank">{i+1} &middot; {"罕见" if s["rarity"]=="r" else "不常见"}</div><div class="bird">{s["n"]}<span style="font-size:13px;color:var(--g700);margin-left:4px;font-weight:400">{s.get("residency_code","")}</span></div><div class="latin">{s["l"]}</div>{prot}</div>'''

# Build checklist table
table_rows = ''
for i, s in enumerate(species):
    st = ''
    if s.get('rarity') == 'r': st = '<span class="badge badge-rare">罕见</span>'
    elif s.get('rarity') == 'uc': st = '<span class="badge badge-uncommon">不常见</span>'
    else: st = '<span class="badge badge-common">常见</span>'
    if s.get('protection') == '1': st += ' <span class="badge badge-protected">一级</span>'
    elif s.get('protection') == '2': st += ' <span class="badge badge-protected">二级</span>'
    gray = s['order_idx'] >= 99998
    tc = 'color:#bbb' if gray else 'color:var(--g500)'
    tr_tc = 'color:#bbb;font-style:italic' if gray else ''
    count_tc = 'color:#bbb' if gray else 'color:var(--g700)'
    res_code = s.get("residency_code","") if not gray else "—"
    st_display = st if not gray else '<span style="color:#bbb;font-size:10px">未收录</span>'
    table_rows += f'<tr><td style="{tc}">{i+1}</td><td style="{tr_tc}"><b>{s["n"]}</b><span class="latin" style="{tc}">{s["l"]}</span></td><td style="{tr_tc}">{s["o"]}</td><td style="{tr_tc}">{s["f"]}</td><td style="text-align:right;font-weight:600;{count_tc};padding-right:32px">{s["c"]}</td><td style="font-size:12px;padding-left:32px;{tc}">{res_code}</td><td style="{tr_tc}">{st_display}</td></tr>\n'

story_text = stories[season].replace('{reports}', str(data['reports'])).replace('{species}', str(len(species)))

html = f'''<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Shanghai Bird Notes</title><style>@import url('https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@400;500;600;700&display=swap');*{{margin:0;padding:0;box-sizing:border-box}}body{{font-family:'Noto Serif SC','Georgia','Songti SC',serif;color:#1a201a;background:#fff;-webkit-font-smoothing:antialiased;line-height:1.7}}:root{{{css}}}section{{padding:80px 0;position:relative;overflow:hidden}}.hero{{padding:60px 28px 40px;display:flex;flex-direction:column;align-items:center;text-align:center;background:linear-gradient(180deg,#fff 0%,var(--g50) 100%)}}.hero .ornament{{position:absolute;opacity:0.06;pointer-events:none}}.hero .ornament.tl{{top:40px;left:40px}}.hero .ornament.br{{bottom:40px;right:40px;transform:rotate(180deg)}}.hero .label{{font-size:12px;letter-spacing:6px;color:var(--g700);margin-bottom:20px;opacity:0.7}}.hero h1{{font-size:clamp(36px,6vw,64px);font-weight:500;color:var(--g950);letter-spacing:-1px;line-height:1.2;max-width:700px;margin:0 auto}}.hero h1 em{{font-style:italic;color:var(--g700)}}.hero .date{{font-size:15px;color:var(--g700);margin-top:32px;letter-spacing:3px;opacity:0.6}}.stat-band{{background:var(--g50);padding:60px 0}}.stat-grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:40px;max-width:800px;margin:0 auto;padding:0 28px}}.stat-grid .item{{text-align:center}}.stat-grid .num{{font-size:48px;font-weight:500;color:var(--g900);line-height:1;font-family:'Georgia','Noto Serif SC',serif}}.stat-grid .num.accent{{color:var(--g700)}}.stat-grid .lbl{{font-size:12px;letter-spacing:4px;color:var(--g700);opacity:0.5;margin-top:6px}}.story{{text-align:center;padding:100px 28px}}.story .overline{{font-size:11px;letter-spacing:5px;color:var(--g700);opacity:0.5;margin-bottom:32px}}.story h2{{font-size:28px;font-weight:500;color:var(--g950);max-width:600px;margin:0 auto 20px;line-height:1.5}}.story p{{max-width:560px;margin:0 auto;color:var(--g900);opacity:0.7;font-size:15px;line-height:2}}.divider{{display:flex;justify-content:center;padding:0 0 20px}}.divider svg{{width:120px;height:auto;opacity:0.25}}.rare-list{{padding:60px 0}}.rare-items{{display:grid;grid-template-columns:repeat(3,1fr);gap:2px;max-width:960px;margin:0 auto;padding:0 28px}}.rare-card{{padding:36px 28px;background:var(--g50);text-align:center}}.rare-card .rank{{font-size:11px;letter-spacing:4px;color:var(--g700);opacity:0.5;margin-bottom:8px}}.rare-card .bird{{font-size:18px;font-weight:600;color:var(--g950)}}.rare-card .latin{{font-size:12px;font-style:italic;color:var(--g500);margin-top:2px}}.rare-card .tag{{display:inline-block;margin-top:8px;padding:3px 12px;font-size:10px;letter-spacing:3px;border:1px solid var(--g200);color:var(--g700)}}.checklist{{padding:60px 0}}.checklist .inner{{max-width:960px;margin:0 auto;padding:0 28px}}.checklist h2{{font-size:20px;font-weight:500;color:var(--g950);margin-bottom:24px;letter-spacing:2px;text-align:center}}.checklist h2 span{{color:var(--g500);font-weight:400;font-size:14px}}table{{width:100%;border-collapse:collapse}}thead th{{font-size:10px;letter-spacing:3px;color:var(--g500);font-weight:500;text-align:left;padding:10px 12px;border-bottom:1px solid var(--g200)}}tbody td{{padding:8px 12px;border-bottom:1px solid var(--g100);font-size:14px;color:var(--g950);vertical-align:top}}.latin{{font-size:11px;font-style:italic;color:var(--g500);display:block;margin-top:1px}}.badge{{display:inline-block;font-size:10px;letter-spacing:2px;padding:2px 8px;border-radius:2px}}.badge-rare{{background:#fff3e0;color:#c25100;font-weight:600}}.badge-uncommon{{background:var(--g100);color:var(--g700);font-weight:600}}.badge-common{{color:var(--g500)}}.badge-protected{{background:#fce4ec;color:#c62828;margin-left:4px;font-weight:600}}footer{{text-align:center;padding:60px 28px;background:var(--g50);font-size:11px;letter-spacing:3px;color:var(--g500)}}footer a{{color:var(--g700);text-decoration:none}}footer .ornament{{margin-top:20px;opacity:0.3}}</style></head><body>
<section class="hero"><svg class="ornament tl" width="180" height="200" viewBox="0 0 180 200" fill="none"><path d="M90 10 C60 40,20 80,30 130 C40 170,70 180,90 190" stroke="{hs}" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M90 10 C120 50,95 80,110 110" stroke="{hs}" stroke-width="1.5" fill="none" stroke-linecap="round"/><ellipse cx="85" cy="50" rx="18" ry="28" stroke="{hs}" stroke-width="1.2" fill="none" transform="rotate(-15,85,50)"/><ellipse cx="100" cy="65" rx="14" ry="22" stroke="{hs}" stroke-width="1" fill="none" transform="rotate(10,100,65)"/></svg><svg class="ornament br" width="180" height="200" viewBox="0 0 180 200" fill="none"><path d="M90 10 C60 40,20 80,30 130 C40 170,70 180,90 190" stroke="{hs}" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M90 10 C120 50,95 80,110 110" stroke="{hs}" stroke-width="1.5" fill="none" stroke-linecap="round"/><ellipse cx="85" cy="50" rx="18" ry="28" stroke="{hs}" stroke-width="1.2" fill="none" transform="rotate(-15,85,50)"/><ellipse cx="100" cy="65" rx="14" ry="22" stroke="{hs}" stroke-width="1" fill="none" transform="rotate(10,100,65)"/></svg><div class="label">上海 · 鸟类观察记录</div><h1><em>上海{term}</em><br>野外观察笔记</h1><div class="date">{date_display}</div></section>
<section class="stat-band"><div class="stat-grid"><div class="item"><div class="num">{data['reports']}</div><div class="lbl">观察报告</div></div><div class="item"><div class="num accent">{len(species)}</div><div class="lbl">鸟种</div></div><div class="item"><div class="num">{total}</div><div class="lbl">记录条数</div></div><div class="item"><div class="num">{orders}</div><div class="lbl">目</div></div></div></section>
<div class="divider"><svg viewBox="0 0 120 20" fill="none"><path d="M0 10 C20 2,40 18,60 10 C80 2,100 18,120 10" stroke="{ds}" stroke-width="1" fill="none"/><circle cx="60" cy="10" r="2" fill="{ds}"/></svg></div>
<section class="story"><div class="overline">今日观察笔记</div><h2>{term}申城，<br>{len(species)} 种鸟类共同栖息</h2><p>{story_text}</p></section>
<section class="rare-list"><div style="text-align:center;margin-bottom:32px;padding:0 28px"><div style="font-size:11px;letter-spacing:5px;color:var(--g700);opacity:0.5;margin-bottom:10px">值得关注的鸟种</div><h2 style="font-size:22px;font-weight:500;color:var(--g950)">值得关注的鸟种</h2></div><div class="rare-items">{rare_html}</div></section>
<section class="checklist"><div class="inner"><h2>完整鸟种名录 <span>{len(species)} 种</span></h2><table><thead><tr><th>#</th><th>鸟种</th><th>目</th><th>科</th><th style="text-align:right;padding-right:32px">次数</th><th style="padding-left:32px">居留型</th><th>状态</th></tr></thead><tbody>{table_rows}</tbody></table><p style="font-size:11px;color:var(--g500);margin-top:10px;text-align:center;line-height:1.8">居留型：R (留鸟)；S (夏候鸟)；W (冬候鸟)；Mp (过境旅鸟)；Mv (游荡旅鸟)；V (迷鸟)</p></div></section>
<footer class="footer"><div>中国观鸟记录中心 &middot; <a href="https://www.birdreport.cn" target="_blank">birdreport.cn</a></div><div class="ornament"><svg width="60" height="20" fill="none"><path d="M0 10 C10 4,20 16,30 10 C40 4,50 16,60 10" stroke="{fs}" stroke-width="0.8" fill="none"/></svg></div></footer>
</body></html>'''

out = f'/tmp/上海{yesterday.replace("-","")}鸟类统计.html'
with open(out, 'w') as f: f.write(html)
print(f'HTML: {out}')

# Validation
errors = []
content = open(out).read()
if re.search(r'\{data\[', content): errors.append('unexpanded variables')
if 'var(--g950)' not in content: errors.append('CSS missing')
for sec in ['hero', 'stat-band', 'divider', 'story', 'rare-list', 'checklist', 'footer']:
    if f'class="{sec}"' not in content: errors.append(f'missing {sec}')
if content.count('<tr><td') < 5: errors.append('too few table rows')
if content.count('class="rare-card"') < 3: errors.append('too few rare cards')
if 'badge badge' not in content: errors.append('status badges missing')

# New validations
# 1. Date check: HTML must contain the data date, not system date
expected_date = datetime.strptime(yesterday, '%Y-%m-%d').strftime('%Y年%-m月%-d日')
if expected_date not in content:
    errors.append(f'date mismatch: expected {expected_date}')

# 2. Season check: story must match season narrative
season_keywords = {'春':'候鸟开始北迁','夏':'白鹭、夜鹭在湿地间穿行','秋':'候鸟南迁接近尾声','冬':'崇明东滩越冬'}
expected_story = season_keywords.get(season, '')
if expected_story and expected_story not in content:
    errors.append(f'story does not match {season} season')

# 3. Checklist order check: first species should have lower order_idx than last (non-gray)
matched_birds = [s for s in species if s['order_idx'] < 99998]
if len(matched_birds) >= 2 and matched_birds[0]['order_idx'] >= matched_birds[-1]['order_idx']:
    errors.append('species not sorted by checklist order')

# 4. Residency check: no empty residency cells for matched species
empty_res = sum(1 for s in species if not s.get('residency_code','') and s['order_idx'] < 99998)
if empty_res > 0:
    names = [s['n'] for s in species if not s.get('residency_code','') and s['order_idx'] < 99998]
    errors.append(f'{empty_res} species missing residency: {", ".join(names[:5])}')

if errors:
    print(f'VALIDATION FAILED: {errors}')
    sys.exit(1)
print('Validation passed')

# Convert to PNG
img_out = out.replace('.html', '.png')
subprocess.run([os.path.expanduser('~/Desktop/kilo/html2png'), out, img_out], check=True)
print(f'PNG: {img_out}')


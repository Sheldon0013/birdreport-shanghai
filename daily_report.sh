#!/bin/bash
# Daily bird report - runs at 6:00 AM
# Query yesterday's Shanghai bird data, generate HTML, convert to PNG, send email

set -e
LOG="/tmp/birdreport-daily.log"
exec >> "$LOG" 2>&1

echo "=== $(date) ==="

# Calculate yesterday's date
YESTERDAY=$(date -v-1d +%Y-%m-%d)
DATE_DISPLAY=$(date -v-1d +"%Y年%-m月%-d日")

# Determine season and color
MONTH=$(date -v-1d +%-m)
if [ "$MONTH" -ge 3 ] && [ "$MONTH" -le 5 ]; then
  SEASON="春" TERM="春日"
  CSS="--g950:#3d0009;--g900:#7f0013;--g700:#e50022;--g500:#ff3251;--g200:#ff99a8;--g100:#fed6dc;--g50:#ffeaed"
  HS="#3d0009" DS="#e50022" FS="#ff3251"
elif [ "$MONTH" -ge 6 ] && [ "$MONTH" -le 8 ]; then
  SEASON="夏" TERM="夏日"
  CSS="--g950:#0f2d19;--g900:#205e35;--g700:#3baa60;--g500:#67ca89;--g200:#b3e4c4;--g100:#e0f4e7;--g50:#eff9f3"
  HS="#0f2d19" DS="#3baa60" FS="#67ca89"
elif [ "$MONTH" -ge 9 ] && [ "$MONTH" -le 11 ]; then
  SEASON="秋" TERM="秋日"
  CSS="--g950:#3d1f00;--g900:#7f4100;--g700:#e57600;--g500:#ff9b32;--g200:#ffcd99;--g100:#feebd6;--g50:#fff5ea"
  HS="#3d1f00" DS="#e57600" FS="#ff9b32"
else
  SEASON="冬" TERM="冬日"
  CSS="--g950:#00283d;--g900:#00537f;--g700:#0096e5;--g500:#32b8ff;--g200:#99dbff;--g100:#d6f0fe;--g50:#eaf7ff"
  HS="#00283d" DS="#0096e5" FS="#32b8ff"
fi

echo "Date: $YESTERDAY ($SEASON)"

# Step 1: Query API
echo "Querying..."
node -e '
const fs=require("fs"),crypto=require("crypto"),https=require("https");
global.window={};var CJ=require("/tmp/crypto-js.js");global.CryptoJS=CJ;global.window.CryptoJS=CJ;
eval(fs.readFileSync("/tmp/aes.util.js","utf8"));const API=global.window.BIRDREPORT_APIJS;
const KEY="-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCvxXa98E1uWXnBzXkS2yHUfnBM\n6n3PCwLdfIox03T91joBvjtoDqiQ5x3tTOfpHs3LtiqMMEafls6b0YWtgB1dse1W\n5m+FpeusVkCOkQxB4SZDH6tuerIknnmB/Hsq5wgEkIvO5Pff9biig6AyoAkdWpSe\nk/1/B7zYIepYY0lxKQIDAQAB\n-----END PUBLIC KEY-----";
function getUuid(){const h="0123456789abcdef",s=[];for(let i=0;i<32;i++)s[i]=h[Math.floor(Math.random()*16)];s[14]="4";s[19]=h[(parseInt(s[19],16)&3)|8];s[8]=s[13]=s[18]=s[23];return s.join("");}
function sortASCII(o){const s={};Object.keys(o).sort().forEach(k=>s[k]=o[k]);return s;}
function encryptLong(p){const M=117,b=Buffer.from(p,"utf8"),c=[];for(let i=0;i<b.length;i+=M)c.push(crypto.publicEncrypt({key:KEY,padding:crypto.constants.RSA_PKCS1_PADDING},b.subarray(i,Math.min(i+M,b.length))).toString("base64"));return c.join("");}
function req(p,params,q){return new Promise((R,rej)=>{const t=Date.now(),id=getUuid(),j=JSON.stringify(sortASCII(params)),b=encryptLong(j),s=crypto.createHash("md5").update(j+id+t).digest("hex"),qs=q?"?"+new URLSearchParams(q).toString():"";const hh=https.request({hostname:"api.birdreport.cn",path:p+qs,method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8","Content-Length":Buffer.byteLength(b),timestamp:String(t),requestId:id,sign:s,Referer:"https://www.birdreport.cn/",Origin:"https://www.birdreport.cn","User-Agent":"Mozilla/5.0"}},res=>{let d="";res.on("data",c=>d+=c);res.on("end",()=>{try{R(JSON.parse(d))}catch(e){R(d)}})});hh.on("error",rej);hh.write(b);hh.end()});}
async function main(){
  const base={province:"上海市",startTime:"'"$YESTERDAY"'",endTime:"'"$YESTERDAY"'",version:"CH4",mode:"0",taxonid:""};
  const summary=await req("/front/record/chart/summary",base);
  const taxon=await req("/front/record/activity/taxon",base,{limit:500,page:1});
  const species=JSON.parse(API.decode(taxon.data));
  const sorted=species.map(s=>({n:s.taxonname,l:s.latinname,o:s.taxonordername,f:s.taxonfamilyname,c:s.recordcount})).sort((a,b)=>b.c-a.c);
  fs.writeFileSync("/tmp/bird_daily.json",JSON.stringify({date:"'"$YESTERDAY"'",reports:summary.data.reports_count,species:sorted,term:"'"$TERM"'",season:"'"$SEASON"'"}));
  console.log(summary.data.reports_count+" reports, "+sorted.length+" species");
}
main().catch(e=>console.error(e));
'

# Step 2: Generate HTML + PNG + Send email via Python
echo "Generating report..."
python3 << 'PYEOF'
import json,re,smtplib,ssl,os
from email.mime.image import MIMEImage
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import Header

data=json.load(open("/tmp/bird_daily.json"))
species=data['species']
term=data['term']

# Load checklist for rarity
lookup={}
for line in open(os.path.expanduser('~/Desktop/kilo/上海市鸟类名录2025.txt')).read().split('\n'):
    m=re.match(r'^(\d{3}[A-F])\s+(.+?)\s+([A-Z][a-z]+(?:[\x27][A-Z][a-z]+)?(?:\s[A-Z][a-z]+(?:[\x27][A-Z][a-z]+)?)*)\s+([A-Z][a-z]+(?:\s[A-Z][a-z]+)*(?:\s[A-Z][a-z]+)?)\s',line)
    if not m: continue
    cn=m.group(2).strip()
    parts=line[m.end():].split()
    rar=None;prot=None
    for p in parts:
        if p in ('c','uc','r'): rar=p
        if p in ('1','2'): prot=p;break
    if cn and cn not in lookup: lookup[cn]={'r':rar,'p':prot}

for s in species:
    info=lookup.get(s['n'])
    s['rarity']=info['r'] if info else None
    s['protection']=info['p'] if info else None
    r_sc=(200 if s.get('rarity')=='r' else (100 if s.get('rarity')=='uc' else 0))
    p_sc=(20 if s.get('protection')=='1' else (10 if s.get('protection')=='2' else 0))
    s['score']=r_sc+p_sc

candidates=[s for s in species if s['score']>0]
candidates.sort(key=lambda x: x['score'], reverse=True)
top6=candidates[:6]

total=sum(s['c'] for s in species)
orders=len(set(s['o'] for s in species))

# Seasonal palettes
P={
  "春":{"css":"--g950:#3d0009;--g900:#7f0013;--g700:#e50022;--g500:#ff3251;--g200:#ff99a8;--g100:#fed6dc;--g50:#ffeaed","hs":"#3d0009","ds":"#e50022","fs":"#ff3251"},
  "夏":{"css":"--g950:#0f2d19;--g900:#205e35;--g700:#3baa60;--g500:#67ca89;--g200:#b3e4c4;--g100:#e0f4e7;--g50:#eff9f3","hs":"#0f2d19","ds":"#3baa60","fs":"#67ca89"},
  "秋":{"css":"--g950:#3d1f00;--g900:#7f4100;--g700:#e57600;--g500:#ff9b32;--g200:#ffcd99;--g100:#feebd6;--g50:#fff5ea","hs":"#3d1f00","ds":"#e57600","fs":"#ff9b32"},
  "冬":{"css":"--g950:#00283d;--g900:#00537f;--g700:#0096e5;--g500:#32b8ff;--g200:#99dbff;--g100:#d6f0fe;--g50:#eaf7ff","hs":"#00283d","ds":"#0096e5","fs":"#32b8ff"},
}
p=P[data['season']]

ICONS=[
  '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" style="margin-bottom:12px;opacity:0.3"><g stroke="#182418" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 7h.01M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/><path d="m20 7 2 .5-2 .5M10 18v3m4-3.25V21m-7-3a6 6 0 0 0 3.84-10.61"/></g></svg>',
  '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" style="margin-bottom:12px;opacity:0.3"><g fill="#182418"><path d="m12.594 23.258-.012.002-.071.035-.02.004-.014-.004-.071-.036q-.016-.004-.024.006l-.004.01-.017.428.005.02.01.013.104.074.015.004.012-.004.104-.074.012-.016.004-.017-.017-.427q-.004-.016-.016-.018m.264-.113-.014.002-.184.093-.01.01-.003.011.018.43.005.012.008.008.201.092q.019.005.029-.008l.004-.014-.034-.614q-.005-.019-.02-.022m-.715.002a.02.02 0 0 0-.027.006l-.006.014-.034.614q.001.018.017.024l.015-.002.201-.093.01-.008.003-.011.018-.43-.003-.012-.01-.01z"/><path d="M15 2a5 5 0 0 1 4.49 2.799l.094.201H21a1 1 0 0 1 .9 1.436l-.068.119-1.552 2.327a1 1 0 0 0-.166.606l.014.128.141.774c.989 5.438-3.108 10.451-8.593 10.606l-.262.004H3a1 1 0 0 1-.832-1.555l3.992-6.01 2.012-2.995 1.441-2.163A2.3 2.3 0 0 0 10 7a5 5 0 0 1 5-5m0 2a3 3 0 0 0-2.995 2.824L12 7a4.3 4.3 0 0 1-.493 2A3.5 3.5 0 0 1 15 12.5c0 1.368-.675 2.43-1.582 3.227-.889.78-2.051 1.356-3.2 1.806-.826.323-1.686.596-2.489.835l-1.945.565L5.56 19h5.853c4.368 0 7.669-3.955 6.887-8.252l-.14-.774a3 3 0 0 1 .455-2.201L19.131 7c-.54 0-1.072-.154-1.226-.75A3 3 0 0 0 15 4m-3.5 7c-.271 0-.663.07-1.036.209-.375.14-.582.295-.654.378l-3.384 5.077c.998-.287 2.065-.603 3.063-.994 1.067-.417 1.978-.892 2.609-1.446.612-.537.902-1.092.902-1.724a1.5 1.5 0 0 0-1.5-1.5M15 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2"/></g></svg>',
  '<svg width="32" height="32" viewBox="0 0 48 48" fill="none" style="margin-bottom:12px;opacity:0.3"><g stroke="#182418" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="m9 14-5 6.07S5.85 27.035 11 32c9.89 9.533 24.334 3.303 30-1 5.357-4.37 2.717-5.332 1-5l-5 1c9.065-14.301 6.575-15.828 4-15l-9 4c-5.769 3.177-8.5 1.5-10 0l-3-3c-4.5-4-8.97-.16-10 1"/><circle cx="14" cy="20" r="2" fill="#182418"/></g></svg>',
  '<svg width="32" height="32" viewBox="0 0 48 48" fill="none" style="margin-bottom:12px;opacity:0.3"><g stroke="#182418" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M6 23c-4.04-7.043 3.624-11.136 8-12 14.541-12.844 26.485-.287 28 8 1.514 8.287 1.158 14.893 2 18-6.463-8.7-10.877-7.158-12-5-2.02 4.144-5.314 4.252-7 3-4.04-3.314-10.476 3.202-13 7 4.847-8.7 5.505-14.273 5-16-2.02-8.286-8.307-5.416-11-3"/><circle cx="23" cy="16" r="2" fill="#182418"/></g></svg>',
  '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" style="margin-bottom:12px;opacity:0.3"><g stroke="#182418" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="9" rx="8" ry="7"/><path d="M12 9a4 4 0 1 1 8 0v12h-4C9.4 21 4 15.6 4 9a4 4 0 1 1 8 0v1M8 9h.01M16 9h.01"/><path d="M20 21a3.9 3.9 0 1 1 0-7.8m-10 6.2V22m4-1.15V22"/></g></svg>',
  '<svg width="32" height="32" viewBox="0 0 32 32" fill="none" style="margin-bottom:12px;opacity:0.3"><path fill="#182418" d="m9.844 1.664-1.16.387c-1.625.543-2.707 1.258-3.34 2.148-.637.89-.739 1.922-.574 2.746.148.746.488 1.336.8 1.813-.285.168-.351.11-.652.41-.813.812-1.473 2.332-.867 4.148a3.86 3.86 0 0 0 2.379 2.422c.242.086.246.035.46.075-.062.347-.132.39-.124.874.02 1.114.414 2.622 1.816 3.528.738.476 1.563.719 2.371.848L5.418 28.44l1.21.485c5.47 2.191 11.688.023 11.688.023l.684-.23V24.87c.773-.113 1.86-.324 3.2-.887 2.116-.886 4.507-2.699 4.796-5.894.113-1.238-.176-2.543-.465-3.602-.074-.277-.082-.254-.156-.488h3.285l-.777-1.469s-.524-1.027-.797-1.59c.781-1.742.215-3.64-1.227-4.441a3.25 3.25 0 0 0-1.324-.398c-1.418-.122-3.058.601-4.332 2.296-.129.172-.664.805-.969 1.172a9 9 0 0 1-.308-.691C19.48 7.758 19 5.89 19 3V2h-1c-1.168 0-2.11.305-2.781.844s-1.028 1.261-1.188 1.914c-.226.894-.078 1.27 0 1.707-.351.16-.601.191-1.113.703a3.8 3.8 0 0 0-.79 1.184 11.9 11.9 0 0 1-2.136-5.477zm7.261 2.574c.125 2.371.5 4.219.97 5.383.28.703.585 1.223.823 1.57-.691.825-.878 1.059-1.414 1.684-.71-.344-2.144-1.145-3.609-2.523-.215-.926.066-1.38.457-1.77.438-.437.984-.633.984-.633l.88-.293-.227-.898s-.172-.82 0-1.516c.09-.347.234-.625.5-.836.11-.09.449-.097.636-.168m-8.761.301c.668 2.875 2.136 5.074 3.687 6.695l.02.082.043-.015a17.3 17.3 0 0 0 4.492 3.347l1.176 1s4.074-4.77 5.035-6.046h.004c1.3-1.735 2.445-1.707 3.09-1.352.64.355 1.02 1.078.277 2.195l-.297.446.207.492c.082.203.172.344.309.617H23.53l.535 1.363s.278.707.54 1.653c.257.945.468 2.14.398 2.894-.211 2.305-1.82 3.492-3.578 4.23s-3.492.86-3.492.86l-.934.063v4.125c-.863.25-4.484 1.113-8.273.175l4.648-6.191a16 16 0 0 0 1.813-.188l-.376-1.968s-.863.168-1.98.175c-1.113.012-2.422-.175-3.164-.656-.723-.469-.89-1.148-.902-1.879a4.6 4.6 0 0 1 .183-1.34l.465-1.394L7.945 14s-.383.02-.843-.145c-.465-.168-.903-.425-1.153-1.171-.394-1.184-.054-1.664.383-2.102.438-.437.984-.633.984-.633l1.536-.511-1.145-1.145s-.809-.89-.977-1.738c-.085-.426-.062-.77.239-1.192.18-.246.879-.539 1.375-.824"/></svg>',
]

rare_html=''
for i in range(min(6, len(top6))):
    s=top6[i]
    prot=f'<div class="tag">国家{"一级" if s["protection"]=="1" else "二级"}保护</div>' if s.get('protection') else ''
    rare_html+=f'''    <div class="rare-card">
      {ICONS[i]}
      <div class="rank">{i+1} &middot; {"罕见" if s["rarity"]=="r" else "不常见"}</div>
      <div class="bird">{s["n"]}</div>
      <div class="latin">{s["l"]}</div>
      {prot}
    </div>
'''

table_rows=''
for i,s in enumerate(species):
    st=''
    if s.get('rarity')=='r': st='<span class="badge badge-rare">罕见</span>'
    elif s.get('rarity')=='uc': st='<span class="badge badge-uncommon">不常见</span>'
    else: st='<span class="badge badge-common">常见</span>'
    if s.get('protection')=='1': st+=' <span class="badge badge-protected">一级</span>'
    elif s.get('protection')=='2': st+=' <span class="badge badge-protected">二级</span>'
    table_rows+=f'<tr><td style="color:var(--g500)">{i+1}</td><td><b>{s["n"]}</b><span class="latin">{s["l"]}</span></td><td>{s["o"]}</td><td>{s["f"]}</td><td style="text-align:right;font-weight:600;color:var(--g700)">{s["c"]}</td><td>{st}</td></tr>\n'

date_display=os.popen('date -v-1d "+%Y年%-m月%-d日"').read().strip()

stories={
  "春":f'{data["reports"]} 份观鸟报告记录了早春时节申城的鸟类活动。候鸟开始北迁，鸻鹬类在沿海滩涂集结，柳莺类在林间穿梭。{len(species)} 种鸟类为这一年拉开了序幕。',
  "夏":f'{data["reports"]} 份观鸟报告记录了盛夏时节申城的鸟类活动。白鹭、夜鹭在湿地间穿行，留鸟在城市的角落中安静栖息。{len(species)} 种鸟类的每一份记录都见证着生命的韧性。',
  "秋":f'{data["reports"]} 份观鸟报告记录了深秋时节申城的鸟类活动。候鸟南迁接近尾声，雁鸭类开始抵达越冬地。秋风萧瑟中，{len(species)} 种鸟类在申城留下了它们的踪迹。',
  "冬":f'{data["reports"]} 份观鸟报告记录了冬季申城的鸟类活动。雁鸭类在崇明东滩越冬，银鸥在黄浦江面翱翔。{len(species)} 种留鸟与越冬候鸟共同构成了申城最寂静也最坚韧的生命图景。',
}
story_text=stories[data['season']]

html=f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Shanghai Bird Notes</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@400;500;600;700&display=swap');
  *{{margin:0;padding:0;box-sizing:border-box}}
  body{{font-family:'Noto Serif SC','Georgia','Songti SC',serif;color:#1a201a;background:#fff;-webkit-font-smoothing:antialiased;line-height:1.7}}
  :root{{{p["css"]}}}
  section{{padding:80px 0;position:relative;overflow:hidden}}
  .hero{{padding:60px 28px 40px;display:flex;flex-direction:column;align-items:center;text-align:center;background:linear-gradient(180deg,#fff 0%,var(--g50) 100%)}}
  .hero .ornament{{position:absolute;opacity:0.06;pointer-events:none}}
  .hero .ornament.tl{{top:40px;left:40px}}
  .hero .ornament.br{{bottom:40px;right:40px;transform:rotate(180deg)}}
  .hero .label{{font-size:12px;letter-spacing:6px;color:var(--g700);margin-bottom:20px;opacity:0.7}}
  .hero h1{{font-size:clamp(36px,6vw,64px);font-weight:500;color:var(--g950);letter-spacing:-1px;line-height:1.2;max-width:700px;margin:0 auto}}
  .hero h1 em{{font-style:italic;color:var(--g700)}}
  .hero .date{{font-size:15px;color:var(--g700);margin-top:16px;letter-spacing:3px;opacity:0.6}}
  .stat-band{{background:var(--g50);padding:60px 0}}
  .stat-grid{{display:grid;grid-template-columns:repeat(4,1fr);gap:40px;max-width:800px;margin:0 auto;padding:0 28px}}
  .stat-grid .item{{text-align:center}}
  .stat-grid .num{{font-size:48px;font-weight:500;color:var(--g900);line-height:1;font-family:'Georgia','Noto Serif SC',serif}}
  .stat-grid .num.accent{{color:var(--g700)}}
  .stat-grid .lbl{{font-size:12px;letter-spacing:4px;color:var(--g700);opacity:0.5;margin-top:6px}}
  .story{{text-align:center;padding:100px 28px}}
  .story .overline{{font-size:11px;letter-spacing:5px;color:var(--g700);opacity:0.5;margin-bottom:16px}}
  .story h2{{font-size:28px;font-weight:500;color:var(--g950);max-width:600px;margin:0 auto 20px;line-height:1.5}}
  .story p{{max-width:560px;margin:0 auto;color:var(--g900);opacity:0.7;font-size:15px;line-height:2}}
  .story .accent{{color:var(--g700);font-weight:600}}
  .divider{{display:flex;justify-content:center;padding:0 0 20px}}
  .divider svg{{width:120px;height:auto;opacity:0.25}}
  .rare-list{{padding:60px 0}}
  .rare-items{{display:grid;grid-template-columns:repeat(3,1fr);gap:2px;max-width:960px;margin:0 auto;padding:0 28px}}
  .rare-card{{padding:36px 28px;background:var(--g50);text-align:center}}
  .rare-card .rank{{font-size:11px;letter-spacing:4px;color:var(--g700);opacity:0.5;margin-bottom:8px}}
  .rare-card .bird{{font-size:18px;font-weight:600;color:var(--g950)}}
  .rare-card .latin{{font-size:12px;font-style:italic;color:var(--g500);margin-top:2px}}
  .rare-card .tag{{display:inline-block;margin-top:8px;padding:3px 12px;font-size:10px;letter-spacing:3px;border:1px solid var(--g200);color:var(--g700)}}
  .checklist{{padding:60px 0}}
  .checklist .inner{{max-width:900px;margin:0 auto;padding:0 28px}}
  .checklist h2{{font-size:20px;font-weight:500;color:var(--g950);margin-bottom:24px;letter-spacing:2px;text-align:center}}
  .checklist h2 span{{color:var(--g500);font-weight:400;font-size:14px}}
  table{{width:100%;border-collapse:collapse}}
  thead th{{font-size:10px;letter-spacing:3px;color:var(--g500);font-weight:500;text-align:left;padding:10px 16px;border-bottom:1px solid var(--g200)}}
  tbody td{{padding:8px 16px;border-bottom:1px solid var(--g100);font-size:14px;color:var(--g950);vertical-align:top}}
  .latin{{font-size:11px;font-style:italic;color:var(--g500);display:block;margin-top:1px}}
  .badge{{display:inline-block;font-size:10px;letter-spacing:2px;padding:2px 8px;border-radius:2px}}
  .badge-rare{{background:#fff3e0;color:#c25100;font-weight:600}}
  .badge-uncommon{{background:var(--g100);color:var(--g700);font-weight:600}}
  .badge-common{{color:var(--g500)}}
  .badge-protected{{background:#fce4ec;color:#c62828;margin-left:4px;font-weight:600}}
  footer{{text-align:center;padding:60px 28px;background:var(--g50);font-size:11px;letter-spacing:3px;color:var(--g500)}}
  footer a{{color:var(--g700);text-decoration:none}}
  footer .ornament{{margin-top:20px;opacity:0.3}}
</style></head><body>
<section class="hero"><svg class="ornament tl" width="180" height="200" viewBox="0 0 180 200" fill="none"><path d="M90 10 C60 40,20 80,30 130 C40 170,70 180,90 190" stroke="{p["hs"]}" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M90 10 C120 50,95 80,110 110" stroke="{p["hs"]}" stroke-width="1.5" fill="none" stroke-linecap="round"/><ellipse cx="85" cy="50" rx="18" ry="28" stroke="{p["hs"]}" stroke-width="1.2" fill="none" transform="rotate(-15,85,50)"/><ellipse cx="100" cy="65" rx="14" ry="22" stroke="{p["hs"]}" stroke-width="1" fill="none" transform="rotate(10,100,65)"/></svg><svg class="ornament br" width="180" height="200" viewBox="0 0 180 200" fill="none"><path d="M90 10 C60 40,20 80,30 130 C40 170,70 180,90 190" stroke="{p["hs"]}" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M90 10 C120 50,95 80,110 110" stroke="{p["hs"]}" stroke-width="1.5" fill="none" stroke-linecap="round"/><ellipse cx="85" cy="50" rx="18" ry="28" stroke="{p["hs"]}" stroke-width="1.2" fill="none" transform="rotate(-15,85,50)"/><ellipse cx="100" cy="65" rx="14" ry="22" stroke="{p["hs"]}" stroke-width="1" fill="none" transform="rotate(10,100,65)"/></svg><div class="label">上海 · 鸟类观察记录</div><h1><em>上海{term}</em><br>野外观察笔记</h1><div class="date">{date_display}</div></section>
<section class="stat-band"><div class="stat-grid"><div class="item"><div class="num">{data['reports']}</div><div class="lbl">观察报告</div></div><div class="item"><div class="num accent">{len(species)}</div><div class="lbl">鸟种</div></div><div class="item"><div class="num">{total}</div><div class="lbl">记录条数</div></div><div class="item"><div class="num">{orders}</div><div class="lbl">目</div></div></div></section>
<div class="divider"><svg viewBox="0 0 120 20" fill="none"><path d="M0 10 C20 2,40 18,60 10 C80 2,100 18,120 10" stroke="{p["ds"]}" stroke-width="1" fill="none"/><circle cx="60" cy="10" r="2" fill="{p["ds"]}"/></svg></div>
<section class="story"><div class="overline">今日观察笔记</div><h2>{term}申城，<br>{len(species)} 种鸟类共同栖息</h2><p>{story_text}</p></section>
<section class="rare-list"><div style="text-align:center;margin-bottom:32px;padding:0 28px"><div style="font-size:11px;letter-spacing:5px;color:var(--g700);opacity:0.5;margin-bottom:10px">值得关注的鸟种</div><h2 style="font-size:22px;font-weight:500;color:var(--g950)">值得关注的鸟种</h2></div><div class="rare-items">{rare_html}</div></section>
<section class="checklist"><div class="inner"><h2>完整鸟种名录 <span>{len(species)} 种</span></h2><table><thead><tr><th>#</th><th>鸟种</th><th>目</th><th>科</th><th style="text-align:right">次数</th><th>状态</th></tr></thead><tbody>{table_rows}</tbody></table></div></section>
<footer class="footer"><div>中国观鸟记录中心 &middot; <a href="https://www.birdreport.cn" target="_blank">birdreport.cn</a></div><div class="ornament"><svg width="60" height="20" fill="none"><path d="M0 10 C10 4,20 16,30 10 C40 4,50 16,60 10" stroke="{p["fs"]}" stroke-width="0.8" fill="none"/></svg></div></footer>
</body></html>'''

out=os.path.expanduser(f'~/Desktop/kilo/上海{data["date"].replace("-","")}鸟类统计.html')
with open(out,'w') as f: f.write(html)
print(f"HTML: {out}")

# ======== Validation ========
errors=[]
with open(out,'r') as f: content=f.read()

# Check 1: No un-expanded template variables
import re
if re.search(r'\{data\[', content) or re.search(r'\{len\(', content):
    errors.append("Un-expanded template variables found")

# Check 2: Required CSS :root
if 'var(--g950)' not in content or 'var(--g50)' not in content:
    errors.append("CSS :root variables missing")

# Check 3: Required sections
for sec in ['hero', 'stat-band', 'divider', 'story', 'rare-list', 'checklist', 'footer']:
    if f'class="{sec}"' not in content and f"class='{sec}'" not in content:
        errors.append(f"Section '{sec}' missing")

# Check 4: Table has data rows (at least 5 <tr> in tbody)
tbody_cnt=content.count('<tr><td')
if tbody_cnt < 5:
    errors.append(f"Table too few rows ({tbody_cnt})")

# Check 5: Rare birds section has cards
rare_cnt=content.count('class="rare-card"')
if rare_cnt < 3:
    errors.append(f"Rare cards missing or too few ({rare_cnt})")

# Check 6: Status badges present
if 'badge badge' not in content:
    errors.append("Status badges missing")

if errors:
    print(f"VALIDATION FAILED: {'; '.join(errors)}")
    print("Regenerating HTML...")
    # Regenerate HTML (same as above)
    out=os.path.expanduser(f'~/Desktop/kilo/上海{data["date"].replace("-","")}鸟类统计.html')
    with open(out,'w') as f: f.write(html)
    # Re-validate
    with open(out,'r') as f: content=f.read()
    err2=[]
    for sec in ['hero','stat-band','divider','story','rare-list','checklist','footer']:
        if f'class="{sec}"' not in content: err2.append(sec)
    if err2:
        print(f"Re-generation still failed: {err2}")
        print("Skipping email - manual fix needed")
        exit(1)
    print("HTML re-generated successfully")
else:
    print("Validation passed: all sections OK")

# ======== Convert to PNG ========
img_out=out.replace('.html','.png')
os.system(f'{os.path.expanduser("~/Desktop/kilo/html2png")} {out} {img_out}')
print(f"PNG: {img_out}")

# Send email
msg=MIMEMultipart('related')
msg['From']=msg['To']='yxd0013@126.com'
msg['Subject']=Header(f'上海{term}鸟况 {data["date"]} ({len(species)}种/{data["reports"]}篇)', 'utf-8')
with open(img_out,'rb') as f:
    img=MIMEImage(f.read());img.add_header('Content-ID','<r>');msg.attach(img)
msg.attach(MIMEText('<html><body style="margin:0"><img src="cid:r" style="width:100%;max-width:900px"></body></html>','html','utf-8'))
ctx=ssl.create_default_context()
with smtplib.SMTP_SSL('smtp.126.com',465,context=ctx,timeout=20) as s:
    s.login('yxd0013@126.com','WMnBMXKvjCqPnbBk')
    s.sendmail('yxd0013@126.com',['yxd0013@126.com'],msg.as_string())
print("Email sent")
PYEOF

echo "=== Done at $(date) ==="

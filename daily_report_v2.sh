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
/usr/local/bin/node -e '
const fs=require("fs"),crypto=require("crypto"),https=require("https");
global.window={};var CJ=require("/Users/sheldon/Library/crypto-js.js");global.CryptoJS=CJ;global.window.CryptoJS=CJ;
eval(fs.readFileSync("/Users/sheldon/Library/aes.util.js","utf8"));const API=global.window.BIRDREPORT_APIJS;
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


# Step 2: Generate HTML + PNG + Send email
/usr/bin/python3 -c "
import csv,json,os
csv_path = os.path.expanduser('~/Desktop/Birding/ebird_CN-31_life_list.csv')
seen_cn, seen_latin = set(), set()
with open(csv_path, 'r') as f:
    for row in csv.DictReader(f):
        cn=row.get('Common Name','').strip(); sn=row.get('Scientific Name','').strip()
        if cn: seen_cn.add(cn)
        if sn: seen_latin.add(sn)
json.dump({'cn':list(seen_cn),'latin':list(seen_latin)}, open(os.path.expanduser('~/Library/ebird_seen.json'),'w'), ensure_ascii=False)
"
/usr/bin/python3 /Users/sheldon/Library/gen_daily_report.py
echo "Done"
# Send email

# § Step 3: Send email with retry (up to 3 attempts)
for attempt in 1 2 3; do
  echo "Email attempt $attempt..."
  python3 -c "
import smtplib,ssl,json,time,sys
from email.mime.image import MIMEImage
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import Header
data=json.load(open('/tmp/bird_daily.json'))
img_path=f'/tmp/上海{data[\"date\"].replace(\"-\",\"\")}鸟类统计.png'
msg=MIMEMultipart('related')
msg['From']=msg['To']='yxd0013@126.com'
msg['Subject']=Header(f'上海{data[\"term\"]}鸟况 {data[\"date\"]} ({len(data[\"species\"])}种/{data[\"reports\"]}篇)', 'utf-8')
with open(img_path,'rb') as f:
    img=MIMEImage(f.read());img.add_header('Content-ID','<r>');msg.attach(img)
msg.attach(MIMEText('<html><body style=\"margin:0\"><img src=\"cid:r\" style=\"width:100%;max-width:900px\"></body></html>','html','utf-8'))
try:
    ctx=ssl.create_default_context()
    with smtplib.SMTP_SSL('smtp.126.com',465,context=ctx,timeout=30) as s:
        s.login('yxd0013@126.com','WMnBMXKvjCqPnbBk')
        s.sendmail('yxd0013@126.com',['yxd0013@126.com'],msg.as_string())
    print('OK')
except Exception as e:
    print(f'FAIL: {e}')
    sys.exit(1)
" && echo "Email sent" && break
  echo "Retry in 10s..."
  sleep 10
done

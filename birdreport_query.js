#!/usr/bin/env node
/**
 * 中国观鸟记录中心 (birdreport.cn) 数据查询 & HTML报告生成工具
 *
 * 用法:  node birdreport_query.js <省份> <日期> [选项]
 * 示例:  node birdreport_query.js 上海 2026-07-01
 *        node birdreport_query.js 云南 2026-06-01 --out ~/Desktop/云南报告.html
 *
 * 首次运行自动下载依赖库到 .cache/
 */

const fs = require("fs");
const crypto = require("crypto");
const https = require("https");
const path = require("path");
const os = require("os");

const TOOL_DIR = __dirname;
const OUT_DIR = TOOL_DIR;

// ========== 配置 (网站更新时调整这里) ==========
const CONFIG = {
  apiHost: "api.birdreport.cn",
  rsaKey: `-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCvxXa98E1uWXnBzXkS2yHUfnBM
6n3PCwLdfIox03T91joBvjtoDqiQ5x3tTOfpHs3LtiqMMEafls6b0YWtgB1dse1W
5m+FpeusVkCOkQxB4SZDH6tuerIknnmB/Hsq5wgEkIvO5Pff9biig6AyoAkdWpSe
k/1/B7zYIepYY0lxKQIDAQAB
-----END PUBLIC KEY-----`,
};

// ========== AES 解密 (使用 crypto-js, 与网站一致) ==========
const CryptoJS = require("crypto-js");

// BIRDREPORT_APIJS 内部映射: key(短)和iv(长)是互换存储的
// getMapping(key) → 8字节 AES密钥(CryptoJS自动兼容)
// getMapping(iv)  → 16字节 AES IV
const AES_KEY_HEX = "53536868555767547048526949655455";
const AES_IV_HEX  = "6756696653534952657053656868665752665050485566485667545454484967";

// getMapping: 每 2 个 hex 字符 → 十进制数 → fromCharCode
// 结果再被 CryptoJS.enc.Hex.parse 解析为字节
function aesDecrypt(cipherB64) {
  const mappedKey = getMappingStr(AES_KEY_HEX);
  const mappedIv  = getMappingStr(AES_IV_HEX);
  const keyBytes  = CryptoJS.enc.Hex.parse(mappedKey);
  const ivBytes   = CryptoJS.enc.Hex.parse(mappedIv);

  // CryptoJS.decrypt 将 base64 字符串解析为 CipherParams
  const cipherParams = CryptoJS.lib.CipherParams.create({
    ciphertext: CryptoJS.enc.Base64.parse(cipherB64)
  });

  const decrypted = CryptoJS.AES.decrypt(cipherParams, keyBytes, {
    iv: ivBytes,
    mode: CryptoJS.mode.CBC,
    padding: CryptoJS.pad.Pkcs7,
  });
  return decrypted.toString(CryptoJS.enc.Utf8);
}

function getMappingStr(hexStr) {
  let result = "";
  for (let i = 0; i < hexStr.length; i += 2) {
    result += String.fromCharCode(Number(hexStr.substr(i, 2)));
  }
  return result;
}

// ========== API 签名 & 请求 ==========
function getUuid() {
  const h = "0123456789abcdef", s = [];
  for (let i = 0; i < 32; i++) s[i] = h[Math.floor(Math.random() * 16)];
  s[14] = "4"; s[19] = h[(parseInt(s[19], 16) & 3) | 8];
  s[8] = s[13] = s[18] = s[23];
  return s.join("");
}
function sortASCII(o) { const s = {}; Object.keys(o).sort().forEach(k => s[k] = o[k]); return s; }
function encryptLong(pt) {
  const M = 117, buf = Buffer.from(pt, "utf8"), c = [];
  for (let i = 0; i < buf.length; i += M)
    c.push(crypto.publicEncrypt({ key: CONFIG.rsaKey, padding: crypto.constants.RSA_PKCS1_PADDING },
      buf.subarray(i, Math.min(i + M, buf.length))).toString("base64"));
  return c.join("");
}
function apiRequest(p, params, q) {
  return new Promise((resolve, reject) => {
    const t = Date.now(), id = getUuid();
    const j = JSON.stringify(sortASCII(params));
    const body = encryptLong(j);
    const sign = crypto.createHash("md5").update(j + id + t).digest("hex");
    const qs = q ? "?" + new URLSearchParams(q).toString() : "";
    const req = https.request({
      hostname: CONFIG.apiHost, path: p + qs, method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        "Content-Length": Buffer.byteLength(body),
        timestamp: String(t), requestId: id, sign: sign,
        Referer: "https://www.birdreport.cn/", Origin: "https://www.birdreport.cn",
        "User-Agent": "Mozilla/5.0",
      }
    }, res => { let d = ""; res.on("data", c => d += c); res.on("end", () => { try { resolve(JSON.parse(d)); } catch (e) { resolve(d); } }); });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ========== 数据查询 ==========
async function query(province, date) {
  const base = { province, startTime: date, endTime: date, version: "CH4", mode: "0", taxonid: "" };

  // 报告列表 (分页)
  const first = await apiRequest("/front/record/activity/search", base, { limit: 5, page: 1 });
  const total = first.count;
  let reports = JSON.parse(aesDecrypt(first.data));
  for (let pg = 2; (pg - 1) * 5 < total; pg++) {
    await sleep(300);
    const r = await apiRequest("/front/record/activity/search", base, { limit: 5, page: pg });
    reports.push(...JSON.parse(aesDecrypt(r.data)));
  }

  // 鸟种汇总
  const taxon = await apiRequest("/front/record/activity/taxon", base, { limit: 500, page: 1 });
  const species = JSON.parse(aesDecrypt(taxon.data));

  return {
    reports: reports.map(r => ({
      serialId: r.serial_id || "", pointName: r.point_name || "",
      username: r.username || "", time: r.start_time || "",
      taxoncount: r.taxoncount || 0,
    })).sort((a, b) => b.taxoncount - a.taxoncount),
    species: species.map(s => ({
      name: s.taxonname || "", count: s.recordcount || 0,
      latin: s.latinname || "", order: s.taxonordername || "",
      family: s.taxonfamilyname || "",
    })).sort((a, b) => b.count - a.count),
    date, province,
  };
}

// ========== HTML 报告生成 ==========
function genHTML(data) {
  const { date, province, reports, species } = data;
  const total = species.reduce((s, d) => s + d.count, 0);
  const colors = [
    "#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C","#E67E22",
    "#2980B9","#27AE60","#8E44AD","#D35400","#16A085","#C0392B",
    "#7F8C8D","#BDC3C7","#2C3E50","#F1C40F","#00BCD4","#FF5722","#795548",
    "#607D8B","#4CAF50","#FF9800","#673AB7","#2196F3","#009688",
    "#E91E63","#CDDC39","#FFC107","#03A9F4","#9E9E9E","#8BC34A",
  ];

  return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">
<title>${province} ${date} 鸟类记录统计</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"><\/script>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,"Microsoft YaHei",sans-serif;background:#f0f2f5;padding:20px;color:#333}
.container{max-width:1300px;margin:0 auto}
h1{text-align:center;color:#1a1a2e;margin-bottom:4px;font-size:24px}
.subtitle{text-align:center;color:#666;font-size:13px;margin-bottom:20px}
.summary-cards{display:flex;gap:12px;justify-content:center;margin-bottom:20px;flex-wrap:wrap}
.card{background:#fff;border-radius:10px;padding:16px 24px;text-align:center;box-shadow:0 1px 4px rgba(0,0,0,.06);min-width:110px}
.card .num{font-size:28px;font-weight:700;color:#2c3e50}
.card .label{font-size:12px;color:#888;margin-top:2px}
.charts{display:flex;gap:16px;margin-bottom:20px;flex-wrap:wrap;justify-content:center}
.chart-box{background:#fff;border-radius:10px;padding:16px;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.section{background:#fff;border-radius:10px;padding:16px;margin-bottom:16px;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.section h2{font-size:16px;color:#2c3e50;margin-bottom:12px;padding-bottom:8px;border-bottom:2px solid #3498DB}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#2c3e50;color:#fff;padding:8px 10px;text-align:left;position:sticky;top:0;white-space:nowrap}
td{padding:6px 10px;border-bottom:1px solid #eee}
tr:nth-child(even){background:#fafbfc}
tr:hover{background:#e8f4fd}
.report-table td:nth-child(4){font-weight:600;color:#2c3e50}
.bar-cell{display:flex;align-items:center;gap:6px}
.bar-fill{height:14px;border-radius:3px;min-width:2px;opacity:.85}
.pct{color:#999;font-size:11px}
.tag{display:inline-block;padding:1px 6px;border-radius:3px;font-size:11px}
.tag-high{background:#ffe0e0;color:#c0392b}
.tag-mid{background:#fff3cd;color:#856404}
.tag-low{background:#d4edda;color:#155724}
@media print{body{background:#fff}.section,.chart-box{box-shadow:none;border:1px solid #ddd}}
</style></head><body><div class="container">
<h1>🪶 ${province} ${date} 鸟类记录统计</h1>
<div class="subtitle">数据来源: 中国观鸟记录中心 · 生成: ${new Date().toISOString().slice(0, 10)}</div>
<div class="summary-cards">
  <div class="card"><div class="num">${reports.length}</div><div class="label">报告数</div></div>
  <div class="card"><div class="num">${species.length}</div><div class="label">鸟种数</div></div>
  <div class="card"><div class="num">${total}</div><div class="label">总记录条数</div></div>
</div>
<div class="charts">
<div class="chart-box" style="width:580px"><canvas id="pieChart" height="400"></canvas></div>
<div class="chart-box" style="width:680px"><canvas id="barChart" height="400"></canvas></div>
</div>
<div class="section"><h2>📋 ${reports.length}篇报告列表 (按鸟种数排序)</h2>
<table class="report-table">
<thead><tr><th>#</th><th>报告编号</th><th>观测地点</th><th>鸟种数</th><th>记录用户</th><th>观测时间</th></tr></thead><tbody>
${reports.map((r, i) => {
  const t = r.taxoncount >= 15 ? "tag-high" : r.taxoncount >= 8 ? "tag-mid" : "tag-low";
  const txt = r.taxoncount >= 15 ? "高" : r.taxoncount >= 8 ? "中" : "低";
  return `<tr><td>${i+1}</td><td>${r.serialId}</td><td>${r.pointName}</td><td>${r.taxoncount} <span class="tag ${t}">${txt}</span></td><td>${r.username}</td><td>${(r.time||"").slice(0,16)}</td></tr>`;
}).join("")}
</tbody></table></div>
<div class="section"><h2>🐦 ${species.length}种鸟类记录详情</h2>
<div style="max-height:600px;overflow-y:auto"><table>
<thead><tr><th>#</th><th>鸟种</th><th>拉丁学名</th><th>目</th><th>科</th><th>记录次数</th><th>占比</th><th>分布</th></tr></thead><tbody>
${species.map((s, i) => `<tr><td>${i+1}</td><td><b>${s.name}</b></td><td><i>${s.latin}</i></td><td>${s.order}</td><td>${s.family}</td><td>${s.count}</td><td class="pct">${(s.count/total*100).toFixed(1)}%</td><td><div class="bar-cell"><div class="bar-fill" style="width:${Math.max(s.count/total*360,4)}px;background:${colors[i%colors.length]}"></div></div></td></tr>`).join("")}
</tbody></table></div></div>
</div>
<script>
var sn=${JSON.stringify(species.map(s=>s.name))},sc=${JSON.stringify(species.map(s=>s.count))},t=${total};
var tn=sn.slice(0,20),tc=sc.slice(0,20),oc=sc.slice(20).reduce(function(a,b){return a+b},0);
new Chart(pieChart,{type:"pie",data:{labels:oc>0?tn.concat(["其他("+(sn.length-20)+"种)"]):tn,datasets:[{data:oc>0?tc.concat([oc]):tc,backgroundColor:${JSON.stringify(colors)}.slice(0,oc>0?21:tc.length)}]},options:{responsive:!0,maintainAspectRatio:!1,plugins:{title:{display:!0,text:"鸟种记录次数分布 · 饼图",font:{size:15},padding:8},legend:{position:"right",labels:{font:{size:10},padding:6,boxWidth:10}},tooltip:{callbacks:{label:function(c){return c.label+": "+c.raw+"次 ("+(c.raw/t*100).toFixed(1)+"%)"}}}}}});
new Chart(barChart,{type:"bar",data:{labels:sn,datasets:[{label:"记录次数",data:sc,backgroundColor:sc.map(function(_,i){return ${JSON.stringify(colors)}[i%32]})}]},options:{indexAxis:"y",responsive:!0,maintainAspectRatio:!1,plugins:{title:{display:!0,text:"全部鸟种记录次数 · 柱状图",font:{size:15},padding:8},legend:{display:!1},tooltip:{callbacks:{label:function(c){return c.label+": "+c.raw+"次"}}}},scales:{x:{title:{display:!0,text:"记录次数"}},y:{ticks:{font:{size:9}}}}}});
<\/script></body></html>`;
}

// ========== 主程序 ==========
async function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.log("用法: node birdreport_query.js <省份> <日期> [选项]");
    console.log("示例: node birdreport_query.js 上海 2026-07-01");
    console.log("      node birdreport_query.js 北京 2026-06-15 --out ~/Desktop/北京报告.html");
    process.exit(1);
  }

  const province = args[0];
  const date = args[1];
  let outPath = path.join(OUT_DIR, `${province}${date.replace(/-/g, "")}鸟类统计.html`);
  const oi = args.indexOf("--out");
  if (oi !== -1 && args[oi + 1]) outPath = args[oi + 1].replace(/^~/, os.homedir());

  console.log("=".repeat(50));
  console.log("  中国观鸟记录中心 数据查询工具");
  console.log(`  地区: ${province}  日期: ${date}`);
  console.log("=".repeat(50) + "\n");

  console.log("正在查询数据...\n");
  const data = await query(province, date);
  console.log(`\n结果: ${data.reports.length}篇报告 · ${data.species.length}种鸟 · ${data.species.reduce((s,d)=>s+d.count,0)}条记录`);

  console.log("生成 HTML 报告...");
  const html = genHTML(data);
  const outDir = path.dirname(outPath);
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(outPath, html);
  console.log(`已保存: ${outPath}`);

// 发送 HTML 邮件 (--email 参数, 使用 126 邮箱, 内含完整鸟种表格)
function sendEmail(province, date, data) {
  const speciesCount = data.species.length;
  const reportCount = data.reports.length;
  const recordCount = data.species.reduce((s,d)=>s+d.count,0);
  const colors = ["#E74C3C","#3498DB","#2ECC71","#F39C12","#9B59B6","#1ABC9C","#E67E22","#2980B9"];

  const rows = data.species.map((s, i) => {
    const bg = i % 2 === 0 ? '#fff' : '#fafbfc';
    const barW = Math.max(s.count / recordCount * 200, 3);
    const barColor = colors[i % colors.length];
    return `<tr style="background:${bg}"><td style="padding:3px 6px">${i+1}</td><td style="padding:3px 6px"><b>${s.name}</b></td><td style="padding:3px 6px;font-size:11px"><i>${s.latin}</i></td><td style="padding:3px 6px;font-size:11px">${s.order}</td><td style="padding:3px 6px;font-size:11px">${s.family}</td><td style="padding:3px 6px;text-align:center">${s.count}</td><td style="padding:3px 6px"><div style="height:10px;width:${barW}px;background:${barColor};border-radius:2px"></div></td></tr>`;
  }).join("\n");

  const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,'Microsoft YaHei',sans-serif;color:#333;padding:20px;background:#f0f2f5"><div style="max-width:800px;margin:0 auto;background:#fff;border-radius:10px;padding:24px;box-shadow:0 2px 8px rgba(0,0,0,0.08)"><h1 style="color:#1a1a2e;text-align:center;font-size:22px">🪶 ${province} ${date} 鸟类记录统计</h1><p style="text-align:center;color:#888;font-size:13px">数据来源: 中国观鸟记录中心 (birdreport.cn)</p><div style="display:flex;gap:12px;justify-content:center;margin:20px 0;flex-wrap:wrap"><div style="background:#f8f9fa;border-radius:8px;padding:14px 20px;text-align:center;min-width:90px"><div style="font-size:24px;font-weight:700;color:#2c3e50">${reportCount}</div><div style="font-size:11px;color:#888">报告数</div></div><div style="background:#f8f9fa;border-radius:8px;padding:14px 20px;text-align:center;min-width:90px"><div style="font-size:24px;font-weight:700;color:#2c3e50">${speciesCount}</div><div style="font-size:11px;color:#888">鸟种数</div></div><div style="background:#f8f9fa;border-radius:8px;padding:14px 20px;text-align:center;min-width:90px"><div style="font-size:24px;font-weight:700;color:#2c3e50">${recordCount}</div><div style="font-size:11px;color:#888">总记录条数</div></div></div><h2 style="font-size:15px;color:#2c3e50;border-bottom:2px solid #3498DB;padding-bottom:6px">🐦 ${speciesCount}种鸟类记录详情</h2><table style="width:100%;border-collapse:collapse;font-size:13px"><thead><tr style="background:#2c3e50;color:#fff"><th style="padding:6px 8px;text-align:left">#</th><th style="padding:6px 8px;text-align:left">鸟种</th><th style="padding:6px 8px;text-align:left">拉丁学名</th><th style="padding:6px 8px;text-align:left">目</th><th style="padding:6px 8px;text-align:left">科</th><th style="padding:6px 8px;text-align:center">次数</th><th style="padding:6px 8px;text-align:left">分布</th></tr></thead><tbody>${rows}</tbody></table><p style="color:#999;font-size:11px;text-align:center;margin-top:16px">生成时间: ${new Date().toLocaleString('zh-CN')} · 完整可视化报告见桌面 kilo 目录</p></div></body></html>`;

  const script = `
import smtplib, ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import Header
msg = MIMEMultipart('alternative')
msg['From'] = 'yxd0013@126.com'
msg['To'] = 'yxd0013@hotmail.com'
msg['Subject'] = Header('${province} ${date} 鸟类记录 (${speciesCount}种/${reportCount}篇)', 'utf-8')
msg.attach(MIMEText("""${html}""", 'html', 'utf-8'))
ctx = ssl.create_default_context()
s = smtplib.SMTP_SSL('smtp.126.com', 465, context=ctx, timeout=15)
s.login('yxd0013@126.com', 'WMnBMXKvjCqPnbBk')
s.sendmail('yxd0013@126.com', ['yxd0013@hotmail.com'], msg.as_string())
s.quit()
print('OK')
`;
  const result = require("child_process").execSync(
    `python3 -c '${script.replace(/'/g, "'\\''")}'`,
    { encoding: "utf8", timeout: 20000 }
  );
  if (result.includes("OK")) console.log("邮件已发送到 yxd0013@hotmail.com");
}
}

function sendEmail(province, date, data) {
  const speciesCount = data.species.length;
  const reportCount = data.reports.length;
  const recordCount = data.species.reduce((s,d)=>s+d.count,0);
  const top10 = data.species.slice(0,10).map((s,i) => `  ${i+1}. ${s.name} (${s.count}次)`).join("\\n");

  const script = `
import smtplib, ssl
from email.mime.text import MIMEText
from email.header import Header
body = """${province} ${date} 鸟类记录统计

报告数: ${reportCount} 篇
鸟种数: ${speciesCount} 种
总记录条数: ${recordCount} 条

Top 10:
${top10}

完整报告: ~/Desktop/kilo/${province}${date.replace(/-/g,"")}鸟类统计.html
数据来源: 中国观鸟记录中心 (birdreport.cn)
"""
msg = MIMEText(body, "plain", "utf-8")
msg["From"] = "yxd0013@126.com"
msg["To"] = "yxd0013@hotmail.com"
msg["Subject"] = Header("${province} ${date} 鸟类记录 (${speciesCount}种/${reportCount}篇)", "utf-8")
ctx = ssl.create_default_context()
s = smtplib.SMTP_SSL("smtp.126.com", 465, context=ctx, timeout=15)
s.login("yxd0013@126.com", "WMnBMXKvjCqPnbBk")
s.sendmail("yxd0013@126.com", ["yxd0013@hotmail.com"], msg.as_string())
s.quit()
print("OK")
`;
  const { execSync } = require("child_process");
  const result = execSync(`python3 -c "${script.replace(/"/g, '\\"')}"`, { encoding: "utf8", timeout: 20000 });
  if (result.includes("OK")) console.log("邮件已发送到 yxd0013@hotmail.com");
  else console.log("邮件发送异常:", result);
}

main().catch(e => { console.error("错误:", e.message); process.exit(1); });

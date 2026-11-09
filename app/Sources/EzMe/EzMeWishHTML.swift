// WishStudio renders every card as a small web page. That is what lets a card show a picture, a GIF or a
// video, and it is the same page that "Open as web page" saves, so what you see here is what you share.
import SwiftUI
import AppKit
import WebKit

// MARK: - State sent to the page

enum WishHTML {
    /// Everything the page needs to draw one card, as JSON.
    static func stateJSON(app: WishApp, card: WishCard, design: WishDesign, context: WishContext, selected: String?, mediaURL: (String) -> String) -> String {
        let bg = card.backgroundHex ?? design.background
        let accent = card.accentHex ?? design.accent
        var ink = design.ink
        if let custom = card.inkHex {
            ink = custom
        } else if card.backgroundHex != nil {
            ink = wishIsDark(bg) ? "#F6F1FF" : (wishIsDark(design.ink) ? design.ink : "#2B2B2B")
        }

        var values: [String: String] = [:]
        for field in app.fields {
            let key = field.key.lowercased()
            values[key] = context.variables[key] ?? ""
        }
        let known: Set<String> = ["eyebrow", "title", "name", "message", "from", "date"]
        let extras = app.fields.map { $0.key.lowercased() }.filter { !known.contains($0) && $0 != "data" }

        var styles: [String: Any] = [:]
        for (key, style) in card.styles {
            var entry: [String: Any] = [:]
            if let color = style.colorHex { entry["color"] = color }
            if style.scale != 1 { entry["scale"] = style.scale }
            if style.dx != 0 { entry["dx"] = style.dx }
            if style.dy != 0 { entry["dy"] = style.dy }
            if let bold = style.bold { entry["bold"] = bold }
            if let italic = style.italic { entry["italic"] = italic }
            if style.hidden { entry["hidden"] = true }
            if !entry.isEmpty { styles[key.lowercased()] = entry }
        }

        var state: [String: Any] = [
            "kind": app.kind == .greeting ? "greeting" : "infographic",
            "layout": design.layout,
            "bg": bg,
            "accent": accent,
            "ink": ink,
            "font": card.fontStyle.rawValue,
            "textScale": card.textScale,
            "magic": card.magic,
            "emoji": WishArtwork.emoji(card.artwork),
            "values": values,
            "extras": extras,
            "styles": styles,
            "selected": selected?.lowercased() ?? "",
            "lang": card.language == .hindi ? "hi" : "en",
            "title": app.name,
        ]

        for item in card.media ?? [] {
            let entry: [String: Any] = ["url": mediaURL(item.file), "kind": item.kind == "video" ? "video" : "image"]
            if item.placement == "background" { state["bgMedia"] = entry } else { state["hero"] = entry }
        }

        if app.kind == .infographic {
            let items = WishData.parse(values["data"] ?? "")
            let weights = WishData.weights(items)
            var list: [[String: Any]] = []
            for (index, item) in items.enumerated() {
                var entry: [String: Any] = ["l": item.label, "w": weights[index]]
                if let value = item.value {
                    entry["v"] = value
                    entry["t"] = WishFormula.formatNumber(value)
                } else {
                    entry["t"] = ""
                }
                list.append(entry)
            }
            state["items"] = list
            state["chartAccent"] = card.styles["data"]?.colorHex ?? accent
        }

        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text.replacingOccurrences(of: "</", with: "<\\/")
    }

    /// The whole page, with the first card already inside it.
    /// interactive: true inside EzMe (cards can be tapped to select); false for the saved web page.
    static func page(stateJSON: String, interactive: Bool = true) -> String {
        var html = template.replacingOccurrences(of: "__STATE__", with: stateJSON)
        if !interactive { html = html.replacingOccurrences(of: "<body class=\"live\">", with: "<body>") }
        return html
    }

    private static let template = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WishStudio</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden}
body{font-family:-apple-system,"SF Pro Text","Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased;background:radial-gradient(circle at 18% 8%,#f8f2fe,#ece4f8 58%,#e3daf3)}
#stage{position:fixed;inset:0;display:flex;align-items:center;justify-content:center}
#card{position:relative;width:520px;height:660px;flex:none;border-radius:22px;overflow:hidden;box-shadow:0 22px 56px rgba(60,30,110,.22);transform:scale(var(--s,1));transform-origin:center center;background:#fff}
body.export #stage{align-items:flex-start;justify-content:flex-start}
body.export #card{transform-origin:0 0;border-radius:0;box-shadow:none}
#card[data-font=classic]{--ff:Georgia,"Times New Roman","Noto Serif Devanagari",serif}
#card[data-font=modern]{--ff:-apple-system,"SF Pro Display","Helvetica Neue",sans-serif}
#card[data-font=romantic]{--ff:Georgia,"Times New Roman","Noto Serif Devanagari",serif;font-style:italic}
.layer{position:absolute;inset:0}
#bgm video,#bgm img,#hero video,#hero img{width:100%;height:100%;object-fit:cover;display:block}
#bgov{display:none}
#hero{position:absolute;top:82px;left:174px;width:172px;height:172px;border-radius:50%;overflow:hidden;display:none;box-shadow:0 8px 24px rgba(0,0,0,.18)}
#content{font-family:var(--ff)}
.g{position:absolute;inset:0;padding:50px 46px;display:flex;flex-direction:column;align-items:center;gap:16px}
.g.info{padding:46px 40px;gap:18px}
.el{position:relative;text-align:center;line-height:1.28;max-width:100%;cursor:default}
body.live .el{cursor:pointer}
body.live .el:hover{outline:1px dashed rgba(0,0,0,.2);outline-offset:6px;border-radius:6px}
.el.sel::after{content:"";position:absolute;inset:-7px;border:1.6px dashed var(--accent);border-radius:8px;pointer-events:none}
.chartbox{flex:1;width:100%;min-height:0;display:flex;flex-direction:column;justify-content:center;text-align:left}
.sp{position:absolute;pointer-events:none;color:var(--accent);opacity:.1;animation:tw 4s ease-in-out infinite}
@keyframes tw{0%,100%{opacity:.1;transform:translateY(0) scale(.8)}50%{opacity:.75;transform:translateY(-14px) scale(1.1)}}
@keyframes rise{from{opacity:0;translate:0 14px}to{opacity:1;translate:0 0}}
#card.play .el{animation:rise .7s cubic-bezier(.2,.7,.2,1) both;animation-delay:calc(var(--i,0)*90ms)}
#card.play #hero{animation:rise .8s cubic-bezier(.2,.7,.2,1) both;animation-delay:.12s}
.empty{font-size:15px;opacity:.55;text-align:center}
</style>
</head>
<body class="live">
<div id="stage">
<div id="card" class="play">
<div id="bgm" class="layer"></div>
<div id="bgov" class="layer"></div>
<div id="deco" class="layer"></div>
<div id="hero"></div>
<div id="content" class="layer"></div>
<div id="spark" class="layer"></div>
</div>
</div>
<script>
var S = __STATE__;
var card = document.getElementById('card');
var idx = 0;

function esc(t){return String(t==null?'':t).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\n/g,'<br>');}
function pad(n){return n<10?'0'+n:''+n;}
function rgba(hex,a){hex=String(hex||'#000000').replace('#','');if(hex.length===3){hex=hex.split('').map(function(c){return c+c;}).join('');}var n=parseInt(hex,16)||0;return 'rgba('+((n>>16)&255)+','+((n>>8)&255)+','+(n&255)+','+a+')';}
function post(k){try{if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.wish){window.webkit.messageHandlers.wish.postMessage(k);}}catch(e){}}
function st(key){return (S.styles||{})[key]||{};}

function line(key,base,o){
  o=o||{};
  var s=st(key);
  if(s.hidden){return '';}
  var v=(S.values||{})[key];
  if(!v){return '';}
  var size=base*S.textScale*(s.scale||1);
  var w=o.weight||400;
  if(s.bold===true){w=700;}else if(s.bold===false){w=400;}
  var color=s.color||o.color;
  if(o.alpha&&!s.color){color=rgba(color,o.alpha);}
  var css='font-size:'+size.toFixed(1)+'px;font-weight:'+w+';color:'+color+';';
  if(o.track){css+='letter-spacing:'+o.track+'px;';}
  if(o.upper){css+='text-transform:uppercase;';}
  if(s.italic===true){css+='font-style:italic;';}
  if(s.dx||s.dy){css+='transform:translate('+(s.dx||0)+'px,'+(s.dy||0)+'px);';}
  return '<div class="el'+(S.selected===key?' sel':'')+'" data-key="'+key+'" style="--i:'+(idx++)+';'+css+'">'+esc(v)+'</div>';
}

function artwork(){
  if(S.hero){return '<div style="height:172px;flex:none"></div>';}
  var s=st('artwork');
  if(s.hidden){return '';}
  var c=s.color||S.accent;
  var sz=62*(s.scale||1);
  var tr=(s.dx||s.dy)?'transform:translate('+(s.dx||0)+'px,'+(s.dy||0)+'px);':'';
  return '<div class="el'+(S.selected==='artwork'?' sel':'')+'" data-key="artwork" style="--i:1;width:172px;height:172px;flex:none;'+tr+'">'+
    '<div style="position:absolute;left:11px;top:11px;width:150px;height:150px;border-radius:50%;background:'+rgba(c,.14)+'"></div>'+
    '<div style="position:absolute;left:2px;top:2px;width:168px;height:168px;border-radius:50%;border:1px solid '+rgba(c,.35)+'"></div>'+
    '<div style="position:absolute;left:0;right:0;top:50%;transform:translateY(-50%);font-size:'+sz+'px;line-height:1;text-align:center">'+S.emoji+'</div></div>';
}

function eyebrow(){
  var l=line('eyebrow',11,{weight:600,color:S.accent,track:3,upper:true});
  return '<div style="height:16px;flex:none;display:flex;align-items:center;justify-content:center">'+l+'</div>';
}

function greeting(){
  var h=eyebrow();
  h+=artwork();
  h+=line('title',40,{weight:600,color:S.ink});
  h+=line('name',22,{weight:500,color:S.accent});
  h+=line('message',17,{color:S.ink,alpha:.85});
  (S.extras||[]).forEach(function(k){h+=line(k,16,{color:S.ink,alpha:.85});});
  h+='<div style="flex:1"></div>';
  h+=line('from',18,{weight:500,color:S.ink});
  h+=line('date',12,{weight:600,color:S.accent,track:2,upper:true});
  return '<div class="g">'+h+'</div>';
}

function cc(i){var o=['#C0507A','#3E9A9A','#C99A2E','#4F7FD1','#6BA36B','#9A62C9','#D9743A'];return i===0?S.chartAccent:o[(i-1)%o.length];}
function fs(n){return (n*S.textScale).toFixed(1)+'px';}

function circles(it){
  var cols=it.length<=4?2:3;
  var h='<div style="display:grid;grid-template-columns:repeat('+cols+',1fr);gap:14px;align-content:center;justify-items:center;width:100%">';
  it.forEach(function(d,i){var c=cc(i);
    h+='<div style="width:100%;max-width:190px;aspect-ratio:1/1;border-radius:50%;border:3px solid '+c+';background:'+rgba(c,.1)+';display:flex;flex-direction:column;align-items:center;justify-content:center;padding:12%;text-align:center">'+
      '<div style="font-size:11px;font-weight:600;color:'+rgba(S.ink,.6)+'">'+pad(i+1)+'</div>'+
      '<div style="font-size:'+fs(17)+';font-weight:600;color:'+S.ink+';line-height:1.15">'+esc(d.l)+'</div>'+
      (d.t?'<div style="font-size:12px;font-weight:500;color:'+c+'">'+esc(d.t)+'</div>':'')+'</div>';});
  return h+'</div>';
}

function table(it){
  var h='<div style="border-radius:12px;overflow:hidden;border:1px solid '+rgba(cc(0),.35)+'">';
  it.forEach(function(d,i){
    h+='<div style="display:flex;align-items:center;gap:12px;padding:11px 14px;background:'+(i%2===0?rgba(cc(0),.1):'transparent')+'">'+
      '<span style="width:26px;font-size:11px;font-weight:600;color:'+cc(0)+'">'+pad(i+1)+'</span>'+
      '<span style="flex:1;font-size:'+fs(17)+';font-weight:500;color:'+S.ink+'">'+esc(d.l)+'</span>'+
      '<span style="font-size:16px;font-weight:600;color:'+cc(0)+'">'+esc(d.t)+'</span></div>';});
  return h+'</div>';
}

function bars(it){
  var top=0.0001;it.forEach(function(d){if(d.w>top){top=d.w;}});
  var h='<div style="display:flex;flex-direction:column;gap:13px">';
  it.forEach(function(d,i){var c=cc(i);
    h+='<div><div style="display:flex;justify-content:space-between;margin-bottom:5px"><span style="font-size:'+fs(15)+';font-weight:500;color:'+S.ink+'">'+esc(d.l)+'</span><span style="font-size:13px;font-weight:600;color:'+c+'">'+esc(d.t)+'</span></div>'+
      '<div style="height:14px;border-radius:7px;background:'+rgba(c,.14)+'"><div style="height:14px;border-radius:7px;background:'+c+';width:'+Math.max(3,d.w/top*100)+'%"></div></div></div>';});
  return h+'</div>';
}

function donut(it){
  var total=0.0001;it.forEach(function(d){total+=d.w;});
  var R=70,C=2*Math.PI*R,run=0;
  var segs='';
  it.forEach(function(d,i){var f=d.w/total;var len=Math.max(0,f*C-1.5);
    segs+='<circle cx="110" cy="110" r="'+R+'" fill="none" stroke="'+cc(i)+'" stroke-width="40" stroke-dasharray="'+len+' '+(C-len)+'" stroke-dashoffset="'+(-run*C)+'" transform="rotate(-90 110 110)"/>';
    run+=f;});
  var h='<div style="display:flex;flex-direction:column;align-items:center;gap:16px"><svg width="220" height="220" viewBox="0 0 220 220">'+segs+
    '<text x="110" y="120" text-anchor="middle" font-size="34" font-weight="600" fill="'+S.ink+'" style="font-family:var(--ff)">'+it.length+'</text></svg>'+
    '<div style="width:100%;display:flex;flex-direction:column;gap:6px">';
  it.slice(0,8).forEach(function(d,i){h+='<div style="display:flex;align-items:center;gap:8px"><span style="width:10px;height:10px;border-radius:50%;background:'+cc(i)+'"></span><span style="flex:1;font-size:'+fs(14)+';color:'+S.ink+'">'+esc(d.l)+'</span><span style="font-size:12px;font-weight:600;color:'+rgba(S.ink,.7)+'">'+esc(d.t)+'</span></div>';});
  return h+'</div></div>';
}

function flow(it){
  var compact=it.length>5;
  var h='<div style="display:flex;flex-direction:column;align-items:stretch;gap:'+(compact?4:8)+'px">';
  it.forEach(function(d,i){
    h+='<div style="text-align:center;color:#fff;font-weight:600;font-size:'+fs(compact?15:19)+';padding:'+(compact?6:11)+'px 20px;border-radius:999px;background:'+cc(i)+'">'+esc(d.l)+'</div>';
    if(i<it.length-1){h+='<div style="text-align:center;font-size:'+(compact?10:13)+'px;font-weight:700;color:'+rgba(S.ink,.5)+'">&#9660;</div>';}});
  return h+'</div>';
}

function grid(it){
  var h='<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">';
  it.forEach(function(d,i){var c=cc(i);
    h+='<div style="min-height:74px;padding:14px;border-radius:14px;background:'+rgba(c,.12)+';border:1px solid '+rgba(c,.5)+'"><div style="font-size:11px;font-weight:700;color:'+c+';margin-bottom:8px">'+pad(i+1)+'</div><div style="font-size:'+fs(17)+';font-weight:600;color:'+S.ink+'">'+esc(d.l)+'</div>'+(d.t?'<div style="font-size:13px;font-weight:500;margin-top:6px;color:'+rgba(S.ink,.65)+'">'+esc(d.t)+'</div>':'')+'</div>';});
  return h+'</div>';
}

function timeline(it){
  var h='<div style="padding:0 10px">';
  it.forEach(function(d,i){
    h+='<div style="display:flex;gap:14px;align-items:stretch"><div style="display:flex;flex-direction:column;align-items:center;width:14px"><span style="width:14px;height:14px;border-radius:50%;background:'+cc(i)+';flex:none"></span>'+(i<it.length-1?'<span style="flex:1;width:2px;background:'+rgba(cc(0),.3)+'"></span>':'')+'</div>'+
      '<div style="padding-bottom:14px"><div style="font-size:'+fs(17)+';font-weight:600;color:'+S.ink+'">'+esc(d.l)+'</div>'+(d.t?'<div style="font-size:12px;font-weight:500;color:'+rgba(S.ink,.6)+'">'+esc(d.t)+'</div>':'')+'</div></div>';});
  return h+'</div>';
}

function ranked(it){
  var o=it.slice().sort(function(a,b){return (b.v==null?-1:b.v)-(a.v==null?-1:a.v);});
  var h='<div>';
  o.forEach(function(d,i){
    h+='<div style="display:flex;align-items:center;gap:14px;padding:9px 0;border-bottom:1px solid '+rgba(S.ink,.15)+'"><span style="width:40px;text-align:center;font-size:30px;font-weight:600;color:'+cc(0)+'">'+(i+1)+'</span><span style="flex:1;font-size:'+fs(18)+';font-weight:500;color:'+S.ink+'">'+esc(d.l)+'</span><span style="font-size:14px;font-weight:600;color:'+cc(0)+'">'+esc(d.t)+'</span></div>';});
  return h+'</div>';
}

function chart(){
  var it=S.items||[];
  if(!it.length){return '<div class="empty" style="color:'+S.ink+'">Add your list in the panel</div>';}
  switch(S.layout){
    case 'table':return table(it);
    case 'bars':return bars(it);
    case 'donut':return donut(it);
    case 'flow':return flow(it);
    case 'grid':return grid(it);
    case 'timeline':return timeline(it);
    case 'ranked':return ranked(it);
    default:return circles(it);
  }
}

function info(){
  var h=eyebrow();
  h+=line('title',32,{weight:600,color:S.ink});
  var s=st('data');
  var tr=(s.dx||s.dy)?'transform:translate('+(s.dx||0)+'px,'+(s.dy||0)+'px);':'';
  h+='<div class="el chartbox'+(S.selected==='data'?' sel':'')+'" data-key="data" style="--i:2;'+tr+'">'+chart()+'</div>';
  return '<div class="g info">'+h+'</div>';
}

function deco(){
  var a=S.accent;
  if(S.kind!=='greeting'){return '<div style="position:absolute;inset:16px;border-radius:14px;border:1px solid '+rgba(a,.35)+'"></div>';}
  if(S.layout==='arch'){return '<div style="position:absolute;inset:26px;border-radius:250px 250px 18px 18px;background:'+rgba(a,.1)+'"></div>';}
  if(S.layout==='band'){return '<div style="position:absolute;left:0;right:0;top:0;height:16px;background:'+a+'"></div><div style="position:absolute;left:0;right:0;bottom:0;height:16px;background:'+a+'"></div>';}
  return '<div style="position:absolute;inset:16px;border-radius:14px;border:1.4px solid '+rgba(a,.7)+'"></div><div style="position:absolute;inset:23px;border-radius:10px;border:.7px solid '+rgba(a,.35)+'"></div>';
}

function seed(i,s){var r=Math.sin(i*12.9898+s*78.233)*43758.5453;return r-Math.floor(r);}
function sparkles(){
  var n=[0,6,12,24][Math.max(0,Math.min(3,S.magic|0))];
  var key=n+'|'+S.accent;
  var el=document.getElementById('spark');
  if(el.dataset.k===key){return;}
  el.dataset.k=key;
  var h='';
  for(var i=0;i<n;i++){h+='<span class="sp" style="left:'+(seed(i,1)*96).toFixed(1)+'%;top:'+(seed(i,3)*92).toFixed(1)+'%;font-size:'+(8+seed(i,5)*12).toFixed(0)+'px;animation-delay:'+(seed(i,2)*4).toFixed(2)+'s;animation-duration:'+(3+seed(i,4)*3).toFixed(1)+'s">&#10022;</span>';}
  el.innerHTML=h;
}

function syncMedia(id,m){
  var el=document.getElementById(id);
  var key=m?(m.url+'|'+m.kind):'';
  if(el.dataset.k===key){return;}
  el.dataset.k=key;
  el.innerHTML='';
  if(!m){return;}
  var n;
  if(m.kind==='video'){
    n=document.createElement('video');
    n.src=m.url;n.autoplay=true;n.loop=true;n.muted=true;n.setAttribute('playsinline','');
    var p=n.play();if(p&&p.catch){p.catch(function(){});}
  }else{
    n=document.createElement('img');n.src=m.url;
  }
  el.appendChild(n);
}

function render(s){
  S=s;idx=0;
  document.documentElement.lang=S.lang||'en';
  document.title=S.title||'WishStudio';
  card.style.setProperty('--accent',S.accent);
  card.style.background=S.bg;
  card.setAttribute('data-font',S.font);
  syncMedia('bgm',S.bgMedia);
  var ov=document.getElementById('bgov');
  ov.style.display=S.bgMedia?'block':'none';
  ov.style.background=rgba(S.bg,.5);
  syncMedia('hero',S.kind==='greeting'?S.hero:null);
  document.getElementById('hero').style.display=(S.kind==='greeting'&&S.hero)?'block':'none';
  document.getElementById('deco').innerHTML=deco();
  document.getElementById('content').innerHTML=(S.kind==='greeting')?greeting():info();
  sparkles();
}

function fit(){
  var w=window.innerWidth,h=window.innerHeight;
  var s=Math.min((w-40)/520,(h-40)/660);
  if(document.body.classList.contains('export')){s=Math.min(1,Math.min(w/520,h/660));}
  s=Math.max(.2,Math.min(s,1.6));
  card.style.setProperty('--s',s);
}
function replay(){card.classList.remove('play');void card.offsetWidth;card.classList.add('play');}
function setExport(on){document.body.classList.toggle('export',!!on);document.body.classList.toggle('live',!on);fit();}
function exportRect(){var r=card.getBoundingClientRect();return [r.left,r.top,r.width,r.height];}

card.addEventListener('click',function(e){var t=e.target.closest?e.target.closest('[data-key]'):null;post(t?t.getAttribute('data-key'):'');e.stopPropagation();});
document.getElementById('stage').addEventListener('click',function(){post('');});
window.addEventListener('resize',fit);
render(S);
fit();
setTimeout(function(){card.classList.remove('play');},1800);
</script>
</body>
</html>
"""#
}

// MARK: - The web view

@MainActor
final class WishWebController: ObservableObject {
    weak var web: WKWebView?

    func replay() {
        web?.evaluateJavaScript("replay()", completionHandler: nil)
    }

    /// A picture of the card exactly as the page shows it (a video shows its current frame).
    func snapshot(_ done: @escaping (NSImage?) -> Void) {
        guard let web = web else {
            done(nil)
            return
        }
        web.evaluateJavaScript("setExport(true)") { _, _ in
            web.evaluateJavaScript("exportRect()") { value, _ in
                guard let numbers = value as? [Double], numbers.count == 4 else {
                    web.evaluateJavaScript("setExport(false)", completionHandler: nil)
                    done(nil)
                    return
                }
                let configuration = WKSnapshotConfiguration()
                configuration.rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                web.takeSnapshot(with: configuration) { image, _ in
                    web.evaluateJavaScript("setExport(false)", completionHandler: nil)
                    done(image)
                }
            }
        }
    }
}

struct WishWebView: NSViewRepresentable {
    let stateJSON: String
    var controller: WishWebController? = nil
    var onSelect: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "wish")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        controller?.web = web

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ezme-wish-\(UUID().uuidString).html")
        try? WishHTML.page(stateJSON: stateJSON).write(to: url, atomically: true, encoding: .utf8)
        context.coordinator.pageURL = url
        context.coordinator.lastJSON = stateJSON
        web.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        controller?.web = web
        guard stateJSON != coordinator.lastJSON else { return }
        coordinator.lastJSON = stateJSON
        if coordinator.loaded {
            web.evaluateJavaScript("render(\(stateJSON))", completionHandler: nil)
        } else {
            coordinator.pending = stateJSON
        }
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "wish")
        if let url = coordinator.pageURL { try? FileManager.default.removeItem(at: url) }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: WishWebView
        var loaded = false
        var lastJSON = ""
        var pending: String?
        var pageURL: URL?

        init(_ parent: WishWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let key = (message.body as? String) ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSelect(key)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let json = pending {
                pending = nil
                webView.evaluateJavaScript("render(\(json))", completionHandler: nil)
            }
        }
    }
}

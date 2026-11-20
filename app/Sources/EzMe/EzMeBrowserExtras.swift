import SwiftUI
import WebKit

// Browser extras: media-only viewing over any page, folders and tab groups on the start page,
// and the "which part of the page is visible" crop for split panes.

// MARK: - Media over the page

/// Runs a small script inside the page. Nothing on the page is deleted: the media view is an overlay,
/// text blur and hide are removed again with "Back to the normal page".
enum PageMedia {
    static func run(_ mode: String, in web: WKWebView) {
        web.evaluateJavaScript("(" + script + ")('" + mode + "')") { _, _ in }
    }

    private static let script = #"""
    function(mode){
      var OV='kd-media-overlay';
      function rm(id){var e=document.getElementById(id);if(e&&e.parentNode)e.parentNode.removeChild(e);}
      function clearText(){var l=document.querySelectorAll('.kd-txt');for(var i=0;i<l.length;i++)l[i].classList.remove('kd-txt');rm('kd-text-style');}
      function restoreVideos(){
        (window.__kdMoved||[]).forEach(function(m){
          try{
            if(m.ph.parentNode){m.ph.parentNode.insertBefore(m.node,m.ph);m.ph.parentNode.removeChild(m.ph);}
            m.node.style.cssText=m.css;
            if(m.controls)m.node.setAttribute('controls','');else m.node.removeAttribute('controls');
            m.node.muted=m.muted;
          }catch(e){}
        });
        window.__kdMoved=[];
      }
      function closeAll(){
        if(window.__kdObs){window.__kdObs.disconnect();window.__kdObs=null;}
        if(window.__kdObs2){window.__kdObs2.disconnect();window.__kdObs2=null;}
        if(window.__kdTimer){clearTimeout(window.__kdTimer);window.__kdTimer=null;}
        restoreVideos();rm(OV);
        if(window.__kdKey){document.removeEventListener('keydown',window.__kdKey,true);window.__kdKey=null;}
      }
      if(mode==='off'){closeAll();clearText();return 'off';}
      if(mode==='pip'){
        var vs=[].slice.call(document.querySelectorAll('video')).filter(function(x){return x.readyState>0;});
        vs.sort(function(a,b){return (b.videoWidth*b.videoHeight)-(a.videoWidth*a.videoHeight);});
        var pv0=vs[0];if(!pv0)return 'none';
        if(pv0.webkitSetPresentationMode){pv0.webkitSetPresentationMode('picture-in-picture');return 'pip';}
        if(pv0.requestPictureInPicture){pv0.requestPictureInPicture();return 'pip';}
        return 'none';
      }
      if(mode==='blur'||mode==='hide'){
        closeAll();clearText();
        var st=document.createElement('style');st.id='kd-text-style';
        st.textContent=mode==='blur'
          ? '.kd-txt{color:transparent!important;text-shadow:0 0 9px rgba(60,60,60,.8)!important}.kd-txt:hover{color:inherit!important;text-shadow:none!important}'
          : '.kd-txt{color:transparent!important;text-shadow:none!important}';
        document.head.appendChild(st);
        var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,null);var n;
        while((n=w.nextNode())){
          var p=n.parentElement;
          if(p&&n.nodeValue.trim().length>0&&!/^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA|INPUT)$/.test(p.tagName)){p.classList.add('kd-txt');}
        }
        return mode;
      }
      closeAll();
      window.__kdMoved=[];
      var items=[],known={},vidId=window.__kdVidId||0;
      var m=(mode==='theater'||mode==='strip'||mode==='list')?mode:'wall',idx=0;
      var loading=false,idle=0,done=false,sentinelSeen=false,statusEl=null,countEl=null,body=null,sentinel=null;

      function best(im){
        var a=im.closest&&im.closest('a');
        if(a&&a.href&&/\.(jpe?g|png|gif|webp|avif)([?#]|$)/i.test(a.href))return a.href;
        var ss=im.getAttribute('srcset')||'',bu='',bw=0;
        ss.split(',').forEach(function(p){var q=p.trim().split(/\s+/);if(q[0]){var wd=parseFloat(q[1])||1;if(wd>=bw){bw=wd;bu=q[0];}}});
        if(bu){try{return new URL(bu,document.baseURI).href;}catch(e){}}
        return im.currentSrc||im.src||im.getAttribute('data-src')||'';
      }
      function collect(){
        var added=0;
        function add(o,key){if(!key||known[key])return;known[key]=1;items.push(o);added++;}
        var vids=document.querySelectorAll('video');
        for(var a=0;a<vids.length;a++){
          var vv=vids[a];
          if(!vv.__kdId){vidId++;vv.__kdId=vidId;window.__kdVidId=vidId;}
          if(vv.parentNode)add({t:'video',node:vv,src:'v'+vv.__kdId},'v'+vv.__kdId);
        }
        var frs=document.querySelectorAll('iframe');
        for(var b=0;b<frs.length;b++){var fs=frs[b].src||'';if(/^https?:/i.test(fs)&&/youtube|youtu\.be|vimeo|dailymotion|player|embed|video/i.test(fs))add({t:'frame',src:fs},fs);}
        var ims=document.querySelectorAll('img');
        for(var c=0;c<ims.length;c++){
          var im=ims[c],u=best(im);
          if(!u||u.indexOf('data:image/svg')===0)continue;
          var iw=im.naturalWidth||im.width,ih=im.naturalHeight||im.height;
          if(iw&&ih&&(iw<120||ih<80))continue;
          add({t:'img',src:u,fb:im.currentSrc||im.src||''},u);
        }
        return added;
      }
      function el(tag,css,txt){var e=document.createElement(tag);if(css)e.style.cssText=css;if(txt)e.textContent=txt;return e;}
      function btn(label,fn,bg){var b=el('button','padding:5px 11px;border-radius:8px;border:0;cursor:pointer;color:#fff;background:'+(bg||'#34343a'),label);b.onclick=fn;return b;}
      function play(v,withSound){
        try{
          v.loop=true;v.setAttribute('playsinline','');
          v.muted=!withSound;
          var pr=v.play();
          if(pr&&pr.catch)pr.catch(function(){v.muted=true;try{v.play();}catch(e){}});
        }catch(e){}
      }
      function mediaNode(it,fit,withSound){
        if(it.t==='img'){
          var i=document.createElement('img');i.src=it.src;i.style.cssText=fit;i.decoding='async';
          i.onerror=function(){if(it.fb&&i.src!==it.fb){i.src=it.fb;}};
          return i;
        }
        if(it.t==='video'){
          var v=it.node;
          if(!it.parked&&v.parentNode){
            var ph=document.createComment('kd');v.parentNode.insertBefore(ph,v);
            window.__kdMoved.push({node:v,ph:ph,css:v.style.cssText,controls:v.hasAttribute('controls'),muted:v.muted});
            it.parked=true;
          }
          v.style.cssText=fit+';background:#000';v.setAttribute('controls','');
          if(withSound){setTimeout(function(){play(v,true);},0);}
          else if(window.__kdObs){window.__kdObs.observe(v);}
          return v;
        }
        var f=document.createElement('iframe');f.src=it.src;f.allowFullscreen=true;
        f.setAttribute('allow','autoplay; fullscreen; picture-in-picture');f.style.cssText=fit+';border:0;aspect-ratio:16/9';
        return f;
      }
      function setStatus(t){if(statusEl)statusEl.textContent=t;}
      function updateCount(){if(countEl)countEl.textContent='Media · '+items.length;}

      function addItem(it,n){
        var node;
        if(m==='wall'){
          node=el('div','border-radius:10px;overflow:hidden;background:#1d1d22;cursor:zoom-in');
          node.appendChild(mediaNode(it,'width:100%;height:190px;object-fit:cover;display:block;background:#000',false));
          node.onclick=function(e){var t=e.target.tagName;if(t==='VIDEO'||t==='IFRAME')return;m='theater';idx=n;render();};
        }else if(m==='strip'){
          node=mediaNode(it,'height:76vh;width:auto;max-width:90vw;object-fit:contain;flex:0 0 auto;border-radius:10px',false);
        }else{
          node=el('div','width:min(980px,96%);margin:0 auto 16px');
          node.appendChild(mediaNode(it,'width:100%;height:auto;max-height:88vh;object-fit:contain;display:block;border-radius:10px;background:#000',false));
        }
        if(sentinel&&sentinel.parentNode===body)body.insertBefore(node,sentinel);else body.appendChild(node);
      }

      function loadMore(){
        if(loading||done)return;
        loading=true;setStatus('Loading more…');
        var before=items.length;
        try{
          var bs=document.querySelectorAll('button,a,[role=button]');
          for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').trim();if(t.length<30&&/^(load|show|see|view)\s+more|^more$/i.test(t)){bs[i].click();break;}}
        }catch(e){}
        try{window.scrollTo(0,document.documentElement.scrollHeight);}catch(e){}
        window.__kdTimer=setTimeout(function(){
          var added=collect();
          loading=false;
          if(added===0){idle++;if(idle>=2){done=true;}}else{idle=0;}
          if(m==='theater'){updateCount();}
          else if(body){for(var k=before;k<items.length;k++){addItem(items[k],k);}updateCount();}
          setStatus(done?'That is everything found on this page.':'');if(!items.length&&body&&done){body.textContent='No pictures or videos found on this page yet.';}
          if(sentinel){sentinel.textContent='';sentinel.appendChild(done?btn('Look again',function(){done=false;idle=0;loadMore();}):el('span','color:#999','Loading more…'));}
          if(!done&&sentinelSeen&&m!=='theater'){window.__kdTimer=setTimeout(loadMore,250);}
        },1600);
      }

      function render(){
        if(window.__kdObs){window.__kdObs.disconnect();}
        if(window.__kdObs2){window.__kdObs2.disconnect();}
        window.__kdObs=new IntersectionObserver(function(es){es.forEach(function(e){
          var v=e.target;
          if(e.isIntersecting){play(v,false);}else{try{v.pause();}catch(x){}}
        });},{threshold:0.4});
        rm(OV);
        var o=el('div','position:fixed;top:0;left:0;right:0;bottom:0;z-index:2147483647;background:#101012;color:#fff;font:13px -apple-system,Helvetica,sans-serif;display:flex;flex-direction:column');
        o.id=OV;
        var bar=el('div','display:flex;gap:8px;align-items:center;padding:10px 14px;background:#1b1b1f;flex:0 0 auto');
        countEl=el('strong','margin-right:8px','');bar.appendChild(countEl);updateCount();
        [['wall','Wall'],['theater','One by one'],['strip','Filmstrip'],['list','Scroll']].forEach(function(p){
          bar.appendChild(btn(p[1],function(){m=p[0];render();},m===p[0]?'#e8603c':'#34343a'));
        });
        statusEl=el('span','color:#aaa;margin-left:8px','');bar.appendChild(statusEl);
        bar.appendChild(el('span','flex:1'));
        bar.appendChild(btn('Load more',function(){done=false;idle=0;loadMore();}));
        bar.appendChild(btn('Close ✕',closeAll,'#6b2b2b'));
        o.appendChild(bar);
        body=el('div','flex:1;overflow:auto;min-height:0;overscroll-behavior:contain');
        sentinel=null;
        if(!items.length){
          body.appendChild(el('div','padding:40px;text-align:center;color:#aaa','Looking for pictures and videos…'));
          o.appendChild(body);document.documentElement.appendChild(o);
          loadMore();return;
        }
        if(m==='theater'){
          body.style.cssText+=';display:flex;align-items:center;justify-content:center;position:relative;padding:10px';
          var cur=items[idx];
          body.appendChild(mediaNode(cur,'max-width:100%;max-height:100%;object-fit:contain;background:#000',true));
          var go=function(d){
            var next=idx+d;
            if(next>=items.length){if(!done){loadMore();setTimeout(function(){if(idx+1<items.length){idx++;render();}},1900);return;}next=0;}
            if(next<0)next=items.length-1;
            idx=next;render();
          };
          var pv=btn('‹',function(){go(-1);},'rgba(0,0,0,.55)');pv.style.cssText+=';position:absolute;left:14px;top:45%;font-size:26px;width:46px;height:46px;border-radius:23px';
          var nx=btn('›',function(){go(1);},'rgba(0,0,0,.55)');nx.style.cssText+=';position:absolute;right:14px;top:45%;font-size:26px;width:46px;height:46px;border-radius:23px';
          body.appendChild(pv);body.appendChild(nx);
          body.appendChild(el('div','position:absolute;bottom:10px;left:0;right:0;text-align:center;color:#bbb;pointer-events:none',(idx+1)+' of '+items.length));
          window.__kdGo=go;
          if(idx>=items.length-2&&!done)loadMore();
        }else{
          if(m==='wall'){body.style.cssText+=';display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:10px;padding:12px;align-content:start';}
          else if(m==='strip'){body.style.cssText+=';display:flex;gap:14px;align-items:center;overflow-x:auto;overflow-y:hidden;padding:14px';}
          else{body.style.cssText+=';padding:14px';}
          sentinel=el('div',m==='wall'?'grid-column:1/-1;text-align:center;padding:18px':(m==='strip'?'flex:0 0 160px;text-align:center':'text-align:center;padding:18px'));
          body.appendChild(sentinel);
          items.forEach(function(it,n){addItem(it,n);});
          sentinel.appendChild(done?btn('Look again',function(){done=false;idle=0;loadMore();}):el('span','color:#999','Loading more…'));
          window.__kdObs2=new IntersectionObserver(function(es){es.forEach(function(e){sentinelSeen=e.isIntersecting;if(e.isIntersecting&&!done)loadMore();});},{root:body,threshold:0.01});
          window.__kdObs2.observe(sentinel);
        }
        o.appendChild(body);
        document.documentElement.appendChild(o);
      }
      window.__kdKey=function(e){
        if(e.key==='Escape'){closeAll();e.stopPropagation();return;}
        if(m==='theater'&&items.length&&window.__kdGo){
          if(e.key==='ArrowRight'){window.__kdGo(1);e.preventDefault();}
          if(e.key==='ArrowLeft'){window.__kdGo(-1);e.preventDefault();}
        }
      };
      document.addEventListener('keydown',window.__kdKey,true);
      collect();
      render();
      return m+':'+items.length;
    }
    """#
}

// MARK: - Start page: folders and tab groups

struct BrowserHomeFolders: View {
    @ObservedObject var state: EzMeBrowserTabs
    @State private var newFolderOpen = false
    @State private var folderName = ""
    @State private var addTo: String?
    @State private var linkTitle = ""
    @State private var linkURL = ""
    @State private var expanded: Set<String> = []

    private func isFavorites(_ name: String) -> Bool { name.caseInsensitiveCompare("Favorites") == .orderedSame }

    private var folderNames: [String] {
        var names = state.collections.map { $0.title }.filter { !isFavorites($0) }
        for site in state.saved where !isFavorites(site.collection) && !names.contains(where: { $0.caseInsensitiveCompare(site.collection) == .orderedSame }) {
            names.append(site.collection)
        }
        return names
    }

    private var allFolderChoices: [String] { ["Favorites"] + folderNames }

    private var groups: [String] { state.orderedGroups.filter { !$0.isEmpty } }

    private func color(_ name: String) -> Color {
        let palette: [Color] = [Butter.coral, .blue, .green, .orange, .pink, .teal]
        return palette[abs(name.hashValue) % palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Folders", systemImage: "folder.fill").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                if !folderNames.isEmpty || !groups.isEmpty {
                    Button(expanded.isEmpty ? "Expand all" : "Collapse all") {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded = expanded.isEmpty ? Set(folderNames + groups.map { "g:" + $0 }) : [] }
                    }.buttonStyle(.borderless).font(.caption)
                }
                Button { folderName = ""; newFolderOpen = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(.bordered).tint(Butter.coral)
            }
            if folderNames.isEmpty {
                Text("Make a folder to keep related links together, then add links to it here or from the save button in the address bar.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(folderNames, id: \.self) { folder in folderSection(folder) }

            if !groups.isEmpty {
                Label("Tab groups", systemImage: "square.stack.3d.up.fill").font(.system(size: 16, weight: .bold, design: .rounded)).padding(.top, 10)
                ForEach(groups, id: \.self) { group in groupSection(group) }
            }
        }
        .alert("New folder", isPresented: $newFolderOpen) {
            TextField("Folder name", text: $folderName)
            Button("Create") { state.ensureCollection(folderName) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: Binding(get: { addTo != nil }, set: { if !$0 { addTo = nil } })) { addLinkSheet }
    }

    private func folderSection(_ folder: String) -> some View {
        let links = state.saved.filter { $0.collection.caseInsensitiveCompare(folder) == .orderedSame && $0.id != EzMeBrowserTabs.homeTabID }
        let open = expanded.contains(folder)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { if open { expanded.remove(folder) } else { expanded.insert(folder) } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: open ? "folder.fill" : "folder").foregroundStyle(Butter.coral).frame(width: 20)
                        Text(folder).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                        Text("\(links.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 1).background(Color.secondary.opacity(0.12), in: Capsule())
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if open {
                    if !links.isEmpty { Button("Open all") { for site in links.prefix(12) { state.newTab(site.url) } }.buttonStyle(.borderless).font(.caption) }
                    Button { linkTitle = ""; linkURL = ""; addTo = folder } label: { Label("Add link", systemImage: "plus") }.buttonStyle(.borderless).font(.caption)
                }
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            if open {
                if links.isEmpty {
                    Text("Empty folder. Add a link, or move one here with a right click.").font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                        ForEach(links) { site in linkCard(site) }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.14)))
    }

    private func linkCard(_ site: EzMeSavedSite) -> some View {
        Button { state.newTab(site.url) } label: {
            HStack(spacing: 10) {
                WebsiteIcon(url: site.url, title: site.title, size: 22).frame(width: 34, height: 34)
                    .background(Butter.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(SiteIconCache.host(site.url) ?? site.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Butter.coral.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Move to folder") {
                ForEach(allFolderChoices, id: \.self) { name in
                    Button(name) {
                        if let index = state.saved.firstIndex(where: { $0.id == site.id }) { state.saved[index].collection = name }
                    }
                }
            }
            Button("Open in a new tab") { state.newTab(site.url) }
            Button("Remove from folder", systemImage: "trash", role: .destructive) { state.removeBookmark(site.id) }
        }
    }

    private func groupSection(_ group: String) -> some View {
        let tabs = state.tabs.filter { (state.tabGroups[$0.id] ?? "") == group && $0.id != EzMeBrowserTabs.homeTabID }
        let key = "g:" + group
        let open = expanded.contains(key)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { if open { expanded.remove(key) } else { expanded.insert(key) } }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(color(group)).frame(width: 9, height: 9).frame(width: 20)
                        Text(group).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                        Text("\(tabs.count) open").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 1).background(Color.secondary.opacity(0.12), in: Capsule())
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if open {
                    Button("Save as folder", systemImage: "folder.badge.plus") {
                        state.ensureCollection(group)
                        for tab in tabs where tab.url.hasPrefix("http") {
                            state.saveCurrent(title: tab.title, url: tab.url, tags: [], note: "", collection: group)
                        }
                    }.buttonStyle(.borderless).font(.caption).help("Keep this group's links in a folder")
                }
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            if open {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs) { tab in
                            Button { state.select(tab.id) } label: {
                                HStack(spacing: 6) {
                                    SiteIconView(icon: state.icon(for: tab), title: tab.title, size: 14)
                                    Text(tab.title).font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(color(group).opacity(0.13), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.14)))
    }

    private var addLinkSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a link to \(addTo ?? "")").font(.title3.bold())
            TextField("Name (optional)", text: $linkTitle).textFieldStyle(.roundedBorder)
            TextField("Website address", text: $linkURL).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { addTo = nil }
                Button("Save") {
                    var address = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !address.isEmpty, let folder = addTo else { return }
                    if !address.contains("://") { address = "https://" + address }
                    let name = linkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.saveCurrent(title: name.isEmpty ? (SiteIconCache.host(address) ?? address) : name, url: address, tags: [], note: "", collection: folder)
                    addTo = nil
                }.buttonStyle(.borderedProminent).tint(Butter.coral).disabled(linkURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(20).frame(width: 400)
    }
}

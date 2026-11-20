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
      function closeAll(){rm(OV);if(window.__kdKey){document.removeEventListener('keydown',window.__kdKey,true);window.__kdKey=null;}if(window.__kdOv!==undefined){document.documentElement.style.overflow=window.__kdOv;window.__kdOv=undefined;}}
      if(mode==='off'){closeAll();clearText();return 'off';}
      if(mode==='pip'){
        var vs=[].slice.call(document.querySelectorAll('video')).filter(function(x){return x.readyState>0;});
        vs.sort(function(a,b){return (b.videoWidth*b.videoHeight)-(a.videoWidth*a.videoHeight);});
        var v=vs[0];if(!v)return 'none';
        if(v.webkitSetPresentationMode){v.webkitSetPresentationMode('picture-in-picture');return 'pip';}
        if(v.requestPictureInPicture){v.requestPictureInPicture();return 'pip';}
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
      var items=[];
      function collect(){
        var out=[],seen={};
        function add(o){if(!o.src||seen[o.src])return;seen[o.src]=1;out.push(o);}
        var vids=document.querySelectorAll('video');
        for(var a=0;a<vids.length;a++){
          var vv=vids[a];var s=vv.currentSrc||vv.src||'';
          if(!s){var so=vv.querySelector('source');if(so)s=so.src||'';}
          if(s&&s.indexOf('blob:')!==0){add({t:'video',src:s,poster:vv.poster||''});}
          else{add({t:'live',src:'live-'+a,node:vv});}
        }
        var frs=document.querySelectorAll('iframe');
        for(var b=0;b<frs.length;b++){var fs=frs[b].src||'';if(/^https?:/i.test(fs)&&/youtube|youtu\.be|vimeo|dailymotion|player|embed|video/i.test(fs))add({t:'frame',src:fs});}
        var ims=document.querySelectorAll('img');
        for(var c=0;c<ims.length;c++){
          var im=ims[c];var u=im.currentSrc||im.src||im.getAttribute('data-src')||'';
          if(!u||u.indexOf('data:image/svg')===0)continue;
          var iw=im.naturalWidth||im.width,ih=im.naturalHeight||im.height;
          if(iw&&ih&&(iw<120||ih<80))continue;
          add({t:'img',src:u});
        }
        return out;
      }
      items=collect();
      function el(tag,css,txt){var e=document.createElement(tag);if(css)e.style.cssText=css;if(txt)e.textContent=txt;return e;}
      function btn(label,fn,bg){var b=el('button','padding:5px 11px;border-radius:8px;border:0;cursor:pointer;color:#fff;background:'+(bg||'#34343a'),label);b.onclick=fn;return b;}
      function mediaNode(it,fit){
        if(it.t==='img'){var i=document.createElement('img');i.src=it.src;i.style.cssText=fit;return i;}
        if(it.t==='video'){var v=document.createElement('video');v.src=it.src;if(it.poster)v.poster=it.poster;v.controls=true;v.loop=true;v.muted=true;v.setAttribute('playsinline','');v.style.cssText=fit;return v;}
        if(it.t==='frame'){var f=document.createElement('iframe');f.src=it.src;f.allowFullscreen=true;f.setAttribute('allow','autoplay; fullscreen; picture-in-picture');f.style.cssText=fit+';border:0;aspect-ratio:16/9';return f;}
        var b=btn('Streaming video: jump to it on the page',function(){closeAll();try{it.node.scrollIntoView({block:'center'});}catch(e){}});b.style.padding='18px';return b;
      }
      var m=(mode==='theater'||mode==='strip'||mode==='list')?mode:'wall',idx=0;
      window.__kdOv=document.documentElement.style.overflow;
      function render(){
        rm(OV);
        var o=el('div','position:fixed;top:0;left:0;right:0;bottom:0;z-index:2147483647;background:#101012;color:#fff;font:13px -apple-system,Helvetica,sans-serif;display:flex;flex-direction:column');
        o.id=OV;
        var bar=el('div','display:flex;gap:8px;align-items:center;padding:10px 14px;background:#1b1b1f;flex:0 0 auto');
        bar.appendChild(el('strong','margin-right:8px','Media · '+items.length));
        [['wall','Wall'],['theater','One by one'],['strip','Filmstrip'],['list','Scroll']].forEach(function(p){
          bar.appendChild(btn(p[1],function(){m=p[0];render();},m===p[0]?'#e8603c':'#34343a'));
        });
        bar.appendChild(el('span','flex:1'));
        bar.appendChild(btn('Rescan',function(){items=collect();idx=0;render();}));
        bar.appendChild(btn('Close ✕',closeAll,'#6b2b2b'));
        o.appendChild(bar);
        var body=el('div','flex:1;overflow:auto;min-height:0');
        if(!items.length){
          body.appendChild(el('div','padding:40px;text-align:center;color:#aaa','No pictures or videos found yet. Scroll the page so they load, then press Rescan.'));
        }else if(m==='wall'){
          body.style.cssText+=';display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:10px;padding:12px;align-content:start';
          items.forEach(function(it,n){
            var c=el('div','border-radius:10px;overflow:hidden;background:#1d1d22;cursor:zoom-in');
            c.appendChild(mediaNode(it,'width:100%;height:190px;object-fit:cover;display:block'));
            c.onclick=function(e){if(e.target.tagName==='VIDEO'||e.target.tagName==='BUTTON'||e.target.tagName==='IFRAME')return;m='theater';idx=n;render();};
            body.appendChild(c);
          });
        }else if(m==='theater'){
          body.style.cssText+=';display:flex;align-items:center;justify-content:center;position:relative;padding:10px';
          body.appendChild(mediaNode(items[idx],'max-width:100%;max-height:100%;object-fit:contain'));
          var go=function(d){idx=(idx+items.length+d)%items.length;render();};
          var pv=btn('‹',function(){go(-1);},'rgba(0,0,0,.55)');pv.style.cssText+=';position:absolute;left:14px;top:45%;font-size:26px;width:46px;height:46px;border-radius:23px';
          var nx=btn('›',function(){go(1);},'rgba(0,0,0,.55)');nx.style.cssText+=';position:absolute;right:14px;top:45%;font-size:26px;width:46px;height:46px;border-radius:23px';
          body.appendChild(pv);body.appendChild(nx);
          body.appendChild(el('div','position:absolute;bottom:10px;left:0;right:0;text-align:center;color:#bbb',(idx+1)+' of '+items.length));
        }else if(m==='strip'){
          body.style.cssText+=';display:flex;gap:14px;align-items:center;overflow-x:auto;overflow-y:hidden;padding:14px';
          items.forEach(function(it){body.appendChild(mediaNode(it,'height:76vh;width:auto;max-width:90vw;object-fit:contain;flex:0 0 auto;border-radius:10px'));});
        }else{
          body.style.cssText+=';padding:14px';
          items.forEach(function(it){var w=el('div','width:min(920px,96%);margin:0 auto 14px');w.appendChild(mediaNode(it,'width:100%;height:auto;display:block;border-radius:10px'));body.appendChild(w);});
        }
        o.appendChild(body);
        document.documentElement.appendChild(o);
        document.documentElement.style.overflow='hidden';
      }
      window.__kdKey=function(e){
        if(e.key==='Escape'){closeAll();e.stopPropagation();return;}
        if(m==='theater'&&items.length){
          if(e.key==='ArrowRight'){idx=(idx+1)%items.length;render();e.preventDefault();}
          if(e.key==='ArrowLeft'){idx=(idx+items.length-1)%items.length;render();e.preventDefault();}
        }
      };
      document.addEventListener('keydown',window.__kdKey,true);
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
    @State private var collapsed: Set<String> = []

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
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Folders", systemImage: "folder.fill").font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                Button { folderName = ""; newFolderOpen = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(.bordered).tint(Butter.coral)
            }
            if folderNames.isEmpty {
                Text("Make a folder to keep related links together, then add links to it here or from the save button in the address bar.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(folderNames, id: \.self) { folder in folderSection(folder) }

            if !groups.isEmpty {
                Divider().padding(.vertical, 2)
                Label("Tab groups", systemImage: "square.stack.3d.up.fill").font(.system(size: 19, weight: .bold, design: .rounded))
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
        let open = !collapsed.contains(folder)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    if open { collapsed.insert(folder) } else { collapsed.remove(folder) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: open ? "folder.fill" : "folder").foregroundStyle(Butter.coral)
                        Text(folder).font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("\(links.count)").font(.caption.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2).background(Butter.coral.opacity(0.14), in: Capsule())
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
                Spacer()
                if !links.isEmpty {
                    Button("Open all") { for site in links.prefix(12) { state.newTab(site.url) } }.buttonStyle(.borderless).font(.caption)
                }
                Button { linkTitle = ""; linkURL = ""; addTo = folder } label: { Label("Add link", systemImage: "plus") }.buttonStyle(.borderless).font(.caption)
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(color(group)).frame(width: 9, height: 9)
                Text(group).font(.system(size: 15, weight: .bold, design: .rounded))
                Text("\(tabs.count) open").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save as folder", systemImage: "folder.badge.plus") {
                    state.ensureCollection(group)
                    for tab in tabs where tab.url.hasPrefix("http") {
                        state.saveCurrent(title: tab.title, url: tab.url, tags: [], note: "", collection: group)
                    }
                }.buttonStyle(.borderless).font(.caption).help("Keep this group's links in a folder")
            }
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

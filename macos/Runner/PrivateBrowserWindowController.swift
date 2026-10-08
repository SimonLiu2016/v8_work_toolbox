import Cocoa
import FlutterMacOS
import WebKit

/// 支持直接拖拽移动窗口的原生 Header 视图
class DraggableHeaderView: NSView {
  override var mouseDownCanMoveWindow: Bool {
    return true
  }
  
  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}

/// 隐私空间私密浏览器原生视图控制器与 WKWebView 容器
///
/// 核心特性：
/// 1. 禁用一切持久化历史记录（使用 nonPersistent websiteDataStore）
/// 2. 原生顶部可拖拽 Header 栏（避让 macOS 左上角红黄绿交通灯，支持按住拖拽移动）
/// 3. 精准视频检测脚本（严格过滤宽高、src 与播放状态，杜绝普通网页误报）
/// 4. 视频增强浮动工具栏原生锚定于底部
/// 5. 实时字幕 CATextLayer 原生渲染 Overlay
class PrivateBrowserWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
  
  static var shared: PrivateBrowserWindowController?
  
  var webView: WKWebView!
  var subtitleOverlay: CALayer?
  var subtitleTextLayer: CATextLayer?
  
  // 顶部原生导航与拖拽条
  var headerView: DraggableHeaderView!
  var titleLabel: NSTextField!
  var domainPill: NSView!
  var domainLabel: NSTextField!
  var backBtn: NSButton!
  var forwardBtn: NSButton!
  var reloadBtn: NSButton!
  
  // 底部原生视频增强浮动工具栏
  var floatingToolbar: NSVisualEffectView?
  var downloadBtn: NSButton?
  var cachePlayBtn: NSButton?
  var favoriteBtn: NSButton?
  var subtitleBtn: NSButton?
  
  // 代理通道回调
  var methodChannel: FlutterMethodChannel?
  
  // 当前检测到的视频信息
  var currentVideoSrc: String?
  var currentVideoTitle: String?
  var currentThumbnail: String?
  var currentVideoDuration: Double = 0
  var isCurrentAuthoritative = false
  var isVideoDetected = false
  
  // 字幕状态
  var subtitles: [[String: Any]] = []
  var showSubtitles = false
  
  convenience init(channel: FlutterMethodChannel?) {
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 1100, height: 750),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "隐私空间 · 私密浏览器"
    window.center()
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
    
    self.init(window: window)
    self.methodChannel = channel
    setupHeaderView()
    setupWebView()
    setupFloatingToolbar()
    setupSubtitleOverlay()
  }
  
  private func setupHeaderView() {
    guard let contentView = window?.contentView else { return }
    
    let header = DraggableHeaderView()
    header.wantsLayer = true
    header.layer?.backgroundColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0).cgColor
    contentView.addSubview(header)
    header.translatesAutoresizingMaskIntoConstraints = false
    
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: contentView.topAnchor),
      header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      header.heightAnchor.constraint(equalToConstant: 40)
    ])
    self.headerView = header
    
    // 导航控制按钮 (Back, Forward, Reload) - 位于交通灯（x=78）之后
    let navStack = NSStackView()
    navStack.orientation = .horizontal
    navStack.spacing = 2
    navStack.alignment = .centerY
    
    backBtn = makeNavButton(symbolName: "chevron.left", action: #selector(onNavBack))
    forwardBtn = makeNavButton(symbolName: "chevron.right", action: #selector(onNavForward))
    reloadBtn = makeNavButton(symbolName: "arrow.clockwise", action: #selector(onNavReload))
    
    navStack.addArrangedSubview(backBtn)
    navStack.addArrangedSubview(forwardBtn)
    navStack.addArrangedSubview(reloadBtn)
    
    header.addSubview(navStack)
    navStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      navStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 78),
      navStack.centerYAnchor.constraint(equalTo: header.centerYAnchor)
    ])
    
    // 域名 / 安全锁药丸胶囊
    let pill = NSView()
    pill.wantsLayer = true
    pill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    pill.layer?.cornerRadius = 11
    
    let lockIcon = NSImageView()
    if #available(macOS 11.0, *) {
      let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
      lockIcon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure")?.withSymbolConfiguration(config)
    }
    lockIcon.contentTintColor = NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.48, alpha: 1.0)
    
    domainLabel = NSTextField(labelWithString: "私密浏览")
    domainLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    domainLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
    domainLabel.lineBreakMode = .byTruncatingTail
    
    let pillStack = NSStackView(views: [lockIcon, domainLabel])
    pillStack.orientation = .horizontal
    pillStack.spacing = 4
    pillStack.alignment = .centerY
    
    pill.addSubview(pillStack)
    pillStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      pillStack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
      pillStack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
      pillStack.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
    ])
    
    header.addSubview(pill)
    pill.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      pill.leadingAnchor.constraint(equalTo: navStack.trailingAnchor, constant: 10),
      pill.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      pill.heightAnchor.constraint(equalToConstant: 22),
    ])
    self.domainPill = pill
    
    // 中间网页标题
    titleLabel = NSTextField(labelWithString: "隐私空间 · 私密浏览器")
    titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = NSColor.white
    titleLabel.alignment = .center
    titleLabel.lineBreakMode = .byTruncatingTail
    
    header.addSubview(titleLabel)
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
      titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: pill.trailingAnchor, constant: 10),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -20)
    ])
    
    // 底部分割线
    let divider = NSBox()
    divider.boxType = .separator
    header.addSubview(divider)
    divider.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      divider.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      divider.bottomAnchor.constraint(equalTo: header.bottomAnchor),
      divider.heightAnchor.constraint(equalToConstant: 1)
    ])
  }
  
  private func makeNavButton(symbolName: String, action: Selector) -> NSButton {
    let btn = NSButton(title: "", target: self, action: action)
    btn.bezelStyle = .regularSquare
    btn.isBordered = false
    btn.wantsLayer = true
    btn.layer?.cornerRadius = 4
    if #available(macOS 11.0, *) {
      let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
      btn.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }
    btn.contentTintColor = NSColor(white: 0.8, alpha: 1.0)
    btn.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      btn.widthAnchor.constraint(equalToConstant: 24),
      btn.heightAnchor.constraint(equalToConstant: 24)
    ])
    return btn
  }
  
  @objc private func onNavBack() {
    if webView.canGoBack { webView.goBack() }
  }
  @objc private func onNavForward() {
    if webView.canGoForward { webView.goForward() }
  }
  @objc private func onNavReload() {
    webView.reload()
  }
  
  private func setupWebView() {
    guard let contentView = window?.contentView else { return }
    
    let config = WKWebViewConfiguration()
    // 强制使用非持久化存储：绝不向磁盘写历史、Cookie 或 Session
    config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
    config.preferences.javaScriptCanOpenWindowsAutomatically = true
    
    // 注入视频检测与时间同步脚本
    let userContent = config.userContentController
    userContent.add(self, name: "videoDetector")
    userContent.add(self, name: "subtitleTime")
    
    let detectorScriptSource = """
    (function() {
      // 1. 优先提取官方权威媒体配置（如 PornHub flashvars 等），代表官方正片高清流，永不被片头广告遮蔽
      function getAuthoritativeVideo() {
        try {
          for (var k in window) {
            if (k.indexOf('flashvars') === 0 && window[k]) {
              var f = window[k];
              var title = f.video_title || '';
              var thumbnail = f.image_url || '';
              var duration = parseFloat(f.video_duration) || 0;
              var src = '';
              if (f.mediaDefinitions && Array.isArray(f.mediaDefinitions)) {
                var defs = f.mediaDefinitions;
                var bestDef = null;
                for (var i = 0; i < defs.length; i++) {
                  var d = defs[i];
                  if (!d.videoUrl || d.videoUrl.indexOf('http') !== 0) continue;
                  if (!bestDef) { bestDef = d; continue; }
                  var qCurrent = parseInt(d.quality) || 0;
                  var qBest = parseInt(bestDef.quality) || 0;
                  if (d.format === 'hls' && bestDef.format !== 'hls') {
                    bestDef = d;
                  } else if (d.format === bestDef.format && qCurrent > qBest) {
                    bestDef = d;
                  } else if (bestDef.format !== 'hls' && qCurrent > qBest) {
                    bestDef = d;
                  }
                }
                if (bestDef && bestDef.videoUrl) {
                  src = bestDef.videoUrl;
                }
              }
              if (src) {
                return {
                  title: title,
                  videoSrc: src,
                  thumbnail: thumbnail,
                  duration: duration,
                  isAuthoritative: true
                };
              }
            }
          }
        } catch (_) {}
        return null;
      }

      // 2. 识别是否为广告视频元素或广告流 URL
      function isAdVideo(v) {
        if (!v) return false;
        var src = v.currentSrc || v.src || '';
        if (!src) {
          var s = v.querySelector('source');
          if (s) src = s.src || '';
        }
        var lowerSrc = (src || '').toLowerCase();
        var adKeywords = [
          'trafficjunky', 'doubleclick', 'googlesyndication', 'adzerk',
          'scorecardresearch', 'spotx', '/ads/', '/ad/', '_ad.', '-ad.',
          'preroll', 'vast', 'vmap', 'delivery', 'adcontent', 'ad_video',
          'advertisement', 'adnxs', 'exponential', 'adservice', 'commercial'
        ];
        for (var i = 0; i < adKeywords.length; i++) {
          if (lowerSrc.indexOf(adKeywords[i]) !== -1) return true;
        }

        var el = v;
        var depth = 0;
        while (el && depth < 6) {
          var cls = (el.className || '').toString().toLowerCase();
          var id = (el.id || '').toString().toLowerCase();
          if (cls.indexOf('ad-container') !== -1 ||
              cls.indexOf('video-ads') !== -1 ||
              cls.indexOf('preroll') !== -1 ||
              cls.indexOf('ad-showing') !== -1 ||
              cls.indexOf('ima-ad') !== -1 ||
              cls.indexOf('mgp_preroll') !== -1 ||
              cls.indexOf('vjs-ad') !== -1 ||
              id.indexOf('ad-') !== -1 ||
              id.indexOf('preroll') !== -1) {
            return true;
          }
          el = el.parentElement;
          depth++;
        }
        return false;
      }

      // 3. 校验普通 DOM video 元素有效性
      function isValidVideo(v) {
        if (!v) return false;
        if (isAdVideo(v)) return false;
        
        var src = v.currentSrc || v.src || '';
        if (!src) {
          var sourceTag = v.querySelector('source');
          if (sourceTag) src = sourceTag.src || '';
        }
        var hasValidSrc = src && src.length > 5 && src !== window.location.href && !src.startsWith('javascript:');
        var hasValidDuration = v.duration && !isNaN(v.duration) && v.duration > 2;
        if (!hasValidSrc && !hasValidDuration) return false;
        
        var rect = v.getBoundingClientRect();
        var style = window.getComputedStyle(v);
        if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
        if (rect.width < 100 && rect.height < 60 && !hasValidDuration) return false;
        
        return true;
      }

      function notifyVideo(v, isAuth) {
        var auth = getAuthoritativeVideo();
        if (auth && auth.videoSrc) {
          var ogTitle = document.querySelector('meta[property="og:title"]');
          var finalTitle = auth.title || (ogTitle ? ogTitle.content : '') || document.title || '';
          var ogImage = document.querySelector('meta[property="og:image"]');
          var finalThumb = auth.thumbnail || (ogImage ? ogImage.content : '') || '';
          window.webkit.messageHandlers.videoDetector.postMessage({
            event: 'detected',
            url: window.location.href,
            title: finalTitle,
            videoSrc: auth.videoSrc,
            thumbnail: finalThumb,
            duration: auth.duration || 0,
            isAuthoritative: true
          });
          return;
        }

        if (!v || !isValidVideo(v)) return;
        var src = v.currentSrc || v.src || '';
        if (!src) {
          var sourceTag = v.querySelector('source');
          if (sourceTag) src = sourceTag.src || '';
        }
        var title = '';
        var ogTitle = document.querySelector('meta[property="og:title"]');
        if (ogTitle && ogTitle.content) title = ogTitle.content;
        if (!title) title = document.title || '';

        var thumbnail = '';
        var ogImage = document.querySelector('meta[property="og:image"]');
        if (ogImage && ogImage.content) thumbnail = ogImage.content;
        if (!thumbnail && v.poster) thumbnail = v.poster;

        window.webkit.messageHandlers.videoDetector.postMessage({
          event: 'detected',
          url: window.location.href,
          title: title,
          videoSrc: src,
          thumbnail: thumbnail,
          duration: v.duration || 0,
          isAuthoritative: false
        });
      }
      
      function scanVideos() {
        var auth = getAuthoritativeVideo();
        if (auth && auth.videoSrc) {
          notifyVideo(null, true);
          return;
        }

        var videos = document.querySelectorAll('video');
        var bestVideo = null;
        var highestScore = -1;
        for (var i = 0; i < videos.length; i++) {
          var vid = videos[i];
          if (isAdVideo(vid)) continue;
          if (!isValidVideo(vid)) continue;
          var rect = vid.getBoundingClientRect();
          var dur = vid.duration || 0;
          var area = (rect.width || 0) * (rect.height || 0);
          var score = area;
          if (dur > 60) score += 1000000;
          if (dur > 300) score += 5000000;
          if (score > highestScore) {
            highestScore = score;
            bestVideo = vid;
          }
        }
        if (bestVideo) {
          notifyVideo(bestVideo, false);
        }
      }
      
      if (document.readyState === 'complete') {
        scanVideos();
      } else {
        window.addEventListener('load', scanVideos);
      }
      
      var debounceTimer = null;
      var observer = new MutationObserver(function() {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(scanVideos, 600);
      });
      observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
      
      var syncTimer = null;
      document.addEventListener('play', function(e) {
        if (e.target && e.target.tagName === 'VIDEO') {
          var targetVideo = e.target;
          if (!isAdVideo(targetVideo) && isValidVideo(targetVideo)) {
            notifyVideo(targetVideo, false);
          }
          if (syncTimer) clearInterval(syncTimer);
          syncTimer = setInterval(function() {
            if (!targetVideo.paused) {
              window.webkit.messageHandlers.subtitleTime.postMessage({
                time: targetVideo.currentTime,
                duration: targetVideo.duration
              });
            }
          }, 250);
        }
      }, true);

      document.addEventListener('durationchange', function(e) {
        if (e.target && e.target.tagName === 'VIDEO') {
          if (!isAdVideo(e.target) && (e.target.duration || 0) > 45) {
            scanVideos();
          }
        }
      }, true);

      document.addEventListener('ended', function(e) {
        if (e.target && e.target.tagName === 'VIDEO') {
          setTimeout(scanVideos, 400);
        }
      }, true);
      
      document.addEventListener('pause', function(e) {
        if (e.target && e.target.tagName === 'VIDEO') {
          if (syncTimer) { clearInterval(syncTimer); syncTimer = null; }
        }
      }, true);
    })();
    """
    
    let userScript = WKUserScript(
      source: detectorScriptSource,
      injectionTime: .atDocumentEnd,
      forMainFrameOnly: false
    )
    userContent.addUserScript(userScript)
    
    webView = WKWebView(frame: .zero, configuration: config)
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.navigationDelegate = self
    webView.uiDelegate = self
    contentView.addSubview(webView)
    
    // 严密锚定在 headerView 下方，绝不与顶部红黄绿按钮重叠
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])
  }
  
  private func setupFloatingToolbar() {
    guard let contentView = window?.contentView else { return }
    
    let toolbar = NSVisualEffectView()
    toolbar.material = .hudWindow
    toolbar.blendingMode = .withinWindow
    toolbar.state = .active
    toolbar.wantsLayer = true
    toolbar.layer?.cornerRadius = 20
    toolbar.layer?.masksToBounds = true
    toolbar.isHidden = true // 初始隐藏，检测到视频后再平滑浮现
    
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.spacing = 10
    stack.alignment = .centerY
    stack.distribution = .gravityAreas
    
    downloadBtn = makeToolbarButton(title: "📥 下载", action: #selector(onDownloadClicked))
    cachePlayBtn = makeToolbarButton(title: "💾 缓存播放", action: #selector(onCachePlayClicked))
    favoriteBtn = makeToolbarButton(title: "★ 收藏", action: #selector(onFavoriteClicked))
    subtitleBtn = makeToolbarButton(title: "CC 字幕", action: #selector(onSubtitleClicked))
    
    stack.addArrangedSubview(downloadBtn!)
    stack.addArrangedSubview(cachePlayBtn!)
    stack.addArrangedSubview(favoriteBtn!)
    stack.addArrangedSubview(subtitleBtn!)
    
    toolbar.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
      stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -6),
    ])
    
    contentView.addSubview(toolbar)
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      toolbar.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      toolbar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
      toolbar.heightAnchor.constraint(equalToConstant: 42),
    ])
    
    self.floatingToolbar = toolbar
  }
  
  private func makeToolbarButton(title: String, action: Selector) -> NSButton {
    let btn = NSButton(title: title, target: self, action: action)
    btn.bezelStyle = .roundRect
    btn.isBordered = false
    btn.wantsLayer = true
    btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    btn.layer?.cornerRadius = 14
    btn.contentTintColor = .white
    btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    return btn
  }

  func updateDownloadStatus(progress: Double, status: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if status == "completed" {
        self.downloadBtn?.title = "✓ 已完成"
        self.downloadBtn?.layer?.backgroundColor = NSColor(calibratedRed: 0.15, green: 0.55, blue: 0.25, alpha: 0.85).cgColor
      } else if status == "downloading" {
        let pct = progress <= 1.0 ? Int(progress * 100) : Int(progress)
        self.downloadBtn?.title = "📥 \(pct)%"
        self.downloadBtn?.layer?.backgroundColor = NSColor(calibratedRed: 0.2, green: 0.45, blue: 0.75, alpha: 0.85).cgColor
      } else if status == "failed" {
        self.downloadBtn?.title = "✗ 下载失败"
        self.downloadBtn?.layer?.backgroundColor = NSColor(calibratedRed: 0.75, green: 0.2, blue: 0.2, alpha: 0.85).cgColor
      } else {
        self.downloadBtn?.title = "📥 下载"
        self.downloadBtn?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
      }
    }
  }

  func updateFavoriteStatus(isFavorite: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if isFavorite {
        self.favoriteBtn?.title = "✓ 已收藏"
        self.favoriteBtn?.layer?.backgroundColor = NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.1, alpha: 0.85).cgColor
      } else {
        self.favoriteBtn?.title = "★ 收藏"
        self.favoriteBtn?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
      }
    }
  }
  
  private func setupSubtitleOverlay() {
    guard let contentView = window?.contentView else { return }
    
    let overlay = CALayer()
    overlay.frame = contentView.bounds
    overlay.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    
    let textLayer = CATextLayer()
    textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    textLayer.fontSize = 20
    textLayer.foregroundColor = NSColor.white.cgColor
    textLayer.alignmentMode = .center
    textLayer.isWrapped = true
    textLayer.shadowColor = NSColor.black.cgColor
    textLayer.shadowOpacity = 0.9
    textLayer.shadowRadius = 4
    textLayer.shadowOffset = CGSize(width: 0, height: -1)
    textLayer.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
    textLayer.cornerRadius = 6
    textLayer.isHidden = true
    
    overlay.addSublayer(textLayer)
    contentView.wantsLayer = true
    contentView.layer?.addSublayer(overlay)
    
    self.subtitleOverlay = overlay
    self.subtitleTextLayer = textLayer
  }
  
  // MARK: - WKScriptMessageHandler
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    if message.name == "videoDetector" {
      guard let dict = message.body as? [String: Any] else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        let isAuth = dict["isAuthoritative"] as? Bool ?? false
        let duration = dict["duration"] as? Double ?? 0
        
        // 若当前已经确立为权威正片，且新消息不是权威源，则拒绝被覆盖
        if self.isCurrentAuthoritative && !isAuth {
          return
        }
        // 若当前已有长视频（> 60s），新传入的如果是短于 45s 的非权威视频（通常是广告），拒绝被覆盖
        if !isAuth && self.currentVideoDuration > 60 && duration > 0 && duration < 45 {
          return
        }
        
        if isAuth {
          self.isCurrentAuthoritative = true
        }
        self.currentVideoDuration = duration
        self.isVideoDetected = true
        self.currentVideoSrc = dict["videoSrc"] as? String
        self.currentVideoTitle = dict["title"] as? String
        self.currentThumbnail = dict["thumbnail"] as? String
        
        // 浮现增强工具栏
        self.floatingToolbar?.isHidden = false
        
        // 回传给 Flutter 端做状态同步
        self.methodChannel?.invokeMethod("onVideoDetected", arguments: [
          "url": self.webView.url?.absoluteString ?? "",
          "title": self.currentVideoTitle ?? "",
          "videoSrc": self.currentVideoSrc ?? "",
          "thumbnail": self.currentThumbnail ?? ""
        ])
      }
    } else if message.name == "subtitleTime" {
      guard let dict = message.body as? [String: Any],
            let timeSec = dict["time"] as? Double else { return }
      
      let timeMs = Int(timeSec * 1000)
      DispatchQueue.main.async { [weak self] in
        self?.renderSubtitle(atTimeMs: timeMs)
      }
    }
  }
  
  // 查找对应字幕段并渲染
  private func renderSubtitle(atTimeMs timeMs: Int) {
    guard showSubtitles, let textLayer = subtitleTextLayer, let bounds = window?.contentView?.bounds else {
      subtitleTextLayer?.isHidden = true
      return
    }
    
    var matchedText = ""
    for seg in subtitles {
      if let startMs = seg["startMs"] as? Int,
         let endMs = seg["endMs"] as? Int,
         let text = seg["text"] as? String {
        if timeMs >= startMs && timeMs <= endMs {
          matchedText = text
          break
        }
      }
    }
    
    if matchedText.isEmpty {
      textLayer.isHidden = true
    } else {
      textLayer.string = matchedText
      let w: CGFloat = min(750, bounds.width - 80)
      let h: CGFloat = 50
      textLayer.frame = CGRect(x: (bounds.width - w) / 2, y: 70, width: w, height: h)
      textLayer.isHidden = false
    }
  }
  
  // MARK: - Actions
  @objc private func onDownloadClicked() {
    let url = webView.url?.absoluteString ?? ""
    let title = currentVideoTitle ?? webView.title ?? ""
    methodChannel?.invokeMethod("triggerDownload", arguments: [
      "url": url,
      "title": title,
      "videoSrc": currentVideoSrc ?? "",
      "thumbnail": currentThumbnail ?? ""
    ])
  }
  
  @objc private func onCachePlayClicked() {
    let url = webView.url?.absoluteString ?? ""
    let title = currentVideoTitle ?? webView.title ?? ""
    methodChannel?.invokeMethod("triggerCachePlay", arguments: [
      "url": url,
      "title": title,
      "videoSrc": currentVideoSrc ?? "",
      "thumbnail": currentThumbnail ?? ""
    ])
  }
  
  @objc private func onFavoriteClicked() {
    let url = webView.url?.absoluteString ?? ""
    let title = currentVideoTitle ?? webView.title ?? ""
    methodChannel?.invokeMethod("triggerFavorite", arguments: [
      "url": url,
      "title": title,
      "videoSrc": currentVideoSrc ?? "",
      "thumbnail": currentThumbnail ?? ""
    ])
  }
  
  @objc private func onSubtitleClicked() {
    let url = webView.url?.absoluteString ?? ""
    methodChannel?.invokeMethod("openSubtitlePanel", arguments: [
      "url": url
    ])
  }
  
  // MARK: - WKNavigationDelegate
  private func updateHeader(url: URL?, title: String?) {
    if let title = title, !title.isEmpty {
      titleLabel?.stringValue = title
      window?.title = "私密浏览器 · \(title)"
    } else {
      titleLabel?.stringValue = "隐私空间 · 私密浏览器"
      window?.title = "隐私空间 · 私密浏览器"
    }
    
    if let host = url?.host, !host.isEmpty {
      domainLabel?.stringValue = host
      domainPill?.isHidden = false
    } else {
      domainLabel?.stringValue = "私密浏览"
    }
    
    backBtn?.isEnabled = webView.canGoBack
    forwardBtn?.isEnabled = webView.canGoForward
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    isVideoDetected = false
    isCurrentAuthoritative = false
    currentVideoDuration = 0
    currentVideoSrc = nil
    currentVideoTitle = nil
    currentThumbnail = nil
    floatingToolbar?.isHidden = true
    subtitleTextLayer?.isHidden = true
    showSubtitles = false
    updateHeader(url: webView.url, title: "加载中...")
    methodChannel?.invokeMethod("onVideoReset", arguments: nil)
  }
  
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    updateHeader(url: webView.url, title: webView.title)
    methodChannel?.invokeMethod("onNavigationFinished", arguments: [
      "url": webView.url?.absoluteString ?? "",
      "title": webView.title ?? ""
    ])
  }
}

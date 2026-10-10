// ===== Tema oscuro (sigue GTK / color-scheme del sistema) =====
user_pref("ui.systemUsesDarkTheme", 1);
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.theme.content-theme", 0);
user_pref("layout.css.prefers-color-scheme.content-override", 0);

// ===== GPU: RTX 3050, Wayland, WebRender + VA-API por NVDEC =====
user_pref("gfx.webrender.all", true);
user_pref("gfx.canvas.accelerated", true);
user_pref("gfx.canvas.accelerated.cache-items", 32768);
user_pref("gfx.canvas.accelerated.cache-size", 4096);
user_pref("gfx.content.skia-font-cache-size", 80);
user_pref("widget.dmabuf.force-enabled", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.rdd-ffmpeg.enabled", true);
user_pref("media.rdd-process.enabled", true);
user_pref("media.av1.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);

// ===== CPU/RAM: Ryzen 5 5600 (12 hilos), 31 GB =====
user_pref("dom.ipc.processCount", 12);
user_pref("dom.ipc.processCount.webIsolated", 12);
user_pref("browser.preferences.defaultPerformanceSettings.enabled", false);
user_pref("browser.cache.memory.capacity", 1048576);
user_pref("browser.cache.memory.max_entry_size", 20480);
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 4194304);
user_pref("browser.cache.disk.smart_size.enabled", false);
user_pref("browser.sessionhistory.max_total_viewers", 8);
user_pref("image.cache.size", 10485760);
user_pref("image.mem.decode_bytes_at_a_time", 65536);
user_pref("browser.sessionstore.interval", 60000);

// ===== Red: más conexiones y DNS en caché =====
user_pref("network.http.max-connections", 1800);
user_pref("network.http.max-persistent-connections-per-server", 10);
user_pref("network.http.max-urgent-start-excessive-connections-per-host", 5);
user_pref("network.http.pacing.requests.enabled", false);
user_pref("network.dnsCacheEntries", 10000);
user_pref("network.dnsCacheExpiration", 3600);
user_pref("network.ssl_tokens_cache_capacity", 10240);
user_pref("network.http.speculative-parallel-limit", 12);
user_pref("network.buffer.cache.size", 262144);
user_pref("network.buffer.cache.count", 128);

// ===== Descargas =====
user_pref("browser.download.useDownloadDir", true);
user_pref("browser.download.manager.addToRecentDocs", false);
user_pref("browser.download.alwaysOpenPanel", false);

// ===== Fluidez =====
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.msdPhysics.enabled", true);
user_pref("apz.overscroll.enabled", true);

// ===== Telemetría y ruido de depuración fuera =====
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);

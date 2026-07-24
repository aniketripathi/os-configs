// Disable Normandy / Firefox Studies (default: true)
user_pref("app.shield.optoutstudies.enabled", false);

// Disable Normandy remote service (default: true)
user_pref("app.normandy.enabled", false);

// Disable Normandy first run check (default: true)
user_pref("app.normandy.first_run", false);

// Disable uploading browser health reports to Mozilla (default: true)
user_pref("datareporting.healthreport.uploadEnabled", false);

// Accept data submission policy version 2 (default: 0)
user_pref("datareporting.policy.dataSubmissionPolicyAcceptedVersion", 2);

// Disable Firefox telemetry engine (default: true)
user_pref("toolkit.telemetry.enabled", false);

// Disable telemetry archiving to local disk (default: true)
user_pref("toolkit.telemetry.archive.enabled", false);

// Disable Pocket integration in toolbar and new tab (default: true)
user_pref("extensions.pocket.enabled", false);

// Increase font rendering cache to 20MB for faster text loading (default: 5MB)
user_pref("gfx.content.skia-font-cache-size", 20);

// Increase Canvas2D hardware acceleration cache to 512MB for complex graphics (default: 256MB)
user_pref("gfx.canvas.accelerated.cache-size", 512);

// Promote JavaScript to Baseline JIT compiler after running a function 50 times (default: 100)
user_pref("javascript.options.baselinejit.threshold", 50);

// Buffer up to 3.6MB (3,600KB) of video ahead of current playback (default: 1,000KB)
user_pref("media.cache_readahead_limit", 3600);

// Resume video buffering when buffer drops below 1.8MB (1,800KB) (default: 500KB)
user_pref("media.cache_resume_threshold", 1800);

// Decode images in chunks of 32KB (32,768 bytes) for smoother rendering (default: 16,384 / 16KB)
user_pref("image.mem.decode_bytes_at_a_time", 32768);

// Increase networking cache size to 64KB (65,535 bytes) for faster data streams (default: 32,768 / 32KB)
user_pref("network.buffer.cache.size", 65535);

// Set network cache buffer count to 48 chunks for optimized throughput (default: 24)
user_pref("network.buffer.cache.count", 48);

// Increase maximum simultaneous network connections to 512 (default: 256)
user_pref("network.http.max-connections", 512);

// Increase maximum persistent connections per server to 10 for parallel asset loading (default: 6)
user_pref("network.http.max-persistent-connections-per-server", 10);

// Increase maximum parallel connections per server for downloads to 15 (default: 8)
user_pref("network.http.max-connections-per-server", 15);

// Limit urgent excessive connections per host to 5 (default: 3)
user_pref("network.http.max-urgent-start-excessive-connections-per-host", 5);

// Set connection request start delay limit to 5 seconds to prevent hanging (default: 10)
user_pref("network.http.request.max-start-delay", 5);

// Keep resolved DNS queries cached for 600 seconds (10 minutes) (default: 60)
user_pref("network.dnsCacheExpiration", 600);

// Disable pre-downloading next pages in search results to save bandwidth (default: true)
user_pref("network.prefetch-next", false);

// Disable speculative DNS pre-fetching to prevent background lookups (default: false)
user_pref("network.dns.disablePrefetch", true);

// Set speculative pre-connection limit to 0 to stop pre-loading links (default: 6)
user_pref("network.http.speculative-parallel-limit", 0);

// Disable sending click-tracking telemetry pings when clicking links (default: true)
user_pref("browser.send_pings", false);

// Save session data every 600,000ms (10 minutes) to protect SSD & battery (default: 15,000ms / 15s)
user_pref("browser.sessionstore.interval", 600000);

// Only load background tabs when they are clicked to save RAM on startup (default: true)
user_pref("browser.sessionstore.restore_on_demand", true);

// Enable hardware GPU decoding for video playback to reduce CPU load and save power (default: true)
user_pref("media.hardware-video-decoding.enabled", true);

// Enable support for custom userChrome.css/userContent.css stylesheets (default: false)
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Enable the compact density option in customization menu (default: false)
user_pref("browser.compactmode.show", true);

// Hide the Firefox View button on the tab bar (default: true)
user_pref("browser.tabs.firefox-view", false);

// Disable the "Here be dragons!" warning page when opening about:config (default: true)
user_pref("browser.aboutConfig.showWarning", false);

// Disable default browser check on startup (default: true)
user_pref("browser.shell.checkDefaultBrowser", false);

// Hide sponsored content on the new tab page (default: true)
user_pref("browser.newtabpage.activity-stream.showSponsored", false);

// Hide sponsored shortcuts on the new tab page (default: true)
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

// Disable recommendation stories on the new tab page (default: true)
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);

// Disable top sites section on the new tab page (default: true)
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);

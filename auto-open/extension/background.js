const routes = new Map([
  ["www.learningmall.cn", "xjtlu-access-learning-mall"],
  ["core.xjtlu.edu.cn", "xjtlu-access-learning-mall"],
  ["uim.xjtlu.edu.cn", "xjtlu-access-learning-mall"],
  ["mail.xjtlu.edu.cn", "xjtlu-access-webmail"],
  ["www.xjtlu.edu.cn", "xjtlu-access-main-site"]
]);

const redirectedTabs = new Set();

async function isEnabled() {
  const settings = await chrome.storage.local.get({ enabled: true });
  return settings.enabled === true;
}

async function updateBadge() {
  const enabled = await isEnabled();
  await chrome.action.setBadgeText({ text: enabled ? "ON" : "OFF" });
  await chrome.action.setBadgeBackgroundColor({ color: enabled ? "#1f7a4d" : "#777777" });
  await chrome.action.setTitle({ title: enabled ? "XJTLU auto-open: ON (click to pause)" : "XJTLU auto-open: OFF (click to enable)" });
}

function getProtocolForUrl(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return null;
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return null;
  }

  return routes.get(url.hostname.toLowerCase()) || null;
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.set({ enabled: true });
  updateBadge();
});

chrome.runtime.onStartup.addListener(updateBadge);

chrome.action.onClicked.addListener(async () => {
  const enabled = await isEnabled();
  await chrome.storage.local.set({ enabled: !enabled });
  await updateBadge();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  redirectedTabs.delete(tabId);
});

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  if (changeInfo.status !== "loading") {
    return;
  }

  if (!(await isEnabled())) {
    return;
  }

  const protocol = getProtocolForUrl(changeInfo.url || tab.url || "");
  if (protocol === null || redirectedTabs.has(tabId)) {
    return;
  }

  redirectedTabs.add(tabId);
  try {
    // Replace the school navigation with a fixed local protocol.
    await chrome.tabs.update(tabId, { url: `${protocol}://open` });
  } catch (error) {
    redirectedTabs.delete(tabId);
    console.warn("XJTLU auto-open could not redirect this tab", error);
  }
});

updateBadge();

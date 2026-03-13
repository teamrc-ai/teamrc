import { execFileSync } from "node:child_process";

export function buildInviteUrl(relayUrl: string, inviteCode: string): string {
  const base = relayUrl.replace(/\/$/, "");
  return `${base}/invite/${encodeURIComponent(inviteCode)}`;
}

export function hasSameOrigin(url: string, baseUrl: string): boolean {
  try {
    return new URL(url).origin === new URL(baseUrl).origin;
  } catch {
    return false;
  }
}

export function openBrowser(url: string): boolean {
  if (process.env.NO_BROWSER === "1") return false;
  try {
    if (process.platform === "darwin") {
      execFileSync("open", [url], { stdio: "ignore" });
      return true;
    }

    if (process.platform === "win32") {
      execFileSync("cmd", ["/c", "start", "", url], {
        stdio: "ignore",
        windowsHide: true,
      });
      return true;
    }

    execFileSync("xdg-open", [url], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

export function openBrowserIfSameOrigin(url: string, baseUrl: string): boolean {
  if (!hasSameOrigin(url, baseUrl)) return false;
  return openBrowser(url);
}

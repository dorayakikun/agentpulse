import { test, expect } from "@playwright/test";
import type { Task } from "../../src/types/task";

type InvokeConfig = {
  delayMs?: number;
  getTasksError?: string;
  removeTaskError?: string;
};

const seedTasks = async (page, tasks: Task[]) => {
  await page.evaluate((nextTasks) => {
    (window as any).__TAURI_MOCK__.setTasks(nextTasks);
  }, tasks);
};

const setInvokeConfig = async (page, config: InvokeConfig) => {
  await page.waitForFunction(() => Boolean((window as any).__TAURI_MOCK__));
  await page.evaluate((nextConfig) => {
    (window as any).__TAURI_MOCK__.setInvokeConfig(nextConfig);
  }, config);
};

const clearInvokeConfig = async (page) => {
  await page.waitForFunction(() => Boolean((window as any).__TAURI_MOCK__));
  await page.evaluate(() => {
    (window as any).__TAURI_MOCK__.clearInvokeConfig();
  });
};

test("renders empty state on startup", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("h1.header-title")).toHaveText("AI Agent Status");
  await expect(page.locator(".empty-title")).toBeVisible();
});

test("shows loading indicator while fetching", async ({ page }) => {
  await page.addInitScript(() => {
    (window as any).__TAURI_E2E_CONFIG__ = { delayMs: 800 };
  });
  await page.goto("/");
  await expect(page.locator(".loading")).toBeVisible();
  await expect(page.locator(".empty-title")).toBeVisible();
});

test("shows error banner and recovers on retry", async ({ page }) => {
  await page.addInitScript(() => {
    (window as any).__TAURI_E2E_CONFIG__ = { getTasksError: "Mock failure" };
  });
  await page.goto("/");
  await expect(page.locator(".error-banner")).toBeVisible();
  await expect(page.locator(".error-message")).toHaveText("Mock failure");

  await clearInvokeConfig(page);
  await page.locator("button.error-action").click();
  await expect(page.locator(".error-banner")).toBeHidden();
  await expect(page.locator(".empty-title")).toBeVisible();
});

test("updates tasks when mock bridge emits an update", async ({ page }) => {
  await page.goto("/");

  const now = Math.floor(Date.now() / 1000);
  await seedTasks(page, [
    {
      session_id: "test-session",
      source: "codex",
      status: "running",
      current_tool: "Read",
      description: "Reading files",
      project_path: "/tmp/project",
      started_at: now,
      last_updated: now,
    },
  ]);

  await expect(page.locator(".task-item")).toHaveCount(1);
  await expect(page.locator(".task-description")).toContainText("Reading files");
});

test("shows dismiss button only for completed or error", async ({ page }) => {
  await page.goto("/");
  const now = Math.floor(Date.now() / 1000);
  await seedTasks(page, [
    {
      session_id: "running-task",
      source: "codex",
      status: "running",
      description: "Running job",
      project_path: "/tmp/running",
      started_at: now,
      last_updated: now,
    },
    {
      session_id: "done-task",
      source: "claude_code",
      status: "completed",
      description: "Done job",
      project_path: "/tmp/done",
      started_at: now,
      last_updated: now,
    },
  ]);

  await expect(page.locator(".dismiss-btn")).toHaveCount(1);
  await page.locator(".dismiss-btn").click();
  await expect(page.locator(".task-item")).toHaveCount(1);
  await expect(page.locator(".project-name")).toContainText("running");
});

test("sorts tasks by status priority then recency", async ({ page }) => {
  await page.goto("/");
  const now = Math.floor(Date.now() / 1000);
  await seedTasks(page, [
    {
      session_id: "error-task",
      source: "codex",
      status: "error",
      description: "Error job",
      project_path: "/tmp/error",
      started_at: now - 10,
      last_updated: now - 10,
    },
    {
      session_id: "waiting-task",
      source: "codex",
      status: "waiting_for_input",
      description: "Waiting job",
      project_path: "/tmp/waiting",
      started_at: now - 5,
      last_updated: now - 5,
    },
    {
      session_id: "running-newer",
      source: "codex",
      status: "running",
      description: "Running newer",
      project_path: "/tmp/running-newer",
      started_at: now,
      last_updated: now,
    },
    {
      session_id: "running-older",
      source: "codex",
      status: "running",
      description: "Running older",
      project_path: "/tmp/running-older",
      started_at: now - 20,
      last_updated: now - 20,
    },
    {
      session_id: "done-task",
      source: "codex",
      status: "completed",
      description: "Done job",
      project_path: "/tmp/done",
      started_at: now - 15,
      last_updated: now - 15,
    },
  ]);

  const names = page.locator(".project-name");
  await expect(names).toHaveCount(5);
  await expect(names.nth(0)).toContainText("running-newer");
  await expect(names.nth(1)).toContainText("running-older");
  await expect(names.nth(2)).toContainText("waiting");
  await expect(names.nth(3)).toContainText("done");
  await expect(names.nth(4)).toContainText("error");
});

test("renders status badges for each state", async ({ page }) => {
  await page.goto("/");
  const now = Math.floor(Date.now() / 1000);
  await seedTasks(page, [
    {
      session_id: "running-task",
      source: "codex",
      status: "running",
      description: "Running job",
      project_path: "/tmp/running",
      started_at: now,
      last_updated: now,
    },
    {
      session_id: "waiting-task",
      source: "codex",
      status: "waiting_for_input",
      description: "Waiting job",
      project_path: "/tmp/waiting",
      started_at: now,
      last_updated: now,
    },
    {
      session_id: "done-task",
      source: "codex",
      status: "completed",
      description: "Done job",
      project_path: "/tmp/done",
      started_at: now,
      last_updated: now,
    },
    {
      session_id: "error-task",
      source: "codex",
      status: "error",
      description: "Error job",
      project_path: "/tmp/error",
      started_at: now,
      last_updated: now,
    },
  ]);

  const badges = page.locator(".status-badge");
  await expect(badges).toHaveCount(4);
  await expect(badges.nth(0)).toContainText("Running");
  await expect(badges.nth(1)).toContainText("Waiting");
  await expect(badges.nth(2)).toContainText("Done");
  await expect(badges.nth(3)).toContainText("Error");
});

test("truncates long descriptions", async ({ page }) => {
  await page.goto("/");
  const now = Math.floor(Date.now() / 1000);
  const longText = "a".repeat(80);
  await seedTasks(page, [
    {
      session_id: "long-desc",
      source: "codex",
      status: "running",
      description: longText,
      project_path: "/tmp/long",
      started_at: now,
      last_updated: now,
    },
  ]);

  const description = page.locator(".task-description");
  await expect(description).toBeVisible();
  const text = await description.textContent();
  expect(text).not.toBeNull();
  if (text) {
    expect(text.length).toBeLessThanOrEqual(60);
    expect(text.endsWith("…")).toBeTruthy();
  }
});

test("shows project name extracted from path", async ({ page }) => {
  await page.goto("/");
  const now = Math.floor(Date.now() / 1000);
  await seedTasks(page, [
    {
      session_id: "project-name",
      source: "codex",
      status: "running",
      description: "Project check",
      project_path: "/Users/test-user/projects/sample-app",
      started_at: now,
      last_updated: now,
    },
  ]);

  await expect(page.locator(".project-name")).toHaveText("sample-app");
});

test("formats relative time labels", async ({ page }) => {
  const fixedNowMs = 1_700_000_000_000;
  await page.addInitScript((now) => {
    Date.now = () => now;
  }, fixedNowMs);

  await page.goto("/");
  const fixedNowSec = Math.floor(fixedNowMs / 1000);
  await seedTasks(page, [
    {
      session_id: "just-now",
      source: "codex",
      status: "running",
      description: "Just now",
      project_path: "/tmp/just-now",
      started_at: fixedNowSec,
      last_updated: fixedNowSec,
    },
    {
      session_id: "minutes",
      source: "codex",
      status: "running",
      description: "Minutes",
      project_path: "/tmp/minutes",
      started_at: fixedNowSec - 120,
      last_updated: fixedNowSec - 120,
    },
    {
      session_id: "hours",
      source: "codex",
      status: "running",
      description: "Hours",
      project_path: "/tmp/hours",
      started_at: fixedNowSec - 7200,
      last_updated: fixedNowSec - 7200,
    },
    {
      session_id: "days",
      source: "codex",
      status: "running",
      description: "Days",
      project_path: "/tmp/days",
      started_at: fixedNowSec - 172800,
      last_updated: fixedNowSec - 172800,
    },
  ]);

  const times = page.locator(".time-ago");
  await expect(times.nth(0)).toHaveText("just now");
  await expect(times.nth(1)).toHaveText("2 mins ago");
  await expect(times.nth(2)).toHaveText("2 hours ago");
  await expect(times.nth(3)).toHaveText("2 days ago");
});

test("shows source labels for Claude Code and Codex", async ({ page }) => {
  await page.goto("/");
  const now = Math.floor(Date.now() / 1000);
  await seedTasks(page, [
    {
      session_id: "claude",
      source: "claude_code",
      status: "running",
      description: "Claude task",
      project_path: "/tmp/claude",
      started_at: now,
      last_updated: now,
    },
    {
      session_id: "codex",
      source: "codex",
      status: "running",
      description: "Codex task",
      project_path: "/tmp/codex",
      started_at: now,
      last_updated: now - 10,
    },
  ]);

  const icons = page.locator(".source-icon");
  await expect(icons).toHaveCount(2);
  await expect(icons.nth(0)).toHaveText("CC");
  await expect(icons.nth(0)).toHaveAttribute("title", "Claude Code");
  await expect(icons.nth(1)).toHaveText("CX");
  await expect(icons.nth(1)).toHaveAttribute("title", "Codex");
});

test("toggles current tool display", async ({ page }) => {
  await page.goto("/");
  const now = Math.floor(Date.now() / 1000);
  await seedTasks(page, [
    {
      session_id: "with-tool",
      source: "codex",
      status: "running",
      current_tool: "Write",
      description: "With tool",
      project_path: "/tmp/with-tool",
      started_at: now,
      last_updated: now,
    },
    {
      session_id: "without-tool",
      source: "codex",
      status: "running",
      description: "Without tool",
      project_path: "/tmp/without-tool",
      started_at: now,
      last_updated: now,
    },
  ]);

  await expect(page.locator(".tool-name")).toHaveCount(1);
  await expect(page.locator(".tool-name")).toHaveText("Write");
});

test("dismisses error banner via close button", async ({ page }) => {
  await page.addInitScript(() => {
    (window as any).__TAURI_E2E_CONFIG__ = { getTasksError: "Mock failure" };
  });
  await page.goto("/");
  await expect(page.locator(".error-banner")).toBeVisible();
  await page.locator("button.error-dismiss").click();
  await expect(page.locator(".error-banner")).toBeHidden();
});

test("shows loading on retry when request is slow", async ({ page }) => {
  await page.addInitScript(() => {
    (window as any).__TAURI_E2E_CONFIG__ = { getTasksError: "Mock failure" };
  });
  await page.goto("/");
  await expect(page.locator(".error-banner")).toBeVisible();

  await setInvokeConfig(page, { delayMs: 800, getTasksError: undefined });
  await page.locator("button.error-action").click();
  await expect(page.locator(".loading")).toBeVisible();
});

import { beforeEach, describe, expect, it, vi } from "vitest"
import { enqueueProgressUpdate, flushQueuedProgress } from "../../../app/javascript/offline/progress_queue"

const STORAGE_KEY = "scanarr:offline_progress_queue"

describe("progress_queue", () => {
  beforeEach(() => {
    if (typeof window.localStorage?.removeItem !== "function") {
      const store = new Map<string, string>()
      vi.stubGlobal("localStorage", {
        getItem: (key: string) => store.get(key) || null,
        setItem: (key: string, value: string) => {
          store.set(key, value)
        },
        removeItem: (key: string) => {
          store.delete(key)
        },
        clear: () => {
          store.clear()
        }
      })
    }

    window.localStorage.removeItem(STORAGE_KEY)
    vi.restoreAllMocks()
  })

  it("deduplicates entries by progress URL", async () => {
    await enqueueProgressUpdate({ progressUrl: "/progress/1", pageIndex: 2, pageCount: 20 })
    await enqueueProgressUpdate({ progressUrl: "/progress/1", pageIndex: 8, pageCount: 20 })

    const queue = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "[]")
    expect(queue).toHaveLength(1)
    expect(queue[0].pageIndex).toBe(8)
  })

  it("flushes queued entries on successful requests", async () => {
    await enqueueProgressUpdate({ progressUrl: "/progress/1", pageIndex: 2, pageCount: 20 })
    await enqueueProgressUpdate({ progressUrl: "/progress/2", pageIndex: 5, pageCount: 20 })

    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }))
      )
    )

    await flushQueuedProgress("token")

    const queue = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "[]")
    expect(queue).toHaveLength(0)
  })

  it("retains failed entries after flush attempt", async () => {
    await enqueueProgressUpdate({ progressUrl: "/progress/1", pageIndex: 2, pageCount: 20 })

    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        Promise.resolve(new Response(JSON.stringify({ error: "fail" }), { status: 500 }))
      )
    )

    await flushQueuedProgress("token")

    const queue = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "[]")
    expect(queue).toHaveLength(1)
    expect(queue[0].progressUrl).toBe("/progress/1")
  })

  it("preserves newer progress queued while an older request is in flight", async () => {
    await enqueueProgressUpdate({ progressUrl: "/race-progress", pageIndex: 2, pageCount: 20 })
    let finish!: (response: Response) => void
    vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>((resolve) => { finish = resolve })))
    const flushing = flushQueuedProgress("token")
    await enqueueProgressUpdate({ progressUrl: "/race-progress", pageIndex: 8, pageCount: 20 })
    finish(new Response("{}", { status: 200 }))
    await flushing

    const queue = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "[]")
    expect(queue.find((entry: { progressUrl: string }) => entry.progressUrl === "/race-progress").pageIndex).toBe(8)
  })
})

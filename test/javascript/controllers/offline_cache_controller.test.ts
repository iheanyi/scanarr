import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import OfflineCacheController from "../../../app/javascript/controllers/offline_cache_controller"
import { fetchOfflinePages, pinChapter, unpinChapter } from "../../../app/javascript/offline/offline_manifest_client"
import { getOfflineChapter, putOfflineChapter, patchOfflineChapter } from "../../../app/javascript/offline/idb_store"

vi.mock("../../../app/javascript/offline/offline_manifest_client", () => ({
  fetchOfflinePages: vi.fn(), pinChapter: vi.fn(), unpinChapter: vi.fn(), syncOfflineManifest: vi.fn()
}))
vi.mock("../../../app/javascript/offline/idb_store", () => ({
  getOfflineChapter: vi.fn(), putOfflineChapter: vi.fn(), patchOfflineChapter: vi.fn(), deleteOfflineChapter: vi.fn()
}))

const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

describe("device download controls", () => {
  let application: Application

  beforeEach(async () => {
    vi.clearAllMocks()
    vi.mocked(getOfflineChapter).mockResolvedValue(null)
    vi.mocked(patchOfflineChapter).mockResolvedValue(null)
    document.body.innerHTML = `<div data-controller="offline-cache">
      <button data-offline-cache-target="downloadButton" data-action="offline-cache#download">Save on device</button>
      <button data-offline-cache-target="cancelButton" data-action="offline-cache#cancel" hidden>Cancel</button>
      <button data-offline-cache-target="removeButton" hidden>Remove</button>
      <span data-offline-cache-target="progress"></span>
      <p data-offline-cache-target="error" role="alert" hidden></p>
    </div>`
    application = Application.start()
    application.register("offline-cache", OfflineCacheController)
    await settle()
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
    vi.unstubAllGlobals()
  })

  it("keeps cancellation usable while a page request is pending", async () => {
    vi.mocked(fetchOfflinePages).mockResolvedValue({ pages: [{ index: 1, source: "downloaded", url: "http://localhost/page.jpg" }], page_count: 1, chapter_public_id: "chapter", chapter_number: "1", status: "pinned" })
    let record: any
    vi.mocked(putOfflineChapter).mockImplementation(async (value) => { record = value })
    vi.mocked(getOfflineChapter).mockImplementation(async () => record || null)
    vi.stubGlobal("caches", { open: vi.fn().mockResolvedValue({ delete: vi.fn().mockResolvedValue(true) }) })
    vi.stubGlobal("fetch", vi.fn((_request, options) => new Promise((_resolve, reject) => {
      options.signal.addEventListener("abort", () => reject(new DOMException("Cancelled", "AbortError")))
    })))

    document.querySelector<HTMLButtonElement>('[data-offline-cache-target="downloadButton"]')!.click()
    await settle()
    const cancel = document.querySelector<HTMLButtonElement>('[data-offline-cache-target="cancelButton"]')!

    expect(cancel.hidden).toBe(false)
    expect(cancel.disabled).toBe(false)
    expect(document.querySelector('[data-offline-cache-target="progress"]')!.textContent).toBe("0/1")
    cancel.click()
    await settle()

    expect(unpinChapter).toHaveBeenCalledOnce()
  })

  it("shows failures even before a local chapter record exists", async () => {
    vi.mocked(pinChapter).mockRejectedValueOnce(new Error("Server unavailable. Try again."))
    document.querySelector<HTMLButtonElement>('[data-offline-cache-target="downloadButton"]')!.click()
    await settle()

    const error = document.querySelector<HTMLElement>('[data-offline-cache-target="error"]')!
    expect(error.hidden).toBe(false)
    expect(error.textContent).toBe("Server unavailable. Try again.")
    expect(document.querySelector<HTMLButtonElement>('[data-offline-cache-target="downloadButton"]')!.disabled).toBe(false)
  })
})

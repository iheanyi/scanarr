import { Application } from "@hotwired/stimulus"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import ReaderController from "../../../app/javascript/controllers/reader_controller"
import { enqueueProgressUpdate, flushQueuedProgress } from "../../../app/javascript/offline/progress_queue"

vi.mock("../../../app/javascript/offline/progress_queue", () => ({
  enqueueProgressUpdate: vi.fn().mockResolvedValue(true),
  flushQueuedProgress: vi.fn().mockResolvedValue(undefined)
}))
const settle = () => new Promise((resolve) => setTimeout(resolve, 0))

describe("reader keyboard and navigation lifecycle", () => {
  let application: Application
  let reader: HTMLElement
  let controller: ReaderController

  beforeEach(async () => {
    vi.clearAllMocks()
    vi.mocked(enqueueProgressUpdate).mockResolvedValue(true)
    document.body.innerHTML = `<main data-controller="reader" data-reader-progress-url-value="/chapters/1/progress" data-reader-page-count-value="2">
      <select><option>Vertical</option><option>Horizontal</option></select>
      <button>Reader settings</button><a href="#">Back to series</a>
      <div contenteditable="true"><span>Edit text</span></div>
    </main>`
    reader = document.querySelector("main")!
    application = Application.start()
    application.register("reader", ReaderController)
    await settle()
    controller = application.getControllerForElementAndIdentifier(reader, "reader") as ReaderController
    // Targets can arrive after controller connection, as with Turbo updates.
    reader.insertAdjacentHTML("beforeend", '<article data-reader-target="page"></article><article data-reader-target="page"></article>')
    reader.querySelectorAll<HTMLElement>("article").forEach((page) => { page.scrollIntoView = vi.fn() })
  })

  afterEach(async () => {
    reader.remove()
    await settle()
    application.stop()
    document.body.innerHTML = ""
    vi.unstubAllGlobals()
  })

  it.each([["select", "ArrowDown"], ["button", " "], ["a", " "], ["[contenteditable] span", "ArrowDown"]])("preserves native keyboard actions inside %s", (selector, key) => {
    const next = vi.spyOn(controller, "next")
    const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
    reader.querySelector(selector)!.dispatchEvent(event)

    expect(next).not.toHaveBeenCalled()
    expect(event.defaultPrevented).toBe(false)
  })

  it("queues the latest page immediately when leaving before the debounce fires", async () => {
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }))
    expect(enqueueProgressUpdate).not.toHaveBeenCalled()
    reader.remove()
    await settle()

    expect(enqueueProgressUpdate).toHaveBeenCalledWith({ progressUrl: "/chapters/1/progress", pageIndex: 2, pageCount: 2 })
    expect(flushQueuedProgress).toHaveBeenCalled()
  })

  it("queues pending progress on pagehide without waiting for DOM removal", () => {
    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }))
    window.dispatchEvent(new Event("pagehide"))

    expect(enqueueProgressUpdate).toHaveBeenCalledWith({ progressUrl: "/chapters/1/progress", pageIndex: 2, pageCount: 2 })
  })

  it("saves online progress even when browser storage throws", async () => {
    const actualQueue = await vi.importActual<typeof import("../../../app/javascript/offline/progress_queue")>("../../../app/javascript/offline/progress_queue")
    vi.mocked(enqueueProgressUpdate).mockImplementation(actualQueue.enqueueProgressUpdate)
    vi.stubGlobal("localStorage", {
      getItem: () => { throw new DOMException("Storage unavailable", "SecurityError") },
      setItem: () => { throw new DOMException("Storage unavailable", "SecurityError") }
    })
    const fetchProgress = vi.fn().mockResolvedValue(new Response("{}", { status: 200 }))
    vi.stubGlobal("fetch", fetchProgress)

    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }))
    window.dispatchEvent(new Event("pagehide"))
    await settle()

    expect(fetchProgress).toHaveBeenCalledWith("/chapters/1/progress", expect.objectContaining({
      method: "PATCH",
      keepalive: true,
      body: JSON.stringify({ page_index: 2, page_count: 2 })
    }))
  })
})

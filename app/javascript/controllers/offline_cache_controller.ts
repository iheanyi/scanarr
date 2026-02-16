import { Controller } from "@hotwired/stimulus"
import {
  deleteOfflineChapter,
  getOfflineChapter,
  patchOfflineChapter,
  putOfflineChapter,
  type OfflineChapterRecord
} from "../offline/idb_store"
import {
  fetchOfflinePages,
  pinChapter,
  syncOfflineManifest,
  unpinChapter
} from "../offline/offline_manifest_client"

const IMAGE_CACHE = "scanarr-images-v1"

export default class extends Controller {
  static targets = ["progress", "downloadButton", "cancelButton", "removeButton", "availableIndicator"]
  static values = {
    chapterKey: String,
    chapterPublicId: String,
    sourceSlug: String,
    seriesSlug: String,
    chapterIdentifier: String,
    pinUrl: String,
    unpinUrl: String,
    pagesUrl: String,
    manifestUrl: { type: String, default: "/offline_manifest" }
  }

  declare readonly hasProgressTarget: boolean
  declare readonly progressTarget: HTMLElement
  declare readonly hasDownloadButtonTarget: boolean
  declare readonly downloadButtonTarget: HTMLButtonElement
  declare readonly hasCancelButtonTarget: boolean
  declare readonly cancelButtonTarget: HTMLButtonElement
  declare readonly hasRemoveButtonTarget: boolean
  declare readonly removeButtonTarget: HTMLButtonElement
  declare readonly hasAvailableIndicatorTarget: boolean
  declare readonly availableIndicatorTarget: HTMLElement

  declare readonly chapterKeyValue: string
  declare readonly chapterPublicIdValue: string
  declare readonly sourceSlugValue: string
  declare readonly seriesSlugValue: string
  declare readonly chapterIdentifierValue: string
  declare readonly pinUrlValue: string
  declare readonly unpinUrlValue: string
  declare readonly pagesUrlValue: string
  declare readonly manifestUrlValue: string

  private busy = false
  private abortController?: AbortController
  private cancelRequested = false

  connect() {
    void this.refreshLocalState()
  }

  async download(event?: Event) {
    await this.save(event)
  }

  async save(event?: Event) {
    event?.preventDefault()
    if (this.busy) return

    this.busy = true
    this.cancelRequested = false
    this.setButtonsEnabled(false)

    try {
      await pinChapter(this.pinUrlValue, this.csrfToken())
      await this.downloadAndCachePages()
    } catch (error) {
      if (this.isAbortError(error) || this.cancelRequested) {
        await this.unpinAndClear()
      } else {
        await this.markFailed(this.errorMessage(error))
      }
    } finally {
      this.abortController = undefined
      this.cancelRequested = false
      this.busy = false
      this.setButtonsEnabled(true)
      await this.refreshLocalState()
    }
  }

  async cancel(event?: Event) {
    event?.preventDefault()

    if (!this.busy) {
      await this.remove(event)
      return
    }

    this.cancelRequested = true
    this.abortController?.abort()
  }

  async remove(event?: Event) {
    event?.preventDefault()
    if (this.busy) return

    this.busy = true
    this.setButtonsEnabled(false)

    try {
      await this.unpinAndClear()
    } catch (error) {
      await this.markFailed(this.errorMessage(error))
    } finally {
      this.busy = false
      this.setButtonsEnabled(true)
      await this.refreshLocalState()
    }
  }

  async retry(event?: Event) {
    await this.save(event)
  }

  private async downloadAndCachePages() {
    await this.ensureStorageBudget()
    this.abortController = new AbortController()

    const payload = await fetchOfflinePages(this.pagesUrlValue)
    const pageUrls = payload.pages.map((page) => page.url)
    if (pageUrls.length === 0) {
      throw new Error("No pages are available to cache for this chapter.")
    }

    const now = new Date().toISOString()
    const baseRecord: OfflineChapterRecord = {
      chapterKey: this.chapterKeyValue,
      chapterPublicId: this.chapterPublicIdValue,
      sourceSlug: this.sourceSlugValue,
      seriesSlug: this.seriesSlugValue,
      chapterIdentifier: this.chapterIdentifierValue,
      status: "downloading",
      pageCount: pageUrls.length,
      downloadedCount: 0,
      pages: pageUrls,
      updatedAt: now,
      lastError: undefined
    }
    await putOfflineChapter(baseRecord)
    this.renderState(baseRecord)

    const cache = await caches.open(IMAGE_CACHE)
    for (let index = 0; index < pageUrls.length; index++) {
      if (this.cancelRequested) {
        throw new DOMException("Offline download cancelled", "AbortError")
      }

      if (index % 8 === 0) await this.ensureStorageBudget()

      const pageUrl = pageUrls[index]
      const request = new Request(pageUrl, { credentials: "same-origin" })
      const response = await fetch(request, { signal: this.abortController.signal })
      if (!response.ok) {
        throw new Error(`Failed to cache page ${index + 1} (${response.status}).`)
      }

      await cache.put(request, response.clone())

      const nextRecord = await patchOfflineChapter(this.chapterKeyValue, {
        downloadedCount: index + 1,
        status: "downloading",
        updatedAt: new Date().toISOString()
      })
      this.renderState(nextRecord)
    }

    const completeRecord = await patchOfflineChapter(this.chapterKeyValue, {
      status: "complete",
      downloadedCount: pageUrls.length,
      updatedAt: new Date().toISOString(),
      lastError: undefined
    })
    this.renderState(completeRecord)

    try {
      await syncOfflineManifest(
        this.manifestUrlValue,
        [
          {
            chapter_public_id: this.chapterPublicIdValue,
            status: "complete",
            last_synced_at: new Date().toISOString()
          }
        ],
        this.csrfToken()
      )
    } catch (_error) {
      // Keep local availability as complete even when manifest sync fails.
    }
  }

  private async markFailed(message: string) {
    const failedRecord = await patchOfflineChapter(this.chapterKeyValue, {
      status: "failed",
      lastError: message,
      updatedAt: new Date().toISOString()
    })
    this.renderState(failedRecord)

    await syncOfflineManifest(
      this.manifestUrlValue,
      [
        {
          chapter_public_id: this.chapterPublicIdValue,
          status: "failed",
          last_error: message,
          last_synced_at: new Date().toISOString()
        }
      ],
      this.csrfToken()
    )
  }

  private async refreshLocalState() {
    const record = await getOfflineChapter(this.chapterKeyValue)
    this.renderState(record)
  }

  private renderState(record: OfflineChapterRecord | null) {
    const isComplete = !!record && record.status === "complete"
    const isDownloading = !!record && ["downloading", "queued", "pinned"].includes(record.status)
    const isFailed = !!record && record.status === "failed"

    if (this.hasProgressTarget) {
      if (!record || !record.pageCount || !isDownloading) {
        this.progressTarget.textContent = ""
      } else {
        this.progressTarget.textContent = `${record.downloadedCount}/${record.pageCount}`
      }

      this.progressTarget.hidden = !isDownloading
    }

    if (this.hasDownloadButtonTarget) {
      const showDownload = !record || isFailed
      this.downloadButtonTarget.hidden = !showDownload
    }

    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.hidden = !isDownloading
    }

    if (this.hasRemoveButtonTarget) {
      this.removeButtonTarget.hidden = !isComplete
    }

    if (this.hasAvailableIndicatorTarget) {
      this.availableIndicatorTarget.hidden = !isComplete
    }
  }

  private setButtonsEnabled(enabled: boolean) {
    if (this.hasDownloadButtonTarget) this.downloadButtonTarget.disabled = !enabled
    if (this.hasCancelButtonTarget) this.cancelButtonTarget.disabled = !enabled
    if (this.hasRemoveButtonTarget) this.removeButtonTarget.disabled = !enabled
  }

  private async ensureStorageBudget() {
    if (!("storage" in navigator) || !navigator.storage.estimate) return

    const estimate = await navigator.storage.estimate()
    const quota = estimate.quota || 0
    const usage = estimate.usage || 0
    if (quota > 0 && usage / quota > 0.97) {
      throw new Error("Storage is almost full. Clear some offline chapters and try again.")
    }
  }

  private csrfToken() {
    return (
      document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") ||
      ""
    )
  }

  private errorMessage(error: unknown) {
    if (error instanceof Error) return error.message
    return "Offline download failed."
  }

  private async unpinAndClear() {
    await unpinChapter(this.unpinUrlValue, this.csrfToken())

    const record = await getOfflineChapter(this.chapterKeyValue)
    if (record?.pages?.length) {
      const cache = await caches.open(IMAGE_CACHE)
      await Promise.all(record.pages.map((pageUrl) => cache.delete(new Request(pageUrl, { credentials: "same-origin" }))))
    }

    await deleteOfflineChapter(this.chapterKeyValue)
  }

  private isAbortError(error: unknown) {
    return error instanceof DOMException && error.name === "AbortError"
  }
}

import { Controller } from "@hotwired/stimulus"

export type TapZoneAction = "next" | "previous" | "toggle"

export function resolveTapZoneAction(xRatio: number, yRatio: number, isHorizontal: boolean, isRtl: boolean): TapZoneAction {
  if (yRatio <= 0.18) return "toggle"

  const isRtlHorizontal = isHorizontal && isRtl
  if (xRatio <= 0.33) return isRtlHorizontal ? "next" : "previous"
  if (xRatio >= 0.67) return isRtlHorizontal ? "previous" : "next"
  return "toggle"
}

type ProgressQueueItem = {
  pageIndex: number
  pageCount: number
  progressUrl: string
  createdAt?: number
}

export function normalizeProgressQueue(raw: unknown): ProgressQueueItem[] {
  if (!Array.isArray(raw)) return []
  return raw.filter((item): item is ProgressQueueItem => {
    if (!item || typeof item !== "object") return false
    const value = item as Partial<ProgressQueueItem>
    return (
      typeof value.pageIndex === "number" &&
      typeof value.pageCount === "number" &&
      typeof value.progressUrl === "string"
    )
  })
}

export default class extends Controller {
  static targets = ["page", "viewport", "progressText", "progressBar", "progressPercent", "lightbox", "lightboxImage", "nextChapterOverlay", "nextChapterCountdown", "chrome", "offlineStatus", "fullscreenLabel"]
  static values = { style: String, pageCount: Number, initialPageIndex: Number, progressUrl: String, nextChapterUrl: String, nextChapterTitle: String }
  declare readonly pageTargets: HTMLElement[]
  declare readonly viewportTarget: HTMLElement
  declare readonly hasViewportTarget: boolean
  declare readonly progressTextTarget: HTMLElement
  declare readonly progressBarTarget: HTMLElement
  declare readonly progressPercentTarget: HTMLElement
  declare readonly hasProgressTextTarget: boolean
  declare readonly hasProgressBarTarget: boolean
  declare readonly hasProgressPercentTarget: boolean
  declare readonly lightboxTarget: HTMLElement
  declare readonly lightboxImageTarget: HTMLImageElement
  declare readonly hasLightboxTarget: boolean
  declare readonly hasLightboxImageTarget: boolean
  declare readonly nextChapterOverlayTarget: HTMLElement
  declare readonly nextChapterCountdownTarget: HTMLElement
  declare readonly hasNextChapterOverlayTarget: boolean
  declare readonly hasNextChapterCountdownTarget: boolean
  declare readonly chromeTargets: HTMLElement[]
  declare readonly hasChromeTarget: boolean
  declare readonly offlineStatusTarget: HTMLElement
  declare readonly hasOfflineStatusTarget: boolean
  declare readonly fullscreenLabelTarget: HTMLElement
  declare readonly hasFullscreenLabelTarget: boolean
  declare readonly styleValue: string
  declare readonly pageCountValue: number
  declare readonly initialPageIndexValue: number
  declare readonly progressUrlValue: string
  declare readonly hasProgressUrlValue: boolean
  declare readonly nextChapterUrlValue: string
  declare readonly nextChapterTitleValue: string
  declare readonly hasNextChapterUrlValue: boolean

  private currentIndex = 0
  private observer?: IntersectionObserver
  private lastReportedIndex = -1
  private lightboxOpen = false
  private pendingProgressSave?: ReturnType<typeof setTimeout>
  private isScrolling = false // Lock to prevent observer interference during programmatic scroll
  private nextChapterCountdownInterval?: ReturnType<typeof setInterval>
  private chromeHideTimeout?: ReturnType<typeof setTimeout>
  private nextChapterCountdownValue = 5
  private chromeVisible = true
  private hasInteracted = false // Don't auto-advance on initial page load
  private pointerStartX?: number
  private pointerStartY?: number
  private pointerStartedAt = 0
  private pointerMoved = false
  private wakeLock?: { release: () => Promise<void> }
  private nextChapterPrefetched = false
  private readonly progressQueueStorageKey = "scanarr:reader-progress-queue"
  private readonly pointerTapDistance = 12
  private readonly pointerTapDurationMs = 350

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.handleKeydown)
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.flushProgressQueue = this.flushProgressQueue.bind(this)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
    window.addEventListener("online", this.flushProgressQueue)
    
    if (this.pageTargets.length > 0) {
      this.currentIndex = this.resolveInitialIndex()
      // Use instant scroll on initial load
      this.scrollToIndex(this.currentIndex, "instant")
      this.observePages()
      // Force initial state sync after scroll
      requestAnimationFrame(() => this.syncState())
    }

    this.requestWakeLock()
    this.flushProgressQueue()
    this.showChrome()
    this.updateFullscreenLabel()
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
    this.observer?.disconnect()
    if (this.pendingProgressSave) clearTimeout(this.pendingProgressSave)
    if (this.chromeHideTimeout) clearTimeout(this.chromeHideTimeout)
    this.clearNextChapterCountdown()
    window.removeEventListener("online", this.flushProgressQueue)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    this.releaseWakeLock()
  }

  private handleKeydown(event: KeyboardEvent) {
    // Don't handle if typing in an input
    if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) return
    
    if (event.key === "Escape" && this.lightboxOpen) {
      this.closeLightbox()
      return
    }

    if (event.key === "f" || event.key === "F") {
      event.preventDefault()
      this.toggleFullscreen()
      return
    }
    
    const isRtl = this.isRtl()
    const isVertical = !this.isHorizontal()
    
    // Next page keys
    const nextKeys = isVertical 
      ? ["ArrowDown", "j", " ", "PageDown"]  // Vertical: down arrow, j, space, page down
      : ["ArrowRight", "j", " ", "PageDown"] // Horizontal: right arrow, j, space, page down
    
    // Previous page keys  
    const prevKeys = isVertical
      ? ["ArrowUp", "k", "PageUp"]           // Vertical: up arrow, k, page up
      : ["ArrowLeft", "k", "PageUp"]         // Horizontal: left arrow, k, page up
    
    // In RTL horizontal mode, swap next/prev
    if (isRtl && !isVertical) {
      if (nextKeys.includes(event.key)) {
        event.preventDefault()
        this.previous()
      } else if (prevKeys.includes(event.key)) {
        event.preventDefault()
        this.next()
      }
    } else {
      if (nextKeys.includes(event.key)) {
        event.preventDefault()
        this.next()
      } else if (prevKeys.includes(event.key)) {
        event.preventDefault()
        this.previous()
      }
    }
  }

  // Action: click on a page to open lightbox at that page
  openLightboxForPage(event: Event) {
    const target = event.currentTarget as HTMLElement
    const index = this.pageTargets.indexOf(target)
    if (index >= 0) {
      this.currentIndex = index
      this.syncState()
      this.openLightbox()
    }
  }

  toggleLightbox(event?: Event) {
    event?.preventDefault()
    if (this.lightboxOpen) {
      this.closeLightbox()
    } else {
      this.openLightbox()
    }
  }

  openLightbox(event?: Event) {
    event?.preventDefault()
    if (!this.hasLightboxTarget || !this.hasLightboxImageTarget) return
    this.lightboxOpen = true
    this.lightboxTarget.classList.remove("hidden")
    this.lightboxTarget.classList.add("flex")
    this.updateLightboxImage()
    document.body.style.overflow = "hidden"
  }

  closeLightbox(event?: Event) {
    event?.preventDefault()
    if (!this.hasLightboxTarget) return
    this.lightboxOpen = false
    this.lightboxTarget.classList.add("hidden")
    this.lightboxTarget.classList.remove("flex")
    document.body.style.overflow = ""
  }

  lightboxNext(event?: Event) {
    event?.preventDefault()
    event?.stopPropagation()
    // In RTL mode, the "next" button (right arrow) goes to previous page
    this.isRtl() ? this.previous() : this.next()
  }

  lightboxPrev(event?: Event) {
    event?.preventDefault()
    event?.stopPropagation()
    // In RTL mode, the "prev" button (left arrow) goes to next page
    this.isRtl() ? this.next() : this.previous()
  }

  private resolveInitialIndex() {
    const pageCount = this.pageTargets.length
    const pageParam = this.pageParamValue()
    const initialValue = pageParam ?? this.initialPageIndexValue
    const oneBased = initialValue && initialValue > 0 ? initialValue : 1
    const clamped = Math.min(Math.max(oneBased, 1), pageCount)
    return clamped - 1
  }

  private pageParamValue() {
    const params = new URLSearchParams(window.location.search)
    const raw = params.get("page")
    if (!raw) return null
    const value = Number.parseInt(raw, 10)
    if (!Number.isFinite(value) || value < 1) return null
    return value
  }

  next() {
    this.hasInteracted = true
    const nextIndex = this.currentIndex + 1
    if (nextIndex >= this.pageTargets.length) {
      // Past last page — trigger next chapter flow
      if (this.lightboxOpen) this.closeLightbox()
      this.checkEndOfChapter()
      return
    }
    this.scrollToIndex(nextIndex)
  }

  previous() {
    this.hasInteracted = true
    this.scrollToIndex(this.currentIndex - 1)
  }

  private scrollToIndex(index: number, behavior: ScrollBehavior = "smooth") {
    if (index < 0 || index >= this.pageTargets.length) return
    
    // Lock to prevent observer from interfering
    this.isScrolling = true
    this.currentIndex = index
    
    const block = this.isHorizontal() ? "nearest" : "start"
    const inline = this.isHorizontal() ? "center" : "nearest"
    
    this.pageTargets[index].scrollIntoView({ behavior, block, inline })
    
    // Update state immediately
    this.syncState()
    
    // Unlock after scroll completes (use longer timeout for smooth, shorter for instant)
    const unlockDelay = behavior === "smooth" ? 500 : 50
    setTimeout(() => {
      this.isScrolling = false
    }, unlockDelay)
  }

  private isHorizontal() {
    return this.styleValue === "left_to_right" || this.styleValue === "right_to_left"
  }

  private isRtl() {
    // Check both the style value and the data attribute on viewport
    if (this.styleValue === "right_to_left") return true
    if (this.hasViewportTarget) {
      return this.viewportTarget.dataset.readerRtl === "true"
    }
    return false
  }

  private observePages() {
    if (this.pageTargets.length === 0) return
    
    // For horizontal modes, observe against the scrolling viewport container
    // For vertical modes, use browser viewport (null) since the whole page scrolls
    const root = this.isHorizontal() && this.hasViewportTarget ? this.viewportTarget : null
    
    // Use lower threshold for vertical (first page that enters view) vs horizontal (centered page)
    const threshold = this.isHorizontal() ? 0.5 : 0.3
    
    this.observer = new IntersectionObserver(
      (entries) => {
        // Skip if we're in the middle of a programmatic scroll
        if (this.isScrolling) return
        
        if (this.isHorizontal()) {
          // Horizontal: find the most visible page (center)
          let bestEntry: IntersectionObserverEntry | null = null
          for (const entry of entries) {
            if (entry.isIntersecting) {
              if (!bestEntry || entry.intersectionRatio > bestEntry.intersectionRatio) {
                bestEntry = entry
              }
            }
          }
          
          if (!bestEntry) return
          
          const index = this.pageTargets.indexOf(bestEntry.target as HTMLElement)
          if (index >= 0 && index !== this.currentIndex) {
            this.hasInteracted = true
            this.currentIndex = index
            this.syncState()
          }
        } else {
          // Vertical: find the topmost visible page (first in reading order)
          let topmostEntry: IntersectionObserverEntry | null = null
          let topmostTop = Infinity

          for (const entry of entries) {
            if (entry.isIntersecting && entry.intersectionRatio >= threshold) {
              const rect = entry.boundingClientRect
              if (rect.top < topmostTop) {
                topmostTop = rect.top
                topmostEntry = entry
              }
            }
          }

          if (!topmostEntry) return

          const index = this.pageTargets.indexOf(topmostEntry.target as HTMLElement)
          if (index >= 0 && index !== this.currentIndex) {
            this.hasInteracted = true
            this.currentIndex = index
            this.syncState()
          }
        }
      },
      { root, threshold }
    )

    this.pageTargets.forEach((page) => this.observer?.observe(page))
  }

  private syncState() {
    this.updateProgressUI()
    this.scheduleProgressSave()
    this.preloadAhead()
    this.checkEndOfChapter()
    // Update URL last - it can fail with credentials in URL (browser security)
    try {
      this.updateURL()
    } catch {
      // Ignore SecurityError when URL contains credentials
    }
  }

  // Preload upcoming images so page flips feel instant.
  // Switches the next few lazy images to eager loading, triggering
  // the browser to start downloading them before they're scrolled into view.
  private preloadAhead() {
    const PRELOAD_COUNT = 5
    const start = this.currentIndex + 1
    const end = Math.min(start + PRELOAD_COUNT, this.pageTargets.length)

    for (let i = start; i < end; i++) {
      const img = this.pageTargets[i]?.querySelector("img") as HTMLImageElement | null
      if (img && img.loading === "lazy") {
        img.loading = "eager"
      }
      const preloadUrl = img?.currentSrc || img?.src
      if (preloadUrl) {
        const preloader = new Image()
        preloader.src = preloadUrl
      }
    }

    this.maybePrefetchNextChapter()
  }

  private updateProgressUI() {
    const pageCount = this.pageCountValue || this.pageTargets.length
    if (!pageCount) return

    const pageIndex = this.currentIndex + 1
    const percent = Math.min(100, Math.round((pageIndex / pageCount) * 100))

    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `Page ${pageIndex} / ${pageCount}`
    }
    if (this.hasProgressPercentTarget) {
      this.progressPercentTarget.textContent = `${percent}%`
    }
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percent}%`
    }

    if (this.lightboxOpen) {
      this.updateLightboxImage()
    }
  }

  private updateURL() {
    const pageIndex = this.currentIndex + 1
    const url = new URL(window.location.href)
    const currentPage = url.searchParams.get("page")
    
    // Only update if changed to avoid unnecessary history entries
    if (currentPage !== pageIndex.toString()) {
      url.searchParams.set("page", pageIndex.toString())
      window.history.replaceState(window.history.state, "", url.toString())
    }
  }

  private scheduleProgressSave() {
    const pageIndex = this.currentIndex + 1
    
    // Skip if same page already reported
    if (pageIndex === this.lastReportedIndex) return
    this.lastReportedIndex = pageIndex
    
    // Debounce progress saves to avoid hammering the server
    if (this.pendingProgressSave) clearTimeout(this.pendingProgressSave)
    this.pendingProgressSave = setTimeout(() => {
      this.persistProgress()
    }, 500)
  }

  private updateLightboxImage() {
    if (!this.hasLightboxImageTarget) return
    const page = this.pageTargets[this.currentIndex]
    if (!page) return
    const image = page.querySelector("img") as HTMLImageElement | null
    if (!image) return
    this.lightboxImageTarget.src = image.currentSrc || image.src
    if (image.alt) {
      this.lightboxImageTarget.alt = image.alt
    }
  }

  private persistProgress() {
    if (!this.hasProgressUrlValue || !this.progressUrlValue) return
    
    const pageIndex = this.currentIndex + 1
    const pageCount = this.pageCountValue || this.pageTargets.length
    
    const token = document
      .querySelector('meta[name="csrf-token"]')
      ?.getAttribute("content")

    fetch(this.progressUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token || ""
      },
      body: JSON.stringify({ page_index: pageIndex, page_count: pageCount })
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Progress save failed with status ${response.status}`)
        return this.flushProgressQueue()
      })
      .catch((error) => {
        this.queueProgressSave(pageIndex, pageCount)
        console.warn("Failed to save reading progress, queued for retry:", error)
      })
  }

  // Check if we're on the last page and should show next chapter prompt
  // Only auto-show when user has actively navigated (not on initial load from saved progress)
  private checkEndOfChapter() {
    if (!this.hasNextChapterUrlValue || !this.nextChapterUrlValue) return
    if (!this.hasInteracted) return

    const isLastPage = this.currentIndex === this.pageTargets.length - 1

    if (isLastPage) {
      this.showNextChapterOverlay()
    } else {
      this.hideNextChapterOverlay()
    }
  }

  private showNextChapterOverlay() {
    if (!this.hasNextChapterOverlayTarget) return
    
    this.nextChapterOverlayTarget.classList.remove("hidden")
    this.nextChapterOverlayTarget.classList.add("flex")
    
    // Start countdown for auto-navigation
    this.startNextChapterCountdown()
  }

  private hideNextChapterOverlay() {
    if (!this.hasNextChapterOverlayTarget) return
    
    this.nextChapterOverlayTarget.classList.add("hidden")
    this.nextChapterOverlayTarget.classList.remove("flex")
    
    this.clearNextChapterCountdown()
  }

  private startNextChapterCountdown() {
    this.clearNextChapterCountdown()
    this.nextChapterCountdownValue = 5
    this.updateCountdownDisplay()
    
    this.nextChapterCountdownInterval = setInterval(() => {
      this.nextChapterCountdownValue--
      this.updateCountdownDisplay()
      
      if (this.nextChapterCountdownValue <= 0) {
        this.goToNextChapter()
      }
    }, 1000)
  }

  private clearNextChapterCountdown() {
    if (this.nextChapterCountdownInterval) {
      clearInterval(this.nextChapterCountdownInterval)
      this.nextChapterCountdownInterval = undefined
    }
  }

  private updateCountdownDisplay() {
    if (!this.hasNextChapterCountdownTarget) return
    this.nextChapterCountdownTarget.textContent = this.nextChapterCountdownValue.toString()
  }

  // Action: manually go to next chapter
  goToNextChapter(event?: Event) {
    event?.preventDefault()
    if (!this.hasNextChapterUrlValue || !this.nextChapterUrlValue) return
    
    this.clearNextChapterCountdown()
    
    // Navigate to next chapter without any query parameters
    // This ensures we start at page 1 of the new chapter
    const url = new URL(this.nextChapterUrlValue, window.location.origin)
    url.search = '' // Clear any query parameters (like page number)
    window.location.href = url.toString()
  }

  // Action: cancel auto-navigation and stay on current chapter
  cancelNextChapter(event?: Event) {
    event?.preventDefault()
    this.hideNextChapterOverlay()
  }

  pointerDown(event: PointerEvent) {
    if (!this.shouldHandlePointerEvent(event)) return
    this.pointerStartX = event.clientX
    this.pointerStartY = event.clientY
    this.pointerStartedAt = Date.now()
    this.pointerMoved = false
  }

  pointerMove(event: PointerEvent) {
    if (this.pointerStartX === undefined || this.pointerStartY === undefined) return
    const movedX = Math.abs(event.clientX - this.pointerStartX)
    const movedY = Math.abs(event.clientY - this.pointerStartY)
    if (movedX > this.pointerTapDistance || movedY > this.pointerTapDistance) {
      this.pointerMoved = true
    }
  }

  pointerUp(event: PointerEvent) {
    if (!this.shouldHandlePointerEvent(event)) return
    if (this.pointerStartX === undefined || this.pointerStartY === undefined) return

    const movedX = Math.abs(event.clientX - this.pointerStartX)
    const movedY = Math.abs(event.clientY - this.pointerStartY)
    const duration = Date.now() - this.pointerStartedAt
    this.resetPointerState()

    if (this.pointerMoved || movedX > this.pointerTapDistance || movedY > this.pointerTapDistance || duration > this.pointerTapDurationMs) {
      return
    }

    const viewport = this.hasViewportTarget ? this.viewportTarget : (this.element as HTMLElement)
    const rect = viewport.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) return

    const xRatio = (event.clientX - rect.left) / rect.width
    const yRatio = (event.clientY - rect.top) / rect.height
    this.handleTapZone(xRatio, yRatio)
  }

  toggleChrome(event?: Event) {
    event?.preventDefault()
    if (this.chromeVisible) {
      this.hideChrome()
    } else {
      this.showChrome()
    }
  }

  toggleFullscreen(event?: Event) {
    event?.preventDefault()
    const doc = document as Document & {
      webkitExitFullscreen?: () => Promise<void>
    }
    const root = document.documentElement as HTMLElement & {
      webkitRequestFullscreen?: () => Promise<void>
    }

    if (document.fullscreenElement) {
      const exit = document.exitFullscreen?.bind(document) || doc.webkitExitFullscreen?.bind(doc)
      Promise.resolve(exit?.())
        .catch(() => undefined)
        .finally(() => this.updateFullscreenLabel())
      return
    }

    const request = root.requestFullscreen?.bind(root) || root.webkitRequestFullscreen?.bind(root)
    Promise.resolve(request?.())
      .catch(() => undefined)
      .finally(() => this.updateFullscreenLabel())
  }

  saveOffline(event?: Event) {
    event?.preventDefault()
    const urls = this.pageTargets
      .map((page) => {
        const img = page.querySelector("img") as HTMLImageElement | null
        return img?.currentSrc || img?.src || null
      })
      .filter((url): url is string => !!url)

    if (urls.length === 0) return

    if (this.hasOfflineStatusTarget) {
      this.offlineStatusTarget.textContent = "Saving offline..."
    }

    const payload = { type: "PREFETCH_CHAPTER", urls }
    if (navigator.serviceWorker?.controller) {
      navigator.serviceWorker.controller.postMessage(payload)
    } else if (navigator.serviceWorker?.ready) {
      navigator.serviceWorker.ready.then((registration) => registration.active?.postMessage(payload))
    }

    window.setTimeout(() => {
      if (this.hasOfflineStatusTarget) this.offlineStatusTarget.textContent = "Saved for offline"
    }, 1200)
  }

  private shouldHandlePointerEvent(event: Event) {
    const target = event.target as HTMLElement | null
    if (!target) return false
    return !target.closest("a,button,input,select,textarea,label,[data-reader-ignore-tap-zones]")
  }

  private resetPointerState() {
    this.pointerStartX = undefined
    this.pointerStartY = undefined
    this.pointerStartedAt = 0
    this.pointerMoved = false
  }

  private handleTapZone(xRatio: number, yRatio: number) {
    const action = resolveTapZoneAction(xRatio, yRatio, this.isHorizontal(), this.isRtl())
    if (action === "next") {
      this.next()
    } else if (action === "previous") {
      this.previous()
    } else {
      this.toggleChrome()
    }
  }

  private showChrome() {
    this.chromeVisible = true
    this.chromeTargets.forEach((element) => element.classList.remove("reader-chrome-hidden"))
    this.scheduleChromeAutoHide()
  }

  private hideChrome() {
    if (this.lightboxOpen) return
    this.chromeVisible = false
    this.chromeTargets.forEach((element) => element.classList.add("reader-chrome-hidden"))
    if (this.chromeHideTimeout) clearTimeout(this.chromeHideTimeout)
  }

  private scheduleChromeAutoHide() {
    if (this.chromeHideTimeout) clearTimeout(this.chromeHideTimeout)
    this.chromeHideTimeout = setTimeout(() => this.hideChrome(), 2600)
  }

  private updateFullscreenLabel() {
    if (!this.hasFullscreenLabelTarget) return
    this.fullscreenLabelTarget.textContent = document.fullscreenElement ? "Exit fullscreen" : "Fullscreen"
  }

  private maybePrefetchNextChapter() {
    if (this.nextChapterPrefetched || !this.hasNextChapterUrlValue || !this.nextChapterUrlValue) return
    const remainingPages = this.pageTargets.length - (this.currentIndex + 1)
    if (remainingPages > 3) return

    const link = document.createElement("link")
    link.rel = "prefetch"
    link.as = "document"
    link.href = this.nextChapterUrlValue
    document.head.appendChild(link)
    this.nextChapterPrefetched = true
  }

  private queueProgressSave(pageIndex: number, pageCount: number) {
    if (!this.hasProgressUrlValue || !this.progressUrlValue) return
    const queue = this.progressQueue()
    queue.push({
      pageIndex,
      pageCount,
      progressUrl: this.progressUrlValue,
      createdAt: Date.now()
    })
    localStorage.setItem(this.progressQueueStorageKey, JSON.stringify(queue.slice(-100)))
  }

  private async flushProgressQueue() {
    if (!this.hasProgressUrlValue || !this.progressUrlValue || !navigator.onLine) return
    const queue = this.progressQueue()
    if (queue.length === 0) return

    const token = document
      .querySelector('meta[name="csrf-token"]')
      ?.getAttribute("content")

    const remaining: typeof queue = []
    for (const item of queue) {
      try {
        const response = await fetch(item.progressUrl, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            Accept: "application/json",
            "X-CSRF-Token": token || ""
          },
          body: JSON.stringify({ page_index: item.pageIndex, page_count: item.pageCount })
        })
        if (!response.ok) throw new Error(`Queue flush failed: ${response.status}`)
      } catch (_) {
        remaining.push(item)
      }
    }

    localStorage.setItem(this.progressQueueStorageKey, JSON.stringify(remaining))
  }

  private progressQueue() {
    try {
      const raw = localStorage.getItem(this.progressQueueStorageKey)
      if (!raw) return []
      return normalizeProgressQueue(JSON.parse(raw))
    } catch (_) {
      return []
    }
  }

  private handleVisibilityChange() {
    if (document.visibilityState === "visible") {
      this.requestWakeLock()
      this.flushProgressQueue()
    } else {
      this.releaseWakeLock()
    }
  }

  private async requestWakeLock() {
    if (!("wakeLock" in navigator)) return
    try {
      this.wakeLock = await (navigator as Navigator & {
        wakeLock: {
          request: (type: "screen") => Promise<{ release: () => Promise<void> }>
        }
      }).wakeLock.request("screen")
    } catch (_) {
      // Wake lock is best-effort; failures are expected in unsupported contexts.
    }
  }

  private async releaseWakeLock() {
    if (!this.wakeLock) return
    try {
      await this.wakeLock.release()
    } catch (_) {
      // Ignore wake lock release errors.
    } finally {
      this.wakeLock = undefined
    }
  }
}

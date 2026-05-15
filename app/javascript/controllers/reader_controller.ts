import { Controller } from "@hotwired/stimulus"
import { enqueueProgressUpdate, flushQueuedProgress } from "../offline/progress_queue"

export function resolveLightboxSwipeAction(
  deltaX: number,
  deltaY: number,
  threshold = 56
): "next" | "previous" | null {
  const absX = Math.abs(deltaX)
  const absY = Math.abs(deltaY)

  if (absX < threshold || absX <= absY) return null
  return deltaX < 0 ? "next" : "previous"
}

export function resolveLightboxTapZoneAction(
  clientX: number,
  left: number,
  width: number,
  edgeZoneRatio = 0.34
): "next" | "previous" | "close" | null {
  if (width <= 0) return null

  const relativeX = clientX - left
  if (relativeX < 0 || relativeX > width) return null

  const edgeWidth = width * edgeZoneRatio
  if (relativeX <= edgeWidth) return "previous"
  if (relativeX >= width - edgeWidth) return "next"

  return "close"
}

export function observerThresholdForStyle(style: string): number {
  if (style === "left_to_right" || style === "right_to_left" || style === "vertical") return 0.5
  if (style === "webtoon") return 0
  return 0.3
}

export function usesVerticalLightboxForStyle(style: string): boolean {
  return style === "vertical" || style === "webtoon"
}

export function navigationScrollBehaviorForStyle(style: string, prefersReducedMotion: boolean): ScrollBehavior {
  if (prefersReducedMotion) return "instant"
  if (style === "left_to_right" || style === "right_to_left" || style === "vertical") return "smooth"
  return "instant"
}

export type VerticalPageRect = Pick<DOMRectReadOnly, "top" | "bottom">

export function resolveVisibleVerticalPageIndex(rects: VerticalPageRect[], viewportHeight: number): number | null {
  if (viewportHeight <= 0) return null

  let topmostVisibleIndex: number | null = null
  let topmostVisibleTop = Infinity

  rects.forEach((rect, index) => {
    const visibleHeight = Math.max(0, Math.min(rect.bottom, viewportHeight) - Math.max(rect.top, 0))
    if (visibleHeight <= 0) return

    if (rect.top < topmostVisibleTop) {
      topmostVisibleTop = rect.top
      topmostVisibleIndex = index
    }
  })

  return topmostVisibleIndex
}

export default class extends Controller {
  static targets = ["page", "viewport", "controls", "progressText", "progressBar", "progressPercent", "lightbox", "lightboxImage", "lightboxScroll", "lightboxStrip", "lightboxHint", "lightboxProgressText", "lightboxPanel", "nextChapterOverlay", "nextChapterCountdown"]
  static values = { style: String, pageCount: Number, initialPageIndex: Number, progressUrl: String, nextChapterUrl: String, nextChapterTitle: String }
  declare readonly pageTargets: HTMLElement[]
  declare readonly viewportTarget: HTMLElement
  declare readonly hasViewportTarget: boolean
  declare readonly controlsTarget: HTMLElement
  declare readonly hasControlsTarget: boolean
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
  declare readonly lightboxScrollTarget: HTMLElement
  declare readonly lightboxStripTarget: HTMLElement
  declare readonly hasLightboxScrollTarget: boolean
  declare readonly hasLightboxStripTarget: boolean
  declare readonly lightboxHintTarget: HTMLElement
  declare readonly lightboxProgressTextTarget: HTMLElement
  declare readonly hasLightboxHintTarget: boolean
  declare readonly hasLightboxProgressTextTarget: boolean
  declare readonly lightboxPanelTargets: HTMLElement[]
  declare readonly hasLightboxPanelTarget: boolean
  declare readonly nextChapterOverlayTarget: HTMLElement
  declare readonly nextChapterCountdownTarget: HTMLElement
  declare readonly hasNextChapterOverlayTarget: boolean
  declare readonly hasNextChapterCountdownTarget: boolean
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
  private readonly nextChapterPromptDelayMs = 500
  private pendingNextChapterPrompt?: ReturnType<typeof setTimeout>
  private nextChapterCountdownInterval?: ReturnType<typeof setInterval>
  private nextChapterCountdownValue = 5
  private hasInteracted = false // Don't auto-advance on initial page load
  private lightboxSwipePointerId: number | null = null
  private lightboxSwipeStartX = 0
  private lightboxSwipeStartY = 0
  private lightboxSwipeDeltaX = 0
  private lightboxSwipeDeltaY = 0
  private verticalLightboxObserver?: IntersectionObserver
  private verticalLightboxPagesByIndex: Array<HTMLElement | undefined> = []
  private lightboxHintFadeTimeout?: ReturnType<typeof setTimeout>
  private lightboxCloseTimeout?: ReturnType<typeof setTimeout>
  private lightboxImageSwapTimeout?: ReturnType<typeof setTimeout>
  private handleOnlineBound?: () => void
  private documentScrollFrame?: number
  private lastDocumentScrollY = 0
  private hasUserNavigated = false
  private initialScrollRetryTimeout?: ReturnType<typeof setTimeout>
  private initialScrollCleanup: Array<() => void> = []
  private readonly handleDocumentScroll = () => {
    if (this.documentScrollFrame) return

    this.documentScrollFrame = requestAnimationFrame(() => {
      this.documentScrollFrame = undefined
      this.syncControlsFromDocumentScroll()
      this.syncCurrentIndexFromDocumentScroll()
    })
  }

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.handleKeydown)
    this.handleOnlineBound = () => { void this.flushQueuedProgressUpdates() }
    window.addEventListener("online", this.handleOnlineBound)
    void this.flushQueuedProgressUpdates()
    
    if (this.pageTargets.length > 0) {
      const initialIndex = this.resolveInitialIndex()
      this.currentIndex = initialIndex
      this.prepareImagesForInitialScroll(initialIndex)
      // Use instant scroll on initial load
      this.scrollToIndex(this.currentIndex, "instant")
      this.observePages()
      this.setupDocumentScrollFallback()
      this.setupInitialScrollCorrection(initialIndex)
      // Force initial state sync after scroll
      requestAnimationFrame(() => this.syncState())
    }
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
    if (this.handleOnlineBound) window.removeEventListener("online", this.handleOnlineBound)
    this.observer?.disconnect()
    this.teardownDocumentScrollFallback()
    this.teardownVerticalLightbox()
    if (this.lightboxHintFadeTimeout) clearTimeout(this.lightboxHintFadeTimeout)
    if (this.lightboxCloseTimeout) clearTimeout(this.lightboxCloseTimeout)
    if (this.lightboxImageSwapTimeout) clearTimeout(this.lightboxImageSwapTimeout)
    if (this.pendingProgressSave) clearTimeout(this.pendingProgressSave)
    if (this.documentScrollFrame) cancelAnimationFrame(this.documentScrollFrame)
    this.teardownInitialScrollCorrection()
    this.clearPendingNextChapterPrompt()
    this.clearNextChapterCountdown()
  }

  private handleKeydown(event: KeyboardEvent) {
    // Don't handle if typing in an input
    if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) return
    
    if (event.key === "Escape" && this.lightboxOpen) {
      this.closeLightbox()
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
        this.hasUserNavigated = true
        this.previous()
      } else if (prevKeys.includes(event.key)) {
        event.preventDefault()
        this.hasUserNavigated = true
        this.next()
      }
    } else {
      if (nextKeys.includes(event.key)) {
        event.preventDefault()
        this.hasUserNavigated = true
        this.next()
      } else if (prevKeys.includes(event.key)) {
        event.preventDefault()
        this.hasUserNavigated = true
        this.previous()
      }
    }
  }

  // Action: click on a page to open lightbox at that page
  openLightboxForPage(event: Event) {
    const target = event.currentTarget as HTMLElement
    const index = this.pageTargets.indexOf(target)
    if (index >= 0) {
      this.hasUserNavigated = true
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
    if (!this.hasLightboxTarget) return
    this.lightboxOpen = true
    this.beginLightboxEnter()

    if (this.usesVerticalLightbox()) {
      this.setupVerticalLightbox()
      this.scrollVerticalLightboxToIndex(this.currentIndex, "instant")
      this.showVerticalLightboxHint()
    } else {
      this.updateLightboxImage()
    }

    document.body.style.overflow = "hidden"
  }

  closeLightbox(event?: Event) {
    event?.preventDefault()
    if (!this.hasLightboxTarget) return
    const shouldSyncVerticalFocus = this.usesVerticalLightbox()
    this.lightboxOpen = false
    this.resetLightboxSwipe()
    this.beginLightboxExit()
    document.body.style.overflow = ""
    if (this.lightboxHintFadeTimeout) clearTimeout(this.lightboxHintFadeTimeout)
    if (this.lightboxImageSwapTimeout) clearTimeout(this.lightboxImageSwapTimeout)
    if (shouldSyncVerticalFocus) {
      this.teardownVerticalLightbox()
      this.scrollToIndex(this.currentIndex, "instant")
    }
  }

  lightboxNext(event?: Event) {
    event?.preventDefault()
    event?.stopPropagation()
    // In RTL mode, the "next" button (right arrow) goes to previous page
    this.isHorizontal() && this.isRtl() ? this.previous() : this.next()
  }

  lightboxPrev(event?: Event) {
    event?.preventDefault()
    event?.stopPropagation()
    // In RTL mode, the "prev" button (left arrow) goes to next page
    this.isHorizontal() && this.isRtl() ? this.next() : this.previous()
  }

  lightboxPointerDown(event: PointerEvent) {
    if (!this.lightboxOpen || event.pointerType !== "touch" || this.usesVerticalLightbox()) return

    this.lightboxSwipePointerId = event.pointerId
    this.lightboxSwipeStartX = event.clientX
    this.lightboxSwipeStartY = event.clientY
    this.lightboxSwipeDeltaX = 0
    this.lightboxSwipeDeltaY = 0
  }

  lightboxPointerMove(event: PointerEvent) {
    if (!this.isTrackingLightboxSwipe(event)) return

    this.lightboxSwipeDeltaX = event.clientX - this.lightboxSwipeStartX
    this.lightboxSwipeDeltaY = event.clientY - this.lightboxSwipeStartY
  }

  lightboxPointerUp(event: PointerEvent) {
    if (!this.isTrackingLightboxSwipe(event)) return
    if (this.usesVerticalLightbox()) {
      this.resetLightboxSwipe()
      return
    }

    const swipeAction = resolveLightboxSwipeAction(this.lightboxSwipeDeltaX, this.lightboxSwipeDeltaY)
    const isTap = Math.abs(this.lightboxSwipeDeltaX) < 14 && Math.abs(this.lightboxSwipeDeltaY) < 14
    this.resetLightboxSwipe()

    if (swipeAction) {
      event.preventDefault()
      event.stopPropagation()
      swipeAction === "next" ? this.lightboxNext() : this.lightboxPrev()
      return
    }

    if (!isTap) return

    const tapAction = this.resolveTouchTapZoneAction(event)
    if (!tapAction) return

    event.preventDefault()
    event.stopPropagation()
    if (tapAction === "next") {
      this.lightboxNext()
    } else if (tapAction === "previous") {
      this.lightboxPrev()
    } else {
      this.closeLightbox()
    }
  }

  lightboxPointerCancel(_event: PointerEvent) {
    this.resetLightboxSwipe()
  }

  private isTrackingLightboxSwipe(event: PointerEvent) {
    return this.lightboxSwipePointerId !== null && event.pointerId === this.lightboxSwipePointerId
  }

  private resetLightboxSwipe() {
    this.lightboxSwipePointerId = null
    this.lightboxSwipeDeltaX = 0
    this.lightboxSwipeDeltaY = 0
  }

  private resolveTouchTapZoneAction(event: PointerEvent) {
    // Let explicit controls (close/arrow buttons) handle their own clicks.
    if (event.target instanceof HTMLElement && event.target.closest("button, a")) return null
    if (!this.hasLightboxTarget || this.usesVerticalLightbox()) return null

    const rect = this.lightboxTarget.getBoundingClientRect()
    return resolveLightboxTapZoneAction(event.clientX, rect.left, rect.width)
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
    this.hasUserNavigated = true
    this.hasInteracted = true
    const nextIndex = this.currentIndex + 1
    const navigationBehavior = this.navigationScrollBehavior()
    if (nextIndex >= this.pageTargets.length) {
      // Past last page — require an explicit next attempt, then prompt.
      if (this.lightboxOpen) this.closeLightbox()
      this.queueNextChapterOverlay()
      return
    }
    if (this.lightboxOpen && this.usesVerticalLightbox()) {
      this.scrollVerticalLightboxToIndex(nextIndex, navigationBehavior)
      return
    }
    if (this.lightboxOpen) {
      // Keep keyboard-driven lightbox navigation deterministic; panel animation
      // is handled by the lightbox image transition itself.
      this.scrollToIndex(nextIndex, "instant")
      return
    }
    this.scrollToIndex(nextIndex, navigationBehavior)
  }

  previous() {
    this.hasUserNavigated = true
    this.hasInteracted = true
    const navigationBehavior = this.navigationScrollBehavior()
    if (this.lightboxOpen && this.usesVerticalLightbox()) {
      this.scrollVerticalLightboxToIndex(this.currentIndex - 1, navigationBehavior)
      return
    }
    if (this.lightboxOpen) {
      this.scrollToIndex(this.currentIndex - 1, "instant")
      return
    }
    this.scrollToIndex(this.currentIndex - 1, navigationBehavior)
  }

  private scrollToIndex(index: number, behavior: ScrollBehavior = "instant") {
    if (index < 0 || index >= this.pageTargets.length) return
    
    // Lock to prevent observer from interfering
    this.isScrolling = true
    this.currentIndex = index
    
    const block = (this.isHorizontal() || this.isPagedVertical()) ? "nearest" : "start"
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

  private isPagedVertical() {
    return this.styleValue === "vertical"
  }

  private isRtl() {
    // Check both the style value and the data attribute on viewport
    if (this.styleValue === "right_to_left") return true
    if (this.hasViewportTarget) {
      return this.viewportTarget.dataset.readerRtl === "true"
    }
    return false
  }

  private usesVerticalLightbox() {
    return usesVerticalLightboxForStyle(this.styleValue)
  }

  private navigationScrollBehavior(): ScrollBehavior {
    return navigationScrollBehaviorForStyle(this.styleValue, this.prefersReducedMotion())
  }

  private prefersReducedMotion(): boolean {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false
  }

  private lightboxTransitionDurationMs() {
    return this.prefersReducedMotion() ? 0 : 220
  }

  private beginLightboxEnter() {
    if (!this.hasLightboxTarget) return

    if (this.lightboxCloseTimeout) clearTimeout(this.lightboxCloseTimeout)
    this.lightboxTarget.classList.remove("hidden")
    this.lightboxTarget.classList.add("flex")

    if (this.prefersReducedMotion()) {
      this.lightboxTarget.classList.remove("opacity-0")
      this.lightboxPanelTargets.forEach((panel) => {
        panel.classList.remove("opacity-0", "scale-[0.98]", "translate-y-1")
      })
      return
    }

    requestAnimationFrame(() => {
      this.lightboxTarget.classList.remove("opacity-0")
      this.lightboxPanelTargets.forEach((panel) => {
        panel.classList.remove("opacity-0", "scale-[0.98]", "translate-y-1")
      })
    })
  }

  private beginLightboxExit() {
    if (!this.hasLightboxTarget) return

    if (this.lightboxCloseTimeout) clearTimeout(this.lightboxCloseTimeout)

    this.lightboxTarget.classList.add("opacity-0")
    this.lightboxPanelTargets.forEach((panel) => {
      panel.classList.add("opacity-0")
      if (this.hasLightboxImageTarget && panel === this.lightboxImageTarget) {
        panel.classList.add("scale-[0.98]")
      } else {
        panel.classList.add("translate-y-1")
      }
    })

    this.lightboxCloseTimeout = setTimeout(() => {
      this.lightboxTarget.classList.add("hidden")
      this.lightboxTarget.classList.remove("flex")
    }, this.lightboxTransitionDurationMs())
  }

  private showVerticalLightboxHint() {
    if (!this.hasLightboxHintTarget) return

    if (this.lightboxHintFadeTimeout) clearTimeout(this.lightboxHintFadeTimeout)
    this.lightboxHintTarget.classList.remove("opacity-0")

    this.lightboxHintFadeTimeout = setTimeout(() => {
      this.lightboxHintTarget.classList.add("opacity-0")
    }, 2200)
  }

  private setupVerticalLightbox() {
    if (!this.hasLightboxScrollTarget || !this.hasLightboxStripTarget) return

    this.teardownVerticalLightbox()
    this.lightboxStripTarget.innerHTML = ""
    this.verticalLightboxPagesByIndex = []

    this.pageTargets.forEach((page, index) => {
      const sourceImage = page.querySelector("img") as HTMLImageElement | null
      if (!sourceImage) return

      const figure = document.createElement("figure")
      figure.className = "mx-auto w-full max-w-4xl"
      figure.dataset.readerLightboxIndex = index.toString()

      const image = document.createElement("img")
      image.src = sourceImage.currentSrc || sourceImage.src
      image.alt = sourceImage.alt || `Reader page ${index + 1}`
      image.className = "w-full max-w-full object-contain rounded-md shadow-2xl"
      image.loading = Math.abs(index - this.currentIndex) <= 1 ? "eager" : "lazy"
      image.decoding = "async"

      figure.appendChild(image)
      this.lightboxStripTarget.appendChild(figure)
      this.verticalLightboxPagesByIndex[index] = figure
    })

    this.verticalLightboxObserver = new IntersectionObserver(
      (entries) => {
        if (!this.lightboxOpen || this.isScrolling || !this.hasLightboxScrollTarget) return

        const rootTop = this.lightboxScrollTarget.getBoundingClientRect().top
        let bestEntry: IntersectionObserverEntry | null = null
        let bestDistance = Infinity

        for (const entry of entries) {
          if (!entry.isIntersecting) continue
          const distance = Math.abs(entry.boundingClientRect.top - rootTop)
          if (distance < bestDistance) {
            bestDistance = distance
            bestEntry = entry
          }
        }

        if (!bestEntry) return

        const rawIndex = (bestEntry.target as HTMLElement).dataset.readerLightboxIndex
        const index = Number.parseInt(rawIndex || "", 10)
        if (!Number.isFinite(index) || index === this.currentIndex) return

        this.hasInteracted = true
        this.currentIndex = index
        this.syncState()
      },
      { root: this.lightboxScrollTarget, threshold: 0 }
    )

    this.verticalLightboxPagesByIndex.forEach((page) => {
      if (page) this.verticalLightboxObserver?.observe(page)
    })
  }

  private teardownVerticalLightbox() {
    this.verticalLightboxObserver?.disconnect()
    this.verticalLightboxObserver = undefined
    this.verticalLightboxPagesByIndex = []

    if (this.hasLightboxStripTarget) {
      this.lightboxStripTarget.innerHTML = ""
    }
  }

  private scrollVerticalLightboxToIndex(index: number, behavior: ScrollBehavior = "smooth") {
    if (index < 0 || index >= this.pageTargets.length) return

    const target = this.verticalLightboxPagesByIndex[index]
    if (!target) return

    this.isScrolling = true
    this.currentIndex = index

    target.scrollIntoView({ behavior, block: "start", inline: "nearest" })
    this.syncState()

    const unlockDelay = behavior === "smooth" ? 500 : 50
    setTimeout(() => {
      this.isScrolling = false
    }, unlockDelay)
  }

  private observePages() {
    if (this.pageTargets.length === 0) return
    
    // For horizontal + paged-vertical modes, observe against the scrolling viewport container
    // For vertical modes, use browser viewport (null) since the whole page scrolls
    const usesViewportRoot = this.isHorizontal() || this.isPagedVertical()
    const root = usesViewportRoot && this.hasViewportTarget ? this.viewportTarget : null
    
    const threshold = observerThresholdForStyle(this.styleValue)
    const minVerticalIntersectionRatio = this.styleValue === "webtoon" ? 0 : 0.3
    
    this.observer = new IntersectionObserver(
      (entries) => {
        // Skip if we're in the middle of a programmatic scroll
        if (this.isScrolling) return
        // While lightbox is open, keyboard/lightbox observers own current page state.
        if (this.lightboxOpen) return
        
        if (this.isHorizontal() || this.isPagedVertical()) {
          // Paged modes: find the most visible page panel.
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
            if (entry.isIntersecting && entry.intersectionRatio >= minVerticalIntersectionRatio) {
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

  private prepareImagesForInitialScroll(index: number) {
    if (index <= 0) return

    this.pageTargets.slice(0, index + 1).forEach((page) => {
      const image = page.querySelector("img") as HTMLImageElement | null
      if (!image) return
      if (image.loading === "lazy") image.loading = "eager"
    })
  }

  private setupInitialScrollCorrection(index: number) {
    this.teardownInitialScrollCorrection()
    if (index <= 0 || index >= this.pageTargets.length) return

    const pendingImages = this.pageTargets
      .slice(0, index + 1)
      .map((page) => page.querySelector("img") as HTMLImageElement | null)
      .filter((image): image is HTMLImageElement => Boolean(image) && (!image.complete || image.naturalHeight === 0))

    const correctInitialScroll = () => {
      if (this.hasUserNavigated || this.lightboxOpen) return
      this.scrollToIndex(index, "instant")
    }

    if (pendingImages.length === 0) {
      requestAnimationFrame(correctInitialScroll)
      return
    }

    let remaining = pendingImages.length
    const markImageSettled = () => {
      remaining -= 1
      if (remaining <= 0) correctInitialScroll()
    }

    pendingImages.forEach((image) => {
      image.addEventListener("load", markImageSettled, { once: true })
      image.addEventListener("error", markImageSettled, { once: true })
      this.initialScrollCleanup.push(() => {
        image.removeEventListener("load", markImageSettled)
        image.removeEventListener("error", markImageSettled)
      })
    })

    this.initialScrollRetryTimeout = setTimeout(correctInitialScroll, 2500)
  }

  private teardownInitialScrollCorrection() {
    if (this.initialScrollRetryTimeout) clearTimeout(this.initialScrollRetryTimeout)
    this.initialScrollRetryTimeout = undefined
    this.initialScrollCleanup.forEach((cleanup) => cleanup())
    this.initialScrollCleanup = []
  }

  private setupDocumentScrollFallback() {
    if (this.isHorizontal() || this.isPagedVertical()) return
    this.lastDocumentScrollY = this.documentScrollY()
    window.addEventListener("scroll", this.handleDocumentScroll, { passive: true })
  }

  private teardownDocumentScrollFallback() {
    window.removeEventListener("scroll", this.handleDocumentScroll)
  }

  private syncCurrentIndexFromDocumentScroll() {
    if (this.isScrolling || this.lightboxOpen || this.pageTargets.length === 0) return

    const index = resolveVisibleVerticalPageIndex(
      this.pageTargets.map((page) => page.getBoundingClientRect()),
      window.innerHeight
    )

    if (index === null || index === this.currentIndex) return

    this.hasInteracted = true
    this.currentIndex = index
    this.syncState()
  }

  private syncControlsFromDocumentScroll() {
    if (!this.hasControlsTarget) return

    const scrollY = this.documentScrollY()
    const delta = scrollY - this.lastDocumentScrollY
    this.lastDocumentScrollY = scrollY

    if (!this.isScrolling && Math.abs(delta) > 8) {
      this.hasUserNavigated = true
    }

    if (this.isScrolling || this.lightboxOpen || scrollY < 80) {
      this.showControls()
      return
    }

    if (delta > 8) {
      this.hideControls()
    } else if (delta < -8) {
      this.showControls()
    }
  }

  private documentScrollY() {
    return document.documentElement.scrollTop || document.body.scrollTop || 0
  }

  private hideControls() {
    if (!this.hasControlsTarget) return
    this.controlsTarget.classList.add("scanarr-reader-controls--hidden")
  }

  private showControls() {
    if (!this.hasControlsTarget) return
    this.controlsTarget.classList.remove("scanarr-reader-controls--hidden")
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
    }
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
    if (this.hasLightboxProgressTextTarget) {
      this.lightboxProgressTextTarget.textContent = `Page ${pageIndex} / ${pageCount} (${percent}%)`
    }

    if (this.lightboxOpen && !this.usesVerticalLightbox()) {
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
    const nextSrc = image.currentSrc || image.src
    const currentSrc = this.lightboxImageTarget.currentSrc || this.lightboxImageTarget.src

    if (this.lightboxImageSwapTimeout) clearTimeout(this.lightboxImageSwapTimeout)
    if (!this.prefersReducedMotion() && currentSrc && currentSrc !== nextSrc) {
      this.lightboxImageTarget.classList.add("opacity-0")
      this.lightboxImageSwapTimeout = setTimeout(() => {
        this.lightboxImageTarget.src = nextSrc
        this.lightboxImageTarget.classList.remove("opacity-0")
      }, 90)
    } else {
      this.lightboxImageTarget.src = nextSrc
      this.lightboxImageTarget.classList.remove("opacity-0")
    }

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
      .then(async (response) => {
        if (!response.ok) {
          await enqueueProgressUpdate({
            progressUrl: this.progressUrlValue,
            pageIndex,
            pageCount
          })
        }
      })
      .catch(async (error) => {
        console.warn("Failed to save reading progress:", error)
        await enqueueProgressUpdate({
          progressUrl: this.progressUrlValue,
          pageIndex,
          pageCount
        })
      })
  }

  private async flushQueuedProgressUpdates() {
    if (!navigator.onLine) return

    const token = document
      .querySelector('meta[name="csrf-token"]')
      ?.getAttribute("content")

    await flushQueuedProgress(token || "")
  }

  // Keep next-chapter prompt state in sync with current location in chapter.
  // Showing is gated behind an explicit next-at-end action via queueNextChapterOverlay().
  private checkEndOfChapter() {
    if (!this.hasNextChapterUrlValue || !this.nextChapterUrlValue) return
    if (!this.hasInteracted) return

    const isLastPage = this.currentIndex === this.pageTargets.length - 1

    if (!isLastPage) {
      this.hideNextChapterOverlay()
    }
  }

  private queueNextChapterOverlay() {
    if (!this.hasNextChapterUrlValue || !this.nextChapterUrlValue) return
    if (!this.hasInteracted) return
    if (this.currentIndex !== this.pageTargets.length - 1) return
    if (this.pendingNextChapterPrompt) return

    if (this.hasNextChapterOverlayTarget && !this.nextChapterOverlayTarget.classList.contains("hidden")) return

    this.pendingNextChapterPrompt = setTimeout(() => {
      this.pendingNextChapterPrompt = undefined

      // User may have moved away from the end before the delay elapsed.
      if (this.currentIndex !== this.pageTargets.length - 1) return
      if (!this.hasInteracted) return

      this.showNextChapterOverlay()
    }, this.nextChapterPromptDelayMs)
  }

  private showNextChapterOverlay() {
    if (!this.hasNextChapterOverlayTarget) return
    
    this.nextChapterOverlayTarget.classList.remove("hidden")
    this.nextChapterOverlayTarget.classList.add("flex")
    
    // Start countdown for auto-navigation
    this.startNextChapterCountdown()
  }

  private hideNextChapterOverlay() {
    this.clearPendingNextChapterPrompt()
    if (!this.hasNextChapterOverlayTarget) return
    
    this.nextChapterOverlayTarget.classList.add("hidden")
    this.nextChapterOverlayTarget.classList.remove("flex")
    
    this.clearNextChapterCountdown()
  }

  private clearPendingNextChapterPrompt() {
    if (!this.pendingNextChapterPrompt) return
    clearTimeout(this.pendingNextChapterPrompt)
    this.pendingNextChapterPrompt = undefined
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
}

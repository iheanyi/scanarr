import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["page", "viewport", "progressText", "progressBar", "progressPercent", "lightbox", "lightboxImage"]
  static values = { style: String, pageCount: Number, initialPageIndex: Number, progressUrl: String }
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
  declare readonly styleValue: string
  declare readonly pageCountValue: number
  declare readonly initialPageIndexValue: number
  declare readonly progressUrlValue: string
  declare readonly hasProgressUrlValue: boolean

  private currentIndex = 0
  private observer?: IntersectionObserver
  private lastReportedIndex = -1
  private lightboxOpen = false
  private pendingProgressSave?: ReturnType<typeof setTimeout>
  private isScrolling = false // Lock to prevent observer interference during programmatic scroll

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.handleKeydown)
    
    if (this.pageTargets.length > 0) {
      this.currentIndex = this.resolveInitialIndex()
      // Use instant scroll on initial load
      this.scrollToIndex(this.currentIndex, "instant")
      this.observePages()
      // Force initial state sync after scroll
      requestAnimationFrame(() => this.syncState())
    }
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleKeydown)
    this.observer?.disconnect()
    if (this.pendingProgressSave) clearTimeout(this.pendingProgressSave)
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
    this.scrollToIndex(this.currentIndex + 1)
  }

  previous() {
    this.scrollToIndex(this.currentIndex - 1)
  }

  private scrollToIndex(index: number, behavior: ScrollBehavior = "instant") {
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
    // Update URL last - it can fail with credentials in URL (browser security)
    try {
      this.updateURL()
    } catch {
      // Ignore SecurityError when URL contains credentials
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
    }).catch((error) => {
      console.warn("Failed to save reading progress:", error)
    })
  }
}

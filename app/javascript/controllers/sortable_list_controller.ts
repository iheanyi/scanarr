import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "input"]

  declare itemTargets: HTMLElement[]
  declare inputTarget: HTMLInputElement
  declare hasInputTarget: boolean

  private draggedItem: HTMLElement | null = null

  connect() {
    this.itemTargets.forEach((item) => {
      item.setAttribute("draggable", "true")
      item.addEventListener("dragstart", this.handleDragStart.bind(this))
      item.addEventListener("dragover", this.handleDragOver.bind(this))
      item.addEventListener("dragend", this.handleDragEnd.bind(this))
      item.addEventListener("drop", this.handleDrop.bind(this))
    })
  }

  handleDragStart(event: DragEvent) {
    this.draggedItem = event.currentTarget as HTMLElement
    this.draggedItem.classList.add("opacity-50")
    event.dataTransfer!.effectAllowed = "move"
  }

  handleDragOver(event: DragEvent) {
    event.preventDefault()
    event.dataTransfer!.dropEffect = "move"

    const target = (event.currentTarget as HTMLElement)
    if (target !== this.draggedItem) {
      target.classList.add("border-t-2", "border-accent")
    }
  }

  handleDrop(event: DragEvent) {
    event.preventDefault()
    const target = event.currentTarget as HTMLElement
    target.classList.remove("border-t-2", "border-accent")

    if (this.draggedItem && target !== this.draggedItem) {
      const parent = target.parentNode!
      const items = Array.from(parent.children)
      const draggedIndex = items.indexOf(this.draggedItem)
      const targetIndex = items.indexOf(target)

      if (draggedIndex < targetIndex) {
        parent.insertBefore(this.draggedItem, target.nextSibling)
      } else {
        parent.insertBefore(this.draggedItem, target)
      }

      this.updateOrder()
    }
  }

  handleDragEnd(_event: DragEvent) {
    if (this.draggedItem) {
      this.draggedItem.classList.remove("opacity-50")
      this.draggedItem = null
    }

    this.itemTargets.forEach((item) => {
      item.classList.remove("border-t-2", "border-accent")
    })
  }

  moveUp(event: Event) {
    const item = (event.currentTarget as HTMLElement).closest("[data-sortable-list-target='item']") as HTMLElement
    const prev = item.previousElementSibling as HTMLElement | null
    if (prev) {
      item.parentNode!.insertBefore(item, prev)
      this.updateOrder()
    }
  }

  moveDown(event: Event) {
    const item = (event.currentTarget as HTMLElement).closest("[data-sortable-list-target='item']") as HTMLElement
    const next = item.nextElementSibling as HTMLElement | null
    if (next) {
      item.parentNode!.insertBefore(next, item)
      this.updateOrder()
    }
  }

  private updateOrder() {
    const keys = this.itemTargets.map((item) => item.dataset.sourceKey).filter(Boolean)

    if (this.hasInputTarget) {
      this.inputTarget.value = JSON.stringify(keys)
    }

    // Auto-submit the closest form
    const form = this.element.closest("form")
    if (form) {
      form.requestSubmit()
    }
  }
}

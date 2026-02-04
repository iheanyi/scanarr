import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]
  static values = {
    active: Boolean,
    activeLabel: String,
    inactiveLabel: String,
    hoverLabel: String
  }

  declare readonly labelTarget: HTMLElement
  declare readonly hasLabelTarget: boolean
  declare activeValue: boolean
  declare readonly activeLabelValue: string
  declare readonly inactiveLabelValue: string
  declare readonly hoverLabelValue: string
  declare readonly hasHoverLabelValue: boolean

  connect() {
    this.updateLabel()
  }

  showHover() {
    if (!this.hasLabelTarget) return
    if (this.activeValue && this.hasHoverLabelValue) {
      this.labelTarget.textContent = this.hoverLabelValue
    }
  }

  showDefault() {
    this.updateLabel()
  }

  private updateLabel() {
    if (!this.hasLabelTarget) return
    this.labelTarget.textContent = this.activeValue ? this.activeLabelValue : this.inactiveLabelValue
  }
}

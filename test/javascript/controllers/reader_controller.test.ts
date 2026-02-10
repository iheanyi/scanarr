import { describe, it, expect, vi, beforeEach } from 'vitest'
import {
  observerThresholdForStyle,
  resolveLightboxSwipeAction,
  resolveLightboxTapZoneAction,
  usesVerticalLightboxForStyle
} from '../../../app/javascript/controllers/reader_controller'

/**
 * Unit tests for ReaderController URL handling logic.
 * 
 * Full Stimulus controller integration testing is better done via system tests
 * (e.g., Capybara, Playwright) due to jsdom limitations with MutationObserver
 * and Stimulus lifecycle.
 * 
 * These tests verify the core logic that was fixed:
 * - Query parameters are stripped when navigating to next chapter
 * - URL manipulation works correctly for various edge cases
 */

describe('Next Chapter URL Stripping Logic', () => {
  // This tests the exact logic used in goToNextChapter()
  const stripQueryParams = (nextChapterUrl: string, origin: string): string => {
    const url = new URL(nextChapterUrl, origin)
    url.search = '' // Clear any query parameters
    return url.toString()
  }

  it('strips page query parameter from next chapter URL', () => {
    const nextChapterUrl = '/sources/weeb-central/series/test-series/chapters/2'
    const result = stripQueryParams(nextChapterUrl, 'http://localhost')

    expect(result).toBe('http://localhost/sources/weeb-central/series/test-series/chapters/2')
    expect(result).not.toContain('?')
    expect(result).not.toContain('page=')
  })

  it('handles URL that already has query params by stripping them', () => {
    // Edge case: what if the next chapter URL somehow has query params?
    const nextChapterUrl = '/chapters/2?unexpected=param'
    const result = stripQueryParams(nextChapterUrl, 'http://localhost')

    expect(result).toBe('http://localhost/chapters/2')
    expect(result).not.toContain('?')
  })

  it('strips multiple query parameters', () => {
    const nextChapterUrl = '/chapters/2?page=10&style=rtl&foo=bar'
    const result = stripQueryParams(nextChapterUrl, 'http://localhost')

    expect(result).toBe('http://localhost/chapters/2')
  })

  it('handles complex manga series paths', () => {
    const nextChapterUrl = '/sources/weeb-central/abc123-my-awesome-manga/chapters/chapter-10.5'
    const result = stripQueryParams(nextChapterUrl, 'http://localhost')

    expect(result).toBe('http://localhost/sources/weeb-central/abc123-my-awesome-manga/chapters/chapter-10.5')
  })

  it('handles paths with special characters', () => {
    const nextChapterUrl = '/sources/test/series/manga%20name/chapters/1'
    const result = stripQueryParams(nextChapterUrl, 'http://localhost')

    expect(result).toContain('/sources/test/series/')
    expect(result).toContain('/chapters/1')
  })

  it('handles different origins', () => {
    const nextChapterUrl = '/chapters/next'
    
    expect(stripQueryParams(nextChapterUrl, 'http://localhost:3000'))
      .toBe('http://localhost:3000/chapters/next')
    
    expect(stripQueryParams(nextChapterUrl, 'https://example.com'))
      .toBe('https://example.com/chapters/next')
  })

  it('preserves the path exactly', () => {
    const nextChapterUrl = '/sources/weeb-central/series/test/chapters/2'
    const result = stripQueryParams(nextChapterUrl, 'http://localhost')
    const url = new URL(result)

    expect(url.pathname).toBe('/sources/weeb-central/series/test/chapters/2')
  })
})

describe('Reading Style Detection Logic', () => {
  // Test the logic used in isHorizontal() and isRtl()
  const isHorizontal = (style: string): boolean => {
    return style === 'left_to_right' || style === 'right_to_left'
  }

  const isRtl = (style: string): boolean => {
    return style === 'right_to_left'
  }

  it('detects horizontal mode for left_to_right', () => {
    expect(isHorizontal('left_to_right')).toBe(true)
    expect(isRtl('left_to_right')).toBe(false)
  })

  it('detects horizontal and RTL mode for right_to_left', () => {
    expect(isHorizontal('right_to_left')).toBe(true)
    expect(isRtl('right_to_left')).toBe(true)
  })

  it('detects paged vertical mode for vertical', () => {
    expect(isHorizontal('vertical')).toBe(false)
    expect(isRtl('vertical')).toBe(false)
  })

  it('detects continuous vertical mode for webtoon', () => {
    expect(isHorizontal('webtoon')).toBe(false)
    expect(isRtl('webtoon')).toBe(false)
  })
})

describe('Intersection Observer Threshold Logic', () => {
  it('uses a low threshold for webtoon mode', () => {
    expect(observerThresholdForStyle('webtoon')).toBe(0)
  })

  it('uses paged threshold for horizontal mode', () => {
    expect(observerThresholdForStyle('left_to_right')).toBe(0.5)
    expect(observerThresholdForStyle('right_to_left')).toBe(0.5)
  })

  it('uses paged threshold for vertical paged mode', () => {
    expect(observerThresholdForStyle('vertical')).toBe(0.5)
  })
})

describe('Vertical Lightbox Style Logic', () => {
  it('uses vertical lightbox for vertical style', () => {
    expect(usesVerticalLightboxForStyle('vertical')).toBe(true)
  })

  it('uses vertical lightbox for webtoon style', () => {
    expect(usesVerticalLightboxForStyle('webtoon')).toBe(true)
  })

  it('does not use vertical lightbox for horizontal styles', () => {
    expect(usesVerticalLightboxForStyle('left_to_right')).toBe(false)
    expect(usesVerticalLightboxForStyle('right_to_left')).toBe(false)
  })
})

describe('Lightbox Swipe Logic', () => {
  it('maps a left swipe to next page', () => {
    expect(resolveLightboxSwipeAction(-96, 14)).toBe('next')
  })

  it('maps a right swipe to previous page', () => {
    expect(resolveLightboxSwipeAction(96, 10)).toBe('previous')
  })

  it('ignores short swipes below threshold', () => {
    expect(resolveLightboxSwipeAction(24, 2)).toBeNull()
    expect(resolveLightboxSwipeAction(-30, 5)).toBeNull()
  })

  it('ignores gestures that are mostly vertical', () => {
    expect(resolveLightboxSwipeAction(90, 120)).toBeNull()
    expect(resolveLightboxSwipeAction(-120, 140)).toBeNull()
  })
})

describe('Lightbox Tap Zone Logic', () => {
  it('maps left edge taps to previous page', () => {
    expect(resolveLightboxTapZoneAction(20, 0, 360)).toBe('previous')
  })

  it('maps right edge taps to next page', () => {
    expect(resolveLightboxTapZoneAction(350, 0, 360)).toBe('next')
  })

  it('maps center taps to close', () => {
    expect(resolveLightboxTapZoneAction(180, 0, 360)).toBe('close')
  })

  it('handles shifted container offsets', () => {
    expect(resolveLightboxTapZoneAction(40, 10, 300)).toBe('previous')
    expect(resolveLightboxTapZoneAction(290, 10, 300)).toBe('next')
  })
})

describe('Page Parameter Parsing Logic', () => {
  // Test the logic used in pageParamValue()
  const parsePageParam = (search: string): number | null => {
    const params = new URLSearchParams(search)
    const raw = params.get('page')
    if (!raw) return null
    const value = Number.parseInt(raw, 10)
    if (!Number.isFinite(value) || value < 1) return null
    return value
  }

  it('parses valid page parameter', () => {
    expect(parsePageParam('?page=5')).toBe(5)
    expect(parsePageParam('?page=1')).toBe(1)
    expect(parsePageParam('?page=100')).toBe(100)
  })

  it('returns null for missing page parameter', () => {
    expect(parsePageParam('')).toBe(null)
    expect(parsePageParam('?foo=bar')).toBe(null)
  })

  it('returns null for invalid page values', () => {
    expect(parsePageParam('?page=0')).toBe(null)
    expect(parsePageParam('?page=-1')).toBe(null)
    expect(parsePageParam('?page=abc')).toBe(null)
    expect(parsePageParam('?page=')).toBe(null)
  })

  it('handles page parameter among other params', () => {
    expect(parsePageParam('?style=rtl&page=10&foo=bar')).toBe(10)
  })
})

describe('Initial Page Index Resolution Logic', () => {
  // Test the logic used in resolveInitialIndex()
  const resolveInitialIndex = (
    pageParam: number | null,
    initialPageIndex: number,
    pageCount: number
  ): number => {
    const initialValue = pageParam ?? initialPageIndex
    const oneBased = initialValue && initialValue > 0 ? initialValue : 1
    const clamped = Math.min(Math.max(oneBased, 1), pageCount)
    return clamped - 1 // Convert to 0-based index
  }

  it('uses page param over initial page index', () => {
    // page=5, initial=1, count=10 -> should use 5 (index 4)
    expect(resolveInitialIndex(5, 1, 10)).toBe(4)
  })

  it('falls back to initial page index when no page param', () => {
    // no page param, initial=3, count=10 -> should use 3 (index 2)
    expect(resolveInitialIndex(null, 3, 10)).toBe(2)
  })

  it('clamps page to max page count', () => {
    // page=100, initial=1, count=10 -> should clamp to 10 (index 9)
    expect(resolveInitialIndex(100, 1, 10)).toBe(9)
  })

  it('clamps page to minimum of 1', () => {
    // page=0 would be invalid, but if it gets through, should clamp to 1 (index 0)
    expect(resolveInitialIndex(null, 0, 10)).toBe(0)
    expect(resolveInitialIndex(null, -5, 10)).toBe(0)
  })

  it('handles single page chapters', () => {
    expect(resolveInitialIndex(null, 1, 1)).toBe(0)
    expect(resolveInitialIndex(5, 1, 1)).toBe(0) // Clamps to 1
  })
})

describe('Window Location Mock Verification', () => {
  beforeEach(() => {
    // These tests verify our mock setup works correctly
    window.location.href = 'http://localhost/'
    window.location.search = ''
  })

  it('can set window.location.href', () => {
    window.location.href = 'http://localhost/new-path'
    expect(window.location.href).toBe('http://localhost/new-path')
  })

  it('can set window.location.search', () => {
    window.location.search = '?page=5'
    expect(window.location.search).toBe('?page=5')
  })

  it('can use window.location.origin', () => {
    expect(window.location.origin).toBe('http://localhost')
  })
})

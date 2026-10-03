'use client';

import { useEffect, useRef, useState } from 'react';

const slides = [
  { file: 6, title: 'Track it', detail: 'Your day, at a glance.', alt: 'Cave Cals daily diary showing calories, macros, and logged foods' },
  { file: 2, title: 'Snap it', detail: 'A photo. A food log.', alt: 'Meal Scan estimating a plate of chicken, sweet potatoes, and broccoli' },
  { file: 3, title: 'Scan it', detail: 'Barcode. Calories. Done.', alt: 'Barcode Scan looking up a bag of almonds' },
  { file: 4, title: 'Say it', detail: 'Tell app what you ate.', alt: 'Voice logging listening to a spoken meal description' },
  { file: 5, title: 'Find it', detail: 'Your food, a few taps away.', alt: 'Food search showing egg dishes and their calories' },
  { file: 7, title: 'See progress', detail: 'Meet your weekly recap.', alt: 'Weekly Recap showing weight trends and average daily calories' },
  { file: 1, title: 'Start simple', detail: 'Build a plan. Or just log.', alt: 'Cave Cals welcome screen with Build Plan and Just start tracking' },
];

export default function ScreenshotCarousel() {
  const [active, setActive] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(true);
  const [visible, setVisible] = useState(true);
  const touchStart = useRef<number | null>(null);

  useEffect(() => {
    const media = window.matchMedia('(prefers-reduced-motion: reduce)');
    const updateMotion = () => setReducedMotion(media.matches);
    const updateVisibility = () => setVisible(!document.hidden);
    updateMotion();
    updateVisibility();
    media.addEventListener('change', updateMotion);
    document.addEventListener('visibilitychange', updateVisibility);
    return () => {
      media.removeEventListener('change', updateMotion);
      document.removeEventListener('visibilitychange', updateVisibility);
    };
  }, []);

  const rotating = playing && !hovered && !focused && !reducedMotion && visible;
  useEffect(() => {
    if (!rotating) return;
    const timer = window.setInterval(() => setActive(index => (index + 1) % slides.length), 5500);
    return () => window.clearInterval(timer);
  }, [rotating]);

  function select(index: number) {
    setActive((index + slides.length) % slides.length);
    setPlaying(false);
  }

  return <section className="carousel" aria-label="Explore Cave Cals" aria-roledescription="carousel"
    onMouseEnter={() => setHovered(true)} onMouseLeave={() => setHovered(false)}
    onFocusCapture={() => setFocused(true)}
    onBlurCapture={event => { if (!event.currentTarget.contains(event.relatedTarget)) setFocused(false); }}
    onKeyDown={event => {
      if (event.key === 'ArrowRight') { event.preventDefault(); select(active + 1); }
      if (event.key === 'ArrowLeft') { event.preventDefault(); select(active - 1); }
    }}>
    <div className="slide-stage"
      onTouchStart={event => { touchStart.current = event.touches[0].clientX; }}
      onTouchEnd={event => {
        if (touchStart.current !== null) {
          const distance = event.changedTouches[0].clientX - touchStart.current;
          if (Math.abs(distance) > 45) select(active + (distance < 0 ? 1 : -1));
        }
        touchStart.current = null;
      }} onTouchCancel={() => { touchStart.current = null; }}>
      {slides.map((slide, index) => <div className={`slide ${index === active ? 'is-active' : ''}`} key={slide.file}
        role="group" aria-roledescription="slide" aria-label={`${index + 1} of ${slides.length}: ${slide.title}`} aria-hidden={index !== active}>
        <img src={`/screenshots/slide${slide.file}.webp`} width="900" height="1948" alt={slide.alt}
          loading={index < 2 ? 'eager' : 'lazy'} fetchPriority={index === 0 ? 'high' : 'auto'} draggable={false} />
      </div>)}
    </div>
    <div className="slide-caption" aria-live={rotating ? 'off' : 'polite'} aria-atomic="true">
      <p>{slides[active].detail}</p><span>{String(active + 1).padStart(2, '0')} / 07</span>
    </div>
    <div className="carousel-controls">
      <button className="round-control" onClick={() => select(active - 1)} aria-label="Previous screenshot"><span aria-hidden="true">‹</span></button>
      <div className="slide-dots" aria-label="Choose a screenshot">{slides.map((slide, index) =>
        <button key={slide.file} className={`dot-button ${active === index ? 'selected' : ''}`} aria-label={`Show ${slide.title}`} aria-current={active === index ? 'true' : undefined} onClick={() => select(index)}><span /></button>
      )}</div>
      <button className="round-control" onClick={() => select(active + 1)} aria-label="Next screenshot"><span aria-hidden="true">›</span></button>
      {!reducedMotion && <button className="round-control play-control" onClick={() => setPlaying(value => !value)} aria-label={playing ? 'Pause slideshow' : 'Play slideshow'}><span aria-hidden="true">{playing ? 'Ⅱ' : '▷'}</span></button>}
    </div>
  </section>;
}

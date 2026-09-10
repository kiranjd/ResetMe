// Keep playback user-initiated and stop audio when the page is hidden.
const video = document.querySelector('video');
document.addEventListener('visibilitychange', () => { if (document.hidden) video?.pause(); });

const notch = document.querySelector('.notch-demo');
const trigger = notch?.querySelector('button');
const preview = document.querySelector('#notch-preview');
const setNotchOpen = open => {
  notch?.classList.toggle('is-open', open);
  trigger?.setAttribute('aria-expanded', String(open));
  preview?.setAttribute('aria-hidden', String(!open));
};
notch?.addEventListener('pointerenter', event => { if (event.pointerType !== 'touch') setNotchOpen(true); });
notch?.addEventListener('pointerleave', () => setNotchOpen(false));
trigger?.addEventListener('click', event => {
  if (event.detail === 0 || !matchMedia('(hover: hover)').matches) {
    setNotchOpen(trigger.getAttribute('aria-expanded') !== 'true');
  }
});
trigger?.addEventListener('blur', () => setNotchOpen(false));
document.addEventListener('keydown', event => { if (event.key === 'Escape') setNotchOpen(false); });
document.addEventListener('pointerdown', event => { if (!notch?.contains(event.target)) setNotchOpen(false); });

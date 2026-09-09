// Keep playback user-initiated and stop audio when the page is hidden.
const video = document.querySelector('video');
document.addEventListener('visibilitychange', () => { if (document.hidden) video?.pause(); });
